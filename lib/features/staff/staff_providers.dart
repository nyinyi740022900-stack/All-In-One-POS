import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/database.dart';
import '../account/account_providers.dart';
import '../account/branch_providers.dart';
import '../account/branch_repository.dart';
import '../printing/printing_providers.dart';
import 'owner_permission.dart';
import 'staff_repository.dart';

/// Two device-local operating modes, not synced — set by the owner before
/// handing the phone to staff. Kept deliberately simple: 'staff' (Sell +
/// Orders only) and 'owner' (everything). A finer-grained role tier was tried
/// and folded back into this — extra roles added complexity without a clear
/// use case for a small shop.
const staffRoles = <String>['staff', 'owner'];

/// Single snapshot of "who is this device acting as right now?" consumed by
/// UI/permission gates, so branch/role/account checks don't drift apart.
class SessionScope {
  final String shopId;
  final String localRole;
  final String? backendRole;
  final String effectiveRole;
  final String? activeStaffId;
  final BranchSwitchRecoveryState? switchState;

  const SessionScope({
    required this.shopId,
    required this.localRole,
    required this.backendRole,
    required this.effectiveRole,
    required this.activeStaffId,
    required this.switchState,
  });

  bool get isEffectiveOwner => effectiveRole == 'owner';
  bool get hasPendingBranchSwitch => switchState != null;
}

final staffRoleProvider = StreamProvider<String>((ref) {
  final shopId = ref.watch(shopIdProvider);
  return ref.watch(settingsRepositoryProvider).watchStaffRole(shopId);
});

final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return StaffRepository(
    ref.watch(databaseProvider),
    ref.watch(shopIdProvider),
  );
});

/// The shop's named staff roster (name + PIN profiles), shared across every
/// device under the shop.
final staffMembersProvider = StreamProvider<List<StaffMember>>((ref) {
  return ref.watch(staffRepositoryProvider).watchActiveMembers();
});

/// A lightweight 1-second ticker so staff-mode UI can refresh countdown text
/// (for owner PIN cooldown) without adding timers inside widgets.
final ownerPinCooldownSecondsProvider = StreamProvider.autoDispose<int>((
  ref,
) async* {
  final ctrl = ref.watch(staffControllerProvider);
  await ctrl.primePinState();
  yield ctrl.ownerPinCooldownRemainingSeconds();
  yield* Stream<int>.periodic(
    const Duration(seconds: 1),
    (_) => ctrl.ownerPinCooldownRemainingSeconds(),
  );
});

/// Which roster member is "using" this device right now — device-local, not
/// synced. Null if no named staff is selected (plain staff mode).
final activeStaffIdProvider = StreamProvider<String?>((ref) {
  final shopId = ref.watch(shopIdProvider);
  return ref.watch(settingsRepositoryProvider).watchActiveStaffId(shopId);
});

/// The active staff member's display name, for the Sell app bar badge —
/// null if none selected (falls back to the generic "Staff" badge).
final activeStaffNameProvider = Provider<String?>((ref) {
  final id = ref.watch(activeStaffIdProvider).valueOrNull;
  if (id == null) return null;
  final members = ref.watch(staffMembersProvider).valueOrNull ?? const [];
  for (final m in members) {
    if (m.id == id) return m.name;
  }
  return null;
});

/// Role currently applied by the UI permission layer.
///
/// Invited email staff (backend `'staff'`) cannot PIN-upgrade to owner.
/// Everyone else — signed in as email owner, or not signed in at all —
/// follows the local Owner/Staff PIN switch so handing this phone to a
/// cashier works either way. Backend `'staff'` without an email session is
/// still a hard floor.
final effectiveRoleProvider = Provider<String>((ref) {
  final backendRole = ref.watch(backendAccountRoleProvider);
  final localRole = ref.watch(staffRoleProvider).valueOrNull ?? 'owner';
  if (backendRole == 'staff') return 'staff';
  if (backendRole == 'owner') return localRole;
  if (backendRole != null && backendRole.isNotEmpty) return 'staff';
  return localRole;
});

/// Centralized session identity used by navigation and settings visibility.
final sessionScopeProvider = Provider<SessionScope>((ref) {
  final shopId = ref.watch(shopIdProvider);
  final localRole = ref.watch(staffRoleProvider).valueOrNull ?? 'owner';
  final backendRole = ref.watch(backendAccountRoleProvider);
  final effectiveRole = ref.watch(effectiveRoleProvider);
  final activeStaffId = ref.watch(activeStaffIdProvider).valueOrNull;
  final switchState = ref.watch(branchSwitchRecoveryProvider).valueOrNull;
  return SessionScope(
    shopId: shopId,
    localRole: localRole,
    backendRole: backendRole,
    effectiveRole: effectiveRole,
    activeStaffId: activeStaffId,
    switchState: switchState,
  );
});

