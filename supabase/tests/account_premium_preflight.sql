-- Single read-only statement so CLI clients that return only the final result
-- cannot hide a blocking issue. No keys, device IDs, emails or secrets returned.
select jsonb_build_object(
  'unverified_branch_owners', coalesce((select jsonb_agg(to_jsonb(x)) from (
    select b.shop_id,b.owner_user_id from org_branches b left join auth.users u on u.id=b.owner_user_id
    where u.id is null or coalesce(u.is_anonymous,false)
      or u.raw_app_meta_data->>'role' is distinct from 'owner'
      or u.raw_app_meta_data->>'shop_id' is distinct from b.shop_id
  ) x),'[]'::jsonb),
  'ambiguous_owners', coalesce((select jsonb_agg(to_jsonb(x)) from (
    select raw_app_meta_data->>'shop_id' shop_id,count(*) owner_count
    from auth.users where raw_app_meta_data->>'role'='owner' and not coalesce(is_anonymous,false)
      and nullif(raw_app_meta_data->>'shop_id','') is not null
    group by raw_app_meta_data->>'shop_id' having count(*)>1
  ) x),'[]'::jsonb),
  'paid_device_allowances', coalesce((select jsonb_agg(to_jsonb(x)) from (
    select shop_id,extra_slots,extras_expires_at from shop_device_allowance
    where extra_slots>0 and (extras_expires_at is null or extras_expires_at>now())
  ) x),'[]'::jsonb),
  'excess_bound_devices', coalesce((select jsonb_agg(to_jsonb(x)) from (
    select shop_id,count(distinct device_id) bound_devices from licenses
    where not is_deleted and device_id is not null group by shop_id having count(distinct device_id)>3
  ) x),'[]'::jsonb),
  'shops', coalesce((select jsonb_agg(to_jsonb(x)) from (
    select l.shop_id,count(*) legacy_rows,count(distinct device_id) filter(where not is_deleted) bound_devices,
      max(expires_at) filter(where not is_deleted) preserved_expiry,
      bool_and(is_deleted) archived,bool_or(plan='trial') historical_trial,
      exists(select 1 from auth.users u where u.raw_app_meta_data->>'role'='owner'
        and u.raw_app_meta_data->>'shop_id'=l.shop_id and not coalesce(u.is_anonymous,false)) identified_owner
    from licenses l group by l.shop_id order by l.shop_id
  ) x),'[]'::jsonb)
) as account_premium_preflight;
