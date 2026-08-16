-- Optional reason recorded when an admin declines a pending license
-- request. `status` on license_requests is a plain text column with no
-- CHECK constraint (0010_license_requests.sql), so 'rejected' is already a
-- legal value — this migration only adds the reason column.
alter table license_requests
  add column if not exists reject_reason text;
