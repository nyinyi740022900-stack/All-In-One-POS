import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import '../sell/payment_labels.dart';
import '../sell/sales_providers.dart';
import 'credit_providers.dart';
import 'credit_repository.dart';

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
                const SizedBox(height: 4),
                Text(Money(total).withSymbol(currency),
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
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
                ? Center(child: Text(l.creditEmpty))
                : ListView.separated(
                    itemCount: customers.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = customers[i];
                      final settled = c.outstanding <= 0;
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(c.name),
                        subtitle: Text(l.creditOpenInvoices(c.openInvoices)),
                        trailing: settled
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle,
                                      color: Colors.green, size: 18),
                                  const SizedBox(width: 4),
                                  Text(l.creditSettled,
                                      style: const TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold)),
                                ],
                              )
                            : Text(
                                Money(c.outstanding).withSymbol(currency),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.error,
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

    return Scaffold(
      appBar: AppBar(title: Text(customerName)),
      floatingActionButton: customer.outstanding > 0
          ? FloatingActionButton.extended(
              onPressed: () => _recordRepayment(context, ref, customer),
              icon: const Icon(Icons.payments),
              label: Text(l.creditRecordRepayment),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.space4),
        children: [
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
                          color: customer.outstanding > 0
                              ? Theme.of(context).colorScheme.error
                              : Colors.green,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTheme.space3),
          Text(l.creditInvoices,
              style: Theme.of(context).textTheme.titleSmall),
          ...sales.map((s) {
            final owed = owedBySale[s.id] ?? (s.total - s.paid);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(s.invoiceNo),
              subtitle: Text(df.format(s.finalizedAt)),
              trailing: Text(
                owed > 0
                    ? Money(owed).withSymbol(currency)
                    : l.creditSettled,
                style: TextStyle(
                    color: owed > 0
                        ? Theme.of(context).colorScheme.error
                        : Colors.green),
              ),
            );
          }),
          if (repayments.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space3),
            Text(l.creditRepayments,
                style: Theme.of(context).textTheme.titleSmall),
            ...repayments.map((p) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: Text('+${Money(p.amount).withSymbol(currency)}'),
                  subtitle: Text(
                      '${paymentLabel(l, p.method)} · ${df.format(p.createdAt)}'),
                )),
          ],
        ],
      ),
    );
  }

  Future<void> _recordRepayment(
      BuildContext context, WidgetRef ref, CreditCustomer customer) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _RepaymentDialog(customer: customer),
    );
  }
}

class _RepaymentDialog extends ConsumerStatefulWidget {
  const _RepaymentDialog({required this.customer});
  final CreditCustomer customer;

  @override
  ConsumerState<_RepaymentDialog> createState() => _RepaymentDialogState();
}

class _RepaymentDialogState extends ConsumerState<_RepaymentDialog> {
  final _amount = TextEditingController();
  String _method = 'cash';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amount.text = '${widget.customer.outstanding}';
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (amount <= 0 || amount > widget.customer.outstanding) return;
    setState(() => _saving = true);
    try {
      await ref.read(creditRepositoryProvider).recordRepayment(
            customerName: widget.customer.name,
            customerId: widget.customer.customerId,
            amount: amount,
            method: _method,
          );
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(l.creditRepaymentSaved)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Repayments settle a debt — 'credit' isn't a tender here.
    final methods = paymentMethods.where((m) => m != 'credit').toList();
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    final exceedsOutstanding = amount > widget.customer.outstanding;
    return AlertDialog(
      title: Text(l.creditRecordRepayment),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: l.creditAmount,
              errorText: exceedsOutstanding
                  ? l.creditRepaymentExceedsOutstanding(
                      Money(widget.customer.outstanding)
                          .withSymbol(l.currencySymbol))
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppTheme.space3),
          Wrap(
            spacing: AppTheme.space2,
            children: [
              for (final m in methods)
                ChoiceChip(
                  label: Text(paymentLabel(l, m)),
                  selected: _method == m,
                  onSelected: (_) => setState(() => _method = m),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed:
              _saving || amount <= 0 || exceedsOutstanding ? null : _save,
          child: Text(l.commonSave),
        ),
      ],
    );
  }
}
