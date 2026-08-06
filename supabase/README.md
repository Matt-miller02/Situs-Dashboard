# Supabase — identity layer (Phase 0)

Project: `cwdtsjccdsviavkbymwa` (hardcoded client-side in `index.html`, using
the anon key — normal, since RLS is the real enforcement boundary).

There's no Supabase CLI project scaffold in this repo yet (all schema
changes so far were made by hand in Supabase Studio). These migrations are
the first tracked ones.

## Applying `0001_identity_layer.sql` and `0002_identity_layer_seed.sql`

Both are additive only — they create `properties`/`units`, a
`resolve_property`/`resolve_property_unit`/`upsert_property` RPC, RLS
policies, and seed the ~15 known apartment-complex properties. They don't
touch any existing table or data.

Run them in order, either:
- Paste into the Supabase Studio SQL editor and run, or
- Once the Supabase MCP server (`.mcp.json`) is authenticated
  (`claude /mcp` in a terminal), ask Claude to apply them via MCP.

## Why the resolver is a Postgres RPC, not a shared JS module

Work Orders, Advertising, Pest Control, and CapEx are each a full HTML
document base64-encoded and injected into an `<iframe srcdoc>` from the
main shell (`index.html`) — they don't share a JS bundle or module system.
A "one resolver used everywhere" can only really mean one thing given that
architecture: the resolver logic lives in the database, and every
dashboard calls it the same way regardless of which iframe it's running in:

```js
const { data } = await sb.rpc('resolve_property_unit', {
  raw_property: 'carr',
  raw_unit: '204',
});
// data[0].property_id, data[0].unit_id
```

## Not done yet (needs live schema access)

Adding `property_id`/`unit_id` columns to the existing tables
(`pest_status`, `ad_listings`, `ad_spend`, `ad_leases`, `ad_vacancy`,
`ad_contracts`, `ad_leasing_funnel`, `market_comps`, `work_orders`,
`capex_actuals`) and backfilling them by running each row's existing
property/unit string through `resolve_property_unit` — this is Phase 2 of
the platform redefinition plan. It needs to see the real, live column list
for each table first (via the Supabase MCP server, once authenticated, or
`\d <table>` in the SQL editor) rather than guessing at columns from
minified upload code. Do this once MCP auth is done.

Also not seeded here: DU Homes' ~16 individual addresses (each is its own
property, confirmed in Advertising's code comments) and any newly-added
properties since this migration was written — add those via
`select upsert_property('...', '[...]'::jsonb, 'region');` as they're
identified, ideally from an admin-only tool once one exists (see Phase 1 /
Foundation #2 in the platform redefinition plan).
