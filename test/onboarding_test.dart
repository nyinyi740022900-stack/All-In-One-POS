import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/core/widgets/app_widgets.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
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
    'Continue Free on the License page advances to the next page, not '
    'just a toast',
    (tester) async {
      // Before this fix, "Continue Free" only called continueFree() and
      // showed a SnackBar, leaving the owner sitting on the same page with no
      // visible confirmation anything happened — indistinguishable from the
      // tap not registering at all. This asserts the page actually advances.
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

      // Welcome -> Shop profile -> License.
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Free plan or license key'), findsOneWidget);

      await tester.ensureVisible(find.text('Continue Free'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue Free'));
      await tester.pumpAndSettle();

      // Landed on the next page (Account) without a second tap on the
      // bottom "Next" button.
      expect(find.text('Free plan or license key'), findsNothing);
    },
  );
}
