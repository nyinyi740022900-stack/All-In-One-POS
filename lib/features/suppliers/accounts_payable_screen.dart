import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import '../accounts/payment_account_providers.dart';
import '../license/license_providers.dart';
import '../license/premium_gate.dart';
import '../sell/payment_labels.dart';
import 'accounts_payable.dart';
import 'accounts_payable_providers.dart';

/// Accounts Payable (ရောင်းသူပေးရန်ကျန်): suppliers the shop still owes
/// money to, aggregated from received purchase orders minus payments made
/// — the mirror image of the Credit book.
class AccountsPayableScreen extends ConsumerWidget {
  const AccountsPayableScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    if (ref.watch(licenseControllerProvider).loading ||
        !ref.watch(isPremiumProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l.accountsPayableTitle)),
        body: PremiumGate(
            featureName: l.accountsPayableTitle,
            child: const SizedBox.shrink()),
      );
    }
    final currency = l.currencySymbol;
    final balances = ref.watch(supplierBalancesProvider);
    final total = ref.watch(accountsPayableTotalProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.accountsPayableTitle)),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(AppTheme.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.apOutstanding,
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
          Expanded(
            child: balances.isEmpty
                ? Center(child: Text(l.apEmpty))
                : ListView.separated(
                    itemCount: balances.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final b = balances[i];
                      return ListTile(
                        leading: const CircleAvatar(
                            child: Icon(Icons.local_shipping_outlined)),
                        title: Text(b.name),
                        trailing: Text(
                          Money(b.outstanding).withSymbol(currency),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AccountsPayableSupplierScreen(
                                supplierKey: b.key, supplierName: b.name),
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

/// One supplier's Accounts Payable detail: outstanding, their received POs,
/// payment history, and a button to record a payment.
class AccountsPayableSupplierScreen extends ConsumerWidget {
  const AccountsPayableSupplierScreen(
      {super.key, required this.supplierKey, required this.supplierName});

  final String supplierKey;
  final String supplierName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final currency = l.currencySymbol;
    final balance = ref.watch(allSupplierBalancesProvider).firstWhere(
          (b) => b.key == supplierKey,
          orElse: () => SupplierBalance(
              key: supplierKey, name: supplierName, billed: 0, paid: 0),
        );
    final pos = (ref.watch(receivedPOsProvider).valueOrNull ??
            const <PurchaseOrder>[])
        .where((po) =>
            poSupplierKeyFor(po.supplierId, po.supplierName) == supplierKey)
        .toList();
    final payments = (ref.watch(supplierPaymentsProvider).valueOrNull ??
            const <SupplierPayment>[])
        .where((p) =>
            poSupplierKeyFor(p.supplierId, p.supplierName) == supplierKey)
        .toList();
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final accounts = ref.watch(paymentAccountsProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(supplierName)),
      floatingActionButton: balance.outstanding > 0
          ? FloatingActionButton.extended(
              onPressed: () => _recordPayment(context, ref, balance),
              icon: const Icon(Icons.payments),
              label: Text(l.apRecordPayment),
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
                  Text(l.apOutstanding,
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    Money(balance.outstanding).withSymbol(currency),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: balance.outstanding > 0
                              ? Theme.of(context).colorScheme.error
                              : Colors.green,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTheme.space3),
          Text(l.apReceivedPOs, style: Theme.of(context).textTheme.titleSmall),
          ...pos.map((po) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(po.poNo),
                subtitle: po.receivedAt != null
                    ? Text(df.format(po.receivedAt!))
                    : null,
                trailing: Text(Money(po.itemsTotal).withSymbol(currency)),
              )),
          if (payments.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space3),
            Text(l.apPayments, style: Theme.of(context).textTheme.titleSmall),
            ...payments.map((p) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: Text('-${Money(p.amount).withSymbol(currency)}'),
                  subtitle: Text(
                      '${paymentLabel(l, p.method, accounts: accounts)} · ${df.format(p.createdAt)}'),
                )),
          ],
        ],
      ),
    );
  }

  Future<void> _recordPayment(
      BuildContext context, WidgetRef ref, SupplierBalance balance) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _SupplierPaymentDialog(balance: balance),
    );
  }
}

class _SupplierPaymentDialog extends ConsumerStatefulWidget {
  const _SupplierPaymentDialog({required this.balance});
  final SupplierBalance balance;

  @override
  ConsumerState<_SupplierPaymentDialog> createState() =>
      _SupplierPaymentDialogState();
}

class _SupplierPaymentDialogState
    extends ConsumerState<_SupplierPaymentDialog> {
  final _amount = TextEditingController();
  String _method = 'cash';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amount.text = '${widget.balance.outstanding}';
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
    if (amount <= 0 || amount > widget.balance.outstanding) return;
    setState(() => _saving = true);
    try {
      await ref.read(accountsPayableRepositoryProvider).recordPayment(
            supplierName: widget.balance.name,
            supplierId: widget.balance.supplierId,
            amount: amount,
            method: _method,
          );
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(l.apPaymentSaved)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final accounts = ref.watch(paymentAccountsProvider).valueOrNull ?? const [];
    final methods = paymentMethodIds(accounts);
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    final exceedsOutstanding = amount > widget.balance.outstanding;
    return AlertDialog(
      title: Text(l.apRecordPayment),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(9),
            ],
            decoration: InputDecoration(
              labelText: l.creditAmount,
              errorText: exceedsOutstanding
                  ? l.creditRepaymentExceedsOutstanding(
                      Money(widget.balance.outstanding)
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
                  label: Text(paymentLabel(l, m, accounts: accounts)),
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