/// True when the effective permission role is owner. Owner controls should gate
/// on this (not on local mode alone).
final isEffectiveOwnerProvider = Provider<bool>((ref) {
  return ref.watch(sessionScopeProvider).isEffectiveOwner;
});

/// Fail-closed owner check for SECURITY gates (audit QA-M5): unlike
/// [isEffectiveOwnerProvider] — which defaults to 'owner' while the role
/// stream is still loading so ordinary UI renders instantly — this answers
/// "not yet" until the local role has actually been read from settings (or
/// the backend role already rules ownership out). A cold-start deep link to
/// /analytics must never render business data in Staff mode during that
/// loading window.
final isResolvedOwnerProvider = Provider<bool>((ref) {
  final backendRole = ref.watch(backendAccountRoleProvider);
  if (backendRole != null && backendRole != 'owner') return false;
  final role = ref.watch(staffRoleProvider);
  return role.hasValue && role.value == 'owner';
});

/// Backward-compatible alias for existing call sites.
final isOwnerProvider = Provider<bool>((ref) {
  return ref.watch(isEffectiveOwnerProvider);
});

/// Alias kept for call-site clarity in the Inventory screen — Inventory
/// add/edit is owner-only, same gate as everything else non-Sell/Orders.
final canEditInventoryProvider = Provider<bool>(
  (ref) => ownerPermissionPolicy.allows(
    OwnerCapability.inventoryEdit,
    isEffectiveOwner: ref.watch(isEffectiveOwnerProvider),
  ),
);

/// Staff/Owner device-PIN mode is the same-phone handoff (lock this device
/// with a PIN, unlock as owner). Shown whether or not an email login exists
/// — a one-phone shop still hands the till to a cashier. Hidden only for
/// invited email staff: they sign out from Account instead of managing the
/// shop PIN.
final showStaffModeSectionProvider = Provider<bool>((ref) {
  return !(ref.watch(hasRealAccountSessionProvider) &&
      ref.watch(backendAccountRoleProvider) == 'staff');
});

/// Whether this device currently has an owner PIN saved. Invalidated after
/// [StaffController.setPin] so the Settings tile can switch Set → Change.
/// Watches [shopIdProvider] — the hash is per-shop (`SettingsRepository`
/// `_shopKey`); a branch switch must not keep the previous shop's answer.
final ownerPinIsSetProvider = FutureProvider<bool>((ref) {
  ref.watch(shopIdProvider);
  return ref.watch(staffControllerProvider).hasPin();
});

