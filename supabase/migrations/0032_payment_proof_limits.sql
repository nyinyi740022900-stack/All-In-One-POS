-- Enforce payment-proof upload limits at the storage-bucket level, not just
-- client-side (storefront_page.dart already restricts the file picker to
-- images and downsizes via compressImage() — but that's bypassable by anyone
-- calling the anon-insert Storage API directly, without going through the
-- app at all). 5 MiB cap, images only.

update storage.buckets
set file_size_limit = 5242880, -- 5 MiB
    allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
where id = 'payment-proofs';
