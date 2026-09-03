-- Scope product-images write access to the owning shop.
--
-- 0019 granted EVERY authenticated user INSERT/UPDATE on the whole
-- `product-images` bucket, checking only `bucket_id = 'product-images'`.
-- Client upload paths were plain filenames with no shop-owning folder
-- (`p-<millis>.<ext>`, `shop-logo-<millis>.<ext>`, `logo-<shopId>-<millis>.<ext>`
-- — that last one embeds the shop id in the filename, not an actual storage
-- folder segment) — so any activated shop's session could upload to or
-- overwrite another shop's product photo or storefront logo object.
--
-- Fix, same shape as 0066's payment-proofs fix: require new writes to land
-- under a `{shop_id}/...` folder matching the caller's own `auth_shop_id()`
-- claim. Public read stays bucket-wide (storefront photos are meant to be
-- publicly viewable) — this migration only tightens INSERT/UPDATE.
--
-- Deliberately NOT migrating existing flat-path objects: the client always
-- generates a fresh millisecond-timestamped filename per upload (never
-- reuses the previous one), so an old flat-path image just stays reachable
-- at its current public URL until the shop next re-uploads a photo for that
-- product/logo, which lands under the new shop-scoped path automatically —
-- no live `image_url`/`logo_url` reference needs rewriting.

drop policy if exists product_images_write on storage.objects;
create policy product_images_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = auth_shop_id()
  );

drop policy if exists product_images_update on storage.objects;
create policy product_images_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = auth_shop_id()
  );
