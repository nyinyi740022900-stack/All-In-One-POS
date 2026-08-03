import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../data/local/database.dart';
import '../../data/repositories/settings_repository.dart';
import '../license/license_model.dart';
import '../license/license_repository.dart';
import '../license/license_status.dart';

class Branch {
  final String shopId;
  final String? label;
  final bool isCurrent;
  const Branch(
      {required this.shopId, required this.label, required this.isCurrent});
}

class BranchActionResult {
  final bool ok;
  final String? error;
  const BranchActionResult.success() : ok = true, error = null;
  const BranchActionResult.failure(this.error) : ok = false;
}

/// A switch's outcome carries the freshly-built [CachedLicense] for the
/// target branch (from the `switch_branch` response) so the caller can apply
/// it via [LicenseController.applyExternal] — this repository deliberately
/// stops short of touching Riverpod state itself.
class BranchSwitchResult {
  final bool ok;
  final String? error;
  final CachedLicense? license;
  const BranchSwitchResult.success(this.license) : ok = true, error = null;
  const BranchSwitchResult.failure(this.error)
      : ok = false,
        license = null;
}

/// Lets a real-login owner (see `account_repository.dart`) group multiple
/// shop_ids they own as "branches" and switch which one this device is
/// scoped to. Switching wipes and resyncs local data — this app's local
/// Drift DB isn't partitioned per shop, so an in-place claim swap alone
/// would leave stale rows and a sync cursor pointed at the wrong shop's
/// high-water mark. See the `org_branches` migration + the `activate`
/// Edge Function's `link_branch`/`list_branches`/`unlink_branch`/
/// `switch_branch` actions for the server-side half of this.
class BranchRepository {
  BranchRepository(this._db, this._licenseRepository, this._settings);

  final AppDatabase _db;
  final LicenseRepository _licenseRepository;
  final SettingsRepository _settings;

  Future<List<Branch>> listBranches() async {
    if (!Env.hasBackend) return const [];
    try {
      final res = await Supabase.instance.client.functions
          .invoke('activate', body: {'action': 'list_branches'});
      final data = res.data as Map<String, dynamic>;
      if (data['ok'] != true) return const [];
      final branches = (data['branches'] as List).cast<Map<String, dynamic>>();
      return branches
          .map((b) => Branch(
                shopId: b['shop_id'] as String,
                label: b['label'] as String?,
                isCurrent: b['is_current'] as bool? ?? false,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Mints a brand new branch from just a name — no separate license key
  /// needed. The primary way to add a branch (see `link_branch` for the
  /// secondary case of registering an already-existing separate shop).
  Future<BranchActionResult> createBranch(String shopName) async {
    if (!Env.hasBackend) return const BranchActionResult.failure('no_backend');
    try {
      final res = await Supabase.instance.client.functions.invoke('activate',
          body: {'action': 'create_branch', 'shop_name': shopName});
      final data = res.data as Map<String, dynamic>;
      if (data['ok'] == true) return const BranchActionResult.success();
      return BranchActionResult.failure(data['error'] as String?);
    } catch (_) {
      return const BranchActionResult.failure('network_error');
    }
  }

  Future<BranchActionResult> linkBranch(String key, String label) async {
    if (!Env.hasBackend) return const BranchActionResult.failure('no_backend');
    try {
      final res = await Supabase.instance.client.functions.invoke('activate',
          body: {'action': 'link_branch', 'key': key, 'label': label});
      final data = res.data as Map<String, dynamic>;
      if (data['ok'] == true) return const BranchActionResult.success();
      return BranchActionResult.failure(data['error'] as String?);
    } catch (_) {
      return const BranchActionResult.failure('network_error');
    }
  }

  Future<bool> unlinkBranch(String shopId) async {
    if (!Env.hasBackend) return false;
    try {
      final res = await Supabase.instance.client.functions.invoke('activate',
          body: {'action': 'unlink_branch', 'shop_id': shopId});
      final data = res.data as Map<String, dynamic>;
      return data['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Switches this device to a different branch: checks the outbox is fully
  /// drained (never wipes unsynced writes), calls `switch_branch`, refreshes
  /// the session so the new shop_id claim lands in the JWT, then wipes every
  /// synced local table and resets sync cursors so the next pull starts
  /// clean for the new shop. Does NOT update `shopIdProvider`/trigger a
  /// resync itself — the caller applies the returned license via
  /// `LicenseController.applyExternal` and kicks `SyncController.sync()`.
  Future<BranchSwitchResult> switchBranch(String shopId) async {
    if (!Env.hasBackend) {
      return const BranchSwitchResult.failure('no_backend');
    }
    final pending = await _db.select(_db.outbox).get();
    if (pending.isNotEmpty) {
      return const BranchSwitchResult.failure('branch_switch_pending_sync');
    }

    Map<String, dynamic> data;
    try {
      final res = await Supabase.instance.client.functions
          .invoke('activate', body: {'action': 'switch_branch', 'shop_id': shopId});
      data = res.data as Map<String, dynamic>;
    } catch (_) {
      return const BranchSwitchResult.failure('network_error');
    }
    if (data['ok'] != true) {
      return BranchSwitchResult.failure(data['error'] as String?);
    }
    final expiresAtRaw = data['expires_at'] as String?;
    if (expiresAtRaw == null) {
      return const BranchSwitchResult.failure('server_error');
    }

    try {
      await Supabase.instance.client.auth.refreshSession();
    } catch (_) {}

    await _db.wipeSyncedData();

    final now = DateTime.now();
    final deviceId = await _settings.deviceId();
    final lic = CachedLicense(
      key: 'BRANCH-SWITCH',
      shopId: shopId,
      plan: _planFrom(data['plan'] as String? ?? 'monthly'),
      expiresAt: DateTime.parse(expiresAtRaw),
      activatedAt: DateTime.tryParse(data['activated_at'] as String? ?? '') ?? now,
      lastVerifiedAt: now,
      deviceId: deviceId,
      realtimeEnabled: data['realtime_enabled'] as bool? ?? false,
    );
    await _licenseRepository.saveExternal(lic);
    return BranchSwitchResult.success(lic);
  }
}

LicensePlan _planFrom(String s) => switch (s) {
      'yearly' => LicensePlan.yearly,
      'monthly' => LicensePlan.monthly,
      _ => LicensePlan.trial,
    };
