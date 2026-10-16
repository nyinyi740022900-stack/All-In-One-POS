import 'dart:async';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/core/theme/app_theme.dart';
import 'package:mm_pos/core/widgets/app_widgets.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/features/cash/cash_providers.dart';
import 'package:mm_pos/features/cash/cash_session_repository.dart';
import 'package:mm_pos/features/cash/cash_session_report_csv.dart';
import 'package:mm_pos/features/cash/cash_session_report_formatter.dart';
import 'package:mm_pos/features/invoices/receipt_data.dart';
import 'package:mm_pos/features/account/account_providers.dart';
import 'package:mm_pos/features/account/branch_providers.dart';
import 'package:mm_pos/features/license/license_repository.dart';
import 'package:mm_pos/features/license/license_providers.dart';
import 'package:mm_pos/features/onboarding/daily_gate.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';
import 'package:mm_pos/features/staff/staff_providers.dart';
import 'package:mm_pos/l10n/app_localizations.dart';
import 'package:mm_pos/features/account/account_repository.dart';

class SignedStaff extends AccountRepository {
  SignedStaff(super.license, super.settings, super.db);
  @override
  bool get isSignedInWithRealAccount => true;
  @override
  String? get currentAccountRole => 'staff';
  @override
  String? get currentAccountEmail => 'staff@example.invalid';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('equal-open-time sessions still allocate each payment once', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = CashSessionRepository(db, 'shop-a');
    final at = DateTime(2026, 10, 15, 9);
    for (final id in ['a', 'b']) {
      await db
          .into(db.cashSessions)
          .insert(
            CashSessionsCompanion.insert(
              id: id,
              shopId: 'shop-a',
              openedAt: at,
              openingAmount: 0,
            ),
          );
    }
    await db
        .into(db.payments)
        .insert(
          PaymentsCompanion.insert(
            id: 'p',
            shopId: 'shop-a',
            saleId: 's',
            method: 'cash',
            amount: 1000,
            createdAt: Value(at.add(const Duration(hours: 1))),
          ),
        );
    final sessions = await db.select(db.cashSessions).get();
    expect(
      await repo.expectedCash(sessions[0]) +
          await repo.expectedCash(sessions[1]),
      1000,
    );
    expect(
      await repo.physicalCashNow(),
      1000,
      reason: 'Balance Sheet must use the same equal-time winner',
    );
  });
  test(
    'a frozen closed snapshot reconciles against a later synced overlapping session',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = CashSessionRepository(db, 'shop-a');
      final at = DateTime(2026, 10, 15, 9);
      await db
          .into(db.cashSessions)
          .insert(
            CashSessionsCompanion.insert(
              id: 'a',
              shopId: 'shop-a',
              openedAt: at,
              openingAmount: 0,
              closedAt: Value(at.add(const Duration(hours: 3))),
              closingAmount: const Value(1000),
              expectedCashAtClose: const Value(1000),
            ),
          );
      await db
          .into(db.cashSessions)
          .insert(
            CashSessionsCompanion.insert(
              id: 'b',
              shopId: 'shop-a',
              openedAt: at.add(const Duration(hours: 1)),
              openingAmount: 0,
            ),
          );
      await db
          .into(db.payments)
          .insert(
            PaymentsCompanion.insert(
              id: 'p',
              shopId: 'shop-a',
              saleId: 's',
              method: 'cash',
              amount: 1000,
              createdAt: Value(at.add(const Duration(hours: 2))),
            ),
          );
      final sessions = await db.select(db.cashSessions).get();
      expect(
        await repo.expectedCash(sessions[0]) +
            await repo.expectedCash(sessions[1]),
        1000,
      );
      final report = await repo.reportFor(
        sessions.firstWhere((s) => s.id == 'a'),
      );
      expect(report.cashSalesTotal, 0);
      expect(report.expectedCash, 0);
      expect(report.recordedExpectedCash, 1000);
      expect(report.reconciliationAdjustment, -1000);
      expect(
        (await db.select(db.cashSessions).get()).first.expectedCashAtClose,
        1000,
      );
      // The remote device may have closed before syncing too. Neither
      // historical snapshot may be rewritten to hide the late conflict.
      await (db.update(db.cashSessions)..where((t) => t.id.equals('b'))).write(
        CashSessionsCompanion(
          closedAt: Value(at.add(const Duration(hours: 4))),
          closingAmount: const Value(1000),
          expectedCashAtClose: const Value(1000),
        ),
      );
      final closed = await db.select(db.cashSessions).get();
      expect(
        await repo.expectedCash(closed[0]) + await repo.expectedCash(closed[1]),
        1000,
      );
      expect(closed.map((s) => s.expectedCashAtClose), everyElement(1000));
    },
  );
  test(
    'lost staff auth keeps Staff role and account cashier attribution',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final settings = SettingsRepository(db);
      addTearDown(db.close);
      final role = StateProvider<String?>((ref) => 'staff');
      await settings.setStaffRole('shop-a', 'staff');
      await settings.setRoleAccountUserId('shop-a', 'staff-user');
      await settings.setActiveStaffId('shop-a', 'account:staff-user');
      final c = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          settingsRepositoryProvider.overrideWithValue(settings),
          shopIdProvider.overrideWith((ref) => 'shop-a'),
          backendAccountRoleProvider.overrideWith((ref) => ref.watch(role)),
          currentAccountEmailProvider.overrideWithValue(
            'staff@example.invalid',
          ),
          currentAccountUserIdProvider.overrideWith(
            (ref) => ref.watch(role) == null ? null : 'staff-user',
          ),
        ],
      );
      addTearDown(c.dispose);
      final id = await c
          .read(staffRepositoryProvider)
          .upsertMember(
            name: 'Staff',
            pin: '1234',
            email: 'staff@example.invalid',
          );
      await c.read(staffRoleProvider.future);
      await c.read(activeStaffIdProvider.future);
      await c.read(staffMembersProvider.future);
      expect(c.read(saleCashierIdProvider), id);
      c.read(role.notifier).state = null;
      expect(c.read(effectiveRoleProvider), 'staff');
      expect(c.read(saleCashierIdProvider), 'account:staff-user');
      expect(
        await c.read(staffControllerProvider).switchRole('owner', pin: ''),
        isFalse,
      );
      expect(await c.read(staffControllerProvider).switchRole('staff'), isTrue);
      expect(await settings.activeStaffId('shop-a'), 'account:staff-user');
    },
  );
  testWidgets('cash stream error offers retry instead of permanent loading', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final settings = SettingsRepository(db);
    addTearDown(db.close);
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          settingsRepositoryProvider.overrideWithValue(settings),
          shopIdProvider.overrideWith((ref) => 'shop-a'),
          accountRepositoryProvider.overrideWithValue(
            SignedStaff(LicenseRepository(settings), settings, db),
          ),
          backendAccountRoleProvider.overrideWithValue('staff'),
          currentAccountEmailProvider.overrideWithValue(
            'staff@example.invalid',
          ),
          staffRoleProvider.overrideWith((ref) => Stream.value('staff')),
          activeStaffIdProvider.overrideWith((ref) => Stream.value(null)),
          staffMembersProvider.overrideWith(
            (ref) => Stream.value(const <StaffMember>[]),
          ),
          branchSwitchRecoveryProvider.overrideWith(
            (ref) => Stream.value(null),
          ),
          branchesProvider.overrideWith((ref) async => const []),
          isPremiumProvider.overrideWithValue(true),
          currentCashSessionProvider.overrideWith(
            (ref) => Stream<CashSession?>.error(StateError('db_read_failed')),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DailyGate(onDone: () {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    final c = ProviderScope.containerOf(tester.element(find.byType(DailyGate)));
    expect(c.read(currentCashSessionProvider).hasError, isTrue);
    expect(find.byType(AppLoadingView), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  test('reconciliation exports keep original close and adjustment visible', () {
    const report = CashSessionReport(
      openingAmount: 0,
      cashSalesTotal: 0,
      cashRepaymentsTotal: 0,
      topUpsTotal: 0,
      expensesTotal: 0,
      supplierPaymentsTotal: 0,
      expectedCash: 0,
      closingAmount: 1000,
      variance: 1000,
      recordedExpectedCash: 1000,
    );
    final csv = buildCashSessionReportCsv(
      report,
      openingFloatLabel: 'Opening',
      cashSalesLabel: 'Sales',
      cashRepaymentsLabel: 'Repayments',
      topUpsLabel: 'Topups',
      expensesLabel: 'Expenses',
      supplierPaymentsLabel: 'Suppliers',
      expectedCashLabel: 'Expected',
      countedCashLabel: 'Counted',
      lineHeader: 'Line',
      amountHeader: 'Amount',
      recordedExpectedCashLabel: 'Recorded',
      reconciliationAdjustmentLabel: 'Adjustment',
    );
    expect(csv, contains('Recorded,1000'));
    expect(csv, contains('Adjustment,-1000'));
    final print = CashSessionReportFormatter(paper: PaperSize.mm80)
        .format(
          report,
          title: 'Report',
          openedLabel: 'Opened',
          closedLabel: 'Closed',
          openingFloatLabel: 'Opening',
          cashSalesLabel: 'Sales',
          cashRepaymentsLabel: 'Repayments',
          topUpsLabel: 'Topups',
          expensesLabel: 'Expenses',
          supplierPaymentsLabel: 'Suppliers',
          expectedCashLabel: 'Expected',
          countedCashLabel: 'Counted',
          openedAt: DateTime(2026, 10, 15),
          recordedExpectedCashLabel: 'Recorded',
          reconciliationAdjustmentLabel: 'Adjustment',
        )
        .join('\n');
    expect(print, contains('Recorded'));
    expect(print, contains('Adjustment'));
    expect(print, contains('-1,000'));
  });
  test(
    'offline account actor and staff floor do not bleed between shops',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = SettingsRepository(db);
      await settings.setStaffRole('shop-a', 'staff');
      await settings.setActiveStaffId('shop-a', 'account:staff-user');
      for (final shop in ['shop-a', 'shop-b']) {
        final c = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            settingsRepositoryProvider.overrideWithValue(settings),
            shopIdProvider.overrideWith((ref) => shop),
            backendAccountRoleProvider.overrideWithValue(null),
          ],
        );
        await c.read(staffRoleProvider.future);
        await c.read(activeStaffIdProvider.future);
        expect(
          c.read(saleCashierIdProvider),
          shop == 'shop-a' ? 'account:staff-user' : null,
        );
        expect(
          await c.read(staffControllerProvider).switchRole('owner', pin: ''),
          shop == 'shop-b',
        );
        c.dispose();
      }
    },
  );
}
