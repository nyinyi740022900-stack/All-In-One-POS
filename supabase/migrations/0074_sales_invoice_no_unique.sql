-- DETECT (not prevent-by-redesign): two devices belonging to the same shop
-- can each be offline at once — the ordinary case this app is built for, not
-- an edge case — and `SalesRepository._nextInvoiceNo` picks the next number
-- by scanning each device's own LOCAL `sales` table. Two devices can
-- therefore mint the identical `INV-yyyyMMdd-NNN` for two different sales;
-- nothing before this migration stopped both rows from landing in Postgres
-- silently, which is exactly the "two receipts, same number" bug a tax audit
-- would flag.
--
-- This does not fix the collision at the source (that needs a product
-- decision — device-suffixed numbers, or renumber-on-conflict — see the
-- 2026-08-27 accounting review) — it only guarantees a collision is loud
-- instead of silent: the losing device's push now fails with 23505, which
-- `sync_force_apply`'s `isConfirmedInvalid` (see that Edge Function's own
-- update alongside this migration) classifies as `rejected_invalid` rather
-- than endlessly-retried `transient`, and `sales` is already a protected
-- "ledger" table in `sync_heal.dart`'s `kNonLedgerSyncTables` allowlist, so
-- the row is never silently dropped — it quarantines and surfaces on the
-- owner's Settings → Sync issues screen instead.
--
-- Partial (WHERE NOT is_deleted): a soft-deleted sale must not permanently
-- block reusing its invoice number.
create unique index if not exists sales_shop_invoice_no_key
  on sales (shop_id, invoice_no)
  where not is_deleted;
