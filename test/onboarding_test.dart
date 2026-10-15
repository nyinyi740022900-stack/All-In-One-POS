import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/theme/app_theme.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/core/widgets/app_widgets.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/local/database_session.dart';
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


/// Records which shop database the app asks to (re)open. With per-shop
/// SQLite files, the shop id IS the data: reopening a different id means the
/// app is now reading a different, empty file and the old shop's sales,
/// stock and unsynced rows are left behind in theirs.
class _RecordingSession extends ChangeNotifier implements DatabaseSession {
  _RecordingSession(this.shopDb, this.shopId);
  @override
  AppDatabase shopDb;
  @override
  AppDatabase get deviceDb => shopDb;
  @override
  String? shopId;
  final reopened = <String>[];
  @override
  Future<void> reopenForShop(String toShopId) async {
    reopened.add(toShopId);
    shopId = toShopId;
  }

  @override
  Future<void> reopenForShopPromotedFrom({
    required String fromShopId,
    required String toShopId,
  }) => reopenForShop(toShopId);
  @override
  Future<void> disposeSessions() async {}
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

  /// Seeds a device that already has a Free licence (shop `free-abc123`) —
  /// the state left behind by quitting the app after the plan page — then
  /// walks onboarding to that page and taps Next.
  Future<({AppDatabase db, _RecordingSession session, SettingsRepository settings})>
  reRunOnboardingOnFreeDevice(
    WidgetTester tester, {
    required bool seedOutbox,
  }) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = SettingsRepository(db);
    final session = _RecordingSession(db, 'free-abc123');
    await settings.setLicenseJson(jsonEncode({
      'key': 'FREE',
      'shop_id': 'free-abc123',
      'plan': 'free',
      'expires_at': DateTime(2026, 10, 15).toIso8601String(),
      'activated_at': DateTime(2026, 10, 15).toIso8601String(),
      'last_verified_at': DateTime(2026, 10, 15).toIso8601String(),
      'device_id': 'phone',
    }));
    if (seedOutbox) {
      // The payment accounts the first launch seeds; they only drain once a
      // cloud account exists, so on a Free device they never leave.
      for (final account in ['kbzpay', 'wavepay', 'ayapay', 'cbpay']) {
        await db.into(db.outbox).insert(
              OutboxCompanion.insert(
                entityTable: 'payment_accounts',
                rowId: account,
                op: 'upsert',
              ),
            );
      }
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          databaseSessionProvider.overrideWith((ref) => session),
        ],
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
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('You start on the Free plan'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    return (db: db, session: session, settings: settings);
  }

  testWidgets(
    're-run onboarding with un-drained outbox rows still advances',
    (tester) async {
      // Regression: quit the app after the plan page and onboarding starts
      // again next launch. `continueFree()` found the existing licence, saw
      // the seeded rows in the outbox, returned false, and the page dead-ended
      // on "Something went wrong. Please try again." until a reinstall.
      final r = await reRunOnboardingOnFreeDevice(tester, seedOutbox: true);
      expect(find.text('Something went wrong. Please try again.'), findsNothing);
      expect(find.text('Email account (optional)'), findsOneWidget);
      // The unsynced rows are still queued — nothing was dropped to get past.
      expect(await r.db.select(r.db.outbox).get(), hasLength(4));
      expect(r.session.reopened, everyElement('free-abc123'));
      expect(await r.settings.licenseJson(), contains('free-abc123'));
    },
  );

  testWidgets(
    're-run onboarding keeps the existing Free shop instead of switching to '
    'a new empty one',
    (tester) async {
      // With nothing in the outbox the guard let it through, and it was worse
      // than the dead end: `startFreePlan()` minted a NEW Free shop id and the
      // per-shop database was reopened for it, so the app silently came back
      // on an empty shop with the owner's sales and stock left in the old
      // file. No error was shown at all.
      final r = await reRunOnboardingOnFreeDevice(tester, seedOutbox: false);
      expect(find.text('Email account (optional)'), findsOneWidget);
      expect(
        r.session.reopened,
        everyElement('free-abc123'),
        reason: 'reopened ${r.session.reopened} — a new id strands the data',
      );
      expect(await r.settings.licenseJson(), contains('free-abc123'));
    },
  );
}
