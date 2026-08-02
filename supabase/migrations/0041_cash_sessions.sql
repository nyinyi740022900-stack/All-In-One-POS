-- Cash-drawer sessions: an owner/cashier declares an opening float at the
-- start of the day (or shift) and counts the drawer at the end, recording a
-- closing amount. The app computes what the drawer *should* hold (opening +
-- cash sales + cash credit-repayments − cash expenses, all within
-- [opened_at, closed_at)) so a till shortage/overage shows up immediately
-- instead of weeks later. closed_at null means the session is still open.

create table if not exists cash_sessions (
  id              text primary key,
  shop_id         text not null,
  opened_at       timestamptz not null,
  opening_amount  integer not null,
  closed_at       timestamptz,
  closing_amount  integer,
  note            text,
  device_id       text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  is_deleted      boolean not null default false
);
create index if not exists idx_cash_sessions_shop_opened
  on cash_sessions (shop_id, opened_at);
create index if not exists idx_cash_sessions_shop_updated
  on cash_sessions (shop_id, updated_at);

alter table cash_sessions enable row level security;
drop policy if exists shop_isolation on cash_sessions;
create policy shop_isolation on cash_sessions
  for all to authenticated
  using (shop_id = auth_shop_id()) with check (shop_id = auth_shop_id());
