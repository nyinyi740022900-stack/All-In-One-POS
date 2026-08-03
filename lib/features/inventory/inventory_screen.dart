import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/money.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/demo_seed.dart';
import '../../data/local/database.dart';
import '../../domain/product_with_stock.dart';
import '../../l10n/app_localizations.dart';
import '../printing/label_data.dart';
import '../printing/label_print_dialog.dart';
import '../printing/printing_providers.dart';
import '../staff/staff_providers.dart';
import 'categories_screen.dart';
import 'inventory_csv.dart';
import 'inventory_providers.dart';
import 'product_edit_screen.dart';
import 'stock_adjust_dialog.dart';
import 'stock_movements_screen.dart';

/// Barcode value to print/scan for a product — its own barcode if set,
/// falling back to the SKU, then the internal id, so every product can get
/// a printable label even if the shop never entered a real barcode.
String labelBarcodeFor(Product p) {
  if ((p.barcode ?? '').trim().isNotEmpty) return p.barcode!.trim();
  if ((p.sku ?? '').trim().isNotEmpty) return p.sku!.trim();
  return p.id;
}

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  @override
  void initState() {
    super.initState();
    // Seed demo data on first run (debug/local convenience).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final db = ref.read(databaseProvider);
      final repo = ref.read(inventoryRepositoryProvider);
      await DemoSeed(db, repo).ensureSeeded();
    });
  }

  Future<void> _openEditor([ProductWithStock? existing]) {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProductEditScreen(existing: existing),
    ));
  }

  Future<void> _exportCsv() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final products = ref.read(filteredProductsProvider);
    final categories = ref.read(categoriesStreamProvider).valueOrNull ?? const [];
    final categoryNameById = {for (final c in categories) c.id: c.name};
    try {
      final csv = buildInventoryCsv(
        products,
        categoryNameById,
        nameHeader: l.productName,
        skuHeader: l.productSku,
        barcodeHeader: l.productBarcode,
        categoryHeader: l.productCategory,
        costPriceHeader: l.productCost,
        salePriceHeader: l.productPrice,
        quantityHeader: l.productQuantity,
        reorderLevelHeader: l.productReorderLevel,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/inventory.csv');
      await file.writeAsString(csv);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: l.inventoryTitle,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(productsStreamProvider);
    final products = ref.watch(filteredProductsProvider);
    final lowCount = ref.watch(lowStockCountProvider);
    final trackStock = ref.watch(trackStockProvider).valueOrNull ?? true;
    final currency = l.currencySymbol;
    // Cashiers can browse inventory but not add/edit products; managers can.
    final canEdit = ref.watch(canEditInventoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.inventoryTitle),
        actions: [
          IconButton(
            tooltip: l.inventoryExportCsv,
            icon: const Icon(Icons.table_chart_outlined),
            onPressed: _exportCsv,
          ),
          IconButton(
            tooltip: l.stockHistoryTitle,
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const StockMovementsScreen(),
            )),
          ),
          IconButton(
            tooltip: l.manageCategories,
            icon: const Icon(Icons.label),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const CategoriesScreen(),
            )),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTheme.space4, 0, AppTheme.space4, AppTheme.space2),
            child: TextField(
              decoration: InputDecoration(
                hintText: l.commonSearch,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) =>
                  ref.read(inventorySearchProvider.notifier).state = v,
            ),
          ),
        ),
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: Text(l.commonAdd),
            )
          : null,
      body: Column(
        children: [
          const _CategoryFilterBar(),
          Expanded(
            child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.commonUnexpectedError)),
        data: (_) {
          if (products.isEmpty) {
            final searching =
                ref.read(inventorySearchProvider).trim().isNotEmpty;
            return Center(
              child: Text(searching ? l.inventoryNoResults : l.inventoryEmpty),
            );
          }
          return Column(
            children: [
              if (trackStock && lowCount > 0)
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.errorContainer,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.space4, vertical: AppTheme.space2),
                  child: Text(
                    '${l.inventoryLowStock}: $lowCount',
                    style: TextStyle(
                        color:
                            Theme.of(context).colorScheme.onErrorContainer),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  itemCount: products.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final p = products[i];
                    return ListTile(
                      title: Text(p.product.name),
                      subtitle: Text(
                          Money(p.product.salePrice).withSymbol(currency)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.qr_code_2),
                            tooltip: l.inventoryPrintLabel,
                            onPressed: () => showLabelPrintDialog(
                              context,
                              ref,
                              data: LabelData(
                                name: p.product.name,
                                // Always the ASCII 'Ks' so it prints cleanly
                                // via native (non-raster) text commands.
                                priceText:
                                    Money(p.product.salePrice).withSymbol('Ks'),
                                barcode: labelBarcodeFor(p.product),
                              ),
                            ),
                          ),
                          if (trackStock && canEdit)
                            IconButton(
                              icon: const Icon(Icons.add_box_outlined),
                              tooltip: l.inventoryUpdateStock,
                              onPressed: () => showStockAdjustDialog(
                                context,
                                ref,
                                productId: p.product.id,
                                productName: p.product.name,
                                currentQuantity: p.quantity,
                              ),
                            ),
                          if (trackStock)
                            _StockBadge(
                                quantity: p.quantity, low: p.isLowStock),
                        ],
                      ),
                      onTap: canEdit ? () => _openEditor(p) : null,
                    );
                  },
                ),
              ),
            ],
          );
        },
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal "All + categories" filter chips. Hidden when no categories exist.
class _CategoryFilterBar extends ConsumerWidget {
  const _CategoryFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final categories =
        ref.watch(categoriesStreamProvider).valueOrNull ?? const [];
    if (categories.isEmpty) return const SizedBox.shrink();
    final selected = ref.watch(inventoryCategoryProvider);

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.space3),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppTheme.space2),
            child: ChoiceChip(
              label: Text(l.categoryAll),
              selected: selected == null,
              onSelected: (_) =>
                  ref.read(inventoryCategoryProvider.notifier).state = null,
            ),
          ),
          for (final c in categories)
            Padding(
              padding: const EdgeInsets.only(right: AppTheme.space2),
              child: ChoiceChip(
                label: Text(c.name),
                selected: selected == c.id,
                onSelected: (_) =>
                    ref.read(inventoryCategoryProvider.notifier).state = c.id,
              ),
            ),
        ],
      ),
    );
  }
}

class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.quantity, required this.low});

  final int quantity;
  final bool low;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = low ? scheme.errorContainer : scheme.secondaryContainer;
    final fg = low ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$quantity',
          style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
    );
  }
}
