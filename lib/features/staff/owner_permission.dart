/// Named owner-only capabilities so screens/actions ask one policy instead of
/// inventing ad-hoc "is owner?" aliases that drift apart.
enum OwnerCapability {
  analytics,
  branches,
  staffAccounts,
  license,
  storefront,
  syncIssuesDiscard,
  inventoryEdit,
  settingsSensitive,
}

/// Thin central policy for owner gates + which mutations need PIN re-auth.
///
/// Today every capability still collapses to effective-owner (no behavior
/// change). Naming them here makes future per-capability rules and call-site
/// audits possible without ripping out Riverpod/`OwnerOnlyGate`.
class OwnerPermissionPolicy {
  const OwnerPermissionPolicy();

  bool allows(OwnerCapability capability, {required bool isEffectiveOwner}) {
    // All listed capabilities are owner-only today.
    return isEffectiveOwner;
  }

  /// True when the capability is a sensitive mutate path that should prompt
  /// for the owner PIN (when one is set) before proceeding.
  bool requiresPinReauth(OwnerCapability capability) {
    switch (capability) {
      case OwnerCapability.branches:
      case OwnerCapability.staffAccounts:
      case OwnerCapability.settingsSensitive:
      case OwnerCapability.syncIssuesDiscard:
        return true;
      case OwnerCapability.analytics:
      case OwnerCapability.license:
      case OwnerCapability.storefront:
      case OwnerCapability.inventoryEdit:
        return false;
    }
  }
}

const ownerPermissionPolicy = OwnerPermissionPolicy();
