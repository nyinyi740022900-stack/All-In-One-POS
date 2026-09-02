-- Per-product toggle for whether it appears in the public web storefront's
-- catalog. Defaults true so every existing product keeps showing exactly as
-- before this column existed — a shop opts a product OUT of online sale.
alter table products add column if not exists sell_online boolean not null default true;
