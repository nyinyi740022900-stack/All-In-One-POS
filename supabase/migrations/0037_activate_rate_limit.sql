-- Rate-limit the `activate` Edge Function's key-guessing surface (the
-- `activate` action accepts an arbitrary `key` string and reports whether it
-- was valid — exactly the shape a brute-force script would exploit). Same
-- pattern as `storefront_order_attempts` (0033): a local-only table, RLS
-- enabled with zero policies, only the service role (which bypasses RLS)
-- ever touches it.

create table if not exists activate_attempts (
  id         uuid primary key default gen_random_uuid(),
  ip         text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_activate_attempts_lookup
  on activate_attempts (ip, created_at);

alter table activate_attempts enable row level security;
