import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/env.dart';
import '../../data/local/database.dart';
import '../../data/local/shop_data_transition_service.dart';
import '../../data/repositories/settings_repository.dart';
import '../license/license_model.dart';
import '../license/license_repository.dart';
import '../license/license_status.dart';

class Branch {
  final String shopId;
  final String? label;
  final bool isCurrent;
  const Branch({
    required this.shopId,
    required this.label,
    required this.isCurrent,
  });
}

class BranchActionResult {
  final bool ok;
  final String? error;
  const BranchActionResult.success() : ok = true, error = null;
  const BranchActionResult.failure(this.error) : ok = false;
}

class BranchListException implements Exception {
  final String code;
  const BranchListException(this.code);
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
  const BranchSwitchResult.failure(this.error) : ok = false, license = null;
}

enum BranchSwitchStep {
  checkingDataSafety,
  switchingAccountClaim,
  refreshingSession,
  clearingOldData,
}

typedef BranchSwitchStepCallback = void Function(BranchSwitchStep step);

class BranchSwitchRecoveryState {
  final String token;
  final String fromShopId;
  final String toShopId;
  final BranchSwitchStep step;
  final DateTime startedAt;
  final String? lastError;
  final bool needsSyncRetry;

  const BranchSwitchRecoveryState({
    required this.token,
    required this.fromShopId,
    required this.toShopId,
    required this.step,
    required this.startedAt,
    this.lastError,
    this.needsSyncRetry = false,
  });

  BranchSwitchRecoveryState copyWith({
    BranchSwitchStep? step,
    String? lastError,
    bool? needsSyncRetry,
  }) {
    return BranchSwitchRecoveryState(
      token: token,
      fromShopId: fromShopId,
      toShopId: toShopId,
      step: step ?? this.step,
      startedAt: startedAt,
      lastError: lastError,
      needsSyncRetry: needsSyncRetry ?? this.needsSyncRetry,
    );
  }

  Map<String, dynamic> toJson() => {
    'token': token,
    'from_shop_id': fromShopId,
    'to_shop_id': toShopId,
    'step': step.name,
    'started_at': startedAt.toUtc().toIso8601String(),
    'last_error': lastError,
    'needs_sync_retry': needsSyncRetry,
  };

  static BranchSwitchRecoveryState? fromJson(Map<String, dynamic> json) {
    final token = json['token'] as String?;
    final fromShopId = json['from_shop_id'] as String?;
    final toShopId = json['to_shop_id'] as String?;
    final stepName = json['step'] as String?;
    final startedRaw = json['started_at'] as String?;
    if (token == null ||
        fromShopId == null ||
        toShopId == null ||
        stepName == null ||
        startedRaw == null) {
      return null;
    }
    final startedAt = DateTime.tryParse(startedRaw);
    final step = BranchSwitchStep.values.where((e) => e.name == stepName);
    if (startedAt == null || step.isEmpty) return null;
    return BranchSwitchRecoveryState(
      token: token,
      fromShopId: fromShopId,
      toShopId: toShopId,
      step: step.first,
      lastError: json['last_error'] as String?,
      needsSyncRetry: json['needs_sync_retry'] as bool? ?? false,
      startedAt: startedAt,
    );
  }
}

class BranchSwitchVerification {
  final bool ok;
  final bool claimMatchesTarget;
  final bool shopMatchesTarget;
  final bool profileReadable;
  final bool categoryQueryOk;
  final bool productQueryOk;
  final bool outboxClear;
  final bool catalogReady;

  const BranchSwitchVerification({
    required this.ok,
    required this.claimMatchesTarget,
    required this.shopMatchesTarget,
    required this.profileReadable,
    required this.categoryQueryOk,
    required this.productQueryOk,
    required this.outboxClear,
    required this.catalogReady,
  });
}

/// Lets a real-login owner (see `account_repository.dart`) group multiple
/// shop_ids they own as "branches" and switch which one this device is
/// scoped to. With [AppDatabase.usePerShopDbFiles], switch closes the
/// current shop SQLite file and opens the target's (no wipe). Legacy mode
/// still wipes the shared DB then resyncs. See `org_branches` + `activate`
/// `link_branch`/`list_branches`/`unlink_branch`/`switch_branch`.
class BranchRepository {
  BranchRepository(
    this._db,
    this._licenseRepository,
    this._settings, {
    this.onShopDbSwap,
    this.onLicenseReady,
  });

