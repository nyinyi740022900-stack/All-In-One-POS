import 'dart:convert';

import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../data/repositories/settings_repository.dart';
import 'invoke_error.dart';
import 'license_model.dart';
import 'license_status.dart';

/// Account subscription refresh, signed receipt caching and device management.
class LicenseRepository {
  LicenseRepository(this._settings);

  /// Local placeholder `CachedLicense.key` for a self-serve trial minted by
  /// [startFreeTrial] — there's no per-key server lookup for this plan type
  /// (same convention `signupShop`'s `'SIGNUP'` key already uses). Named here
  /// so every comparison site (this file, `license_providers.dart`) shares
  /// one source instead of re-typing the literal — a re-typed copy is
  /// exactly what caused `refreshOnline` to silently check a dead
  /// `'FREE-TRIAL'` string instead of this value.
  static const String trialKey = 'TRIAL';

  /// Local placeholder `CachedLicense.key` for a shop minted by email
  /// signup — same convention [AccountRepository.signupShop] already writes.
  static const String signupKey = 'SIGNUP';

  /// Local placeholder `CachedLicense.key` for the Free plan — see
  /// [startFreePlan] / [downgradeToFree]. Same rationale as [trialKey].
  static const String freeKey = 'FREE';

  final SettingsRepository _settings;

