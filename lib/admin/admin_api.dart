import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/net/edge_invoke.dart';

/// The licence was issued but its request row is still open — see
/// [AdminApi.confirmPayment]. Confirming again would mint a second licence
/// for the same payment, so this must never be presented as a plain failure
/// the admin can retry.
class RequestNotClosedException implements Exception {
  const RequestNotClosedException({required this.key, this.detail = ''});
  final String key;
  final String detail;
  @override
  String toString() => 'request_not_closed';
}

class ExtendLicenseResult {
  const ExtendLicenseResult({
    required this.expiresAt,
    required this.created,
    this.duplicate = false,
  });
  final String expiresAt;
  final bool created;

  /// The server suppressed this call as a repeat of a recent identical
  /// extend (same key, same months, inside its dedup window) and granted
  /// **nothing**. Reporting it as a plain success is a real error: a shop
  /// that pays for two separate 1-month top-ups in quick succession would be
  /// shown "Extended to `<date>`" twice while receiving one month.
  final bool duplicate;
}

class DeviceAllowanceResult {
  const DeviceAllowanceResult({
    required this.extraSlots,
    this.extrasExpiresAt,
  });
  final int extraSlots;
  final String? extrasExpiresAt;
}

/// Thrown by [AdminApi.createLicense] when the shop already has a
/// non-deleted license row — create_license has no shop_id uniqueness
/// guard at the DB level, so the caller must be stopped from minting a
/// second live license for the same shop (should use Extend instead).
class LicenseAlreadyExistsException implements Exception {
  const LicenseAlreadyExistsException();
  @override
  String toString() => 'license_already_exists';
}

/// Thin client over the `admin` Edge Function. Every call carries the current
/// admin session's JWT (added automatically by `functions.invoke`); the
/// function verifies the `role=admin` claim and uses the service role
/// server-side. The web app never holds the service key.
class AdminApi {
  SupabaseClient get _c => Supabase.instance.client;

  bool get isSignedIn => _c.auth.currentSession != null;

  bool get isAdmin => (_c.auth.currentUser?.appMetadata['role']) == 'admin';

  Future<void> signIn(String email, String password) =>
      _c.auth.signInWithPassword(email: email, password: password);

  Future<void> signOut() => _c.auth.signOut();

