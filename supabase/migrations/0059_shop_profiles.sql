-- Mirrors ShopProfile's contact fields (name/phone/address) so the admin
-- console can show them without a shop having published a public
-- Storefront. One row per shop (id == shop_id) — the client's own local
-- copy (AppSettings KV) stays authoritative; this is a write-through sync
-- target populated whenever ShopProfileScreen saves.
create table if not exists shop_profiles (
  id         text primary key,
  shop_id    text not null,
  name       text not null,
  phone      text,
  address    text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false
);
create index if not exists idx_shop_profiles_shop_updated
  on shop_profiles (shop_id, updated_at);

alter table shop_profiles enable row level security;
drop policy if exists shop_isolation on shop_profiles;
create policy shop_isolation on shop_profiles
  for all to authenticated
  using (shop_id = auth_shop_id()) with check (shop_id = auth_shop_id());
