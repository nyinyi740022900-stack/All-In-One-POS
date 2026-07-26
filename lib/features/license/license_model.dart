import 'license_status.dart';

LicensePlan _planFrom(String s) => switch (s) {
      'yearly' => LicensePlan.yearly,
      'monthly' => LicensePlan.monthly,
      _ => LicensePlan.trial,
    };

String planName(LicensePlan p) => switch (p) {
      LicensePlan.yearly => 'yearly',
      LicensePlan.monthly => 'monthly',
      LicensePlan.trial => 'trial',
    };

/// Locally cached license, refreshed from the server on activation/verify.
class CachedLicense {
  final String key;
  final String shopId;
  final LicensePlan plan;
  final DateTime expiresAt;
  final DateTime activatedAt;
  final DateTime lastVerifiedAt;
  final String deviceId;

  /// Admin-granted premium flag (no automated billing gateway exists, same
  /// precedent as the multi-device fee) — when true, `RealtimeSyncController`
  /// subscribes to Supabase Realtime so other devices under the shop see a
  /// change within seconds instead of waiting for the 5-minute poll.
  final bool realtimeEnabled;

  const CachedLicense({
    required this.key,
    required this.shopId,
    required this.plan,
    required this.expiresAt,
    required this.activatedAt,
    required this.lastVerifiedAt,
    required this.deviceId,
    this.realtimeEnabled = false,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'shop_id': shopId,
        'plan': planName(plan),
        'expires_at': expiresAt.toIso8601String(),
        'activated_at': activatedAt.toIso8601String(),
        'last_verified_at': lastVerifiedAt.toIso8601String(),
        'device_id': deviceId,
        'realtime_enabled': realtimeEnabled,
      };

  factory CachedLicense.fromJson(Map<String, dynamic> j) => CachedLicense(
        key: j['key'] as String,
        shopId: j['shop_id'] as String,
        plan: _planFrom(j['plan'] as String? ?? 'trial'),
        expiresAt: DateTime.parse(j['expires_at'] as String),
        activatedAt: DateTime.parse(j['activated_at'] as String),
        lastVerifiedAt: DateTime.parse(
            (j['last_verified_at'] ?? j['activated_at']) as String),
        deviceId: j['device_id'] as String? ?? '',
        realtimeEnabled: j['realtime_enabled'] as bool? ?? false,
      );

  CachedLicense copyWith({
    DateTime? lastVerifiedAt,
    DateTime? expiresAt,
    bool? realtimeEnabled,
  }) =>
      CachedLicense(
        key: key,
        shopId: shopId,
        plan: plan,
        expiresAt: expiresAt ?? this.expiresAt,
        activatedAt: activatedAt,
        lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
        deviceId: deviceId,
        realtimeEnabled: realtimeEnabled ?? this.realtimeEnabled,
      );
}

/// Outcome of an activation attempt.
class ActivationResult {
  final bool ok;
  final String? errorCode;
  final CachedLicense? license;

  const ActivationResult.success(this.license) : ok = true, errorCode = null;
  const ActivationResult.failure(this.errorCode) : ok = false, license = null;
}

/// One device slot under the shop's license (a row in `licenses`). [deviceId]
/// is null for a released/unclaimed slot waiting to be picked up by a new
/// device.
class ShopDevice {
  final String key;
  final String? deviceId;
  final String status;
  final DateTime? lastVerifiedAt;

  const ShopDevice({
    required this.key,
    required this.deviceId,
    required this.status,
    required this.lastVerifiedAt,
  });

  bool get isBound => deviceId != null && deviceId!.isNotEmpty;

  factory ShopDevice.fromJson(Map<String, dynamic> j) => ShopDevice(
        key: j['key'] as String,
        deviceId: j['device_id'] as String?,
        status: j['status'] as String? ?? 'active',
        lastVerifiedAt: j['last_verified_at'] == null
            ? null
            : DateTime.parse(j['last_verified_at'] as String),
      );
}

/// Outcome of requesting a new device slot: either a key ready to activate on
/// the new device, or a one-time fee the shop must pay first.
class DeviceSlotResult {
  final bool ok;
  final String? key;
  final int? fee;
  final String? errorCode;

  const DeviceSlotResult.granted(this.key)
      : ok = true, fee = null, errorCode = null;
  const DeviceSlotResult.paymentRequired(this.fee)
      : ok = false, key = null, errorCode = 'payment_required';
  const DeviceSlotResult.failure(this.errorCode)
      : ok = false, key = null, fee = null;
}
