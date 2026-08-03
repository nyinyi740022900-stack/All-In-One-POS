import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';
import '../../data/repositories/inventory_repository.dart';

/// One line of a purchase-order draft being built in the editor — mirrors
/// `OrderDraftLine`, but `productId` is required (a PO line always ties to a
/// real product, since receiving needs one to restock).
class PurchaseOrderDraftLine {
  final String productId;
  final String name;
  final int qty;
  final int unitCost;
  const PurchaseOrderDraftLine({
    required this.productId,
    required this.name,
    required this.qty,
    required this.unitCost,
  });

  int get lineTotal => qty * unitCost;
}

/// Suppliers' purchase orders — lightweight tracking (what was ordered,
/// from whom, at what cost), not procurement automation. See
/// `PurchaseOrders`/`PurchaseOrderItems` in tables.dart.
class PurchaseOrderRepository {
  PurchaseOrderRepository(this._db, this._shopId, this._inventory);

  final AppDatabase _db;
  final String _shopId;
  final InventoryRepository _inventory;
  static const _uuid = Uuid();

  Stream<List<PurchaseOrder>> watchOrders() {
    return (_db.select(_db.purchaseOrders)
          ..where((t) => t.shopId.equals(_shopId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<PurchaseOrder?> getOrder(String id) {
    return (_db.select(_db.purchaseOrders)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Stream<List<PurchaseOrderItem>> items(String poId) {
    return (_db.select(_db.purchaseOrderItems)
          ..where((t) => t.poId.equals(poId) & t.isDeleted.equals(false)))
        .watch();
  }

  Future<String> savePO({
    String? id,
    String? supplierId,
    required String supplierName,
    String? note,
    required List<PurchaseOrderDraftLine> lines,
  }) async {
    final poId = id ?? _uuid.v4();
    final now = DateTime.now();
    final itemsTotal = lines.fold<int>(0, (s, l) => s + l.lineTotal);

    await _db.transaction(() async {
      final existing = await (_db.select(_db.purchaseOrders)
            ..where((t) => t.id.equals(poId)))
          .getSingleOrNull();
      final poNo = existing?.poNo ?? 'PO-${poId.substring(0, 8).toUpperCase()}';

      await _db.into(_db.purchaseOrders).insertOnConflictUpdate(
            PurchaseOrdersCompanion(
              id: Value(poId),
              shopId: Value(_shopId),
              poNo: Value(poNo),
              supplierId: Value(supplierId),
              supplierName: Value(supplierName),
              status: Value(existing?.status ?? 'open'),
              itemsTotal: Value(itemsTotal),
              note: Value(note),
              receivedAt: Value(existing?.receivedAt),
              createdAt: existing == null ? Value(now) : Value(existing.createdAt),
              updatedAt: Value(now),
              dirty: const Value(true),
            ),
          );
      await _enqueuePO(poId);

      // Replace items: tombstone the old set, insert the new one — same
      // pattern as OrdersRepository.saveOrder.
      final old = await (_db.select(_db.purchaseOrderItems)
            ..where((t) => t.poId.equals(poId) & t.isDeleted.equals(false)))
          .get();
      for (final o in old) {
        await (_db.update(_db.purchaseOrderItems)
              ..where((t) => t.id.equals(o.id)))
            .write(PurchaseOrderItemsCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(now),
          dirty: const Value(true),
        ));
        await _enqueue(
            'purchase_order_items', o.id, 'delete', '{"id":"${o.id}"}');
      }
      for (final l in lines) {
        final itemId = _uuid.v4();
        await _db.into(_db.purchaseOrderItems).insert(
              PurchaseOrderItemsCompanion.insert(
                id: itemId,
                shopId: _shopId,
                poId: poId,
                productId: l.productId,
                nameSnapshot: l.name,
                qty: l.qty,
                unitCost: l.unitCost,
                lineTotal: l.lineTotal,
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
        await _enqueue(
            'purchase_order_items',
            itemId,
            'upsert',
            jsonEncode((await (_db.select(_db.purchaseOrderItems)
                      ..where((t) => t.id.equals(itemId)))
                    .getSingle())
                .toJson()));
      }
    });
    return poId;
  }

  /// All-or-nothing: adds every line's ordered qty to stock at its ordered
  /// cost via the existing `InventoryRepository.adjustStock` (the same
  /// method a manual restock already calls), then marks the PO received.
  /// Idempotent — a PO already received is left untouched, same dedupe
  /// guard `OrdersRepository.convertToSale` uses.
  Future<void> receivePO(String poId) async {
    final po = await getOrder(poId);
    if (po == null || po.status == 'received') return;

    final lines = await (_db.select(_db.purchaseOrderItems)
          ..where((t) => t.poId.equals(poId) & t.isDeleted.equals(false)))
        .get();
    for (final l in lines) {
      await _inventory.adjustStock(
        productId: l.productId,
        delta: l.qty,
        type: 'purchase',
        unitCost: l.unitCost,
        note: 'PO ${po.poNo}',
      );
    }

    final now = DateTime.now();
    await (_db.update(_db.purchaseOrders)..where((t) => t.id.equals(poId)))
        .write(PurchaseOrdersCompanion(
      status: const Value('received'),
      receivedAt: Value(now),
      updatedAt: Value(now),
      dirty: const Value(true),
    ));
    await _enqueuePO(poId);
  }

  /// A cancelled PO never touches stock — this is the only other terminal
  /// status besides `received`.
  Future<void> cancelPO(String poId) async {
    final now = DateTime.now();
    await (_db.update(_db.purchaseOrders)..where((t) => t.id.equals(poId)))
        .write(PurchaseOrdersCompanion(
      status: const Value('cancelled'),
      updatedAt: Value(now),
      dirty: const Value(true),
    ));
    await _enqueuePO(poId);
  }

  /// Only meaningful while still `open` — the UI doesn't offer this once a
  /// PO has been received (an immutable record of what actually happened to
  /// stock, same as a finalized Sale).
  Future<void> deletePO(String poId) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.purchaseOrders)..where((t) => t.id.equals(poId)))
          .write(PurchaseOrdersCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueuePO(poId);

      final lines = await (_db.select(_db.purchaseOrderItems)
            ..where((t) => t.poId.equals(poId) & t.isDeleted.equals(false)))
          .get();
      for (final l in lines) {
        await (_db.update(_db.purchaseOrderItems)
              ..where((t) => t.id.equals(l.id)))
            .write(PurchaseOrderItemsCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(now),
          dirty: const Value(true),
        ));
        await _enqueue(
            'purchase_order_items', l.id, 'delete', '{"id":"${l.id}"}');
      }
    });
  }

  Future<void> _enqueuePO(String poId) async {
    final row = await (_db.select(_db.purchaseOrders)
          ..where((t) => t.id.equals(poId)))
        .getSingle();
    await _enqueue('purchase_orders', poId, 'upsert', jsonEncode(row.toJson()));
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