/// Switches the device's staff role and manages the owner PIN. Switching to
/// 'staff' is always free (an owner locking the device down for a cashier);
/// switching to 'owner' requires the correct PIN (or succeeds if none is set).
class StaffController {
  StaffController(this._ref, {DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final Ref _ref;
  final DateTime Function() _now;
  int _ownerPinFailures = 0;
  DateTime? _ownerPinLockedUntil;
  bool _pinStateLoaded = false;
  static const int _kMaxOwnerPinFailures = 5;
  static const Duration _kOwnerPinCooldown = Duration(seconds: 30);

  Future<void> primePinState() => _ensurePinStateLoaded();

  Future<void> _ensurePinStateLoaded() async {
    if (_pinStateLoaded) return;
    final repo = _ref.read(settingsRepositoryProvider);
    final shopId = _ref.read(shopIdProvider);
    _ownerPinFailures = await repo.ownerPinFailedAttempts(shopId);
    _ownerPinLockedUntil = await repo.ownerPinLockedUntil(shopId);
    _pinStateLoaded = true;
  }

  bool _clearExpiredOwnerPinLock() {
    final until = _ownerPinLockedUntil;
    if (until != null && !_now().isBefore(until)) {
      _ownerPinLockedUntil = null;
      return true;
    }
    return false;
  }

  int ownerPinCooldownRemainingSeconds() {
    _clearExpiredOwnerPinLock();
    final until = _ownerPinLockedUntil;
    if (until == null) return 0;
    final ms = until.difference(_now()).inMilliseconds;
    if (ms <= 0) return 0;
    return ((ms + 999) ~/ 1000);
  }

  bool isValidOwnerPin(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);

  Future<bool> hasPin() async =>
      (await _ref
              .read(settingsRepositoryProvider)
              .staffPinHash(_ref.read(shopIdProvider)))
          ?.isNotEmpty ??
      false;

  Future<bool> verifyOwnerPin(String pin) {
    return _ref
        .read(settingsRepositoryProvider)
        .verifyStaffPin(_ref.read(shopIdProvider), pin.trim());
  }

  Future<void> setPin(String pin) async {
    if (!isValidOwnerPin(pin)) {
      throw ArgumentError('owner PIN must be 4-6 digits');
    }
    final repo = _ref.read(settingsRepositoryProvider);
    final shopId = _ref.read(shopIdProvider);
    await repo.setStaffPin(shopId, pin);
    _ownerPinFailures = 0;
    _ownerPinLockedUntil = null;
    _pinStateLoaded = true;
    await repo.clearOwnerPinFailedAttempts(shopId);
    await repo.clearOwnerPinLockedUntil(shopId);
  }

  /// Attempts to switch to [targetRole]. [pin] is required only when
  /// switching to 'owner'. Returns false on a wrong PIN (role unchanged).
  /// Switching to 'owner' always clears the active staff identity — no named
  /// staff is "using" the device while it's in owner mode.
  Future<bool> switchRole(String targetRole, {String? pin}) async {
    await _ensurePinStateLoaded();
    final repo = _ref.read(settingsRepositoryProvider);
    final shopId = _ref.read(shopIdProvider);
    if (targetRole == 'owner') {
      final lockExpired = _clearExpiredOwnerPinLock();
      if (lockExpired) {
        await repo.clearOwnerPinLockedUntil(shopId);
      }
      if (_ownerPinLockedUntil != null &&
          _now().isBefore(_ownerPinLockedUntil!)) {
        return false;
      }
      final ok = await repo.verifyStaffPin(shopId, (pin ?? '').trim());
      if (!ok) {
        _ownerPinFailures += 1;
        await repo.setOwnerPinFailedAttempts(shopId, _ownerPinFailures);
        if (_ownerPinFailures >= _kMaxOwnerPinFailures) {
          _ownerPinFailures = 0;
          _ownerPinLockedUntil = _now().add(_kOwnerPinCooldown);
          await repo.setOwnerPinFailedAttempts(shopId, 0);
          await repo.setOwnerPinLockedUntil(shopId, _ownerPinLockedUntil!);
        }
        return false;
      }
      _ownerPinFailures = 0;
      _ownerPinLockedUntil = null;
      await repo.clearOwnerPinFailedAttempts(shopId);
      await repo.clearOwnerPinLockedUntil(shopId);
      await repo.setActiveStaffId(shopId, '');
    }
    await repo.setStaffRole(shopId, targetRole);
    return true;
  }

  /// Switches to Staff mode AS a specific named roster member — verifies
  /// that member's own PIN (not the shared owner PIN). Returns false on a
  /// wrong PIN.
  Future<bool> switchToStaffMember(String memberId, String pin) async {
    final staff = _ref.read(staffRepositoryProvider);
    final member = await staff.verifyPin(memberId, pin);
    if (member == null) return false;
    final repo = _ref.read(settingsRepositoryProvider);
    final shopId = _ref.read(shopIdProvider);
    await repo.setActiveStaffId(shopId, member.id);
    await repo.setStaffRole(shopId, 'staff');
    return true;
  }

  /// Applies a role the OWNER already chose when generating this device's
  /// activation QR (see `_DevicesSection`'s "Add a device" flow) — no PIN
  /// check, since switching a device to plain Staff mode has never required
  /// one (it's a device-lockdown action the owner takes, not an identity
  /// claim), and the owner already deliberately picked this device's
  /// intended staff member at generation time. Called once, right after a
  /// successful activation that came from a role-carrying QR; a no-op for a
  /// plain key with no role attached.
  Future<void> applyProvisionedRole(
    String role, {
    String? staffMemberId,
  }) async {
    if (role != 'staff') return;
    final repo = _ref.read(settingsRepositoryProvider);
    final shopId = _ref.read(shopIdProvider);
    if (staffMemberId != null && staffMemberId.isNotEmpty) {
      await repo.setActiveStaffId(shopId, staffMemberId);
    }
    await repo.setStaffRole(shopId, 'staff');
  }
}

final staffControllerProvider = Provider<StaffController>((ref) {
  // PIN lock counters are loaded once per controller. Recreate on shop
  // switch so shop-A's cooldown / failure count cannot leak into shop-B.
  ref.watch(shopIdProvider);
  return StaffController(ref);
});
