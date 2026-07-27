-- Storefront anti-spam: track submit_order attempts per (shop, IP) so the
-- Edge Function can throttle repeat/bot submissions. This is NOT a synced
-- Drift entity — only the storefront function (service role) ever touches
-- it, so RLS stays enabled with zero policies (default-deny for anon/
-- authenticated; the service role bypasses RLS entirely).

create table if not exists storefront_order_attempts (
  id uuid primary key default gen_random_uuid(),
  shop_id text not null,
  ip text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_storefront_order_attempts_lookup
  on storefront_order_attempts (shop_id, ip, created_at);

alter table storefront_order_attempts enable row level security;
