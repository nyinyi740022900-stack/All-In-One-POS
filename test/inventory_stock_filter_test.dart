import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/domain/product_with_stock.dart';
import 'package:mm_pos/features/inventory/inventory_providers.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';

Product _product(String id, {int salePrice = 1000}) => Product(
      id: id,
      shopId: 'shop-1',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      isDeleted: false,
      dirty: true,
      name: 'P-$id',
      costPrice: 0,
      salePrice: salePrice,
      unit: 'pcs',
      isActive: true,
    );

ProductWithStock _row(Product p, int qty, int reorder) =>
    ProductWithStock(product: p, quantity: qty, reorderLevel: reorder);

/// The low-stock-only list filter (owner feedback, 2026-08-24): the chip and
/// the tappable banner both drive [inventoryLowStockOnlyProvider], and the
/// filter must include out-of-stock rows even when no reorder level was ever
/// set — and must switch itself off when the shop stops tracking stock,
/// because a filter whose control is hidden must not keep hiding rows.
void main() {
  late ProviderContainer container;

  /// A `Stream.value` override delivers on a microtask, and only once
  /// something subscribes — listen first, then let microtasks run before
  /// asserting (see #234's widget-test harness note).
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    container = ProviderContainer(
      overrides: [
        productsStreamProvider.overrideWith(
          (ref) => Stream.value([
            _row(_product('healthy'), 50, 5),
            _row(_product('low'), 3, 5),
            _row(_product('out-no-reorder'), 0, 0),
          ]),
        ),
        trackStockProvider.overrideWith((ref) => Stream.value(true)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(productsStreamProvider, (_, _) {});
    container.listen(trackStockProvider, (_, _) {});
  });

  test('filter off shows everything', () async {
    await settle();
    expect(container.read(filteredProductsProvider), hasLength(3));
  });

  test('filter on keeps low AND out-of-stock, drops healthy', () async {
    await settle();
    container.read(inventoryLowStockOnlyProvider.notifier).state = true;
    final names = container
        .read(filteredProductsProvider)
        .map((p) => p.product.name)
        .toList();
    expect(names, ['P-low', 'P-out-no-reorder']);
  });

  test('filter ignores itself when the shop does not track stock', () async {
    final off = ProviderContainer(
      overrides: [
        productsStreamProvider.overrideWith(
          (ref) => Stream.value([
            _row(_product('healthy'), 50, 5),
            _row(_product('low'), 3, 5),
          ]),
        ),
        trackStockProvider.overrideWith((ref) => Stream.value(false)),
      ],
    );
    addTearDown(off.dispose);
    off.listen(productsStreamProvider, (_, _) {});
    off.listen(trackStockProvider, (_, _) {});
    await settle();
    off.read(inventoryLowStockOnlyProvider.notifier).state = true;
    // Tracking is off, so the filter clause must be skipped and BOTH rows
    // stay visible even with the flag stuck on (control hidden = no wedge).
    expect(off.read(filteredProductsProvider), hasLength(2));
  });

  test('needsStockAttention: out with no reorder level still counts', () {
    expect(needsStockAttention(_row(_product('a'), 0, 0)), isTrue);
    expect(needsStockAttention(_row(_product('b'), 3, 5)), isTrue);
    expect(needsStockAttention(_row(_product('c'), 50, 5)), isFalse);
  });
}
