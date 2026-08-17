import 'dart:convert';

import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../data/repositories/settings_repository.dart';
import 'license_model.dart';
import 'license_status.dart';
import 'offline_license.dart';

/// Owns license activation and local caching.
///
/// Online activation calls the `activate` Edge Function (which validates the
/// key, binds the device, and sets the JWT `shop_id` claim). When no backend
/// is configured it falls back to a local trial so development and offline
/// demos keep working.
class LicenseRepository {
  LicenseRepository(this._settings);

  final SettingsRepository _settings;

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

  Future<ActivationResult> activate(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return const ActivationResult.failure('empty_key');
    final deviceId = await _settings.deviceId();

    // Offline signed token: verify locally with the embedded public key — works
    // with no connectivity at all (activation + renewal for offline shops).
    if (OfflineLicense.looksLikeToken(trimmed)) {
      try {
        final lic = await OfflineLicense.verify(trimmed, deviceId);
        if (!lic.expiresAt.isAfter(DateTime.now())) {
          return const ActivationResult.failure('invalid_key'); // expired
        }
        return ActivationResult.success(await _save(lic));
      } on OfflineLicenseException catch (e) {
        return ActivationResult.failure(
            e.code == 'device_mismatch' ? 'device_mismatch' : 'invalid_key');
      }
    }

    if (!Env.hasBackend) {
      return ActivationResult.success(await _localTrial(trimmed, deviceId));
    }

    try {
      final res = await Supabase.instance.client.functions.invoke(
        'activate',
        body: {'key': trimmed, 'device_id': deviceId},
      );
      final data = res.data as Map<String, dynamic>;
      if (data['ok'] != true) {
        return ActivationResult.failure(
            (data['error'] as String?) ?? 'activation_failed');
      }
      final now = DateTime.now();
      final lic = CachedLicense(
        key: trimmed,
        shopId: data['shop_id'] as String,
        plan: _planFrom(data['plan'] as String? ?? 'monthly'),
        expiresAt: DateTime.parse(data['expires_at'] as String),
        activatedAt:
            DateTime.parse((data['activated_at'] ?? now.toIso8601String())
                as String),
        lastVerifiedAt: now,
        deviceId: deviceId,
        realtimeEnabled: data['realtime_enabled'] as bool? ?? false,
        tier: data['tier'] as String? ?? 'offline',
      );
      // Refresh the session and confirm the new shop_id claim actually
      // landed — best-effort (reported to Sentry on failure, never blocks
      // activation itself, since the license is already valid server-side).
      await refreshSessionAndVerifyClaim(lic.shopId);
      // Best-effort: cache the offline-verifiable fallback token the Edge
      // Function now issues alongside every activation, if present (older
      // deployments / a missing signing-key secret just omit it).
      final offlineToken = data['offline_token'] as String?;
      if (offlineToken != null && offlineToken.isNotEmpty) {
        await _settings.setLicenseOfflineFallbackToken(
          lic.shopId,
          offlineToken,
        );
      }
      return ActivationResult.success(await _save(lic));
    } catch (e) {
      return ActivationResult.failure('network_error');
    }
  }

  Future<CachedLicense> _localTrial(String key, String deviceId) {
    final now = DateTime.now();
    return _save(CachedLicense(
      key: key,
      shopId: 'demo-shop',
      plan: LicensePlan.trial,
      expiresAt: now.add(const Duration(days: 14)),
      activatedAt: now,
      lastVerifiedAt: now,
      deviceId: deviceId,
    )).then((v) => v!);
  }

  /// Self-serve, no-account Premium trial for a device on the Free plan (or
  /// never activated) — calls the `start_trial` action, which enforces one
  /// trial per `device_id` permanently (server-side; see `activate`'s
  /// `deviceAlreadyHasTrial`). No email/password, unlike the sibling
  /// `signup_shop` flow (`AccountRepository.signupShop`) — this stamps
  /// `app_metadata.shop_id` on the caller's own (possibly anonymous)
  /// session instead of creating a separate account. `'TRIAL'` is a local
  /// placeholder key, same
  /// non-lookup-able-but-harmless convention `signupShop`'s `'SIGNUP'` key
  /// already uses — there's no per-key server lookup for this plan type.
  Future<ActivationResult> startFreeTrial(String shopName) async {
    if (!Env.hasBackend) return const ActivationResult.failure('no_backend');
    final deviceId = await _settings.deviceId();

    try {
      final res = await Supabase.instance.client.functions.invoke(
        'activate',
        body: {
          'action': 'start_trial',
          'shop_name': shopName,
          'device_id': deviceId,
        },
      );
      final data = res.data as Map<String, dynamic>;
      if (data['ok'] != true) {
        return ActivationResult.failure(
            (data['error'] as String?) ?? 'server_error');
      }
      final now = DateTime.now();
      final lic = CachedLicense(
        key: 'TRIAL',
        shopId: data['shop_id'] as String,
        plan: LicensePlan.trial,
        expiresAt: DateTime.parse(data['expires_at'] as String),
        activatedAt:
            DateTime.tryParse(data['activated_at'] as String? ?? '') ?? now,
        lastVerifiedAt: now,
        deviceId: deviceId,
        tier: data['tier'] as String? ?? 'offline',
      );
      // Refresh the session and confirm the new shop_id claim actually
      // landed — see refreshSessionAndVerifyClaim's own doc comment; this is
      // the exact path that was silently failing before (a self-serve trial
      // whose session never picked up its shop_id claim, closed alongside
      // this change).
      await refreshSessionAndVerifyClaim(lic.shopId);
      final offlineToken = data['offline_token'] as String?;
      if (offlineToken != null && offlineToken.isNotEmpty) {
        await _settings.setLicenseOfflineFallbackToken(
          lic.shopId,
          offlineToken,
        );
      }
      return ActivationResult.success(await _save(lic));
    } catch (_) {
      return const ActivationResult.failure('network_error');
    }
  }

