-- Owner-set cap on how many units of a product the public web storefront may
-- sell, independent of the shop's real in-store stock (e.g. 20 in the shop,
-- but only 5 reserved for online). Null = no cap, storefront falls back to
-- the soft real-stock warning from 0034. Existing shop_isolation policy on
-- products already covers this column.

alter table products add column if not exists online_stock_limit integer;
