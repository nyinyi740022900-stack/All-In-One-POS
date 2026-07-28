-- Which physical device rang a sale up (Sales.device_id — same stable id
-- already used for license activation), plus owner-editable friendly names
-- for devices so a raw UUID can show as something meaningful on an invoice
-- regardless of which device is doing the viewing.

alter table sales add column if not exists device_id text;

create table if not exists device_labels (
  id         text primary key,
  shop_id    text not null,
  device_id  text not null,
  label      text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_deleted boolean not null default false
);
create index if not exists idx_device_labels_shop_device
  on device_labels (shop_id, device_id);
create index if not exists idx_device_labels_shop_updated
  on device_labels (shop_id, updated_at);

alter table device_labels enable row level security;
drop policy if exists shop_isolation on device_labels;
create policy shop_isolation on device_labels
  for all to authenticated
  using (shop_id = auth_shop_id()) with check (shop_id = auth_shop_id());
