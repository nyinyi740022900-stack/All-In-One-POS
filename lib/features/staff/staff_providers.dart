import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/database.dart';
import '../account/account_providers.dart';
import '../printing/printing_providers.dart';
import 'staff_repository.dart';

final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return StaffRepository(ref.watch(databaseProvider), ref.watch(shopIdProvider));
});

/// The shop's named staff roster (name + PIN profiles), shared across every
/// device under the shop.
final staffMembersProvider = StreamProvider<List<StaffMember>>((ref) {
  return ref.watch(staffRepositoryProvider).watchActiveMembers();
});

/// Role currently applied by the UI permission layer.
///
/// Source of truth is now backend account role (email-login invite model):
/// - backend 'staff' => staff
/// - backend 'owner' => owner
/// - unknown backend role => staff-safe fallback
/// - no backend role/session => owner fallback
final effectiveRoleProvider = Provider<String>((ref) {
  final backendRole = ref.watch(backendAccountRoleProvider);
  if (backendRole == 'staff') return 'staff';
  if (backendRole == 'owner') return 'owner';
  if (backendRole != null && backendRole.isNotEmpty) return 'staff';
  return 'owner';
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
final canEditInventoryProvider =
    Provider<bool>((ref) => ref.watch(isEffectiveOwnerProvider));

/// One-shot app migration hook for hard-cut removal of local staff/PIN mode.
final staffModeCleanupProvider = FutureProvider<void>((ref) async {
  await ref.watch(settingsRepositoryProvider).cleanupDeprecatedStaffModeSettings();
});
