import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin client over the `admin` Edge Function. Every call carries the current
/// admin session's JWT (added automatically by `functions.invoke`); the
/// function verifies the `role=admin` claim and uses the service role
/// server-side. The web app never holds the service key.
class AdminApi {
  SupabaseClient get _c => Supabase.instance.client;

  bool get isSignedIn => _c.auth.currentSession != null;

  bool get isAdmin =>
      (_c.auth.currentUser?.appMetadata['role']) == 'admin';

  Future<void> signIn(String email, String password) =>
      _c.auth.signInWithPassword(email: email, password: password);

  Future<void> signOut() => _c.auth.signOut();

  Future<List<Map<String, dynamic>>> _rows(String action) async {
    final res = await _c.functions.invoke('admin', body: {'action': action});
    _throwIfError(res);
    return (((res.data as Map)['rows'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  Future<List<Map<String, dynamic>>> listLicenses() => _rows('list_licenses');
  Future<List<Map<String, dynamic>>> listRequests() => _rows('list_requests');
  Future<List<Map<String, dynamic>>> listEvents() => _rows('list_events');
  Future<List<Map<String, dynamic>>> listReferrals() => _rows('list_referrals');
  Future<List<Map<String, dynamic>>> listCommissions() =>
      _rows('list_commissions');

  /// Redeems a referrer's outstanding balance into whole license months on
  /// their own license. Returns { months, amount, expires_at, balance }
  /// (months == 0 when the balance isn't yet one month's price).
  Future<Map<String, dynamic>> applyReferralCredit(
      {required String shopId}) async {
    final res = await _c.functions.invoke('admin',
        body: {'action': 'apply_referral_credit', 'shop_id': shopId});
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
    final res = await _c.functions.invoke('admin', body: {
      'action': 'sign_offline',
      'shop_id': shopId,
      if (shopName != null && shopName.isNotEmpty) 'shop_name': shopName,
      'plan': plan,
      'months': months,
      if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
    });
    _throwIfError(res);
    return (res.data as Map)['token'] as String;
  }

  Future<int> resetDevice({required String deviceId}) async {
    final res = await _c.functions.invoke('admin',
        body: {'action': 'reset_device', 'device_id': deviceId});
    _throwIfError(res);
    return ((res.data as Map)['cleared'] as num?)?.toInt() ?? 0;
  }

  Future<String> extendByDevice(
      {required String deviceId, required int months}) async {
    final res = await _c.functions.invoke('admin', body: {
      'action': 'extend_by_device',
      'device_id': deviceId,
      'months': months,
    });
    _throwIfError(res);
    return '${(res.data as Map)['expires_at']}';
  }

  Future<String> fulfillRequest({required String requestId, int? months}) async {
    final body = <String, dynamic>{
      'action': 'fulfill_request',
      'request_id': requestId,
    };
    if (months != null) body['months'] = months;
    final res = await _c.functions.invoke('admin', body: body);
    _throwIfError(res);
    return (res.data as Map)['key'] as String;
  }

  Future<Map<String, String>> getConfig() async {
    final rows = await _rows('get_config');
    return {
      for (final r in rows) '${r['key']}': '${r['value'] ?? ''}',
    };
  }

  Future<void> setConfig(Map<String, String> config) async {
    final res = await _c.functions
        .invoke('admin', body: {'action': 'set_config', 'config': config});
    _throwIfError(res);
  }

  Future<String> createLicense({
    required String shopId,
    String? shopName,
    required String plan,
    required int months,
  }) async {
    final res = await _c.functions.invoke('admin', body: {
      'action': 'create_license',
      'shop_id': shopId,
      if (shopName != null && shopName.isNotEmpty) 'shop_name': shopName,
      'plan': plan,
      'months': months,
    });
    _throwIfError(res);
    return (res.data as Map)['key'] as String;
  }

  void _throwIfError(FunctionResponse res) {
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw Exception('${data['error']}${data['detail'] != null ? ': ${data['detail']}' : ''}');
    }
    if (res.status >= 400) {
      throw Exception('Request failed (${res.status})');
    }
  }
}
