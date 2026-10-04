-- Cloud-only account authority. Legacy licenses remain migration/audit evidence.
-- Run supabase/tests/account_premium_preflight.sql read-only before cutover.
-- Unverified branch ownership and purchased capacity require operator resolution,
-- never an arbitrary winner or silent truncation.
do $$ begin
  if exists(select 1 from org_branches b left join auth.users u on u.id=b.owner_user_id
    where u.id is null or coalesce(u.is_anonymous,false) or
      u.raw_app_meta_data->>'role' is distinct from 'owner' or
      u.raw_app_meta_data->>'shop_id' is distinct from b.shop_id)
    or exists(select 1 from auth.users where raw_app_meta_data->>'role'='owner'
      and not coalesce(is_anonymous,false) and nullif(raw_app_meta_data->>'shop_id','') is not null
      group by raw_app_meta_data->>'shop_id' having count(*)>1)
  then raise exception 'account_premium_preflight: unverified or ambiguous ownership; review report before cutover'; end if;
  if exists(select 1 from shop_device_allowance where extra_slots>0
      and (extras_expires_at is null or extras_expires_at>now()))
    or exists(select 1 from licenses where not is_deleted and device_id is not null
      group by shop_id having count(distinct device_id)>3)
  then raise exception 'account_premium_preflight: paid allowance or more than three devices needs resolution'; end if;
end $$;

