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
import '../license/license_status.dart';
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
    // Free plan never expires — computeLicenseStatus keeps expiresAt as a
    // non-null placeholder (`now`, see license_status.dart) purely so `kind`
    // can be `active`, not as a real date. Without this guard, every Free
    // shop saw a permanent "expires in 0 days" warning (license_widgets.dart
    // already carries the same plan != free guard for this exact reason).
    final expiringSoon = !licState.loading &&
        licState.status.canSell &&
        licState.status.plan != LicensePlan.free &&
        daysLeft != null &&
        daysLeft <= 5;
    final daysLeftShown = daysLeft == null ? 0 : (daysLeft < 0 ? 0 : daysLeft);
    final split = isMediumPlus(context);
    // Sized so a phone keeps **three** columns now that each tile carries a
    // photo band: `SliverGridDelegateWithMaxCrossAxisExtent` counts the
    // cross-axis spacing into the extent, so the old 180 gave only two
    // 183pt-wide tiles on a 402pt phone — a shop-window layout, not a
    // counter one. 132 lands on three ~118pt tiles (still 2 on a small
    // 320pt phone), 168 on four in the tablet split view.
    final tileExtent = split ? 168.0 : 132.0;
    final trailFlex = widthClassOf(context) == AppWidthClass.expanded ? 38 : 42;
    final leadFlex = 100 - trailFlex;

    Widget banners() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (expiringSoon && !readOnly)
              Material(
                // Soft-fill tier (see AppColors) rather than an ad-hoc alpha
                // wash — 12% of a bright orange over a near-black dark
                // surface came out muddy and unreadable.
                color: AppColors.of(context).warningSurface,
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
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColors.of(context).warning),
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
                // Same soft-fill banner language as the expiry warning above,
                // so the two never look like different kinds of component.
                color: AppColors.of(context).dangerSurface,
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.space3),
                  child: Row(
                    children: [
                      Icon(Icons.lock, color: AppColors.of(context).danger),
                      const SizedBox(width: AppTheme.space2),
                      Expanded(
                        child: Text(
                          l.licenseReadOnly,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.of(context).danger),
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
            error: (e, _) => ErrorRetryView(
              message: l.commonUnexpectedError,
              onRetry: () => ref.invalidate(productsStreamProvider),
            ),
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
                  // Portrait, not the old near-square 1.1. The tile now
                  // carries a photo band *plus* two lines of name plus a
                  // price; at 1.1 the image band collapsed to a sliver.
                  // 0.68 leaves the photo band a near-square top half at
                  // default text scale (the two-line name + price block below
                  // it is a fixed height) while keeping three columns on a
                  // phone — density the counter can't afford to lose.
                  childAspectRatio: 0.68,
                ),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final p = filtered[i];
                  return _ProductCard(
                    name: p.product.name,
                    price: Money(p.product.salePrice).withSymbol(currency),
                    imageUrl: p.product.imageUrl,
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
                        // Same mark as the grid tile the seller just tapped —
                        // the fastest way to confirm the right thing landed
                        // in the cart without re-reading the name.
                        leading: ProductThumb(
                          name: line.product.name,
                          imageUrl: line.product.imageUrl,
                          size: 44,
                          radius: AppTheme.radiusSm,
                        ),
                        title: Text(line.product.name, maxLines: 2),
                        subtitle: MoneyText(
                          cart.lineTotalFor(line).withSymbol(currency),
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.left,
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
                            SizedBox(
                              width: 24,
                              child: Text(
                                '${line.qty}',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontFeatures: AppTheme.tabularFigures,
                                    ),
                              ),
                            ),
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
                    Text(
                      cart.total.withSymbol(currency),
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
        ],
      ),
    );
  }
}

/// Sell's binding of the shared [CategoryFilterBar] — the chip row itself now
/// lives in `core/widgets/app_widgets.dart` so Inventory shows the identical
/// control over the identical catalogue instead of its own bare-chip variant.
class _SellCategoryFilterBar extends ConsumerWidget {
  const _SellCategoryFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final categories =
        ref.watch(categoriesStreamProvider).valueOrNull ?? const [];
    if (categories.isEmpty) return const SizedBox.shrink();
    final counts = ref.watch(sellCategoryCountsProvider);

