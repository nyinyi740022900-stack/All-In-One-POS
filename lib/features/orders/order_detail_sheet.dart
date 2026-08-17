import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/layout.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import '../accounts/payment_account_providers.dart';
import '../sell/payment_labels.dart';
import '../sell/sales_providers.dart';
import '../storefront/storefront_screen.dart' show storefrontRepositoryProvider;
import 'order_invoice.dart';
import 'order_editor_sheet.dart';
import 'order_labels.dart';
import 'orders_providers.dart';

/// Read-only order view with pipeline actions (edit, move, convert, cancel,
/// delete). Reads the live order from the stream so it reflects edits/moves.
class OrderDetailSheet extends ConsumerWidget {
  const OrderDetailSheet({
    super.key,
    required this.orderId,
    this.embedded = false,
  });

  final String orderId;

  /// When true, render as an inline pane (no sheet chrome / close that pops).
  final bool embedded;

  static Future<void> show(BuildContext context, String orderId) {
    return showAppModal<void>(
      context: context,
      builder: (_) => OrderDetailSheet(orderId: orderId),
    );
  }

  /// Pop only when this sheet was shown as a modal. When [embedded] in a
  /// master–detail pane, a bare [Navigator.pop] would hit the shell branch
  /// navigator and break tab navigation.
  void _closeIfModal(BuildContext context) {
    if (embedded) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final sym = l.currencySymbol;
    final orders = ref.watch(ordersStreamProvider).valueOrNull ?? const [];
    Order? order;
    for (final o in orders) {
      if (o.id == orderId) {
        order = o;
        break;
      }
    }
    if (order == null) {
      return const SizedBox(height: 120, child: Center(child: Text('—')));
    }
    final o = order;
    final items = ref.watch(orderItemsProvider(orderId)).valueOrNull ?? const [];
    final repo = ref.read(ordersRepositoryProvider);
    final total = o.itemsTotal + o.deliveryFee;
    final isCancelled = o.status == 'cancelled';
    final canConvert = o.status == 'delivered' && o.saleId == null;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(orderChannelIcon(o.channel), size: 18),
                const SizedBox(width: 6),
                Text(o.orderNo,
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                StatusPill(
                  label: orderStatusLabel(l, o.status),
                  tone: orderStatusTone(o.status),
                  showDot: true,
                ),
                const SizedBox(width: 4),
                // Explicit close — the content can be tall enough (items +
                // payment proof photo + delivery section) that the sheet's
                // drag-handle swipe-to-dismiss isn't an obvious way out.
                if (!embedded)
                  IconButton(
                    tooltip: MaterialLocalizations.of(context)
                        .closeButtonTooltip,
                    icon: const Icon(Icons.close),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _closeIfModal(context),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(orderChannelLabel(l, o.channel),
                style: Theme.of(context).textTheme.bodySmall),
            // Carrier hand-off is the single most-used action on this sheet
            // (it's what actually moves an order along) — surfaced first so
            // it never requires scrolling past customer/item detail.
            if (!isCancelled) ...[
              const SizedBox(height: 14),
              _CarrierHandoffSection(order: o),
            ],
            const Divider(height: 20),
            _kv(context, Icons.person_outline, o.customerName),
            if (o.customerPhone != null && o.customerPhone!.isNotEmpty)
              Row(
                children: [
                  Expanded(
                      child: _kv(
                          context, Icons.phone_outlined, o.customerPhone!)),
                  IconButton(
                    tooltip: l.orderBlockCustomer,
                    icon: const Icon(Icons.block, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        _blockCustomer(context, ref, l, o.customerPhone!),
                  ),
                ],
              ),
            if (o.deliveryAddress != null && o.deliveryAddress!.isNotEmpty)
              _kv(context, Icons.location_on_outlined, o.deliveryAddress!),
            if (o.township != null && o.township!.isNotEmpty)
              _kv(context, Icons.map_outlined, o.township!),
            if (o.note != null && o.note!.isNotEmpty)
              _kv(context, Icons.sticky_note_2_outlined, o.note!),
            const Divider(height: 20),
            for (final it in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    if (it.lowStockAtOrder) ...[
                      Tooltip(
                        message: l.orderLowStockAtOrder,
                        // Warning, not error: the item was low when the order
                        // came in, which is something to check, not a failure.
                        child: Icon(Icons.warning_amber_rounded,
                            size: 16, color: AppColors.of(context).warning),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(child: Text('${it.nameSnapshot}  ×${it.qty}')),
                    Text(Money(it.lineTotal).withSymbol(sym)),
                  ],
                ),
              ),
            if (o.deliveryFee > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l.orderDeliveryFee),
                    Text(Money(o.deliveryFee).withSymbol(sym)),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l.orderTotal,
                    style: Theme.of(context).textTheme.titleMedium),
                Text(Money(total).withSymbol(sym),
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            _PaymentSection(order: o),
            const Divider(height: 24),

            // --- actions ---
            if (canConvert)
              FilledButton.icon(
                onPressed: () => _convert(context, ref, o),
                icon: const Icon(Icons.point_of_sale),
                label: Text(l.orderConvertToSale),
              ),
            if (o.saleId != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: AppColors.of(context).success, size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text(l.orderAlreadySale)),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: o.saleId != null
                        ? null
                        : () {
                            _closeIfModal(context);
                            OrderEditorSheet.show(context,
                                order: o, existingItems: items);
                          },
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(l.orderEdit),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => isCancelled
                        ? repo.setStatus(orderId, 'new')
                        : _markReturn(context, ref, o),
                    icon: Icon(isCancelled
                        ? Icons.restore
                        : Icons.cancel_outlined),
                    label: Text(isCancelled ? l.orderRestore : l.orderCancel),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: items.isEmpty
                        ? null
                        : () => _printInvoice(context, ref, o, items),
                    icon: const Icon(Icons.print_outlined),
                    label: Text(l.orderPrint),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: items.isEmpty
                        ? null
                        : () => _shareInvoice(context, ref, o, items),
                    icon: const Icon(Icons.receipt_long),
                    label: Text(l.orderInvoice),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Destructive, but *not* a status: it takes the solid danger tone
            // (from the palette, so dark mode gets the lighter red that
            // actually reads on near-black) and no soft fill — a pastel plate
            // here would make deleting an order look like a state badge.
            TextButton.icon(
              onPressed: () => _confirmDelete(context, ref),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.of(context).danger,
              ),
              icon: const Icon(Icons.delete_outline),
              label: Text(l.orderDelete),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, IconData icon, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<void> _printInvoice(BuildContext context, WidgetRef ref, Order o,
      List<OrderItem> items) async {
    try {
      await printOrderInvoice(context, ref, o, items);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context).commonUnexpectedError)));
      }
    }
  }

  Future<void> _shareInvoice(BuildContext context, WidgetRef ref, Order o,
      List<OrderItem> items) async {
    try {
      await shareOrderInvoice(context, ref, o, items);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context).commonUnexpectedError)));
      }
    }
  }

  Future<void> _convert(BuildContext context, WidgetRef ref, Order o) async {
    final l = AppLocalizations.of(context);
    final method = await showAppModal<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Text(l.orderPickPaymentMethod,
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(l.orderConvertHint,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            const SizedBox(height: 8),
            for (final m in paymentMethodIds(
                ref.read(paymentAccountsProvider).valueOrNull ?? const []))
              ListTile(
                title: Text(paymentLabel(l, m,
                    accounts:
                        ref.read(paymentAccountsProvider).valueOrNull)),
                onTap: () => Navigator.of(context).pop(m),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (method == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(ordersRepositoryProvider);
    try {
      await repo.convertToSale(o.id, paymentMethod: method);
      final saved = await repo.getOrder(o.id);
      final sale = await ref.read(salesRepositoryProvider).getSale(saved.saleId!);
      if (!context.mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(l.orderConverted(sale.invoiceNo))));
      _closeIfModal(context);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.orderConvertFailed)));
    }
  }

  /// Marking an order Return used to be a pure label change — it never
  /// touched the sale it was converted to, or the stock that sale already
  /// deducted, which could easily read as "the stock/money came back" when
  /// it hadn't. If the order has a linked sale, this now reverses it for
  /// real via the same accounting-correct refund used from Invoices
  /// (append-only reversal sale, stock restored at original cost, payment
  /// reversed, any outstanding credit closed) — with an explicit
  /// confirmation showing the amount, since it's irreversible. An order
  /// never converted to a sale has nothing to reverse, so it just flips the
  /// status as before.
  Future<void> _markReturn(BuildContext context, WidgetRef ref, Order o) async {
    final l = AppLocalizations.of(context);
    final repo = ref.read(ordersRepositoryProvider);
    final saleId = o.saleId;
    if (saleId == null) {
      try {
        await repo.setStatus(o.id, 'cancelled');
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(l.orderReturnFailed)));
        }
      }
      return;
    }
    final salesRepo = ref.read(salesRepositoryProvider);
    try {
      final alreadyRefunded = await salesRepo.refundOf(saleId) != null;
      if (!alreadyRefunded) {
        final sale = await salesRepo.getSale(saleId);
        if (!context.mounted) return;
        final amount = Money(sale.total).withSymbol(l.currencySymbol);
        final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l.orderReturnConfirmTitle),
            content: Text(l.orderReturnConfirmBody(amount)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(l.commonCancel)),
              FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(l.invoiceRefund)),
            ],
          ),
        );
        if (ok != true || !context.mounted) return;
        await salesRepo.refundSale(saleId);
      }
      await repo.setStatus(o.id, 'cancelled');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.orderReturnFailed)));
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      // showDialog defaults to the ROOT navigator, while this sheet's own
      // `context` belongs to go_router's nested shell-branch navigator —
      // popping via the outer context pops the wrong (branch) navigator,
      // dismissing the sheet underneath while leaving the dialog stuck open.
      // Use the dialog's own builder context instead.
      builder: (dialogContext) => AlertDialog(
        content: Text(l.orderDeleteConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l.commonCancel)),
          FilledButton(
              style: AppTheme.dangerFilledButtonStyle(dialogContext),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l.orderDelete)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(ordersRepositoryProvider).deleteOrder(orderId);
      if (context.mounted) _closeIfModal(context);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l.commonUnexpectedError)));
      }
    }
  }

  Future<void> _blockCustomer(BuildContext context, WidgetRef ref,
      AppLocalizations l, String phone) async {
    final ok = await showDialog<bool>(
      context: context,
      // See _confirmDelete's comment: must pop via the dialog's own context.
      builder: (dialogContext) => AlertDialog(
        title: Text(l.orderBlockCustomer),
        content: Text(l.orderBlockCustomerConfirm(phone)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l.orderBlockCustomer)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(storefrontRepositoryProvider).block(phone);
      messenger.showSnackBar(SnackBar(content: Text(l.orderCustomerBlocked)));
    } catch (e) {
      messenger
          .showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    }
  }
}

