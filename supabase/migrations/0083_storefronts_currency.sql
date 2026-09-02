-- The public storefront (customer-facing) needs to display prices in
-- whatever currency the owning shop has chosen — mirrors
-- shop_profiles.currency_code (0082), but this table is the one the
-- `storefront` Edge Function actually reads for the public page.
alter table storefronts add column if not exists currency_code text not null default 'MMK';