  final AppDatabase _db;
  late final ShopDataTransitionService _transition = ShopDataTransitionService(
    _db,
  );
  final LicenseRepository _licenseRepository;
  final SettingsRepository _settings;

  /// When per-shop DB files are on: reopen the target shop file after
  /// [ShopDataTransitionService.prepareShopSwitch] (which skips wipe).
  final Future<void> Function(String toShopId)? onShopDbSwap;

  /// Called immediately after license save + DB swap so [shopIdProvider]
  /// matches the new shop before any post-switch sync.
  final Future<void> Function(CachedLicense license)? onLicenseReady;

  Future<void> _saveRecoveryState(BranchSwitchRecoveryState state) =>
      _settings.setBranchSwitchStateJson(jsonEncode(state.toJson()));

  Future<BranchSwitchRecoveryState?> switchRecoveryState() async {
    final raw = await _settings.branchSwitchStateJson();
    if (raw == null || raw.isEmpty) return null;
    try {
      return BranchSwitchRecoveryState.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Stream<BranchSwitchRecoveryState?> watchSwitchRecoveryState() {
    return _settings.watchBranchSwitchStateJson().map((raw) {
      if (raw == null || raw.isEmpty) return null;
      try {
        return BranchSwitchRecoveryState.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {
        return null;
      }
    });
  }

  Future<void> clearSwitchRecoveryState() => _settings.clearBranchSwitchState();

  Future<void> markSwitchNeedsSyncRetry({
    required String toShopId,
    required String fromShopId,
    String? token,
    String? lastError,
  }) {
    final state = BranchSwitchRecoveryState(
      token: (token == null || token.isEmpty) ? const Uuid().v4() : token,
      fromShopId: fromShopId,
      toShopId: toShopId,
      step: BranchSwitchStep.clearingOldData,
      startedAt: DateTime.now(),
      lastError: lastError,
      needsSyncRetry: true,
    );
    return _saveRecoveryState(state);
  }

  Future<BranchSwitchVerification> verifyPostSwitch(String targetShopId) async {
    final current = await _licenseRepository.current();
    final shopMatchesTarget = current?.shopId == targetShopId;
    final claimShopId =
        Supabase.instance.client.auth.currentUser?.appMetadata['shop_id']
            as String?;
    final claimMatchesTarget = claimShopId == targetShopId;

    bool profileReadable = false;
    try {
      await _settings.shopProfile(targetShopId);
      profileReadable = true;
    } catch (_) {}

    var categoryQueryOk = false;
    var localCategoryCount = 0;
    try {
      final rows = await _db.select(_db.categories).get();
      localCategoryCount = rows.length;
      categoryQueryOk = rows.every((r) => r.shopId == targetShopId);
    } catch (_) {}

    var productQueryOk = false;
    var localProductCount = 0;
    try {
      final rows = await _db.select(_db.products).get();
      localProductCount = rows.length;
      productQueryOk = rows.every((r) => r.shopId == targetShopId);
    } catch (_) {}

    final pendingOutbox = await (_db.select(_db.outbox)
          ..where((o) => o.quarantined.equals(false)))
        .get();
    final outboxClear = pendingOutbox.isEmpty;

    // Empty local catalog is only OK when the server also has no catalog for
    // this shop (brand-new branch). If remote has rows but local is empty,
    // post-switch pull did not finish — do not treat as success.
    var catalogReady = true;
    final localCatalogEmpty = localCategoryCount == 0 && localProductCount == 0;
    if (localCatalogEmpty && Env.hasBackend) {
      try {
        final remoteCats = await Supabase.instance.client
            .from('categories')
            .select('id')
            .eq('shop_id', targetShopId)
            .limit(1);
        final remoteProds = await Supabase.instance.client
            .from('products')
            .select('id')
            .eq('shop_id', targetShopId)
            .limit(1);
        final remoteHasCatalog =
            (remoteCats as List).isNotEmpty || (remoteProds as List).isNotEmpty;
        catalogReady = !remoteHasCatalog;
      } catch (_) {
        // Only fail when we *observe* remote catalog with empty local.
        // Offline / probe error: allow empty new branch; incomplete pull
        // still fails once online (remoteHasCatalog → false).
        catalogReady = true;
      }
    }

    final ok =
        claimMatchesTarget &&
        shopMatchesTarget &&
        profileReadable &&
        categoryQueryOk &&
        productQueryOk &&
        outboxClear &&
        catalogReady;
    return BranchSwitchVerification(
      ok: ok,
      claimMatchesTarget: claimMatchesTarget,
      shopMatchesTarget: shopMatchesTarget,
      profileReadable: profileReadable,
      categoryQueryOk: categoryQueryOk,
      productQueryOk: productQueryOk,
      outboxClear: outboxClear,
      catalogReady: catalogReady,
    );
  }

  Future<List<Branch>> listBranches() async {
    if (!Env.hasBackend) return const [];
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'activate',
        body: {'action': 'list_branches'},
      );
      final data = res.data as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw BranchListException((data['error'] as String?) ?? 'server_error');
      }
      final branches = (data['branches'] as List).cast<Map<String, dynamic>>();
      return branches
          .map(
            (b) => Branch(
              shopId: b['shop_id'] as String,
              label: b['label'] as String?,
              isCurrent: b['is_current'] as bool? ?? false,
            ),
          )
          .toList();
    } catch (e) {
      if (e is BranchListException) rethrow;
      throw const BranchListException('network_error');
    }
  }