create table shop_subscriptions (
  shop_id text primary key,
  owner_user_id uuid references auth.users(id) on delete set null,
  shop_name text,
  plan text not null default 'free' check(plan in ('free','trial','monthly','yearly')),
  expires_at timestamptz not null default '1970-01-01T00:00:00Z',
  activated_at timestamptz not null default now(),
  revision bigint not null default 1 check(revision>0),
  is_archived boolean not null default false,
  free_device_id text
);
create table shop_devices (
  shop_id text not null references shop_subscriptions(shop_id) on delete cascade,
  device_id text not null check(length(trim(device_id)) between 1 and 200),
  user_id uuid references auth.users(id) on delete set null,
  session_id uuid,
  registered_at timestamptz not null default now(),
  last_active_at timestamptz not null default now(),
  released_at timestamptz,
  primary key(shop_id,device_id)
);
create table account_trial_claims (
  owner_user_id uuid primary key references auth.users(id) on delete cascade,
  shop_id text not null,
  started_at timestamptz not null,
  expires_at timestamptz not null
);
create table shop_subscription_payments (
  payment_id text primary key,
  shop_id text not null references shop_subscriptions(shop_id),
  months int not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

insert into shop_subscriptions(shop_id,owner_user_id,shop_name,plan,expires_at,activated_at,is_archived,free_device_id)
select l.shop_id,
  (select u.id from auth.users u where u.raw_app_meta_data->>'shop_id'=l.shop_id
    and u.raw_app_meta_data->>'role'='owner' and not coalesce(u.is_anonymous,false)),
  max(l.shop_name),
  case when bool_or(not l.is_deleted and l.plan not in ('trial','free')) then case when bool_or(not l.is_deleted and l.plan='yearly') then 'yearly' else 'monthly' end
    when bool_or(not l.is_deleted and l.plan='trial') then 'trial' else 'free' end,
  coalesce(max(l.expires_at) filter(where not l.is_deleted),'1970-01-01T00:00:00Z'::timestamptz),
  coalesce(min(l.activated_at),now()),bool_and(l.is_deleted),
  (array_agg(l.device_id order by l.activated_at nulls last,l.device_id) filter(where not l.is_deleted and l.device_id is not null))[1]
from licenses l group by l.shop_id;
insert into shop_devices(shop_id,device_id,user_id,registered_at,last_active_at)
select l.shop_id,l.device_id,s.owner_user_id,coalesce(min(l.activated_at),now()),coalesce(max(l.last_verified_at),now())
from licenses l join shop_subscriptions s using(shop_id)
where not l.is_deleted and l.device_id is not null and length(trim(l.device_id))>0
group by l.shop_id,l.device_id,s.owner_user_id;
-- All historical trials count, including deleted/expired rows and prior devices.
insert into account_trial_claims(owner_user_id,shop_id,started_at,expires_at)
select distinct on(s.owner_user_id) s.owner_user_id,l.shop_id,coalesce(l.activated_at,l.expires_at-interval '2 months'),l.expires_at
from licenses l join shop_subscriptions s using(shop_id)
where l.plan='trial' and s.owner_user_id is not null
order by s.owner_user_id,l.expires_at,l.shop_id;
-- Audited cleanup on 2026-10-04 retained these two owner accounts but purged
-- MM SHOP's historical trial rows. Preserve consumption, never grant a new
-- term or recreate the deleted shop. Dates are audit-marker timestamps, not
-- a reconstructed historical trial interval. Missing/deleted users are skipped.
insert into account_trial_claims(owner_user_id,shop_id,started_at,expires_at)
select u.id,'shop-5bd659ab60b5','2026-10-04T00:00:00Z'::timestamptz,'2026-10-04T00:00:00Z'::timestamptz
from auth.users u where not coalesce(u.is_anonymous,false) and u.id in
  ('3476821d-e7ab-4fc3-966b-ad628fc52e1d'::uuid,'af47495e-4505-40cb-aefb-bc0fbf0be729'::uuid)
on conflict(owner_user_id) do nothing;
insert into org_branches(owner_user_id,shop_id,label)
select owner_user_id,shop_id,coalesce(shop_name,'Home') from shop_subscriptions where owner_user_id is not null
on conflict(owner_user_id,shop_id) do nothing;

-- Membership derives from backend-owned authority or current, non-banned staff
-- metadata. Mutable user_metadata and arbitrary org links never prove access.
create function account_shop_role(p_user_id uuid,p_shop_id text) returns text
language sql stable security definer set search_path=public,pg_temp as $$
  select case when s.owner_user_id=u.id then 'owner'
    when u.raw_app_meta_data->>'role'='staff' and u.raw_app_meta_data->>'shop_id'=s.shop_id then 'staff' end
  from shop_subscriptions s join auth.users u on u.id=p_user_id
  where s.shop_id=p_shop_id and not coalesce(u.is_anonymous,false)
    and (u.banned_until is null or u.banned_until<=now());
$$;
create function can_read_account_shop(p_shop_id text) returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
  select account_shop_role(auth.uid(),p_shop_id) is not null;
$$;
alter table shop_subscriptions enable row level security;
alter table shop_devices enable row level security;
alter table account_trial_claims enable row level security;
alter table shop_subscription_payments enable row level security;
create policy shop_isolation on shop_subscriptions for select to authenticated using(can_read_account_shop(shop_id));
create policy shop_isolation on shop_devices for select to authenticated using(can_read_account_shop(shop_id));
create policy owner_account on account_trial_claims for select to authenticated using(owner_user_id=auth.uid());
drop policy if exists org_branches_owner on org_branches;
create policy org_branches_owner on org_branches for select to authenticated using(owner_user_id=auth.uid());
revoke all on shop_subscriptions,shop_devices,account_trial_claims,shop_subscription_payments,org_branches from anon,authenticated;
grant select on shop_subscriptions,shop_devices,account_trial_claims,org_branches to authenticated;
grant all on shop_subscriptions,shop_devices,account_trial_claims,shop_subscription_payments,org_branches to service_role;

create function create_account_shop(p_user_id uuid,p_shop_id text,p_shop_name text,p_device_id text default null) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not exists(select 1 from auth.users where id=p_user_id and not coalesce(is_anonymous,false)
    and (banned_until is null or banned_until<=now())) then raise exception 'not_authenticated'; end if;
  if nullif(trim(p_shop_id),'') is null then raise exception 'bad_request'; end if;
  insert into shop_subscriptions(shop_id,owner_user_id,shop_name,free_device_id)
    values(p_shop_id,p_user_id,p_shop_name,nullif(trim(p_device_id),''));
  insert into org_branches(owner_user_id,shop_id,label) values(p_user_id,p_shop_id,coalesce(nullif(p_shop_name,''),'Home'));
  if nullif(trim(p_device_id),'') is not null then
    insert into shop_devices(shop_id,device_id,user_id) values(p_shop_id,p_device_id,p_user_id);
  end if;
  return (select to_jsonb(s) from shop_subscriptions s where shop_id=p_shop_id);
end $$;

create function start_account_trial(p_user_id uuid,p_shop_id text,p_device_id text default null,p_reclaim boolean default false,p_session_id uuid default null) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare s shop_subscriptions;
begin
  -- Account first, then shop: consistent ordering prevents concurrent branch trials.
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,94));
  select * into s from shop_subscriptions where shop_id=p_shop_id for update;
  if account_shop_role(p_user_id,p_shop_id) is distinct from 'owner' then raise exception 'membership_revoked'; end if;
  if s.is_archived then raise exception 'shop_archived'; end if;
  if exists(select 1 from account_trial_claims where owner_user_id=p_user_id) then raise exception 'trial_already_used'; end if;
  if s.plan<>'free' then raise exception 'already_premium'; end if;
  insert into account_trial_claims values(p_user_id,p_shop_id,now(),now()+interval '2 months');
  update shop_subscriptions set plan='trial',expires_at=now()+interval '2 months',activated_at=now(),revision=revision+1 where shop_id=p_shop_id returning * into s;
  -- Trial consumption and slot registration commit together. A failed fourth
  -- device/released-device claim cannot burn the owner's once-only trial.
  if p_device_id is not null then
    return register_shop_device(p_user_id,p_shop_id,p_device_id,p_reclaim,p_session_id);
  end if;
  return to_jsonb(s);
