-- Admin / payment extend used to add months and flip status to active, but
-- left `plan` untouched. Signup and self-serve trials mint `plan = 'trial'`,
-- so a paid extension still showed in the app as "Free trial" (e.g. expiry
-- pushed to 2027 while the label stayed trial).
--
-- renew_license now promotes trial/free → a paid plan. 12+ months becomes
-- yearly; otherwise monthly. An already-paid yearly shop is never demoted
-- by a shorter top-up. Signature stays (text, int) so Edge Function callers
-- need no change.
--
-- Same function is used by fulfill_request (website payment) and referral
-- credit — those paid paths also stop leaving the shop labelled as a trial.

create or replace function renew_license(
  p_key    text,
  p_months int
) returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shop_id text;
  v_base    timestamptz;
  v_expiry  timestamptz;
  v_paid    text;
begin
  select shop_id into v_shop_id from licenses where key = p_key;
  if v_shop_id is null then
    raise exception 'license key % not found', p_key;
  end if;

  select greatest(max(expires_at), now()) into v_base
  from licenses
  where shop_id = v_shop_id and is_deleted = false;

  v_expiry := v_base + (p_months || ' months')::interval;
  v_paid := case when p_months >= 12 then 'yearly' else 'monthly' end;

  update licenses
  set expires_at = v_expiry,
      status     = 'active',
      plan       = case
                     when plan in ('trial', 'free') then v_paid
                     when plan = 'monthly' and p_months >= 12 then 'yearly'
                     else plan
                   end,
      updated_at = now()
  where shop_id = v_shop_id and is_deleted = false;

  return v_expiry;
end;
$$;

revoke execute on function renew_license(text, int) from public;

-- Shops already extended while still labelled trial. A genuine signup /
-- self-serve trial is 2 months (~60 days). More than 70 days remaining
-- means Support (or a payment) already added time — relabel as paid.
update licenses
set plan = case
             when expires_at > now() + interval '10 months' then 'yearly'
             else 'monthly'
           end,
    updated_at = now()
where plan = 'trial'
  and is_deleted = false
  and expires_at > now() + interval '70 days';
