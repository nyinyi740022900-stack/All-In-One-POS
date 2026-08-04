-- Payment Accounts: a named-money-account directory (KBZPay, WavePay, or
-- any custom one the owner adds) besides physical cash (Cash Register
-- stays a separate, untouched feature). No balance column here — the
-- running balance is always derived client-side from payments/
-- credit_payments/expenses rows referencing an account's id, never a
-- directly-synced absolute-value counter (same reasoning stock_levels
-- already follows).

create table if not exists payment_accounts (
  id               text primary key,
  shop_id          text not null,
  name             text not null,
  opening_balance  integer not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  is_deleted       boolean not null default false
);
create index if not exists idx_payment_accounts_shop_updated
  on payment_accounts (shop_id, updated_at);

alter table payment_accounts enable row level security;
drop policy if exists shop_isolation on payment_accounts;
create policy shop_isolation on payment_accounts
  for all to authenticated
  using (shop_id = auth_shop_id()) with check (shop_id = auth_shop_id());

-- Which payment_accounts row an expense was paid from — null means cash
-- (the implicit default every expense had before this column existed).
alter table expenses add column if not exists account_id text;
