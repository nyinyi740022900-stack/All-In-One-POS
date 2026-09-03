import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../features/license/invoke_error.dart';

/// Minimal device-activation logic for the Invoices Web companion. Reuses
/// the exact same flow the mobile app's License screen uses (Supabase auth
/// + the `activate` Edge Function). A browser tab that signs in consumes
/// one of the shop's device slots — a phone and a computer each count as
/// one extra, same as Windows POS.
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
  static String? get shopId => shopIdOfCurrentUser();

  static String? shopIdOfCurrentUser() =>
      Supabase.instance.client.auth.currentUser?.appMetadata['shop_id']
          as String?;

  /// Sign in with the shop's existing email/password, then bind this
  /// browser as a device (Check for renewal equivalent). Returns an error
  /// code, or null on success.
  static Future<String?> signIn(String email, String password) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty || password.isEmpty) return 'empty_signin';
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: trimmed,
        password: password,
      );
      final claimed = await _claimThisBrowser();
      if (claimed != null) {
        await Supabase.instance.client.auth.signOut();
        return claimed;
      }
      final shopId = shopIdOfCurrentUser();
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

  /// Binds this browser under the shop's device cap. Null = continue;
  /// `payment_required` means Support has not allowed another device yet.
  static Future<String?> _claimThisBrowser() async {
    try {
      final res = await invokeActivate({
        'action': 'refresh_account_license',
        'device_id': await _deviceId(),
      });
      final data = parseInvokeData(res.data);
      if (data == null) return null;
      if (data['ok'] == true) {
        try {
          await Supabase.instance.client.auth.refreshSession();
        } catch (_) {}
        return null;
      }
      final code = errorCodeFromInvokeData(data);
      if (code == 'payment_required') return 'payment_required';
      // Anything else — `rate_limited` (which this action really does
      // return), a null body, a 15s timeout — used to fall through to
      // `null`, i.e. "carry on". The device cap this function exists to
      // enforce therefore held only on the happy path: retrying past a rate
      // limit, or signing in while the function was degraded, bound nothing
      // and was billed for nothing. Surface the code instead so the caller
      // can tell the user rather than silently granting access.
      if (code != null && code.isNotEmpty) return code;
      return null;
    } catch (e) {
      if (classifyInvokeError(e) == 'payment_required') {
        return 'payment_required';
      }
      return null;
    }
  }

  /// Activates this browser with an Offline device key. Online shops should
  /// use [signIn] instead (no key).
  static Future<String?> activate(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return 'empty_key';
    final auth = Supabase.instance.client.auth;
    if (auth.currentSession == null) {
      await auth.signInAnonymously();
    }
    final deviceId = await _deviceId();
    final Map<String, dynamic>? data;
    try {
      final res = await invokeActivate(
        {'key': trimmed, 'device_id': deviceId},
      );
      data = parseInvokeData(res.data);
    } catch (e) {
      return classifyInvokeError(e) == 'network_error'
          ? 'network_error'
          : 'activation_failed';
    }
    if (data == null || data['ok'] != true) {
      return errorCodeFromInvokeData(data) ?? 'activation_failed';
    }
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
