import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/thousands_formatter.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../core/widgets/numeric_keypad.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import '../accounts/payment_account_providers.dart';
import '../credit/credit_providers.dart';
import '../customers/customer_picker.dart';
import '../customers/customer_providers.dart';
import '../inventory/inventory_providers.dart';
import '../license/license_providers.dart';
import '../../data/repositories/sales_repository.dart' show PaymentEntry;
import '../printing/print_action.dart';
import '../printing/printing_providers.dart';
import '../staff/staff_providers.dart';
import 'cart.dart';
import 'amount_pad.dart';
import 'cash_tender.dart';
import 'payment_labels.dart';
import 'sales_providers.dart';
import 'sell_feedback.dart';
import 'split_payment_dialog.dart';

class CheckoutSheet extends ConsumerStatefulWidget {
  const CheckoutSheet({super.key});

  @override
  ConsumerState<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends ConsumerState<CheckoutSheet> {
  String _method = 'cash';
  // Set once the split-payment dialog is confirmed; null means either
  // "not split" or "split chip picked but the dialog was dismissed without
  // completing" — the latter is treated as invalid (Confirm blocked) rather
  // than silently falling back to a single method.
  List<PaymentEntry>? _splitPayments;
  final _paid = TextEditingController();
  final _paidFieldKey = GlobalKey();
  final _customer = TextEditingController();
  final _customerFocus = FocusNode();
  final _phone = TextEditingController();
  final _phoneFocus = FocusNode();
  final _address = TextEditingController();
  final _addressFocus = FocusNode();
  bool _submitting = false;
  // Seller-controlled, per-sale: reveal the optional customer name/phone fields.
  bool _addCustomer = false;
  // Latches the customer section open once the sale *needs* it (credit
  // method, or a shortfall) — but only while the seller is NOT mid-amount-
  // entry. Without the latch, typing a partial amount on the pad flipped
  // `forced` mid-keystroke: the card expanded ABOVE the amount field, the
  // scroll jumped, and the digits being typed scrolled out of sight (owner
  // report). While typing, the collapsed row's attention tone still signals
  // the requirement, and Confirm blocks with the name-required message;
  // the card expands as soon as they tap the row or finish the amount
  // before the requirement arose.
  bool _customerSectionLatched = false;
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
  // Cart lines collapse to a one-row summary ("3 items … total") so a simple
  // cash sale reads top-to-bottom without scrolling; tap to expand and edit.
  // Lines start EXPANDED — a cashier mid-scan needs to see what's on the
  // ticket without tapping the summary row first (owner request). Still
  // collapsible for the quick cash-sale glance.
  bool _linesExpanded = true;
  // The big-button pad under the amount-paid field. The OS keyboard is gone
  // from this field entirely — its viewport jump mid-checkout was the very
  // thing that used to push the confirm button off-screen.
  bool _padVisible = false;
  // Staff mode: once the owner PIN has been verified this session, per-line
  // and order-level discounts stay open for the rest of the sheet's life.
  bool _discountUnlocked = false;
  // Non-null after a committed sale — swaps the whole sheet for the success
  // panel, whose job is to keep the change-due figure on screen while the
  // cashier counts it out (the old flow popped instantly and the figure
  // vanished at the exact moment it was needed).
  _SaleSuccess? _success;

  @override
  void initState() {
    super.initState();
    // Any customer field taking focus summons the OS keyboard, so the
    // amount pad must get out of the way — otherwise BOTH keyboards stack
    // and the field being typed into is buried between them (owner report:
    // tapping into "Customer name" left the numeric pad on screen).
    for (final node in [_customerFocus, _phoneFocus, _addressFocus]) {
      node.addListener(() {
        if (node.hasFocus && _padVisible && mounted) {
          setState(() => _padVisible = false);
        }
      });
    }
  }

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
    _phoneFocus.dispose();
    _address.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  int get _paidAmount => parseThousands(_paid.text);

  /// This customer's outstanding credit-book balance *before* this sale —
  /// 0 if they have none (or aren't a directory customer at all).
  int _outstandingFor(String customerId) {
    for (final c in ref.read(creditCustomersProvider)) {
      if (c.customerId == customerId) return c.outstanding;
    }
    return 0;
  }

  /// Amount tendered. Empty field means "paid in full" for a normal method, or
  /// "nothing down" for the credit method. A split sale's entries are
  /// dialog-validated to already sum to the total, so this just re-sums them
  /// (0 while the split hasn't been configured yet, which correctly keeps
  /// Confirm blocked via the same `owed > 0` shortfall path every other
  /// under-paid method already uses).
  int _resolvePaid(int total) {
    if (_method == 'split') {
      return _splitPayments?.fold<int>(0, (a, e) => a + e.amount) ?? 0;
    }
    if (_paid.text.trim().isEmpty) return _method == 'credit' ? 0 : total;
    return _paidAmount;
  }

  /// Exact chip: keep the field empty so paid-in-full tracks a live cart
  /// total (qty/discount changes). Credit is the exception — empty means
  /// zero down, so Exact has to write the number.
  void _applyTenderExact(int total) {
    if (_method == 'credit') {
      _setPaidDigits('$total');
    } else {
      _setPaidDigits('');
    }
    setState(() {});
  }

  /// Handles a payment-method chip tap. `'split'` opens the split-payment
  /// dialog instead of just flipping `_method` like every other chip —
  /// confirming it is what actually switches `_method` to `'split'`, so
  /// cancelling leaves the previously-selected method in place. Tapping the
  /// already-selected split chip again reopens the dialog pre-filled, for
  /// editing the split.
  Future<void> _selectMethod(String m, int total) async {
    if (m != 'split') {
      setState(() {
        _method = m;
        // Picking Credit is an explicit "this sale needs a customer" signal
        // — and unlike a shortfall typed digit-by-digit, it's a deliberate
        // tap, not a transient mid-keystroke state. Close the pad here so
        // the `forced && !_padVisible` latch below fires on this very build
        // and the customer card opens immediately, instead of waiting for
        // the seller to dismiss the pad themselves (owner report: "Credit
        // amount နဲ့လဲ add customer မပေါ်ပါ").
        if (m == 'credit') _padVisible = false;
      });
      return;
    }
    final accounts = ref.read(paymentAccountsProvider).valueOrNull ?? const [];
    final result = await showSplitPaymentDialog(
      context,
      total: total,
      methodIds: paymentMethodIds(accounts),
      accounts: accounts,
      initial: _splitPayments,
    );
    if (result == null || !mounted) return;
    setState(() {
      _method = 'split';
      _splitPayments = result;
    });
  }

  void _applyTenderAmount(int kyat) {
    // setState is REQUIRED here: the pad path re-renders via _padDigit's own
    // setState, but chip writes only notified the TextField — Change/Owed
    // rows kept showing stale zeros until the next unrelated rebuild
    // (owner report: tapping 3,000/5,000/10,000 never showed the change).
    setState(() => _setPaidDigits('$kyat'));
  }

  /// Writes [digits] into the paid field, grouped with thousands separators
  /// exactly as if typed — programmatic writes bypass input formatters, so
  /// chip values would otherwise display ungrouped next to grouped typing.
  void _setPaidDigits(String digits) {
    final text = ThousandsSeparatorInputFormatter.formatThousandsText(digits);
    _paid.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// Scrolls the amount-paid field into view. Runs when the pad opens and
  /// again after every pad keystroke: anything that grows the scroll content
  /// above the field (expanded cart lines, the customer card, new summary
  /// rows) otherwise pushes the digits being typed off-screen — the seller
  /// ends up keying blind (owner report).
  void _ensurePaidFieldVisible() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final ctx = _paidFieldKey.currentContext;
      if (ctx != null && mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: AppTheme.motionMedium,
          alignment: 0.1,
        );
      }
    });
  }

  void _padDigit(String d) {
    final digits = ThousandsSeparatorInputFormatter.digitsOf(_paid.text);
    final next = digits + d;
    // 10 digits ≈ up to 9,999,999,999 Ks — far past any retail ticket.
    if (next.length > 10) return;
    _setPaidDigits(next);
    setState(() {});
    _ensurePaidFieldVisible();
  }

  void _padBackspace() {
    final digits = ThousandsSeparatorInputFormatter.digitsOf(_paid.text);
    if (digits.isNotEmpty) {
      _setPaidDigits(digits.substring(0, digits.length - 1));
    }
    setState(() {});
    _ensurePaidFieldVisible();
  }

  /// Discounts are an owner capability. Staff mode has to clear a gate first
  /// — the device's owner PIN (no PIN configured = allowed through, matching
  /// `StaffController.switchRole`'s documented behavior). One unlock covers
  /// every discount edit in this sheet.
  Future<bool> _ensureDiscountAllowed() async {
    if (ref.read(isEffectiveOwnerProvider) || _discountUnlocked) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _OwnerPinDialog(
        verify: (pin) =>
            ref.read(staffControllerProvider).verifyOwnerPin(pin),
      ),
    );
    if (!mounted) return false;
    if (ok == true) _discountUnlocked = true;
    return ok == true;
  }

  /// Order-level flat-Kyat discount editor — a big-button pad with quick
  /// percentage chips, replacing the old 120pt inline TextField that was
  /// both a tiny target and keyboard-bound.
  Future<void> _editOrderDiscount(int subtotal) async {
    if (!await _ensureDiscountAllowed()) return;
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _AmountPadDialog(
        title: l.sellDiscount,
        currency: l.currencySymbol,
        initial: ref.read(cartProvider).discount,
        percentBase: subtotal,
      ),
    );
    if (value == null || !mounted) return;
    ref.read(cartProvider.notifier).setDiscount(value);
  }

  /// Per-line flat-Kyat discount editor — same pad dialog, percentage base
  /// is just this line.
  Future<void> _editLineDiscount(CartLine line) async {
    if (!await _ensureDiscountAllowed()) return;
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    final cart = ref.read(cartProvider);
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _AmountPadDialog(
        title: l.sellItemDiscountTitle(line.product.name),
        currency: l.currencySymbol,
        initial: line.discount,
        percentBase:
            resolveUnitPrice(line.product, cart.customerTier) * line.qty,
      ),
    );
    if (value == null || !mounted) return;
    ref.read(cartProvider.notifier).setLineDiscount(line.product.id, value);
  }

  Future<void> _confirm(CartState cart, int total) async {
    final l = AppLocalizations.of(context);

    // `LicenseState` starts as loading + `none`, so `canSell` is false until
    // the cache is read. Wait rather than flash the "not set up" snackbar.
    await ref.read(licenseControllerProvider.notifier).load();
    if (!mounted) return;

    // No license at all (pre-onboarding) — a lapsed paid plan still sells
    // (auto-downgrade to Free). Do not lock the till behind a read-only banner.
    if (!ref.read(licenseControllerProvider).canSell) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.licenseReadOnly)));
      return;
    }

    // Split payment picked but the dialog was never completed — nothing to
    // charge. Distinct from the credit-shortfall message below since this
    // has nothing to do with billing a customer.
    if (_method == 'split' && _splitPayments == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.splitPaymentSetUp)));
      return;
    }

    final paid = _resolvePaid(total);
    final owed = total - paid;
    final name = _customer.text.trim();
    // A shortfall is booked as credit, and the credit method is always credit —
    // both need a customer name to bill. Phone stays optional. A split sale
    // never has a shortfall (the dialog enforces exact-sum-to-total), so it
    // never reaches this branch once configured.
    final forced = owed > 0 || _method == 'credit';
    if (forced && name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.creditCustomerRequired)));
      return;
    }

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    // Captured before any await: the cart notifier belongs to the provider
    // container, not this widget, so it stays valid (and the cart still gets
    // cleared) even if the sheet is somehow dismissed mid-commit — belt and
    // braces for the PopScope guard above.
    final cartNotifier = ref.read(cartProvider.notifier);
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
                    ? await ref
                          .read(customerRepositoryProvider)
                          .resolveOrCreate(
                            name,
                            phone: phone.isEmpty ? null : phone,
                            address: address.isEmpty ? null : address,
                          )
                    : null);
      final result = await salesRepo.finalizeSale(
        cart: cart,
        paymentMethod: _method == 'split' ? null : _method,
        paid: _method == 'split' ? null : paid,
        payments: _method == 'split' ? _splitPayments : null,
        customerName: name.isEmpty ? null : name,
        customerPhone: phone.isEmpty ? null : phone,
        customerId: customerId,
        staffId: ref.read(activeStaffIdProvider).valueOrNull,
        deviceId: ref.read(deviceIdProvider).valueOrNull,
        trackStock: ref.read(trackStockProvider).valueOrNull ?? true,
      );

      // The sale is committed as of here — everything below is best-effort
      // convenience (auto-print) and must never surface as "sale failed" or
      // block showing the success panel. printSaleReceipt already reports
      // its own outcome via a snackbar and never throws.
      //
      // Receipt data is fetched *before* the success panel appears (local
      // reads — milliseconds), so a cashier who taps Done instantly doesn't
      // cancel their own receipt; the print itself then runs unawaited while
      // the change figure is on screen. The old flow awaited the whole print
      // before closing, leaving the till spinning on a slow printer for a
      // sale that had already committed.
      Sale? printSale;
      List<SaleItem>? printItems;
      try {
        final config = await ref
            .read(settingsRepositoryProvider)
            .printerConfig();
        if (config.hasPrinter && mounted) {
          printSale = await salesRepo.getSale(result.saleId);
          printItems = await salesRepo.saleItems(result.saleId);
        }
      } catch (_) {}

      _confirmed = true;
      cartNotifier.clear();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _submitting = false;
        _success = _SaleSuccess(
          total: total,
          paid: paid,
          change: paid > total ? paid - total : 0,
          owed: total - paid > 0 ? total - paid : 0,
          isCredit: _method == 'credit',
        );
      });
      if (printSale != null && printItems != null) {
        unawaited(
          printSaleReceipt(context, ref, sale: printSale, items: printItems),
        );
      }
    } catch (e) {
      // Reached only if finalizeSale (or the customer-directory lookup
      // before it) itself threw — nothing was charged, the cart is intact,
      // and it's safe for the cashier to just try again.
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l.sellCheckoutFailed)));
      }
    } finally {
      if (mounted && _success == null) setState(() => _submitting = false);
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
    // Audit M3: this map used to be rebuilt inside every build — i.e. on
    // EVERY keypad digit tap — by scanning the whole product stream. It now
    // lives in stockByIdProvider, which only recomputes when products do.
    final stockById = ref.watch(stockByIdProvider);
    final total = cart.total.kyat;
    final paid = _resolvePaid(total);
    final change = paid > total ? paid - total : 0;
    final owed = total - paid > 0 ? total - paid : 0;
    // Credit / any shortfall forces the customer fields (name is then
    // required) — except an unfinished split, whose transient "owed" is
    // just "the dialog hasn't been completed yet", not a credit shortfall.
    final forced =
        _method == 'credit' || (owed > 0 && _method != 'split');
    // Latch the section open only while the pad isn't actively being typed
    // into — see [_customerSectionLatched]. Monotonic (never resets
    // mid-sheet), and read right after assignment so this build already
    // reflects it. Deliberately keyed on `_padVisible` alone, NOT on
    // `_paid.text` being non-empty: gating on the text too used to block
    // this from EVER latching once any digit had been typed (the field
    // never re-empties itself just because the pad closed), so a shortfall
    // amount typed and confirmed left "Add customer" permanently stuck
    // collapsed — the seller had to scroll up and tap it open by hand every
    // time (owner report). Gating on `_padVisible` still avoids yanking the
    // section into view mid-keystroke (typing "2" of "20000" already reads
    // as a huge shortfall), but correctly latches the instant they finish
    // and close the pad.
    if (forced && !_padVisible) _customerSectionLatched = true;
    final showCustomer = _addCustomer || _customerSectionLatched;

    // A committed sale replaces the whole sheet: the one figure the cashier
    // still needs — change due, or the balance being booked as credit — stays
    // up until they tap Done, instead of vanishing with the sheet.
    final success = _success;
    if (success != null) {
      return _SuccessBody(success: success, onDone: () => Navigator.of(context).pop());
    }

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
    //
    // While the sale is committing the sheet must not be dismissible —
    // backing out mid-submit (barrier tap or drag) used to dispose the State
    // between awaits, leaving the sale committed but the cart un-cleared and
    // no success panel: it reads to the cashier as "it didn't go through"
    // and invites a double ring. PopScope blocks barrier taps AND drags.
    return PopScope(
      canPop: !_submitting,
      child: LayoutBuilder(
      builder: (context, constraints) {
        final topInset = MediaQueryData.fromView(View.of(context)).padding.top;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: constraints.maxHeight.isFinite
                ? (constraints.maxHeight - topInset - AppTheme.space2).clamp(
                    240.0,
                    constraints.maxHeight,
                  )
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
                  // Drag-to-dismiss the amount pad, the same convention iOS
                  // lists use for the OS keyboard
                  // (ScrollViewKeyboardDismissBehavior.onDrag). The pad is
                  // pinned outside this scroll so it can never scroll away
                  // on its own — without this it just sat there occupying
                  // half the sheet while the seller scrolled up to the
                  // customer fields, reading as if it were "following" them
                  // (owner report).
                  //
                  // Gated on `dragDetails != null` — i.e. a real finger drag.
                  // `_ensurePaidFieldVisible()` fires a PROGRAMMATIC
                  // `Scrollable.ensureVisible` after EVERY pad keystroke, and
                  // dismissing on that would close the pad on the first digit
                  // typed.
                  child: NotificationListener<ScrollStartNotification>(
                    onNotification: (n) {
                      if (n.dragDetails != null && _padVisible) {
                        setState(() => _padVisible = false);
                      }
                      return false;
                    },
                    child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.sellCheckout,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppTheme.space1),

                        // Customer first — the row a credit/partial sale needs is
                        // the one that used to sit at the very bottom of the
                        // scroll, past every field. Collapsed it shows who's on
                        // the ticket (and their outstanding balance); tap to
                        // expand the name/phone/address card.
                        _customerSection(context, l, forced, showCustomer),
                        // The expanded card lives DIRECTLY under its row — it
                        // used to render at the very bottom of the scroll,
                        // past every payment field, so tapping "Add customer"
                        // appeared to do nothing until the seller dragged the
                        // whole sheet up (owner report).
                        if (showCustomer)
                          _customerCard(context, l, cart, forced),
                        const SizedBox(height: AppTheme.space2),

                        // Cart lines collapse to a one-row summary so a simple
                        // cash sale reads top-to-bottom without scrolling; tap
                        // to expand and adjust quantities.
                        InkWell(
                          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                          onTap: () =>
                              setState(() => _linesExpanded = !_linesExpanded),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppTheme.space2,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  l.checkoutItemsCount(cart.itemCount),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                                const Spacer(),
                                MoneyText(
                                  cart.total.withSymbol(currency),
                                  style: Theme.of(context).textTheme.titleMedium,
                                  emphasis: true,
                                ),
                                AnimatedRotation(
                                  turns: _linesExpanded ? 0.5 : 0,
                                  duration: AppTheme.motionFast,
                                  child: Icon(
                                    Icons.expand_more,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        AnimatedCrossFade(
                          duration: AppTheme.motionMedium,
                          sizeCurve: AppTheme.curveStandard,
                          crossFadeState: _linesExpanded
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          // Cart lines with qty steppers, hairline-separated —
                          // with a thumbnail on every row they read as distinct
                          // records rather than a run-on block of text.
                          secondChild: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ...cart.lines.asMap().entries.expand((entry) sync* {
                                final line = entry.value;
                                if (entry.key > 0) yield const Divider(height: 1);
                                yield _CartLineTile(
                                  line: line,
                                  lineTotal: cart.lineTotalFor(line),
                                  currency: currency,
                                  onDiscountTap: () => _editLineDiscount(line),
                                  onInc: () {
                                    HapticFeedback.selectionClick();
                                    final ok = ref
                                        .read(cartProvider.notifier)
                                        .increment(
                                          line.product.id,
                                          maxQty: trackStock
                                              ? stockById[line.product.id]
                                              : null,
                                        );
                                    if (!ok) {
                                      showStockCapSnackBar(
                                        context,
                                        l,
                                        stockById[line.product.id] ?? 0,
                                      );
                                    }
                                  },
                                  onDec: () {
                                    HapticFeedback.selectionClick();
                                    ref
                                        .read(cartProvider.notifier)
                                        .decrement(line.product.id);
                                  },
                                );
                              }),
                            ],
                          ),
                          firstChild: const SizedBox(width: double.infinity),
                        ),
                        const Divider(),

                        SummaryRow(
                          l.sellSubtotal,
                          cart.subtotal.withSymbol(currency),
                        ),
                        _DiscountRow(
                          discount: cart.discount,
                          currency: currency,
                          onTap: () => _editOrderDiscount(cart.subtotal.kyat),
                        ),
                        SummaryRow(
                          l.commonTotal,
                          Money(total).withSymbol(currency),
                          emphasis: true,
                        ),
                        const SizedBox(height: AppTheme.space4),

                        SectionHeader(title: l.sellPaymentMethod),
                        const SizedBox(height: AppTheme.space1),
                        Wrap(
                          spacing: AppTheme.space2,
                          runSpacing: AppTheme.space2,
                          children: [
                            for (final m in [
                              ...paymentMethodIds(accounts),
                              'split',
                              'credit',
                            ])
                              ChoiceChip(
                                avatar: Icon(
                                  paymentIcon(m),
                                  size: 18,
                                  color: _method == m
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.onPrimaryContainer
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                ),
                                // Material paints the selected checkmark *on top of* the
                                // avatar, which turned the chosen method's icon into an
                                // unreadable smudge. The filled `primaryContainer` pill
                                // plus the darkened icon/label already say "selected".
                                showCheckmark: false,
                                // Same generous padding as CategoryFilterBar — a
                                // payment method is aimed at with a thumb while a
                                // customer waits, and the default chip height sat
                                // under the 48dp target.
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppTheme.space3,
                                  vertical: AppTheme.space2,
                                ),
                                label: Text(
                                  paymentLabel(l, m, accounts: accounts),
                                ),
                                selected: _method == m,
                                onSelected: (_) => _selectMethod(m, total),
                              ),
                          ],
                        ),

                        const SizedBox(height: AppTheme.space3),
                        if (_method == 'split')
                          _SplitPaymentSummary(
                            entries: _splitPayments,
                            currency: currency,
                            accounts: accounts,
                            onEdit: () => _selectMethod('split', total),
                          )
                        else ...[
                          // Amount paid — shown for every method. Leave blank to pay
                          // in full. Read-only: taps toggle the big-button pad below
                          // instead of summoning the OS keyboard (whose viewport jump
                          // used to push this sheet's footer around mid-sale).
                          TextField(
                            key: _paidFieldKey,
                            controller: _paid,
                            readOnly: true,
                            showCursor: true,
                            onTap: () {
                              setState(() => _padVisible = !_padVisible);
                              if (_padVisible) {
                                // The pinned pad grows the sheet; make sure the
                                // field it edits is on-screen, not scrolled off
                                // under an expanded cart.
                                _ensurePaidFieldVisible();
                              }
                            },
                            decoration: InputDecoration(
                              labelText: _method == 'credit'
                                  ? l.creditPaidNow
                                  : l.sellAmountPaid,
                              hintText: Money(total).withSymbol(currency),
                              suffixIcon: Icon(
                                _padVisible
                                    ? Icons.keyboard_hide_outlined
                                    : Icons.dialpad_outlined,
                              ),
                            ),
                          ),
                          if (total > 0) ...[
                            const SizedBox(height: AppTheme.space2),
                            _TenderChips(
                              suggestions: cashTenderSuggestions(total),
                              total: total,
                              paidAmount: _paidAmount,
                              fieldEmpty: _paid.text.trim().isEmpty,
                              isCredit: _method == 'credit',
                              currency: currency,
                              exactLabel: l.sellTenderExact,
                              onExact: () => _applyTenderExact(total),
                              onAmount: _applyTenderAmount,
                            ),
                          ],
                          // Credit sales get an explicit deposit/balance-due breakdown
                          // rather than the generic Owed-or-Change row every other method
                          // shares, so a down payment always reads clearly as "this much
                          // now, this much still owed" instead of being conflated with an
                          // accidental cash-sale shortfall.
                          if (_method == 'credit') ...[
                            SummaryRow(
                              l.creditDeposit,
                              Money(paid).withSymbol(currency),
                            ),
                            SummaryRow(
                              l.creditBalanceDue,
                              Money(owed).withSymbol(currency),
                              emphasis: true,
                            ),
                          ] else if (owed > 0) ...[
                            SummaryRow(
                              l.creditOwed,
                              Money(owed).withSymbol(currency),
                              emphasis: true,
                            ),
                            // A typed shortfall silently becomes credit at confirm
                            // time — say so *here*, while the cashier can still fix
                            // the number, instead of letting the "customer name
                            // required" error be the first hint at the very end.
                            if (_paid.text.trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: AppTheme.space1,
                                ),
                                child: _HintBanner(
                                  icon: Icons.info_outline,
                                  text: l.checkoutShortfallCreditHint,
                                ),
                              ),
                          ] else
                            SummaryRow(
                              l.sellChange,
                              Money(change).withSymbol(currency),
                            ),
                        ],

                        const SizedBox(height: AppTheme.space3),
                      ],
                    ),
                  ),
                  ),
                ),
                // The numeric pad is PINNED above the footer, outside the
                // scroll — opening it used to push it below the fold of a
                // full cart, so the seller had to drag the sheet down to see
                // what they were typing into (owner report).
                if (_padVisible)
                  Padding(
                    padding: const EdgeInsets.only(top: AppTheme.space2),
                    child: NumericKeypad(
                      onDigit: _padDigit,
                      onBackspace: _padBackspace,
                    ),
                  ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.only(top: AppTheme.space3),
                  child: FilledButton(
                    onPressed:
                        _submitting ||
                            cart.isEmpty ||
                            (_method == 'split' && _splitPayments == null)
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
                          Money(_method == 'credit' ? paid : total)
                              .withSymbol(currency),
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
      ),
    );
  }

  String _tierLabel(AppLocalizations l, String tier) => switch (tier) {
    'wholesale' => l.customerTierWholesale,
    'vip' => l.customerTierVip,
    _ => l.customerTierRetail,
  };

  /// The customer row, pinned at the *top* of the sheet. Collapsed it already
  /// answers "who is this ticket for?" — picked name, or their outstanding
  /// credit balance — so a seller can confirm at a glance without expanding.
  Widget _customerSection(
    BuildContext context,
    AppLocalizations l,
    bool forced,
    bool showCustomer,
  ) {
    final colors = AppColors.of(context);
    final name = _customer.text.trim();
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      onTap: () => setState(() {
        final v = !showCustomer;
        _addCustomer = v;
        // Opening this section makes room for it by collapsing the numeric
        // pad — the pad is pinned OUTSIDE the scroll (see its own comment
        // below), so it kept eating the sheet's height and never closed on
        // its own, making "Add customer" feel like it was chasing the
        // scroll rather than opening (owner report).
        if (v) _padVisible = false;
        // Collapsing hides these fields — clear them too, so leftover typed
        // text can't silently still get attached to the sale/directory at
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.space2),
        child: Row(
          children: [
            IconAvatar(
              icon: name.isEmpty
                  ? Icons.person_add_alt_1
                  : Icons.person_outline,
              tone: forced && name.isEmpty ? StatusTone.attention : null,
            ),
            const SizedBox(width: AppTheme.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name.isEmpty ? l.checkoutAddCustomer : name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (forced && name.isEmpty)
                    Text(
                      l.creditCustomerRequired,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.warning,
                      ),
                    )
                  else if (_previousBalance > 0)
                    Text(
                      '${l.creditPreviousBalance} · '
                      '${Money(_previousBalance).withSymbol(l.currencySymbol)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFeatures: AppTheme.tabularFigures,
                      ),
                    ),
                ],
              ),
            ),
            AnimatedRotation(
              turns: showCustomer ? 0.5 : 0,
              duration: AppTheme.motionFast,
              child: Icon(
                Icons.expand_more,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The expanded customer card (name autocomplete / phone / address /
  /// save-to-directory), revealed under the row above.
  Widget _customerCard(
    BuildContext context,
    AppLocalizations l,
    CartState cart,
    bool forced,
  ) {
    return Card(
      margin: const EdgeInsets.only(top: AppTheme.space1),
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
            const SizedBox(height: AppTheme.space3),
            TextField(
              controller: _phone,
              focusNode: _phoneFocus,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: InputDecoration(labelText: l.customerPhone),
            ),
            const SizedBox(height: AppTheme.space3),
            TextField(
              controller: _address,
              focusNode: _addressFocus,
              autofillHints: const [AutofillHints.streetAddressLine1],
              decoration: InputDecoration(labelText: l.customerAddress),
            ),
            // Only meaningful for a freshly-typed name: an already-picked
            // directory customer is already saved, and a forced (credit) sale
            // must save regardless (the credit book needs the link).
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
            if (cart.customerTier != null) ...[
              const SizedBox(height: AppTheme.space2),
              Text(
                l.checkoutTierPricingApplied(
                  _tierLabel(l, cart.customerTier!),
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Quick-tender chips under the amount-paid field. Exact plus the next few
/// kyat-note round-ups — same ChoiceChip language as the payment-method row
/// above, so a cashier does not have to learn a second control.
class _TenderChips extends StatelessWidget {
  const _TenderChips({
    required this.suggestions,
    required this.total,
    required this.paidAmount,
    required this.fieldEmpty,
    required this.isCredit,
    required this.currency,
    required this.exactLabel,
    required this.onExact,
    required this.onAmount,
  });

  final List<int> suggestions;
  final int total;
  final int paidAmount;
  final bool fieldEmpty;
  final bool isCredit;
  final String currency;
  final String exactLabel;
  final VoidCallback onExact;
  final ValueChanged<int> onAmount;

  bool get _exactSelected => isCredit
      ? !fieldEmpty && paidAmount == total
      : fieldEmpty || paidAmount == total;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    final extras = suggestions.skip(1);
    return Wrap(
      spacing: AppTheme.space2,
      runSpacing: AppTheme.space2,
      children: [
        ChoiceChip(
          showCheckmark: false,
          // Same generous padding as the payment-method chips — tender
          // amounts are tapped at speed with a customer waiting.
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.space3,
            vertical: AppTheme.space2,
          ),
          label: Text(exactLabel),
          selected: _exactSelected,
          onSelected: (_) => onExact(),
        ),
        for (final amount in extras)
          ChoiceChip(
            showCheckmark: false,
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.space3,
              vertical: AppTheme.space2,
            ),
            label: Text(
              Money(amount).withSymbol(currency),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontFeatures: AppTheme.tabularFigures,
              ),
            ),
            selected: !fieldEmpty && paidAmount == amount,
            onSelected: (on) => on ? onAmount(amount) : onExact(),
          ),
      ],
    );
  }
}

/// Flat-Kyat amount editor on the big-button pad — used for both the
/// order-level discount and per-line discounts. No text field at all: the
/// value lives as an int, displayed grouped, edited by [NumericKeypad] with
/// optional quick-percentage chips computed off [percentBase].
///
/// Replaces the old system-keyboard TextField dialogs, which were both a
/// small target and a viewport jump inside a dialog.
class _AmountPadDialog extends StatefulWidget {
  const _AmountPadDialog({
    required this.title,
    required this.currency,
    this.initial = 0,
    this.percentBase,
  });

  final String title;
  final String currency;
  final int initial;

  /// When set, offers 5/10/15/20% quick chips of this base amount.
  final int? percentBase;

  @override
  State<_AmountPadDialog> createState() => _AmountPadDialogState();
}

class _AmountPadDialogState extends State<_AmountPadDialog> {
  late int _value = widget.initial;

  static const _percents = [5, 10, 15, 20];

  void _digit(String d) {
    setState(() {
      _value = appendPadDigits(_value, d);
    });
  }

  void _backspace() => setState(() => _value ~/= 10);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.space3,
              vertical: AppTheme.space3,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: MoneyText(
              Money(_value).withSymbol(widget.currency),
              style: Theme.of(context).textTheme.headlineSmall,
              emphasis: true,
            ),
          ),
          if (widget.percentBase != null && widget.percentBase! > 0) ...[
            const SizedBox(height: AppTheme.space2),
            Wrap(
              spacing: AppTheme.space2,
              runSpacing: AppTheme.space1,
              children: [
                for (final p in _percents)
                  ChoiceChip(
                    label: Text('$p%'),
                    selected: _value == widget.percentBase! * p ~/ 100,
                    onSelected: (_) => setState(
                      () => _value = widget.percentBase! * p ~/ 100,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppTheme.space2),
          NumericKeypad(onDigit: _digit, onBackspace: _backspace, keyHeight: 48),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _value = 0),
          child: Text(l.commonClear),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_value),
          child: Text(l.commonSave),
        ),
      ],
    );
  }
}

/// The staff-mode gate for discounts: enter the device's owner PIN to unlock
/// discount editing for this sheet. No PIN configured = allowed through
/// (same contract as `StaffController.switchRole`). Wrong PINs count toward
/// the controller's own lockout — this dialog just surfaces the failure.
class _OwnerPinDialog extends StatefulWidget {
  const _OwnerPinDialog({required this.verify});

  final Future<bool> Function(String pin) verify;

  @override
  State<_OwnerPinDialog> createState() => _OwnerPinDialogState();
}

class _OwnerPinDialogState extends State<_OwnerPinDialog> {
  final _pin = TextEditingController();
  bool _checking = false;
  bool _wrong = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _checking = true;
      _wrong = false;
    });
    final ok = await widget.verify(_pin.text.trim());
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _checking = false;
        _wrong = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.checkoutOwnerPinTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.checkoutOwnerPinExplain,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _pin,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              counterText: '',
              errorText: _wrong ? l.checkoutOwnerPinWrong : null,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: _checking || _pin.text.trim().isEmpty ? null : _submit,
          child: Text(l.commonOk),
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
            icon: Icon(
              Icons.sell_outlined,
              color: line.discount > 0
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
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
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFeatures: AppTheme.tabularFigures,
                      ),
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
            child: Center(child: Icon(icon, size: 18, color: scheme.onSurface)),
          ),
        ),
      ),
    );
  }
}

