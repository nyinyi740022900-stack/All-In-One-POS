import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../analytics/analytics_providers.dart';
import '../analytics/pnl_data.dart';
import '../analytics/pnl_pdf.dart';
import '../credit/credit_providers.dart';
import '../expenses/expense_screen.dart' show categoryLabel;
import '../license/license_providers.dart';
import '../sell/sales_providers.dart' show salesStreamProvider;
import '../license/premium_gate.dart';
import '../printing/printing_providers.dart';

/// The tax period's statement — same derivation as the P&L (revenue − COGS
/// − expenses by category) with its own date range so it doesn't fight the
/// P&L screen's picker. Default: this year to date.
final taxStatementProvider = FutureProvider.family<PnlStatement,
    ({DateTime start, DateTime endExclusive})>((ref, period) async {
  ref.watch(salesStreamProvider);
  ref.watch(expenseChangesProvider);
  final repo = ref.watch(analyticsRepositoryProvider);
  final summary = await repo.summary(period.start, period.endExclusive,
      creditOwedBySaleId: ref.watch(creditOwedBySaleProvider));
  final byCategory = await repo.expensesByCategory(
    period.start,
    period.endExclusive,
  );
  return buildPnlStatement(
    summary,
    expensesByCategory: byCategory,
    start: period.start,
    end: period.endExclusive,
  );
});

/// Tax Summary — the figures a tax filing needs for a period (default: this
/// year): turnover, COGS, gross profit, expenses by category, net profit,
/// plus the credit-sales slice. Deliberately NO tax computation: rates and
/// slabs change with law and jurisdiction, so this report gives the
/// accountant the inputs and stays out of the arithmetic.
class TaxReportScreen extends ConsumerStatefulWidget {
  const TaxReportScreen({super.key});

  @override
  ConsumerState<TaxReportScreen> createState() => _TaxReportScreenState();
}

class _TaxReportScreenState extends ConsumerState<TaxReportScreen> {
  bool _exporting = false;

  DateTime? _start;
  DateTime? _end;

  DateTime get _defaultStart {
    final now = DateTime.now();
    return DateTime(now.year, 1, 1);
  }

  DateTime get _defaultEnd {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _start != null && _end != null
          ? DateTimeRange(
              start: _start!, end: _end!.subtract(const Duration(days: 1)))
          : null,
    );
    if (picked == null) return;
    setState(() {
      _start =
          DateTime(picked.start.year, picked.start.month, picked.start.day);
      _end = DateTime(picked.end.year, picked.end.month, picked.end.day)
          .add(const Duration(days: 1));
    });
  }

  Future<void> _exportCsv(PnlStatement p) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      final csv = buildPnlCsv(
        p,
        lineHeader: l.pnlLine,
        amountHeader: l.pnlAmount,
        revenueLabel: l.taxRevenueLabel,
        cogsLabel: l.pnlCogs,
        grossProfitLabel: l.pnlGrossProfit,
        totalExpensesLabel: l.pnlTotalExpenses,
        netProfitLabel: l.taxNetProfitLabel,
        categoryLabel: (c) => categoryLabel(l, c),
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/tax-summary.csv');
      await file.writeAsString(csv);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: l.accountingTaxSummary,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
        title: l.accountingTaxSummary,
        statement: p,
        currencySymbol: l.currencySymbol,
        dateRangeLabel: l.pnlDateRange,
        revenueLabel: l.taxRevenueLabel,
        cogsLabel: l.pnlCogs,
        grossProfitLabel: l.pnlGrossProfit,
        totalExpensesLabel: l.pnlTotalExpenses,
        netProfitLabel: l.taxNetProfitLabel,
        categoryLabel: (c) => categoryLabel(l, c),
        pageFormat: printerConfig.pdfPaperSize,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/tax-summary.pdf');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: l.accountingTaxSummary,
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
        appBar: AppBar(title: Text(l.accountingTaxSummary)),
        body: PremiumGate(
          featureName: l.accountingTaxSummary,
          benefits: [l.pnlBenefit1, l.pnlBenefit2],
          child: const SizedBox.shrink(),
        ),
      );
    }
    final sym = l.currencySymbol;
    final start = _start ?? _defaultStart;
    final end = _end ?? _defaultEnd;
    final df = DateFormat('yyyy-MM-dd');
    ref.watch(creditOwedBySaleProvider); // repayment-aware credit figures
    final statementAsync = ref.watch(taxStatementProvider(
      (start: start, endExclusive: end),
    ));

    return Scaffold(
      appBar: AppBar(
        title: Text(l.accountingTaxSummary),
        actions: [
          IconButton(
            tooltip: l.stockHistoryPickDateRange,
            icon: const Icon(Icons.date_range_outlined),
            onPressed: _pickRange,
          ),
          if (_start != null && _end != null)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: l.stockHistoryClearDateRange,
              onPressed: () => setState(() {
                _start = null;
                _end = null;
              }),
            ),
        ],
      ),
      body: statementAsync.when(
        loading: () => const AppLoadingView(),
        error: (_, _) => EmptyStateView(
          icon: Icons.error_outline,
          title: l.commonUnexpectedError,
          actionLabel: l.commonRetry,
          onAction: () => ref.invalidate(taxStatementProvider),
        ),
        data: (p) {
          Widget row(String label, int amount, {bool bold = false}) =>
              SummaryRow(label, Money(amount).withSymbol(sym), emphasis: bold);
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppTheme.space4),
                  children: [
                    Text(
                      '${df.format(start)} → ${df.format(end.subtract(const Duration(days: 1)))}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppTheme.space3),
                    row(l.taxRevenueLabel, p.revenue),
                    row(l.pnlCogs, -p.cogs),
                    const Divider(),
                    row(l.pnlGrossProfit, p.grossProfit, bold: true),
                    const SizedBox(height: AppTheme.space3),
                    for (final entry in p.expensesByCategory.entries)
                      if (entry.value != 0)
                        SummaryRow(
                          categoryLabel(l, entry.key),
                          Money(-entry.value).withSymbol(sym),
                        ),
                    row(l.pnlTotalExpenses, -p.totalExpenses),
                    const Divider(),
                    row(
                      l.taxNetProfitLabel,
                      p.netProfit,
                      bold: true,
                    ),
                    const SizedBox(height: AppTheme.space3),
                    Text(
                      l.taxNoComputationNote,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.space4),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _exporting ? null : () => _exportPdf(p),
                          icon: _exporting
                              ? const ButtonSpinner()
                              : const Icon(Icons.picture_as_pdf_outlined),
                          label: Text(l.salesReportExportPdf),
                        ),
                      ),
                      const SizedBox(height: AppTheme.space2),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _exporting ? null : () => _exportCsv(p),
                          icon: _exporting
                              ? const ButtonSpinner()
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
