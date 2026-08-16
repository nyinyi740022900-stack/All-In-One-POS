-- Rate-limit the storefront function's submit_license_request action. Same
-- shape as activate_attempts (0037): this flow has no shop_id to key on (a
-- renewal request identifies itself only by device_id, which we don't trust
-- as a rate-limit key since it's exactly the field an abuser would vary) —
-- so, like activate_attempts, key on IP alone.

create table if not exists license_request_attempts (
  id         uuid primary key default gen_random_uuid(),
  ip         text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_license_request_attempts_lookup
  on license_request_attempts (ip, created_at);

alter table license_request_attempts enable row level security;
-- RLS enabled, zero policies — default-deny for anon/authenticated; only
-- the storefront function's service-role client ever touches this table.