/// Renders a storefront payment screenshot from its private storage path via a
/// short-lived signed URL.
class _PaymentProof extends StatefulWidget {
  const _PaymentProof({required this.path});
  final String path;

  @override
  State<_PaymentProof> createState() => _PaymentProofState();
}

class _PaymentProofState extends State<_PaymentProof> {
  late final Future<String> _url;

  @override
  void initState() {
    super.initState();
    _url = Supabase.instance.client.storage
        .from('payment-proofs')
        .createSignedUrl(widget.path, 3600);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
              height: 120, child: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError || snap.data == null) {
          return const Icon(Icons.broken_image_outlined);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            snap.data!,
            height: 200,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.broken_image_outlined),
          ),
        );
      },
    );
  }
}

/// Payment section: COD orders never need a "paid?" status before delivery
/// (the cash is collected at the door, so it's always unpaid until then) —
/// showing "Unpaid" there just reads as an alarm with nothing to do about
/// it, so COD gets one plain descriptive line instead. Transfer orders (or
/// orders with no method set) get the real status plus a way to confirm
/// payment after reviewing the screenshot — `Order.paymentStatus` only ever
/// flips to 'paid' automatically when converted to a sale otherwise, with no
/// way to acknowledge "I saw the screenshot, payment is confirmed" before
/// that (fulfillment and payment confirmation are separate steps).
class _PaymentSection extends ConsumerStatefulWidget {
  const _PaymentSection({required this.order});
  final Order order;

