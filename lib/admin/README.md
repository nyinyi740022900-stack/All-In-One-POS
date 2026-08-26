# All In One POS — Admin dashboard (Flutter Web)

**Live:** https://admin.allinonepos.app

Vendor console for licenses, payments, and shop support. Separate from the
POS app: its own entry point (`admin_main.dart`), tree-shaken out of the
mobile build. All privileged work goes through the `admin` Edge Function
(service role stays server-side).

## Modules (sidebar)

- **Dashboard** — shop / Premium / at-risk counts, pending inbox, paid
  revenue this month, expiring-in-7-days. Monthly revenue bar (fulfilled
  `license_requests` only — complimentary admin extends are not counted as
  income) and a plan mix (paid / trial / free / expired).
- **Inbox** — pending KBZPay/WavePay requests with screenshot; Confirm /
  Decline. Lands here automatically when anything is waiting.
- **Shops** — search by name, email, phone, or App Reference ID, then a
  360° panel: extend by email vs device, allow extra devices (no key), reset a phone, offline code,
  Viber, generate key, password-reset link, unlink staff, restore a banned
  login.
- **Payments** — settled requests + license activity history.
- **Licensing** — Viber-paste extend only: email or App Reference ID
  (two separate cards so an email cannot be pasted into a device field).
  Both find a shop and add months to **every** device on it. Reset a
  phone, allow extra devices, mint a key, or send an offline code from **Shops**.
- **Referrals** — commissions grouped by referrer with **Apply credit**,
  plus raw referral links. Rate/toggle live under Settings
  (`referral.rate`, `referral.enabled`).
- **Settings** — KBZPay/WavePay pay-to, Support Viber, prices.

Confirming a payment calls `fulfill_request`, which extends the shop's
existing license when the request carries a `shop_id` (or matches by
`device_id` for older requests with none), or mints a brand-new one
otherwise.

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
Hosted at **https://admin.allinonepos.app** (Vercel project `allinonepos-admin`,
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

Password-reset links are generated server-side (`auth.admin.generateLink`) and
copied onto Viber — this console does not send recovery email (same reason
shop signup is `email_confirm: true`: SMTP would strand a shop).
