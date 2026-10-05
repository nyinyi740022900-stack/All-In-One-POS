import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mm_pos/core/router.dart';
import 'package:mm_pos/features/account/auth_callback.dart';
import 'package:mm_pos/l10n/app_localizations.dart';
import 'package:mm_pos/features/onboarding/onboarding_state.dart';
import 'package:mm_pos/features/onboarding/operating_mode_providers.dart';

void main() {
  testWidgets(
    'expired native email callback shows recovery instead of router error',
    (tester) async {
      final router = GoRouter(
        initialLocation:
            'allinonepos://login-callback/#error=access_denied&error_code=otp_expired&error_description=private_description',
        routes: buildAppRoutes(),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('This confirmation link is no longer valid.'),
        findsOneWidget,
      );
      expect(find.textContaining('GoException'), findsNothing);
      expect(find.textContaining('private_description'), findsNothing);
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/auth-callback?status=invalid',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'valid callback strips bearer and does not claim email is changed',
    (tester) async {
      final router = GoRouter(
        initialLocation:
            'allinonepos://login-callback/#access_token=private_token&type=email_change',
        routes: buildAppRoutes(),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Check your account to finish.'), findsOneWidget);
      expect(find.textContaining('private_token'), findsNothing);
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/auth-callback',
      );
      expect(tester.takeException(), isNull);
    },
  );
  test('query errors and local callback variants retain only safe status', () {
    expect(
      authCallbackLocation(
        Uri.parse('/login-callback/?error=access_denied&code=secret'),
      ),
      '/auth-callback?status=invalid',
    );
    expect(
      authCallbackLocation(
        Uri.parse('allinonepos://login-callback?code=secret'),
      ),
      '/auth-callback',
    );
    expect(
      authCallbackLocation(
        Uri.parse('allinonepos://login-callback/#error_description=%ZZ'),
      ),
      '/auth-callback?status=invalid',
    );
    expect(
      authCallbackLocation(
        Uri.parse('https://other.example/login-callback?code=secret'),
      ),
      isNull,
    );
    expect(
      authCallbackLocation(
        Uri.parse('other://login-callback/#access_token=secret'),
      ),
      isNull,
    );
  });
  testWidgets(
    'root Home destination resolves to Sell rather than another error',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          buildAppRoutes().first,
          GoRoute(
            path: '/sell',
            builder: (_, _) => const Scaffold(body: Text('Sell destination')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('Sell destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('production guard admits only callback status before daily PIN', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        onboardingStillNeededProvider.overrideWithValue(false),
        dailyGateNeededProvider.overrideWith((ref) async => true),
      ],
    );
    addTearDown(container.dispose);
    await container.read(dailyGateNeededProvider.future);
    final router = container.read(appRouterProvider);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );
    router.go(
      'allinonepos://login-callback/#error_code=otp_expired&access_token=secret',
    );
    final callback = await router.routeInformationParser
        .parseRouteInformationWithDependencies(
          router.routeInformationProvider.value,
          context,
        );
    expect(callback.uri.toString(), '/auth-callback?status=invalid');
    router.go('/settings');
    final gated = await router.routeInformationParser
        .parseRouteInformationWithDependencies(
          router.routeInformationProvider.value,
          context,
        );
    expect(gated.uri.path, '/daily-entry');
    expect(gated.uri.queryParameters['next'], '/settings');
  });
}
