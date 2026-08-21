-- Per-shop paid extra-device allowance. The global device.free_limit (3)
-- is always included: main phone + 2 extras. This table adds more slots
-- after Support records a paid extra-device grant. No license key is
-- issued — the extra phone signs in and taps Check for renewal, which
-- calls claim_device_slot and binds under the raised cap.
create table if not exists shop_device_allowance (
  shop_id            text primary key,
  extra_slots        int not null default 0 check (extra_slots >= 0),
  extras_expires_at  timestamptz,
  updated_at         timestamptz not null default now()
);

alter table shop_device_allowance enable row level security;
drop policy if exists shop_isolation on shop_device_allowance;
create policy shop_isolation on shop_device_allowance
  for select to authenticated
  using (shop_id = auth_shop_id());

create or replace function set_shop_device_allowance(
  p_shop_id     text,
  p_extra_slots int,
  p_months      int
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_expires timestamptz;
begin
  if p_shop_id is null or length(trim(p_shop_id)) = 0 then
    raise exception 'shop id required';
  end if;
  if p_extra_slots is null or p_extra_slots < 0 then
    raise exception 'extra_slots must be >= 0';
  end if;

  if p_extra_slots = 0 then
    v_expires := null;
  else
    if p_months is null or p_months < 1 then
      raise exception 'months must be >= 1';
    end if;
    v_expires := now() + (p_months || ' months')::interval;
  end if;

  insert into shop_device_allowance (
    shop_id, extra_slots, extras_expires_at, updated_at
  ) values (
    p_shop_id, p_extra_slots, v_expires, now()
  )
  on conflict (shop_id) do update set
    extra_slots = excluded.extra_slots,
    extras_expires_at = excluded.extras_expires_at,
    updated_at = now();

  return jsonb_build_object(
    'extra_slots', p_extra_slots,
    'extras_expires_at', v_expires
  );
end;
$$;

revoke execute on function set_shop_device_allowance(text, int, int) from public;

-- Same as 0061, plus paid extra_slots from shop_device_allowance while
-- the grant has not expired.
create or replace function claim_device_slot(
  p_shop_id text
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key         text;
  v_plan        text;
  v_expires_at  timestamptz;
  v_free_limit  int;
  v_extra       int;
  v_bound_count int;
begin
  perform pg_advisory_xact_lock(hashtext(p_shop_id));

  select key into v_key
  from licenses
  where shop_id = p_shop_id and device_id is null and is_deleted = false
  order by created_at asc
  limit 1;

  if v_key is not null then
    return v_key;
  end if;

  select coalesce(nullif(value, '')::int, 3) into v_free_limit
  from app_config where key = 'device.free_limit';
  v_free_limit := coalesce(v_free_limit, 3);

  select extra_slots into v_extra
  from shop_device_allowance
  where shop_id = p_shop_id
    and extra_slots > 0
    and (extras_expires_at is null or extras_expires_at > now());
  v_free_limit := v_free_limit + coalesce(v_extra, 0);

  select count(*) into v_bound_count
  from licenses
  where shop_id = p_shop_id and device_id is not null and is_deleted = false;

  if v_bound_count >= v_free_limit then
    return null;
  end if;

  select plan, expires_at into v_plan, v_expires_at
  from licenses
  where shop_id = p_shop_id and is_deleted = false
  order by created_at asc
  limit 1;

  if v_plan is null then
    raise exception 'shop % has no license to base a new device on', p_shop_id;
  end if;

  v_key := 'MMPOS-'
    || upper(substr(md5(gen_random_uuid()::text), 1, 4)) || '-'
    || upper(substr(md5(gen_random_uuid()::text), 1, 4)) || '-'
    || upper(substr(md5(gen_random_uuid()::text), 1, 4));

  insert into licenses (shop_id, key, plan, status, expires_at, activated_at)
  values (p_shop_id, v_key, v_plan, 'active', v_expires_at, null);

  return v_key;
end;
$$;

revoke execute on function claim_device_slot(text) from public;
