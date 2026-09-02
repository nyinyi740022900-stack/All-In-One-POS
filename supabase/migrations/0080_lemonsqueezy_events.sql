-- Idempotency ledger for the lemonsqueezy-webhook Edge Function (service
-- role only; never read by a client) plus a `months` column resolved once
-- the license action runs, so a later event for the same shop can reuse it
-- when a subscription-invoice payload doesn't repeat the variant id.
create table if not exists lemonsqueezy_events (
  id text primary key,           -- '<event_name>:<data.id>', dedupes retries
  event_name text not null,
  shop_id text,
  months int,
  processed_at timestamptz not null default now(),
  raw_payload jsonb
);
create index if not exists idx_lemonsqueezy_events_shop
  on lemonsqueezy_events (shop_id, processed_at desc);

alter table lemonsqueezy_events enable row level security;
-- No client policy → service-role (this Edge Function) only.

-- Seed the 3 config keys the international checkout + webhook read via
-- VendorConfig/app_config — empty until the owner fills real values in from
-- the admin console's existing Config tab once Lemon Squeezy's store slug
-- and variant ids are known.
insert into app_config (key, value) values
  ('pay.lemonsqueezy.store_slug', ''),
  ('pay.lemonsqueezy.variant_monthly', ''),
  ('pay.lemonsqueezy.variant_yearly', '')
on conflict (key) do nothing;
