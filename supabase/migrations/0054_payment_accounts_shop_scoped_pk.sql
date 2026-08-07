-- payment_accounts.id is a *per-shop* code (e.g. 'kbzpay'), reused so
-- Payments.method / Sales.payment_method keep resolving without migration.
-- The original PK on id alone made those codes *globally* unique across
-- every tenant — the first shop to sync owned 'kbzpay', and every other
-- shop's upsert hit RLS 42501 ("new row violates row-level security")
-- and poisoned the outbox (Sync issues / blocked branch switch).
-- Composite PK (shop_id, id) matches the multi-branch model.

alter table payment_accounts drop constraint if exists payment_accounts_pkey;
alter table payment_accounts add primary key (shop_id, id);
