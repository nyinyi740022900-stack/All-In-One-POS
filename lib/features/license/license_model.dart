import 'license_status.dart';

LicensePlan _planFrom(String s) => switch (s) {
      'yearly' => LicensePlan.yearly,
      'monthly' => LicensePlan.monthly,
      'free' => LicensePlan.free,
      _ => LicensePlan.trial,
    };

String planName(LicensePlan p) => switch (p) {
      LicensePlan.yearly => 'yearly',
      LicensePlan.monthly => 'monthly',
      LicensePlan.trial => 'trial',
      LicensePlan.free => 'free',
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

  /// Fixed at shop-creation time — 'online' for a shop minted by the
  /// self-serve signup/create-branch actions, 'offline' for everything else
  /// (key activate, device trial, admin-issued key). Never re-derived from
  /// whichever session type happens to be active later (a real login can be
  /// added to an offline shop too), so pricing (`VendorConfig.priceFor`)
  /// stays correct regardless of how the shop is currently being used.
  final String tier;

  const CachedLicense({
    required this.key,
    required this.shopId,
    required this.plan,
    required this.expiresAt,
    required this.activatedAt,
    required this.lastVerifiedAt,
    required this.deviceId,
    this.realtimeEnabled = false,
    this.tier = 'offline',
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
        'tier': tier,
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
        tier: j['tier'] as String? ?? 'offline',
      );

  CachedLicense copyWith({
    DateTime? lastVerifiedAt,
    DateTime? expiresAt,
    bool? realtimeEnabled,
    String? tier,
    LicensePlan? plan,
    String? key,
  }) =>
      CachedLicense(
        key: key ?? this.key,
        shopId: shopId,
        plan: plan ?? this.plan,
        expiresAt: expiresAt ?? this.expiresAt,
        activatedAt: activatedAt,
        lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
        deviceId: deviceId,
        realtimeEnabled: realtimeEnabled ?? this.realtimeEnabled,
        tier: tier ?? this.tier,
      );
}

/// Local-only Free plan from onboarding ("Continue Free"), not a real
/// cloud shop. Safe to replace when the owner signs into a paid account on
/// a new install. A downgraded *real* shop keeps its `shop-…` id and still
/// needs the wipe-confirm dialog if they sign into a different account.
bool isReplaceableLocalLicense(CachedLicense? lic) {
  if (lic == null) return true;
  return lic.shopId.startsWith('free-');
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
/// device. [realtimeEnabled]/[createdAt] are used to rank this shop's
/// devices for the Realtime connection-pool cap — see
/// `sync_providers.dart`'s `realtimePriorityRank`.
class ShopDevice {
  final String key;
  final String? deviceId;
  final String status;
  final DateTime? lastVerifiedAt;
  final bool realtimeEnabled;
  final DateTime createdAt;

  const ShopDevice({
    required this.key,
    required this.deviceId,
    required this.status,
    required this.lastVerifiedAt,
    required this.createdAt,
    this.realtimeEnabled = false,
  });

  bool get isBound => deviceId != null && deviceId!.isNotEmpty;

  factory ShopDevice.fromJson(Map<String, dynamic> j) => ShopDevice(
        key: j['key'] as String,
        deviceId: j['device_id'] as String?,
        status: j['status'] as String? ?? 'active',
        lastVerifiedAt: j['last_verified_at'] == null
            ? null
            : DateTime.parse(j['last_verified_at'] as String),
        realtimeEnabled: j['realtime_enabled'] as bool? ?? false,
        createdAt: j['created_at'] == null
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : DateTime.parse(j['created_at'] as String),
      );
}

/// Bound license rows minus the shop's main phone. The first slot is
/// included and does not count; a phone and a computer each count as one
/// extra. Owner vs staff login does not change the count — only the device.
int extraDevicesUsed(int boundCount) => boundCount <= 0 ? 0 : boundCount - 1;

/// Extra phones/computers included besides the main phone.
/// [freeLimit] is the TOTAL cap stored in `device.free_limit` (default 3).
int extraDeviceQuota(int freeLimit) => freeLimit <= 1 ? 0 : freeLimit - 1;

/// Paid extras Support granted on top of the free cap (main phone + 2).
/// [extraSlots] is ignored after [extrasExpiresAt].
class ShopDeviceAllowance {
  final int extraSlots;
  final DateTime? extrasExpiresAt;

  const ShopDeviceAllowance({
    this.extraSlots = 0,
    this.extrasExpiresAt,
  });

  static const none = ShopDeviceAllowance();

  int activeExtraSlots(DateTime now) {
    if (extraSlots <= 0) return 0;
    if (extrasExpiresAt != null && !extrasExpiresAt!.isAfter(now)) return 0;
    return extraSlots;
  }
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
