-- Closes a check-then-insert race in `create_branch` (activate/index.ts):
-- `ownerActiveTrialBranchCount` (a SELECT) and the new trial license's
-- INSERT were two separate statements with no constraint tying them
-- together, so two concurrent create_branch calls for the same owner
-- (a double-tap under a slow connection) could both read
-- activeTrials < MAX_ACTIVE_TRIAL_BRANCHES_PER_OWNER and both insert,
-- giving one owner two concurrent free trial branches instead of the
-- intended cap of one. Minor abuse surface (an extra free trial, not lost
-- revenue), but easy to close properly with a single atomic RPC.
--
-- pg_advisory_xact_lock serializes concurrent calls for the SAME owner
-- (the lock releases automatically at transaction end) without needing a
-- new table or a unique constraint expressing a cross-table aggregate rule
-- ("at most N active trials among the shops this owner has linked").
create or replace function create_trial_branch(
  p_owner_user_id uuid,
  p_shop_id       text,
  p_shop_name     text,
  p_key           text,
  p_months        int,
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
    (shop_id, shop_name, key, plan, status, expires_at, activated_at,
     referral_code, tier)
  values
    (p_shop_id, p_shop_name, p_key, 'trial', 'active',
     now() + (p_months || ' months')::interval, now(),
     gen_referral_code(), 'online');

  insert into org_branches (owner_user_id, shop_id, label)
  values (p_owner_user_id, p_shop_id, p_shop_name)
  on conflict (owner_user_id, shop_id) do update set label = excluded.label;

  return query select p_shop_id, false;
end;
$$;
revoke execute on function create_trial_branch(uuid, text, text, text, int, int) from public;
