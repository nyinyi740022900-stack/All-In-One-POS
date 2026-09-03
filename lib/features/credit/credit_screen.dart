import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import '../accounts/payment_account_providers.dart';
import '../accounting/accounting_csv.dart';
import '../accounting/accounting_pdf.dart';
import '../accounting/accounting_providers.dart';
import '../license/license_providers.dart';
import '../license/premium_gate.dart';
import '../printing/printing_providers.dart';
import '../sell/payment_labels.dart';
import 'credit_providers.dart';
import 'credit_repository.dart';
import 'repayment_dialog.dart';

final _agingDay = DateFormat('yyyy-MM-dd');

String _agingBucketLabel(AppLocalizations l, int bucket) => switch (bucket) {
      0 => l.agingBucket0,
      1 => l.agingBucket1,
      2 => l.agingBucket2,
      _ => l.agingBucket3,
    };

/// Shares the aged receivables ledger as CSV: one row per still-owed sale
/// with its age bucket, then a per-bucket totals block — the file an
/// accountant chases debts from. Premium-gated by the caller, like every
/// other export.
Future<void> shareAgedReceivablesCsv(
  BuildContext context,
  WidgetRef ref,
) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final currency = ref.read(shopCurrencyProvider);
  final rows = ref.read(agedReceivablesProvider);
  final totals = ref.read(agingTotalsProvider);
  final csv = buildAgedReceivablesCsv(
    rows,
    totals,
    bucketLabels: [
      for (var i = 0; i < totals.length; i++) _agingBucketLabel(l, i),
    ],
    customerHeader: l.arHeaderCustomer,
    phoneHeader: l.arHeaderPhone,
    invoiceHeader: l.arHeaderInvoice,
    dateHeader: l.stockHistoryHeaderDate,
    daysHeader: l.arHeaderDays,
    bucketHeader: l.arHeaderBucket,
    outstandingHeader: l.arHeaderOutstanding,
    exponent: currency.exponent,
  );
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/receivables-aging.csv');
    await file.writeAsString(csv);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: l.creditTitle,
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
  }
}

/// Shares the aged receivables ledger as a PDF — same rows/bucket-totals
/// shape as [shareAgedReceivablesCsv]. Premium-gated by the caller.
Future<void> shareAgedReceivablesPdf(
  BuildContext context,
  WidgetRef ref,
) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final currency = ref.read(shopCurrencyProvider);
  final locale = Localizations.localeOf(context).languageCode;
  final rows = ref.read(agedReceivablesProvider);
  final totals = ref.read(agingTotalsProvider);
  final bucketLabels = [
    l.agingBucket0,
    l.agingBucket1,
    l.agingBucket2,
    l.agingBucket3,
  ];
  try {
    final profile = await ref.read(shopProfileProvider.future);
    final printerConfig = await ref.read(printerConfigProvider.future);
    final bytes = await buildLabeledTablePdf(
      shopName: profile.name,
      shopLogoUrl: profile.logoUrl,
      shopPhone: profile.phone,
      shopAddress: profile.address,
      title: l.creditTitle,
      columnLabels: [
        l.arHeaderCustomer,
        l.arHeaderPhone,
        l.arHeaderInvoice,
        l.stockHistoryHeaderDate,
        l.arHeaderDays,
        l.arHeaderBucket,
        l.arHeaderOutstanding,
      ],
      columnFlex: const [3, 2, 2, 2, 1, 2, 2],
      rightAlignColumns: const {6},
      rows: [
        for (final r in rows)
          [
            r.customerName,
            r.phone ?? '',
            r.invoiceNo,
            _agingDay.format(r.finalizedAt),
            '${DateTime.now().difference(r.finalizedAt).inDays}',
            _agingBucketLabel(l, r.bucket),
            Money(r.outstanding).withCurrency(currency, locale),
          ],
        for (var i = 0; i < totals.length; i++)
          [
            bucketLabels[i],
            '',
            '',
            '',
            '',
            '',
            Money(totals[i]).withCurrency(currency, locale),
          ],
      ],
      boldRowIndices: {
        for (var i = 0; i < totals.length; i++) rows.length + i,
      },
      emptyLabel: l.creditEmpty,
      pageFormat: printerConfig.pdfPaperSize,
    );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/receivables-aging.pdf');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: l.creditTitle,
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
  }
}

