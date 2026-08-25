/// Build-time switches that change what this binary is *allowed* to show,
/// as opposed to runtime state (a license, a role, a feature flag).
library;

/// Whether this build may show purchase, pricing, or "buy/renew Premium"
/// UI at all.
///
/// **Defaults to `false` on purpose.** An App Store / Play build that
/// forgets to pass the define is then still compliant with App Store
/// Review Guideline 3.1.1, which bans "buttons, external links, or other
/// calls to action that direct customers to purchasing mechanisms other
/// than in-app purchase". That ban is lifted only on the United States
/// storefront (2025 Epic injunction) — never in Myanmar, our actual
/// market — so the store build has to carry no commerce UI whatsoever and
/// lean on guideline 3.1.3(b) *Multiplatform Services* instead: the
/// service exists on Android and on the web, the user signs in / redeems a
/// license they already hold, and nothing is sold inside the iOS app.
///
/// Only the direct-install APK (and dev runs) turn it on, explicitly:
///
/// ```
/// flutter build apk --release \
///   --dart-define-from-file=env.local.json --dart-define=COMMERCE_UI=true
/// ```
///
/// ⚠️ Do NOT put `COMMERCE_UI` in `env.local.json` — that file is passed to
/// the App Store build too (`--dart-define-from-file`), which would switch
/// the commerce UI back on in exactly the build that must not have it.
///
/// What this gates is listed in PROJECT_SPEC §12 (2026-08-25 entry); the
/// short version is: anything that names a price, or that tells the owner
/// where to go to pay. License-key entry, "Check for renewal", and the
/// free trial are NOT commerce — they stay in every build.
const bool kCommerceUiEnabled =
    bool.fromEnvironment('COMMERCE_UI', defaultValue: false);
