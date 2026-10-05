import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mm_pos/core/env.dart';
import 'package:mm_pos/core/theme/app_theme.dart';
import 'package:mm_pos/l10n/app_localizations.dart';
import 'package:mm_pos/storefront/renew_request_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mm_pos/storefront/renewal_auth.dart';

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

  Future<List<String>> server(
    Map<String, dynamic> preparation, {
    bool signedIn = true,
    String role = 'owner',
  }) async {
    final calls = <String>[];
    await Supabase.initialize(
      url: 'https://renewal.test',
      publishableKey: 'test-anon',
      httpClient: MockClient((r) async {
        calls.add(r.url.path);
        if (r.url.path.endsWith('/activate')) {
          expect(jsonDecode(r.body), {'action': 'prepare_social_account'});
          return http.Response(
            jsonEncode(preparation),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (r.url.path.startsWith('/rest/')) {
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (r.url.path.endsWith('/storefront')) {
          final body = jsonDecode(r.body);
          return http.Response(
            jsonEncode(
              body['action'] == 'list_billing_shops'
                  ? {
                      'shops': [
                        {'shop_id': 'shop-a', 'name': 'Original shop'},
                      ],
                      'card_payment': false,
                    }
                  : {'requests': []},
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'access_token': 'test-token',
            'refresh_token': 'test-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'owner-a',
              'email': 'owner@example.com',
              'app_metadata': {'role': calls.length > 1 ? role : null},
              'user_metadata': {},
              'aud': 'authenticated',
              'created_at': '2026-10-05T00:00:00Z',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
    if (signedIn) {
      await Supabase.instance.client.auth.signInWithPassword(
        email: 'owner@example.com',
        password: 'test',
      );
    }
    calls.clear();
    return calls;
  }

  test(
    'Google return strips OAuth parameters and stays on this origin',
    () async {
      await server({'ok': true});
      expect(
        RenewalAuth.redirectUri(
          Uri.parse(
            'https://shop.allinonepos.app/renew?code=secret&next=https://evil.test/#token',
          ),
        ),
        Uri.parse('https://shop.allinonepos.app/renew'),
      );
    },
  );
  test('existing account resolves membership before refreshing JWT', () async {
    final calls = await server({'ok': true, 'needs_shop_name': false});
    expect(await RenewalAuth().prepareAccount(), true);
    expect(calls, ['/functions/v1/activate', '/auth/v1/token']);
  });
  test('new Google account does not create a shop or claim a device', () async {
    final calls = await server({'ok': true, 'needs_shop_name': true});
    expect(await RenewalAuth().prepareAccount(), false);
    expect(calls, ['/functions/v1/activate']);
  });
  test('revoked membership cannot proceed as an owner', () async {
    final calls = await server({'ok': false, 'error': 'membership_revoked'});
    await expectLater(
      RenewalAuth().prepareAccount(),
      throwsA(isA<StateError>()),
    );
    expect(calls, ['/functions/v1/activate']);
  });
  test('staff membership never opens owner billing', () async {
    final calls = await server({
      'ok': true,
      'needs_shop_name': false,
    }, role: 'staff');
    expect(await RenewalAuth().prepareAccount(), false);
    expect(calls, ['/functions/v1/activate', '/auth/v1/token']);
  });
  Future<void> page(WidgetTester tester) async {
    await tester.runAsync(
      () => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(localeCode: 'en'),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RenewRequestPage(
            locale: const Locale('en'),
            onToggleLocale: () {},
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Google button follows provider configuration', (tester) async {
    await tester.runAsync(() => server({'ok': true}, signedIn: false));
    await page(tester);
    expect(
      find.text('Continue with Google'),
      Env.googleAuthEnabled ? findsOneWidget : findsNothing,
    );
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('a session arriving after page load resolves its original shop', (
    tester,
  ) async {
    final calls = (await tester.runAsync(
      () => server({'ok': true, 'needs_shop_name': false}, signedIn: false),
    ))!;
    await page(tester);
    await tester.runAsync(
      () => Supabase.instance.client.auth.signInWithPassword(
        email: 'owner@example.com',
        password: 'test',
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(calls.where((p) => p.endsWith('/activate')).length, 1);
    expect(find.textContaining('owner@example.com'), findsOneWidget);
    expect(find.text('Original shop'), findsOneWidget);
    await tester.runAsync(() => Supabase.instance.client.auth.signOut());
    await tester.pumpAndSettle();
    expect(find.text('Original shop'), findsNothing);
    expect(find.textContaining('owner@example.com'), findsNothing);
  });

  testWidgets(
    'Google account without membership shows setup guidance without billing',
    (tester) async {
      final calls = (await tester.runAsync(
        () => server({'ok': true, 'needs_shop_name': true}),
      ))!;
      await page(tester);
      expect(
        find.text('No owner shops available. Create a shop in the app first.'),
        findsOneWidget,
      );
      expect(calls.any((p) => p.endsWith('/storefront')), false);
    },
  );
}