/// The credit book (အကြွေးစာရင်း): customers who owe, and their balances.
class CreditScreen extends ConsumerWidget {
  const CreditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final currency = ref.watch(shopCurrencyProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final filter = ref.watch(creditFilterProvider);
    final customers = filter == CreditFilter.all
        ? ref.watch(allCreditCustomersProvider)
        : ref.watch(creditCustomersProvider);
    final total = ref.watch(creditOutstandingTotalProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.creditTitle),
        actions: [
          IconButton(
            tooltip: l.salesReportExportPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () {
              if (!ref.read(isPremiumProvider)) {
                showPremiumRequiredDialog(
                  context,
                  l.arExportCsv,
                  benefit: l.arExportBenefit,
                );
                return;
              }
              shareAgedReceivablesPdf(context, ref);
            },
          ),
          IconButton(
            tooltip: l.arExportCsv,
            icon: const Icon(Icons.table_chart_outlined),
            onPressed: () {
              if (!ref.read(isPremiumProvider)) {
                showPremiumRequiredDialog(
                  context,
                  l.arExportCsv,
                  benefit: l.arExportBenefit,
                );
                return;
              }
              shareAgedReceivablesCsv(context, ref);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(AppTheme.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.creditTotalOutstanding,
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: AppTheme.space1),
                MoneyText(
                  Money(total).withCurrency(currency, locale),
                  textAlign: TextAlign.start,
                  emphasis: true,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppTheme.space2),
                _AgingStrip(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTheme.space4, AppTheme.space2, AppTheme.space4, 0),
            child: Row(
              children: [
                ChoiceChip(
                  label: Text(l.creditFilterOutstanding),
                  selected: filter == CreditFilter.outstanding,
                  onSelected: (_) => ref.read(creditFilterProvider.notifier).state =
                      CreditFilter.outstanding,
                ),
                const SizedBox(width: AppTheme.space2),
                ChoiceChip(
                  label: Text(l.creditFilterAll),
                  selected: filter == CreditFilter.all,
                  onSelected: (_) => ref.read(creditFilterProvider.notifier).state =
                      CreditFilter.all,
                ),
              ],
            ),
          ),
          Expanded(
            child: customers.isEmpty
                ? EmptyStateView(
                    icon: Icons.credit_score_outlined,
                    title: l.creditEmpty,
                  )
                : ListView.separated(
                    itemCount: customers.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = customers[i];
                      final settled = c.outstanding <= 0;
                      final colors = AppColors.of(context);
                      return ListTile(
                        leading: ProductThumb(
                          name: c.name,
                          size: 40,
                          radius: AppTheme.radiusFull,
                        ),
                        title: Text(c.name),
                        subtitle: Text(l.creditOpenInvoices(c.openInvoices)),
                        // Same StatusPill/MoneyText pair Accounts Payable's
                        // own settled/outstanding row already uses for the
                        // identical concept — this row used to hand-roll a
                        // third visual language for the same "owed" fact.
                        trailing: settled
                            ? StatusPill(
                                label: l.creditSettled,
                                tone: StatusTone.positive,
                                icon: Icons.check_circle,
                              )
                            : MoneyText(
                                Money(c.outstanding).withCurrency(currency, locale),
                                emphasis: true,
                                color: colors.danger,
                              ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CreditCustomerScreen(
                                customerKey: c.key, customerName: c.name),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// One customer's credit detail: outstanding, their credit invoices, and a
/// button to record a repayment.
class CreditCustomerScreen extends ConsumerWidget {
  const CreditCustomerScreen(
      {super.key, required this.customerKey, required this.customerName});

  /// The stable grouping key (see [creditKeyFor]) — used to match sales and
  /// repayments so a directory customer's rename doesn't orphan their
  /// history the way matching on the raw display name would.
  final String customerKey;
  final String customerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final currency = ref.watch(shopCurrencyProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final customer = ref.watch(creditCustomersProvider).firstWhere(
          (c) => c.key == customerKey,
          orElse: () => CreditCustomer(
              key: customerKey,
              name: customerName,
              billed: 0,
              paid: 0,
              openInvoices: 0),
        );
    final owedBySale = ref.watch(creditOwedBySaleProvider);
    final sales = (ref.watch(creditSalesProvider).valueOrNull ?? const <Sale>[])
        .where((s) =>
            creditKeyFor(s.customerId, (s.customerName ?? '').trim()) ==
            customerKey)
        .toList();
    final repayments =
        (ref.watch(repaymentsProvider).valueOrNull ?? const <CreditPayment>[])
            .where((p) =>
                creditKeyFor(p.customerId, p.customerName.trim()) ==
                customerKey)
            .toList();
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final accounts = ref.watch(paymentAccountsProvider).valueOrNull ?? const [];
    final colors = AppColors.of(context);
    // Owed figure per invoice, FIFO-adjusted (same rule as the Credit book
    // list above) — computed once here so row builders stay declarative.
    final invoiceRows = [
      for (final s in sales)
        (sale: s, owed: owedBySale[s.id] ?? (s.total - s.paid)),
    ];

    // Lazy builder over a flat row list (audit H3): a long-time customer's
    // invoices + repayments grow for years, and the old
    // `ListView(children: ...)` built EVERY ListTile up front. Widget
    // configs here are cheap; only visible rows are now laid out/built.
    final rows = <Widget>[
      Card(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l.creditOutstanding,
                  style: Theme.of(context).textTheme.titleMedium),
              MoneyText(
                Money(customer.outstanding).withCurrency(currency, locale),
                style: Theme.of(context).textTheme.titleLarge,
                emphasis: true,
                color: customer.outstanding > 0 ? colors.danger : colors.success,
              ),
            ],
          ),
        ),
      ),
      if (invoiceRows.isNotEmpty) ...[
        const SizedBox(height: AppTheme.space3),
        Text(l.creditInvoices, style: Theme.of(context).textTheme.titleSmall),
        for (final (:sale, :owed) in invoiceRows)
          ListTile(
            key: ValueKey('inv-${sale.id}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(sale.invoiceNo),
            subtitle: Text(df.format(sale.finalizedAt)),
            trailing: owed > 0
                ? MoneyText(
                    Money(owed).withCurrency(currency, locale),
                    color: colors.danger,
                  )
                : Text(l.creditSettled, style: TextStyle(color: colors.success)),
          ),
      ],
      if (repayments.isNotEmpty) ...[
        const SizedBox(height: AppTheme.space3),
        Text(l.creditRepayments, style: Theme.of(context).textTheme.titleSmall),
        for (final p in repayments)
          ListTile(
            key: ValueKey('rep-${p.id}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.check_circle, color: colors.success),
            title: Text('+${Money(p.amount).withCurrency(currency, locale)}'),
            subtitle: Text(
                '${paymentLabel(l, p.method, accounts: accounts)} · ${df.format(p.createdAt)}'),
          ),
      ],
    ];

    return Scaffold(
      appBar: AppBar(title: Text(customerName)),
      floatingActionButton: customer.outstanding > 0
          ? FloatingActionButton.extended(
              onPressed: () => _recordRepayment(context, ref, customer),
              icon: const Icon(Icons.payments),
              label: Text(l.creditRecordRepayment),
            )
          : null,
      body: ListView.builder(
        padding: const EdgeInsets.all(AppTheme.space4),
        itemCount: rows.length,
        itemBuilder: (context, i) => rows[i],
      ),
    );
  }

  Future<void> _recordRepayment(
      BuildContext context, WidgetRef ref, CreditCustomer customer) async {
    await showRepaymentDialog(context, customer);
  }
}

/// The four aging buckets (0–30/31–60/61–90/90+) as a compact row under the
/// total — where the money is stuck and how long it's been stuck, the two
/// things a collection round needs before anything else.
class _AgingStrip extends ConsumerWidget {
  const _AgingStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final totals = ref.watch(agingTotalsProvider);
    final currency = ref.watch(shopCurrencyProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final labels = [
      l.agingBucket0,
      l.agingBucket1,
      l.agingBucket2,
      l.agingBucket3,
    ];
    return Wrap(
      spacing: AppTheme.space2,
      runSpacing: AppTheme.space1,
      children: [
        for (var i = 0; i < totals.length; i++)
          StatusPill(
            label:
                '${labels[i]}: ${Money(totals[i]).withCurrency(currency, locale)}',
            tone: totals[i] > 0 ? StatusTone.attention : StatusTone.neutral,
          ),
      ],
    );
  }
}
