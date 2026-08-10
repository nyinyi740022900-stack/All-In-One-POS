import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../expenses/expense_screen.dart' show categoryLabel;
import '../invoices/receipt_data.dart';
import '../license/license_providers.dart';
import '../license/premium_gate.dart';
import '../printing/printing_providers.dart';
import 'pnl_data.dart';
import 'pnl_formatter.dart';
import 'pnl_pdf.dart';
import 'pnl_providers.dart';

/// Profit & Loss statement — Revenue − COGS = Gross Profit; Gross Profit −
/// operating expenses = Net Profit — for a chosen date range. Reachable from
/// the Analytics screen's app bar, same relationship Sales Report has to
/// Invoices. Every figure is derived from already-synced data (sales, sale
/// items, expenses); nothing new is stored.
class PnlScreen extends ConsumerStatefulWidget {
  const PnlScreen({super.key});

  @override
  ConsumerState<PnlScreen> createState() => _PnlScreenState();
}

class _PnlScreenState extends ConsumerState<PnlScreen> {
  bool _exporting = false;
  bool _exportingCsv = false;
  bool _printing = false;

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final start = ref.read(pnlStartDateProvider);
    final end = ref.read(pnlEndDateProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: start != null && end != null
          ? DateTimeRange(
              start: start, end: end.subtract(const Duration(days: 1)))
          : null,
    );
    if (picked == null) return;
    ref.read(pnlStartDateProvider.notifier).state =
        DateTime(picked.start.year, picked.start.month, picked.start.day);
    ref.read(pnlEndDateProvider.notifier).state =
        DateTime(picked.end.year, picked.end.month, picked.end.day)
            .add(const Duration(days: 1));
  }

  String _rangeLabel(PnlStatement p) {
    final df = DateFormat('yyyy-MM-dd');
    final inclusiveEnd = p.end.subtract(const Duration(days: 1));
    return '${df.format(p.start)} → ${df.format(inclusiveEnd)}';
  }

  Future<void> _exportPdf(PnlStatement p) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      final profile = await ref.read(shopProfileProvider.future);
      final printerConfig = await ref.read(printerConfigProvider.future);
      final bytes = await buildPnlPdf(
        shopName: profile.name,
        shopLogoUrl: profile.logoUrl,
        shopPhone: profile.phone,
        shopAddress: profile.address,
        title: l.pnlTitle,
        statement: p,
        currencySymbol: l.currencySymbol,
        dateRangeLabel: l.pnlDateRange,
        revenueLabel: l.pnlRevenue,
        cogsLabel: l.pnlCogs,
        grossProfitLabel: l.pnlGrossProfit,
        totalExpensesLabel: l.pnlTotalExpenses,
        netProfitLabel: l.pnlNetProfit,
        categoryLabel: (c) => categoryLabel(l, c),
        pageFormat: printerConfig.pdfPaperSize,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/profit-and-loss.pdf');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: l.pnlTitle,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportCsv(PnlStatement p) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exportingCsv = true);
    try {
      final csv = buildPnlCsv(
        p,
        lineHeader: l.pnlLine,
        amountHeader: l.pnlAmount,
        revenueLabel: l.pnlRevenue,
        cogsLabel: l.pnlCogs,
        grossProfitLabel: l.pnlGrossProfit,
        totalExpensesLabel: l.pnlTotalExpenses,
        netProfitLabel: l.pnlNetProfit,
        categoryLabel: (c) => categoryLabel(l, c),
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/profit-and-loss.csv');
      await file.writeAsString(csv);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: l.pnlTitle,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    } finally {
      if (mounted) setState(() => _exportingCsv = false);
    }
  }

  Future<void> _printBluetooth(PnlStatement p, String mac, PaperSize paper) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _printing = true);
    try {
      final profile = await ref.read(shopProfileProvider.future);
      final lines = PnlFormatter(paper: paper, currencySymbol: l.currencySymbol)
          .format(
        p,
        title: l.pnlTitle,
        dateRangeLabel: l.pnlDateRange,
        revenueLabel: l.pnlRevenue,
        cogsLabel: l.pnlCogs,
        grossProfitLabel: l.pnlGrossProfit,
        totalExpensesLabel: l.pnlTotalExpenses,
        netProfitLabel: l.pnlNetProfit,
        categoryLabel: (c) => categoryLabel(l, c),
      );
      final result = await ref
          .read(printerServiceProvider)
          .printZReport(lines, profile.name, paper: paper, mac: mac);
      messenger.showSnackBar(SnackBar(
          content: Text(result.ok ? l.printSuccess : l.printFailed)));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Widget _row(BuildContext context, String label, int amount, String currency,
      {bool bold = false, bool indent = false, Color? color}) {
    return Padding(
      padding: EdgeInsets.only(
          left: indent ? AppTheme.space4 : 0,
          top: AppTheme.space1,
          bottom: AppTheme.space1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: bold
                  ? Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)
                  : Theme.of(context).textTheme.bodyMedium),
          Text(
            Money(amount).withSymbol(currency),
            style: (bold
                    ? Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)
                    : Theme.of(context).textTheme.bodyMedium)
                ?.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (ref.watch(licenseControllerProvider).loading ||
        !ref.watch(isPremiumProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l.pnlTitle)),
        body: PremiumGate(featureName: l.pnlTitle, child: const SizedBox.shrink()),
      );
    }
    final sym = l.currencySymbol;
    final start = ref.watch(pnlStartDateProvider);
    final end = ref.watch(pnlEndDateProvider);
    final printerConfig = ref.watch(printerConfigProvider).valueOrNull;
    final statementAsync = ref.watch(pnlStatementProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.pnlTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range_outlined),
            tooltip: l.stockHistoryPickDateRange,
            onPressed: _pickRange,
          ),
          if (start != null && end != null)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: l.stockHistoryClearDateRange,
              onPressed: () {
                ref.read(pnlStartDateProvider.notifier).state = null;
                ref.read(pnlEndDateProvider.notifier).state = null;
              },
            ),
        ],
      ),
      body: statementAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(l.commonUnexpectedError)),
        data: (p) {
          final netColor = p.netProfit < 0
              ? AppColors.of(context).danger
              : AppColors.of(context).success;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppTheme.space4),
                  children: [
                    Text(_rangeLabel(p),
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: AppTheme.space3),
                    _row(context, l.pnlRevenue, p.revenue, sym),
                    _row(context, l.pnlCogs, -p.cogs, sym),
                    const Divider(),
                    _row(context, l.pnlGrossProfit, p.grossProfit, sym,
                        bold: true),
                    const SizedBox(height: AppTheme.space3),
                    for (final entry in p.expensesByCategory.entries)
                      if (entry.value != 0)
                        _row(context, categoryLabel(l, entry.key),
                            -entry.value, sym,
                            indent: true),
                    _row(context, l.pnlTotalExpenses, -p.totalExpenses, sym),
                    const Divider(),
                    _row(context, l.pnlNetProfit, p.netProfit, sym,
                        bold: true, color: netColor),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.space4),
                  child: Column(
                    children: [
                      if (printerConfig != null && printerConfig.hasPrinter)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _printing
                                ? null
                                : () => _printBluetooth(p,
                                    printerConfig.mac!, printerConfig.paper),
                            icon: _printing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.print_outlined),
                            label: Text(l.salesReportPrintBluetooth),
                          ),
                        )
                      else
                        Text(l.salesReportNoPrinter,
                            style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: AppTheme.space2),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed:
                              _exporting ? null : () => _exportPdf(p),
                          icon: _exporting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.picture_as_pdf_outlined),
                          label: Text(l.salesReportExportPdf),
                        ),
                      ),
                      const SizedBox(height: AppTheme.space2),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _exportingCsv
                              ? null
                              : () => _exportCsv(p),
                          icon: _exportingCsv
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.table_chart_outlined),
                          label: Text(l.pnlExportCsv),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
