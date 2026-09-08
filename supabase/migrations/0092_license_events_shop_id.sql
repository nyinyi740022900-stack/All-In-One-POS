-- `license_events` is the console's only audit surface, and it could not
-- record WHICH shop an event belonged to unless the event happened to carry a
-- licence key or a device id.
--
-- That was already a live gap before this migration: `set_device_allowance`
-- logs `action = 'device_allowance'` with key and device both null, and the
-- History tab renders that row as `Extra devices granted · <months> · <shop_id>`
-- — reading a column that did not exist, so every one of those rows has always
-- shown a bare "—" where the shop should be.
--
-- Archiving a shop makes the gap unacceptable rather than untidy: "someone
-- revoked a shop's licence" is exactly the event you need to be able to trace
-- back to a shop, and an archive carries no key and no device either.
--
-- Nullable, no backfill: existing rows genuinely do not know their shop, and
-- inventing one would be worse than the honest null the History tab already
-- renders as "—".
alter table license_events
  add column if not exists shop_id text;

create index if not exists idx_license_events_shop
  on license_events (shop_id, created_at desc);
