-- Phase 0 seed data: known properties, consolidated from the three
-- hand-written cleanup tables already living in the codebase today:
--   - pest.html's cleanupName() function
--   - advertising.html's PROPERTY_ALIASES / PROPERTY_REGION / PORTFOLIO_PREFIXES
--   - capex.html's `properties` array (aliases + legal/entity names)
--
-- Naming convention: short display name (e.g. "Carr Street Flats"), per
-- Matt — matches Advertising's existing style and what people actually
-- call these day to day, not the legal-entity names CapEx uses internally.
--
-- DU Homes is deliberately NOT seeded here. Advertising's code already
-- confirmed (comment at PORTFOLIO_PREFIXES) that each "DU Homes (address)"
-- is a genuinely separate single-family rental property, not one building —
-- so it's ~16 distinct properties, not one row. The actual addresses only
-- exist in already-uploaded data, not in any hardcoded table, so they
-- should be created via upsert_property(...) during the Phase 2 backfill
-- (one per distinct address encountered), not guessed here.
--
-- "Arizona" is included per Matt's confirmation it's a real property not
-- yet tracked by Pest Control or CapEx.

select upsert_property('Aspen Leaf', '["aspen leaf","aspenleaf","aspen"]'::jsonb, 'Arvada');
select upsert_property('Carr Street Flats', '["carr","carr street","carr st","carr street flats"]'::jsonb, 'Lakewood');
select upsert_property('Lampliter', '["lampliter","lamplighter"]'::jsonb, 'Lakewood');
select upsert_property('Barcelona', '["barcelona"]'::jsonb, 'Lakewood');
select upsert_property('McKenzie', '["mckenzie","mackenzie"]'::jsonb, 'Lakewood');
select upsert_property('Zephyr', '["zephyr"]'::jsonb, 'Lakewood');
select upsert_property('Dahlia', '["dahlia"]'::jsonb, 'Rose');
select upsert_property('Mayor', '["mayor","mayor apartments"]'::jsonb, 'Rose');
select upsert_property('Cottonwoods', '["cottonwoods","cottonwood","5100 w 8th","5100 w. 8th ave","5100 w 8th ave"]'::jsonb, null);
select upsert_property('Olde Town Terrace', '["olde town","old town","oldetown","olde town terrace","old town terrace","old towne terrace"]'::jsonb, null);
select upsert_property('Bryant Gardens', '["bryant gardens"]'::jsonb, null);
select upsert_property('Lowry Flats', '["lowry flats","lowry"]'::jsonb, null);
select upsert_property('Alton Apartments', '["alton"]'::jsonb, null);
select upsert_property('Dexter Apartments', '["dexter"]'::jsonb, null);
select upsert_property('Arizona', '["arizona"]'::jsonb, null);
