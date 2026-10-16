-- Old product photos/logos were uploaded at the bucket root (0088 leaves
-- them there). URLs in shop rows are user-controlled and cannot authorize
-- deletion: use Storage's uploader identity, before deleting Auth users.
create function account_legacy_product_files(p_owner_user_id uuid)
returns table(name text)
language sql stable security definer set search_path=public,pg_temp as $$
  with owned_shops as (
    select shop_id from shop_subscriptions where owner_user_id=p_owner_user_id
  ), uploaders as (
    select u.id::text as id from auth.users u
    where exists(select 1 from owned_shops)
      and (u.id=p_owner_user_id or (
        u.raw_app_meta_data->>'shop_id' in (select shop_id from owned_shops)
        and (u.raw_app_meta_data->>'role' in ('owner','staff') or u.is_anonymous)
      ))
  )
  select o.name from storage.objects o
  where o.bucket_id='product-images' and position('/' in o.name)=0
    -- owner_id replaced owner in newer Storage releases. JSON access also
    -- works against older schemas that only have the original UUID column.
    and coalesce(nullif(to_jsonb(o)->>'owner_id',''),to_jsonb(o)->>'owner')
      in (select id from uploaders)
    -- An old uploader may since have transferred a shop or shared a logo.
    -- Keep any root object still referenced by a shop outside this deletion.
    and not exists (
      select 1 from products p
      where p.shop_id not in (select shop_id from owned_shops)
        and (right(split_part(split_part(p.image_url,'?',1),'#',1),length(o.name)+1)='/'||o.name
          or right(split_part(split_part(p.image_path,'?',1),'#',1),length(o.name)+1)='/'||o.name)
    )
    and not exists (
      select 1 from storefronts s
      where s.shop_id not in (select shop_id from owned_shops)
        and right(split_part(split_part(s.logo_url,'?',1),'#',1),length(o.name)+1)='/'||o.name
    )
  order by o.name limit 1000;
$$;
revoke all on function account_legacy_product_files(uuid) from public,anon,authenticated;
grant execute on function account_legacy_product_files(uuid) to service_role;

-- Auth refuses to delete a Storage owner. Billing proofs and transferred
-- photos must remain, so detach ONLY deleting users' ownership metadata.
-- Never delete metadata rows, rename objects, or change their bytes here:
-- physical cleanup is exclusively through the Storage API.
create function release_deleted_account_storage(p_owner_user_id uuid)
returns boolean
language plpgsql security definer set search_path=public,pg_temp as $$
declare deleting_users text[];
begin
  if not exists(select 1 from shop_subscriptions where owner_user_id=p_owner_user_id)
     or exists(select 1 from shop_subscriptions where owner_user_id=p_owner_user_id and not is_archived)
  then raise exception 'shop_not_archived'; end if;
  select array_agg(u.id::text) into deleting_users from auth.users u
  where u.id=p_owner_user_id or (
    u.raw_app_meta_data->>'role'='staff'
    and u.raw_app_meta_data->>'shop_id' in (
      select shop_id from shop_subscriptions where owner_user_id=p_owner_user_id
    )
  );
  -- A modern owner_id can already belong to a different shop while the
  -- deprecated owner still points at the old user. Clear independently.
  if exists(select 1 from pg_attribute where attrelid='storage.objects'::regclass
            and attname='owner' and not attisdropped) then
    execute 'update storage.objects set owner=null where owner::text=any($1)'
      using deleting_users;
  end if;
  if exists(select 1 from pg_attribute where attrelid='storage.objects'::regclass
            and attname='owner_id' and not attisdropped) then
    execute 'update storage.objects set owner_id=null where owner_id=any($1)'
      using deleting_users;
  end if;
  return true;
end $$;
revoke all on function release_deleted_account_storage(uuid) from public,anon,authenticated;
grant execute on function release_deleted_account_storage(uuid) to service_role;
