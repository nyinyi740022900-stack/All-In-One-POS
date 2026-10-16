import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/core/router.dart';
import 'package:mm_pos/core/theme/app_theme.dart';
import 'package:mm_pos/features/onboarding/daily_gate.dart';
import 'package:mm_pos/features/account/account_repository.dart';
import 'package:mm_pos/features/account/account_providers.dart';
import 'package:mm_pos/features/account/branch_providers.dart';
import 'package:mm_pos/features/cash/cash_providers.dart';
import 'package:mm_pos/features/cash/cash_session_repository.dart';
import 'package:mm_pos/features/license/license_providers.dart';
import 'package:mm_pos/features/license/license_repository.dart';
import 'package:mm_pos/features/staff/staff_providers.dart';
import 'package:mm_pos/l10n/app_localizations.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/features/onboarding/onboarding_state.dart';
import 'package:mm_pos/features/onboarding/operating_mode_providers.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';

class _Account extends AccountRepository {
  _Account(SettingsRepository settings, AppDatabase db)
    : super(LicenseRepository(settings), settings, db);
  @override
  bool get isSignedInWithRealAccount => true;
  @override
  String? get currentAccountEmail => 'staff@example.com';
}

class _FailingSettings extends SettingsRepository {
  _FailingSettings(super.db);
  @override
  Future<void> markDailyGateComplete(
    String shopId, {
    required String ymd,
    required bool skippedOpen,
  }) async {
    throw StateError('local write failed');
  }
}

