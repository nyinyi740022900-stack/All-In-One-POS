# Play Data safety form (answers)

Declare collection for app functionality. No ads / no cross-app tracking.

| Data type | Collected? | Shared? | Purpose |
|---|---|---|---|
| Email address | Yes (online login) | No (processor: auth host) | App functionality |
| Device or other IDs | Yes (license binding) | No | App functionality |
| Photos | Yes (if user attaches proofs/images) | No | App functionality |
| Other user-generated content | Yes (shop catalog, sales) | Sync to our backend for the shop | App functionality |
| Crash logs | Yes — Sentry DSN configured in `env.local.json` (`SENTRY_DSN`) | Crash vendor (Sentry) | Analytics / stability |

**Security practices:** Data encrypted in transit (HTTPS). Online account owners can delete their account in-app (Settings → Shop Login → Delete account). Users may also contact Support.

**Premium / payments:** Not sold through Google Play Billing. External license for physical retail POS software — declare accordingly in the Payments / subscriptions questionnaire.

Permissions used in-app: Camera, Bluetooth, Photos/media, Notifications, Internet.
