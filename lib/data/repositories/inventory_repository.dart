import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/product_with_stock.dart';
import '../local/database.dart';
import 'stock_lots.dart';

/// Offline-first inventory repository.
///
/// Every mutation writes to the local Drift database (the device source of
/// truth) inside a transaction, and enqueues the change into the [Outbox] so
/// the SyncEngine (Phase 4) can push it to Supabase when online. The UI reads
/// via reactive streams and never blocks on the network.
class InventoryRepository {
  InventoryRepository(this._db, this._shopId);

  final AppDatabase _db;
  final String _shopId;
  static const _uuid = Uuid();

  // ---- Reads -------------------------------------------------------------

  /// Streams active products with their current stock, newest first.
  Stream<List<ProductWithStock>> watchProducts() {
    final query = _db.select(_db.products).join([
      leftOuterJoin(
        _db.stockLevels,
        _db.stockLevels.productId.equalsExp(_db.products.id),
      ),
    ])
      ..where(_db.products.isDeleted.equals(false) &
          _db.products.shopId.equals(_shopId))
      ..orderBy([OrderingTerm.desc(_db.products.createdAt)]);

    return query.watch().map((rows) {
      return rows.map((row) {
        final product = row.readTable(_db.products);
        final stock = row.readTableOrNull(_db.stockLevels);
        return ProductWithStock(
          product: product,
          quantity: stock?.quantity ?? 0,
          reorderLevel: stock?.reorderLevel ?? 0,
        );
      }).toList();
    });
  }

  Stream<List<Category>> watchCategories() {
    return (_db.select(_db.categories)
          ..where((c) => c.isDeleted.equals(false) & c.shopId.equals(_shopId))
          ..orderBy([(c) => OrderingTerm(expression: c.sort)]))
        .watch();
  }

  /// Newest-first stock movement ledger for one product (restocks,
  /// adjustments, sales, returns, opening balance) — read-only history.
  ///
  /// Orders by SQLite's implicit `rowid` rather than `createdAt`: drift
  /// stores `DateTime` as a unix timestamp with **second** precision, so two
  /// movements written within the same second (routine for back-to-back
  /// restock/adjust taps) would otherwise tie and sort arbitrarily. `rowid`
  /// always increases with insertion order, so it's a free, exact
  /// chronological tiebreaker with no schema change needed.
  Stream<List<StockMovement>> watchStockMovements(String productId) {
    return (_db.select(_db.stockMovements)
          ..where((m) =>
              m.productId.equals(productId) & m.shopId.equals(_shopId))
          ..orderBy([
            (_) => OrderingTerm(
                expression: const CustomExpression<int>('rowid'),
                mode: OrderingMode.desc)
          ]))
        .watch();
  }

  // ---- Writes ------------------------------------------------------------

  /// Creates or updates a product and (optionally) its stock level.
  Future<String> upsertProduct({
    String? id,
    required String name,
    String? sku,
    String? barcode,
    String? categoryId,
    int costPrice = 0,
    int salePrice = 0,
    int? wholesalePrice,
    int? vipPrice,
    String unit = 'pcs',
    int? quantity,
    int reorderLevel = 0,
    String? imageUrl,
  }) async {
    final productId = id ?? _uuid.v4();
    final now = DateTime.now();

    await _db.transaction(() async {
      final companion = ProductsCompanion(
        id: Value(productId),
        shopId: Value(_shopId),
        name: Value(name),
        sku: Value(sku),
        barcode: Value(barcode),
        categoryId: Value(categoryId),
        costPrice: Value(costPrice),
        salePrice: Value(salePrice),
        wholesalePrice: Value(wholesalePrice),
        vipPrice: Value(vipPrice),
        unit: Value(unit),
        // Only overwrite the photo URL when one is supplied (keep existing).
        imageUrl: imageUrl == null ? const Value.absent() : Value(imageUrl),
        isActive: const Value(true),
        updatedAt: Value(now),
        dirty: const Value(true),
      );
      await _db
          .into(_db.products)
          .insertOnConflictUpdate(companion);
      await _enqueue('products', productId, 'upsert',
          (await _productJson(productId)));

      if (quantity != null) {
        await _setStockLevel(productId, quantity, reorderLevel, now, costPrice);
      }
    });

    return productId;
  }

