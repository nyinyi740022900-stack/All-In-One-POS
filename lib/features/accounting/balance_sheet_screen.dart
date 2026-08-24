import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
import '../license/premium_gate.dart';
import 'accounting_csv.dart';
import 'accounting_providers.dart';

/// Balance Sheet — what the shop owns (cash & accounts, stock at cost,
/// receivables), what it owes (supplier payables), and the owner's stake
/// (paid-in capital + retained earnings), all live. The three-way
/// difference is shown honestly as "untracked" rather than forced into a
/// line — this ledger was not born from a double-entry GL, so manual
/// opening stock has no equity counterpart (see [BalanceSheet]).
class BalanceSheetScreen extends ConsumerStatefulWidget {
  const BalanceSheetScreen({super.key});

  @override
  ConsumerState<BalanceSheetScreen> createState() => _BalanceSheetScreenState();
}

class _BalanceSheetScreenState extends ConsumerState<BalanceSheetScreen> {
  bool _exporting = false;

  Future<void> _exportCsv() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sheet = ref.read(balanceSheetProvider).valueOrNull;
    if (sheet == null) return;
    setState(() => _exporting = true);
    try {
      final sym = l.currencySymbol;
      final csv = buildBalanceSheetCsv(
        [
          (l.balanceSheetAssets, sheet.assets),
          (l.balanceSheetCashAccounts, sheet.cashAndAccounts),
          (l.balanceSheetInventory, sheet.inventoryValue),
          (l.balanceSheetReceivables, sheet.receivables),
          (l.balanceSheetLiabilities, sheet.liabilities),
          (l.balanceSheetPayables, sheet.payables),
          (l.balanceSheetEquity, sheet.equityTotal),
          (l.equityPaidInCapital, sheet.paidInCapital),
          (l.equityRetainedEarnings, sheet.retainedEarnings),
          (l.balanceSheetUntracked, sheet.untracked),
        ],
        labelHeader: l.pnlLine,
        amountHeader: '${l.pnlAmount} ($sym)',
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/balance-sheet.csv');
      await file.writeAsString(csv);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: l.accountingBalanceSheet,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (ref.watch(licenseControllerProvider).loading ||
        !ref.watch(isPremiumProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l.accountingBalanceSheet)),
        body: PremiumGate(
          featureName: l.accountingBalanceSheet,
          benefits: [l.pnlBenefit1, l.pnlBenefit2],
          child: const SizedBox.shrink(),
        ),
      );
    }
    final sym = l.currencySymbol;
    final closedThrough = ref.watch(booksClosedThroughProvider).valueOrNull;
    final async = ref.watch(balanceSheetProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.accountingBalanceSheet),
        actions: [
          IconButton(
            tooltip: l.pnlExportCsv,
            icon: _exporting
                ? const ButtonSpinner()
                : const Icon(Icons.table_chart_outlined),
            onPressed: _exporting ? null : _exportCsv,
          ),
        ],
      ),
      body: async.when(
        loading: () => const AppLoadingView(),
        error: (_, _) => EmptyStateView(
          icon: Icons.error_outline,
          title: l.commonUnexpectedError,
          actionLabel: l.commonRetry,
          onAction: () => ref.invalidate(balanceSheetProvider),
        ),
        data: (sheet) {
          Widget row(String label, int amount, {bool bold = false}) =>
              SummaryRow(
                label,
                Money(amount).withSymbol(sym),
                emphasis: bold,
              );
          return ListView(
            padding: const EdgeInsets.all(AppTheme.space4),
            children: [
              if (closedThrough != null && closedThrough.isNotEmpty) ...[
                StatusPill(
                  label: l.yearEndClosedChip(closedThrough),
                  tone: StatusTone.neutral,
                ),
                const SizedBox(height: AppTheme.space3),
              ],
              Text(
                l.balanceSheetAssets,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppTheme.space2),
              row(l.balanceSheetCashAccounts, sheet.cashAndAccounts),
              row(l.balanceSheetInventory, sheet.inventoryValue),
              row(l.balanceSheetReceivables, sheet.receivables),
              const Divider(),
              row(l.balanceSheetAssets, sheet.assets, bold: true),
              const SizedBox(height: AppTheme.space4),
              Text(
                l.balanceSheetLiabilities,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppTheme.space2),
              row(l.balanceSheetPayables, sheet.payables),
              const Divider(),
              row(l.balanceSheetLiabilities, sheet.liabilities, bold: true),
              const SizedBox(height: AppTheme.space4),
              Text(
                l.balanceSheetEquity,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppTheme.space2),
              row(l.equityPaidInCapital, sheet.paidInCapital),
              row(l.equityRetainedEarnings, sheet.retainedEarnings),
              const Divider(),
              row(l.balanceSheetEquity, sheet.equityTotal, bold: true),
              const SizedBox(height: AppTheme.space4),
              row(l.balanceSheetAssets,
                  sheet.assets - sheet.liabilities, bold: true),
              const SizedBox(height: AppTheme.space4),
              // The honest line: what the three-way comparison can't
              // attribute — typically manual opening stock. Not an error,
              // not hidden inside retained earnings.
              row(
                l.balanceSheetUntracked,
                sheet.untracked,
                bold: true,
              ),
              if (sheet.untracked != 0) ...[
                const SizedBox(height: AppTheme.space2),
                Text(
                  l.balanceSheetUntrackedNote,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
