-- Phase 0: shared identity layer (properties & units)
--
-- Problem this solves: today Pest Control, Advertising, and CapEx each
-- maintain their own hand-written property-name cleanup table, and they
-- disagree — e.g. Pest Control resolves "carr" to "Carr Street" while
-- Advertising resolves it to "Carr Street Flats". This creates one
-- canonical properties table plus a resolver every dashboard can call via
-- RPC (sb.rpc(...)) instead of maintaining its own alias list. This
-- migration is purely additive: it does not touch any existing table.
--
-- Apply via the Supabase SQL editor, or via the Supabase MCP server once
-- authenticated (see supabase/README.md).

create table if not exists properties (
  id uuid primary key default gen_random_uuid(),
  canonical_name text not null unique,
  aliases jsonb not null default '[]'::jsonb,
  region text,
  created_at timestamptz not null default now()
);

create table if not exists units (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references properties(id) on delete cascade,
  unit_label text not null,
  created_at timestamptz not null default now(),
  unique (property_id, unit_label)
);

create index if not exists units_property_id_idx on units (property_id);
create index if not exists properties_aliases_gin_idx on properties using gin (aliases);

-- ===== Normalization + resolver =====
-- Lowercases, strips punctuation, collapses whitespace — mirrors what each
-- dashboard's private cleanup table did by hand (.toLowerCase(), trimming a
-- trailing period, etc.), but in one place.
create or replace function normalize_property_text(raw text)
returns text
language sql
immutable
as $$
  select trim(regexp_replace(lower(coalesce(raw, '')), '[^a-z0-9]+', ' ', 'g'));
$$;

-- The one resolver every dashboard's upload parser / chat updater calls
-- instead of maintaining its own aliases list. Matches against
-- canonical_name first, then against any entry in aliases. Returns null on
-- no match — callers decide whether "no match" means "ask a human" or
-- "this is a new property, create it" (see upsert_property below).
create or replace function resolve_property(raw_text text)
returns uuid
language sql
stable
as $$
  select p.id
  from properties p
  where normalize_property_text(p.canonical_name) = normalize_property_text(raw_text)
     or exists (
       select 1
       from jsonb_array_elements_text(p.aliases) a
       where normalize_property_text(a) = normalize_property_text(raw_text)
     )
  limit 1;
$$;

create or replace function resolve_property_unit(raw_property text, raw_unit text)
returns table (property_id uuid, unit_id uuid)
language sql
stable
as $$
  with prop as (select resolve_property(raw_property) as id)
  select
    prop.id,
    (
      select u.id from units u
      where u.property_id = prop.id
        and normalize_property_text(u.unit_label) = normalize_property_text(raw_unit)
      limit 1
    )
  from prop;
$$;

-- Explicit, admin-only "this raw text is a genuinely new property" path —
-- deliberately separate from resolve_property so no dashboard can silently
-- fabricate a new property just because a name didn't match anything.
create or replace function upsert_property(p_canonical_name text, p_aliases jsonb default '[]'::jsonb, p_region text default null)
returns uuid
language plpgsql
security invoker
as $$
declare
  result_id uuid;
begin
  insert into properties (canonical_name, aliases, region)
  values (p_canonical_name, p_aliases, p_region)
  on conflict (canonical_name) do update
    set aliases = properties.aliases || excluded.aliases,
        region = coalesce(excluded.region, properties.region)
  returning id into result_id;
  return result_id;
end;
$$;

-- ===== RLS =====
-- Every signed-in user can resolve/read property identity (every dashboard
-- needs this to display data). Writes are restricted to admins, matching
-- the existing admin_users pattern used elsewhere in this app.
alter table properties enable row level security;
alter table units enable row level security;

create policy properties_select_authenticated on properties
  for select to authenticated
  using (true);

create policy properties_write_admin on properties
  for all to authenticated
  using (exists (select 1 from admin_users a where a.id = auth.uid()))
  with check (exists (select 1 from admin_users a where a.id = auth.uid()));

create policy units_select_authenticated on units
  for select to authenticated
  using (true);

create policy units_write_admin on units
  for all to authenticated
  using (exists (select 1 from admin_users a where a.id = auth.uid()))
  with check (exists (select 1 from admin_users a where a.id = auth.uid()));

grant execute on function resolve_property(text) to authenticated;
grant execute on function resolve_property_unit(text, text) to authenticated;
grant execute on function upsert_property(text, jsonb, text) to authenticated;
