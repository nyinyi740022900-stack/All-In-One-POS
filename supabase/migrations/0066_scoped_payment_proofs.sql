-- Audit C-1 fix — scope payment-proof reads to the owning shop.
--
-- 0022 granted EVERY authenticated user SELECT on the whole private
-- `payment-proofs` bucket ("paths are random/unguessable"). Two problems:
-- a bucket-wide SELECT also allows LISTING the bucket (Supabase Storage's
-- list() checks the same policy), and the paths are NOT high-entropy —
-- `proof-{millis}-{size}.{ext}` (storefront_api.dart). Any shop's session
-- could enumerate and download every other shop's customer transfer
-- screenshots (bank-app PII).
--
-- Fix: move every object into a folder named after its owning shop
-- (`{shop_id}/...`), put owner-unresolvable files (renew-page uploads,
-- orphans) under `_admin/`, and scope the read policy by that first folder
-- segment. Platform-admin sessions (`app_metadata.role = 'admin'`) keep
-- access for license-request review. The anon INSERT policy stays, but now
-- requires one of those two folder shapes so guests still can't write
-- outside them (they still can never list or read).

-- ---------------------------------------------------------------------------
-- 1) Move existing objects + rewrite the referencing path columns.
--    updated_at is bumped on every touched row so devices learn the new
--    path through the normal sync pull (LWW compares updated_at).

-- Storefront order proofs → folder = orders.shop_id.
update storage.objects o
set name = ord.shop_id || '/' || o.name
from public.orders ord
where o.bucket_id = 'payment-proofs'
  and position('/' in o.name) = 0
  and ord.payment_proof_path = o.name;

update public.orders
set payment_proof_path = shop_id || '/' || payment_proof_path,
    updated_at = now()
where payment_proof_path is not null
  and position('/' in payment_proof_path) = 0;

-- License-request proofs with a resolved shop → that shop's folder.
update storage.objects o
set name = lr.shop_id || '/' || o.name
from public.license_requests lr
where o.bucket_id = 'payment-proofs'
  and position('/' in o.name) = 0
  and lr.shop_id is not null
  and lr.payment_proof_path = o.name;

update public.license_requests
set payment_proof_path = shop_id || '/' || payment_proof_path,
    updated_at = now()
where payment_proof_path is not null
  and shop_id is not null
  and position('/' in payment_proof_path) = 0;

-- Everything left flat (renew-page uploads with no resolved shop, orphaned
-- uploads whose order/request was never submitted) → admin-only folder.
update storage.objects
set name = '_admin/' || name
where bucket_id = 'payment-proofs'
  and position('/' in name) = 0;

update public.license_requests
set payment_proof_path = '_admin/' || payment_proof_path,
    updated_at = now()
where payment_proof_path is not null
  and position('/' in payment_proof_path) = 0;

-- ---------------------------------------------------------------------------
-- 2) Replace the bucket-wide read policy with folder-scoped access:
--    the first path segment must equal the caller's own shop_id claim,
--    or the caller must be a platform admin.

drop policy if exists proof_auth_read on storage.objects;
create policy proof_auth_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'payment-proofs'
    and (
      (storage.foldername(name))[1] = auth_shop_id()
      or coalesce(
        current_setting('request.jwt.claims', true)::json
          -> 'app_metadata' ->> 'role',
        ''
      ) = 'admin'
    )
  );

-- 3) Keep anon guest uploads working, but only into a valid folder shape:
--    a UUID-named shop folder or `_admin/`. Guests still cannot list/read.

drop policy if exists proof_anon_upload on storage.objects;
create policy proof_anon_upload on storage.objects
  for insert to anon
  with check (
    bucket_id = 'payment-proofs'
    and (
      (storage.foldername(name))[1] ~
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or (storage.foldername(name))[1] = '_admin'
    )
  );
