import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../../core/layout.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../inventory/inventory_providers.dart';
import '../license/license_providers.dart';
import '../license/license_screen.dart';
import '../printing/printing_providers.dart';
import 'barcode_scanner_screen.dart';
import 'cart.dart';
import 'checkout_sheet.dart';
import 'sales_providers.dart';

class SellScreen extends ConsumerWidget {
  const SellScreen({super.key});

  Future<void> _confirmClear(
      BuildContext context, WidgetRef ref, AppLocalizations l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.sellClearConfirmTitle),
        content: Text(l.sellClearConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.sellClear)),
        ],
      ),
    );
    if (ok == true) ref.read(cartProvider.notifier).clear();
  }

  Future<void> _scanAndAdd(
      BuildContext context, WidgetRef ref, AppLocalizations l) async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (code == null || !context.mounted) return;
    final products = ref.read(productsStreamProvider).valueOrNull ?? const [];
    final match =
        products.firstWhereOrNull((p) => (p.product.barcode ?? '') == code);
    final messenger = ScaffoldMessenger.of(context);
    if (match != null) {
      ref.read(cartProvider.notifier).addProduct(match.product);
      messenger.showSnackBar(
          SnackBar(content: Text(l.scanAdded(match.product.name))));
    } else {
      ref.read(sellSearchProvider.notifier).state = code;
      messenger
          .showSnackBar(SnackBar(content: Text(l.scanNotFound(code))));
    }
  }

  void _openCheckout(BuildContext context) {
    showAppModal<void>(
      context: context,
      builder: (_) => const CheckoutSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final products = ref.watch(productsStreamProvider);
    final filtered = ref.watch(sellProductsProvider);
    final cart = ref.watch(cartProvider);
    final currency = l.currencySymbol;
    final trackStock = ref.watch(trackStockProvider).valueOrNull ?? true;
    final licState = ref.watch(licenseControllerProvider);
    final readOnly = licState.status.isReadOnly && !licState.loading;
    final expiresAt = licState.status.expiresAt;
    final daysLeft = expiresAt?.difference(DateTime.now()).inDays;
    final expiringSoon = !licState.loading &&
        licState.status.canSell &&
        daysLeft != null &&
        daysLeft <= 5;
    final daysLeftShown = daysLeft == null ? 0 : (daysLeft < 0 ? 0 : daysLeft);
    final split = isMediumPlus(context);
    final tileExtent = split ? 210.0 : 180.0;
    final trailFlex = widthClassOf(context) == AppWidthClass.expanded ? 38 : 42;
    final leadFlex = 100 - trailFlex;

    Widget banners() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (expiringSoon && !readOnly)
              Material(
                color: AppColors.of(context).warning.withValues(alpha: 0.12),
                child: InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const LicenseScreen())),
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.space3),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber,
                            color: AppColors.of(context).warning),
                        const SizedBox(width: AppTheme.space2),
                        Expanded(
                          child: Text(
                            l.licenseExpiringSoon(daysLeftShown),
                            style:
                                TextStyle(color: AppColors.of(context).warning),
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            color: AppColors.of(context).warning),
                      ],
                    ),
                  ),
                ),
              ),
            if (readOnly)
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.space3),
                  child: Row(
                    children: [
                      Icon(Icons.lock,
                          color:
                              Theme.of(context).colorScheme.onErrorContainer),
                      const SizedBox(width: AppTheme.space2),
                      Expanded(
                        child: Text(
                          l.licenseReadOnly,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );

    final productPane = Column(
      children: [
        banners(),
        const _SellCategoryFilterBar(),
        Expanded(
          child: products.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(l.commonUnexpectedError)),
            data: (_) {
              if (filtered.isEmpty) {
                final searching =
                    ref.read(sellSearchProvider).trim().isNotEmpty ||
                        ref.read(sellCategoryProvider) != null;
                return EmptyStateView(
                  icon: searching ? Icons.search_off : Icons.inventory_2_outlined,
                  title: searching ? l.inventoryNoResults : l.inventoryEmpty,
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.all(AppTheme.space3),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: tileExtent,
                  mainAxisSpacing: AppTheme.space3,
                  crossAxisSpacing: AppTheme.space3,
                  childAspectRatio: 1.1,
                ),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final p = filtered[i];
                  return _ProductCard(
                    name: p.product.name,
                    price: Money(p.product.salePrice).withSymbol(currency),
                    outOfStock: trackStock && p.quantity <= 0,
                    onTap: () {
                      final ok = ref.read(cartProvider.notifier).addProduct(
                            p.product,
                            maxQty: trackStock ? p.quantity : null,
                          );
                      if (!ok) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(l.sellStockCap(p.quantity)),
                          duration: const Duration(seconds: 1),
                        ));
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l.sellTitle),
        actions: [
          IconButton(
            tooltip: l.scanBarcode,
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => _scanAndAdd(context, ref, l),
          ),
          if (!cart.isEmpty)
            IconButton(
              tooltip: l.sellClear,
              icon: const Icon(Icons.remove_shopping_cart),
              onPressed: () => _confirmClear(context, ref, l),
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
                  ref.read(sellSearchProvider.notifier).state = v,
            ),
          ),
        ),
      ),
      body: split
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: leadFlex, child: productPane),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: trailFlex,
                  child: _CartPanel(
                    onCheckout: () => _openCheckout(context),
                    onClear: () => _confirmClear(context, ref, l),
                  ),
                ),
              ],
            )
          : productPane,
      bottomNavigationBar: split || cart.isEmpty
          ? null
          : _CartBar(
              itemCount: cart.itemCount,
              total: cart.total.withSymbol(currency),
              onCheckout: () => _openCheckout(context),
            ),
    );
  }
}

