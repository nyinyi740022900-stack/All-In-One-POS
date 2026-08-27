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
import '../license/license_providers.dart';
import '../license/premium_gate.dart';
import '../printing/printing_providers.dart';
import 'accounting_csv.dart';
import 'accounting_pdf.dart';
import 'cash_flow_calculator.dart';
import 'accounting_providers.dart';

/// Cash Flow — per payment account, where the money stood at the start of
/// the period, what came in, what went out, and where it stands now, from
/// the same four tables the account balances fold. Owner
/// contributions/drawings carry no account and are deliberately outside
/// this statement (the note under the list says so).
class CashFlowScreen extends ConsumerStatefulWidget {
  const CashFlowScreen({super.key});

  @override
  ConsumerState<CashFlowScreen> createState() => _CashFlowScreenState();
}

class _CashFlowScreenState extends ConsumerState<CashFlowScreen> {
  bool _exporting = false;
  bool _exportingPdf = false;

  /// Inclusive start / exclusive end — defaults to this month, same shape
  /// as the P&L's own range.
  DateTime get _defaultStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  DateTime get _defaultEnd {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }

  DateTime? _start;
  DateTime? _end;

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _start != null && _end != null
          ? DateTimeRange(start: _start!, end: _end!.subtract(const Duration(days: 1)))
          : null,
    );
    if (picked == null) return;
    setState(() {
      _start = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _end = DateTime(picked.end.year, picked.end.month, picked.end.day)
          .add(const Duration(days: 1));
    });
  }

  Future<void> _exportCsv(List<AccountCashFlow> flows) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      final csv = buildCashFlowCsv(
        flows,
        accountHeader: l.paymentAccountNameLabel,
        openingHeader: l.cashFlowOpening,
        inflowHeader: l.cashFlowInflow,
        outflowHeader: l.cashFlowOutflow,
        closingHeader: l.cashFlowClosing,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/cash-flow.csv');
      await file.writeAsString(csv);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: l.accountingCashFlow,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportPdf(List<AccountCashFlow> flows, String rangeLabel) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exportingPdf = true);
    try {
      final sym = l.currencySymbol;
      var totalIn = 0;
      var totalOut = 0;
      for (final f in flows) {
        totalIn += f.inflow;
        totalOut += f.outflow;
      }
      final profile = await ref.read(shopProfileProvider.future);
      final printerConfig = await ref.read(printerConfigProvider.future);
      final bytes = await buildLabeledTablePdf(
        shopName: profile.name,
        shopLogoUrl: profile.logoUrl,
        shopPhone: profile.phone,
        shopAddress: profile.address,
        title: l.accountingCashFlow,
        subtitle: rangeLabel,
        columnLabels: [
          l.paymentAccountNameLabel,
          l.cashFlowOpening,
          l.cashFlowInflow,
          l.cashFlowOutflow,
          l.cashFlowClosing,
        ],
        columnFlex: const [3, 2, 2, 2, 2],
        rightAlignColumns: const {1, 2, 3, 4},
        boldRowIndices: {flows.length},
        rows: [
          for (final f in flows)
            [
              f.name,
              Money(f.opening).withSymbol(sym),
              Money(f.inflow).withSymbol(sym),
              Money(-f.outflow).withSymbol(sym),
              Money(f.closing).withSymbol(sym),
            ],
          [
            l.cashFlowInflow,
            '',
            Money(totalIn).withSymbol(sym),
            Money(-totalOut).withSymbol(sym),
            '',
          ],
        ],
        emptyLabel: l.cashFlowEmpty,
        pageFormat: printerConfig.pdfPaperSize,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/cash-flow.pdf');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: l.accountingCashFlow,
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
        appBar: AppBar(title: Text(l.accountingCashFlow)),
        body: PremiumGate(
          featureName: l.accountingCashFlow,
          benefits: [l.pnlBenefit1, l.pnlBenefit2],
          child: const SizedBox.shrink(),
        ),
      );
    }
    final sym = l.currencySymbol;
    final start = _start ?? _defaultStart;
    final end = _end ?? _defaultEnd;
    final df = DateFormat('yyyy-MM-dd');
    final flowsAsync = ref.watch(
      cashFlowProvider((start: start, endExclusive: end)),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l.accountingCashFlow),
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
      body: flowsAsync.when(
        loading: () => const AppLoadingView(),
        error: (_, _) => EmptyStateView(
          icon: Icons.error_outline,
          title: l.commonUnexpectedError,
          actionLabel: l.commonRetry,
          onAction: () => ref.invalidate(cashFlowProvider),
        ),
        data: (flows) {
          var totalIn = 0;
          var totalOut = 0;
          for (final f in flows) {
            totalIn += f.inflow;
            totalOut += f.outflow;
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space4, AppTheme.space3, AppTheme.space4, 0,
                ),
                child: Text(
                  '${df.format(start)} → ${df.format(end.subtract(const Duration(days: 1)))}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: flows.isEmpty
                    ? EmptyStateView(
                        icon: Icons.account_balance_wallet_outlined,
                        title: l.cashFlowEmpty,
                      )
                    : ListView(
                        padding: const EdgeInsets.all(AppTheme.space4),
                        children: [
                          for (final f in flows) ...[
                            Text(
                              f.name,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: AppTheme.space2),
                            SummaryRow(
                              l.cashFlowOpening,
                              Money(f.opening).withSymbol(sym),
                            ),
                            SummaryRow(
                              l.cashFlowInflow,
                              Money(f.inflow).withSymbol(sym),
                              color: AppColors.of(context).success,
                            ),
                            SummaryRow(
                              l.cashFlowOutflow,
                              Money(-f.outflow).withSymbol(sym),
                              color: f.outflow > 0
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                            ),
                            const Divider(),
                            SummaryRow(
                              l.cashFlowClosing,
                              Money(f.closing).withSymbol(sym),
                              emphasis: true,
                            ),
                            const SizedBox(height: AppTheme.space4),
                          ],
                          SummaryRow(
                            l.cashFlowInflow,
                            Money(totalIn).withSymbol(sym),
                            emphasis: true,
                          ),
                          SummaryRow(
                            l.cashFlowOutflow,
                            Money(-totalOut).withSymbol(sym),
                            emphasis: true,
                          ),
                          const SizedBox(height: AppTheme.space3),
                          Text(
                            l.cashFlowOwnerNote,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.space4),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _exportingPdf || flows.isEmpty
                              ? null
                              : () => _exportPdf(
                                  flows,
                                  '${df.format(start)} → '
                                  '${df.format(end.subtract(const Duration(days: 1)))}'),
                          icon: _exportingPdf
                              ? const ButtonSpinner()
                              : const Icon(Icons.picture_as_pdf_outlined),
                          label: Text(l.salesReportExportPdf),
                        ),
                      ),
                      const SizedBox(width: AppTheme.space2),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _exporting || flows.isEmpty
                              ? null
                              : () => _exportCsv(flows),
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
