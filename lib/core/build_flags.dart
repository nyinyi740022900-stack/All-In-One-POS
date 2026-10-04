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
/// use account sign-in for access to an existing entitlement. This guard
/// does not establish an IAP exemption: 3.1.3(b) requires equivalent IAP.
/// A no-IAP submission must separately qualify, for example under 3.1.3(f)
/// as a free companion to a paid web tool. Review notes track that gate.
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
/// where to go to pay. Account sign-in and checking an existing entitlement
/// remain available; customer key entry is retired.
const bool kCommerceUiEnabled =
    bool.fromEnvironment('COMMERCE_UI', defaultValue: false);
