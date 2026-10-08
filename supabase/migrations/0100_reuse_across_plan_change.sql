-- 0099 let an abandoned card reservation be picked up again, but only for the
-- same plan: a dead monthly reservation still refused a yearly purchase, which
-- is the case the owner actually hit. The reason for that refusal was real —
-- a reused row keeps one variant_id, and fulfilment rejected an invoice naming
-- any other, so repurposing the row would have made a late invoice for the
-- superseded plan unfulfilable.
--
-- Rather than accept that loss, the row now remembers what it has offered.
-- `offered_terms` maps every superseded variant to the term it was sold for,
-- so a late invoice is still honoured — and honoured for *its own* term, not
-- the row's current one. That distinction is the whole point: granting a year
-- for a month's invoice because the row had since been switched to yearly
-- would be worse than refusing it.
--
-- The pairs are trustworthy because the Edge Function verifies a variant's
-- billing interval against the requested plan before it ever reserves
-- (verifyVariantForPlan), so a variant_id can only reach this table alongside
-- the term the processor will actually charge for it.
alter table billing_checkouts
  add column offered_terms jsonb not null default '{}'::jsonb;

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
    -- Reuse: a card reservation, never linked to a subscription, and past the
    -- expiry we set on Lemon Squeezy's own checkout object by a margin. The
    -- plan may now differ; the term it used to offer is kept so an invoice
    -- for it can still be paid out at that term.
    if c.provider = 'lemonsqueezy'
       and c.subscription_id is null
       and c.checkout_expires_at is not null
       and c.checkout_expires_at < now() - interval '15 minutes'
    then
      update billing_checkouts
         set offered_terms = case when c.variant_id = p_variant_id then c.offered_terms
                                  else c.offered_terms || jsonb_build_object(c.variant_id, c.months) end,
             variant_id = p_variant_id,
             months = p_months,
             checkout_expires_at = now()+interval '1 hour',
             checkout_url = null
       where id = c.id returning * into c;
      return jsonb_build_object('reserved',true,'reused',true,'checkout',to_jsonb(c));
    end if;
    return jsonb_build_object('reserved',false,'checkout',to_jsonb(c));
  end if;
  insert into billing_checkouts(id,shop_id,owner_user_id,variant_id,months,checkout_expires_at)
    values(gen_random_uuid(),p_shop_id,p_owner_user_id,p_variant_id,p_months,now()+interval '1 hour') returning * into c;
  return jsonb_build_object('reserved',true,'checkout',to_jsonb(c));
end $$;

-- Identical to 0097's in every check but one: the term paid out is resolved
-- from the variant the invoice actually names, so a superseded plan settles at
-- its own price and a variant this row never offered is still refused.
create or replace function fulfill_gateway_payment(p_checkout_id uuid,p_subscription_id text,p_invoice_id text,p_variant_id text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare c billing_checkouts; result jsonb; shop text; term int;
begin
  if nullif(p_subscription_id,'') is null or nullif(p_invoice_id,'') is null then raise exception 'payment_identity_required'; end if;
  select shop_id into shop from billing_checkouts where id=p_checkout_id;
  -- Same lock order as reservation/closure, including simultaneous invoices.
  perform 1 from shop_subscriptions where shop_id=shop for update;
  select * into c from billing_checkouts where id=p_checkout_id for update;
  if not found then raise exception 'checkout_not_found'; end if;
  if p_variant_id is null then raise exception 'checkout_variant_mismatch'; end if;
  if c.variant_id = p_variant_id then
    term := c.months;
  elsif c.offered_terms ? p_variant_id then
    term := (c.offered_terms->>p_variant_id)::int;
  else
    raise exception 'checkout_variant_mismatch';
  end if;
  if c.subscription_id is not null and c.subscription_id <> p_subscription_id then raise exception 'checkout_subscription_mismatch'; end if;
  if account_shop_role(c.owner_user_id,c.shop_id) is distinct from 'owner' then raise exception 'verified_owner_required'; end if;
  if c.subscription_id is null and (c.closed_at is not null or exists(
    select 1 from billing_checkouts where shop_id=c.shop_id and id<>c.id
      and closed_at is null and subscription_id is not null
  )) then raise exception 'duplicate_subscription'; end if;
  update billing_checkouts set subscription_id=p_subscription_id where id=c.id;
  result := renew_shop_subscription(c.shop_id,term,'lemonsqueezy:invoice:'||p_invoice_id);
  return result || jsonb_build_object('ok',true);
end $$;
