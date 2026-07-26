-- Customer directory — enter a name/phone/address once and reuse it on
-- every future invoice/order instead of retyping. `sales`/`orders`/
-- `credit_payments` link here via a nullable `customer_id`, but keep their
-- own name/phone snapshot too — a directory rename never retroactively
-- changes what already printed on an old receipt.

create table if not exists customers (
  id         text primary key,
  shop_id    text not null,
  name       text not null,
  phone      text,
  address    text,
  township   text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false
);
create index if not exists idx_customers_shop_updated
  on customers (shop_id, updated_at);

alter table customers enable row level security;
drop policy if exists shop_isolation on customers;
create policy shop_isolation on customers
  for all to authenticated
  using (shop_id = auth_shop_id()) with check (shop_id = auth_shop_id());

alter table sales add column if not exists customer_id text;
alter table orders add column if not exists customer_id text;
alter table credit_payments add column if not exists customer_id text;

create index if not exists idx_sales_customer on sales (customer_id)
  where customer_id is not null;
create index if not exists idx_orders_customer on orders (customer_id)
  where customer_id is not null;
create index if not exists idx_credit_payments_customer
  on credit_payments (customer_id) where customer_id is not null;
