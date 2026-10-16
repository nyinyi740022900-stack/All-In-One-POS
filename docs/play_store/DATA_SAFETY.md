# Play Data safety form (answers)

Mirrors the public privacy policy at https://legal.allinonepos.app
(deployed and verified 16 Oct 2026) — change both together. Migration 0103
and the updated activate function were deployed before the policy. Declare collection for app
functionality. No ads, no cross-app tracking, nothing sold.

| Data type | Collected? | Shared? | Purpose |
|---|---|---|---|
| Email address | Yes — online account; staff invites; Google sign-in returns it | No (processors: Supabase auth, Resend email) | Account management, App functionality |
| User IDs | Yes — account ID; Google account ID if Google sign-in | No | Account management |
| Name / Phone number / Address | Yes — customers a shop records, and web-storefront orders (name, phone, delivery address) | No — stored for that shop only | App functionality |
| Purchase history | Yes — Premium plan and payment records | No (processors: Lemon Squeezy, MyanMyanPay) | App functionality, fraud prevention |
| Photos | Yes — product photos, logos, transfer screenshots (expense receipt photos stay on device) | No | App functionality |
| Other user-generated content | Yes — shop catalogue, sales, orders, expenses | Synced to our backend for that shop | App functionality |
| Device or other IDs | Yes — device ID for the 3-device limit and Premium checks; web-storefront orders record the customer's IP to block abuse | No | App functionality, fraud prevention |
| Crash logs / diagnostics | Yes — Sentry | Processor (Sentry) | App stability |

Processors (service providers, not "sharing" in Play's sense): Supabase,
Vercel, Google (sign-in only), Lemon Squeezy, MyanMyanPay, Resend, Sentry.

**Security practices:** Data encrypted in transit (HTTPS).

**Account deletion:** Yes, users can request deletion.
- In app: Shop → Account → Delete account (password, or Google re-auth).
- **Delete account URL** (Play Console → App content → Data deletion):
  `https://legal.allinonepos.app/#delete-account` — the off-app path is
  Viber 09740022900, deleted within 30 days.
- Deleted: account, staff logins, owned shops' cloud data and uploaded
  files (incl. customers' payment screenshots — the `activate` function's
  `deleteShopFiles`). Kept: Premium subscription/payment records, the
  owner's own Premium payment screenshots (`_admin/`) — declare these as
  retained for legal/fraud-prevention reasons. Trial-claim records are deleted
  with the account; the once-only trial limit applies per existing owner account.

**Premium / payments:** Not sold through Google Play Billing. External
licence for physical retail POS software — declare accordingly in the
Payments / subscriptions questionnaire. The store build ships with no
purchase UI (`COMMERCE_UI` off).

Permissions used in-app: Camera, Bluetooth, Photos/media, Notifications, Internet.
