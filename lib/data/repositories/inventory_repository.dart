
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
      // `stock_levels` is keyed by row id, not product_id — a second cache
      // row for the same product (sync inserting a new id, then pulling the
      // original) would otherwise list that product twice. Collapse to one
      // row per product, keeping the newest stock cache.
      final products = <String, Product>{};
      final bestStock = <String, StockLevel?>{};
      for (final row in rows) {
        final product = row.readTable(_db.products);
        final stock = row.readTableOrNull(_db.stockLevels);
        products[product.id] = product;
        final prev = bestStock[product.id];
        if (prev == null ||
            (stock != null && stock.updatedAt.isAfter(prev.updatedAt))) {
          bestStock[product.id] = stock;
        }
      }
      return [
        for (final e in products.entries)
          ProductWithStock(
            product: e.value,
            quantity: bestStock[e.key]?.quantity ?? 0,
            reorderLevel: bestStock[e.key]?.reorderLevel ?? 0,
          ),
      ];
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

  /// Newest-first stock movement ledger across *every* product (shop-wide),
  /// optionally bounded to `[start, end)` — the Inventory tab's "Stock
  /// history" screen. See [watchStockMovements] for why this orders by
  /// `rowid` rather than `createdAt`.
  Stream<List<StockMovement>> watchAllMovements({
    DateTime? start,
    DateTime? end,
  }) {
    return (_db.select(_db.stockMovements)
          ..where((m) {
            var pred = m.shopId.equals(_shopId);
            if (start != null) {
              pred = pred & m.createdAt.isBiggerOrEqualValue(start);
            }
            if (end != null) {
              pred = pred & m.createdAt.isSmallerThanValue(end);
            }
            return pred;
          })
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
    int? onlineStockLimit,
    bool sellOnline = true,
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
        onlineStockLimit: Value(onlineStockLimit),
        sellOnline: Value(sellOnline),
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
      await _enqueue('products', productId, 'upsert');

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
      if (newQuantity < 0) {
        throw StateError(
            'adjustStock: delta $delta would take stock below zero '
            '(currently ${existing?.quantity ?? 0})');
      }

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
            // Explicit timestamp (not the SQL CURRENT_TIMESTAMP default) so
            // insertion order, not statement time, decides. Note Drift still
            // stores DateTime truncated to whole seconds — sub-second
            // precision does NOT survive; same-second rows are ordered
            // deterministically by rowid in the history views instead.
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
      await _enqueue('stock_movements', moveId, 'upsert');

      await _db.into(_db.stockLevels).insertOnConflictUpdate(StockLevelsCompanion(
            id: Value(rowId),
            shopId: Value(_shopId),
            productId: Value(productId),
            quantity: Value(newQuantity),
            reorderLevel: Value(existing?.reorderLevel ?? 0),
            updatedAt: Value(now),
            dirty: const Value(true),
          ));
      // NOTE: no stock_levels outbox enqueue here — `quantity` is a counter
      // and must never sync as an absolute LWW value; only genuine
      // reorder-level edits are pushed (see _setStockLevel).
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
      await _enqueue('products', productId, 'delete');
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
      await _enqueue('categories', categoryId, 'upsert');
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
      await _enqueue('categories', categoryId, 'delete');
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
            // See the note in adjustStock: explicit timestamp, but Drift
            // truncates to whole seconds — history ordering relies on the
            // views' rowid tie-breaker, not sub-second precision.
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
      await _enqueue('stock_movements', moveId, 'upsert');
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
    // Push the level row ONLY when it's new or the reorder level actually
    // changed — those carry real settings. `quantity` is a device-reconciled
    // counter (see adjustStock's NOTE + sync_mappers.dart's _stockLevels).
    if (existing == null || existing.reorderLevel != reorderLevel) {
      await _enqueue('stock_levels', rowId, 'upsert');
    }
  }

  Future<void> _enqueue(String table, String rowId, String op) {
    return _db.into(_db.outbox).insert(OutboxCompanion.insert(
          entityTable: table,
          rowId: rowId,
          op: op,
        ));
  }
}
