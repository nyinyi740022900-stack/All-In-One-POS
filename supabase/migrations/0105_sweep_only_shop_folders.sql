-- Never sweep the old flat uploads at the bucket root.
--
-- The first dry run against production (2026-10-17) listed 15 files, every
-- one of them a pre-0088 root upload (`p-<millis>`, `logo-<shop>-<millis>`).
-- Before 0088 any signed-in session could upload, Free shops included, and a
-- Free shop's products live only on its phone, never in the cloud
-- `products` table. So "no product row names it" proves nothing for those
-- files: a phone may still be showing one. A wrong delete there cannot be
-- undone, and keeping all of them costs about 4 MB.
--
-- Files under a `<shop>/` folder stay eligible. Since 0088 only a shop with a
-- current subscription can write there, and that same subscription syncs its
-- product rows, so the cloud does see every reference to them.
create or replace function orphan_product_images(
  p_min_age interval default interval '30 days',
  p_limit int default 1000)
returns table(name text, bytes bigint, created_at timestamptz)
language sql stable security definer set search_path=public,pg_temp as $$
  select o.name, coalesce((o.metadata->>'size')::bigint,0), o.created_at
  from storage.objects o
  where o.bucket_id='product-images'
    and position('/' in o.name)>0
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
