import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/license/invoke_error.dart';
import 'package:mm_pos/features/license/license_model.dart';
import 'package:mm_pos/features/license/license_status.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('parseInvokeData', () {
    test('accepts a JSON string, not only a decoded Map', () {
      final data = parseInvokeData('{"ok":false,"error":"bad_request"}');
      expect(data?['error'], 'bad_request');
    });

    test('copies a non-String-keyed map', () {
      final data = parseInvokeData(<dynamic, dynamic>{'ok': true});
      expect(data?['ok'], isTrue);
    });
  });

  group('classifyInvokeError', () {
    test('HTTP 400 is server-side, not "no internet"', () {
      expect(
        classifyInvokeError(
          const FunctionException(
            status: 400,
            details: {'ok': false, 'error': 'bad_request'},
          ),
        ),
        'bad_request',
      );
    });

    test('401 without a shop-scope code means the JWT was not sent', () {
      expect(
        classifyInvokeError(const FunctionException(status: 401)),
        'not_authenticated',
      );
      expect(
        classifyInvokeError(
          const FunctionException(
            status: 401,
            details: {'ok': false, 'error': 'not_authenticated'},
          ),
        ),
        'not_authenticated',
      );
    });

    test('socket failures stay network_error', () {
      expect(
        classifyInvokeError(Exception('SocketException: Failed host lookup')),
        'network_error',
      );
    });

    test('a random cast error is server_error, not network_error', () {
      expect(
        classifyInvokeError(TypeError()),
        'server_error',
      );
    });
  });

  group('isReplaceableLocalLicense', () {
    CachedLicense lic({required String shopId, required String key}) {
      final now = DateTime.now();
      return CachedLicense(
        key: key,
        shopId: shopId,
        plan: LicensePlan.free,
        expiresAt: now,
        activatedAt: now,
        lastVerifiedAt: now,
        deviceId: 'dev',
      );
    }

    test('null and onboarding Free shop are replaceable', () {
      expect(isReplaceableLocalLicense(null), isTrue);
      expect(
        isReplaceableLocalLicense(lic(shopId: 'free-abc123', key: 'FREE')),
        isTrue,
      );
    });

    test('a real shop that was downgraded to Free is not replaceable', () {
      expect(
        isReplaceableLocalLicense(
          lic(shopId: 'shop-paid-1', key: 'FREE'),
        ),
        isFalse,
      );
    });
  });
}