    return CategoryFilterBar(
      selectedId: ref.watch(sellCategoryProvider),
      onSelected: (id) => ref.read(sellCategoryProvider.notifier).state = id,
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

/// A tappable product tile: **photo band on top, name and price below** — the
/// structure every POS reference converges on, and the thing this grid was
/// missing entirely (it used to render a name and a price with a blank
/// flexible gap above them, shaped exactly like a photo slot nobody had
/// filled).
///
/// Products with no photo — most of them, in a shop that typed its catalogue
/// in by hand — get a tonal initials plate from [ProductThumb] rather than an
/// empty box, so the grid reads as deliberate whether or not anyone ever
/// pointed a camera at the stock.
///
/// Bumps down briefly on tap — the one micro-interaction that matters most on
/// this screen: instant tactile confirmation that "add to cart" registered,
/// since the cart panel/bar can be out of the shopkeeper's eye line while
/// they're keying in the next item.
class _ProductCard extends StatefulWidget {
  const _ProductCard({
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.outOfStock,
    required this.onTap,
  });

  final String name;
  final String price;
  final String? imageUrl;
  final bool outOfStock;
  final VoidCallback onTap;

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _pressed = false;

  void _bump() {
    // Out of stock still calls through: the cart caps the line at 0 and the
    // caller answers with the "only N left" snackbar. Swallowing the tap here
    // (as this used to) left a card that ripples under your finger and then
    // does nothing at all — the worst possible answer at a counter.
    if (!widget.outOfStock) {
      setState(() => _pressed = true);
      Future.delayed(AppTheme.motionFast, () {
        if (mounted) setState(() => _pressed = false);
      });
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = AppColors.of(context);
    return AnimatedScale(
      scale: _pressed ? 0.96 : 1.0,
      duration: AppTheme.motionFast,
      curve: AppTheme.curveEmphasized,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _bump,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The photo band takes whatever the text block leaves, rather
              // than a fixed fraction — so a long Myanmar name or a 1.3x text
              // scale shrinks the image instead of overflowing the tile.
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ProductThumb(
                      name: widget.name,
                      imageUrl: widget.imageUrl,
                      radius: 0,
                      dimmed: widget.outOfStock,
                    ),
                    if (widget.outOfStock)
                      Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(AppTheme.space2),
                          child: const _OutOfStockBadge(),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space3,
                  AppTheme.space2,
                  AppTheme.space3,
                  AppTheme.space3,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Always exactly two lines tall, even for a one-word
                    // name. Without this the text block's height varied per
                    // tile, so the photo band above it did too and the names
                    // in a row started at three different heights — the same
                    // class of raggedness as a price column that doesn't line
                    // up. Reserved from the *scaled* font size, so it grows
                    // with the user's text-size setting instead of clipping
                    // a longer Myanmar name at 1.3x.
                    SizedBox(
                      height: MediaQuery.textScalerOf(context).scale(
                            theme.textTheme.titleSmall?.fontSize ?? 14,
                          ) *
                          (theme.textTheme.titleSmall?.height ?? 1.4) *
                          2,
                      child: Text(
                        widget.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: widget.outOfStock
                              ? colors.muted
                              : scheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.space1),
                    MoneyText(
                      widget.price,
                      style: theme.textTheme.titleSmall,
                      color: widget.outOfStock ? colors.muted : scheme.primary,
                      emphasis: true,
                      textAlign: TextAlign.left,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Soft-fill danger pill laid over the product photo. Moved off the old
/// one-line red caption under the price: on a tile that now carries an image,
/// a caption competes with the price for the eye, while a badge on the image
/// is read before either.
class _OutOfStockBadge extends StatelessWidget {
  const _OutOfStockBadge();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.dangerSurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.space2,
          vertical: 2,
        ),
        child: Text(
          // The compact wording, not `inventoryOutOfStock`: the full Myanmar
          // string ("ကုန်ပစ္စည်း ကုန်သွားပါပြီ") is ~2x the English one and wrapped
          // to two lines, turning a corner badge into a panel covering half
          // the photo. Truncating it wasn't an option either — this is the
          // label that explains why the tile won't sell.
          AppLocalizations.of(context).inventoryOutOfStockBadge,
          maxLines: 2,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: colors.danger),
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
    final brightness = Theme.of(context).brightness;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: AppTheme.dockedBarShadow(brightness),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space3),
          child: FilledButton(
            onPressed: onCheckout,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${l.sellCheckout}  ($itemCount)'),
                Text(
                  total,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontFeatures: AppTheme.tabularFigures,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
