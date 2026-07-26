import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../data/local/database.dart';
import '../customers/customer_providers.dart';
import '../inventory/inventory_providers.dart';
import '../license/license_providers.dart';
import '../printing/print_action.dart';
import '../printing/printing_providers.dart';
import '../staff/staff_providers.dart';
import 'cart.dart';
import 'payment_labels.dart';
import 'sales_providers.dart';

class CheckoutSheet extends ConsumerStatefulWidget {
  const CheckoutSheet({super.key});

  @override
  ConsumerState<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends ConsumerState<CheckoutSheet> {
  String _method = 'cash';
  final _paid = TextEditingController();
  final _customer = TextEditingController();
  final _phone = TextEditingController();
  bool _submitting = false;
  // Seller-controlled, per-sale: reveal the optional customer name/phone fields.
  bool _addCustomer = false;
  // Set when a directory customer was picked from the autocomplete; cleared
  // whenever the name is edited by hand so a stale id never gets attached to
  // the wrong typed name.
  String? _selectedCustomerId;
  // True once `_confirm` has cleared the cart on a successful sale — guards
  // `dispose` so a cancelled/dismissed sheet reverts any tier it applied.
  bool _confirmed = false;

  @override
  void dispose() {
    // Cancelled/dismissed without confirming — don't leave a picked
    // customer's tier pricing applied to the cart for whatever happens next.
    if (!_confirmed) {
      ref.read(cartProvider.notifier).setCustomerTier(null);
    }
    _paid.dispose();
    _customer.dispose();
    _phone.dispose();
    super.dispose();
  }

  int get _paidAmount => int.tryParse(_paid.text.trim()) ?? 0;

  /// Amount tendered. Empty field means "paid in full" for a normal method, or
  /// "nothing down" for the credit method.
  int _resolvePaid(int total) {
    if (_paid.text.trim().isEmpty) return _method == 'credit' ? 0 : total;
    return _paidAmount;
  }

  Future<void> _confirm(CartState cart, int total) async {
    final l = AppLocalizations.of(context);

    // License gate: no finalizing sales once past the grace period.
    if (!ref.read(licenseControllerProvider).canSell) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.licenseReadOnly)),
      );
      return;
    }

    final paid = _resolvePaid(total);
    final owed = total - paid;
    final name = _customer.text.trim();
    // A shortfall is booked as credit, and the credit method is always credit —
    // both need a customer name to bill. Phone stays optional.
    if ((owed > 0 || _method == 'credit') && name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.creditCustomerRequired)),
      );
      return;
    }

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final salesRepo = ref.read(salesRepositoryProvider);
      final phone = _phone.text.trim();
      // Prefer the directory entry the seller picked from the autocomplete;
      // otherwise resolve (or create) one by the typed name so repeat
      // customers still link to one directory entry over time even if the
      // seller never bothers with the dropdown.
      final customerId = name.isEmpty
          ? null
          : _selectedCustomerId ??
              await ref.read(customerRepositoryProvider).resolveOrCreate(
                    name,
                    phone: phone.isEmpty ? null : phone,
                  );
      final result = await salesRepo.finalizeSale(
        cart: cart,
        paymentMethod: _method,
        paid: paid,
        customerName: name.isEmpty ? null : name,
        customerPhone: phone.isEmpty ? null : phone,
        customerId: customerId,
        staffId: ref.read(activeStaffIdProvider).valueOrNull,
        trackStock: ref.read(trackStockProvider).valueOrNull ?? true,
      );

      // Auto-print the receipt if a printer is configured (done before the
      // sheet closes so the context is still valid).
      final config = await ref.read(settingsRepositoryProvider).printerConfig();
      if (config.hasPrinter && mounted) {
        final sale = await salesRepo.getSale(result.saleId);
        final items = await salesRepo.saleItems(result.saleId);
        if (mounted) {
          await printSaleReceipt(context, ref, sale: sale, items: items);
        }
      }

      _confirmed = true;
      ref.read(cartProvider.notifier).clear();
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(l.sellCompleted)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cart = ref.watch(cartProvider);
    final currency = l.currencySymbol;
    // Live stock per product, to cap the qty steppers (no overselling).
    final trackStock = ref.watch(trackStockProvider).valueOrNull ?? true;
    final stockById = <String, int>{
      for (final p in ref.watch(productsStreamProvider).valueOrNull ?? const [])
        p.product.id: p.quantity,
    };
    final total = cart.total.kyat;
    final paid = _resolvePaid(total);
    final change = paid > total ? paid - total : 0;
    final owed = total - paid > 0 ? total - paid : 0;
    // Credit / any shortfall forces the customer fields (name is then required).
    final forced = _method == 'credit' || owed > 0;
    final showCustomer = _addCustomer || forced;

    return Padding(
      padding: EdgeInsets.only(
        left: AppTheme.space4,
        right: AppTheme.space4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppTheme.space4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.sellCheckout,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppTheme.space3),

            // Cart lines with qty steppers.
            ...cart.lines.map((line) => _CartLineTile(
                  line: line,
                  lineTotal: cart.lineTotalFor(line),
                  currency: currency,
                  onInc: () {
                    final ok = ref.read(cartProvider.notifier).increment(
                          line.product.id,
                          maxQty: trackStock
                              ? stockById[line.product.id]
                              : null,
                        );
                    if (!ok) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            l.sellStockCap(stockById[line.product.id] ?? 0)),
                        duration: const Duration(seconds: 1),
                      ));
                    }
                  },
                  onDec: () => ref
                      .read(cartProvider.notifier)
                      .decrement(line.product.id),
                )),
            const Divider(),

            _row(l.sellSubtotal, cart.subtotal.withSymbol(currency)),
            _DiscountField(
              onChanged: (v) =>
                  ref.read(cartProvider.notifier).setDiscount(v),
            ),
            _row(l.commonTotal, Money(total).withSymbol(currency), bold: true),
            const SizedBox(height: AppTheme.space3),

            Text(l.sellPaymentMethod,
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: AppTheme.space2),
            Wrap(
              spacing: AppTheme.space2,
              children: [
                for (final m in paymentMethods)
                  ChoiceChip(
                    label: Text(paymentLabel(l, m)),
                    selected: _method == m,
                    onSelected: (_) => setState(() => _method = m),
                  ),
              ],
            ),

            const SizedBox(height: AppTheme.space3),
            // Amount paid — shown for every method. Leave blank to pay in full.
            TextField(
              controller: _paid,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText:
                    _method == 'credit' ? l.creditPaidNow : l.sellAmountPaid,
                hintText: Money(total).withSymbol(currency),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppTheme.space2),
            if (owed > 0)
              _row(l.creditOwed, Money(owed).withSymbol(currency), bold: true)
            else
              _row(l.sellChange, Money(change).withSymbol(currency)),

            // Inline switch so the seller can add customer details on demand.
            // Forced on (and locked) for credit / partial-payment sales.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(l.checkoutAddCustomer),
              value: showCustomer,
              onChanged:
                  forced ? null : (v) => setState(() => _addCustomer = v),
            ),

            if (showCustomer) ...[
              _CustomerAutocomplete(
                controller: _customer,
                labelText: forced
                    ? '${l.creditCustomerName} *'
                    : l.creditCustomerName,
                helperText: forced ? l.creditCustomerRequired : null,
                onChanged: () => setState(() {}),
                onSelected: (c) => setState(() {
                  _selectedCustomerId = c.id;
                  _customer.text = c.name;
                  _phone.text = c.phone ?? '';
                  ref
                      .read(cartProvider.notifier)
                      .setCustomerTier(c.tier == 'retail' ? null : c.tier);
                }),
                onEditedByHand: () {
                  _selectedCustomerId = null;
                  ref.read(cartProvider.notifier).setCustomerTier(null);
                },
              ),
              const SizedBox(height: AppTheme.space2),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: l.customerPhone),
              ),
              if (cart.customerTier != null) ...[
                const SizedBox(height: AppTheme.space2),
                Text(
                  l.checkoutTierPricingApplied(_tierLabel(l, cart.customerTier!)),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12),
                ),
              ],
            ],

            const SizedBox(height: AppTheme.space4),
            FilledButton.icon(
              onPressed:
                  _submitting || cart.isEmpty ? null : () => _confirm(cart, total),
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_circle),
              label: Text(l.sellConfirm),
            ),
          ],
        ),
      ),
    );
  }

  String _tierLabel(AppLocalizations l, String tier) => switch (tier) {
        'wholesale' => l.customerTierWholesale,
        'vip' => l.customerTierVip,
        _ => l.customerTierRetail,
      };

  Widget _row(String label, String value, {bool bold = false}) {
    final style = bold
        ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}

