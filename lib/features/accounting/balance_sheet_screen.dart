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
import '../printing/printing_providers.dart';
import 'accounting_csv.dart';
import 'accounting_pdf.dart';
import 'accounting_providers.dart';
import 'balance_sheet.dart';

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
  bool _exportingPdf = false;

  List<(String, int)> _rows(BalanceSheet sheet) {
    final l = AppLocalizations.of(context);
    return [
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
    ];
  }

  Future<void> _exportCsv() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sheet = ref.read(balanceSheetProvider).valueOrNull;
    if (sheet == null) return;
    setState(() => _exporting = true);
    try {
      final currency = ref.read(shopCurrencyProvider);
      final locale = Localizations.localeOf(context).languageCode;
      final csv = buildBalanceSheetCsv(
        _rows(sheet),
        labelHeader: l.pnlLine,
        amountHeader: '${l.pnlAmount} (${currency.label(locale)})',
        exponent: currency.exponent,
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

  Future<void> _exportPdf() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sheet = ref.read(balanceSheetProvider).valueOrNull;
    if (sheet == null) return;
    setState(() => _exportingPdf = true);
    try {
      final currency = ref.read(shopCurrencyProvider);
      final locale = Localizations.localeOf(context).languageCode;
      final profile = await ref.read(shopProfileProvider.future);
      final printerConfig = await ref.read(printerConfigProvider.future);
      final bytes = await buildLabeledTablePdf(
        shopName: profile.name,
        shopLogoUrl: profile.logoUrl,
        shopPhone: profile.phone,
        shopAddress: profile.address,
        title: l.accountingBalanceSheet,
        columnLabels: [l.pnlLine, '${l.pnlAmount} (${currency.label(locale)})'],
        columnFlex: const [3, 2],
        rightAlignColumns: const {1},
        // Same rows the on-screen view bolds: the Assets/Liabilities/Equity
        // totals and the Untracked line — see [_rows]' order.
        boldRowIndices: const {0, 4, 6, 9},
        rows: [
          for (final r in _rows(sheet))
            [r.$1, Money(r.$2).withCurrency(currency, locale)],
        ],
        pageFormat: printerConfig.pdfPaperSize,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/balance-sheet.pdf');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: l.accountingBalanceSheet,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
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
    final currency = ref.watch(shopCurrencyProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final closedThrough = ref.watch(booksClosedThroughProvider).valueOrNull;
    final async = ref.watch(balanceSheetProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.accountingBalanceSheet),
        actions: [
          IconButton(
            tooltip: l.salesReportExportPdf,
            icon: _exportingPdf
                ? const ButtonSpinner()
                : const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _exportingPdf ? null : _exportPdf,
          ),
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
                Money(amount).withCurrency(currency, locale),
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
              // Assets − Liabilities, i.e. what's left if every debt were
              // paid off today — a distinct figure from the "Assets" total
              // shown above, previously mislabeled with that same string so
              // the screen showed "Assets" twice with two different numbers.
              row(l.balanceSheetNetWorth,
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