end $$;

create function register_shop_device(p_user_id uuid,p_shop_id text,p_device_id text,p_reclaim boolean default false,p_session_id uuid default null) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare s shop_subscriptions; d shop_devices; premium boolean;
begin
  if nullif(trim(p_device_id),'') is null or length(p_device_id)>200 then raise exception 'bad_request'; end if;
  select * into s from shop_subscriptions where shop_id=p_shop_id for update;
  if account_shop_role(p_user_id,p_shop_id) is null then raise exception 'membership_revoked'; end if;
  if s.is_archived then raise exception 'shop_archived'; end if;
  select * into d from shop_devices where shop_id=p_shop_id and device_id=p_device_id;
  if d.released_at is not null and not p_reclaim then raise exception 'device_released'; end if;
  premium := s.plan<>'free' and s.expires_at+interval '14 days'>=now();
  -- Previously provisioned staff may keep local core POS after lapse. New Free
  -- devices require explicit owner-directed backup/restore, not cloud recovery.
  if d.device_id is null or d.released_at is not null then
    if not premium and s.free_device_id is not null and s.free_device_id<>p_device_id then
      -- Owner explicitly signs in after releasing the old Free device. This
      -- changes device authority only; local backup/restore transfers records.
      if not p_reclaim or account_shop_role(p_user_id,p_shop_id)<>'owner'
        or exists(select 1 from shop_devices where shop_id=p_shop_id and released_at is null) then
        raise exception 'free_device_replacement_required';
      end if;
      update shop_subscriptions set free_device_id=p_device_id,revision=revision+1 where shop_id=p_shop_id;
    end if;
    if (select count(*) from shop_devices where shop_id=p_shop_id and released_at is null)>=(case when premium then 3 else 1 end) then raise exception 'device_limit_reached'; end if;
  end if;
  insert into shop_devices(shop_id,device_id,user_id,session_id) values(p_shop_id,p_device_id,p_user_id,p_session_id)
    on conflict(shop_id,device_id) do update set user_id=p_user_id,session_id=p_session_id,last_active_at=now(),released_at=null;
  if s.free_device_id is null then
    update shop_subscriptions set free_device_id=p_device_id where shop_id=p_shop_id;
  end if;
  select * into s from shop_subscriptions where shop_id=p_shop_id;
  return to_jsonb(s)||jsonb_build_object('device_id',p_device_id,'user_id',p_user_id);
end $$;

