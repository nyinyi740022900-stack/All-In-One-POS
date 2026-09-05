-- Remove the Refer & earn programme end to end (owner decision, 2026-09-05).
--
-- The feature shipped in 0013/0014 and was never used in production: every
-- one of `referrals`, `referral_commissions` and `referral_redemptions` was
-- empty at removal time, and no `license_requests` row ever carried a
-- `referred_by_code`. The only real data was the auto-generated
-- `licenses.referral_code` handed to each licence, which nothing consumed
-- once the app-side feature was deleted.
--
-- ORDER MATTERS. `create_license` and `create_trial_branch` both call
-- `gen_referral_code()` and write `licenses.referral_code`, so they are
-- redefined FIRST — dropping the function or column ahead of that would
-- break licence minting (and therefore every activation/renewal) outright.
-- The `activate` and `admin` Edge Functions that also called
-- `gen_referral_code` are deployed before this migration runs.

-- ---------------------------------------------------------------------------
-- 1. Redefine the two licence-minting functions without referral_code.
--    Bodies are otherwise byte-for-byte what 0013 / 0089 left in place.
-- ---------------------------------------------------------------------------
create or replace function create_license(
  p_shop_id   text,
  p_plan      text default 'monthly',
  p_months    int  default 1,
  p_shop_name text default null
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text;
begin
  v_key := 'MMPOS-'
    || upper(substr(md5(gen_random_uuid()::text), 1, 4)) || '-'
    || upper(substr(md5(gen_random_uuid()::text), 1, 4)) || '-'
    || upper(substr(md5(gen_random_uuid()::text), 1, 4));

  insert into licenses
    (shop_id, shop_name, key, plan, status, expires_at, activated_at)
  values
    (p_shop_id, p_shop_name, v_key, p_plan, 'active',
     now() + (p_months || ' months')::interval, null);

  return v_key;
end;
$$;
revoke execute on function create_license(text, text, int, text) from public;

create or replace function create_trial_branch(
  p_owner_user_id     uuid,
  p_shop_id           text,
  p_shop_name         text,
  p_key               text,
  p_months            int,
  p_max_active_trials int
) returns table(shop_id text, blocked boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_active_trials int;
begin
  perform pg_advisory_xact_lock(hashtext(p_owner_user_id::text));

  select count(*) into v_active_trials
  from licenses l
  join org_branches b on b.shop_id = l.shop_id
  where b.owner_user_id = p_owner_user_id
    and l.plan = 'trial'
    and l.status = 'active'
    and l.expires_at > now();

  if v_active_trials >= p_max_active_trials then
    return query select null::text, true;
    return;
  end if;

  insert into licenses
    (shop_id, shop_name, key, plan, status, expires_at, activated_at, tier)
  values
    (p_shop_id, p_shop_name, p_key, 'trial', 'active',
     now() + (p_months || ' months')::interval, now(), 'online');

  insert into org_branches (owner_user_id, shop_id, label)
  values (p_owner_user_id, p_shop_id, p_shop_name)
  on conflict (owner_user_id, shop_id) do update set label = excluded.label;

  return query select p_shop_id, false;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Drop the referral-only functions (nothing calls them after step 1).
-- ---------------------------------------------------------------------------
drop function if exists redeem_referral_balance();
drop function if exists apply_referral_credit_for(text);
drop function if exists my_referral_balance();
drop function if exists gen_referral_code();

-- ---------------------------------------------------------------------------
-- 3. Drop the ledgers. All three were empty; their RLS policies and indexes
--    go with the tables.
-- ---------------------------------------------------------------------------
drop table if exists referral_commissions;
drop table if exists referral_redemptions;
drop table if exists referrals;

-- ---------------------------------------------------------------------------
-- 4. Drop the columns (the unique index on referral_code goes with it).
-- ---------------------------------------------------------------------------
alter table licenses         drop column if exists referral_code;
alter table license_requests drop column if exists referred_by_code;

-- ---------------------------------------------------------------------------
-- 5. Retire the config knobs the admin Config tab no longer renders.
-- ---------------------------------------------------------------------------
delete from app_config where key in ('referral.enabled', 'referral.rate');
