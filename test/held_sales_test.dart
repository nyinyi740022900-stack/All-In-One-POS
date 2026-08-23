import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/sell/cart.dart';
import 'package:mm_pos/features/sell/held_sales_provider.dart';

Product _product(String id, {int price = 1000}) => Product(
      id: id,
      shopId: 'shop-1',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      isDeleted: false,
      dirty: true,
      name: 'P-$id',
      costPrice: 0,
      salePrice: price,
      unit: 'pcs',
      isActive: true,
    );

CartState _cart(String productId, {int qty = 1, int discount = 0}) {
  final cart = CartNotifier();
  cart.addProduct(_product(productId));
  for (var i = 1; i < qty; i++) {
    cart.increment(productId);
  }
  if (discount > 0) cart.setDiscount(discount);
  return cart.state;
}

void main() {
  test('hold prepends and returns an id', () {
    final held = HeldSalesNotifier();
    final a = held.hold(_cart('a'));
    final b = held.hold(_cart('b', qty: 2));
    expect(a, isNot(b));
    expect(held.state.first.id, b); // newest first
    expect(held.state.length, 2);
  });

  test('resume removes and returns the cart intact (lines + discount)', () {
    final held = HeldSalesNotifier();
    final id = held.hold(_cart('a', qty: 3, discount: 500));
    final restored = held.resume(id);
    expect(restored, isNotNull);
    expect(restored!.lines.single.qty, 3);
    expect(restored.discount, 500);
    expect(held.state, isEmpty);
  });

  test('resume of an unknown id returns null without touching state', () {
    final held = HeldSalesNotifier();
    held.hold(_cart('a'));
    expect(held.resume('nope'), isNull);
    expect(held.state.length, 1);
  });

  test('remove deletes just that entry', () {
    final held = HeldSalesNotifier();
    final a = held.hold(_cart('a'));
    held.hold(_cart('b'));
    held.remove(a);
    expect(held.state.length, 1);
    expect(held.state.single.cart.lines.single.product.id, 'b');
  });

  test('CartNotifier.restore replaces the whole cart state', () {
    final cart = CartNotifier();
    cart.addProduct(_product('x'));
    cart.restore(_cart('a', qty: 2));
    expect(cart.state.lines.single.product.id, 'a');
    expect(cart.state.lines.single.qty, 2);
  });
}
