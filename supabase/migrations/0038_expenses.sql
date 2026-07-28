-- Non-inventory operating expenses (rent, utilities, staff wages, transport,
-- packaging, …) — separate from restock cost, which already flows into
-- Analytics as cost-of-goods-sold via products.cost_price/stock_lots.
-- Recording a restock here too would double-count it against gross profit.
--
-- Deliberately has NO receipt-photo column: the app stores that as a local
-- file path only (see Expenses in lib/data/local/tables.dart) and never
-- uploads it, to keep this feature off the ongoing cloud-egress/data-cost
-- path entirely.

create table if not exists expenses (
  id         text primary key,
  shop_id    text not null,
  category   text not null,
  amount     integer not null,
  date       timestamptz not null,
  note       text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false
);
create index if not exists idx_expenses_shop_date on expenses (shop_id, date);
create index if not exists idx_expenses_shop_updated
  on expenses (shop_id, updated_at);

alter table expenses enable row level security;
drop policy if exists shop_isolation on expenses;
create policy shop_isolation on expenses
  for all to authenticated
  using (shop_id = auth_shop_id()) with check (shop_id = auth_shop_id());
