/// Subscription plan. `free` is the always-on, never-expiring plan that
/// backs core POS features (Sell/Inventory/etc.) for a shop with no active
/// key/subscription — see `computeLicenseStatus`'s special case below.
enum LicensePlan { trial, monthly, yearly, free }

/// How the app should behave right now given the license.
enum LicenseStatusKind {
  /// No license activated yet.
  none,

  /// Active and paid.
  active,

  /// Expired but inside the offline grace window — still fully usable.
  grace,

  /// Past grace — read-only (can view, cannot finalize sales).
  expired,
}

/// Immutable snapshot of license state, derived purely from dates so it can be
/// computed offline and unit-tested without any I/O.
class LicenseStatus {
  final LicenseStatusKind kind;
  final LicensePlan? plan;
  final DateTime? expiresAt;

  /// Whole days of grace remaining (0 when not in grace).
  final int graceDaysLeft;

  const LicenseStatus({
    required this.kind,
    this.plan,
    this.expiresAt,
    this.graceDaysLeft = 0,
  });

  static const none = LicenseStatus(kind: LicenseStatusKind.none);

  /// Sales can be finalized only while active or in grace.
  bool get canSell =>
      kind == LicenseStatusKind.active || kind == LicenseStatusKind.grace;

  bool get isReadOnly => !canSell;
}

/// Computes the effective status.
///
/// - active:  `now <= expiresAt`
/// - grace:   `expiresAt < now <= expiresAt + graceDays`
/// - expired: beyond grace
/// - none:    not activated / no expiry
LicenseStatus computeLicenseStatus({
  required DateTime? expiresAt,
  required DateTime now,
  LicensePlan? plan,
  bool activated = true,
  int graceDays = 7,
}) {
  if (!activated || expiresAt == null) return LicenseStatus.none;

  // The Free plan never expires — core POS features (Sell/Inventory/etc.)
  // stay usable forever with no key/subscription. Only `isPremium` (derived
  // separately, see LicenseState) distinguishes Free from a paid plan; this
  // function only ever answers "can this shop sell right now."
  if (plan == LicensePlan.free) {
    return LicenseStatus(
      kind: LicenseStatusKind.active,
      plan: plan,
      expiresAt: expiresAt,
    );
  }

  if (!now.isAfter(expiresAt)) {
    return LicenseStatus(
      kind: LicenseStatusKind.active,
      plan: plan,
      expiresAt: expiresAt,
    );
  }

  final graceEnd = expiresAt.add(Duration(days: graceDays));
  if (!now.isAfter(graceEnd)) {
    // Round up so a partial day still counts as a day of grace.
    final left = graceEnd.difference(now).inHours / 24.0;
    return LicenseStatus(
      kind: LicenseStatusKind.grace,
      plan: plan,
      expiresAt: expiresAt,
      graceDaysLeft: left.ceil(),
    );
  }

  return LicenseStatus(
    kind: LicenseStatusKind.expired,
    plan: plan,
    expiresAt: expiresAt,
  );
}
