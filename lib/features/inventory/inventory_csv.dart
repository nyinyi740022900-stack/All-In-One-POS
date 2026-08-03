import '../../core/csv_util.dart';
import '../../domain/product_with_stock.dart';

/// Pure: renders the current product list (with stock) as CSV, for handing
/// off to an accountant or a stock take in a spreadsheet — alongside the
/// existing label-printing/backup export paths. [categoryNameById] resolves
/// each product's `categoryId`; a product with no category (or one not
/// found, e.g. deleted) prints an empty category field.
String buildInventoryCsv(
  List<ProductWithStock> products,
  Map<String, String> categoryNameById, {
  required String nameHeader,
  required String skuHeader,
  required String barcodeHeader,
  required String categoryHeader,
  required String costPriceHeader,
  required String salePriceHeader,
  required String quantityHeader,
  required String reorderLevelHeader,
}) {
  return csvDocument(
    [
      nameHeader,
      skuHeader,
      barcodeHeader,
      categoryHeader,
      costPriceHeader,
      salePriceHeader,
      quantityHeader,
      reorderLevelHeader,
    ],
    [
      for (final p in products)
        [
          p.product.name,
          p.product.sku ?? '',
          p.product.barcode ?? '',
          categoryNameById[p.product.categoryId] ?? '',
          p.product.costPrice,
          p.product.salePrice,
          p.quantity,
          p.reorderLevel,
        ],
    ],
  );
}
