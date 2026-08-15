import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/core/widgets/app_widgets.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/features/onboarding/onboarding_flow.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() {
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

  testWidgets(
      'fresh install shows a single linear onboarding flow — no mode '
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
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OnboardingFlow(onDone: () {}),
        ),
      ),
    );
    await tester.pump();

    // First page is Welcome (BrandHero lockup), not a mode-choice screen —
    // the permanent Online/Offline choice no longer exists.
    expect(find.byType(BrandHero), findsOneWidget);
    expect(find.text('Online'), findsNothing);
    expect(find.text('Offline'), findsNothing);

    // 5 pagination dots: Welcome, Shop profile, License, Account (optional),
    // Staff mode.
    expect(find.byType(AnimatedContainer), findsNWidgets(5));
  });
}
