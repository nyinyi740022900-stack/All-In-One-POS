# App Privacy nutrition labels (App Store Connect)

Declare data linked to the user / used for app functionality. All In One POS does **not** track across apps (ATT not used).

## Data types to declare

| Type | Collected? | Linked to user? | Used for tracking? | Purposes |
|---|---|---|---|---|
| Contact Info — Email Address | Yes (online login) | Yes | No | App Functionality |
| Identifiers — Device ID | Yes (license binding) | Yes | No | App Functionality |
| Purchases — Other Purchase History | Yes (license/plan metadata) | Yes | No | App Functionality |
| User Content — Photos or Videos | Yes (if user attaches proofs/images) | Yes | No | App Functionality |
| User Content — Other User Content | Yes (shop catalog, sales you enter) | Yes | No | App Functionality |
| Diagnostics — Crash Data | Yes (if Sentry DSN configured) | No | No | App Functionality |
| Diagnostics — Performance Data | Optional via Sentry | No | No | App Functionality |

## Not collected for advertising
No advertising identifiers, no third-party ads.

## Permissions (Info.plist) — already set
- Camera (barcodes / QR)
- Bluetooth (receipt printer)
- Photo Library (attachments)
- Notifications (local: referral / storefront orders)

## Encryption
`ITSAppUsesNonExemptEncryption` = **false** in Info.plist (HTTPS + standard crypto only for license verify). Still answer the Connect export-compliance question consistently.
