/// Named owner-only capabilities so screens/actions ask one policy instead of
/// inventing ad-hoc "is owner?" aliases that drift apart.
enum OwnerCapability {
  analytics,
  branches,
  staffAccounts,
  license,
  storefront,
  inventoryEdit,
  settingsSensitive,
}

/// Thin central policy for owner gates + which mutations need PIN re-auth.
///
/// The owner always passes every capability. A staff member passes only a
/// capability the owner has explicitly granted them (see
/// `StaffRepository.watchGrantedCapabilities` / `StaffPermissions` in
/// tables.dart) — [grantedCapabilities] defaults to empty, so an existing
/// staff member with no grants yet keeps the exact pre-permissions-feature
/// behavior (blocked from every `OwnerCapability` gate).
class OwnerPermissionPolicy {
  const OwnerPermissionPolicy();

  bool allows(
    OwnerCapability capability, {
    required bool isEffectiveOwner,
    Set<OwnerCapability> grantedCapabilities = const {},
  }) {
    if (isEffectiveOwner) return true;
    return grantedCapabilities.contains(capability);
  }

  /// True when the capability is a sensitive mutate path that should prompt
  /// for the owner PIN (when one is set) before proceeding.
  bool requiresPinReauth(OwnerCapability capability) {
    switch (capability) {
      case OwnerCapability.branches:
      case OwnerCapability.staffAccounts:
      case OwnerCapability.settingsSensitive:
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
