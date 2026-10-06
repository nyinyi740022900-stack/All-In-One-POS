-- MMQR (Myan Myan Pay) rides the existing checkout table rather than a table of
-- its own, so 0097's one-open-checkout-per-shop lock holds BETWEEN providers: a
-- shop cannot hold a live Lemon Squeezy subscription checkout and an MMQR order
-- at the same time and pay both. A one-off QR bought alongside a recurring
-- subscription is not "two months", it is a subscription the owner forgot plus
-- a refund conversation.
alter table billing_checkouts
  add column provider text not null default 'lemonsqueezy'
    check (provider in ('lemonsqueezy','mmpay')),
  add column provider_order_id text,
  add column amount int,
  add column currency text;

-- One order id per provider, forever. With shop_subscription_payments keyed on
-- the payment id this is the second of two independent idempotency layers, so
-- MMPay's documented duplicate callback deliveries grant nothing twice.
create unique index billing_checkouts_provider_order
  on billing_checkouts(provider, provider_order_id)
  where provider_order_id is not null;

-- 0069 added these in anticipation of this feature under the old key-minting
-- licence model. MMQR writes to billing_checkouts instead, so leaving them is
-- leaving two permanently empty columns wearing the name of a live payment
-- path — the kind of thing that costs an hour the next time someone debugs a
-- payment. payment_status stays; it is live.
alter table license_requests
  drop column if exists mmpay_order_id,
  drop column if exists mmpay_expires_at;

-- Same shape and same lock order as reserve_gateway_checkout, so the Edge
-- Function's two-attempt loop needs no new branch. The price is derived here
-- and never taken from the client: these are the same two literals
-- fulfill_account_payment checks, so Premium's price lives in exactly one
-- place in SQL.
create function reserve_mmpay_checkout(p_shop_id text,p_owner_user_id uuid,p_months int)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare s shop_subscriptions; c billing_checkouts; open_count int; want_amount int;
begin
  select * into s from shop_subscriptions where shop_id=p_shop_id for update;
  if not found or s.is_archived or account_shop_role(p_owner_user_id,p_shop_id) is distinct from 'owner' then
    raise exception 'verified_owner_required';
  end if;
  if p_months is null or p_months not in (1,12) then raise exception 'invalid_checkout'; end if;
  want_amount := case p_months when 12 then 200000 else 20000 end;
  select count(*) into open_count from billing_checkouts where shop_id=p_shop_id and closed_at is null;
  if open_count>1 then return jsonb_build_object('reserved',false,'error','billing_review_required'); end if;
  select * into c from billing_checkouts where shop_id=p_shop_id and closed_at is null;
  if found then
    if c.owner_user_id is distinct from p_owner_user_id then
      return jsonb_build_object('reserved',false,'error','billing_review_required');
    end if;
    -- May belong to either provider. The caller decides what to do with it:
    -- a lemonsqueezy row becomes subscription_already_exists, an mmpay row is
    -- re-queried against MMPay before anything is closed.
    return jsonb_build_object('reserved',false,'checkout',to_jsonb(c));
  end if;
  -- variant_id is not null and has no meaning for a one-off QR. A readable
  -- sentinel beats widening a column the Lemon Squeezy validation relies on.
  insert into billing_checkouts(id,shop_id,owner_user_id,variant_id,months,provider,amount,currency,checkout_expires_at)
    values(gen_random_uuid(),p_shop_id,p_owner_user_id,'mmpay:'||p_months,p_months,'mmpay',want_amount,'MMK',
           now()+interval '15 minutes') returning * into c;
  return jsonb_build_object('reserved',true,'checkout',to_jsonb(c));
end $$;

-- Closing an MMQR row. Mirrors close_gateway_checkout's rule that a payable
-- artifact may only be abandoned on an API-verified terminal state: pass the
-- order id that was verified dead, or null only when no order was ever issued.
create function close_mmpay_checkout(p_checkout_id uuid,p_order_id text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare c billing_checkouts; shop text;
begin
  select shop_id into shop from billing_checkouts where id=p_checkout_id;
  perform 1 from shop_subscriptions where shop_id=shop for update;
  select * into c from billing_checkouts where id=p_checkout_id for update;
  if not found then raise exception 'checkout_not_found'; end if;
  if c.provider is distinct from 'mmpay' then raise exception 'checkout_provider_mismatch'; end if;
  -- Covers both directions: an issued order may not be closed as if it never
  -- existed, and a stale order id may not close someone else's row.
  if c.provider_order_id is distinct from p_order_id then raise exception 'checkout_order_mismatch'; end if;
  update billing_checkouts set closed_at=coalesce(closed_at,now()) where id=p_checkout_id;
  return jsonb_build_object('ok',true);
end $$;

-- Never writes subscription_id: an MMQR payment buys a term, it does not start
-- a recurring agreement. Same lock order as reservation and closure.
create function fulfill_mmpay_payment(p_checkout_id uuid,p_order_id text,p_amount int)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare c billing_checkouts; result jsonb; shop text; want_amount int;
begin
  if nullif(p_order_id,'') is null then raise exception 'payment_identity_required'; end if;
  select shop_id into shop from billing_checkouts where id=p_checkout_id;
  perform 1 from shop_subscriptions where shop_id=shop for update;
  select * into c from billing_checkouts where id=p_checkout_id for update;
  if not found then raise exception 'checkout_not_found'; end if;
  if c.provider is distinct from 'mmpay' then raise exception 'checkout_provider_mismatch'; end if;
  if c.provider_order_id is not null and c.provider_order_id <> p_order_id then
    raise exception 'checkout_order_mismatch';
  end if;
  if account_shop_role(c.owner_user_id,c.shop_id) is distinct from 'owner' then
    raise exception 'verified_owner_required';
  end if;
  -- Re-derived from the stored term rather than compared against the stored
  -- amount, so a tampered reservation row cannot buy a year at a month's price.
  want_amount := case c.months when 12 then 200000 else 20000 end;
  if p_amount is distinct from want_amount then raise exception 'payment_amount_mismatch'; end if;
  update billing_checkouts
    set provider_order_id=p_order_id, closed_at=coalesce(closed_at,now())
    where id=c.id;
  result := renew_shop_subscription(c.shop_id,c.months,'mmpay:order:'||p_order_id);
  return result || jsonb_build_object('ok',true);
end $$;

revoke all on function reserve_mmpay_checkout(text,uuid,int),close_mmpay_checkout(uuid,text),
  fulfill_mmpay_payment(uuid,text,int) from public,anon,authenticated;
grant execute on function reserve_mmpay_checkout(text,uuid,int),close_mmpay_checkout(uuid,text),
  fulfill_mmpay_payment(uuid,text,int) to service_role;
