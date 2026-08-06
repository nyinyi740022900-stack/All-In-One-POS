-- Phase 1 (read-only quarantine): keep historical reads, block all writes.
-- This is reversible and intended to run ahead of final retirement.

alter table if exists staff_members enable row level security;

drop policy if exists shop_isolation on staff_members;
drop policy if exists shop_isolation_read_only on staff_members;

create policy shop_isolation_read_only on staff_members
  for select to authenticated
  using (shop_id = auth_shop_id());
