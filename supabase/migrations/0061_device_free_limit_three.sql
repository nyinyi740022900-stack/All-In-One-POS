-- Extra-device policy: the shop's main phone is included and does not
-- count toward the extra quota. Two more phones or computers (owner or
-- staff login) are free. device.free_limit is the TOTAL bound-device cap
-- (main + extras), so 3 — not extras-only. Only bump the original default
-- of 2 so an admin who already set a custom value is left alone.
update app_config
set value = '3'
where key = 'device.free_limit' and value = '2';

-- Same function as 0025, with the missing-config fallback 2 → 3.
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

  select coalesce(nullif(value, '')::int, 3) into v_free_limit
  from app_config where key = 'device.free_limit';
  v_free_limit := coalesce(v_free_limit, 3);

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