/// Customer name field with directory suggestions: typing filters the
/// shop's saved customers by name/phone; picking one fills phone too.
/// Typing without picking anything still works exactly like a plain text
/// field (the checkout flow resolves/creates a directory entry by name at
/// finalize time either way — see `_confirm`).
class _CustomerAutocomplete extends ConsumerWidget {
  const _CustomerAutocomplete({
    required this.controller,
    required this.labelText,
    required this.onChanged,
    required this.onSelected,
    required this.onEditedByHand,
    this.helperText,
  });

  final TextEditingController controller;
  final String labelText;
  final String? helperText;
  final VoidCallback onChanged;
  final ValueChanged<Customer> onSelected;
  final VoidCallback onEditedByHand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customersStreamProvider).valueOrNull ?? const [];
    return RawAutocomplete<Customer>(
      textEditingController: controller,
      focusNode: FocusNode(),
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<Customer>.empty();
        return customers.where((c) =>
            c.name.toLowerCase().contains(q) ||
            (c.phone?.contains(q) ?? false));
      },
      displayStringForOption: (c) => c.name,
      onSelected: onSelected,
      fieldViewBuilder: (context, textController, focusNode, onSubmit) {
        return TextField(
          controller: textController,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: labelText,
            helperText: helperText,
          ),
          onChanged: (_) {
            onEditedByHand();
            onChanged();
          },
        );
      },
      optionsViewBuilder: (context, onSelectedOption, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final c in options)
                    ListTile(
                      dense: true,
                      title: Text(c.name),
                      subtitle: (c.phone ?? '').isEmpty ? null : Text(c.phone!),
                      onTap: () => onSelectedOption(c),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    required this.line,
    required this.lineTotal,
    required this.currency,
    required this.onInc,
    required this.onDec,
  });

  final CartLine line;
  final Money lineTotal;
  final String currency;
  final VoidCallback onInc;
  final VoidCallback onDec;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(line.product.name)),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: onDec,
          ),
          Text('${line.qty}'),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline),
            onPressed: onInc,
          ),
          SizedBox(
            width: 90,
            child: Text(
              lineTotal.withSymbol(currency),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscountField extends StatelessWidget {
  const _DiscountField({required this.onChanged});

  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(l.sellDiscount)),
          SizedBox(
            width: 120,
            child: TextField(
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                isDense: true,
                hintText: '0',
              ),
              onChanged: (v) => onChanged(int.tryParse(v.trim()) ?? 0),
            ),
          ),
        ],
      ),
    );
  }
}
