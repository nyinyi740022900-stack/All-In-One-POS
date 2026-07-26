import 'dart:convert';

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
      );
      // Refresh the session so the new shop_id claim lands in the JWT.
      try {
        await Supabase.instance.client.auth.refreshSession();
      } catch (_) {}
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

  /// Grants a one-time free 2-month trial. When online it goes through the
  /// `start_trial` Edge Function (server-tracked per device, so it can't be
  /// farmed by reinstalling, and stamps the shop_id claim for sync); offline it
  /// falls back to a local trial.
  Future<CachedLicense?> startFreeTrial() async {
    if (await _settings.trialUsed()) return null;
    final deviceId = await _settings.deviceId();
    final now = DateTime.now();

    if (Env.hasBackend) {
      try {
        final profile = await _settings.shopProfile();
        final res = await Supabase.instance.client.functions.invoke(
          'start_trial',
          body: {'device_id': deviceId, 'shop_name': profile.name},
        );
        final data = res.data as Map<String, dynamic>;
        if (data['ok'] == true) {
          final lic = CachedLicense(
            key: data['key'] as String,
            shopId: data['shop_id'] as String,
            plan: LicensePlan.trial,
            expiresAt: DateTime.parse(data['expires_at'] as String),
            activatedAt: DateTime.parse(
                (data['activated_at'] ?? now.toIso8601String()) as String),
            lastVerifiedAt: now,
            deviceId: deviceId,
          );
          try {
            await Supabase.instance.client.auth.refreshSession();
          } catch (_) {}
          await _settings.markTrialUsed();
          return _save(lic);
        }
      } catch (_) {/* fall back to a local trial */}
    }

    final lic = await _save(CachedLicense(
      key: 'FREE-TRIAL',
      shopId: 'trial-${deviceId.replaceAll('-', '').substring(0, 10)}',
      plan: LicensePlan.trial,
      expiresAt: now.add(const Duration(days: 60)),
      activatedAt: now,
      lastVerifiedAt: now,
      deviceId: deviceId,
    ));
    await _settings.markTrialUsed();
    return lic;
  }

  Future<void> deactivate() => _settings.clearLicense();

  // ---- Multi-device (Phase 3) --------------------------------------------

  /// The shop's device slots (one row per license key under this shop_id).
  /// Requires an active backend session — devices are meaningless offline.
  Future<List<ShopDevice>> listDevices() async {
    if (!Env.hasBackend) return const [];
    final rows = await Supabase.instance.client
        .from('licenses')
        .select('key, device_id, status, last_verified_at')
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
