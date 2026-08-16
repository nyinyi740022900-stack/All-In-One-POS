# All In One POS — Admin dashboard (Flutter Web)

**Live:** https://allinonepos-admin.vercel.app

Vendor console for managing licenses. Separate from the POS app: its own entry
point (`admin_main.dart`), tree-shaken out of the mobile build. All privileged
work goes through the `admin` Edge Function (service role stays server-side).

## What it does
- **Licenses** — every key: shop, plan, status, expiry, bound device.
- **Requests** — self-service subscribe/renew requests customers submit
  in-app (KBZPay/WavePay + a payment screenshot); **Issue key** calls
  `fulfill_request`, which extends the shop's existing license when the
  request carries a `shop_id` (or matches by `device_id` for older requests
  with none), or mints a brand-new one otherwise.
- **Generate key** — mint a key for a shop (`create_license`).
- **Referrals** — commissions grouped by referrer (lifetime earned + payment
  count) with **Apply credit** (redeems the referrer's balance into license
  months via `apply_referral_credit`), plus the raw referral links. Commission
  rate is editable under **Config** (`referral.rate`, `referral.enabled`).

## One-time setup

1. **Deploy the backend function**
   ```bash
   supabase functions deploy admin
   ```
   (Also apply migrations first if not done: `supabase db push`.)

2. **Create an admin user** (Supabase Dashboard → Authentication → Add user,
   or SQL), then grant the admin role in SQL Editor:
   ```sql
   update auth.users
   set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
                           || '{"role":"admin"}'::jsonb
   where email = 'admin@yourcompany.com';
   ```
   The `admin` function rejects anyone without `app_metadata.role = 'admin'`.

## Run locally
```bash
flutter run -d chrome -t lib/admin/admin_main.dart \
  --dart-define-from-file=env.local.json
```

## Deploy the dashboard (Vercel)
Hosted at **https://allinonepos-admin.vercel.app** (Vercel project `allinonepos-admin`,
scope `nyi-nyi-s-projects1`). To ship a new build:
```bash
flutter build web -t lib/admin/admin_main.dart \
  --dart-define-from-file=env.local.json --no-web-resources-cdn
cd build/web
# SPA fallback so deep links resolve to index.html:
cat > vercel.json <<'JSON'
{ "routes": [ { "handle": "filesystem" }, { "src": "/.*", "dest": "/index.html" } ] }
JSON
vercel deploy --prod --yes --scope nyi-nyi-s-projects1
```
Only the anon key ships in the web bundle (safe — the `admin` function enforces
the admin check). Never put the service-role key in this app.
