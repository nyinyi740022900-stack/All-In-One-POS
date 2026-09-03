import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/currency_def.dart';
import '../../core/layout.dart';
import '../../core/money.dart';
import '../../data/local/database.dart';
import '../../domain/product_with_stock.dart';
import '../../l10n/app_localizations.dart';
import '../customers/customer_picker.dart';
import '../customers/customer_providers.dart';
import '../inventory/inventory_providers.dart';
import '../printing/printing_providers.dart';
import 'order_labels.dart';
import 'orders_providers.dart';
import 'orders_repository.dart';

/// One editable item row in the order editor.
class _LineDraft {
  final String? productId;
  final TextEditingController name;
  final TextEditingController price;
  final TextEditingController qty;
  _LineDraft({this.productId, String name = '', int price = 0, int qty = 1})
      : name = TextEditingController(text: name),
        price = TextEditingController(text: price == 0 ? '' : '$price'),
        qty = TextEditingController(text: '$qty');

  int get priceVal => int.tryParse(price.text.trim()) ?? 0;
  int get qtyVal => int.tryParse(qty.text.trim()) ?? 0;
  int get lineTotal => priceVal * qtyVal;

  void dispose() {
    name.dispose();
    price.dispose();
    qty.dispose();
  }
}

/// Bottom sheet to create a new order or edit an existing one. Pass [order] +
/// [existingItems] to edit; omit both to create.
class OrderEditorSheet extends ConsumerStatefulWidget {
  const OrderEditorSheet({super.key, this.order, this.existingItems});

  final Order? order;
  final List<OrderItem>? existingItems;

  static Future<void> show(
    BuildContext context, {
    Order? order,
    List<OrderItem>? existingItems,
  }) {
    return showAppModal<void>(
      context: context,
      builder: (_) => OrderEditorSheet(order: order, existingItems: existingItems),
    );
  }

  @override
  ConsumerState<OrderEditorSheet> createState() => _OrderEditorSheetState();
}

class _OrderEditorSheetState extends ConsumerState<OrderEditorSheet> {
  late final TextEditingController _name;
  final _nameFocus = FocusNode();
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _deliveryFee;
  late final TextEditingController _note;
  late String _channel;
  final List<_LineDraft> _lines = [];
  bool _saving = false;
  // Set when a directory customer was picked via the autocomplete/picker
  // sheet; cleared whenever the name is edited by hand so a stale id never
  // gets attached to the wrong typed name.
  String? _selectedCustomerId;

