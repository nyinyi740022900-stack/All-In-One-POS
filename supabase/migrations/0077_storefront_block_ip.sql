-- Storefront block-list is IP-based (scam/harassment), not phone.
-- Phone-number rows cannot match an IP, so they are dropped before rename.
-- customer_ip is stamped on storefront orders so the owner can block that
-- address from the order sheet.

delete from storefront_blocklist;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'storefront_blocklist'
      and column_name = 'phone'
  ) then
    alter table storefront_blocklist rename column phone to ip;
  end if;
end $$;

drop index if exists idx_storefront_blocklist_shop_phone;

create unique index if not exists idx_storefront_blocklist_shop_ip
  on storefront_blocklist (shop_id, ip);

comment on column storefront_blocklist.ip is
  'Normalized client IP blocked from submit_order on this shop.';

alter table orders add column if not exists customer_ip text;

comment on column orders.customer_ip is
  'Storefront client IP (last X-Forwarded-For hop). Null for POS/manual orders.';