  /// Mints a brand new branch from just a name — no separate license key
  /// needed. The only in-app way to add a branch under an online account.
  Future<BranchActionResult> createBranch(String shopName) async {
    if (!Env.hasBackend) return const BranchActionResult.failure('no_backend');
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'activate',
        body: {'action': 'create_branch', 'shop_name': shopName},
      );
      final data = res.data as Map<String, dynamic>;
      if (data['ok'] == true) return const BranchActionResult.success();
      return BranchActionResult.failure(data['error'] as String?);
    } catch (_) {
      return const BranchActionResult.failure('network_error');
    }
  }

  Future<BranchActionResult> linkBranch(String key, String label) async {
    // Kept for Support/legacy tooling; not exposed in the Branches UI
    // (online accounts add branches via [createBranch] only).
    if (!Env.hasBackend) return const BranchActionResult.failure('no_backend');
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'activate',
        body: {'action': 'link_branch', 'key': key, 'label': label},
      );
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
      final res = await Supabase.instance.client.functions.invoke(
        'activate',
        body: {'action': 'unlink_branch', 'shop_id': shopId},
      );
      final data = res.data as Map<String, dynamic>;
      return data['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<int> pendingOutboxCount() async {
    return (await _transition.precheck()).pendingOutboxCount;
  }

  Future<ShopTransitionPrecheck> transitionPrecheck() => _transition.precheck();

  /// Switches this device to a different branch: checks the outbox is fully
  /// drained (never leaves unsynced writes behind), calls `switch_branch`,
  /// refreshes the session so the new shop_id claim lands in the JWT, then
  /// reopens the target shop DB (or wipes in legacy mode). Invokes
  /// [onLicenseReady] before returning so shopId + license bind atomically
  /// with the DB file. Caller should still pause background sync around the
  /// whole critical section and run a post-switch pull.
  Future<BranchSwitchResult> switchBranch(
    String shopId, {
    BranchSwitchStepCallback? onStep,
    String? idempotencyToken,
  }) async {
    final current = await _licenseRepository.current();
    final fromShopId = current?.shopId ?? '';
    final token = idempotencyToken ?? const Uuid().v4();
    final startedAt = DateTime.now();
    Future<void> saveStep(BranchSwitchStep step, {String? error}) async {
      await _saveRecoveryState(
        BranchSwitchRecoveryState(
          token: token,
          fromShopId: fromShopId,
          toShopId: shopId,
          step: step,
          startedAt: startedAt,
          lastError: error,
          needsSyncRetry: false,
        ),
      );
    }

    await saveStep(BranchSwitchStep.checkingDataSafety);
    onStep?.call(BranchSwitchStep.checkingDataSafety);
    if (!Env.hasBackend) {
      return const BranchSwitchResult.failure('no_backend');
    }
    final auth = Supabase.instance.client.auth;
    if (auth.currentSession == null || auth.currentUser == null) {
      return const BranchSwitchResult.failure('auth_expired');
    }
    final clearGuard = await _transition.assertSafeToClear();
    if (clearGuard != null) {
      final code = clearGuard == 'stuck_outbox'
          ? 'stuck_outbox'
          : 'branch_switch_pending_sync';
      await saveStep(BranchSwitchStep.checkingDataSafety, error: code);
      return BranchSwitchResult.failure(code);
    }

    Map<String, dynamic> data;
    try {
      await saveStep(BranchSwitchStep.switchingAccountClaim);
      onStep?.call(BranchSwitchStep.switchingAccountClaim);
      final res = await Supabase.instance.client.functions.invoke(
        'activate',
        body: {
          'action': 'switch_branch',
          'shop_id': shopId,
          'switch_token': token,
        },
      );
      data = res.data as Map<String, dynamic>;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('jwt') ||
          msg.contains('unauthorized') ||
          msg.contains('forbidden') ||
          msg.contains('auth')) {
        await saveStep(
          BranchSwitchStep.switchingAccountClaim,
          error: 'auth_expired',
        );
        return const BranchSwitchResult.failure('auth_expired');
      }
      await saveStep(
        BranchSwitchStep.switchingAccountClaim,
        error: 'network_error',
      );
      return const BranchSwitchResult.failure('network_error');
    }
    if (data['ok'] != true) {
      final error = data['error'] as String?;
      await saveStep(BranchSwitchStep.switchingAccountClaim, error: error);
      return BranchSwitchResult.failure(error);
    }
    final expiresAtRaw = data['expires_at'] as String?;
    if (expiresAtRaw == null) {
      return const BranchSwitchResult.failure('server_error');
    }

    try {
      await saveStep(BranchSwitchStep.refreshingSession);
      onStep?.call(BranchSwitchStep.refreshingSession);
      await Supabase.instance.client.auth.refreshSession();
    } catch (_) {
      await saveStep(BranchSwitchStep.refreshingSession, error: 'auth_expired');
      return const BranchSwitchResult.failure('auth_expired');
    }
    var refreshedShopId = auth.currentUser?.appMetadata['shop_id'] as String?;
    if (refreshedShopId != shopId) {
      try {
        await Supabase.instance.client.auth.refreshSession();
        refreshedShopId = auth.currentUser?.appMetadata['shop_id'] as String?;
      } catch (_) {}
    }
    if (refreshedShopId != shopId) {
      await saveStep(
        BranchSwitchStep.refreshingSession,
        error: 'invalid_branch_state',
      );
      return const BranchSwitchResult.failure('invalid_branch_state');
    }

    await saveStep(BranchSwitchStep.clearingOldData);
    onStep?.call(BranchSwitchStep.clearingOldData);
    final prep = await _transition.prepareShopSwitch(
      fromShopId: fromShopId,
      toShopId: shopId,
    );
    if (!prep.usedWipeFallback) {
      await onShopDbSwap?.call(shopId);
    }

    final now = DateTime.now();
    final deviceId = await _settings.deviceId();
    final lic = CachedLicense(
      key: 'BRANCH-SWITCH',
      shopId: shopId,
      plan: _planFrom(data['plan'] as String? ?? 'monthly'),
      expiresAt: DateTime.parse(expiresAtRaw),
      activatedAt:
          DateTime.tryParse(data['activated_at'] as String? ?? '') ?? now,
      lastVerifiedAt: now,
      deviceId: deviceId,
      realtimeEnabled: data['realtime_enabled'] as bool? ?? false,
      tier: data['tier'] as String? ?? 'offline',
    );
    // license.json is device-global (sidecar) — safe after shop DB reopen.
    await _licenseRepository.saveExternal(lic);
    await onLicenseReady?.call(lic);
    return BranchSwitchResult.success(lic);
  }
}

LicensePlan _planFrom(String s) => switch (s) {
  'yearly' => LicensePlan.yearly,
  'monthly' => LicensePlan.monthly,
  'free' => LicensePlan.free,
  _ => LicensePlan.trial,
};