  @override
  void initState() {
    super.initState();
    final o = widget.order;
    _name = TextEditingController(text: o?.customerName ?? '');
    _selectedCustomerId = o?.customerId;
    _phone = TextEditingController(text: o?.customerPhone ?? '');
    _address = TextEditingController(text: o?.deliveryAddress ?? '');
    _deliveryFee = TextEditingController(
        text: (o?.deliveryFee ?? 0) == 0 ? '' : '${o!.deliveryFee}');
    _note = TextEditingController(text: o?.note ?? '');
    _channel = o?.channel ?? 'facebook';
    for (final it in widget.existingItems ?? const <OrderItem>[]) {
      _lines.add(_LineDraft(
        productId: it.productId,
        name: it.nameSnapshot,
        price: it.priceSnapshot,
        qty: it.qty,
      ));
    }
    if (_lines.isEmpty) _lines.add(_LineDraft());
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    _phone.dispose();
    _address.dispose();
    _deliveryFee.dispose();
    _note.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  int get _itemsTotal => _lines.fold(0, (s, l) => s + l.lineTotal);
  int get _deliveryFeeVal => int.tryParse(_deliveryFee.text.trim()) ?? 0;

  /// Auto-expand "More details" when editing an order that already has any
  /// of those optional fields filled, so nothing looks lost.
  bool get _hasMoreDetails =>
      _phone.text.isNotEmpty ||
      _address.text.isNotEmpty ||
      _deliveryFee.text.isNotEmpty ||
      _note.text.isNotEmpty;

  Future<void> _pickProduct(_LineDraft line) async {
    final products = ref.read(productsStreamProvider).valueOrNull ?? const [];
    final currency = ref.read(shopCurrencyProvider);
    final selected = await showModalBottomSheet<ProductPick>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProductPickerSheet(products: products, currency: currency),
    );
    if (selected == null) return;
    setState(() {
      line.name.text = selected.name;
      line.price.text = '${selected.price}';
    });
    // Rebind productId by replacing the draft (productId is final).
    final idx = _lines.indexOf(line);
    if (idx >= 0) {
      final replacement = _LineDraft(
        productId: selected.productId,
        name: selected.name,
        price: selected.price,
        qty: line.qtyVal < 1 ? 1 : line.qtyVal,
      );
      setState(() {
        _lines[idx] = replacement;
      });
      // Dispose only AFTER the frame where the row's TextFields rebind to
      // the replacement's controllers — disposing inside the same setState
      // left them bound to a dead controller for one frame, and a cursor
      // blink or IME update landing in that window crashed.
      WidgetsBinding.instance.addPostFrameCallback((_) => line.dispose());
    }
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    if (_name.text.trim().isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l.orderNeedsName)));
      return;
    }
    // QA-L6: a fully blank row (the "+ Add item" default) is skipped
    // silently, but a row the seller PARTIALLY filled — a name with no qty,
    // or a price with no name — used to vanish on save without a word.
    // Block instead and point at the problem.
    for (final d in _lines) {
      final hasName = d.name.text.trim().isNotEmpty;
      final invalid =
          (hasName && d.qtyVal <= 0) || (!hasName && d.priceVal > 0);
      if (invalid) {
        messenger.showSnackBar(SnackBar(content: Text(l.orderInvalidLine)));
        return;
      }
    }
    final lines = _lines
        .where((d) => d.name.text.trim().isNotEmpty && d.qtyVal > 0)
        .map((d) => OrderDraftLine(
              productId: d.productId,
              name: d.name.text.trim(),
              price: d.priceVal,
              qty: d.qtyVal,
            ))
        .toList();
    if (lines.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l.orderNeedsItem)));
      return;
    }

    setState(() => _saving = true);
    try {
      final phone = _phone.text.trim();
      // A directory customer explicitly picked via the autocomplete/picker
      // sheet is used as-is — resolving by name again could match a
      // different customer sharing that name.
      final customerId = _selectedCustomerId ??
          await ref
              .read(customerRepositoryProvider)
              .resolveOrCreate(_name.text.trim(),
                  phone: phone.isEmpty ? null : phone);
      await ref.read(ordersRepositoryProvider).saveOrder(
            id: widget.order?.id,
            customerName: _name.text.trim(),
            customerPhone: phone.isEmpty ? null : phone,
            customerId: customerId,
            channel: _channel,
            deliveryAddress:
                _address.text.trim().isEmpty ? null : _address.text.trim(),
            deliveryFee: _deliveryFeeVal,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            lines: lines,
          );
      // saveOrder() replaces this order's items wholesale (tombstone + insert)
      // — orderItemsProvider has no watch signal of its own (a plain family
      // provider over a one-shot repository read), so without this the
      // detail sheet keeps showing the pre-edit item list until app restart.
      // Guarded on mounted: a sheet dismissed mid-save used to throw
      // StateError out of ref here (after the save had already succeeded).
      final editedId = widget.order?.id;
      if (editedId != null && mounted) {
        ref.invalidate(orderItemsProvider(editedId));
      }
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l.orderSaved)));
      nav.pop();
    } catch (e) {
      if (mounted) {
        messenger
            .showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final currency = ref.watch(shopCurrencyProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraftedContent(
        title: widget.order == null ? l.orderNew : l.orderEditTitle,
        children: [
          CustomerAutocomplete(
            controller: _name,
            focusNode: _nameFocus,
            labelText: l.orderCustomerName,
            onChanged: () {},
            onEditedByHand: () => _selectedCustomerId = null,
            onSelected: (c) {
              setState(() {
                _name.text = c.name;
                if (_phone.text.trim().isEmpty && (c.phone ?? '').isNotEmpty) {
                  _phone.text = c.phone!;
                }
                _selectedCustomerId = c.id;
              });
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _channel,
            decoration: InputDecoration(labelText: l.orderChannel),
            // `orderChannels` is the pickable list for a manually-created
            // order and deliberately excludes 'storefront' (that channel is
            // stamped server-side, never hand-picked — see
            // supabase/functions/storefront/index.ts's submit_order). An
            // existing order can still carry a channel outside that list
            // (storefront today, potentially others later), and
            // DropdownButtonFormField asserts its initialValue must appear
            // exactly once in items — append it here so opening a
            // storefront order for editing doesn't crash.
            items: [
              for (final c in {...orderChannels, _channel})
                DropdownMenuItem(value: c, child: Text(orderChannelLabel(l, c))),
            ],
            onChanged: (v) => setState(() => _channel = v ?? 'facebook'),
          ),
          const SizedBox(height: 8),
          // Phone/address/delivery-fee/note are all optional — folded away by
          // default so a quick "name + item" order takes one glance to fill,
          // and auto-expanded when editing an order that already has any of
          // this filled in (so nothing looks lost).
          Theme(
            data: Theme.of(context)
                .copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: _hasMoreDetails,
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(l.orderMoreDetails,
                  style: Theme.of(context).textTheme.labelLarge),
              children: [
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: l.orderCustomerPhone),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _address,
                  maxLines: 2,
                  decoration:
                      InputDecoration(labelText: l.orderDeliveryAddress),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _deliveryFee,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(9),
                  ],
                  decoration: InputDecoration(
                    labelText: l.orderDeliveryFee,
                    suffixText: currency.label(locale),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  maxLines: 2,
                  decoration: InputDecoration(labelText: l.orderNote),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(l.orderItems,
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _lines.add(_LineDraft())),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l.orderAddItem),
              ),
            ],
          ),
          for (final line in _lines) _itemRow(l, line),
          const SizedBox(height: 16),
          _totalRow(l.orderItemsTotal,
              Money(_itemsTotal).withCurrency(currency, locale)),
          _totalRow(l.orderTotal,
              Money(_itemsTotal + _deliveryFeeVal).withCurrency(currency, locale),
              bold: true),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text(l.orderSave),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _itemRow(AppLocalizations l, _LineDraft line) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: TextField(
              controller: line.name,
              decoration: InputDecoration(
                labelText: l.orderItemName,
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: l.orderAddItem,
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  onPressed: () => _pickProduct(line),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 3,
            child: TextField(
              controller: line.price,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              decoration:
                  InputDecoration(labelText: l.orderItemPrice, isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: TextField(
              controller: line.qty,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              decoration:
                  InputDecoration(labelText: l.orderItemQty, isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: _lines.length == 1
                ? null
                : () => setState(() {
                      _lines.remove(line);
                      line.dispose();
                    }),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool bold = false}) {
    final style = bold
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}

/// Scrollable padded column used by the editor sheet body.
class DraftedContent extends StatelessWidget {
  const DraftedContent({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                // Explicit close — this form can get tall (items list +
                // expanded "More details"), so the drag-handle
                // swipe-to-dismiss isn't always an obvious way out.
                IconButton(
                  tooltip: MaterialLocalizations.of(context)
                      .closeButtonTooltip,
                  icon: const Icon(Icons.close),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Result of the catalog product picker.
class ProductPick {
  final String productId;
  final String name;
  final int price;
  const ProductPick(this.productId, this.name, this.price);
}

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet({required this.products, required this.currency});
  final List<ProductWithStock> products;
  final CurrencyDef currency;

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final q = _q.trim().toLowerCase();
    final items = widget.products
        .where((p) => q.isEmpty || p.product.name.toLowerCase().contains(q))
        .toList();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l.orderItemName,
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final p = items[i].product;
                  return ListTile(
                    dense: true,
                    title: Text(p.name),
                    trailing: Text(
                      Money(p.salePrice).withCurrency(widget.currency, locale),
                    ),
                    onTap: () => Navigator.of(context)
                        .pop(ProductPick(p.id, p.name, p.salePrice)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
