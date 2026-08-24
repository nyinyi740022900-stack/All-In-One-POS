import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
import '../license/premium_gate.dart';
import 'balance_sheet_screen.dart';
import 'cash_flow_screen.dart';
import 'tax_report_screen.dart';
import 'year_end_close_screen.dart';

/// Accounting hub — the statements a shop hands its accountant: Balance
/// Sheet, Cash Flow, Tax Summary, and the Year-end Close control. Reached
/// from the P&L screen's app bar (the statements' home); every child is
/// premium-gated the same way P&L is.
class AccountingScreen extends ConsumerWidget {
  const AccountingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    if (ref.watch(licenseControllerProvider).loading ||
        !ref.watch(isPremiumProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l.accountingTitle)),
        body: PremiumGate(
          featureName: l.accountingTitle,
          benefits: [l.pnlBenefit1, l.pnlBenefit2],
          child: const SizedBox.shrink(),
        ),
      );
    }

    final tiles = [
      (
        Icons.account_balance_outlined,
        l.accountingBalanceSheet,
        l.accountingBalanceSheetSubtitle,
        const BalanceSheetScreen(),
      ),
      (
        Icons.swap_vert_outlined,
        l.accountingCashFlow,
        l.accountingCashFlowSubtitle,
        const CashFlowScreen(),
      ),
      (
        Icons.request_quote_outlined,
        l.accountingTaxSummary,
        l.accountingTaxSummarySubtitle,
        const TaxReportScreen(),
      ),
      (
        Icons.lock_outline,
        l.accountingYearEndClose,
        l.accountingYearEndCloseSubtitle,
        const YearEndCloseScreen(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l.accountingTitle)),
      body: ListView(
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
      ),
    );
  }
}
