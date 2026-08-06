-- Phase 2 (drop-window step A): move table to a legacy name.
-- Apply only after the read-only quarantine observation window is complete.

alter table if exists staff_members rename to staff_members_legacy;

alter index if exists idx_staff_members_shop_updated
  rename to idx_staff_members_legacy_shop_updated;
