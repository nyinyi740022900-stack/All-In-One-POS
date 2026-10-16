-- Cloud storage: a per-shop usage report, and the list of product photos
-- nothing uses any more.
--
-- Nothing is ever deleted here. Physical removal goes through the Storage API
-- (the `storage-sweep` Edge Function), never a delete on storage.objects:
-- removing the metadata row would leave the bytes behind and still billed.

-- What each shop costs to keep in the cloud, for the admin console.
--
-- Row bytes are pg_column_size of the stored tuples: the data itself, without
-- indexes or page overhead. So it under-reads the disk a table occupies, but
-- ranks shops correctly against each other, which is what it is for. Every
-- public table that carries a shop_id is counted, not a fixed list, so a table
-- added later is never silently left out of the total.
create function admin_storage_report()
returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare
  q text;
  shops jsonb;
begin
  select string_agg(format(
    'select shop_id::text as shop_id, count(*)::bigint as n, '
    'coalesce(sum(pg_column_size(t.*)),0)::bigint as b '
    'from public.%I t group by 1', c.table_name), ' union all ')
    into q
  from information_schema.columns c
  join information_schema.tables tb
    on tb.table_schema=c.table_schema and tb.table_name=c.table_name
  where c.table_schema='public' and c.column_name='shop_id'
    and tb.table_type='BASE TABLE';

  execute format($f$
    with d as (
      select shop_id, sum(n)::bigint as rows, sum(b)::bigint as bytes
      from (%s) u where shop_id is not null group by shop_id
    ), p as (
      select split_part(o.name,'/',1) as shop_id, count(*)::bigint as photos,
             coalesce(sum((o.metadata->>'size')::bigint),0)::bigint as photo_bytes
      from storage.objects o
      where o.bucket_id='product-images' and position('/' in o.name)>0
      group by 1
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'shop_id', coalesce(d.shop_id,p.shop_id),
      'rows', coalesce(d.rows,0),
      'bytes', coalesce(d.bytes,0),
      'photos', coalesce(p.photos,0),
      'photo_bytes', coalesce(p.photo_bytes,0))
      order by coalesce(d.bytes,0)+coalesce(p.photo_bytes,0) desc), '[]'::jsonb)
    from d full join p on p.shop_id=d.shop_id
  $f$, coalesce(q, 'select null::text as shop_id, 0::bigint as n, 0::bigint as b'))
  into shops;

  return jsonb_build_object(
    'database_bytes', pg_database_size(current_database()),
    'shops', shops,
    -- Pre-0088 uploads sit at the bucket root with no shop folder, so they
    -- cannot be attributed to a shop; reported as one line instead.
    'unfoldered_photos', (select count(*) from storage.objects o
      where o.bucket_id='product-images' and position('/' in o.name)=0),
    'unfoldered_photo_bytes', (select coalesce(sum((o.metadata->>'size')::bigint),0)
      from storage.objects o
      where o.bucket_id='product-images' and position('/' in o.name)=0));
end $$;
revoke all on function admin_storage_report() from public,anon,authenticated;
grant execute on function admin_storage_report() to service_role;

-- Product photos no row points at any more: the old file after a photo was
-- replaced, or the photo of a deleted product.
--
-- Errs towards keeping. A file is kept when:
--  * any product row names it, deleted or not, in image_url or image_path, or
--    any storefront names it as its logo, in ANY shop;
--  * it is a receipt logo (`shop-logo-…`). Those URLs live only in the
--    device's own settings and never reach the cloud, so the server cannot
--    see that one is in use; it must never guess;
--  * it is younger than p_min_age, floored at 7 days whatever the caller
--    passes. A photo is uploaded the moment it is picked, before its product
--    is saved and synced, so a fresh file with no reference yet is normal.
-- The match is "the URL ends in /<name>": a root `p-1.jpg` is therefore also
-- kept by a reference to `shop/p-1.jpg` — the safe direction to be wrong in.
create function orphan_product_images(
  p_min_age interval default interval '30 days',
  p_limit int default 1000)
returns table(name text, bytes bigint, created_at timestamptz)
language sql stable security definer set search_path=public,pg_temp as $$
  select o.name, coalesce((o.metadata->>'size')::bigint,0), o.created_at
  from storage.objects o
  where o.bucket_id='product-images'
    and o.created_at < now() - greatest(coalesce(p_min_age, interval '30 days'),
                                        interval '7 days')
    and regexp_replace(o.name,'^.*/','') not like 'shop-logo-%'
    and not exists (
      select 1 from products p
      where right(split_part(split_part(p.image_url,'?',1),'#',1),length(o.name)+1)='/'||o.name
         or right(split_part(split_part(p.image_path,'?',1),'#',1),length(o.name)+1)='/'||o.name
         or p.image_path=o.name)
    and not exists (
      select 1 from storefronts s
      where right(split_part(split_part(s.logo_url,'?',1),'#',1),length(o.name)+1)='/'||o.name)
  order by o.created_at, o.name
  limit least(greatest(coalesce(p_limit,1000),1),1000);
$$;
revoke all on function orphan_product_images(interval,int) from public,anon,authenticated;
grant execute on function orphan_product_images(interval,int) to service_role;
