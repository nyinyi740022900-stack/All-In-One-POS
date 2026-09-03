import 'dart:convert';

import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../data/repositories/settings_repository.dart';
import 'invoke_error.dart';
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
      final res = await invokeActivate(
        {'key': trimmed, 'device_id': deviceId},
      );
      final data = parseInvokeData(res.data);
      if (data == null) {
        return const ActivationResult.failure('server_error');
      }
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
      return ActivationResult.failure(classifyInvokeError(e));
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
  /// session instead of creating a separate account. [trialKey] is a local
  /// placeholder key, same
  /// non-lookup-able-but-harmless convention `signupShop`'s `'SIGNUP'` key
  /// already uses — there's no per-key server lookup for this plan type.
  Future<ActivationResult> startFreeTrial(String shopName) async {
    if (!Env.hasBackend) return const ActivationResult.failure('no_backend');
    final deviceId = await _settings.deviceId();

    try {
      final res = await invokeActivate(
        {
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
        key: trialKey,
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
    } catch (e) {
      return ActivationResult.failure(classifyInvokeError(e));
    }
  }

  /// Last-resort recovery when [refreshSessionAndVerifyClaim] keeps failing
  /// even after its own retry. Asks the server to re-stamp this session's
  /// `app_metadata.shop_id` from the device's existing license (looked up
  /// by device_id rather than key, since a self-serve trial's cached key
  /// is only ever the local [trialKey] placeholder).
  ///
  /// Must keep the current session: `resync_session` requires the JWT to
  /// already carry this license's `shop_id` (device_id is the public App
  /// Reference ID and is not proof of ownership). Signing out and signing
  /// in anonymously used to be the recovery path — it is also the hijack
  /// (anyone who knows the public id could stamp a fresh anon session).
  Future<ActivationResult> repairSession() async {
    if (!Env.hasBackend) return const ActivationResult.failure('no_backend');
    final current = await this.current();
    if (current == null) {
      return const ActivationResult.failure('not_activated');
    }
    final deviceId = await _settings.deviceId();
    final auth = Supabase.instance.client.auth;
    if (auth.currentUser == null) {
      return const ActivationResult.failure('not_authenticated');
    }
    try {
      final res = await invokeActivate({
        'action': 'resync_session',
        'device_id': deviceId,
      });
      final data = res.data as Map<String, dynamic>;
      if (data['ok'] != true) {
        return ActivationResult.failure(
            (data['error'] as String?) ?? 'server_error');
      }
      final now = DateTime.now();
      // shop_id/device_id are unchanged by design — resync_session looks the
      // license up by this exact device_id, so the shop_id it returns is
      // always this device's own shop; copyWith doesn't (and shouldn't)
      // let either be overridden.
      final lic = current.copyWith(
        plan: _planFrom(data['plan'] as String? ?? 'monthly'),
        expiresAt: DateTime.parse(data['expires_at'] as String),
        lastVerifiedAt: now,
        tier: data['tier'] as String? ?? 'offline',
      );
      // The session should carry the claim immediately (it was just
      // restamped, synchronously, before this response came back) — verify
      // rather than assume, same discipline every other mint/activate path
      // here already follows.
      final verified = await refreshSessionAndVerifyClaim(lic.shopId);
      if (!verified) return const ActivationResult.failure('network_error');
      return ActivationResult.success(await _save(lic));
    } catch (_) {
      return const ActivationResult.failure('network_error');
    }
  }

  /// Pulls this signed-in shop's current plan + expiry (admin extend) onto
  /// the device without a typed key — Settings → Check for renewal, and
  /// email sign-in on a new install.
  Future<ActivationResult> refreshAccountLicense() async {
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
    var result = await _refreshAccountLicenseOnce();
    for (var attempt = 0;
        attempt < 2 &&
            (result.errorCode == 'not_activated' ||
                result.errorCode == 'not_authenticated');
        attempt++) {
      await refreshSessionBounded();
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      result = await _refreshAccountLicenseOnce();
    }
    return result;
  }

  Future<ActivationResult> _refreshAccountLicenseOnce() async {
    final deviceId = await _settings.deviceId();
    final Map<String, dynamic> data;
    try {
      final res = await invokeActivate({
        'action': 'refresh_account_license',
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
      activatedAt: DateTime.tryParse(
            data['activated_at'] as String? ?? '',
          ) ??
          current?.activatedAt ??
          now,
      lastVerifiedAt: now,
      deviceId: deviceId,
      realtimeEnabled: data['realtime_enabled'] as bool? ?? false,
      tier: data['tier'] as String? ?? current?.tier ?? 'online',
    );
    await refreshSessionAndVerifyClaim(lic.shopId);
    return ActivationResult.success(await _save(lic));
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
      key: freeKey,
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
      key: freeKey,
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

  /// Paid extra slots Support granted for this shop (on top of the free
  /// main-phone + 2). Empty when unsigned / offline / no grant row.
  Future<ShopDeviceAllowance> deviceAllowance() async {
    if (!Env.hasBackend) return ShopDeviceAllowance.none;
    try {
      final row = await Supabase.instance.client
          .from('shop_device_allowance')
          .select('extra_slots, extras_expires_at')
          .maybeSingle();
      if (row == null) return ShopDeviceAllowance.none;
      final extras = (row['extra_slots'] as num?)?.toInt() ?? 0;
      final raw = row['extras_expires_at'] as String?;
      return ShopDeviceAllowance(
        extraSlots: extras,
        extrasExpiresAt: raw == null ? null : DateTime.tryParse(raw),
      );
    } catch (_) {
      return ShopDeviceAllowance.none;
    }
  }

  /// Claims a slot for a NEW device under this shop: a free slot if the shop
  /// is under its device limit, or a fee to pay first. The returned key still
  /// needs to be activated (via [activate]) on the new physical device.
  Future<DeviceSlotResult> requestDeviceSlot() async {
    if (!Env.hasBackend) {
      return const DeviceSlotResult.failure('no_backend');
    }
    try {
      final res = await invokeActivate({'action': 'request_device_slot'});
      final parsed = parseInvokeData(res.data);
      if (parsed == null) {
        return const DeviceSlotResult.failure('server_error');
      }
      if (parsed['ok'] == true) {
        return DeviceSlotResult.granted(parsed['key'] as String);
      }
      if (parsed['error'] == 'payment_required') {
        return DeviceSlotResult.paymentRequired(parsed['fee'] as int? ?? 0);
      }
      return DeviceSlotResult.failure(parsed['error'] as String?);
    } catch (e) {
      return DeviceSlotResult.failure(classifyInvokeError(e));
    }
  }

  /// Releases one of the shop's own devices (frees its slot for reuse by a
  /// new device) — the released device itself loses access on its next
  /// license re-verify.
  Future<bool> releaseDevice(String deviceId) async {
    if (!Env.hasBackend) return false;
    try {
      final res = await invokeActivate({
        'action': 'release_device',
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
      _ => LicensePlan.trial,
    };
