-- Recurring expense templates (rent, wages, etc.) the owner sets up once so
-- they don't have to retype the same category/amount every month.
-- Deliberately NOT auto-generated — the owner quick-fills a new `expenses`
-- row from one of these each month via the app, reviewing the amount/date
-- before saving. `active` lets a seasonal cost be paused without deleting it.

create table if not exists recurring_expenses (
  id          text primary key,
  shop_id     text not null,
  category    text not null,
  amount      integer not null,
  note        text,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  is_deleted  boolean not null default false
);
create index if not exists idx_recurring_expenses_shop_updated
  on recurring_expenses (shop_id, updated_at);

alter table recurring_expenses enable row level security;
drop policy if exists shop_isolation on recurring_expenses;
create policy shop_isolation on recurring_expenses
  for all to authenticated
  using (shop_id = auth_shop_id()) with check (shop_id = auth_shop_id());
