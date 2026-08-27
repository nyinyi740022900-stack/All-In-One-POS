-- Owner-granted, per-staff-member, per-feature permissions.
--
-- One row = a StaffMembers roster member has been explicitly granted one
-- OwnerCapability (see lib/features/staff/owner_permission.dart) — e.g. a
-- trusted cashier allowed into Analytics without full Owner access.
-- Presence of a non-deleted row means granted; absence/tombstoned means
-- default-deny, so an existing staff member with zero rows keeps today's
-- exact behavior (blocked from every OwnerCapability gate) until the owner
-- opens the new permissions screen and turns something on.
--
-- Same client-enforced-only trust model as staff_members (see
-- 0026_staff_members.sql): any device signed into this shop can write here
-- via the shared shop session, so this is a workflow gate, not a
-- server-side authorization boundary between devices of one shop.
--
-- Includes hlc + received_at from creation (see 0065_sync_hlc.sql /
-- 0064_sync_received_at.sql) since both are required by the generic sync
-- engine for every synced table, not retrofitted afterward this time.

create table if not exists staff_permissions (
  id              text primary key,
  shop_id         text not null,
  staff_member_id text not null,
  capability      text not null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  received_at     timestamptz not null default clock_timestamp(),
  hlc             text,
  is_deleted      boolean not null default false
);

create unique index if not exists idx_staff_permissions_member_capability
  on staff_permissions (staff_member_id, capability);
create index if not exists idx_staff_permissions_shop_updated
  on staff_permissions (shop_id, updated_at);
create index if not exists idx_staff_permissions_shop_received
  on staff_permissions (shop_id, received_at);

drop trigger if exists trg_staff_permissions_received_at on staff_permissions;
create trigger trg_staff_permissions_received_at
  before insert or update on staff_permissions
  for each row execute function touch_received_at();

alter table staff_permissions enable row level security;
drop policy if exists shop_isolation on staff_permissions;
create policy shop_isolation on staff_permissions
  for all to authenticated
  using (shop_id = auth_shop_id()) with check (shop_id = auth_shop_id());