create function release_shop_device(p_user_id uuid,p_shop_id text,p_device_id text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare s shop_subscriptions; role text;
begin
  select * into s from shop_subscriptions where shop_id=p_shop_id for update;
  role := account_shop_role(p_user_id,p_shop_id);
  if role is null then raise exception 'membership_revoked'; end if;
  -- Staff may release their own session at sign-out, not other devices.
  if role<>'owner' and not exists(select 1 from shop_devices where shop_id=p_shop_id and device_id=p_device_id and user_id=p_user_id) then raise exception 'forbidden'; end if;
  update shop_devices set released_at=now() where shop_id=p_shop_id and device_id=p_device_id and released_at is null;
  if found then update shop_subscriptions set revision=revision+1 where shop_id=p_shop_id; end if;
  return jsonb_build_object('ok',true);
end $$;

create function renew_shop_subscription(p_shop_id text,p_months int,p_payment_id text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare s shop_subscriptions; paid shop_subscription_payments; expiry timestamptz;
begin
  if p_months not in(1,12) or p_months is null or nullif(trim(p_payment_id),'') is null then raise exception 'bad_request'; end if;
  -- Payment lock serializes conflicting shop IDs as well as same-shop retries.
  perform pg_advisory_xact_lock(hashtextextended(p_payment_id,95));
  select * into paid from shop_subscription_payments where payment_id=p_payment_id;
  if found then
    if paid.shop_id<>p_shop_id or paid.months<>p_months then raise exception 'payment_conflict'; end if;
    return jsonb_build_object('expires_at',paid.expires_at,'duplicate',true);
  end if;
  select * into s from shop_subscriptions where shop_id=p_shop_id for update;
  if not found then raise exception 'not_found'; end if;
  if s.is_archived then raise exception 'shop_archived'; end if;
  if s.owner_user_id is null or not exists(select 1 from auth.users u
    where u.id=s.owner_user_id and not coalesce(u.is_anonymous,false)
      and (u.banned_until is null or u.banned_until<=now()))
  then raise exception 'ownership_verification_required'; end if;
  expiry := (case when s.expires_at>=now()-interval '14 days' then s.expires_at else now() end)+make_interval(months=>p_months);
  update shop_subscriptions set plan=case when p_months=12 or s.plan='yearly' then 'yearly' else 'monthly' end,expires_at=expiry,revision=revision+1 where shop_id=p_shop_id;
  insert into shop_subscription_payments(payment_id,shop_id,months,expires_at) values(p_payment_id,p_shop_id,p_months,expiry);
  return jsonb_build_object('expires_at',expiry,'duplicate',false);
end $$;

revoke all on function account_shop_role(uuid,text),create_account_shop(uuid,text,text,text),start_account_trial(uuid,text,text,boolean,uuid),register_shop_device(uuid,text,text,boolean,uuid),release_shop_device(uuid,text,text),renew_shop_subscription(text,int,text) from public,anon,authenticated;
grant execute on function account_shop_role(uuid,text),create_account_shop(uuid,text,text,text),start_account_trial(uuid,text,text,boolean,uuid),register_shop_device(uuid,text,text,boolean,uuid),release_shop_device(uuid,text,text),renew_shop_subscription(text,int,text) to service_role;
revoke all on function can_read_account_shop(text) from public,anon;
grant execute on function can_read_account_shop(text) to authenticated,service_role;
-- Retire legacy service RPCs as authority. Existing records stay read-only evidence.
do $$ declare f record; begin
  for f in select oid::regprocedure as name from pg_proc where pronamespace='public'::regnamespace
    and proname in('create_license','grant_extra_device_slot','claim_device_slot','create_trial_branch','renew_license','set_shop_device_allowance')
  loop execute format('revoke all on function %s from public,anon,authenticated,service_role',f.name); end loop;
end $$;

-- Trusted legacy owner session -> real account. Account creation itself happens
-- through Auth admin; the ownership CAS and consumed historical trial are atomic.
create function attach_legacy_shop_owner(p_legacy_user_id uuid,p_owner_user_id uuid,p_shop_id text) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare s shop_subscriptions;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_owner_user_id::text,94));
  select * into s from shop_subscriptions where shop_id=p_shop_id for update;
  if not found or not exists(select 1 from auth.users where id=p_legacy_user_id
    and raw_app_meta_data->>'shop_id'=p_shop_id and raw_app_meta_data->>'role'='owner'
    and (banned_until is null or banned_until<=now())) then raise exception 'ownership_verification_required'; end if;
  if s.owner_user_id is not null then raise exception 'account_already_linked'; end if;
  if s.is_archived then raise exception 'shop_archived'; end if;
  if not exists(select 1 from auth.users where id=p_owner_user_id and not coalesce(is_anonymous,false)
    and (banned_until is null or banned_until<=now())) then raise exception 'not_authenticated'; end if;
  update shop_subscriptions set owner_user_id=p_owner_user_id,revision=revision+1 where shop_id=p_shop_id;
  insert into org_branches(owner_user_id,shop_id,label) values(p_owner_user_id,p_shop_id,coalesce(s.shop_name,'Home'));
  insert into account_trial_claims(owner_user_id,shop_id,started_at,expires_at)
    select p_owner_user_id,p_shop_id,coalesce(activated_at,expires_at-interval '2 months'),expires_at
    from licenses where shop_id=p_shop_id and plan='trial' order by expires_at limit 1
    on conflict(owner_user_id) do nothing;
  return jsonb_build_object('ok',true);
end $$;
revoke all on function attach_legacy_shop_owner(uuid,uuid,text) from public,anon,authenticated;
grant execute on function attach_legacy_shop_owner(uuid,uuid,text) to service_role;


-- Every existing business-table shop_isolation policy calls this function.
-- Account/billing reads use separate membership policies so renewal stays usable.
-- A server-verified JWT session is provisioned by activate; global user metadata
-- cannot accidentally make a fourth device inherit another session's slot.
create or replace function auth_shop_id() returns text
language sql stable security definer set search_path=public,pg_temp as $$
  with claims as (
    select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb j
  )
  select coalesce((select s.shop_id from shop_subscriptions s,claims c
    where s.shop_id=coalesce(nullif(c.j->>'shop_id',''),c.j->'app_metadata'->>'shop_id')
      and not s.is_archived and s.plan<>'free' and s.expires_at+interval '14 days'>=now()
      and account_shop_role(auth.uid(),s.shop_id) is not null
      and exists(select 1 from shop_devices d where d.shop_id=s.shop_id and d.user_id=auth.uid()
        and d.released_at is null and d.session_id::text=c.j->>'session_id')
  ),'');
$$;
revoke all on function auth_shop_id() from public,anon;
grant execute on function auth_shop_id() to authenticated,service_role;
