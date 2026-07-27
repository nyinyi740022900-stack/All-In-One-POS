-- Flag a storefront order line placed against insufficient stock (see the
-- 0033 rate-limit migration's sibling change in the storefront function).
-- Orders are never blocked for this — storefront stock can lag the synced
-- reality — this just lets the owner notice before packing/shipping it.
-- Existing shop_isolation policy on order_items already covers this column.

alter table order_items add column if not exists low_stock_at_order boolean not null default false;
