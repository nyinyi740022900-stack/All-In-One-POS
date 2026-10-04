-- Account-only billing. Legacy requests remain audit evidence; unverified
-- requests cannot silently acquire an owner or mint new activation keys.
alter table license_requests
  add column owner_user_id uuid references auth.users(id) on delete set null,
  add column fulfilled_expires_at timestamptz;
drop policy if exists lr_insert on license_requests;
revoke insert,update,delete on license_requests from anon,authenticated;

-- Preserve financial audit rows on account deletion; null owner fails all
-- fulfillment membership checks and cannot grant new paid time.
create table billing_checkouts (
  id uuid primary key,
  shop_id text not null references shop_subscriptions(shop_id),
  owner_user_id uuid references auth.users(id) on delete set null,
  variant_id text not null,
  months int not null check(months in (1,12)),
  subscription_id text unique,
  created_at timestamptz not null default now()
);
alter table billing_checkouts enable row level security;
revoke all on billing_checkouts from anon,authenticated;
grant all on billing_checkouts to service_role;

create function fulfill_account_payment(p_request_id text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare r license_requests%rowtype; result jsonb;
begin
  select * into r from license_requests where id=p_request_id for update;
  if not found then raise exception 'request_not_found'; end if;
  if r.status='fulfilled' then
    if r.fulfilled_expires_at is null then raise exception 'legacy_request_requires_review'; end if;
    return jsonb_build_object('ok',true,'duplicate',true,'expires_at',r.fulfilled_expires_at);
  end if;
  if r.status not in ('pending','processing') then raise exception 'request_not_pending'; end if;
  if r.owner_user_id is null or account_shop_role(r.owner_user_id,r.shop_id) is distinct from 'owner' then
    raise exception 'verified_owner_required';
  end if;
  if ((r.plan='monthly' and r.months=1 and r.amount=20000) or (r.plan='yearly' and r.months=12 and r.amount=200000)) is not true then
    raise exception 'invalid_request_price';
  end if;
  result := renew_shop_subscription(r.shop_id,r.months,'manual:'||r.id);
  update license_requests set status='fulfilled',payment_status='paid',paid_at=coalesce(paid_at,now()),
    fulfilled_expires_at=(result->>'expires_at')::timestamptz,updated_at=now() where id=r.id;
  return result || jsonb_build_object('ok',true);
end $$;

create function reject_account_payment(p_request_id text,p_reason text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare r license_requests%rowtype;
begin
  select * into r from license_requests where id=p_request_id for update;
  if not found or r.status <> 'pending' then raise exception 'request_not_pending'; end if;
  update license_requests set status='rejected',reject_reason=nullif(p_reason,''),updated_at=now() where id=r.id;
  return jsonb_build_object('ok',true);
end $$;

-- Only subscription invoices grant time, so the initial order + invoice pair
-- cannot charge two terms. Each processor invoice has one global payment ID.
create function fulfill_gateway_payment(p_checkout_id uuid,p_subscription_id text,p_invoice_id text,p_variant_id text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare c billing_checkouts%rowtype; result jsonb;
begin
  if nullif(p_subscription_id,'') is null or nullif(p_invoice_id,'') is null then raise exception 'payment_identity_required'; end if;
  select * into c from billing_checkouts where id=p_checkout_id for update;
  if not found then raise exception 'checkout_not_found'; end if;
  if c.variant_id is distinct from p_variant_id then raise exception 'checkout_variant_mismatch'; end if;
  if c.subscription_id is not null and c.subscription_id <> p_subscription_id then raise exception 'checkout_subscription_mismatch'; end if;
  if account_shop_role(c.owner_user_id,c.shop_id) is distinct from 'owner' then raise exception 'verified_owner_required'; end if;
  update billing_checkouts set subscription_id=p_subscription_id where id=c.id;
  result := renew_shop_subscription(c.shop_id,c.months,'lemonsqueezy:invoice:'||p_invoice_id);
  return result || jsonb_build_object('ok',true);
end $$;

create function archive_shop_subscription(p_shop_id text,p_archived boolean) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare s shop_subscriptions%rowtype;
begin
  select * into s from shop_subscriptions where shop_id=p_shop_id for update;
  if not found then raise exception 'not_found'; end if;
  if p_archived and s.plan in ('monthly','yearly') and s.expires_at+interval '14 days'>now() then raise exception 'shop_is_paid'; end if;
  update shop_subscriptions set is_archived=p_archived,revision=revision+1 where shop_id=p_shop_id and is_archived is distinct from p_archived;
  return jsonb_build_object('ok',true);
end $$;

revoke all on function fulfill_account_payment(text),reject_account_payment(text,text),fulfill_gateway_payment(uuid,text,text,text),archive_shop_subscription(text,boolean) from public,anon,authenticated;
grant execute on function fulfill_account_payment(text),reject_account_payment(text,text),fulfill_gateway_payment(uuid,text,text,text),archive_shop_subscription(text,boolean) to service_role;

-- Billing uploads must work while the owner has Free or lapsed Premium.
-- Proofs of existing customer obligations remain readable by their shop.
drop policy if exists proof_auth_read on storage.objects;
create policy proof_auth_read on storage.objects for select to authenticated using (
  bucket_id='payment-proofs' and (
    can_read_account_shop((storage.foldername(name))[1])
    or coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->'app_metadata'->>'role','')='admin'
  )
);
drop policy if exists proof_account_upload on storage.objects;
create policy proof_account_upload on storage.objects for insert to authenticated with check (
  bucket_id='payment-proofs' and (
    ((storage.foldername(name))[1]='_admin'
      and (storage.foldername(name))[2]=auth.uid()::text
      and exists(select 1 from shop_subscriptions where owner_user_id=auth.uid()))
    -- A signed-in customer may still order from a public storefront.
    or (storage.foldername(name))[1] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  )
);
