-- Supports the new "has this device already used its trial?" lookup in
-- signup_shop (activate/index.ts) — a partial index on exactly the rows that
-- query filters (trial-plan licenses with a non-null device_id).
create index if not exists idx_licenses_trial_device
  on licenses (device_id)
  where plan = 'trial' and device_id is not null;