  /// Records a stock change as a proper ledger entry (restock or a manual
  /// correction), unlike [upsertProduct]'s `quantity` param which silently
  /// sets an absolute value with no reason captured. [type] is `'purchase'`
  /// for a restock or `'adjustment'` for a correction; [delta] is signed
  /// (positive = increase, negative = decrease) and must be non-zero.
  ///
  /// [unitCost] is the cost basis for a positive delta (what this batch was
  /// bought/found at) — defaults to the product's current [Product.costPrice]
  /// when not given. A negative delta instead consumes existing FIFO lots
  /// (oldest first), keeping the lot ledger in step with the cached quantity.
  Future<void> adjustStock({
    required String productId,
    required int delta,
    required String type,
    String? note,
    int? unitCost,
  }) async {
    if (delta == 0) throw ArgumentError('delta must be non-zero');
    final now = DateTime.now();

    await _db.transaction(() async {
      final existing = await (_db.select(_db.stockLevels)
            ..where((s) => s.productId.equals(productId)))
          .getSingleOrNull();
      final rowId = existing?.id ?? _uuid.v4();
      final newQuantity = (existing?.quantity ?? 0) + delta;

      final product =
          await (_db.select(_db.products)..where((p) => p.id.equals(productId)))
              .getSingle();
      if (delta > 0) {
        await pushStockLot(_db,
            productId: productId,
            qty: delta,
            unitCost: unitCost ?? product.costPrice);
      } else {
        await consumeStockLots(_db,
            productId: productId,
            qty: -delta,
            fallbackUnitCost: product.costPrice);
      }

      final moveId = _uuid.v4();
      await _db.into(_db.stockMovements).insert(StockMovementsCompanion.insert(
            id: moveId,
            shopId: _shopId,
            productId: productId,
            type: type,
            qtyDelta: delta,
            unitCost: Value(delta > 0 ? (unitCost ?? product.costPrice) : 0),
            note: Value(note),
            // Explicit microsecond-precision timestamp — the column default
            // (SQL CURRENT_TIMESTAMP) only has second accuracy, which makes
            // same-second movements sort inconsistently in the history view.
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
      await _enqueue('stock_movements', moveId, 'upsert', jsonEncode(
          (await (_db.select(_db.stockMovements)
                    ..where((m) => m.id.equals(moveId)))
                  .getSingle())
              .toJson()));

      await _db.into(_db.stockLevels).insertOnConflictUpdate(StockLevelsCompanion(
            id: Value(rowId),
            shopId: Value(_shopId),
            productId: Value(productId),
            quantity: Value(newQuantity),
            reorderLevel: Value(existing?.reorderLevel ?? 0),
            updatedAt: Value(now),
            dirty: const Value(true),
          ));
      final row = await (_db.select(_db.stockLevels)
            ..where((s) => s.id.equals(rowId)))
          .getSingle();
      await _enqueue(
          'stock_levels', rowId, 'upsert', jsonEncode(row.toJson()));
    });
  }

  Future<void> deleteProduct(String productId) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.products)..where((p) => p.id.equals(productId)))
          .write(ProductsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueue('products', productId, 'delete', '{"id":"$productId"}');
    });
  }

  Future<String> upsertCategory({String? id, required String name, int sort = 0}) async {
    final categoryId = id ?? _uuid.v4();
    final companion = CategoriesCompanion(
      id: Value(categoryId),
      shopId: Value(_shopId),
      name: Value(name),
      sort: Value(sort),
      updatedAt: Value(DateTime.now()),
      dirty: const Value(true),
    );
    await _db.transaction(() async {
      await _db.into(_db.categories).insertOnConflictUpdate(companion);
      final row = await (_db.select(_db.categories)
            ..where((c) => c.id.equals(categoryId)))
          .getSingle();
      await _enqueue('categories', categoryId, 'upsert', jsonEncode(row.toJson()));
    });
    return categoryId;
  }

  /// Tombstones a category. Products keep their `categoryId`; they simply show
  /// as uncategorized until reassigned.
  Future<void> deleteCategory(String categoryId) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.categories)..where((c) => c.id.equals(categoryId)))
          .write(CategoriesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueue(
          'categories', categoryId, 'delete', '{"id":"$categoryId"}');
    });
  }

  // ---- Internals ---------------------------------------------------------

  Future<void> _setStockLevel(String productId, int quantity, int reorderLevel,
      DateTime now, int costPrice) async {
    final existing = await (_db.select(_db.stockLevels)
          ..where((s) => s.productId.equals(productId)))
        .getSingleOrNull();
    final rowId = existing?.id ?? _uuid.v4();

    // Record the change as an append-only movement so the ledger is complete:
    // opening balance on create, adjustment on later edits. The ledger (which
    // syncs append-only, never LWW) is the authoritative history — this is the
    // basis for cross-channel stock reconciliation once a 2nd writer (the web
    // storefront) exists. The cached level below is a fast-read denormalization.
    final delta = quantity - (existing?.quantity ?? 0);
    if (delta != 0) {
      if (delta > 0) {
        await pushStockLot(_db,
            productId: productId, qty: delta, unitCost: costPrice);
      } else {
        await consumeStockLots(_db,
            productId: productId, qty: -delta, fallbackUnitCost: costPrice);
      }

      final moveId = _uuid.v4();
      await _db.into(_db.stockMovements).insert(StockMovementsCompanion.insert(
            id: moveId,
            shopId: _shopId,
            productId: productId,
            type: existing == null ? 'opening' : 'adjustment',
            qtyDelta: delta,
            unitCost: Value(delta > 0 ? costPrice : 0),
            note: const Value('manual stock set'),
            // See the same note in adjustStock: an explicit timestamp avoids
            // SQL CURRENT_TIMESTAMP's second-level tie-breaking in history.
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
      await _enqueue('stock_movements', moveId, 'upsert', jsonEncode(
          (await (_db.select(_db.stockMovements)..where((m) => m.id.equals(moveId)))
                  .getSingle())
              .toJson()));
    }

    await _db.into(_db.stockLevels).insertOnConflictUpdate(StockLevelsCompanion(
          id: Value(rowId),
          shopId: Value(_shopId),
          productId: Value(productId),
          quantity: Value(quantity),
          reorderLevel: Value(reorderLevel),
          updatedAt: Value(now),
          dirty: const Value(true),
        ));
    final row = await (_db.select(_db.stockLevels)
          ..where((s) => s.id.equals(rowId)))
        .getSingle();
    await _enqueue('stock_levels', rowId, 'upsert', jsonEncode(row.toJson()));
  }

  Future<String> _productJson(String productId) async {
    final row = await (_db.select(_db.products)
          ..where((p) => p.id.equals(productId)))
        .getSingle();
    return jsonEncode(row.toJson());
  }

  Future<void> _enqueue(
      String table, String rowId, String op, String payload) {
    return _db.into(_db.outbox).insert(OutboxCompanion.insert(
          entityTable: table,
          rowId: rowId,
          op: op,
          payload: payload,
        ));
  }
}
