# All In One POS — account Premium admin

Live URL: https://admin.allinonepos.app. The local account-Premium console
requires migrations0094/0095 and matching functions; deploy only after staging
rehearsal. The current local code must not be deployed ahead of its backend.

The console is a separate Flutter Web entry point. Privileged actions require
an authenticated admin and run in the admin Edge Function. Service-role/API
keys remain server-side.

## Keep these modules

- Dashboard: shop counts, Premium/at-risk status, pending payments and manual
  Myanmar revenue. Gateway currencies are not added to kyat revenue.
- Inbox: account-owned KBZPay/WavePay requests, proof inspection, atomic
  Confirm/Decline. Duplicate confirmation cannot add a second term.
- Shops: search and inspect shop authority, account status, subscription and
  up to three active devices. Renew monthly/yearly only by exact shop ID.
  Release a device, recover account access, manage staff bans and archive or
  restore an abandoned shop. A verified owner account is required for renewal.
- Payments: settled requests and subscription-renewal records. A manual admin
  extension is not proof of money received and is excluded from revenue.
- Settings: public KBZPay/WavePay instructions, support contact and monthly/
  yearly Lemon Squeezy variant IDs. Variant IDs must be positive integers.
  API/webhook secrets are never entered in this public table/editor.

## Retired controls

No customer key creation, offline codes, Online/Offline tiers, purchased extra
slots, standalone Licensing menu or unbound Buy Now URL/store-slug editor.
Renewals belong to a shop with an owner account, not a public device reference.
Legacy data remains audit evidence; removing an editor is not deleting rows.

## Development and delivery

Run with lib/admin/admin_main.dart and the shared env.local.json. Never expose
its contents or commit it. Use tool/build_web.sh admin to create the correct
admin page metadata. Follow .agents/skills/deploy/SKILL.md for coordinated
backend/Vercel deployment and project relinking, rather than a raw web build.

## Remaining rollout checks

Identify a POS staging project, rehearse0094/0095 and session RLS, verify the
trusted deleted-shop trial backfill, then test account signup, explicit trial,
manual renewal, duplicate payment, ownerless renewal refusal, fourth-device
refusal, staff permissions and archive/restore. Coordinate with the current
social-auth work before freezing the shared checkout or deploying0096.

Verify monthly/yearly provider variants and signed webhook delivery separately.
Saving API/store secrets alone does not make checkout operational. No live
charge is authorized by this README.
