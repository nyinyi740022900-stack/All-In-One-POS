import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/database.dart';
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

/// True when the current device mode is owner (or still loading, so the UI
/// never briefly hides owner controls from the owner). Gates Analytics,
/// Inventory add/edit, Storefront, Delivery-carrier config, and staff-mode/
/// License management.
final isOwnerProvider = Provider<bool>((ref) {
  return (ref.watch(staffRoleProvider).valueOrNull ?? 'owner') == 'owner';
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
  StaffController(this._ref);
  final Ref _ref;

  Future<bool> hasPin() async =>
      (await _ref.read(settingsRepositoryProvider).staffPin())?.isNotEmpty ??
      false;

  Future<void> setPin(String pin) =>
      _ref.read(settingsRepositoryProvider).setStaffPin(pin);

  /// Attempts to switch to [targetRole]. [pin] is required only when
  /// switching to 'owner'. Returns false on a wrong PIN (role unchanged).
  /// Switching to 'owner' always clears the active staff identity — no named
  /// staff is "using" the device while it's in owner mode.
  Future<bool> switchRole(String targetRole, {String? pin}) async {
    final repo = _ref.read(settingsRepositoryProvider);
    if (targetRole == 'owner') {
      final saved = await repo.staffPin();
      if (saved != null && saved.isNotEmpty && saved != (pin ?? '')) {
        return false;
      }
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
}

final staffControllerProvider =
    Provider<StaffController>((ref) => StaffController(ref));
