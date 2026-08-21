-- Admin-only: grant a device slot under an existing shop, ignoring the
-- free-device cap. Support uses this after a shop pays the extra-device
-- fee (main phone + 2 extras are free; a 4th+ is paid).
--
-- Reuses an unbound (device_id null) key first so a second tap does not
-- pile up unused rows. Otherwise mints a new key on the shop's current
-- plan / expiry / tier. The new row stays unbound until the shop
-- activates it (offline key) or signs in on the new phone (online).
create or replace function grant_extra_device_slot(
  p_shop_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key            text;
  v_plan           text;
  v_expires_at     timestamptz;
  v_shop_name      text;
  v_tier           text;
  v_realtime       boolean;
begin
  perform pg_advisory_xact_lock(hashtext(p_shop_id));

  select key into v_key
  from licenses
  where shop_id = p_shop_id and device_id is null and is_deleted = false
  order by created_at asc
  limit 1;

  if v_key is not null then
    return jsonb_build_object('key', v_key, 'reused', true);
  end if;

  select plan, expires_at, shop_name, tier, realtime_enabled
    into v_plan, v_expires_at, v_shop_name, v_tier, v_realtime
  from licenses
  where shop_id = p_shop_id and is_deleted = false
  order by created_at asc
  limit 1;

  if v_plan is null then
    raise exception 'shop % has no license to grant a device on', p_shop_id;
  end if;

  v_key := 'MMPOS-'
    || upper(substr(md5(gen_random_uuid()::text), 1, 4)) || '-'
    || upper(substr(md5(gen_random_uuid()::text), 1, 4)) || '-'
    || upper(substr(md5(gen_random_uuid()::text), 1, 4));

  insert into licenses (
    shop_id, shop_name, key, plan, status, expires_at, activated_at,
    tier, realtime_enabled
  ) values (
    p_shop_id, v_shop_name, v_key, v_plan, 'active', v_expires_at, null,
    coalesce(v_tier, 'offline'), coalesce(v_realtime, false)
  );

  return jsonb_build_object('key', v_key, 'reused', false);
end;
$$;

revoke execute on function grant_extra_device_slot(text) from public;
