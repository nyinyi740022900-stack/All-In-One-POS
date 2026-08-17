import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
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
  ///
  /// The controller lives inside [_LineDiscountDialog] rather than here.
  /// `await showDialog(...)` resolves the moment the route is *popped*, not
  /// when its exit animation ends, so disposing a locally-owned controller
  /// on the next line tears it out from under a TextField that is still on
  /// screen — "A TextEditingController was used after being disposed",
  /// followed by a cascade of framework assertions and a red screen over the
  /// checkout sheet. (Observed live on this build from the identical pattern
  /// in `categories_screen.dart:66-89`; the same shape is in
  /// `settings_screen.dart` — see DESIGN_PASS.md.)
  Future<void> _editLineDiscount(CartLine line) async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _LineDiscountDialog(line: line),
    );
    if (value == null || !mounted) return;
    ref.read(cartProvider.notifier).setLineDiscount(line.product.id, value);
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
    // Resolved before any `await`/pop below — this state's `context` may be
    // unmounted by the time the sale finishes (the sheet closes on success).
    final successColor = AppColors.of(context).success;
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

      // The sale is committed as of here — everything below is best-effort
      // convenience (auto-print) and must never surface as "sale failed" or
      // block clearing the cart, since retrying at this point would double
      // the sale, not fix a failure. printSaleReceipt already reports its
      // own outcome via a snackbar and never throws.
      try {
        final config =
            await ref.read(settingsRepositoryProvider).printerConfig();
        if (config.hasPrinter && mounted) {
          final sale = await salesRepo.getSale(result.saleId);
          final items = await salesRepo.saleItems(result.saleId);
          if (mounted) {
            await printSaleReceipt(context, ref, sale: sale, items: items);
          }
        }
      } catch (_) {}

      _confirmed = true;
      ref.read(cartProvider.notifier).clear();
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: successColor, size: 20),
              const SizedBox(width: AppTheme.space2),
              Expanded(child: Text(l.sellCompleted)),
            ],
          ),
        ),
      );
    } catch (e) {
      // Reached only if finalizeSale (or the customer-directory lookup
      // before it) itself threw — nothing was charged, the cart is intact,
      // and it's safe for the cashier to just try again.
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l.sellCheckoutFailed)));
      }
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

    // Keep the sheet clear of the status bar. A full cart grew this sheet to
    // the entire height of its host area, which slid the "Checkout" title
    // under the notch and the drag handle off-screen entirely — it stopped
    // reading as a dismissible sheet at exactly the moment a seller might
    // want to back out of it.
    //
    // Measured off the *incoming* constraints, not the screen: this modal is
    // hosted by the shell's inner navigator, so its box is the body area
    // above the bottom nav bar, not the display. And the top inset comes from
    // the view rather than `MediaQuery.paddingOf`, which the modal route
    // zeroes out.
    return LayoutBuilder(
      builder: (context, constraints) {
        final topInset = MediaQueryData.fromView(View.of(context)).padding.top;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: constraints.maxHeight.isFinite
                ? (constraints.maxHeight - topInset - AppTheme.space2)
                    .clamp(240.0, constraints.maxHeight)
                : double.infinity,
          ),
          child: Padding(
        padding: EdgeInsets.only(
          left: AppTheme.space4,
          right: AppTheme.space4,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppTheme.space4,
        ),
        // Scroll body + pinned action footer, rather than one long scroll with
        // the CTA at the far end of it. With thumbnails the line items are
        // taller, so on a real cart the "Confirm sale" button used to be two
        // screens below the fold — and behind the keyboard as soon as the
        // amount-paid field was focused.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.sellCheckout,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: AppTheme.space2),

                    // Cart lines with qty steppers, hairline-separated — with a
                    // thumbnail on every row they read as distinct records rather
                    // than a run-on block of text.
                    ...cart.lines.asMap().entries.expand((entry) sync* {
                      final line = entry.value;
                      if (entry.key > 0) yield const Divider(height: 1);
                      yield _CartLineTile(
                        line: line,
                        lineTotal: cart.lineTotalFor(line),
                        currency: currency,
                        onDiscountTap: () => _editLineDiscount(line),
                        onInc: () {
                          final ok = ref.read(cartProvider.notifier).increment(
                                line.product.id,
                                maxQty:
                                    trackStock ? stockById[line.product.id] : null,
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
                      );
                    }),
                    const Divider(),

                    SummaryRow(l.sellSubtotal, cart.subtotal.withSymbol(currency)),
                    _DiscountField(
                      onChanged: (v) =>
                          ref.read(cartProvider.notifier).setDiscount(v),
                    ),
                    SummaryRow(l.commonTotal, Money(total).withSymbol(currency), emphasis: true),
                    const SizedBox(height: AppTheme.space4),

                    SectionHeader(title: l.sellPaymentMethod),
                    const SizedBox(height: AppTheme.space1),
                    Wrap(
                      spacing: AppTheme.space2,
                      runSpacing: AppTheme.space2,
                      children: [
                        for (final m in [...paymentMethodIds(accounts), 'credit'])
                          ChoiceChip(
                            avatar: Icon(
                              paymentIcon(m),
                              size: 18,
                              color: _method == m
                                  ? Theme.of(context).colorScheme.onPrimaryContainer
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            // Material paints the selected checkmark *on top of* the
                            // avatar, which turned the chosen method's icon into an
                            // unreadable smudge. The filled `primaryContainer` pill
                            // plus the darkened icon/label already say "selected".
                            showCheckmark: false,
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
                      SummaryRow(l.creditDeposit, Money(paid).withSymbol(currency)),
                      SummaryRow(l.creditBalanceDue, Money(owed).withSymbol(currency),
                          emphasis: true),
                    ] else if (owed > 0)
                      SummaryRow(l.creditOwed, Money(owed).withSymbol(currency), emphasis: true)
                    else
                      SummaryRow(l.sellChange, Money(change).withSymbol(currency)),

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

                    if (showCustomer)
                      Card(
                        margin: const EdgeInsets.only(top: AppTheme.space2),
                        child: Padding(
                          padding: const EdgeInsets.all(AppTheme.space3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
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
                                  ref.read(cartProvider.notifier).setCustomerTier(
                                      c.tier == 'retail' ? null : c.tier);
                                }),
                                onEditedByHand: () {
                                  _selectedCustomerId = null;
                                  _previousBalance = 0;
                                  ref.read(cartProvider.notifier).setCustomerTier(null);
                                },
                              ),
                              const SizedBox(height: AppTheme.space3),
                              TextField(
                                controller: _phone,
                                keyboardType: TextInputType.phone,
                                autofillHints: const [AutofillHints.telephoneNumber],
                                decoration:
                                    InputDecoration(labelText: l.customerPhone),
                              ),
                              const SizedBox(height: AppTheme.space3),
                              TextField(
                                controller: _address,
                                autofillHints: const [
                                  AutofillHints.streetAddressLine1,
                                ],
                                decoration:
                                    InputDecoration(labelText: l.customerAddress),
                              ),
                              // Only meaningful for a freshly-typed name: an
                              // already-picked directory customer is already saved,
                              // and a forced (credit) sale must save regardless (the
                              // credit book needs the link).
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
                                  padding: const EdgeInsets.only(
                                    top: AppTheme.space2,
                                  ),
                                  child: SummaryRow(
                                    l.creditPreviousBalance,
                                    Money(_previousBalance).withSymbol(currency),
                                  ),
                                ),
                              if (cart.customerTier != null) ...[
                                const SizedBox(height: AppTheme.space2),
                                Text(
                                  l.checkoutTierPricingApplied(
                                    _tierLabel(l, cart.customerTier!),
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: AppTheme.space3),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.space3),
              child: FilledButton(
                onPressed: _submitting || cart.isEmpty
                    ? null
                    : () => _confirm(cart, total),
                // Label + amount on one bar, the same shape as the Sell
                // screen's docked checkout button — so the figure the seller is
                // about to charge is on the control they press, not only in the
                // summary they may have scrolled past.
                child: Row(
                  children: [
                    if (_submitting)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(Icons.check_circle, size: 20),
                    const SizedBox(width: AppTheme.space2),
                    Expanded(child: Text(l.sellConfirm, maxLines: 2)),
                    const SizedBox(width: AppTheme.space2),
                    Text(
                      Money(total).withSymbol(currency),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
        );
      },
    );
  }

  String _tierLabel(AppLocalizations l, String tier) => switch (tier) {
        'wholesale' => l.customerTierWholesale,
        'vip' => l.customerTierVip,
        _ => l.customerTierRetail,
      };
}

/// Per-line flat-Kyat discount editor. A `StatefulWidget` purely so the
/// `TextEditingController` is owned by something whose `dispose` runs when
/// the route is actually gone — see `_editLineDiscount`.
class _LineDiscountDialog extends StatefulWidget {
  const _LineDiscountDialog({required this.line});

  final CartLine line;

  @override
  State<_LineDiscountDialog> createState() => _LineDiscountDialogState();
}

class _LineDiscountDialogState extends State<_LineDiscountDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.line.discount > 0 ? '${widget.line.discount}' : '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.sellItemDiscountTitle(widget.line.product.name)),
      content: TextField(
        controller: _controller,
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
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context)
              .pop(int.tryParse(_controller.text.trim()) ?? 0),
          child: Text(l.commonSave),
        ),
      ],
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
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ProductThumb(
            name: line.product.name,
            imageUrl: line.product.imageUrl,
            size: 44,
            radius: AppTheme.radiusSm,
          ),
          const SizedBox(width: AppTheme.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  line.product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                // Unit price, so a wrong line total is traceable without
                // leaving the sheet — and so the row still says something
                // useful when the qty is 1.
                Text(
                  Money(line.product.salePrice).withSymbol(currency),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFeatures: AppTheme.tabularFigures,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.sell_outlined,
                color: line.discount > 0
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant),
            tooltip: l.sellDiscount,
            onPressed: onDiscountTap,
          ),
          // Stepper and money stacked on the trailing edge: the line total is
          // what gets checked against the customer's cash, so it sits on the
          // same right-hand rule as every figure in the summary block below.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StepperButton(
                    icon: Icons.remove,
                    semanticLabel: l.sellDecreaseQty,
                    onPressed: onDec,
                  ),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${line.qty}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontFeatures: AppTheme.tabularFigures),
                    ),
                  ),
                  _StepperButton(
                    icon: Icons.add,
                    semanticLabel: l.sellIncreaseQty,
                    onPressed: onInc,
                  ),
                ],
              ),
              MoneyText(
                lineTotal.withSymbol(currency),
                style: theme.textTheme.titleSmall,
              ),
              if (line.discount > 0)
                MoneyText(
                  '-${Money(line.discount).withSymbol(currency)}',
                  style: theme.textTheme.bodySmall,
                  color: theme.colorScheme.error,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Square 40dp stepper button with a real tonal surface behind it, rather
/// than a bare icon floating on the sheet — a qty stepper is aimed at with a
/// thumb, at speed, while a customer waits.
class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Icon(icon, size: 18, color: scheme.onSurface),
            ),
          ),
        ),
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
