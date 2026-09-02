import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/thousands_formatter.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../accounts/payment_account_providers.dart';
import '../printing/printing_providers.dart';
import '../sell/payment_labels.dart';
import 'credit_providers.dart';
import 'credit_repository.dart';

/// Opens the record-a-repayment dialog for [customer]. Shared by the credit
/// book's customer screen and the invoice detail screen — the counter flow
/// "customer walks in to pay their credit" starts from whichever surface the
/// seller is already on, so both need the exact same dialog.
Future<void> showRepaymentDialog(
  BuildContext context,
  CreditCustomer customer,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => RepaymentDialog(customer: customer),
  );
}

/// Amount + payment-method entry for one repayment. Validates against the
/// customer's whole outstanding balance (repayments allocate FIFO across
/// their invoices, not to one specific invoice), writes via
/// [creditRepositoryProvider], pops itself, and confirms with a snackbar.
class RepaymentDialog extends ConsumerStatefulWidget {
  const RepaymentDialog({super.key, required this.customer});
  final CreditCustomer customer;

  @override
  ConsumerState<RepaymentDialog> createState() => _RepaymentDialogState();
}

class _RepaymentDialogState extends ConsumerState<RepaymentDialog> {
  final _amount = TextEditingController();
  String _method = 'cash';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amount.text = formatDecimalMinorUnits(
      widget.customer.outstanding,
      exponent: ref.read(shopCurrencyProvider).exponent,
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final amount = parseDecimalMinorUnits(
      _amount.text.trim(),
      exponent: ref.read(shopCurrencyProvider).exponent,
    );
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
    // Repayments settle a debt — 'credit' isn't a tender here, so this is
    // just cash + accounts (never includes it, unlike checkout).
    final accounts = ref.watch(paymentAccountsProvider).valueOrNull ?? const [];
    final methods = paymentMethodIds(accounts);
    final currency = ref.watch(shopCurrencyProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final amount = parseDecimalMinorUnits(
      _amount.text.trim(),
      exponent: currency.exponent,
    );
    final exceedsOutstanding = amount > widget.customer.outstanding;
    return AlertDialog(
      title: Text(l.creditRecordRepayment),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType:
                TextInputType.numberWithOptions(decimal: currency.exponent > 0),
            inputFormatters: [
              DecimalMoneyInputFormatter(exponent: currency.exponent),
              LengthLimitingTextInputFormatter(12),
            ],
            decoration: InputDecoration(
              labelText: l.creditAmount,
              errorText: exceedsOutstanding
                  ? l.creditRepaymentExceedsOutstanding(
                      Money(widget.customer.outstanding)
                          .withCurrency(currency, locale))
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
