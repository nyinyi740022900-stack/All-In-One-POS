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
import 'receipt_data.dart';
import 'sales_report_data.dart';
import 'sales_report_pdf.dart';
import 'sales_report_providers.dart';

/// Date-range sales report — reachable from the Invoices screen. Prints on
/// whatever the shop actually has: the paired Bluetooth thermal printer
/// (condensed list), or a real A4/A5 document shared out (AirPrint on the
/// same WiFi network, or saved/emailed to a computer to print from there).
class SalesReportScreen extends ConsumerStatefulWidget {
  const SalesReportScreen({super.key});

  @override
  ConsumerState<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends ConsumerState<SalesReportScreen> {
  bool _exporting = false;
  bool _exportingCsv = false;
  bool _printing = false;

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final start = ref.read(salesReportStartDateProvider);
    final end = ref.read(salesReportEndDateProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: start != null && end != null
          ? DateTimeRange(
              start: start,
              end: end.subtract(const Duration(days: 1)),
            )
          : null,
    );
    if (picked == null) return;
    ref.read(salesReportStartDateProvider.notifier).state = DateTime(
      picked.start.year,
      picked.start.month,
      picked.start.day,
    );
    ref.read(salesReportEndDateProvider.notifier).state = DateTime(
      picked.end.year,
      picked.end.month,
      picked.end.day,
    ).add(const Duration(days: 1));
  }

  String _rangeLabel(AppLocalizations l, DateTime? start, DateTime? end) {
    if (start == null || end == null) return l.salesReportAllDates;
    final df = DateFormat('yyyy-MM-dd');
    final inclusiveEnd = end.subtract(const Duration(days: 1));
    return '${df.format(start)} → ${df.format(inclusiveEnd)}';
  }

  Future<void> _exportPdf(SalesReport report, String rangeLabel) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      final profile = await ref.read(shopProfileProvider.future);
      final printerConfig = await ref.read(printerConfigProvider.future);
      final bytes = await buildSalesReportPdf(
        shopName: profile.name,
        shopLogoUrl: profile.logoUrl,
        shopPhone: profile.phone,
        shopAddress: profile.address,
        title: l.salesReportTitle,
        dateRangeLabel: rangeLabel,
        report: report,
        currencySymbol: l.currencySymbol,
        invoiceColumnLabel: l.salesReportColumnInvoice,
        dateColumnLabel: l.salesReportColumnDate,
        customerColumnLabel: l.salesReportColumnCustomer,
        addressColumnLabel: l.salesReportColumnAddress,
        amountColumnLabel: l.salesReportColumnAmount,
        totalLabel: l.salesReportTotal,
        noSalesLabel: l.salesReportEmpty,
        pageFormat: printerConfig.pdfPaperSize,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/sales-report.pdf');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: l.salesReportTitle,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportCsv(SalesReport report) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exportingCsv = true);
    try {
      final csv = buildSalesReportCsv(
        report,
        invoiceHeader: l.salesReportColumnInvoice,
        dateHeader: l.salesReportColumnDate,
        customerHeader: l.salesReportColumnCustomer,
        addressHeader: l.salesReportColumnAddress,
        amountHeader: l.salesReportColumnAmount,
        totalLabel: l.salesReportTotal,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/sales-report.csv');
      await file.writeAsString(csv);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: l.salesReportTitle,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    } finally {
      if (mounted) setState(() => _exportingCsv = false);
    }
  }

  Future<void> _printBluetooth(
    SalesReport report,
    String rangeLabel,
    String mac,
    PaperSize paper,
  ) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _printing = true);
    try {
      final profile = await ref.read(shopProfileProvider.future);
      final result = await ref
          .read(printerServiceProvider)
          .printReport(
            report,
            profile.name,
            paper: paper,
            mac: mac,
            title: l.salesReportTitle,
            dateRangeLabel: rangeLabel,
            totalLabel: l.salesReportTotal,
            noSalesLabel: l.salesReportEmpty,
          );
      messenger.showSnackBar(
        SnackBar(content: Text(result.ok ? l.printSuccess : l.printFailed)),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (ref.watch(licenseControllerProvider).loading ||
        !ref.watch(isPremiumProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l.salesReportTitle)),
        body: PremiumGate(
          featureName: l.salesReportTitle,
          benefits: [l.salesReportBenefit1, l.salesReportBenefit2],
          child: const SizedBox.shrink(),
        ),
      );
    }
    final sym = l.currencySymbol;
    final report = ref.watch(salesReportProvider);
    final start = ref.watch(salesReportStartDateProvider);
    final end = ref.watch(salesReportEndDateProvider);
    final printerConfig = ref.watch(printerConfigProvider).valueOrNull;
    final rangeLabel = _rangeLabel(l, start, end);
    final df = DateFormat('yyyy-MM-dd');