  /// Enters the Free plan from scratch — no key, no account, no network call.
  /// Core POS features (Sell/Inventory/etc.) work immediately and forever;
  /// only Premium-gated features stay locked (see `PremiumGate`). The shop_id
  /// is synthesized locally, same shape as the offline-trial fallback above,
  /// since a Free-plan shop has no server-side `licenses` row at all.
  Future<CachedLicense> startFreePlan() async {
    final deviceId = await _settings.deviceId();
    final now = DateTime.now();
    return (await _save(CachedLicense(
      key: 'FREE',
      shopId: 'free-${deviceId.replaceAll('-', '').substring(0, 10)}',
      plan: LicensePlan.free,
      expiresAt: now,
      activatedAt: now,
      lastVerifiedAt: now,
      deviceId: deviceId,
    )))!;
  }

  /// Drops an existing license to the Free plan while preserving its
  /// identity (`shopId`/`deviceId`/`tier`) — local data and sync keep working
  /// under the same shop, only Premium features stop being unlocked. Used
  /// both for auto-downgrade on expiry and for the sign-out-revokes-premium
  /// flow (see `LicenseController`/`AccountRepository`).
  Future<CachedLicense> downgradeToFree(CachedLicense current) async {
    final now = DateTime.now();
    return (await _save(current.copyWith(
      key: 'FREE',
      plan: LicensePlan.free,
      expiresAt: now,
      lastVerifiedAt: now,
    )))!;
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
        await auth.refreshSession();
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

  Future<void> deactivate() => _settings.clearLicense();

  /// Persists a [CachedLicense] built from somewhere other than `activate()`
  /// (e.g. a branch switch, which restamps the caller's own shop_id claim
  /// via a different Edge Function action). Same cache write `activate()`
  /// itself uses.
  Future<CachedLicense?> saveExternal(CachedLicense lic) => _save(lic);

  // ---- Multi-device (Phase 3) --------------------------------------------

  /// The shop's device slots (one row per license key under this shop_id).
  /// Requires an active backend session — devices are meaningless offline.
  Future<List<ShopDevice>> listDevices() async {
    if (!Env.hasBackend) return const [];
    final rows = await Supabase.instance.client
        .from('licenses')
        .select(
          'key, device_id, status, last_verified_at, realtime_enabled, created_at',
        )
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => ShopDevice.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Claims a slot for a NEW device under this shop: a free slot if the shop
  /// is under its device limit, or a fee to pay first. The returned key still
  /// needs to be activated (via [activate]) on the new physical device.
  Future<DeviceSlotResult> requestDeviceSlot() async {
    if (!Env.hasBackend) {
      return const DeviceSlotResult.failure('no_backend');
    }
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'activate',
        body: {'action': 'request_device_slot'},
      );
      final data = res.data as Map<String, dynamic>;
      if (data['ok'] == true) {
        return DeviceSlotResult.granted(data['key'] as String);
      }
      if (data['error'] == 'payment_required') {
        return DeviceSlotResult.paymentRequired(data['fee'] as int? ?? 0);
      }
      return DeviceSlotResult.failure(data['error'] as String?);
    } catch (_) {
      return const DeviceSlotResult.failure('network_error');
    }
  }

  /// Releases one of the shop's own devices (frees its slot for reuse by a
  /// new device) — the released device itself loses access on its next
  /// license re-verify.
  Future<bool> releaseDevice(String deviceId) async {
    if (!Env.hasBackend) return false;
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'activate',
        body: {'action': 'release_device', 'device_id': deviceId},
      );
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
      _ => LicensePlan.trial,
    };
