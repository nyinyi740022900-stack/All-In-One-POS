import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/theme/app_theme.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/core/widgets/app_widgets.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/features/onboarding/full_screen_gate.dart';
import 'package:mm_pos/features/onboarding/onboarding_flow.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

/// `SettingsRepository.deviceId()` already has a try/catch around its
/// `flutter_secure_storage` read specifically for "not available (tests)" —
/// but a `MethodChannel` call with no mock handler registered doesn't throw
/// in a widget test, it just never resolves. That leaves the awaiting
/// `Future` permanently pending instead of hitting the catch block, which
/// silently stalls anything downstream (e.g. `continueFree()`) with no
/// exception and no timeout. Installing a handler that answers `null` (the
/// same "no secure value yet" signal a real absent key would give) lets the
/// code's own existing local-DB fallback run, exactly as intended.
void _mockSecureStorageChannel() {
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() {
    _mockSecureStorageChannel();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsRepository(db);
  });

  tearDown(() async => db.close());

  test('onboarding is not complete on a fresh install', () async {
    expect(await settings.onboardingComplete(), isFalse);
  });

  test('marking onboarding complete persists', () async {
    await settings.markOnboardingComplete();
    expect(await settings.onboardingComplete(), isTrue);
  });

  testWidgets('fresh install shows a single linear onboarding flow — no mode '
      'choice page, 5 pages total', (tester) async {
    // OnboardingFlow directly, not the full MmPosApp — MaterialApp.router's
    // builder still resolves the router's own page underneath even when the
    // builder returns something else instead of `child`, which would open
    // real Drift query streams (products/categories/orders/...) that never
    // get cancelled under the test's fake clock. Isolating the widget under
    // test avoids that unrelated class of pending-timer failures entirely.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OnboardingFlow(onDone: () {}),
        ),
      ),
    );
    await tester.pump();

    // First page is Welcome (brand-green wave header), not a mode-choice
    // screen — the permanent Online/Offline choice no longer exists.
    expect(find.byType(BrandHeroPanel), findsOneWidget);
    expect(find.text('Online'), findsNothing);
    expect(find.text('Offline'), findsNothing);

    // 5 pagination dots: Welcome, Shop profile, License, Account (optional),
    // Staff mode.
    expect(find.byType(AnimatedContainer), findsNWidgets(5));

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Your shop'), findsOneWidget);
    expect(find.text('Address'), findsOneWidget);
    expect(find.text('Receipt footer'), findsOneWidget);
  });

  testWidgets(
    'Next on the plan page starts Free and opens the email page',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
          theme: AppTheme.light(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: OnboardingFlow(onDone: () {}),
          ),
        ),
      );
      await tester.pump();

      // Welcome -> Shop profile -> Plan (explained, no Free vs key choice).
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('You start on the Free plan'), findsOneWidget);
      expect(find.text('Continue Free'), findsNothing);
      expect(find.text('Activate a license key'), findsNothing);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('You start on the Free plan'), findsNothing);
      expect(find.text('Email account (optional)'), findsOneWidget);
      // Footer Next is fully ABSENT here, not merely disabled — a greyed
      // "Next" read as broken (owners tapped it and nothing happened). The
      // page advances via its own Sign in / Skip for now actions.
      expect(find.widgetWithText(FilledButton, 'Next'), findsNothing);
    },
  );

  testWidgets(
    'Get started on Owner and Staff modes completes onboarding',
    (tester) async {
      var done = 0;
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
          theme: AppTheme.light(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: OnboardingFlow(onDone: () => done++),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Skip for now'));
      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();

      expect(find.text('Owner and Staff modes'), findsOneWidget);
      final getStarted = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Get started'),
      );
      expect(getStarted.onPressed, isNotNull);

      await tester.tap(find.text('Get started'));
      await tester.pump();
      expect(done, 1);
    },
  );

  testWidgets(
    'Get started still completes when shown from MaterialApp.builder over a router child',
    (tester) async {
      var done = 0;
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
          theme: AppTheme.light(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => FullScreenGate(
              underneath: child,
              page: OnboardingFlow(onDone: () => done++),
            ),
            home: const ColoredBox(color: Color(0xFF888888)),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Skip for now'));
      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();

      expect(find.text('Owner and Staff modes'), findsOneWidget);
      await tester.tap(find.text('Get started'));
      await tester.pump();
      expect(done, 1);
    },
  );
}
