import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/database.dart';
import '../../domain/product_with_stock.dart';
import '../../l10n/app_localizations.dart';
import '../inventory/inventory_providers.dart';
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
    final l = AppLocalizations.of(context);
    final products = ref.read(filteredProductsProvider);
    final searchCtrl = TextEditingController();
    var query = '';
    final picked = await showModalBottomSheet<ProductWithStock>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final filtered = query.isEmpty
              ? products
              : products
                  .where((p) => p.product.name
                      .toLowerCase()
                      .contains(query.toLowerCase()))
                  .toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppTheme.space3),
                    child: TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: l.commonSearch,
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (v) => setSheetState(() => query = v),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                    child: filtered.isEmpty
                        ? Padding(
                            padding:
                                const EdgeInsets.all(AppTheme.space4),
                            child: Text(l.poNoProductsFound,
                                style: Theme.of(ctx).textTheme.bodySmall),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final p in filtered)
                                ListTile(
                                  title: Text(p.product.name),
                                  subtitle: Text(Money(p.product.costPrice)
                                      .withSymbol(l.currencySymbol)),
                                  onTap: () => Navigator.pop(ctx, p),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
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
    final l = AppLocalizations.of(context);
    final qtyCtrl = TextEditingController(text: '${line.qty}');
    final costCtrl = TextEditingController(text: '${line.unitCost}');
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(line.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: l.productQuantity),
            ),
            const SizedBox(height: AppTheme.space2),
            TextField(
              controller: costCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: l.poUnitCost),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: ctx,
                builder: (ctx2) => AlertDialog(
                  title: Text(l.poRemoveLineConfirmTitle),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx2, false),
                        child: Text(l.commonCancel)),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx2, true),
                        child: Text(l.commonDelete)),
                  ],
                ),
              );
              if (confirmed == true) {
                setState(() => _lines.remove(line));
                if (ctx.mounted) Navigator.pop(ctx, false);
              }
            },
            child: Text(l.commonDelete,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.commonSave)),
        ],
      ),
    );
    if (result != true) return;
    setState(() {
      line.qty = int.tryParse(qtyCtrl.text.trim()) ?? line.qty;
      line.unitCost = int.tryParse(costCtrl.text.trim()) ?? line.unitCost;
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
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cur = l.currencySymbol;

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
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(line.name),
                subtitle: Text(
                    '${line.qty} x ${Money(line.unitCost).withSymbol(cur)}'),
                trailing: Text(Money(line.lineTotal).withSymbol(cur)),
                onTap: () => _editLine(line),
              ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.space2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l.commonTotal,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Text(Money(_total).withSymbol(cur),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.space3),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(l.poSaveDraft),
          ),
        ],
      ),
    );
  }
}