/// The order-level discount as a tappable summary row — full-width target,
/// opens the pad dialog. Replaces the old 120pt inline TextField (a tiny
/// target wedged between money rows, bound to the OS keyboard).
class _DiscountRow extends StatelessWidget {
  const _DiscountRow({
    required this.discount,
    required this.currency,
    required this.onTap,
  });

  final int discount;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.space1),
        child: Row(
          children: [
            Expanded(child: Text(l.sellDiscount)),
            MoneyText(
              Money(discount).withSymbol(currency),
              color: discount > 0 ? scheme.primary : null,
            ),
            const SizedBox(width: AppTheme.space1),
            Icon(
              Icons.edit_outlined,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Snapshot of the committed sale, captured at confirm time (the cart is
/// cleared the moment after — these figures must not read live state).
class _SaleSuccess {
  const _SaleSuccess({
    required this.total,
    required this.paid,
    required this.change,
    required this.owed,
    required this.isCredit,
  });

  final int total;
  final int paid;
  final int change;
  final int owed;
  final bool isCredit;
}

/// The post-sale panel. Its whole reason to exist: the change-due figure is
/// needed *while counting money into the customer's hand*, and the old flow
/// popped the sheet — figure and all — the instant the sale committed.
class _SuccessBody extends StatelessWidget {
  const _SuccessBody({required this.success, required this.onDone});

  final _SaleSuccess success;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final currency = l.currencySymbol;
    String fmt(int v) => Money(v).withSymbol(currency);

    // The one figure the cashier acts on next: change to hand over, the
    // credit balance just booked, or the total collected.
    final headline = success.isCredit
        ? (label: l.creditBalanceDue, value: success.owed)
        : success.change > 0
        ? (label: l.sellChange, value: success.change)
        : (label: l.commonTotal, value: success.total);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppTheme.space4,
        AppTheme.space2,
        AppTheme.space4,
        AppTheme.space4 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppTheme.space4),
            decoration: BoxDecoration(
              color: colors.successSurface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: colors.success, size: 44),
                const SizedBox(width: AppTheme.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l.sellCompleted,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppTheme.space1),
                      Text(
                        headline.label,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      MoneyText(
                        fmt(headline.value),
                        style: Theme.of(context).textTheme.headlineSmall,
                        emphasis: true,
                        color: colors.success,
                        textAlign: TextAlign.left,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.space3),
          SummaryRow(l.commonTotal, fmt(success.total)),
          SummaryRow(l.sellAmountPaid, fmt(success.paid)),
          if (success.change > 0)
            SummaryRow(
              l.sellChange,
              fmt(success.change),
              emphasis: true,
              color: colors.success,
            ),
          const SizedBox(height: AppTheme.space2),
          FilledButton(
            onPressed: onDone,
            child: Text(l.checkoutDone),
          ),
        ],
      ),
    );
  }
}

