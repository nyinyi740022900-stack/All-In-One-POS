-- Staff accountability, phase 1: named staff profiles.
--
-- A lightweight identity tag (name + PIN), not a real login account — no
-- Supabase Auth user, no server-side enforcement. Every device under a shop
-- still authenticates as the same shop user; this just lets a sale record
-- WHICH staff member rang it up (Sales.staff_id), and lets the owner ask
-- "who am I" when switching a device into Staff mode instead of a single
-- shared PIN. Synced like any other shop entity so the roster is the same
-- on every device.

create table if not exists staff_members (
  id         text primary key,
  shop_id    text not null,
  name       text not null,
  pin        text not null,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false
);
create index if not exists idx_staff_members_shop_updated
  on staff_members (shop_id, updated_at);

alter table staff_members enable row level security;
drop policy if exists shop_isolation on staff_members;
create policy shop_isolation on staff_members
  for all to authenticated
  using (shop_id = auth_shop_id()) with check (shop_id = auth_shop_id());
