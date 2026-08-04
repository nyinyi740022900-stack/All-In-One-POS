-- fulfill_request previously decided "renewal vs brand-new shop" by looking
-- up `licenses` by device_id alone — unreliable now that a shop can have
-- multiple devices (0025_multi_device_licensing.sql), causing renewals to
-- silently mint a phantom new shop instead of extending the real one when
-- the submitting device's id didn't match the shop's stamped device_id.
-- The app already knows its own shop_id when one exists (null only for a
-- genuinely brand-new customer) — carry it so the lookup can be authoritative.

alter table license_requests add column if not exists shop_id text;