  Future<List<Map<String, dynamic>>> _rows(String action) async {
    final res = await _c.functions.invokeBounded('admin', body: {'action': action});
    _throwIfError(res);
    return (((res.data as Map)['rows'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  Future<List<Map<String, dynamic>>> listLicenses() => _rows('list_licenses');
  Future<List<Map<String, dynamic>>> listShops() => _rows('list_shops');
  Future<List<Map<String, dynamic>>> listRequests() => _rows('list_requests');
  Future<List<Map<String, dynamic>>> listEvents() => _rows('list_events');
  Future<List<Map<String, dynamic>>> listReferrals() => _rows('list_referrals');
  Future<List<Map<String, dynamic>>> listCommissions() =>
      _rows('list_commissions');

  /// Fresh shop payload for the extend-preview dialog. Pass exactly one of
  /// [email] / [deviceId] / [shopId].
  Future<Map<String, dynamic>> lookupShop({
    String? email,
    String? deviceId,
    String? shopId,
  }) async {
    final res = await _c.functions.invokeBounded(
      'admin',
      body: {
        'action': 'lookup_shop',
        if (email != null && email.isNotEmpty) 'email': email,
        if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
        if (shopId != null && shopId.isNotEmpty) 'shop_id': shopId,
      },
    );
    _throwIfError(res);
    return ((res.data as Map)['shop'] as Map).cast<String, dynamic>();
  }

  /// Recovery URL the admin copies onto Viber. Never emails the shop —
  /// this product does not rely on SMTP for account recovery.
  Future<String> resetPassword({required String email}) async {
    final res = await _c.functions.invokeBounded(
      'admin',
      body: {'action': 'reset_password', 'email': email},
    );
    _throwIfError(res);
    return '${(res.data as Map)['action_link']}';
  }

  Future<void> unlinkAccount({required String userId}) async {
    final res = await _c.functions.invokeBounded(
      'admin',
      body: {'action': 'unlink_account', 'user_id': userId},
    );
    _throwIfError(res);
  }

  Future<void> restoreAccount({required String userId}) async {
    final res = await _c.functions.invokeBounded(
      'admin',
      body: {'action': 'restore_account', 'user_id': userId},
    );
    _throwIfError(res);
  }

  /// Redeems a referrer's outstanding balance into whole license months on
  /// their own license. Returns { months, amount, expires_at, balance }
  /// (months == 0 when the balance isn't yet one month's price).
  Future<Map<String, dynamic>> applyReferralCredit({
    required String shopId,
  }) async {
    final res = await _c.functions.invokeBounded(
      'admin',
      body: {'action': 'apply_referral_credit', 'shop_id': shopId},
    );
    _throwIfError(res);
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<String> signOffline({
    required String shopId,
    String? shopName,
    required String plan,
    required int months,
    String? deviceId,
  }) async {
    final res = await _c.functions.invokeBounded(
      'admin',
      body: {
        'action': 'sign_offline',
        'shop_id': shopId,
        if (shopName != null && shopName.isNotEmpty) 'shop_name': shopName,
        'plan': plan,
        'months': months,
        if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
      },
    );
    _throwIfError(res);
    return (res.data as Map)['token'] as String;
  }

  Future<int> resetDevice({required String deviceId}) async {
    final res = await _c.functions.invokeBounded(
      'admin',
      body: {'action': 'reset_device', 'device_id': deviceId},
    );
    _throwIfError(res);
    return ((res.data as Map)['cleared'] as num?)?.toInt() ?? 0;
  }

  /// Extends whichever license matches [deviceId] (a specific device) or
  /// [email] (the shop's account, any device) — pass whichever the admin
  /// has on hand, at least one is required. If the resolved shop has an
  /// account but no license row at all (e.g. one removed by a data
  /// cleanup while the login was kept), mints a fresh one instead of
  /// failing — [ExtendLicenseResult.created] tells the caller which
  /// happened, for the confirmation message.
  Future<ExtendLicenseResult> extendLicense({
    String? deviceId,
    String? email,
    required int months,
  }) async {
    final res = await _c.functions.invokeBounded(
      'admin',
      body: {
        'action': 'extend_license',
        if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
        if (email != null && email.isNotEmpty) 'email': email,
        'months': months,
      },
    );
    _throwIfError(res);
    final data = res.data as Map;
    return ExtendLicenseResult(
      expiresAt: '${data['expires_at']}',
      created: data['created'] == true,
      duplicate: data['duplicate'] == true,
    );
  }

  /// Confirms a paid renewal request: mints or extends the licence, then
  /// marks the request fulfilled.
  ///
  /// Throws [RequestNotClosedException] when the licence was issued but the
  /// request row could NOT be flipped to `fulfilled` — the server returns
  /// HTTP 200 with `request_marked_fulfilled: false` for exactly this case,
  /// precisely so the caller does not treat it as a clean success. Ignoring
  /// it was a real double-mint path: the request reappears as pending, the
  /// admin clicks Confirm again, the pending->processing claim succeeds
  /// (the status genuinely is still pending), and `create_license` — which
  /// has no shop_id uniqueness guard — mints a SECOND licence for one
  /// payment.
  Future<String> confirmPayment({
    required String requestId,
    int? months,
  }) async {
    final body = <String, dynamic>{
      'action': 'fulfill_request',
      'request_id': requestId,
    };
    if (months != null) body['months'] = months;
    final res = await _c.functions.invokeBounded('admin', body: body);
    _throwIfError(res);
    final data = res.data as Map;
    final key = data['key'] as String;
    if (data['request_marked_fulfilled'] == false) {
      throw RequestNotClosedException(
        key: key,
        detail: '${data['detail'] ?? ''}',
      );
    }
    return key;
  }

  Future<void> rejectRequest({
    required String requestId,
    String? reason,
  }) async {
    final res = await _c.functions.invokeBounded(
      'admin',
      body: {
        'action': 'reject_request',
        'request_id': requestId,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
    _throwIfError(res);
  }

  Future<Map<String, String>> getConfig() async {
    final rows = await _rows('get_config');
    return {for (final r in rows) '${r['key']}': '${r['value'] ?? ''}'};
  }

  Future<void> setConfig(Map<String, String> config) async {
    final res = await _c.functions.invokeBounded(
      'admin',
      body: {'action': 'set_config', 'config': config},
    );
    _throwIfError(res);
  }

  /// Throws [LicenseAlreadyExistsException] when [shopId] already has a
  /// license — most callers reach this only via the Shops-tab "Generate
  /// key" button (shown solely for status: 'no_license' rows), but the FAB
  /// dialog accepts any typed-in shop_id, so this guard is what actually
  /// stops a duplicate live license there.
  Future<String> createLicense({
    required String shopId,
    String? shopName,
    required String plan,
    required int months,
  }) async {
    final res = await _c.functions.invokeBounded(
      'admin',
      body: {
        'action': 'create_license',
        'shop_id': shopId,
        if (shopName != null && shopName.isNotEmpty) 'shop_name': shopName,
        'plan': plan,
        'months': months,
      },
    );
    if (res.data is Map &&
        (res.data as Map)['error'] == 'license_already_exists') {
      throw const LicenseAlreadyExistsException();
    }
    _throwIfError(res);
    return (res.data as Map)['key'] as String;
  }

  /// Sets how many paid extra devices this shop may use (on top of the
  /// free main phone + 2) and for how many months. No key is issued —
  /// they sign in on the new device and tap Check for renewal.
  Future<DeviceAllowanceResult> setDeviceAllowance({
    required String shopId,
    required int extraSlots,
    required int months,
  }) async {
    final res = await _c.functions.invokeBounded(
      'admin',
      body: {
        'action': 'set_device_allowance',
        'shop_id': shopId,
        'extra_slots': extraSlots,
        'months': months,
      },
    );
    _throwIfError(res);
    final data = res.data as Map;
    return DeviceAllowanceResult(
      extraSlots: (data['extra_slots'] as num?)?.toInt() ?? extraSlots,
      extrasExpiresAt: data['extras_expires_at'] as String?,
    );
  }

  void _throwIfError(FunctionResponse res) {
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw Exception(
        '${data['error']}${data['detail'] != null ? ': ${data['detail']}' : ''}',
      );
    }
    if (res.status >= 400) {
      throw Exception('Request failed (${res.status})');
    }
  }
}
