import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../features/license/invoke_error.dart';
import '../features/license/entitlement.dart';
import '../features/license/license_status.dart';

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
  static String? _verifiedShopId;
  static String? _verifiedUserId;
  static DateTime? _verifiedUntil;
  static DateTime? _clockFloor;
  static int _generation = 0;
  static final _elapsedClock = Stopwatch()..start();
  static Future<void> _claimQueue = Future<void>.value();
  static String? get shopId {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null ||
        user.id != _verifiedUserId ||
        _verifiedUntil == null ||
        _localNow().isAfter(_verifiedUntil!)) {
      return null;
    }
    return _verifiedShopId;
  }

  static DateTime _localNow() {
    final now = DateTime.now();
    final elapsedNow = _clockFloor?.add(_elapsedClock.elapsed);
    _clockFloor = elapsedNow != null && elapsedNow.isAfter(now)
        ? elapsedNow
        : now;
    _elapsedClock.reset();
    return _clockFloor!;
  }

  static void _clearProof() {
    _generation++;
    _verifiedShopId = null;
    _verifiedUserId = null;
    _verifiedUntil = null;
    _clockFloor = null;
    _elapsedClock.reset();
  }

  static Future<String?> resume() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || (user.email ?? '').isEmpty) {
      _clearProof();
      return 'account_required';
    }
    return _claimThisBrowser();
  }

  static String? shopIdOfCurrentUser() =>
      Supabase.instance.client.auth.currentUser?.appMetadata['shop_id']
          as String?;

  /// Sign in with the shop's existing email/password, then bind this
  /// browser as a device (Check for renewal equivalent). Returns an error
  /// code, or null on success.
  static Future<String?> signIn(String email, String password) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty || password.isEmpty) return 'empty_signin';
    _clearProof();
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: trimmed,
        password: password,
      );
      final claimed = await _claimThisBrowser(reclaimDevice: true);
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
  static Future<String?> _claimThisBrowser({bool reclaimDevice = false}) {
    final request = _claimQueue.then(
      (_) => _claimBrowserBody(reclaimDevice: reclaimDevice),
    );
    _claimQueue = request.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return request;
  }

  static Future<String?> _claimBrowserBody({bool reclaimDevice = false}) async {
    final auth = Supabase.instance.client.auth;
    final userId = auth.currentUser?.id;
    final generation = _generation;
    try {
      final deviceId = await _deviceId();
      final res = await invokeActivate({
        'action': 'refresh_account_license',
        'device_id': deviceId,
        if (reclaimDevice) 'reclaim_device': true,
      });
      final data = parseInvokeData(res.data);
      if (data == null || data['ok'] != true) {
        final error = errorCodeFromInvokeData(data) ?? 'server_error';
        if (const [
          'device_released',
          'shop_archived',
          'membership_revoked',
        ].contains(error)) {
          _clearProof();
        }
        return error;
      }
      final expectedShop = data['shop_id'] as String?;
      if (expectedShop == null ||
          expectedShop.isEmpty ||
          data['plan'] == 'free') {
        _clearProof();
        return 'premium_required';
      }
      final receipt = await Entitlement.verify(data['entitlement'] as String?);
      if (receipt == null ||
          receipt.shopId != expectedShop ||
          receipt.userId != userId ||
          receipt.deviceId != deviceId) {
        _clearProof();
        return 'verification_required';
      }
      final scope = 'entitlement.${receipt.shopId}.$deviceId';
      final highest =
          int.tryParse(await _storage.read(key: '$scope.revision') ?? '') ?? 0;
      if (receipt.revision < highest) return 'verification_required';
      final lastSeen = int.tryParse(
        await _storage.read(key: '$scope.last_seen') ?? '',
      );
      final lastIat = int.tryParse(
        await _storage.read(key: '$scope.last_iat') ?? '',
      );
      final time = resolveTrustedTime(
        deviceNow: DateTime.now(),
        lastSeen: lastSeen == null
            ? _clockFloor
            : DateTime.fromMillisecondsSinceEpoch(lastSeen, isUtc: true),
        lastReceiptIssuedAt: lastIat == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lastIat, isUtc: true),
        entitlement: receipt,
      );
      await auth.refreshSession().timeout(const Duration(seconds: 8));
      if (generation != _generation ||
          auth.currentUser?.id != userId ||
          shopIdOfCurrentUser() != expectedShop) {
        _clearProof();
        return 'claim_mismatch';
      }
      final status = computeLicenseStatus(
        expiresAt: receipt.expiresAt,
        plan: receipt.plan,
        now: time.now,
      );
      if (status.kind != LicenseStatusKind.active &&
          status.kind != LicenseStatusKind.grace) {
        _clearProof();
        return 'premium_required';
      }
      if (generation != _generation) return 'stale_response';
      await _storage.write(
        key: '$scope.revision',
        value: receipt.revision.toString(),
      );
      await _storage.write(
        key: '$scope.last_seen',
        value: time.lastSeen.millisecondsSinceEpoch.toString(),
      );
      await _storage.write(
        key: '$scope.last_iat',
        value: receipt.issuedAt.millisecondsSinceEpoch.toString(),
      );
      if (generation != _generation) return 'stale_response';
      _clockFloor = time.now;
      _elapsedClock.reset();
      _verifiedShopId = expectedShop;
      _verifiedUserId = userId;
      _verifiedUntil = receipt.expiresAt.add(
        const Duration(days: kLicenseGraceDays),
      );
      return null;
    } catch (e) {
      return classifyInvokeError(e);
    }
  }

  /// Activates this browser with an Offline device key. Online shops should
  /// use [signIn] instead (no key).
  static Future<String?> activate(String key) async => 'retired_path';

  static Future<void> signOut() async {
    final selectedShop = _verifiedShopId;
    _clearProof();
    try {
      await invokeActivate({
        'action': 'release_device',
        'shop_id': selectedShop,
        'device_id': await _deviceId(),
      });
    } catch (_) {}
    await Supabase.instance.client.auth.signOut();
  }
}
