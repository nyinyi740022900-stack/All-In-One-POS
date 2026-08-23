import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import '../accounts/payment_account_providers.dart';
import '../sell/payment_labels.dart';
import 'credit_providers.dart';
import 'credit_repository.dart';
import 'repayment_dialog.dart';

/// The credit book (အကြွေးစာရင်း): customers who owe, and their balances.
class CreditScreen extends ConsumerWidget {
  const CreditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final currency = l.currencySymbol;
    final filter = ref.watch(creditFilterProvider);
    final customers = filter == CreditFilter.all
        ? ref.watch(allCreditCustomersProvider)
        : ref.watch(creditCustomersProvider);
    final total = ref.watch(creditOutstandingTotalProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.creditTitle)),
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
                  Money(total).withSymbol(currency),
                  textAlign: TextAlign.start,
                  emphasis: true,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
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
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(c.name),
                        subtitle: Text(l.creditOpenInvoices(c.openInvoices)),
                        trailing: settled
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle,
                                      color: colors.success, size: 18),
                                  const SizedBox(width: AppTheme.space1),
                                  Text(l.creditSettled,
                                      style: TextStyle(
                                          color: colors.success,
                                          fontWeight: FontWeight.bold)),
                                ],
                              )
                            : Text(
                                Money(c.outstanding).withSymbol(currency),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: colors.danger,
                                ),
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
    final currency = l.currencySymbol;
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
              Text(
                Money(customer.outstanding).withSymbol(currency),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color:
                          customer.outstanding > 0 ? colors.danger : colors.success,
                    ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: AppTheme.space3),
      Text(l.creditInvoices, style: Theme.of(context).textTheme.titleSmall),
      for (final (:sale, :owed) in invoiceRows)
        ListTile(
          key: ValueKey('inv-${sale.id}'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(sale.invoiceNo),
          subtitle: Text(df.format(sale.finalizedAt)),
          trailing: Text(
            owed > 0
                ? Money(owed).withSymbol(currency)
                : l.creditSettled,
            style: TextStyle(
                color: owed > 0 ? colors.danger : colors.success),
          ),
        ),
      if (repayments.isNotEmpty) ...[
        const SizedBox(height: AppTheme.space3),
        Text(l.creditRepayments, style: Theme.of(context).textTheme.titleSmall),
        for (final p in repayments)
          ListTile(
            key: ValueKey('rep-${p.id}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.check_circle, color: colors.success),
            title: Text('+${Money(p.amount).withSymbol(currency)}'),
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
