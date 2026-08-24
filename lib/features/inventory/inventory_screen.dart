import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/layout.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/repositories/demo_seed.dart';
import '../../data/local/database.dart';
import '../../domain/product_with_stock.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
import '../license/premium_gate.dart';
import '../printing/label_data.dart';
import '../printing/label_print_dialog.dart';
import '../printing/printing_providers.dart';
import '../sell/hardware_scanner_listener.dart';
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
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
    // Debug seeding + one-shot per-shop duplicate cleanup (audit M2 — the
    // cleanup used to rescan the whole catalogue on every tab mount; a
    // per-shop settings flag now runs it once).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await runInventoryStartupMaintenance(
        db: ref.read(databaseProvider),
        repo: ref.read(inventoryRepositoryProvider),
        shopId: ref.read(shopIdProvider),
        settings: ref.read(settingsRepositoryProvider),
      );
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openEditor([ProductWithStock? existing]) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProductEditScreen(existing: existing)),
    );
  }

  Future<void> _exportCsv() async {
    final l = AppLocalizations.of(context);
    if (!ref.read(isPremiumProvider)) {
      await showPremiumRequiredDialog(
        context,
        l.inventoryExportCsv,
        benefit: l.inventoryCsvBenefit,
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final products = ref.read(filteredProductsProvider);
    final categories =
        ref.read(categoriesStreamProvider).valueOrNull ?? const [];
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
    ref.listen<String>(inventorySearchProvider, (prev, next) {
      if (next != _search.text) {
        _search.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    });

    return HardwareScannerListener(
      onScan: (code) {
        final trimmed = code.trim();
        ref.read(inventorySearchProvider.notifier).state = trimmed;
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight:
              kToolbarHeight +
              (async.hasValue ? MediaQuery.textScalerOf(context).scale(20) : 0),
          // The theme's default centerTitle: true optically centers a title
          // between leading and actions — fine for a single-line title, but
          // this screen's 3 trailing icons (vs. a single-width leading back
          // button) unbalance that math and visibly push the two-line
          // title+subtitle block left of the icon row's true center. A
          // left-aligned title has no such asymmetry to fight.
          centerTitle: false,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.inventoryTitle),
              if (async.hasValue)
                Text(
                  l.inventoryFilteredCount(products.length),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: l.inventoryExportCsv,
              icon: const Icon(Icons.table_chart_outlined),
              onPressed: _exportCsv,
            ),
            IconButton(
              tooltip: l.stockHistoryTitle,
              icon: const Icon(Icons.history),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StockMovementsScreen()),
              ),
            ),
            IconButton(
              tooltip: l.manageCategories,
              icon: const Icon(Icons.label),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CategoriesScreen()),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space4,
                0,
                AppTheme.space4,
                AppTheme.space2,
              ),
              child: TextField(
                controller: _search,
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
                loading: () => const AppLoadingView(),
                error: (e, _) => ErrorRetryView(
                  message: l.commonUnexpectedError,
                  onRetry: () => ref.invalidate(productsStreamProvider),
                ),
                data: (_) {
                  if (products.isEmpty) {
                    final searching = ref
                        .read(inventorySearchProvider)
                        .trim()
                        .isNotEmpty;
                    return EmptyStateView(
                      icon: searching
                          ? Icons.search_off
                          : Icons.inventory_2_outlined,
                      title: searching
                          ? l.inventoryNoResults
                          : l.inventoryEmpty,
                    );
                  }
                  return Column(
                    children: [
                      if (trackStock && lowCount > 0)
                        _LowStockBanner(count: lowCount),
                      Expanded(
                        child: isMediumPlus(context)
                            ? GridView.builder(
                                padding: const EdgeInsets.all(AppTheme.space3),
                                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                                  // **Not** the old 300. `maxCrossAxisExtent` is a
                                  // ceiling, not a target: the delegate takes
                                  // `ceil(width / extent)` columns and divides evenly,
                                  // so 300 on an 820pt iPad produced three ~235pt
                                  // cards — and a card that narrow leaves ~70pt for
                                  // the name once the thumbnail, stock pill and menu
                                  // have taken their fixed widths, which shredded
                                  // every Myanmar product name into two clipped
                                  // fragments and wrapped "300 ကျပ်" onto two lines.
                                  // (Seen on a real iPad, not reasoned about: the old
                                  // 300 was equally broken, the thumbnail just made
                                  // it visible.) 440 forces two ~360pt cards on this
                                  // iPad and never divides below ~300pt on anything
                                  // wider.
                                  maxCrossAxisExtent: 440,
                                  mainAxisSpacing: AppTheme.space3,
                                  crossAxisSpacing: AppTheme.space3,
                                  // A fixed row height derived from the type scale
                                  // beats `childAspectRatio`, which ties the row's
                                  // height to how many columns happened to fit and
                                  // therefore breaks at exactly one window width.
                                  mainAxisExtent: _gridTileHeight(context),
                                ),
                                itemCount: products.length,
                                itemBuilder: (context, i) {
                                  final p = products[i];
                                  return Card(
                                    // Stable per-product key (audit Low).
                                    key: ValueKey('prod-${p.product.id}'),
                                    clipBehavior: Clip.antiAlias,
                                    child: _ProductTile(
                                      p: p,
                                      currency: currency,
                                      trackStock: trackStock,
                                      canEdit: canEdit,
                                      onOpen: () => _openEditor(p),
                                    ),
                                  );
                                },
                              )
                            : ListView.separated(
                                // Clears the extended FAB, which otherwise sits on
                                // top of the last row's overflow menu.
                                padding: const EdgeInsets.fromLTRB(
                                  AppTheme.space3,
                                  AppTheme.space2,
                                  AppTheme.space3,
                                  88,
                                ),
                                itemCount: products.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: AppTheme.space2),
                                itemBuilder: (context, i) {
                                  final p = products[i];
                                  return Card(
                                    key: ValueKey('prod-${p.product.id}'),
                                    clipBehavior: Clip.antiAlias,
                                    child: _ProductTile(
                                      p: p,
                                      currency: currency,
                                      trackStock: trackStock,
                                      canEdit: canEdit,
                                      onOpen: () => _openEditor(p),
                                    ),
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
      ),
    );
  }
}

/// Height of one tablet grid cell: whichever is taller, the 48pt thumbnail or
/// a two-line name over a price line, plus the tile's own padding and the
/// `Card`'s default 4pt margin. Measured off the *scaled* type scale so a
/// shopkeeper running large text gets a taller row instead of a clipped one.
double _gridTileHeight(BuildContext context) {
  final text = Theme.of(context).textTheme;
  final scaler = MediaQuery.textScalerOf(context);
  double line(TextStyle? s, double fallbackSize) =>
      scaler.scale(s?.fontSize ?? fallbackSize) * (s?.height ?? 1.4);
  final textBlock = line(text.titleSmall, 14) * 2 + line(text.bodyMedium, 14);
  final content = textBlock > 48 ? textBlock : 48.0;
  return content + AppTheme.space2 * 2 + 8;
}

/// Inventory's binding of the shared [CategoryFilterBar] — the same control
/// Sell shows over the same catalogue, with per-chip counts. Hidden when the
/// shop has no categories.
class _CategoryFilterBar extends ConsumerWidget {
  const _CategoryFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final categories =
        ref.watch(categoriesStreamProvider).valueOrNull ?? const [];
    if (categories.isEmpty) return const SizedBox.shrink();
    final counts = ref.watch(inventoryCategoryCountsProvider);

    return CategoryFilterBar(
      selectedId: ref.watch(inventoryCategoryProvider),
      onSelected: (id) =>
          ref.read(inventoryCategoryProvider.notifier).state = id,
      options: [
        CategoryFilterOption(
          id: null,
          label: l.categoryAll,
          count: counts[null] ?? 0,
        ),
        for (final c in categories)
          CategoryFilterOption(
            id: c.id,
            label: c.name,
            count: counts[c.id] ?? 0,
          ),
      ],
    );
  }
}

/// One product in the Inventory list (phone) or grid (tablet) — the same
/// widget in both, so the two layouts can't drift apart.
///
/// **Carries the shared [ProductThumb].** Inventory lists the *same products*
/// the Sell grid does, but rendered them as bare text with no mark at all, so
/// the two tabs disagreed about what a product looks like. Same photo-or-
/// initials-plate, same stable [AppColors.identityTone] color as Sell's grid
/// tile and the checkout cart line.
///
/// **The two per-row icon buttons moved into a labelled overflow menu.** A
/// thumbnail + a two-line Myanmar name + a stock pill + two 48dp icon buttons
/// does not fit a 402pt phone; something had to give, and the two things that
/// gave the least were the unlabeled glyphs — on a touch device their
/// `tooltip:` is effectively invisible, so "print label" and "update stock"
/// were being distinguished by icon shape alone. In the menu they are icon
/// *plus* translated label. The frequent one (update stock) also stays one tap
/// away: the stock pill itself is the control, since the number you want to
/// change is the obvious thing to press.
class _ProductTile extends ConsumerWidget {
  const _ProductTile({
    required this.p,
    required this.currency,
    required this.trackStock,
    required this.canEdit,
    required this.onOpen,
  });

  final ProductWithStock p;
  final String currency;
  final bool trackStock;
  final bool canEdit;
  final VoidCallback onOpen;

  void _adjustStock(BuildContext context, WidgetRef ref) =>
      showStockAdjustDialog(
        context,
        ref,
        productId: p.product.id,
        productName: p.product.name,
        currentQuantity: p.quantity,
      );

  void _printLabel(BuildContext context, WidgetRef ref) => showLabelPrintDialog(
    context,
    ref,
    data: LabelData(
      name: p.product.name,
      // Always the ASCII 'Ks' so it prints cleanly via native text
      // commands.
      priceText: Money(p.product.salePrice).withSymbol('Ks'),
      barcode: labelBarcodeFor(p.product),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final outOfStock = trackStock && p.quantity <= 0;

    return InkWell(
      onTap: canEdit ? onOpen : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space4,
          AppTheme.space2,
          AppTheme.space2,
          AppTheme.space2,
        ),
        child: Row(
          children: [
            ProductThumb(
              name: p.product.name,
              imageUrl: p.product.imageUrl,
              size: 48,
              radius: AppTheme.radiusSm,
              dimmed: outOfStock,
            ),
            const SizedBox(width: AppTheme.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p.product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  // Left-aligned but still tabular: prices all start on the
                  // same rule down the list, so the digits line up as a
                  // column. Neutral, not the brand green Sell uses — on this
                  // screen the accent belongs to the "Add product" FAB, and
                  // the figure that needs to catch the eye is the stock
                  // count, not the price.
                  MoneyText(
                    Money(p.product.salePrice).withSymbol(currency),
                    style: theme.textTheme.bodyMedium,
                    color: theme.colorScheme.onSurfaceVariant,
                    textAlign: TextAlign.left,
                  ),
                ],
              ),
            ),
            if (trackStock) ...[
              const SizedBox(width: AppTheme.space2),
              _StockBadge(
                quantity: p.quantity,
                low: p.isLowStock,
                onTap: canEdit ? () => _adjustStock(context, ref) : null,
              ),
            ],
            PopupMenuButton<void>(
              tooltip: l.commonMore,
              icon: const Icon(Icons.more_vert),
              itemBuilder: (_) => [
                if (trackStock && canEdit)
                  PopupMenuItem<void>(
                    onTap: () => _adjustStock(context, ref),
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.add_box_outlined),
                      title: Text(l.inventoryUpdateStock),
                    ),
                  ),
                PopupMenuItem<void>(
                  onTap: () => _printLabel(context, ref),
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.qr_code_2),
                    title: Text(l.inventoryPrintLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The stock figure as a pill, and — when the user may edit — the control
/// that changes it.
///
/// Three tiers rather than the old two, so "none left" and "getting low" stop
/// looking identical: **out of stock** takes the danger soft-fill (matching
/// Sell's out-of-stock badge, which already treats `qty <= 0` as the hard
/// stop), **low stock** takes warning, and a healthy count is neutral. The
/// old healthy fill was `secondaryContainer`, which in the current palette is
/// `#DCE7E1` — byte-for-byte the same sage as `identityFills[0]`, so a sage
/// product plate and the pill beside it merged into one shape on roughly a
/// quarter of all rows.
class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.quantity, required this.low, this.onTap});

  final int quantity;
  final bool low;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    // Only the tiers that need attention (out of stock / low) get pill
    // chrome. A healthy count is plain text — on a full list, every row
    // wearing the same grey pill drowned out the handful that actually
    // needed a glance, and a bare number gave no hint it was tappable.
    final needsAttention = quantity <= 0 || low;
    final (Color bg, Color fg) = quantity <= 0
        ? (colors.dangerSurface, colors.danger)
        : low
        ? (colors.warningSurface, colors.warning)
        : (Colors.transparent, scheme.onSurfaceVariant);

    final number = Text(
      '$quantity',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: fg,
        fontFeatures: AppTheme.tabularFigures,
      ),
    );

    final pill = Container(
      // A floor wide enough for three digits so single- and triple-digit
      // counts share one right edge down the list.
      constraints: const BoxConstraints(minWidth: 48),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space3,
        vertical: AppTheme.space1,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: onTap == null
          ? number
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                number,
                const SizedBox(width: AppTheme.space1),
                // The pencil is the only visual cue this plain-looking
                // number is a button — without it a healthy count (now
                // background-free, see above) is indistinguishable from
                // static text.
                Icon(
                  Icons.edit_outlined,
                  size: 14,
                  color: needsAttention
                      ? fg.withValues(alpha: 0.7)
                      : scheme.outline,
                ),
              ],
            ),
    );

    if (onTap == null) {
      return Semantics(label: '${l.productQuantity}: $quantity', child: pill);
    }
    return Tooltip(
      message: l.inventoryUpdateStock,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        child: Semantics(
          button: true,
          label: '${l.inventoryUpdateStock}, ${l.productQuantity}: $quantity',
          excludeSemantics: true,
          // The pill itself is ~30pt tall; this keeps the *target* at 48.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Center(widthFactor: 1, child: pill),
          ),
        ),
      ),
    );
  }
}

/// "N products are low on stock" strip above the list.
///
/// Was a full-bleed `errorContainer` block with bare text — a third banner
/// language in an app that had already converged on the [AppColors] soft-fill
/// tier for Sell's two licence banners. Low stock is a *warning* (the shop can
/// still sell), so it takes the warning fill; the danger fill stays reserved
/// for the rows that have actually run out.
class _LowStockBanner extends StatelessWidget {
  const _LowStockBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      color: colors.warningSurface,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space4,
        vertical: AppTheme.space3,
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, size: 20, color: colors.warning),
          const SizedBox(width: AppTheme.space2),
          Expanded(
            child: Text(
              '${l.inventoryLowStock}: $count',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.warning),
            ),
          ),
        ],
      ),
    );
  }
}
