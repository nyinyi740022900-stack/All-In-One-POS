import 'package:uuid/uuid.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/net/edge_invoke.dart';

class ExtendLicenseResult {
  const ExtendLicenseResult({
    required this.expiresAt,
    required this.created,
    this.duplicate = false,
  });
  final String expiresAt;
  final bool created;

  /// A retry returned the stored result for the same persisted operation ID.
  final bool duplicate;
}

class AdminApi {
  SupabaseClient get _c => Supabase.instance.client;

  bool get isSignedIn => _c.auth.currentSession != null;

  bool get isAdmin => (_c.auth.currentUser?.appMetadata['role']) == 'admin';

  Future<void> signIn(String email, String password) =>
      _c.auth.signInWithPassword(email: email, password: password);

  Future<void> signOut() => _c.auth.signOut();

  Future<List<Map<String, dynamic>>> _rows(
    String action, [
    Map<String, dynamic> extra = const {},
  ]) async {
    final res = await _c.functions.invokeBounded(
      'admin',
      body: {'action': action, ...extra},
    );
    _throwIfError(res);
    return (((res.data as Map)['rows'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  Future<List<Map<String, dynamic>>> listLicenses() => _rows('list_licenses');

  /// The console's shop list. [archived] swaps it for the shops hidden by
  /// [setShopArchived] instead of the live ones — either/or, not a merged
  /// list, because an archived shop's licence is revoked and it must not sit
  /// next to live shops on a screen where "extend" is one click away.
  Future<List<Map<String, dynamic>>> listShops({bool archived = false}) =>
      _rows('list_shops', archived ? const {'archived': true} : const {});
  Future<List<Map<String, dynamic>>> listRequests() => _rows('list_requests');
  Future<List<Map<String, dynamic>>> listEvents() => _rows('list_events');

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

  Future<int> resetDevice({
    required String shopId,
    required String deviceId,
  }) async {
    final res = await _c.functions.invokeBounded(
      'admin',
      body: {
        'action': 'reset_device',
        'shop_id': shopId,
        'device_id': deviceId,
      },
    );
    _throwIfError(res);
    return ((res.data as Map)['rows'] as num?)?.toInt() ?? 0;
  }

  /// Preserve an operation id until the server has confirmed it. A reload
  /// after a lost response must retry the same payment, not grant twice.
  Future<ExtendLicenseResult> extendSubscription({
    required String shopId,
    required int months,
  }) async {
    const prefs = FlutterSecureStorage();
    final pendingKey = 'admin.renewal.$shopId.$months';
    final operationId = await prefs.read(key: pendingKey) ?? const Uuid().v4();
    await prefs.write(key: pendingKey, value: operationId);
    final res = await _c.functions.invokeBounded(
      'admin',
      body: {
        'action': 'extend_license',
        'shop_id': shopId,
        'months': months,
        'id': operationId,
      },
    );
    _throwIfError(res);
    final data = res.data as Map;
    await prefs.delete(key: pendingKey);
    return ExtendLicenseResult(
      expiresAt: '${data['expires_at']}',
      created: false,
      duplicate: data['duplicate'] == true,
    );
  }

  Future<String> confirmPayment({required String requestId}) async {
    final res = await _c.functions.invokeBounded(
      'admin',
      body: {'action': 'fulfill_request', 'request_id': requestId},
    );
    _throwIfError(res);
    return '${(res.data as Map)['expires_at']}';
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

  /// Hides a shop from the console, or brings it back.
  ///
  /// Not cosmetic: this flips `licenses.is_deleted`, which `activate`'s
  /// re-verify and resync also filter on — so archiving **revokes the shop's
  /// licence** and its app drops to Free at the next check. That is the point
  /// for a test or abandoned shop. The server refuses outright
  /// (`shop_is_paid`) when the shop still holds an active paid licence, so
  /// this cannot quietly cut off a paying customer.
  ///
  /// Reversible: pass `archived: false` to put every row back.
  Future<void> setShopArchived({
    required String shopId,
    required bool archived,
  }) async {
    final res = await _c.functions.invokeBounded(
      'admin',
      body: {
        'action': 'set_shop_archived',
        'shop_id': shopId,
        'archived': archived,
      },
    );
    _throwIfError(res);
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