    return Scaffold(
      appBar: AppBar(
        title: Text(l.salesReportTitle),
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
                ref.read(salesReportStartDateProvider.notifier).state = null;
                ref.read(salesReportEndDateProvider.notifier).state = null;
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // The answer to "how much did we take in this period" is the whole
          // point of this screen, so it gets a tonal header band and the
          // biggest type on it — it used to be a `titleMedium` sharing a plain
          // row with the row count.
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space4,
              AppTheme.space3,
              AppTheme.space4,
              AppTheme.space3,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rangeLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        l.salesReportCount(report.rows.length),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppTheme.space3),
                MoneyText(
                  Money(report.total).withSymbol(sym),
                  style: Theme.of(context).textTheme.headlineSmall,
                  emphasis: true,
                ),
              ],
            ),
          ),
          Expanded(
            child: report.rows.isEmpty
                ? EmptyStateView(
                    icon: Icons.summarize_outlined,
                    title: l.salesReportEmpty,
                    // Which period came up empty is the one thing that makes
                    // this state actionable ("ah — wrong date range").
                    message: rangeLabel,
                  )
                : ListView.separated(
                    itemCount: report.rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = report.rows[i];
                      final detail = [
                        df.format(r.date),
                        if (r.customerName.isNotEmpty) r.customerName,
                        if (r.address.isNotEmpty) r.address,
                      ].join(' · ');
                      return ListTile(
                        title: Row(
                          children: [
                            Flexible(child: Text(r.invoiceNo)),
                            if (r.isRefund) ...[
                              const SizedBox(width: AppTheme.space2),
                              // Same pill as the Invoices list marks a
                              // reversal with, so a refund looks the same
                              // everywhere in the hub.
                              StatusPill(
                                label: l.invoiceRefunded,
                                tone: StatusTone.critical,
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: MoneyText(
                          Money(r.amount).withSymbol(sym),
                          style: Theme.of(context).textTheme.bodyLarge,
                          emphasis: true,
                          color: r.isRefund
                              ? AppColors.of(context).danger
                              : null,
                        ),
                      );
                    },
                  ),
          ),
          // Docked action bar: this is a long scrolling list, so the three
          // exports are pinned chrome rather than something you scroll to.
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: AppTheme.dockedBarShadow(
                Theme.of(context).brightness,
              ),
            ),
            child: SafeArea(
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
                              : () => _printBluetooth(
                                  report,
                                  rangeLabel,
                                  printerConfig.mac!,
                                  printerConfig.paper,
                                ),
                          icon: _printing
                              ? const ButtonSpinner()
                              : const Icon(Icons.print_outlined),
                          label: Text(l.salesReportPrintBluetooth),
                        ),
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.print_disabled_outlined,
                            size: 18,
                            color: AppColors.of(context).muted,
                          ),
                          const SizedBox(width: AppTheme.space2),
                          Expanded(
                            child: Text(
                              l.salesReportNoPrinter,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: AppTheme.space2),
                    // Two peer actions side by side rather than a stack of
                    // three full-width buttons, which read as three primary
                    // actions and pushed the list up by ~160pt.
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _exporting
                                ? null
                                : () => _exportPdf(report, rangeLabel),
                            icon: _exporting
                                ? const ButtonSpinner()
                                : const Icon(Icons.picture_as_pdf_outlined),
                            label: Text(l.salesReportExportPdf),
                          ),
                        ),
                        const SizedBox(width: AppTheme.space2),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _exportingCsv
                                ? null
                                : () => _exportCsv(report),
                            icon: _exportingCsv
                                ? const ButtonSpinner()
                                : const Icon(Icons.table_chart_outlined),
                            label: Text(l.salesReportExportCsv),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
