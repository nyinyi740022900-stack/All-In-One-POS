-- Suppliers directory + lightweight purchase-order tracking (what was
-- ordered from whom, at what cost) — NOT procurement automation, see
-- PROJECT_SPEC.md §1.2. Receiving a PO reuses the existing restock
-- machinery client-side (InventoryRepository.adjustStock), so it writes to
-- the already-existing stock_levels/stock_movements tables, unchanged here.

create table if not exists suppliers (
  id          text primary key,
  shop_id     text not null,
  name        text not null,
  phone       text,
  address     text,
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  is_deleted  boolean not null default false
);
create index if not exists idx_suppliers_shop_updated
  on suppliers (shop_id, updated_at);

create table if not exists purchase_orders (
  id             text primary key,
  shop_id        text not null,
  po_no          text not null,
  supplier_id    text,
  supplier_name  text not null,
  status         text not null default 'open',
  items_total    integer not null default 0,
  note           text,
  received_at    timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  is_deleted     boolean not null default false
);
create index if not exists idx_purchase_orders_shop_updated
  on purchase_orders (shop_id, updated_at);

create table if not exists purchase_order_items (
  id             text primary key,
  shop_id        text not null,
  po_id          text not null,
  product_id     text not null,
  name_snapshot  text not null,
  qty            integer not null,
  unit_cost      integer not null,
  line_total     integer not null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  is_deleted     boolean not null default false
);
create index if not exists idx_purchase_order_items_shop_updated
  on purchase_order_items (shop_id, updated_at);
create index if not exists idx_purchase_order_items_po
  on purchase_order_items (po_id);

alter table suppliers enable row level security;
drop policy if exists shop_isolation on suppliers;
create policy shop_isolation on suppliers
  for all to authenticated
  using (shop_id = auth_shop_id()) with check (shop_id = auth_shop_id());

alter table purchase_orders enable row level security;
drop policy if exists shop_isolation on purchase_orders;
create policy shop_isolation on purchase_orders
  for all to authenticated
  using (shop_id = auth_shop_id()) with check (shop_id = auth_shop_id());

alter table purchase_order_items enable row level security;
drop policy if exists shop_isolation on purchase_order_items;
create policy shop_isolation on purchase_order_items
  for all to authenticated
  using (shop_id = auth_shop_id()) with check (shop_id = auth_shop_id());
