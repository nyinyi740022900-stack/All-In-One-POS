import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/sell/cart.dart';
import 'package:mm_pos/features/sell/held_sales_provider.dart';
import 'package:mm_pos/features/sell/sales_providers.dart';
import 'package:mm_pos/features/sell/sell_session_reset.dart';

/// Regression coverage for audit QA-C2: a shop switch must drop the old
/// shop's in-memory Sell state — cart, held carts, search text and category
/// filter — or Shop A's cart can be checked out as Shop B.
void main() {
  Product product() => Product(
        id: 'p1',
        shopId: 'shop-1',
        name: 'Coke',
        costPrice: 500,
        salePrice: 700,
        unit: 'pcs',
        isActive: true,
        sellOnline: true,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        isDeleted: false,
        dirty: false,
      );

  test('resetSellSessionState clears cart, held carts, search and category',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final p = product();

    // Populate every session-scoped surface.
    container.read(cartProvider.notifier).addProduct(p);
    container
        .read(heldSalesProvider.notifier)
        .hold(CartState(lines: [CartLine(product: p, qty: 3)], discount: 100));
    container.read(sellSearchProvider.notifier).state = 'coke';
    container.read(sellCategoryProvider.notifier).state = 'cat-1';

    expect(container.read(cartProvider).isEmpty, isFalse);
    expect(container.read(heldSalesProvider), hasLength(1));
    expect(container.read(sellSearchProvider), 'coke');
    expect(container.read(sellCategoryProvider), 'cat-1');

    // resetSellSessionState takes a provider Ref and mutates other
    // providers, which riverpod forbids during a provider's own build — so
    // run it from a probe provider AFTER initialization settles.
    final trigger = Provider<Future<void>>((ref) async {
      await Future<void>.delayed(Duration.zero);
      resetSellSessionState(ref);
    });
    await container.read(trigger);

    expect(container.read(cartProvider).isEmpty, isTrue,
        reason: 'cart holds foreign products after a shop switch');
    expect(container.read(heldSalesProvider), isEmpty,
        reason: 'held carts are the same leak via resume()');
    expect(container.read(sellSearchProvider), '');
    expect(container.read(sellCategoryProvider), isNull);
  });

  test('clearAll drops every held cart but keeps hold/resume usable', () {
    final notifier = HeldSalesNotifier();
    final p = product();
    notifier.hold(CartState(lines: [CartLine(product: p, qty: 1)]));
    notifier.hold(CartState(lines: [CartLine(product: p, qty: 2)]));

    notifier.clearAll();
    expect(notifier.state, isEmpty);

    // And the park/resume flow still works afterwards for the new shop.
    final id = notifier.hold(CartState(lines: [CartLine(product: p, qty: 4)]));
    expect(notifier.resume(id)?.itemCount, 4);
  });
}
