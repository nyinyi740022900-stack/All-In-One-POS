-- Owner-managed block-list for the public storefront: a phone number the
-- owner blocks (after a scam/spam order) can no longer place new orders on
-- that shop's storefront. Online-only config (mirrors `storefronts` itself,
-- which is also not a synced Drift entity) — the owner manages it from the
-- signed-in app; the anonymous `storefront` function checks it with the
-- service role, which bypasses RLS.

create table if not exists storefront_blocklist (
  id         uuid primary key default gen_random_uuid(),
  shop_id    text not null,
  phone      text not null,
  reason     text,
  created_at timestamptz not null default now()
);
create unique index if not exists idx_storefront_blocklist_shop_phone
  on storefront_blocklist (shop_id, phone);

alter table storefront_blocklist enable row level security;
drop policy if exists shop_isolation on storefront_blocklist;
create policy shop_isolation on storefront_blocklist
  for all to authenticated
  using (shop_id = auth_shop_id()) with check (shop_id = auth_shop_id());