class _CartPanel extends ConsumerWidget {
  const _CartPanel({required this.onCheckout, required this.onClear});

  final VoidCallback onCheckout;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final cart = ref.watch(cartProvider);
    final currency = l.currencySymbol;
    final trackStock = ref.watch(trackStockProvider).valueOrNull ?? true;
    final stockById = <String, int>{
      for (final p in ref.watch(productsStreamProvider).valueOrNull ?? const [])
        p.product.id: p.quantity,
    };

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppTheme.space4,
                AppTheme.space3, AppTheme.space2, AppTheme.space2),
            child: Row(
              children: [
                Expanded(
                  child: Text(l.sellCart,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (!cart.isEmpty)
                  TextButton(onPressed: onClear, child: Text(l.sellClear)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: cart.isEmpty
                ? EmptyStateView(
                    icon: Icons.shopping_cart_outlined,
                    title: l.sellEmptyCart,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        vertical: AppTheme.space2),
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final line = cart.lines[i];
                      return ListTile(
                        dense: true,
                        title: Text(line.product.name, maxLines: 2),
                        subtitle: Text(
                          cart.lineTotalFor(line).withSymbol(currency),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.remove),
                              onPressed: () => ref
                                  .read(cartProvider.notifier)
                                  .decrement(line.product.id),
                            ),
                            Text('${line.qty}'),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.add),
                              onPressed: () {
                                final ok =
                                    ref.read(cartProvider.notifier).increment(
                                          line.product.id,
                                          maxQty: trackStock
                                              ? stockById[line.product.id]
                                              : null,
                                        );
                                if (!ok) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(
                                    content: Text(l.sellStockCap(
                                        stockById[line.product.id] ?? 0)),
                                    duration: const Duration(seconds: 1),
                                  ));
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          if (!cart.isEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppTheme.space3),
              child: FilledButton(
                onPressed: onCheckout,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${l.sellCheckout}  (${cart.itemCount})'),
                    Text(cart.total.withSymbol(currency),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SellCategoryFilterBar extends ConsumerWidget {
  const _SellCategoryFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final categories =
        ref.watch(categoriesStreamProvider).valueOrNull ?? const [];
    if (categories.isEmpty) return const SizedBox.shrink();
    final selected = ref.watch(sellCategoryProvider);

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
                  ref.read(sellCategoryProvider.notifier).state = null,
            ),
          ),
          for (final c in categories)
            Padding(
              padding: const EdgeInsets.only(right: AppTheme.space2),
              child: ChoiceChip(
                label: Text(c.name),
                selected: selected == c.id,
                onSelected: (_) =>
                    ref.read(sellCategoryProvider.notifier).state = c.id,
              ),
            ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.name,
    required this.price,
    required this.outOfStock,
    required this.onTap,
  });

  final String name;
  final String price;
  final bool outOfStock;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: AppTheme.space2),
              Text(price,
                  style: TextStyle(
                      color: scheme.primary, fontWeight: FontWeight.bold)),
              if (outOfStock)
                Text('0',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: scheme.error)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({
    required this.itemCount,
    required this.total,
    required this.onCheckout,
  });

  final int itemCount;
  final String total;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space3),
        child: FilledButton(
          onPressed: onCheckout,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${l.sellCheckout}  ($itemCount)'),
              Text(total, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
