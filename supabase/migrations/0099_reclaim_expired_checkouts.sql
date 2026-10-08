-- An abandoned card checkout locked its shop out of /renew permanently.
--
-- 0097 counts open rows by `closed_at is null` alone and never looks at
-- `checkout_expires_at`, on the stated grounds that an unpaid checkout must
-- never be inferred from its age. That rule is right and stays. What was
-- missing is any way back: a reservation whose owner closed the Lemon Squeezy
-- tab has no subscription to re-query, so the Edge Function's recovery branch
-- never runs and every later attempt returns checkout_in_progress forever.
-- Three such rows were closed by hand in production on 2026-10-08.
--
-- The way out is reuse, not closure. Closing is what would be dangerous:
-- `fulfill_gateway_payment` raises `duplicate_subscription` for a closed row
-- with no subscription_id, so a late signed invoice against a closed
-- reservation would be refused — the owner pays and gets nothing. Handing the
-- same row back instead keeps exactly one reservation per shop, keeps it open
-- and fulfilable, and lets the function issue a fresh hosted checkout against
-- the same `custom.billing_id`. Whichever invoice arrives, early or late,
-- credits the same row, and `shop_subscription_payments` keyed on the invoice
-- id stops a duplicate granting twice.
--
-- Reuse requires the reservation to be past the expiry we set on Lemon
-- Squeezy's own checkout object (the POST /v1/checkouts body sends
-- `expires_at: checkout_expires_at`), plus a quarter-hour margin for an
-- invoice paid in the last seconds before it. Past that the old hosted page
-- cannot take a payment at all, so reissuing cannot produce two payable carts.
--
-- Only when the request matches the reservation's own variant and term. A
-- reused row keeps its variant_id, and `fulfill_gateway_payment` rejects an
-- invoice whose variant differs — so quietly repurposing the row for a
-- different plan is what would lose a late payment.
--
-- Deliberately NOT applied to `mmpay` rows: MyanMyanPay publishes no TTL, the
-- fifteen-minute window on an MMQR is ours alone, and a QR issued an hour ago
-- may still be sitting payable in someone's banking app. Those are resolved
-- the only way they safely can be, by asking MyanMyanPay, which the MMQR
-- handler already does before closing anything.
create or replace function reserve_gateway_checkout(p_shop_id text,p_owner_user_id uuid,p_variant_id text,p_months int)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare s shop_subscriptions; c billing_checkouts; open_count int;
begin
  select * into s from shop_subscriptions where shop_id=p_shop_id for update;
  if not found or s.is_archived or account_shop_role(p_owner_user_id,p_shop_id) is distinct from 'owner' then
    raise exception 'verified_owner_required';
  end if;
  if p_months is null or p_months not in (1,12) or p_variant_id is null or p_variant_id !~ '^[1-9][0-9]*$' then
    raise exception 'invalid_checkout';
  end if;
  select count(*) into open_count from billing_checkouts where shop_id=p_shop_id and closed_at is null;
  if open_count>1 then return jsonb_build_object('reserved',false,'error','billing_review_required'); end if;
  select * into c from billing_checkouts where shop_id=p_shop_id and closed_at is null;
  if found then
    if c.owner_user_id is distinct from p_owner_user_id then
      return jsonb_build_object('reserved',false,'error','billing_review_required');
    end if;
    if c.provider = 'lemonsqueezy'
       and c.subscription_id is null
       and c.variant_id = p_variant_id
       and c.months = p_months
       and c.checkout_expires_at is not null
       and c.checkout_expires_at < now() - interval '15 minutes'
    then
      -- Same row, new window, no issued URL. The caller treats this exactly
      -- as a fresh reservation and posts a new hosted checkout for this id.
      update billing_checkouts
         set checkout_expires_at = now()+interval '1 hour', checkout_url = null
       where id = c.id returning * into c;
      return jsonb_build_object('reserved',true,'reused',true,'checkout',to_jsonb(c));
    end if;
    return jsonb_build_object('reserved',false,'checkout',to_jsonb(c));
  end if;
  insert into billing_checkouts(id,shop_id,owner_user_id,variant_id,months,checkout_expires_at)
    values(gen_random_uuid(),p_shop_id,p_owner_user_id,p_variant_id,p_months,now()+interval '1 hour') returning * into c;
  return jsonb_build_object('reserved',true,'checkout',to_jsonb(c));
end $$;
