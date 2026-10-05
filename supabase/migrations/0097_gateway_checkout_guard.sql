-- Serialize card checkout creation per shop. Never infer an unpaid checkout
-- from its age: the customer may have paid and its signed invoice be delayed.
alter table billing_checkouts
  add column checkout_url text,
  add column checkout_expires_at timestamptz,
  add column closed_at timestamptz;
create index billing_checkouts_open_shop on billing_checkouts(shop_id) where closed_at is null;

create function reserve_gateway_checkout(p_shop_id text,p_owner_user_id uuid,p_variant_id text,p_months int)
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
    return jsonb_build_object('reserved',false,'checkout',to_jsonb(c));
  end if;
  insert into billing_checkouts(id,shop_id,owner_user_id,variant_id,months,checkout_expires_at)
    values(gen_random_uuid(),p_shop_id,p_owner_user_id,p_variant_id,p_months,now()+interval '1 hour') returning * into c;
  return jsonb_build_object('reserved',true,'checkout',to_jsonb(c));
end $$;

-- Called only after a definitive processor rejection (no URL issued), or an
-- API-verified expired subscription. Timeouts/unknown outcomes never call this.
create function close_gateway_checkout(p_checkout_id uuid,p_subscription_id text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare c billing_checkouts; shop text;
begin
  select shop_id into shop from billing_checkouts where id=p_checkout_id;
  perform 1 from shop_subscriptions where shop_id=shop for update;
  select * into c from billing_checkouts where id=p_checkout_id for update;
  if not found then raise exception 'checkout_not_found'; end if;
  if c.subscription_id is distinct from p_subscription_id then raise exception 'checkout_subscription_mismatch'; end if;
  if p_subscription_id is null and c.checkout_url is not null then raise exception 'checkout_requires_review'; end if;
  update billing_checkouts set closed_at=coalesce(closed_at,now()) where id=p_checkout_id;
  return jsonb_build_object('ok',true);
end $$;

create or replace function fulfill_gateway_payment(p_checkout_id uuid,p_subscription_id text,p_invoice_id text,p_variant_id text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare c billing_checkouts; result jsonb; shop text;
begin
  if nullif(p_subscription_id,'') is null or nullif(p_invoice_id,'') is null then raise exception 'payment_identity_required'; end if;
  select shop_id into shop from billing_checkouts where id=p_checkout_id;
  -- Same lock order as reservation/closure, including simultaneous invoices.
  perform 1 from shop_subscriptions where shop_id=shop for update;
  select * into c from billing_checkouts where id=p_checkout_id for update;
  if not found then raise exception 'checkout_not_found'; end if;
  if c.variant_id is distinct from p_variant_id then raise exception 'checkout_variant_mismatch'; end if;
  if c.subscription_id is not null and c.subscription_id <> p_subscription_id then raise exception 'checkout_subscription_mismatch'; end if;
  if account_shop_role(c.owner_user_id,c.shop_id) is distinct from 'owner' then raise exception 'verified_owner_required'; end if;
  if c.subscription_id is null and (c.closed_at is not null or exists(
    select 1 from billing_checkouts where shop_id=c.shop_id and id<>c.id
      and closed_at is null and subscription_id is not null
  )) then raise exception 'duplicate_subscription'; end if;
  update billing_checkouts set subscription_id=p_subscription_id where id=c.id;
  result := renew_shop_subscription(c.shop_id,c.months,'lemonsqueezy:invoice:'||p_invoice_id);
  return result || jsonb_build_object('ok',true);
end $$;

revoke all on function reserve_gateway_checkout(text,uuid,text,int),close_gateway_checkout(uuid,text) from public,anon,authenticated;
grant execute on function reserve_gateway_checkout(text,uuid,text,int),close_gateway_checkout(uuid,text) to service_role;
