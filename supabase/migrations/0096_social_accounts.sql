-- Social sign-in shares existing account authority. These mutations are callable
-- only by the authenticated-user-verifying activate service, never by clients.
create function resolve_social_account(p_user_id uuid) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare u auth.users; s shop_subscriptions; selected_shop text;
begin
  select * into u from auth.users where id=p_user_id;
  if not found or coalesce(u.is_anonymous,false) or nullif(trim(u.email),'') is null
    or (u.banned_until is not null and u.banned_until>now()) then
    raise exception 'not_authenticated';
  end if;
  selected_shop := nullif(u.raw_app_meta_data->>'shop_id','');
  -- A historical staff identity must never be converted to an owner by signup.
  if u.raw_app_meta_data->>'role'='staff' then
    select * into s from shop_subscriptions where shop_id=selected_shop;
    if not found or account_shop_role(p_user_id,selected_shop) is distinct from 'staff' then
      raise exception 'membership_revoked';
    end if;
    if s.is_archived then raise exception 'shop_archived'; end if;
    return jsonb_build_object('needs_shop_name',false,'shop_id',s.shop_id,'role','staff');
  end if;
  select sub.* into s from shop_subscriptions sub
    where sub.owner_user_id=p_user_id and not sub.is_archived
    order by (sub.shop_id=selected_shop) desc nulls last,
      (select max(b.last_active_at) from org_branches b
        where b.owner_user_id=p_user_id and b.shop_id=sub.shop_id) desc nulls last,
      sub.shop_id limit 1;
  if found then
    return jsonb_build_object('needs_shop_name',false,'shop_id',s.shop_id,'role','owner');
  end if;
  if exists(select 1 from shop_subscriptions where owner_user_id=p_user_id and is_archived) then
    raise exception 'shop_archived';
  end if;
  -- Dangling trusted membership/branch links are recovery cases, not new users.
  if selected_shop is not null or u.raw_app_meta_data->>'role' in ('owner','staff')
    or exists(select 1 from org_branches where owner_user_id=p_user_id) then
    raise exception 'membership_revoked';
  end if;
  return jsonb_build_object('needs_shop_name',true);
end $$;

create function create_social_account_shop(p_user_id uuid,p_shop_name text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare membership jsonb; created jsonb;
begin
  -- The same user can race first setup from multiple devices. Both the lookup
  -- and creation are in this transaction, and all retries return the same shop.
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,96));
  membership := resolve_social_account(p_user_id);
  if membership->>'role'='staff' then raise exception 'forbidden'; end if;
  if membership->>'needs_shop_name'='false' then
    return (select to_jsonb(s) from shop_subscriptions s
      where s.shop_id=membership->>'shop_id');
  end if;
  if nullif(trim(p_shop_name),'') is null then raise exception 'bad_request'; end if;
  -- No trial and no device/session registration: the client must refresh JWT
  -- and use register_shop_device through the normal authenticated attach path.
  created := create_account_shop(p_user_id,'shop-'||gen_random_uuid()::text,trim(p_shop_name),null);
  return created;
end $$;

-- Store only hashes of validated provider tokens, never provider credentials.
-- Consumption before deletion makes a retry require a fresh native proof.
create table social_reauth_proofs (
  proof_hash text primary key check(proof_hash ~ '^[0-9a-f]{64}$'),
  user_id uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null
);
alter table social_reauth_proofs enable row level security;
revoke all on social_reauth_proofs from public,anon,authenticated;
grant all on social_reauth_proofs to service_role;
create function consume_social_reauth_proof(p_user_id uuid,p_proof_hash text,p_expires_at timestamptz) returns boolean
language plpgsql security definer set search_path=public,pg_temp as $$
declare inserted int;
begin
  if p_expires_at<=now() or p_expires_at>now()+interval '6 minutes' then return false; end if;
  delete from social_reauth_proofs where expires_at<now();
  insert into social_reauth_proofs(proof_hash,user_id,expires_at)
    values(p_proof_hash,p_user_id,p_expires_at) on conflict do nothing;
  get diagnostics inserted = row_count;
  return inserted=1;
end $$;
revoke all on function resolve_social_account(uuid),create_social_account_shop(uuid,text),consume_social_reauth_proof(uuid,text,timestamptz) from public,anon,authenticated;
grant execute on function resolve_social_account(uuid),create_social_account_shop(uuid,text),consume_social_reauth_proof(uuid,text,timestamptz) to service_role;
