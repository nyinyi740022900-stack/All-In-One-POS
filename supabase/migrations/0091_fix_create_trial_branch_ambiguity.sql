-- Fixes a PRE-EXISTING bug in `create_trial_branch` (shipped in 0089, found
-- while smoke-testing 0090's rewrite of the same function): adding a branch
-- has been failing outright with
--
--   ERROR 42702: column reference "shop_id" is ambiguous
--
-- The function is declared `returns table(shop_id text, blocked boolean)`,
-- which puts a PL/pgSQL variable named `shop_id` in scope for the whole
-- body. The `on conflict (owner_user_id, shop_id)` target below then can't
-- be resolved — Postgres won't guess between that variable and
-- `org_branches.shop_id`, and PL/pgSQL's default `variable_conflict` is
-- `error`. It raises at execution time, so `activate`'s `create_branch`
-- action turned every "add a branch" attempt into a 500 (the caller maps any
-- RPC error to `server_error`). Nothing about referrals caused it: the same
-- failure reproduces on a bare probe function with only the RETURNS TABLE
-- shape and the ON CONFLICT clause, and 0090 reproduced 0089's body
-- verbatim.
--
-- `#variable_conflict use_column` resolves an ambiguous reference to the
-- column, which is what the ON CONFLICT target means here. Everything else
-- in the body is either qualified (`b.shop_id`, `l.shop_id`) or a `p_`/`v_`
-- prefixed identifier that can't collide, so this changes nothing else. The
-- OUT column stays named `shop_id` on purpose — `handleCreateBranch` reads
-- `result?.shop_id` by name.
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
#variable_conflict use_column
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
revoke execute on function create_trial_branch(uuid, text, text, text, int, int) from public;
