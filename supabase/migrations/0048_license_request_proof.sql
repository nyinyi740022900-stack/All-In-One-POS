-- Payment screenshot on a self-service license request, same pattern as
-- storefront guest orders (0018/0022/0032): the `payment-proofs` bucket
-- already allows anon INSERT and authenticated SELECT, so no new storage
-- policy is needed here — just the column to carry the path.

alter table license_requests add column if not exists payment_proof_path text;
