import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mm_pos/storefront/storefront_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async => call.method == 'getAll' ? <String, Object>{} : true,
        );
  });
  tearDown(() async => Supabase.instance.dispose());

  Future<void> server(int status, String body) async {
    await Supabase.initialize(
      url: 'https://checkout.test',
      publishableKey: 'test-anon',
      httpClient: MockClient(
        (_) async => http.Response(
          body,
          status,
          headers: {'content-type': 'application/json'},
        ),
      ),
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
  }

  for (final status in [502, 503]) {
    test('$status unavailable becomes the payment-specific error', () async {
      await server(status, '{"error":"checkout_unavailable"}');
      await expectLater(
        StorefrontApi().createCheckout(shopId: 'a', plan: 'monthly'),
        throwsA(isA<CheckoutUnavailable>()),
      );
    });
  }
  test(
    '403 authentication/ownership errors keep their original type',
    () async {
      await server(403, '{"error":"forbidden"}');
      await expectLater(
        StorefrontApi().createCheckout(shopId: 'a', plan: 'monthly'),
        throwsA(isA<FunctionException>()),
      );
    },
  );
  test(
    '409 existing subscription exposes only a trusted management URL',
    () async {
      await server(
        409,
        '{"error":"subscription_already_exists","management_url":"https://shop.lemonsqueezy.com/billing/manage"}',
      );
      await expectLater(
        StorefrontApi().createCheckout(shopId: 'a', plan: 'monthly'),
        throwsA(
          isA<CheckoutAlreadySubscribed>().having(
            (e) => e.managementUrl?.host,
            'trusted host',
            'shop.lemonsqueezy.com',
          ),
        ),
      );
    },
  );
  test('409 existing subscription does not expose an untrusted URL', () async {
    await server(
      409,
      '{"error":"subscription_already_exists","management_url":"https://evil.example/billing"}',
    );
    await expectLater(
      StorefrontApi().createCheckout(shopId: 'a', plan: 'monthly'),
      throwsA(
        isA<CheckoutAlreadySubscribed>().having(
          (e) => e.managementUrl,
          'unsafe URL omitted',
          null,
        ),
      ),
    );
  });
  test('409 pending checkout becomes an in-progress error', () async {
    await server(409, '{"error":"checkout_in_progress"}');
    await expectLater(
      StorefrontApi().createCheckout(shopId: 'a', plan: 'monthly'),
      throwsA(isA<CheckoutInProgress>()),
    );
  });
  test('successful checkout returns its HTTPS URL', () async {
    await server(200, '{"url":"https://pay.example.com/checkout"}');
    expect(
      await StorefrontApi().createCheckout(shopId: 'a', plan: 'monthly'),
      'https://pay.example.com/checkout',
    );
  });
}
