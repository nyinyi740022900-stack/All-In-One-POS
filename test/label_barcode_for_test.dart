import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/inventory/inventory_screen.dart';

void main() {
  Product product({String? barcode, String? sku}) {
    final now = DateTime(2026, 1, 1);
    return Product(
      id: 'p1',
      shopId: 'shop-1',
      createdAt: now,
      updatedAt: now,
      isDeleted: false,
      dirty: true,
      name: 'Coke',
      sku: sku,
      barcode: barcode,
      costPrice: 500,
      salePrice: 700,
      unit: 'pcs',
      isActive: true,
    );
  }

  test('prefers the real barcode when set', () {
    expect(labelBarcodeFor(product(barcode: '8901234', sku: 'SKU1')),
        '8901234');
  });

  test('falls back to sku when barcode is blank', () {
    expect(labelBarcodeFor(product(barcode: '  ', sku: 'SKU1')), 'SKU1');
  });

  test('falls back to the product id when neither is set', () {
    expect(labelBarcodeFor(product()), 'p1');
  });
}
