import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../accounts/payment_account_providers.dart';
import '../credit/credit_providers.dart';
import '../customers/customer_picker.dart';
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
  final _customerFocus = FocusNode();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  bool _submitting = false;
  // Seller-controlled, per-sale: reveal the optional customer name/phone fields.
  bool _addCustomer = false;
  // Whether a freshly-*typed* (not picked) name gets saved as a new directory
  // entry, vs just attached to this one invoice. Irrelevant once an existing
  // customer is picked (already in the directory — nothing new to save) and
  // forced on for credit sales (the credit book needs the directory link).
  bool _saveToDirectory = true;
  // Set when a directory customer was picked from the autocomplete; cleared
  // whenever the name is edited by hand so a stale id never gets attached to
  // the wrong typed name.
  String? _selectedCustomerId;
  // The picked customer's outstanding balance *before* this sale, so the
  // seller sees it before confirming (the invoice itself shows the combined
  // total afterward — see InvoiceDetailScreen).
  int _previousBalance = 0;
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
    _customerFocus.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  int get _paidAmount => int.tryParse(_paid.text.trim()) ?? 0;

  /// This customer's outstanding credit-book balance *before* this sale —
  /// 0 if they have none (or aren't a directory customer at all).
  int _outstandingFor(String customerId) {
    for (final c in ref.read(creditCustomersProvider)) {
      if (c.customerId == customerId) return c.outstanding;
    }
    return 0;
  }

  /// Opens a small dialog to set (or clear) a flat-Kyat discount on just
  /// this one cart line — distinct from the order-level discount below,
  /// which still applies on top.
  Future<void> _editLineDiscount(CartLine line) async {
    final l = AppLocalizations.of(context);
    final controller =
        TextEditingController(text: line.discount > 0 ? '${line.discount}' : '');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.sellItemDiscountTitle(line.product.name)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(9),
          ],
          decoration: InputDecoration(labelText: l.sellDiscount),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim()) ?? 0;
              ref
                  .read(cartProvider.notifier)
                  .setLineDiscount(line.product.id, value);
              Navigator.of(dialogContext).pop();
            },
            child: Text(l.commonSave),
          ),
        ],
      ),
    );
    controller.dispose();
  }

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
    final forced = owed > 0 || _method == 'credit';
    if (forced && name.isEmpty) {
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
      final address = _address.text.trim();
      // Prefer the directory entry the seller picked from the autocomplete —
      // already in the directory, nothing new to create. Otherwise, only
      // create a new directory entry for a freshly-typed name if the seller
      // opted in (or it's forced, since the credit book needs the link);
      // declining just attaches the name/phone/address to this one invoice
      // via customerName/customerPhone below, with no directory row.
      final customerId = name.isEmpty
          ? null
          : _selectedCustomerId ??
              (forced || _saveToDirectory
                  ? await ref.read(customerRepositoryProvider).resolveOrCreate(
                        name,
                        phone: phone.isEmpty ? null : phone,
                        address: address.isEmpty ? null : address,
                      )
                  : null);
      final result = await salesRepo.finalizeSale(
        cart: cart,
        paymentMethod: _method,
        paid: paid,
        customerName: name.isEmpty ? null : name,
        customerPhone: phone.isEmpty ? null : phone,
        customerId: customerId,
        staffId: ref.read(activeStaffIdProvider).valueOrNull,
        deviceId: ref.read(deviceIdProvider).valueOrNull,
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
    final accounts = ref.watch(paymentAccountsProvider).valueOrNull ?? const [];
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
                  onDiscountTap: () => _editLineDiscount(line),
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
                for (final m in [...paymentMethodIds(accounts), 'credit'])
                  ChoiceChip(
                    label: Text(paymentLabel(l, m, accounts: accounts)),
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
              inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(9),
          ],
              decoration: InputDecoration(
                labelText:
                    _method == 'credit' ? l.creditPaidNow : l.sellAmountPaid,
                hintText: Money(total).withSymbol(currency),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppTheme.space2),
            // Credit sales get an explicit deposit/balance-due breakdown
            // rather than the generic Owed-or-Change row every other method
            // shares, so a down payment always reads clearly as "this much
            // now, this much still owed" instead of being conflated with an
            // accidental cash-sale shortfall.
            if (_method == 'credit') ...[
              _row(l.creditDeposit, Money(paid).withSymbol(currency)),
              _row(l.creditBalanceDue, Money(owed).withSymbol(currency),
                  bold: true),
            ] else if (owed > 0)
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
              onChanged: forced
                  ? null
                  : (v) => setState(() {
                        _addCustomer = v;
                        // Turning the switch off hides these fields — clear
                        // them too, so leftover typed text can't silently
                        // still get attached to the sale/directory at
                        // confirm time even though the fields are gone.
                        if (!v) {
                          _customer.clear();
                          _phone.clear();
                          _address.clear();
                          _selectedCustomerId = null;
                          _previousBalance = 0;
                          ref.read(cartProvider.notifier).setCustomerTier(null);
                        }
                      }),
            ),

            if (showCustomer) ...[
              CustomerAutocomplete(
                controller: _customer,
                focusNode: _customerFocus,
                labelText: forced
                    ? '${l.creditCustomerName} *'
                    : l.creditCustomerName,
                helperText: forced ? l.creditCustomerRequired : null,
                onChanged: () => setState(() {}),
                onSelected: (c) => setState(() {
                  _selectedCustomerId = c.id;
                  _customer.text = c.name;
                  _phone.text = c.phone ?? '';
                  _address.text = c.address ?? '';
                  _previousBalance = _outstandingFor(c.id);
                  ref
                      .read(cartProvider.notifier)
                      .setCustomerTier(c.tier == 'retail' ? null : c.tier);
                }),
                onEditedByHand: () {
                  _selectedCustomerId = null;
                  _previousBalance = 0;
                  ref.read(cartProvider.notifier).setCustomerTier(null);
                },
              ),
              const SizedBox(height: AppTheme.space2),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: l.customerPhone),
              ),
              const SizedBox(height: AppTheme.space2),
              TextField(
                controller: _address,
                decoration: InputDecoration(labelText: l.customerAddress),
              ),
              // Only meaningful for a freshly-typed name: an already-picked
              // directory customer is already saved, and a forced (credit)
              // sale must save regardless (the credit book needs the link).
              if (!forced && _selectedCustomerId == null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(l.checkoutSaveToDirectory),
                  value: _saveToDirectory,
                  onChanged: (v) =>
                      setState(() => _saveToDirectory = v ?? true),
                ),
              if (_previousBalance > 0)
                Padding(
                  padding: const EdgeInsets.only(top: AppTheme.space2),
                  child: _row(l.creditPreviousBalance,
                      Money(_previousBalance).withSymbol(currency)),
                ),
              if (cart.customerTier != null) ...[
                const SizedBox(height: AppTheme.space2),
                Text(
                  l.checkoutTierPricingApplied(_tierLabel(l, cart.customerTier!)),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary),
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
        ? Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
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
    required this.onDiscountTap,
  });

  final CartLine line;
  final Money lineTotal;
  final String currency;
  final VoidCallback onInc;
  final VoidCallback onDec;
  final VoidCallback onDiscountTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(line.product.name)),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.sell_outlined,
                color: line.discount > 0
                    ? Theme.of(context).colorScheme.primary
                    : null),
            tooltip: AppLocalizations.of(context).sellDiscount,
            onPressed: onDiscountTap,
          ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  lineTotal.withSymbol(currency),
                  textAlign: TextAlign.right,
                ),
                if (line.discount > 0)
                  Text(
                    '-${Money(line.discount).withSymbol(currency)}',
                    textAlign: TextAlign.right,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
              ],
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
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space1),
      child: Row(
        children: [
          Expanded(child: Text(l.sellDiscount)),
          SizedBox(
            width: 120,
            child: TextField(
              keyboardType: TextInputType.number,
              inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(9),
          ],
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
