-- Fix: storefront guest proof uploads rejected since 0066 — shop ids are
-- `shop-<hex>`, not UUIDs.
--
-- 0066's `proof_anon_upload` policy only accepted a first folder segment
-- matching a standard UUID (`^[0-9a-f]{8}-...`). But this app's shop ids are
-- minted as `shop-` + hex (`activate/index.ts` start_trial: 12 hex;
-- admin `fulfill_request`: 10 hex — `shop_id` is `text`, never a uuid).
-- So EVERY guest upload into the shop's own `{shop_id}/` folder failed RLS
-- ("new row violates row-level security policy"), and since the storefront
-- checkout defaults to the `transfer` payment method with proof required,
-- customers could not place transfer orders at all (COD still worked —
-- no upload involved). Live-verified 2026-08-24: `_admin/` upload → 200,
-- `shop-fd9f88405a76/...` upload → 403.
--
-- Fix the shape check to match the app's real id format. Security posture is
-- unchanged from 0066's intent: anon still can never list/read anything; a
-- junk upload into a shape-valid folder is invisible unless an order row
-- references it, and `submit_order` only accepts proof paths under the
-- ordering shop's own id. (The read side — folder-scoped by `auth_shop_id()`
-- or platform-admin — is text equality and was never format-sensitive.)

drop policy if exists proof_anon_upload on storage.objects;
create policy proof_anon_upload on storage.objects
  for insert to anon
  with check (
    bucket_id = 'payment-proofs'
    and (
      (storage.foldername(name))[1] ~ '^shop-[0-9a-f]{6,32}$'
      or (storage.foldername(name))[1] = '_admin'
    )
  );
