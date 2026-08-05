import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/database.dart';
import '../account/account_providers.dart';
import '../license/license_providers.dart';
import '../printing/printing_providers.dart';
import 'staff_repository.dart';

/// Two device-local operating modes, not synced — set by the owner before
/// handing the phone to staff. Kept deliberately simple: 'staff' (Sell +
/// Orders only) and 'owner' (everything). A finer-grained role tier was tried
/// and folded back into this — extra roles added complexity without a clear
/// use case for a small shop.
const staffRoles = <String>['staff', 'owner'];

final staffRoleProvider = StreamProvider<String>((ref) {
  return ref.watch(settingsRepositoryProvider).watchStaffRole();
});

final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return StaffRepository(ref.watch(databaseProvider), ref.watch(shopIdProvider));
});

/// The shop's named staff roster (name + PIN profiles), shared across every
/// device under the shop.
final staffMembersProvider = StreamProvider<List<StaffMember>>((ref) {
  return ref.watch(staffRepositoryProvider).watchActiveMembers();
});

/// A lightweight 1-second ticker so staff-mode UI can refresh countdown text
/// (for owner PIN cooldown) without adding timers inside widgets.
final ownerPinCooldownTickProvider = StreamProvider<int>((ref) async* {
  var tick = 0;
  while (true) {
    yield tick++;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
});

/// Which roster member is "using" this device right now — device-local, not
/// synced. Null if no named staff is selected (plain staff mode).
final activeStaffIdProvider = StreamProvider<String?>((ref) {
  return ref.watch(settingsRepositoryProvider).watchActiveStaffId();
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
/// Local device mode can lock a phone down to staff, while a real backend
/// account may also itself be staff. We pick the more restrictive result:
/// - backend 'staff' => always staff
/// - backend 'owner' => follow local device mode
/// - no backend role  => follow local device mode
final effectiveRoleProvider = Provider<String>((ref) {
  final localRole = ref.watch(staffRoleProvider).valueOrNull ?? 'owner';
  final backendRole = ref.watch(backendAccountRoleProvider);
  if (backendRole == 'staff') return 'staff';
  if (backendRole == 'owner') return localRole;
  if (backendRole != null && backendRole.isNotEmpty) return 'staff';
  return localRole;
});

/// True when the effective permission role is owner. Owner controls should gate
/// on this (not on local mode alone).
final isEffectiveOwnerProvider = Provider<bool>((ref) {
  return ref.watch(effectiveRoleProvider) == 'owner';
});

/// Backward-compatible alias for existing call sites.
final isOwnerProvider = Provider<bool>((ref) {
  return ref.watch(isEffectiveOwnerProvider);
});

/// Alias kept for call-site clarity in the Inventory screen — Inventory
/// add/edit is owner-only, same gate as everything else non-Sell/Orders.
final canEditInventoryProvider = Provider<bool>((ref) => ref.watch(isOwnerProvider));

/// Staff/Owner mode only matters once there's a second device to hand off to
/// someone else — for a shop running just one device, switching that one
/// phone into Staff mode has no real benefit and is just confusing extra
/// settings. Hidden in that case, EXCEPT when the device is already in Staff
/// mode (e.g. a shop released devices back down to one after using Staff
/// mode) — then it stays visible so there's always a way back to Owner.
final showStaffModeSectionProvider = Provider<bool>((ref) {
  final role = ref.watch(staffRoleProvider).valueOrNull ?? 'owner';
  if (role != 'owner') return true;
  final deviceCount = ref.watch(shopDevicesProvider).valueOrNull
          ?.where((d) => d.isBound).length ??
      1;
  return deviceCount > 1;
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
  static const int _kMaxOwnerPinFailures = 5;
  static const Duration _kOwnerPinCooldown = Duration(seconds: 30);

  void _clearExpiredOwnerPinLock() {
    final until = _ownerPinLockedUntil;
    if (until != null && !_now().isBefore(until)) {
      _ownerPinLockedUntil = null;
    }
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
      (await _ref.read(settingsRepositoryProvider).staffPinHash())?.isNotEmpty ??
      false;

  Future<void> setPin(String pin) async {
    if (!isValidOwnerPin(pin)) {
      throw ArgumentError('owner PIN must be 4-6 digits');
    }
    await _ref.read(settingsRepositoryProvider).setStaffPin(pin);
  }

  /// Attempts to switch to [targetRole]. [pin] is required only when
  /// switching to 'owner'. Returns false on a wrong PIN (role unchanged).
  /// Switching to 'owner' always clears the active staff identity — no named
  /// staff is "using" the device while it's in owner mode.
  Future<bool> switchRole(String targetRole, {String? pin}) async {
    final repo = _ref.read(settingsRepositoryProvider);
    if (targetRole == 'owner') {
      _clearExpiredOwnerPinLock();
      if (_ownerPinLockedUntil != null && _now().isBefore(_ownerPinLockedUntil!)) {
        return false;
      }
      final ok = await repo.verifyStaffPin((pin ?? '').trim());
      if (!ok) {
        _ownerPinFailures += 1;
        if (_ownerPinFailures >= _kMaxOwnerPinFailures) {
          _ownerPinFailures = 0;
          _ownerPinLockedUntil = _now().add(_kOwnerPinCooldown);
        }
        return false;
      }
      _ownerPinFailures = 0;
      _ownerPinLockedUntil = null;
      await repo.setActiveStaffId('');
    }
    await repo.setStaffRole(targetRole);
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
    await repo.setActiveStaffId(member.id);
    await repo.setStaffRole('staff');
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
  Future<void> applyProvisionedRole(String role, {String? staffMemberId}) async {
    if (role != 'staff') return;
    final repo = _ref.read(settingsRepositoryProvider);
    if (staffMemberId != null && staffMemberId.isNotEmpty) {
      await repo.setActiveStaffId(staffMemberId);
    }
    await repo.setStaffRole('staff');
  }
}

final staffControllerProvider =
    Provider<StaffController>((ref) => StaffController(ref));
