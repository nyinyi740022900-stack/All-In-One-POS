-- Accounts Payable (money the shop owes a supplier) + Owner's Equity
-- (capital contributions/drawings) — the two remaining pieces toward a
-- Balance Sheet, after Payment Accounts + P&L.
--
-- supplier_payments mirrors credit_payments (owed *to* the shop) but for
-- money owed *by* the shop, reconciled against purchase_orders.items_total
-- for received (status='received') POs only.
--
-- equity_entries is deliberately separate from expenses — a drawing must
-- never be summed into the P&L's operating expenses.

create table if not exists supplier_payments (
  id           text primary key,
  shop_id      text not null,
  supplier_name text not null,
  supplier_id  text,
  method       text not null default 'cash',
  amount       integer not null,
  note         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  is_deleted   boolean not null default false
);
create index if not exists idx_supplier_payments_shop_updated
  on supplier_payments (shop_id, updated_at);

create table if not exists equity_entries (
  id          text primary key,
  shop_id     text not null,
  type        text not null,   -- contribution | drawing
  amount      integer not null,
  date        timestamptz not null,
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  is_deleted  boolean not null default false
);
create index if not exists idx_equity_entries_shop_updated
  on equity_entries (shop_id, updated_at);

alter table supplier_payments enable row level security;
drop policy if exists shop_isolation on supplier_payments;
create policy shop_isolation on supplier_payments
  for all to authenticated
  using (shop_id = auth_shop_id()) with check (shop_id = auth_shop_id());

alter table equity_entries enable row level security;
drop policy if exists shop_isolation on equity_entries;
create policy shop_isolation on equity_entries
  for all to authenticated
  using (shop_id = auth_shop_id()) with check (shop_id = auth_shop_id());