  bool get hasEmailSession {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      return user != null && (user.email ?? '').isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<CachedLicense?> current() async {
    final raw = await _settings.licenseJson();
    if (raw == null) return null;
    try {
      return CachedLicense.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<CachedLicense?> _save(CachedLicense lic) async {
    await _settings.setLicenseJson(jsonEncode(lic.toJson()));
    return lic;
  }

  /// Retained for old internal callers; account authentication replaced keys.
  Future<ActivationResult> activate(String key) async =>
      const ActivationResult.failure('retired_path');

  String? get currentUserId {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      return hasEmailSession ? user?.id : null;
    } catch (_) {
      return null;
    }
  }

  String? get currentAccountRole {
    try {
      return Supabase.instance.client.auth.currentUser?.appMetadata['role']
          as String?;
    } catch (_) {
      return null;
    }
  }

  String? get currentSessionShopId {
    try {
      return Supabase.instance.client.auth.currentUser?.appMetadata['shop_id']
          as String?;
    } catch (_) {
      return null;
    }
  }

  int _generation = 0;
  void cancelPendingRequests() {
    _generation++;
  }

  /// Explicit owner-account trial for the already registered selected shop.
  Future<ActivationResult> startFreeTrial(String shopName) async {
    if (!Env.hasBackend) return const ActivationResult.failure('no_backend');
    if (!hasEmailSession) {
      return const ActivationResult.failure('account_required');
    }
    final current = await this.current();
    if (current == null || current.shopId.startsWith('free-')) {
      return const ActivationResult.failure('account_required');
    }
    final generation = _generation;
    final userId = currentUserId;
    final deviceId = await _settings.deviceId();

    try {
      final res = await invokeActivate({
        'action': 'start_trial',
        'shop_id': current.shopId,
        'device_id': deviceId,
      });
      final data = res.data as Map<String, dynamic>;
      if (data['ok'] != true) {
        return ActivationResult.failure(
          (data['error'] as String?) ?? 'server_error',
        );
      }
      final now = DateTime.now();
      final lic = CachedLicense(
        key: current.key,
        shopId: data['shop_id'] as String,
        plan: LicensePlan.trial,
        expiresAt: DateTime.parse(data['expires_at'] as String),
        activatedAt:
            DateTime.tryParse(data['activated_at'] as String? ?? '') ?? now,
        lastVerifiedAt: now,
        deviceId: deviceId,
        tier: data['tier'] as String? ?? 'offline',
        entitlement: data['entitlement'] as String?,
      );
      // Refresh the session and confirm the new shop_id claim actually
      // landed — see refreshSessionAndVerifyClaim's own doc comment; this is
      // the exact path that was silently failing before (a self-serve trial
      // whose session never picked up its shop_id claim, closed alongside
      // this change).
      if (!await refreshSessionAndVerifyClaim(lic.shopId)) {
        return const ActivationResult.failure('claim_mismatch');
      }
      if (generation != _generation || userId != currentUserId) {
        return const ActivationResult.failure('stale_response');
      }
      return ActivationResult.success(await _save(lic));
    } catch (e) {
      return ActivationResult.failure(classifyInvokeError(e));
    }
  }

  /// Recover the authenticated account connection without a key input.
  Future<ActivationResult> repairSession() => refreshAccountLicense();

  /// Pulls this signed-in shop's current plan + expiry (admin extend) onto
  /// the device without a typed key — Settings → Check for renewal, and
  /// email sign-in on a new install.
  Future<ActivationResult> refreshAccountLicense({
    bool persist = true,
    bool reclaimDevice = false,
  }) async {
    if (!Env.hasBackend) return const ActivationResult.failure('no_backend');
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || (user.email ?? '').isEmpty) {
      return const ActivationResult.failure('not_activated');
    }
    // Mirrors signupShop()'s retry strength: a just-created account (e.g.
    // createShopLogin() immediately followed by this sign-in) can hit the
    // same shop_id-claim-propagation race a brand-new signup does, and one
    // flat retry wasn't always enough to clear it before falling through to
    // the sign-out path with a misleading-sounding failure.
    var result = await _refreshAccountLicenseOnce(
      persist: persist,
      reclaimDevice: reclaimDevice,
    );
    for (
      var attempt = 0;
      attempt < 2 &&
          (result.errorCode == 'not_activated' ||
              result.errorCode == 'not_authenticated');
      attempt++
    ) {
      await refreshSessionBounded();
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      result = await _refreshAccountLicenseOnce(
        persist: persist,
        reclaimDevice: reclaimDevice,
      );
    }
    return result;
  }

  Future<ActivationResult> _refreshAccountLicenseOnce({
    required bool persist,
    required bool reclaimDevice,
  }) async {
    final generation = _generation;
    final userId = currentUserId;
    final before = await this.current();
    final deviceId = await _settings.deviceId();
    final Map<String, dynamic> data;
    try {
      final res = await invokeActivate({
        'action': 'refresh_account_license',
        if (reclaimDevice) 'reclaim_device': true,
        if (before != null &&
            !before.shopId.startsWith('free-') &&
            Supabase.instance.client.auth.currentUser?.appMetadata['shop_id'] ==
                before.shopId)
          'shop_id': before.shopId,
        'device_id': deviceId,
      });
      final parsed = parseInvokeData(res.data);
      if (parsed == null) {
        return const ActivationResult.failure('server_error');
      }
      data = parsed;
    } catch (e) {
      return ActivationResult.failure(classifyInvokeError(e));
    }
    if (data['ok'] != true) {
      return ActivationResult.failure(
        errorCodeFromInvokeData(data) ?? 'server_error',
      );
    }
    final expiresAtRaw = data['expires_at'] as String?;
    final shopId = data['shop_id'] as String?;
    if (expiresAtRaw == null || shopId == null || shopId.isEmpty) {
      return const ActivationResult.failure('server_error');
    }
    final now = DateTime.now();
    final current = await this.current();
    final key = (data['key'] as String?)?.trim();
    final lic = CachedLicense(
      key: (key != null && key.isNotEmpty) ? key : (current?.key ?? signupKey),
      shopId: shopId,
      plan: _planFrom(data['plan'] as String? ?? 'monthly'),
      expiresAt: DateTime.parse(expiresAtRaw),
      activatedAt:
          DateTime.tryParse(data['activated_at'] as String? ?? '') ??
          current?.activatedAt ??
          now,
      lastVerifiedAt: now,
      deviceId: deviceId,
      realtimeEnabled: data['realtime_enabled'] as bool? ?? true,
      tier: data['tier'] as String? ?? current?.tier ?? 'online',
      entitlement: data['entitlement'] as String?,
    );
    if (!await refreshSessionAndVerifyClaim(lic.shopId)) {
      return const ActivationResult.failure('claim_mismatch');
    }
    if (generation != _generation || userId != currentUserId) {
      return const ActivationResult.failure('stale_response');
    }
    return ActivationResult.success(persist ? await _save(lic) : lic);
  }

  /// Enters the Free plan from scratch — no key, no account, no network call.
  /// Core POS features (Sell/Inventory/etc.) work immediately and forever;
  /// only Premium-gated features stay locked (see `PremiumGate`). The shop_id
  /// is synthesized locally, same shape as the offline-trial fallback above,
  /// since a Free-plan shop has no server-side `licenses` row at all.
  Future<CachedLicense> startFreePlan() async {
    final deviceId = await _settings.deviceId();
    final now = DateTime.now();
    return (await _save(
      CachedLicense(
        key: freeKey,
        shopId: 'free-${deviceId.replaceAll('-', '').substring(0, 10)}',
        plan: LicensePlan.free,
        expiresAt: now,
        activatedAt: now,
        lastVerifiedAt: now,
        deviceId: deviceId,
      ),
    ))!;
  }

  /// Drops an existing license to the Free plan while preserving its
  /// identity (`shopId`/`deviceId`/`tier`) — local data and sync keep working
  /// under the same shop, only Premium features stop being unlocked. Used
  /// both for auto-downgrade on expiry and for the sign-out-revokes-premium
  /// flow (see `LicenseController`/`AccountRepository`).
  Future<CachedLicense> downgradeToFree(CachedLicense current) async {
    cancelPendingRequests();
    final now = DateTime.now();
    return (await _save(
      current.copyWith(
        plan: LicensePlan.free,
        expiresAt: now,
        lastVerifiedAt: now,
      ),
    ))!;
  }

  /// Refreshes the caller's Supabase session and verifies the resulting JWT
  /// actually carries [expectedShopId] in `app_metadata.shop_id` — retries
  /// the refresh once if the claim hasn't landed yet, then reports (Sentry,
  /// best-effort) and returns false if it still hasn't. Every call site that
  /// mints or re-verifies a license needs this, not just a fire-and-forget
  /// `refreshSession()`: a claim that silently fails to land makes every
  /// subsequent RLS-scoped write fail with no way to tell why (the bug this
  /// centralizes the fix for). Mirrors the verify-after-refresh pattern
  /// `BranchRepository.switchBranch()` already used in exactly one place.
  Future<bool> refreshSessionAndVerifyClaim(String expectedShopId) async {
    final auth = Supabase.instance.client.auth;
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await auth.refreshSession().timeout(const Duration(seconds: 8));
      } catch (e) {
        lastError = e;
        continue;
      }
      final claim = auth.currentUser?.appMetadata['shop_id'] as String?;
      if (claim == expectedShopId) return true;
      lastError = 'claim_mismatch (got: $claim)';
    }
    try {
      await Sentry.captureMessage(
        'License session refresh did not carry the expected shop_id claim',
        level: SentryLevel.warning,
        withScope: (scope) {
          scope.setTag('license.expected_shop_id', expectedShopId);
          scope.setContexts('license_refresh', {
            'expected_shop_id': expectedShopId,
            'last_error': lastError.toString(),
          });
        },
      );
    } catch (_) {}
    return false;
  }

  Future<void> deactivate() {
    cancelPendingRequests();
    return _settings.clearLicense();
  }

  /// Persists a [CachedLicense] built from somewhere other than `activate()`
  /// (e.g. a branch switch, which restamps the caller's own shop_id claim
  /// via a different Edge Function action). Same cache write `activate()`
  /// itself uses.
  Future<CachedLicense?> saveExternal(CachedLicense lic) {
    cancelPendingRequests();
    return _save(lic);
  }

  // ---- Multi-device (Phase 3) --------------------------------------------

  /// Owner-visible active/released devices from the subscription authority.
  /// Requires an active backend session — devices are meaningless offline.
  String? _accountShopId(CachedLicense? lic) {
    if (lic != null && !lic.shopId.startsWith('free-')) return lic.shopId;
    return Supabase.instance.client.auth.currentUser?.appMetadata['shop_id']
        as String?;
  }

  Future<List<ShopDevice>> listDevices() async {
    if (!Env.hasBackend) return const [];
    final lic = await current();
    final res = await invokeActivate({
      'action': 'list_devices',
      'shop_id': _accountShopId(lic),
    });
    final data = parseInvokeData(res.data);
    if (data == null || data['ok'] != true) {
      throw StateError(errorCodeFromInvokeData(data) ?? 'server_error');
    }
    return (data['devices'] as List)
        .map((r) => ShopDevice.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Compatibility rejection for the retired key-provisioning action.
  Future<DeviceSlotResult> requestDeviceSlot() async {
    if (!Env.hasBackend) {
      return const DeviceSlotResult.failure('no_backend');
    }
    return const DeviceSlotResult.failure('retired_path');
  }

  /// Releases one of the shop's own devices (frees its slot for reuse by a
  /// new device) — the released device itself loses access on its next
  /// license re-verify.
  Future<bool> releaseDevice(String deviceId) async {
    if (!Env.hasBackend) return false;
    try {
      final lic = await current();
      final res = await invokeActivate({
        'action': 'release_device',
        'shop_id': _accountShopId(lic),
        'device_id': deviceId,
      });
      final data = res.data as Map<String, dynamic>;
      return data['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}

LicensePlan _planFrom(String s) => switch (s) {
  'yearly' => LicensePlan.yearly,
  'monthly' => LicensePlan.monthly,
  'free' => LicensePlan.free,
  _ => LicensePlan.trial,
};
