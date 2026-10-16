-- Undo the account-Premium cutover, checkout guard and MMQR schema (0094
-- through 0098).
--
-- These migrations add rather than destroy, with one exception: 0098 drops the
-- two unused `license_requests.mmpay_*` columns 0069 had added, and this script
-- restores them by re-running 0069. No row is dropped anywhere, and the
-- policies these migrations drop are recreated in the same file. `licenses`
-- and every other 0093 table keep their rows, so rolling back means removing
-- what was added and putting the changed policies back to their pre-cutover
-- definitions.
--
-- The object lists below were derived by diffing a database stopped at 0093
-- against one carrying 0098, and `migration_rollback_test.py` fails if this
-- script does not reproduce the 0093 schema exactly (tables, columns, function
-- signatures and policy definitions). Re-derive both if you add a migration.
--
-- This does NOT roll back the client. Deploy the pre-cutover Edge Functions,
-- web targets and app alongside it, or the new code calls functions that are
-- gone. Take a dump first and run it in a maintenance window.
--
-- Afterwards, clear the CLI's ledger so a later `db push` reapplies them:
--   delete from supabase_migrations.schema_migrations
--    where version in ('0094', '0095', '0096', '0097', '0098');

begin;

-- 0102's owner-only write policies call auth_is_shop_owner(), which calls
-- account_shop_role(); drop them before the functions go, and put back the
-- pre-0102 shop-wide policies below by re-running 0026/0072.
drop policy if exists owner_insert on staff_permissions;
drop policy if exists owner_update on staff_permissions;
drop policy if exists owner_delete on staff_permissions;
drop policy if exists owner_insert on staff_members;
drop policy if exists owner_update on staff_members;
drop policy if exists owner_delete on staff_members;
drop function if exists auth_is_shop_owner();
drop function if exists account_legacy_product_files(uuid);
drop function if exists release_deleted_account_storage(uuid);

-- Tables they added, before the functions: the policies on these tables call
-- those functions, so dropping the functions first is refused.  Nothing from
-- 0093 references these tables, so the cascade only reaches the new objects'
-- own dependants.
-- 0101's bookkeeping. It references shop_subscriptions, so it has to go
-- before that table does.
drop table if exists shop_expiry_notices cascade;
drop table if exists social_reauth_proofs cascade;
drop table if exists billing_checkouts cascade;
drop table if exists shop_subscription_payments cascade;
drop table if exists account_trial_claims cascade;
drop table if exists shop_devices cascade;
drop table if exists shop_subscriptions cascade;

-- Functions the three migrations added, dropped by name so a changed argument
-- list cannot leave one behind. `cascade` is needed because 0095 rewrote
-- proof_auth_read on storage.objects to call can_read_account_shop; that policy
-- goes with it and is restored from 0066/0068 at the end of this script.
do $$
declare fn record;
begin
  for fn in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'account_shop_role', 'archive_shop_subscription', 'attach_legacy_shop_owner',
      'can_read_account_shop', 'consume_social_reauth_proof', 'create_account_shop',
      'create_social_account_shop', 'fulfill_account_payment', 'fulfill_gateway_payment',
      'register_shop_device', 'reject_account_payment', 'release_shop_device',
      'renew_shop_subscription', 'resolve_social_account', 'start_account_trial',
      'reserve_gateway_checkout', 'close_gateway_checkout',
      'reserve_mmpay_checkout', 'close_mmpay_checkout', 'fulfill_mmpay_payment',
      'claim_expiry_notices', 'release_expiry_notice', 'expiry_days_left')
  loop
    execute format('drop function %s cascade', fn.sig);
  end loop;
end $$;

-- Columns 0095 added to an existing table.
alter table license_requests drop column if exists owner_user_id;
alter table license_requests drop column if exists fulfilled_expires_at;

-- A policy 0095 introduced on the storage bucket; 0093 had no equivalent.
drop policy if exists proof_account_upload on storage.objects;

-- Restore the policies the cutover replaced by re-running the migrations that
-- define them, rather than restating them here where they could drift. Each of
-- these files drops before it creates, so re-running is idempotent:
--   0010 — lr_insert, which 0095 dropped when renewal moved behind an
--          authenticated Edge Function
--   0042 — org_branches_owner, which 0094 narrowed from `for all` to `for
--          select` once branch writes moved behind the authority RPCs
--   0066/0068 — the payment-proof read/upload policies 0095 reshaped
--   0069 — the two license_requests.mmpay_* columns 0098 dropped; every
--          statement in that file is `if not exists`, so it restores the
--          columns without disturbing the invoice numbers already backfilled
\ir ../migrations/0010_license_requests.sql
\ir ../migrations/0042_org_branches.sql
\ir ../migrations/0066_scoped_payment_proofs.sql
\ir ../migrations/0068_proof_folder_shop_id_shape.sql
\ir ../migrations/0069_license_request_receipt.sql
--   0026/0072 — staff_members / staff_permissions `shop_isolation` for all
--          operations, which 0102 narrowed to reads plus owner-only writes
\ir ../migrations/0026_staff_members.sql
\ir ../migrations/0072_staff_permissions.sql

commit;
