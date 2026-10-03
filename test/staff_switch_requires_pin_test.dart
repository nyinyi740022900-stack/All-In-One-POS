import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';
import 'package:mm_pos/features/staff/staff_providers.dart';
import 'package:mm_pos/features/staff/staff_ui.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

/// Regression: an owner with no owner PIN used to be able to tap "Switch to
/// Staff" and get locked in Staff mode — leaving it needs the owner PIN, and a
/// staff user is not allowed to create one. Entering Staff mode must first make
/// the owner set a PIN.
void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  bool? result;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsRepository(db);
    result = null;
  });

  tearDown(() => db.close());

  Future<void> pumpHarness(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          databaseProvider.overrideWithValue(db),
          shopIdProvider.overrideWith((ref) => 'shop-1'),
          // Plain value, not the Drift-backed stream: disposing a Drift
          // stream provider leaves a pending zero-duration timer that the
          // test binding rejects at teardown. The roster is irrelevant here.
          staffMembersProvider.overrideWith(
            (ref) => Stream.value(const <StaffMember>[]),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await switchStaffRole(context, ref, 'staff');
                  },
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Dialog transitions take ~300ms. `pumpAndSettle` is avoided on purpose:
  // the Drift streams behind the staff providers keep scheduling frames, so it
  // never reports settled and the test hangs instead of failing.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> start(WidgetTester tester) async {
    await tester.tap(find.text('go'));
    await settle(tester);
  }

  final guardBody = find.textContaining('switch back to Owner mode');

  testWidgets('no PIN yet: explains, and cancelling leaves the device as '
      'Owner', (tester) async {
    await pumpHarness(tester);
    await start(tester);

    expect(guardBody, findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(result, isFalse);
    expect(await settings.staffRole('shop-1'), 'owner');
  });

  testWidgets('no PIN yet: abandoning the PIN entry also stays Owner',
      (tester) async {
    await pumpHarness(tester);
    await start(tester);

    await tester.tap(find.text('OK')); // acknowledge the explanation
    await settle(tester);
    await tester.tap(find.text('Cancel')); // cancel the PIN prompt
    await settle(tester);

    expect(result, isFalse);
    expect(await settings.staffRole('shop-1'), 'owner');
  });

  testWidgets('no PIN yet: mismatched confirmation stays Owner',
      (tester) async {
    await pumpHarness(tester);
    await start(tester);

    await tester.tap(find.text('OK'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('OK'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '9999');
    await tester.tap(find.text('OK'));
    await settle(tester);

    expect(result, isFalse);
    expect(await settings.staffRole('shop-1'), 'owner');
  });

  testWidgets('no PIN yet: setting one switches to Staff and the way back '
      'works', (tester) async {
    await pumpHarness(tester);
    await start(tester);

    await tester.tap(find.text('OK'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('OK'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('OK'));
    await settle(tester);

    expect(result, isTrue);

    // The point of the guard: Owner is now reachable again. Driven through
    // `runAsync` because the widget-test zone fakes async, and these touch the
    // real database.
    final container = ProviderScope.containerOf(
      tester.element(find.text('go')),
    );
    await tester.runAsync(() async {
      final ctrl = container.read(staffControllerProvider);
      expect(await settings.staffRole('shop-1'), 'staff');
      expect(await ctrl.hasPin(), isTrue);
      expect(await ctrl.switchRole('owner', pin: '1234'), isTrue);
      expect(await settings.staffRole('shop-1'), 'owner');
    });
  });

  testWidgets('PIN already set: switches straight to Staff with no extra '
      'dialog', (tester) async {
    await pumpHarness(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.text('go')),
    );
    await tester.runAsync(
      () => container.read(staffControllerProvider).setPin('1234'),
    );

    await start(tester);

    expect(guardBody, findsNothing);
    expect(result, isTrue);
    await tester.runAsync(
      () async => expect(await settings.staffRole('shop-1'), 'staff'),
    );
  });
}