void main() {
  for (final fail in [false, true]) {
    testWidgets(
      fail
          ? 'Continue shows a retryable error when its local write fails'
          : 'Staff Continue persists entry only for the active shop',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const channel = MethodChannel(
          'plugins.it_nomads.com/flutter_secure_storage',
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final settings = fail ? _FailingSettings(db) : SettingsRepository(db);
        var done = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(db),
              settingsRepositoryProvider.overrideWithValue(settings),
              shopIdProvider.overrideWith((ref) => 'shop-1'),
              accountRepositoryProvider.overrideWithValue(
                _Account(settings, db),
              ),
              staffMembersProvider.overrideWith((ref) => Stream.value([])),
              staffRoleProvider.overrideWith((ref) => Stream.value('staff')),
              effectiveRoleProvider.overrideWithValue('staff'),
              activeStaffNameProvider.overrideWithValue(null),
              branchesProvider.overrideWith((ref) async => []),
              isPremiumProvider.overrideWithValue(false),
              currentCashSessionProvider.overrideWith(
                (ref) => Stream.value(null),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: DailyGate(onDone: () => done++),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Staff'), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.text('Continue'));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
        if (fail) {
          expect(done, 0);
          expect(
            find.text('Something went wrong. Please try again.'),
            findsOneWidget,
          );
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Continue'),
                )
                .onPressed,
            isNotNull,
          );
        } else {
          expect(done, 1);
          await tester.runAsync(() async {
            expect(await settings.dailyGateYmd('shop-1'), localCalendarYmd());
            expect(await settings.dailyGateYmd('shop-2'), isNull);
          });
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  for (final destination in [
    '/sell',
    '/orders',
    '/inventory',
    '/invoices?search=customer',
    '/analytics',
    '/accounting',
  ]) {
    testWidgets('daily entry owns navigation before opening $destination', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final settings = SettingsRepository(db);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          settingsRepositoryProvider.overrideWithValue(settings),
          shopIdProvider.overrideWith((ref) => 'shop-1'),
          onboardingCompleteProvider.overrideWith((ref) async => true),
          staffRoleProvider.overrideWith((ref) => Stream.value('staff')),
          backendAccountRoleProvider.overrideWithValue('staff'),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(db.close);
      await container.read(onboardingCompleteProvider.future);
      await container.read(staffRoleProvider.future);
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
      router.go(destination);
      final gated = await router.routeInformationParser
          .parseRouteInformationWithDependencies(
            router.routeInformationProvider.value,
            context,
          );
      expect(gated.uri.path, '/daily-entry');
      expect(gated.uri.queryParameters['next'], destination);
      await tester.runAsync(() async {
        await settings.markDailyGateComplete(
          'shop-1',
          ymd: localCalendarYmd(),
          skippedOpen: true,
        );
        container.invalidate(dailyGateNeededProvider);
        expect(await container.read(dailyGateNeededProvider.future), isFalse);
      });
      router.go(gated.uri.toString());
      final completed = await router.routeInformationParser
          .parseRouteInformationWithDependencies(
            router.routeInformationProvider.value,
            context,
          );
      expect(completed.uri.toString(),
        destination == '/analytics' || destination == '/accounting' ? '/sell' : destination);
      for (final invalid in ['https://example.com', '//example.com', '/daily-entry', '/missing']) {
        router.go(Uri(path: '/daily-entry', queryParameters: {'next': invalid}).toString());
        final safe = await router.routeInformationParser.parseRouteInformationWithDependencies(
          router.routeInformationProvider.value, context);
        expect(safe.uri.path, '/sell');
      }
    });
  }

  for (final failure in ['session_already_open', 'disk_full']) {
    testWidgets(
      'Open register waits for the till to resolve and recovers from '
      '"$failure"',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const channel = MethodChannel(
          'plugins.it_nomads.com/flutter_secure_storage',
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final settings = SettingsRepository(db);
        final session = StreamController<CashSession?>();
        addTearDown(session.close);
        final repo = _FailingCash(db, failure);
        var done = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(db),
              settingsRepositoryProvider.overrideWithValue(settings),
              shopIdProvider.overrideWith((ref) => 'shop-1'),
              accountRepositoryProvider.overrideWithValue(
                _Account(settings, db),
              ),
              staffMembersProvider.overrideWith((ref) => Stream.value([])),
              staffRoleProvider.overrideWith((ref) => Stream.value('staff')),
              effectiveRoleProvider.overrideWithValue('staff'),
              activeStaffNameProvider.overrideWithValue(null),
              branchesProvider.overrideWith((ref) async => []),
              isPremiumProvider.overrideWithValue(true),
              cashSessionRepositoryProvider.overrideWithValue(repo),
              currentCashSessionProvider.overrideWith((ref) => session.stream),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: DailyGate(onDone: () => done++),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        // Still resolving: Open register must not be offered yet.
        expect(find.text('Open register'), findsNothing);

        session.add(null);
        await tester.pumpAndSettle();
        final open = find.widgetWithText(FilledButton, 'Open register');
        expect(tester.widget<FilledButton>(open).onPressed, isNotNull);

        // The open path reads the device id and the daily marker from the
        // real (in-memory) database, which only progresses in real async.
        await tester.runAsync(() async {
          await tester.tap(open);
          for (var i = 0; i < 40; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
            await tester.pump();
            if (failure == 'session_already_open' ? done == 1 : repo.attempts == 1) {
              await Future<void>.delayed(const Duration(milliseconds: 50));
              break;
            }
          }
        });
        await tester.pumpAndSettle();
        expect(repo.attempts, 1);
        if (failure == 'session_already_open') {
          // Another device / a double tap opened it: continue that till.
          expect(done, 1);
        } else {
          expect(done, 0);
          expect(
            find.text('Something went wrong. Please try again.'),
            findsOneWidget,
          );
          expect(
            tester.widget<FilledButton>(open).onPressed,
            isNotNull,
            reason: 'a failed open must leave a retryable button, not a '
                'permanently busy one',
          );
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}

class _FailingCash extends CashSessionRepository {
  _FailingCash(AppDatabase db, this.failure) : super(db, 'shop-1');
  final String failure;
  int attempts = 0;
  @override
  Future<String> openSession({
    required int openingAmount,
    String? note,
    String? deviceId,
  }) async {
    attempts++;
    throw StateError(failure);
  }
}
