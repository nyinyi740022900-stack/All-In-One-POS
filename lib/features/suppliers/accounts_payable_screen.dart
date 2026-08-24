import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          benefits: [l.accountsPayableBenefit1, l.accountsPayableBenefit2],
          child: const SizedBox.shrink(),
        ),
      );
    }
    final currency = l.currencySymbol;
    final filter = ref.watch(accountsPayableFilterProvider);
    final balances = filter == AccountsPayableFilter.all
        ? ref.watch(allSupplierBalancesProvider)
        : ref.watch(supplierBalancesProvider);
    final total = ref.watch(accountsPayableTotalProvider);

    Future<void> exportCsv() async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        final csv = buildAccountsPayableCsv(
          balances,
          supplierHeader: l.supplierNameLabel,
          billedHeader: l.apBilledHeader,
          paidHeader: l.apPaidHeader,
          outstandingHeader: l.apOutstanding,
        );
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/accounts-payable.csv');
        await file.writeAsString(csv);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'text/csv')],
            subject: l.accountsPayableTitle,
          ),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text(l.commonUnexpectedError)),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.accountsPayableTitle),
        actions: [
          IconButton(
            tooltip: l.apExportCsv,
            icon: const Icon(Icons.table_chart_outlined),
            onPressed: exportCsv,
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
                Text(l.apOutstanding,
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
                  selected: filter == AccountsPayableFilter.outstanding,
                  onSelected: (_) =>
                      ref.read(accountsPayableFilterProvider.notifier).state =
                          AccountsPayableFilter.outstanding,
                ),
                const SizedBox(width: AppTheme.space2),
                ChoiceChip(
                  label: Text(l.creditFilterAll),
                  selected: filter == AccountsPayableFilter.all,
                  onSelected: (_) =>
                      ref.read(accountsPayableFilterProvider.notifier).state =
                          AccountsPayableFilter.all,
                ),
              ],
            ),
          ),
          Expanded(
            child: balances.isEmpty
                ? EmptyStateView(
                    icon: Icons.local_shipping_outlined,
                    title: l.apEmpty,
                  )
                : ListView.separated(
                    itemCount: balances.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final b = balances[i];
                      final settled = b.outstanding <= 0;
                      final colors = AppColors.of(context);
                      return ListTile(
                        leading: const IconAvatar(
                            icon: Icons.local_shipping_outlined),
                        title: Text(b.name),
                        trailing: settled
                            ? StatusPill(
                                label: l.creditSettled,
                                tone: StatusTone.positive,
                                icon: Icons.check_circle,
                              )
                            : MoneyText(
                                Money(b.outstanding).withSymbol(currency),
                                emphasis: true,
                                color: colors.danger,
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
    final colors = AppColors.of(context);

    // Lazy builder over a flat row list (audit H3): a supplier's received
    // POs and payment history grow for years, and the old
    // `ListView(children: ...)` built EVERY ListTile up front. Widget
    // configs here are cheap; only visible rows are now laid out/built.
    final rows = <Widget>[
      Card(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l.apOutstanding,
                  style: Theme.of(context).textTheme.titleMedium),
              MoneyText(
                Money(balance.outstanding).withSymbol(currency),
                emphasis: true,
                style: Theme.of(context).textTheme.titleLarge,
                color: balance.outstanding > 0
                    ? colors.danger
                    : colors.success,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: AppTheme.space3),
      Text(l.apReceivedPOs, style: Theme.of(context).textTheme.titleSmall),
      for (final po in pos)
        ListTile(
          key: ValueKey('po-${po.id}'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(po.poNo),
          subtitle: po.receivedAt != null
              ? Text(df.format(po.receivedAt!))
              : null,
          trailing: MoneyText(Money(po.itemsTotal).withSymbol(currency)),
        ),
      if (payments.isNotEmpty) ...[
        const SizedBox(height: AppTheme.space3),
        Text(l.apPayments, style: Theme.of(context).textTheme.titleSmall),
        for (final p in payments)
          ListTile(
            key: ValueKey('pay-${p.id}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.check_circle, color: colors.success),
            title: MoneyText(
              '-${Money(p.amount).withSymbol(currency)}',
              textAlign: TextAlign.left,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            subtitle: Text(
                '${paymentLabel(l, p.method, accounts: accounts)} · ${df.format(p.createdAt)}'),
          ),
      ],
    ];

    return Scaffold(
      appBar: AppBar(title: Text(supplierName)),
      floatingActionButton: balance.outstanding > 0
          ? FloatingActionButton.extended(
              onPressed: () => _recordPayment(context, ref, balance),
              icon: const Icon(Icons.payments),
              label: Text(l.apRecordPayment),
            )
          : null,
      body: ListView.builder(
        padding: const EdgeInsets.all(AppTheme.space4),
        itemCount: rows.length,
        itemBuilder: (context, i) => rows[i],
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
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text(l.commonUnexpectedError)));
      }
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
