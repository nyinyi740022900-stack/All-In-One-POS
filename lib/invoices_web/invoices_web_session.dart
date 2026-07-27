import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Minimal device-activation logic for the Invoices Web companion. Reuses
/// the exact same flow the mobile app's License screen uses (anonymous
/// Supabase auth + the `activate` Edge Function, which sets a `shop_id` JWT
/// claim on this browser's own session) — a browser tab activated this way
/// consumes one of the shop's device slots, same as adding another phone.
/// Deliberately doesn't pull in the full Drift/SettingsRepository stack this
/// standalone read-only companion has no other use for.
class InvoicesWebSession {
  InvoicesWebSession._();

  static const _storage = FlutterSecureStorage();
  static const _deviceIdKey = 'invoices_web_device_id';

  static Future<String> _deviceId() async {
    var id = await _storage.read(key: _deviceIdKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await _storage.write(key: _deviceIdKey, value: id);
    }
    return id;
  }

  /// The shop this browser is activated for, or null if not yet activated.
  static String? get shopId => Supabase
      .instance.client.auth.currentSession?.user.appMetadata['shop_id'] as String?;

  /// Activates this browser with a device key generated from the shop's
  /// phone (Settings > License > Add device). Returns an error code on
  /// failure (`invalid_key`, `device_mismatch`, `payment_required`, etc. —
  /// the same codes the mobile app's activation flow already surfaces), or
  /// null on success.
  static Future<String?> activate(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return 'empty_key';
    final auth = Supabase.instance.client.auth;
    if (auth.currentSession == null) {
      await auth.signInAnonymously();
    }
    final deviceId = await _deviceId();
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'activate',
        body: {'key': trimmed, 'device_id': deviceId},
      );
      final data = res.data as Map<String, dynamic>;
      if (data['ok'] != true) {
        return (data['error'] as String?) ?? 'activation_failed';
      }
      await auth.refreshSession();
      return null;
    } catch (_) {
      return 'network_error';
    }
  }

  static Future<void> signOut() => Supabase.instance.client.auth.signOut();
}