/// A soft warning-tone inline hint (shortfall-becomes-credit and friends) —
/// informational, not an error, so it uses the warning soft-fill tier rather
/// than [InlineErrorBanner]'s danger container.
class _HintBanner extends StatelessWidget {
  const _HintBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space3,
        vertical: AppTheme.space2,
      ),
      decoration: BoxDecoration(
        color: colors.warningSurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.warning),
          const SizedBox(width: AppTheme.space2),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

/// Replaces the amount-paid field + tender chips + change/owed rows when
/// `_method == 'split'` — a compact read-out of what `showSplitPaymentDialog`
/// returned, plus an edit affordance, rather than trying to fold a
/// multi-method breakdown into controls built for a single amount.
class _SplitPaymentSummary extends StatelessWidget {
  const _SplitPaymentSummary({
    required this.entries,
    required this.currency,
    required this.accounts,
    required this.onEdit,
  });

  final List<PaymentEntry>? entries;
  final String currency;
  final List<PaymentAccount> accounts;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final list = entries;
    if (list == null || list.isEmpty) {
      return OutlinedButton.icon(
        onPressed: onEdit,
        icon: const Icon(Icons.call_split),
        label: Text(l.splitPaymentSetUp),
      );
    }
    final total = list.fold<int>(0, (a, e) => a + e.amount);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.space3),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in list)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space1),
              child: Row(
                children: [
                  Icon(paymentIcon(e.method), size: 16),
                  const SizedBox(width: AppTheme.space2),
                  Expanded(
                    child: Text(paymentLabel(l, e.method, accounts: accounts)),
                  ),
                  Text(Money(e.amount).withSymbol(currency)),
                ],
              ),
            ),
          const Divider(height: AppTheme.space3),
          Row(
            children: [
              Expanded(
                child: Text(
                  l.commonTotal,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              MoneyText(
                Money(total).withSymbol(currency),
                emphasis: true,
              ),
              const SizedBox(width: AppTheme.space2),
              TextButton(onPressed: onEdit, child: Text(l.splitPaymentEdit)),
            ],
          ),
        ],
      ),
    );
  }
}
