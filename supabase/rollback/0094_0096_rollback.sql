-- Undo the account-Premium cutover and checkout guard (0094 through 0097).
--
-- Safe to run because those three migrations add rather than destroy: no table,
-- column or row is dropped, and the policies they drop are recreated in the same
-- file. `licenses` and every other 0093 table keep their rows, so rolling back
-- means removing what was added and putting the changed policies back to their
-- pre-cutover definitions.
--
-- The object lists below were derived by diffing a database stopped at 0093
-- against one carrying 0096, and `migration_rollback_test.py` fails if this
-- script does not reproduce the 0093 schema exactly (tables, columns, function
-- signatures and policy definitions). Re-derive both if you add a migration.
--
-- This does NOT roll back the client. Deploy the pre-cutover Edge Functions,
-- web targets and app alongside it, or the new code calls functions that are
-- gone. Take a dump first and run it in a maintenance window.
--
-- Afterwards, clear the CLI's ledger so a later `db push` reapplies them:
--   delete from supabase_migrations.schema_migrations
--    where version in ('0094', '0095', '0096', '0097');

begin;

-- Tables they added, before the functions: the policies on these tables call
-- those functions, so dropping the functions first is refused.  Nothing from
-- 0093 references these tables, so the cascade only reaches the new objects'
-- own dependants.
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
      'reserve_gateway_checkout', 'close_gateway_checkout')
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
\ir ../migrations/0010_license_requests.sql
\ir ../migrations/0042_org_branches.sql
\ir ../migrations/0066_scoped_payment_proofs.sql
\ir ../migrations/0068_proof_folder_shop_id_shape.sql

commit;
