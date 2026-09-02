-- Seeds `pay.lemonsqueezy.buy_now_url` — the product's shared hosted-checkout
-- URL (Lemon Squeezy dashboard: product's "Share" button / a variant page's
-- embedded `buy_now_url`). The client opens this directly with
-- `checkout[custom][shop_id]`/`device_id` appended; Lemon Squeezy's own
-- checkout page shows the Monthly/Yearly picker for a multi-variant product.
--
-- This replaces building a URL from `pay.lemonsqueezy.variant_monthly`/
-- `variant_yearly` client-side — confirmed live that Lemon Squeezy's
-- `/checkout/buy/[numeric_variant_id]` route 404s for a multi-variant
-- subscription product; only a UUID checkout link (this one) resolves.
-- Those two variant-id keys are kept and still used server-side by
-- `lemonsqueezy-webhook` to resolve months from a purchased variant.
--
-- ON CONFLICT DO NOTHING: a later `set_config`/admin action may already own
-- this key by the time this migration runs elsewhere (e.g. a fresh
-- environment) — never clobber a real value with the empty seed.
insert into app_config (key, value)
values ('pay.lemonsqueezy.buy_now_url', '')
on conflict (key) do nothing;
