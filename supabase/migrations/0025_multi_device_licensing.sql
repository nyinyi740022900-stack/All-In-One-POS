-- Multi-device licensing, phase 1 (DB layer).
--
-- A shop may run several devices under one shop_id: `licenses.shop_id` was
-- never unique, so multiple key rows sharing a shop_id already works at the
-- schema level — the two gaps are (1) renewal only ever touched the one key
-- being renewed, and (2) there was no safe, self-service way to claim an
-- additional device slot.

-- Fix: renew_license now extends every license row under the shop, not just
-- the key passed in. Signature is unchanged (callers in supabase/functions
-- need no changes) — only the internal behavior.
--
-- Bases the new expiry off the LATEST expires_at among the shop's rows
-- (never `now()` alone), so a renewal never loses days for any device, and
-- also self-heals any drift that had crept in between devices to bring them
-- all back onto one shared expiry.
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
begin
  select shop_id into v_shop_id from licenses where key = p_key;
  if v_shop_id is null then
    raise exception 'license key % not found', p_key;
  end if;

  select greatest(max(expires_at), now()) into v_base
  from licenses
  where shop_id = v_shop_id and is_deleted = false;

  v_expiry := v_base + (p_months || ' months')::interval;

  update licenses
  set expires_at = v_expiry,
      status     = 'active',
      updated_at = now()
  where shop_id = v_shop_id and is_deleted = false;

  return v_expiry;
end;
$$;

-- claim_device_slot(shop_id) -> a key the caller can activate a new device
-- with, or null if the shop is at its free-device limit (the caller shows
-- the device-fee payment flow instead — see app_config below).
--
-- Reuses a released (device_id null) row first, so releasing a device and
-- adding a new one doesn't pile up throwaway key rows. An advisory lock
-- keyed by shop_id serializes concurrent calls for the same shop for the
-- whole function body, so two rapid "Add device" taps can't both slip past
-- the free-limit check and mint two keys for one open slot.
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

  select coalesce(nullif(value, '')::int, 2) into v_free_limit
  from app_config where key = 'device.free_limit';
  v_free_limit := coalesce(v_free_limit, 2);

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

-- Device count included free per shop, and the one-time fee (Ks) for each
-- device beyond that — both editable from the admin console without an app
-- release, same pattern as the existing price.* config rows.
insert into app_config (key, value) values
  ('device.free_limit', '2'),
  ('device.extra_fee',  '10000')
on conflict (key) do nothing;
