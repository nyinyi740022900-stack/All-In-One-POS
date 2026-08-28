-- Cash physically added to the till mid-session — e.g. the owner topping up
-- the drawer from their own pocket to cover a large cash-out (a supplier
-- paid in cash). Separate from equity_entries (that's a balance-sheet
-- concept and deliberately never touches Cash Register math). No
-- session_id column — matched by created_at falling inside the open
-- session's [opened_at, closed_at) window, the same convention
-- computeExpectedCash already uses for expenses/supplier_payments.
--
-- Includes hlc + received_at from creation (see 0065_sync_hlc.sql /
-- 0064_sync_received_at.sql), same as staff_permissions (0072).

create table if not exists cash_top_ups (
  id          text primary key,
  shop_id     text not null,
  amount      integer not null,
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  received_at timestamptz not null default clock_timestamp(),
  hlc         text,
  is_deleted  boolean not null default false
);

create index if not exists idx_cash_top_ups_shop_created
  on cash_top_ups (shop_id, created_at);
create index if not exists idx_cash_top_ups_shop_updated
  on cash_top_ups (shop_id, updated_at);
create index if not exists idx_cash_top_ups_shop_received
  on cash_top_ups (shop_id, received_at);

drop trigger if exists trg_cash_top_ups_received_at on cash_top_ups;
create trigger trg_cash_top_ups_received_at
  before insert or update on cash_top_ups
  for each row execute function touch_received_at();

alter table cash_top_ups enable row level security;
drop policy if exists shop_isolation on cash_top_ups;
create policy shop_isolation on cash_top_ups
  for all to authenticated
  using (shop_id = auth_shop_id()) with check (shop_id = auth_shop_id());
