import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/domain/product_with_stock.dart';
import 'package:mm_pos/features/inventory/inventory_csv.dart';

Product _product({
  required String id,
  required String name,
  String? sku,
  String? barcode,
  String? categoryId,
  int costPrice = 0,
  int salePrice = 0,
}) {
  final now = DateTime(2026, 1, 1);
  return Product(
    id: id,
    shopId: 'shop-1',
    createdAt: now,
    updatedAt: now,
    isDeleted: false,
    dirty: false,
    name: name,
    sku: sku,
    barcode: barcode,
    categoryId: categoryId,
    costPrice: costPrice,
    salePrice: salePrice,
    unit: 'pcs',
    isActive: true,
    sellOnline: true,
  );
}

void main() {
  const headers = (
    nameHeader: 'Name',
    skuHeader: 'SKU',
    barcodeHeader: 'Barcode',
    categoryHeader: 'Category',
    costPriceHeader: 'Cost',
    salePriceHeader: 'Price',
    quantityHeader: 'Qty',
    reorderLevelHeader: 'Reorder',
  );

  test('renders header + one row per product, resolving category names', () {
    final products = [
      ProductWithStock(
        product: _product(
            id: 'p1', name: 'Coke', sku: 'C1', categoryId: 'cat-1', salePrice: 700),
        quantity: 10,
        reorderLevel: 3,
      ),
      ProductWithStock(
        product: _product(id: 'p2', name: 'Rice bag', costPrice: 5000),
        quantity: 2,
        reorderLevel: 0,
      ),
    ];
    final csv = buildInventoryCsv(
      products,
      {'cat-1': 'Drinks'},
      nameHeader: headers.nameHeader,
      skuHeader: headers.skuHeader,
      barcodeHeader: headers.barcodeHeader,
      categoryHeader: headers.categoryHeader,
      costPriceHeader: headers.costPriceHeader,
      salePriceHeader: headers.salePriceHeader,
      quantityHeader: headers.quantityHeader,
      reorderLevelHeader: headers.reorderLevelHeader,
    );
    final lines = csv.split('\r\n');
    expect(lines[0], 'Name,SKU,Barcode,Category,Cost,Price,Qty,Reorder');
    expect(lines, contains('Coke,C1,,Drinks,0,700,10,3'));
    expect(lines, contains('Rice bag,,,,5000,0,2,0'));
  });

  test('a product with no category prints an empty category field', () {
    final products = [
      ProductWithStock(
        product: _product(id: 'p1', name: 'Loose item', categoryId: 'missing'),
        quantity: 1,
        reorderLevel: 0,
      ),
    ];
    final csv = buildInventoryCsv(
      products,
      const {},
      nameHeader: headers.nameHeader,
      skuHeader: headers.skuHeader,
      barcodeHeader: headers.barcodeHeader,
      categoryHeader: headers.categoryHeader,
      costPriceHeader: headers.costPriceHeader,
      salePriceHeader: headers.salePriceHeader,
      quantityHeader: headers.quantityHeader,
      reorderLevelHeader: headers.reorderLevelHeader,
    );
    expect(csv, contains('Loose item,,,,0,0,1,0'));
  });
}
