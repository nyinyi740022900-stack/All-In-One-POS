import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/sell/cart.dart';

Product _product(String id,
        {int price = 1000, int? wholesalePrice, int? vipPrice}) =>
    Product(
      id: id,
      shopId: 'shop-1',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      isDeleted: false,
      dirty: true,
      name: 'P-$id',
      costPrice: 0,
      salePrice: price,
      wholesalePrice: wholesalePrice,
      vipPrice: vipPrice,
      unit: 'pcs',
      isActive: true,
    );

void main() {
  test('addProduct without a cap keeps incrementing', () {
    final cart = CartNotifier();
    final p = _product('a');
    expect(cart.addProduct(p), isTrue);
    expect(cart.addProduct(p), isTrue);
    expect(cart.state.lines.single.qty, 2);
  });

  test('addProduct caps at maxQty (no overselling)', () {
    final cart = CartNotifier();
    final p = _product('a');
    expect(cart.addProduct(p, maxQty: 2), isTrue);
    expect(cart.addProduct(p, maxQty: 2), isTrue);
    // Third add is refused — already at available stock.
    expect(cart.addProduct(p, maxQty: 2), isFalse);
    expect(cart.state.lines.single.qty, 2);
  });

  test('addProduct with maxQty 0 (out of stock) refuses immediately', () {
    final cart = CartNotifier();
    expect(cart.addProduct(_product('a'), maxQty: 0), isFalse);
    expect(cart.state.lines, isEmpty);
  });

  test('increment respects the cap', () {
    final cart = CartNotifier();
    final p = _product('a');
    cart.addProduct(p);
    expect(cart.increment('a', maxQty: 2), isTrue); // -> 2
    expect(cart.increment('a', maxQty: 2), isFalse); // at cap
    expect(cart.state.lines.single.qty, 2);
  });

  group('resolveUnitPrice', () {
    test('falls back to salePrice with no tier or no override', () {
      final p = _product('a', price: 1000, wholesalePrice: 800);
      expect(resolveUnitPrice(p, null), 1000);
      expect(resolveUnitPrice(p, 'retail'), 1000);
      expect(resolveUnitPrice(p, 'vip'), 1000); // no vipPrice set
    });

    test('picks the tier-specific price when set', () {
      final p =
          _product('a', price: 1000, wholesalePrice: 800, vipPrice: 900);
      expect(resolveUnitPrice(p, 'wholesale'), 800);
      expect(resolveUnitPrice(p, 'vip'), 900);
    });
  });

  test('cart totals react to customerTier without touching the lines', () {
    final cart = CartNotifier();
    final p = _product('a', price: 1000, wholesalePrice: 800);
    cart.addProduct(p, maxQty: 5);
    cart.increment('a', maxQty: 5); // qty 2

    expect(cart.state.subtotal.kyat, 2000); // retail default

    cart.setCustomerTier('wholesale');
    expect(cart.state.subtotal.kyat, 1600);
    expect(cart.state.lines.single.qty, 2); // lines themselves unchanged

    cart.setCustomerTier(null);
    expect(cart.state.subtotal.kyat, 2000); // back to retail
  });

  test('clear() resets customerTier back to retail', () {
    final cart = CartNotifier();
    cart.addProduct(_product('a', price: 1000, wholesalePrice: 800));
    cart.setCustomerTier('wholesale');
    cart.clear();
    expect(cart.state.customerTier, isNull);
  });

  group('per-item discount', () {
    test('setLineDiscount reduces just that line\'s total', () {
      final cart = CartNotifier();
      cart.addProduct(_product('a', price: 1000)); // qty 1
      cart.addProduct(_product('b', price: 500));
      cart.setLineDiscount('a', 200);

      final lineA = cart.state.lines.firstWhere((l) => l.product.id == 'a');
      final lineB = cart.state.lines.firstWhere((l) => l.product.id == 'b');
      expect(cart.state.lineTotalFor(lineA).kyat, 800);
      expect(cart.state.lineTotalFor(lineB).kyat, 500); // untouched
      expect(cart.state.subtotal.kyat, 1300);
      expect(cart.state.total.kyat, 1300);
    });

    test('a discount larger than the line total clamps to zero, not negative',
        () {
      final cart = CartNotifier();
      cart.addProduct(_product('a', price: 1000));
      cart.setLineDiscount('a', 5000);

      final line = cart.state.lines.single;
      expect(cart.state.lineTotalFor(line).kyat, 0);
      expect(cart.state.subtotal.kyat, 0);
    });

    test('negative input is clamped to 0 (no discount)', () {
      final cart = CartNotifier();
      cart.addProduct(_product('a', price: 1000));
      cart.setLineDiscount('a', -50);
      expect(cart.state.lines.single.discount, 0);
    });

    test('order-level discount still applies on top of per-item discounts',
        () {
      final cart = CartNotifier();
      cart.addProduct(_product('a', price: 1000));
      cart.setLineDiscount('a', 200); // line total 800
      cart.setDiscount(100); // order-level, on top
      expect(cart.state.subtotal.kyat, 800);
      expect(cart.state.total.kyat, 700);
    });
  });
}