  @override
  ConsumerState<_PaymentSection> createState() => _PaymentSectionState();
}

class _PaymentSectionState extends ConsumerState<_PaymentSection> {
  // Guards against a double-tap firing the write twice while the first one
  // is still in flight, and lets the button show it's working instead of
  // looking like the tap did nothing.
  bool _updating = false;

  Future<void> _setPaymentStatus(String status) async {
    if (_updating) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _updating = true);
    try {
      await ref
          .read(ordersRepositoryProvider)
          .setPaymentStatus(widget.order.id, status);
    } catch (e) {
      if (mounted) {
        messenger
            .showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final o = widget.order;

    final isPaid = o.paymentStatus == 'paid';
    // COD's "not paid yet" is the expected default before the courier
    // collects cash at the door — showing a status word for it just reads as
    // an alarm with nothing to act on, so it gets one plain sentence instead
    // (see orderPaymentCodNote below). But COD that's ALREADY paid (a
    // customer transferred early despite being tagged COD) is real,
    // actionable information — that case falls through to the same
    // badge/toggle UI as a transfer order, not the plain note.
    if (o.paymentMethod == 'cod' && !isPaid) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.local_shipping_outlined,
                size: 18, color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: 8),
            Expanded(child: Text(l.orderPaymentCodNote)),
            if (o.saleId == null)
              TextButton(
                onPressed:
                    _updating ? null : () => _setPaymentStatus('paid'),
                child: _updating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l.orderMarkAsPaid),
              ),
          ],
        ),
      );
    }

    // Once converted to a sale, the sale itself is the source of truth for
    // what was actually paid — toggling this afterward would be cosmetic at
    // best and misleading at worst, so the control disappears and the badge
    // just reflects the (already 'paid') status convertToSale set.
    final canToggle = o.saleId == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (o.paymentMethod != null && o.paymentMethod!.isNotEmpty) ...[
              _PaymentMethodChip(method: o.paymentMethod!),
              const SizedBox(width: 8),
            ],
            StatusPill(
              label: isPaid ? l.orderPayPaid : l.orderAwaitingPayment,
              tone: orderPaymentTone(isPaid ? 'paid' : 'unpaid'),
              icon: isPaid
                  ? Icons.check_circle_outline
                  : Icons.schedule_outlined,
            ),
          ],
        ),
        if (o.paymentProofPath != null &&
            o.paymentProofPath!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(l.orderPaymentProof,
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          _PaymentProof(path: o.paymentProofPath!),
        ],
        if (canToggle) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: isPaid
                ? TextButton.icon(
                    onPressed:
                        _updating ? null : () => _setPaymentStatus('unpaid'),
                    icon: _updating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.undo, size: 16),
                    label: Text(l.orderMarkAsUnpaid),
                  )
                : FilledButton.tonalIcon(
                    onPressed:
                        _updating ? null : () => _setPaymentStatus('paid'),
                    icon: _updating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(l.orderMarkAsPaid),
                  ),
          ),
        ],
      ],
    );
  }
}

