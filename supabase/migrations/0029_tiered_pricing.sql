-- Tiered pricing: a customer's retail/wholesale/vip tier picks which
-- products price column the Sell screen applies at checkout. Existing rows
-- default to 'retail' / null overrides, so this is purely additive — no
-- behavior change until a shop actually sets a wholesale/vip price or a
-- customer's tier.

alter table customers add column if not exists tier text not null default 'retail';

alter table products add column if not exists wholesale_price integer;
alter table products add column if not exists vip_price integer;

-- Existing shop_isolation policies on customers/products already cover
-- these new columns (RLS is row-scoped, not column-scoped) — no policy change.
