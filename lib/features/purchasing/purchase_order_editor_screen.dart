import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/currency_def.dart';
import '../../core/input/thousands_formatter.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/local/database.dart';
import '../../domain/product_with_stock.dart';
import '../../l10n/app_localizations.dart';
import '../inventory/inventory_providers.dart';
import '../printing/printing_providers.dart';
import '../suppliers/supplier_providers.dart';
import 'purchase_order_providers.dart';
import 'purchase_order_repository.dart';

class _EditableLine {
  _EditableLine({required this.productId, required this.name, required this.qty, required this.unitCost});
  final String productId;
  final String name;
  int qty;
  int unitCost;
  int get lineTotal => qty * unitCost;
}

/// One PO line, flagging when its cost has drifted from what's saved on the
/// product today — that mismatch is often the actual trigger to go update
/// the catalogue price, and previously had no visual cue distinguishing
/// "still the catalogue default" from "I typed today's real supplier price."
class _POLineTile extends StatelessWidget {
  const _POLineTile({
    required this.line,
    required this.catalogCost,
    required this.currency,
    required this.locale,
    required this.onTap,
  });

  final _EditableLine line;
  final int? catalogCost;
  final CurrencyDef currency;
  final String locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final differs = catalogCost != null && catalogCost != line.unitCost;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(line.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${line.qty} x ${Money(line.unitCost).withCurrency(currency, locale)}'),
          if (differs)
            Text(
              l.poLineCatalogCostDiffers(
                  Money(catalogCost!).withCurrency(currency, locale)),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      trailing: MoneyText(Money(line.lineTotal).withCurrency(currency, locale)),
      onTap: onTap,
    );
  }
}

/// Create (or edit, while still `open`) a purchase order: pick a supplier,
/// add product lines with qty + unit cost, save as a draft. See
/// `PurchaseOrderRepository.savePO`.
class PurchaseOrderEditorScreen extends ConsumerStatefulWidget {
  const PurchaseOrderEditorScreen({super.key, this.existing, this.existingItems});
  final PurchaseOrder? existing;
  final List<PurchaseOrderItem>? existingItems;

  @override
  ConsumerState<PurchaseOrderEditorScreen> createState() =>
      _PurchaseOrderEditorScreenState();
}

class _PurchaseOrderEditorScreenState
    extends ConsumerState<PurchaseOrderEditorScreen> {
  final _supplierName = TextEditingController();
  final _note = TextEditingController();
  String? _supplierId;
  final _lines = <_EditableLine>[];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _supplierName.text = e.supplierName;
      _supplierId = e.supplierId;
      _note.text = e.note ?? '';
      for (final it in widget.existingItems ?? const <PurchaseOrderItem>[]) {
        _lines.add(_EditableLine(
            productId: it.productId,
            name: it.nameSnapshot,
            qty: it.qty,
            unitCost: it.unitCost));
      }
    }
  }

  @override
  void dispose() {
    _supplierName.dispose();
    _note.dispose();
    super.dispose();
  }

  int get _total => _lines.fold(0, (s, l) => s + l.lineTotal);

  Future<void> _pickSupplier() async {
    final l = AppLocalizations.of(context);
    final suppliers = ref.read(suppliersProvider).valueOrNull ?? const [];
    if (suppliers.isEmpty) return;
    final picked = await showModalBottomSheet<Supplier>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppTheme.space3),
              child: Text(l.suppliersTitle,
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final s in suppliers)
              ListTile(
                title: Text(s.name),
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _supplierId = picked.id;
      _supplierName.text = picked.name;
    });
  }

  Future<void> _addProduct() async {
    // The shop's full active catalogue, deliberately **not**
    // `filteredProductsProvider` — that provider carries Inventory's own
    // leftover search/category state (a `StateProvider` that outlives the
    // Inventory tab), so this picker used to silently show whatever subset
    // Inventory was last filtered to (e.g. a cashier leaves Inventory on the
    // "Drinks" category, and the PO picker then can't find a non-drink
    // product at all until the user notices and clears Inventory's own
    // filter first). `productsStreamProvider` is the same unfiltered base
    // `filteredProductsProvider` itself reads from, so this picker now does
    // only its own local text search, independent of any other tab's state.
    final products = ref.read(productsStreamProvider).valueOrNull ?? const [];
    final currency = ref.read(shopCurrencyProvider);
    final picked = await showModalBottomSheet<ProductWithStock>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductPickerSheet(products: products, currency: currency),
    );
    if (picked == null) return;
    setState(() {
      final idx =
          _lines.indexWhere((l) => l.productId == picked.product.id);
      if (idx >= 0) {
        _lines[idx].qty += 1;
      } else {
        _lines.add(_EditableLine(
            productId: picked.product.id,
            name: picked.product.name,
            qty: 1,
            unitCost: picked.product.costPrice));
      }
    });
  }

  Future<void> _editLine(_EditableLine line) async {
    final currency = ref.read(shopCurrencyProvider);
    final result = await showDialog<_LineEditResult>(
      context: context,
      builder: (_) => _LineEditorDialog(line: line, currency: currency),
    );
    if (result == null) return;
    setState(() {
      if (result.removed) {
        _lines.remove(line);
      } else {
        line.qty = result.qty;
        line.unitCost = result.cost;
      }
    });
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (_supplierName.text.trim().isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l.poNeedsSupplier)));
      return;
    }
    if (_lines.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l.poNeedsItems)));
      return;
    }
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(purchaseOrderRepositoryProvider).savePO(
            id: widget.existing?.id,
            supplierId: _supplierId,
            supplierName: _supplierName.text.trim(),
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            lines: [
              for (final line in _lines)
                PurchaseOrderDraftLine(
                  productId: line.productId,
                  name: line.name,
                  qty: line.qty,
                  unitCost: line.unitCost,
                ),
            ],
          );
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(l.poSaved)));
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
    final products = ref.watch(productsStreamProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(l.poCreate)),
      floatingActionButton: FloatingActionButton(
        onPressed: _addProduct,
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.space4),
        children: [
          TextField(
            controller: _supplierName,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: l.supplierNameLabel,
              suffixIcon: IconButton(
                icon: const Icon(Icons.local_shipping_outlined),
                onPressed: _pickSupplier,
              ),
            ),
            onChanged: (_) => setState(() => _supplierId = null),
          ),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _note,
            decoration: InputDecoration(labelText: l.expenseNote),
          ),
          const SizedBox(height: AppTheme.space4),
          Text(l.poItems, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppTheme.space2),
          if (_lines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.space3),
              child: Text(l.poNoItems,
                  style: Theme.of(context).textTheme.bodySmall),
            )
          else
            for (final line in _lines)
              _POLineTile(
                line: line,
                catalogCost: products
                    .where((p) => p.product.id == line.productId)
                    .firstOrNull
                    ?.product
                    .costPrice,
                currency: currency,
                locale: locale,
                onTap: () => _editLine(line),
              ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.space2),
            child: SummaryRow(
                l.commonTotal, Money(_total).withCurrency(currency, locale),
                emphasis: true),
          ),
          const SizedBox(height: AppTheme.space3),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const ButtonSpinner()
                : Text(l.poSaveDraft),
          ),
        ],
      ),
    );
  }
}

