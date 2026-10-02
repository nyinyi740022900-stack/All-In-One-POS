-- Renewal extends from the old expiry while the shop is inside the grace
-- window, instead of from now().
--
-- 0060's `greatest(max(expires_at), now())` made every grace day free: a
-- shop that paid on day 13 of grace got its months counted from that day,
-- so the 13 days it kept using Premium were never billed. With grace raised
-- from 7 to 14 days (GRACE_DAYS in functions/activate, kLicenseGraceDays in
-- lib/features/license/license_status.dart — keep all three in step) that
-- gap would have been up to two free weeks per renewal.
--
-- Now: still active or within 14 days of expiry -> base is the old expiry
-- (grace is time to pay, not free time). Lapsed beyond grace, or no expiry
-- at all -> base is now(), so a returning shop is not billed for the months
-- it was actually locked out of Premium.
--
-- Body otherwise identical to 0060 (plan promotion rules unchanged). Shared
-- by every renewal path: admin extend_license, fulfill_request, and the
-- Lemon Squeezy webhook.

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
  v_current timestamptz;
  v_base    timestamptz;
  v_expiry  timestamptz;
  v_paid    text;
begin
  select shop_id into v_shop_id from licenses where key = p_key;
  if v_shop_id is null then
    raise exception 'license key % not found', p_key;
  end if;

  select max(expires_at) into v_current
  from licenses
  where shop_id = v_shop_id and is_deleted = false;

  v_base := case
              when v_current is not null
                   and v_current >= now() - interval '14 days'
                then v_current
              else now()
            end;

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
