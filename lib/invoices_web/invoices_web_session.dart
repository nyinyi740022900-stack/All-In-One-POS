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

  /// Sign in with the shop's existing email/password. Does **not** consume a
  /// device-key slot — same session as Settings → Account on the phone.
  /// Returns an error code, or null on success.
  static Future<String?> signIn(String email, String password) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty || password.isEmpty) return 'empty_signin';
    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: trimmed,
        password: password,
      );
      final shopId = res.user?.appMetadata['shop_id'] as String?;
      if (shopId == null || shopId.isEmpty) {
        await Supabase.instance.client.auth.signOut();
        return 'not_a_shop';
      }
      return null;
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('invalid') || m.contains('credential')) {
        return 'wrong_password';
      }
      return 'network_error';
    } catch (_) {
      return 'network_error';
    }
  }

  /// Activates this browser with a device key generated from the shop's
  /// phone (Settings > License > Add a device, Offline shops only).
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
    final Map<String, dynamic> data;
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'activate',
        body: {'key': trimmed, 'device_id': deviceId},
      );
      data = res.data as Map<String, dynamic>;
    } catch (_) {
      return 'network_error';
    }
    if (data['ok'] != true) {
      return (data['error'] as String?) ?? 'activation_failed';
    }
    // The Edge Function call above already succeeded server-side — this
    // device's slot is consumed — so a failure from here on must never be
    // reported as a generic activation failure (a naive retry could then
    // hit an "already activated" rejection and confuse the user further).
    // A freshly-granted shop_id claim can lag behind the cached JWT until
    // the next refresh, so give it one retry before giving up; if it still
    // doesn't stick, tell the caller activation succeeded but the browser
    // needs a reload to pick up the new session.
    try {
      await auth.refreshSession();
      return null;
    } catch (_) {
      try {
        await auth.refreshSession();
        return null;
      } catch (_) {
        return 'activated_refresh_pending';
      }
    }
  }

  static Future<void> signOut() => Supabase.instance.client.auth.signOut();
}