/// Result of [_LineEditorDialog] — either updated qty/cost, or a request to
/// remove the line entirely (the nested "remove line" confirm inside the
/// dialog pops this dialog too, so the caller only ever handles one result).
class _LineEditResult {
  const _LineEditResult.save({required this.qty, required this.cost})
      : removed = false;
  const _LineEditResult.remove()
      : qty = 0,
        cost = 0,
        removed = true;

  final int qty;
  final int cost;
  final bool removed;
}

/// Owns its own `qty`/`unitCost` [TextEditingController]s so `dispose()`
/// runs on the dialog route's real teardown rather than a `showDialog`
/// `await` that resolves on *pop* — this was the second of two dispose-
/// after-`await` crash instances in this file (the first is
/// [_ProductPickerSheet]'s search field), same pattern fixed repeatedly
/// elsewhere this session.
class _LineEditorDialog extends StatefulWidget {
  const _LineEditorDialog({required this.line, required this.currency});
  final _EditableLine line;
  final CurrencyDef currency;

  @override
  State<_LineEditorDialog> createState() => _LineEditorDialogState();
}

class _LineEditorDialogState extends State<_LineEditorDialog> {
  late final _qty = TextEditingController(text: '${widget.line.qty}');
  late final _cost = TextEditingController(
    text: formatDecimalMinorUnits(widget.line.unitCost,
        exponent: widget.currency.exponent),
  );

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _confirmRemove() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx2) => AlertDialog(
        title: Text(l.poRemoveLineConfirmTitle),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx2, false),
              child: Text(l.commonCancel)),
          FilledButton(
              style: AppTheme.dangerFilledButtonStyle(ctx2),
              onPressed: () => Navigator.pop(ctx2, true),
              child: Text(l.commonDelete)),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.pop(context, const _LineEditResult.remove());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.line.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _qty,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(9),
            ],
            decoration: InputDecoration(labelText: l.productQuantity),
          ),
          const SizedBox(height: AppTheme.space2),
          TextField(
            controller: _cost,
            keyboardType: TextInputType.numberWithOptions(
                decimal: widget.currency.exponent > 0),
            inputFormatters: [
              DecimalMoneyInputFormatter(exponent: widget.currency.exponent),
              LengthLimitingTextInputFormatter(12),
            ],
            decoration: InputDecoration(labelText: l.poUnitCost),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _confirmRemove,
          child: Text(l.commonDelete,
              style: TextStyle(color: AppColors.of(context).danger)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _LineEditResult.save(
              // Clamp to >= 1: `receivePO` calls `adjustStock` per line and
              // that throws on a zero delta, so a line saved with qty 0
              // rolled back the whole receive transaction — the PO could
              // never be received, with only a generic error to go on.
              qty: switch (int.tryParse(_qty.text.trim())) {
                final n? when n > 0 => n,
                _ => widget.line.qty,
              },
              cost: _cost.text.trim().isEmpty
                  ? widget.line.unitCost
                  : parseDecimalMinorUnits(_cost.text.trim(),
                      exponent: widget.currency.exponent),
            ),
          ),
          child: Text(l.commonSave),
        ),
      ],
    );
  }
}

/// Owns its own search [TextEditingController] so `dispose()` runs on the
/// sheet route's real teardown rather than a `showModalBottomSheet` `await`
/// that resolves on *pop* — the first of two dispose-after-`await` crash
/// instances in this file.
class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet({required this.products, required this.currency});
  final List<ProductWithStock> products;
  final CurrencyDef currency;

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final filtered = _query.isEmpty
        ? widget.products
        : widget.products
            .where((p) =>
                p.product.name.toLowerCase().contains(_query.toLowerCase()))
            .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppTheme.space3),
              child: TextField(
                controller: _search,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l.commonSearch,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppTheme.space4),
                      child: Text(l.poNoProductsFound,
                          style: Theme.of(context).textTheme.bodySmall),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final p in filtered)
                          ListTile(
                            title: Text(p.product.name),
                            subtitle: MoneyText(
                              Money(p.product.costPrice)
                                  .withCurrency(widget.currency, locale),
                              textAlign: TextAlign.left,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            onTap: () => Navigator.pop(context, p),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