/// Small pill for "Bank transfer" vs "Cash on delivery" — these need visibly
/// different shop workflows (review a screenshot vs collect cash at the
/// door), so it sits right next to the payment status, not buried in notes.
///
/// Not a [StatusPill]: a payment *method* is a fact about the order, not a
/// status, so it deliberately takes the neutral `secondaryContainer` chip
/// treatment rather than one of the four semantic tones — otherwise "Cash on
/// delivery" would look like a state the shopkeeper has to resolve. It does
/// share the pill's geometry (stadium radius, token padding) so the two read
/// as one row of pills rather than two unrelated boxes.
class _PaymentMethodChip extends StatelessWidget {
  const _PaymentMethodChip({required this.method});
  final String method;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isCod = method == 'cod';
    final label = isCod ? l.orderPaymentCod : l.orderPaymentTransfer;
    final icon = isCod ? Icons.local_shipping_outlined : Icons.account_balance_outlined;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space2,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: scheme.onSecondaryContainer),
          const SizedBox(width: AppTheme.space1),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// The primary action: pick (or type a new) carrier and hand the order off
/// in one tap. Before hand-off, shows the carrier field + button; after,
/// shows a compact confirmation with a "Change" link back into edit mode.
class _CarrierHandoffSection extends ConsumerStatefulWidget {
  const _CarrierHandoffSection({required this.order});
  final Order order;

