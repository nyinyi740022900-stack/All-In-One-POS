import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/currency_def.dart';
import 'package:mm_pos/core/theme/app_theme.dart';
import 'package:mm_pos/features/accounting/accounting_providers.dart';
import 'package:mm_pos/features/accounting/accounting_screen.dart';
import 'package:mm_pos/features/accounting/balance_sheet.dart';
import 'package:mm_pos/features/accounting/cash_flow_calculator.dart';
import 'package:mm_pos/features/accounting/tax_report_screen.dart';
import 'package:mm_pos/features/analytics/pnl_data.dart';
import 'package:mm_pos/features/license/license_model.dart';
import 'package:mm_pos/features/license/license_providers.dart';
import 'package:mm_pos/features/license/license_status.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

class _PremiumLicense extends LicenseController {
  _PremiumLicense(super.ref) {
    state = LicenseState(
      loading: false,
      license: CachedLicense(
        key: 'test-premium',
        shopId: 'test-shop',
        plan: LicensePlan.yearly,
        expiresAt: DateTime(2100),
        activatedAt: DateTime(2026),
        lastVerifiedAt: DateTime(2026),
        deviceId: 'test-device',
      ),
      status: const LicenseStatus(kind: LicenseStatusKind.active),
    );
  }
}

final _profit = StateProvider<int>((ref) => -84810);

Color? _renderedColor(WidgetTester tester, Finder text) {
  final richText = tester.widget<RichText>(
    find.descendant(of: text, matching: find.byType(RichText)),
  );
  return richText.text.style?.color;
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required String locale,
  required bool dark,
  Future<PnlStatement>? pending,
}) async {
  final now = DateTime.now();
  final start = DateTime(now.year, 1, 1);
  final end = DateTime(now.year, now.month, now.day + 1);
  final monthStart = DateTime(now.year, now.month, 1);
  final monthEnd = DateTime(now.year, now.month + 1, 1);
  final container = ProviderContainer(
    overrides: [
      licenseControllerProvider.overrideWith((ref) => _PremiumLicense(ref)),
      shopCurrencyProvider.overrideWithValue(CurrencyDef.mmk),
      balanceSheetProvider.overrideWith(
        (ref) async => const BalanceSheet(
          cashAndAccounts: 0,
          inventoryValue: 0,
          receivables: 0,
          payables: 84810,
          paidInCapital: 0,
          retainedEarnings: -84810,
        ),
      ),
      cashFlowProvider.overrideWith((ref, period) async {
        expect(period, (start: monthStart, endExclusive: monthEnd));
        return const [
          AccountCashFlow(
            accountId: 'cash',
            name: 'Cash',
            opening: 0,
            inflow: 0,
            outflow: 84810,
          ),
        ];
      }),
      taxStatementProvider.overrideWith((ref, period) {
        expect(period, (start: start, endExclusive: end));
        final profit = ref.watch(_profit);
        return pending ??
            Future.value(
              PnlStatement(
                start: start,
                end: end,
                revenue: profit > 0 ? profit : 0,
                cogs: 0,
                grossProfit: profit > 0 ? profit : 0,
                expensesByCategory: profit < 0 ? {'other': -profit} : {},
                totalExpenses: profit < 0 ? -profit : 0,
                netProfit: profit,
              ),
            );
      }),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: dark
            ? AppTheme.dark(localeCode: locale)
            : AppTheme.light(localeCode: locale),
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AccountingScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  for (final locale in ['en', 'my']) {
    for (final dark in [false, true]) {
      final variant = '$locale ${dark ? 'dark' : 'light'}';
      testWidgets(
        'negative YTD profit is danger and clears on updates $variant',
        (tester) async {
          final container = await _pump(tester, locale: locale, dark: dark);
          final context = tester.element(find.byType(AccountingScreen));
          final l = AppLocalizations.of(context);
          final neutral = Theme.of(
            context,
          ).listTileTheme.subtitleTextStyle!.color;
          final danger = AppColors.of(context).danger;
          final currency = locale == 'my' ? 'ကျပ်' : 'Ks';

          void expectUnrelatedNeutral() {
            for (final text in [
              l.accountingNetWorthFigure('-84,810 $currency'),
              l.accountingCashFlowFigure('-84,810 $currency'),
              l.accountingYearEndCloseSubtitle,
            ]) {
              expect(_renderedColor(tester, find.text(text)), neutral);
            }
          }

          final negative = find.text(
            l.accountingTaxFigure('-84,810 $currency'),
          );
          expect(negative, findsOneWidget);
          expect(_renderedColor(tester, negative), danger);
          expectUnrelatedNeutral();

        for (final (value, money) in [(0, '0'), (84810, '84,810')]) {
          container.read(_profit.notifier).state = -84810;
          await tester.pumpAndSettle();
          expect(_renderedColor(tester, negative), danger);
          container.read(_profit.notifier).state = value;
            await tester.pumpAndSettle();
            final updated = find.text(
              l.accountingTaxFigure('$money $currency'),
            );
            expect(updated, findsOneWidget);
            expect(_renderedColor(tester, updated), neutral);
            expect(negative, findsNothing);
            expectUnrelatedNeutral();
          }
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('loading tax description stays neutral $variant', (
        tester,
      ) async {
        await _pump(
          tester,
          locale: locale,
          dark: dark,
          pending: Completer<PnlStatement>().future,
        );
        final context = tester.element(find.byType(AccountingScreen));
        final l = AppLocalizations.of(context);
        expect(
          _renderedColor(tester, find.text(l.accountingTaxSummarySubtitle)),
          Theme.of(context).listTileTheme.subtitleTextStyle!.color,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
