import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
import '../license/premium_gate.dart';
import '../printing/printing_providers.dart' show shopCurrencyProvider;
import 'accounting_providers.dart';
import 'balance_sheet_screen.dart';
import 'cash_flow_screen.dart';
import 'tax_report_screen.dart';
import 'year_end_close_screen.dart';

/// Accounting hub — the statements a shop hands its accountant: Balance
/// Sheet, Cash Flow, Tax Summary, and the Year-end Close control. Reached as
/// a peer tab of Analytics (`AnalyticsAccountingHubScreen`) and from the P&L
/// screen's app bar; every child is premium-gated the same way P&L is.
class AccountingScreen extends ConsumerWidget {
  const AccountingScreen({super.key, this.embedded = false});

  /// When true, builds only the body — no [Scaffold]/[AppBar] — so
  /// `AnalyticsAccountingHubScreen` can host it under its own chrome as a
  /// sub-tab (same convention as `OrdersScreen`/`InvoicesScreen`'s
  /// `embedded`). Default (false) keeps the original standalone
  /// full-screen behaviour (still used by the P&L screen's push).
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    if (ref.watch(licenseControllerProvider).loading ||
        !ref.watch(isPremiumProvider)) {
      final gate = PremiumGate(
        featureName: l.accountingTitle,
        benefits: [l.pnlBenefit1, l.pnlBenefit2],
        child: const SizedBox.shrink(),
      );
      if (embedded) return gate;
      return Scaffold(
        appBar: AppBar(title: Text(l.accountingTitle)),
        body: gate,
      );
    }

    // A live figure per report — previously every tile showed the same
    // static description forever, so "how's my shop doing" needed opening
    // each one just to see a number. Each watch mirrors the exact default
    // range its own screen uses, so this hits the same provider cache
    // rather than computing anything twice. Falls back to the static
    // subtitle while the figure is still loading (first paint, cold cache).
    final currency = ref.watch(shopCurrencyProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = now.month == 12
        ? DateTime(now.year + 1, 1, 1)
        : DateTime(now.year, now.month + 1, 1);
    final yearStart = DateTime(now.year, 1, 1);
    final todayExclusiveEnd =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));

    final balanceSheet = ref.watch(balanceSheetProvider).valueOrNull;
    final netWorthSubtitle = balanceSheet == null
        ? l.accountingBalanceSheetSubtitle
        : l.accountingNetWorthFigure(
            Money(balanceSheet.assets - balanceSheet.liabilities)
                .withCurrency(currency, locale));

    final cashFlows = ref
        .watch(cashFlowProvider((start: monthStart, endExclusive: monthEnd)))
        .valueOrNull;
    final cashFlowSubtitle = cashFlows == null
        ? l.accountingCashFlowSubtitle
        : l.accountingCashFlowFigure(Money(cashFlows.fold<int>(
                0, (sum, f) => sum + f.inflow - f.outflow))
            .withCurrency(currency, locale));

    final taxStatement = ref
        .watch(taxStatementProvider(
            (start: yearStart, endExclusive: todayExclusiveEnd)))
        .valueOrNull;
    final taxSubtitle = taxStatement == null
        ? l.accountingTaxSummarySubtitle
        : l.accountingTaxFigure(
            Money(taxStatement.netProfit).withCurrency(currency, locale));

    final tiles = [
      (
        Icons.account_balance_outlined,
        l.accountingBalanceSheet,
        netWorthSubtitle,
        const BalanceSheetScreen(),
      ),
      (
        Icons.swap_vert_outlined,
        l.accountingCashFlow,
        cashFlowSubtitle,
        const CashFlowScreen(),
      ),
      (
        Icons.request_quote_outlined,
        l.accountingTaxSummary,
        taxSubtitle,
        const TaxReportScreen(),
      ),
      (
        Icons.lock_outline,
        l.accountingYearEndClose,
        l.accountingYearEndCloseSubtitle,
        const YearEndCloseScreen(),
      ),
    ];

    final body = ListView(
      padding: const EdgeInsets.all(AppTheme.space3),
      children: [
        for (final (icon, title, subtitle, screen) in tiles)
          Card(
            margin: const EdgeInsets.only(bottom: AppTheme.space2),
            child: ListTile(
              leading: Icon(icon),
              title: Text(title),
              subtitle: Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => screen),
              ),
            ),
          ),
      ],
    );

    if (embedded) return body;

    return Scaffold(
      appBar: AppBar(title: Text(l.accountingTitle)),
      body: body,
    );
  }
}