  @override
  ConsumerState<_CarrierHandoffSection> createState() =>
      _CarrierHandoffSectionState();
}

class _CarrierHandoffSectionState extends ConsumerState<_CarrierHandoffSection> {
  late final TextEditingController _carrier;
  late final TextEditingController _tracking;
  bool _editing = false;
  bool _saving = false;
  bool _savingTracking = false;

  @override
  void initState() {
    super.initState();
    _carrier = TextEditingController(text: widget.order.deliveryCarrier ?? '');
    _tracking = TextEditingController(text: widget.order.trackingNumber ?? '');
  }

  @override
  void dispose() {
    _carrier.dispose();
    _tracking.dispose();
    super.dispose();
  }

  Future<void> _handOff() async {
    final carrier = _carrier.text.trim();
    if (carrier.isEmpty) return;
    final l = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(ordersRepositoryProvider)
          .handOffToCarrier(widget.order.id, carrier: carrier);
      if (!mounted) return;
      setState(() {
        _editing = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveTracking() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingTracking = true);
    try {
      await ref
          .read(ordersRepositoryProvider)
          .setDelivery(widget.order.id, trackingNumber: _tracking.text.trim());
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l.deliverySaved)));
    } catch (e) {
      if (mounted) {
        messenger
            .showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
      }
    } finally {
      if (mounted) setState(() => _savingTracking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final handedOff = widget.order.status == 'delivered' && !_editing;

    if (handedOff) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping_outlined,
                  color: AppColors.of(context).success, size: 18),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(
                      l.orderHandedOffTo(widget.order.deliveryCarrier ?? ''))),
              TextButton(
                onPressed: () => setState(() => _editing = true),
                child: Text(l.orderChangeCarrier),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Waybill/tracking number is only ever known once the carrier has
          // actually picked the parcel up — asking for it before hand-off
          // (as an always-visible field) just means an empty box nobody can
          // fill in yet.
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tracking,
                  decoration: InputDecoration(
                    labelText: l.deliveryTrackingNumber,
                    hintText: l.deliveryTrackingHint,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _savingTracking ? null : _saveTracking,
                icon: _savingTracking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check, size: 18),
                label: Text(l.deliverySave),
              ),
            ],
          ),
        ],
      );
    }

    final suggestions =
        ref.watch(carrierSuggestionsProvider).where((c) => c.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.deliveryCarrier, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        RawAutocomplete<String>(
          textEditingController: _carrier,
          focusNode: FocusNode(),
          optionsBuilder: (v) {
            final q = v.text.trim().toLowerCase();
            if (q.isEmpty) return suggestions;
            return suggestions.where((c) => c.toLowerCase().contains(q));
          },
          onSelected: (c) => setState(() => _carrier.text = c),
          fieldViewBuilder: (context, controller, focusNode, onSubmit) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: InputDecoration(
                labelText: l.orderCarrierHint,
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            );
          },
          optionsViewBuilder: (context, onSelectedOption, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      for (final c in options)
                        ListTile(
                          dense: true,
                          title: Text(c),
                          onTap: () => onSelectedOption(c),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed:
              _saving || _carrier.text.trim().isEmpty ? null : _handOff,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.local_shipping_outlined),
          label: Text(l.orderHandOffButton),
        ),
      ],
    );
  }
}

