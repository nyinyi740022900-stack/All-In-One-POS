import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';

/// Order pipeline statuses. Deliberately just two — `new` (received, not yet
/// handed to a carrier) and `delivered` (handed off) — collapsed from an
/// earlier 5-stage Confirmed/Packed/Shipped pipeline that Myanmar shop owners
/// found confusing in practice; a Myanmar retail order's real lifecycle is
/// "arrived" then "gone to the courier," not a multi-step warehouse flow.
/// `cancelled` is a separate terminal state reachable from an order's actions.
const orderStatuses = <String>[
  'new',
  'delivered',
];

/// Social channels an order can come from. (Instagram dropped — not commonly
/// used for order-taking by Myanmar shops.)
const orderChannels = <String>[
  'facebook',
  'viber',
  'tiktok',
  'phone',
  'other',
];

/// A line the caller wants on an order, before it is persisted. A line may
/// reference a catalog product ([productId]) or be a free-text item.
class OrderDraftLine {
  final String? productId;
  final String name;
  final int price;
  final int qty;
  const OrderDraftLine({
    this.productId,
    required this.name,
    required this.price,
    required this.qty,
  });
  int get lineTotal => price * qty;
}

/// Persists social-channel orders and moves them through the Kanban pipeline.
///
/// Orders are **mutable** (status + items change), so — unlike sales — they
/// sync last-write-wins. Stock is only ever touched by [convertToSale], which
/// writes the append-only sale + stock movements once, mirroring
/// `SalesRepository`. Every mutation writes local + enqueues to the outbox.
class OrdersRepository {
  OrdersRepository(this._db, this._shopId);

  final AppDatabase _db;
  final String _shopId;
  static const _uuid = Uuid();

  Stream<List<Order>> watchOrders() {
    return (_db.select(_db.orders)
          ..where((o) => o.shopId.equals(_shopId) & o.isDeleted.equals(false))
          ..orderBy([(o) => OrderingTerm.desc(o.updatedAt)]))
        .watch();
  }

  Future<Order> getOrder(String id) =>
      (_db.select(_db.orders)..where((o) => o.id.equals(id))).getSingle();

  Future<List<OrderItem>> items(String orderId) {
    return (_db.select(_db.orderItems)
          ..where((i) => i.orderId.equals(orderId) & i.isDeleted.equals(false))
          ..orderBy([(i) => OrderingTerm(expression: i.createdAt)]))
        .get();
  }

  /// Creates a new order (no [id]) or edits an existing one. Header fields are
  /// upserted and the item set is fully replaced. Returns the order id.
  Future<String> saveOrder({
    String? id,
    required String customerName,
    String? customerPhone,
    String? customerId,
    required String channel,
    String? deliveryAddress,
    int deliveryFee = 0,
    String? note,
    required List<OrderDraftLine> lines,
  }) async {
    final orderId = id ?? _uuid.v4();
    final now = DateTime.now();
    final itemsTotal = lines.fold<int>(0, (s, l) => s + l.lineTotal);

    await _db.transaction(() async {
      final existing = await (_db.select(_db.orders)
            ..where((o) => o.id.equals(orderId)))
          .getSingleOrNull();
      final orderNo = existing?.orderNo ?? await _nextOrderNo(now);

      await _db.into(_db.orders).insertOnConflictUpdate(OrdersCompanion(
            id: Value(orderId),
            shopId: Value(_shopId),
            orderNo: Value(orderNo),
            channel: Value(channel),
            status: Value(existing?.status ?? 'new'),
            customerName: Value(customerName),
            customerPhone: Value(customerPhone),
            customerId: Value(customerId),
            deliveryAddress: Value(deliveryAddress),
            deliveryFee: Value(deliveryFee),
            itemsTotal: Value(itemsTotal),
            paymentStatus: Value(existing?.paymentStatus ?? 'unpaid'),
            note: Value(note),
            saleId: Value(existing?.saleId),
            createdAt: existing == null ? Value(now) : Value(existing.createdAt),
            updatedAt: Value(now),
            dirty: const Value(true),
          ));
      await _enqueueOrder(orderId);

      // Replace items: tombstone the old set, insert the new one.
      final old = await (_db.select(_db.orderItems)
            ..where((i) => i.orderId.equals(orderId) & i.isDeleted.equals(false)))
          .get();
      for (final o in old) {
        await (_db.update(_db.orderItems)..where((i) => i.id.equals(o.id)))
            .write(OrderItemsCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(now),
          dirty: const Value(true),
        ));
        await _enqueue('order_items', o.id, 'delete', '{"id":"${o.id}"}');
      }
      for (final l in lines) {
        final itemId = _uuid.v4();
        await _db.into(_db.orderItems).insert(OrderItemsCompanion.insert(
              id: itemId,
              shopId: _shopId,
              orderId: orderId,
              productId: Value(l.productId),
              nameSnapshot: l.name,
              priceSnapshot: l.price,
              qty: l.qty,
              lineTotal: l.lineTotal,
              updatedAt: Value(now),
            ));
        await _enqueue('order_items', itemId, 'upsert', jsonEncode(
            (await _one(_db.orderItems, (t) => t.id.equals(itemId))).toJson()));
      }
    });
    return orderId;
  }

  /// Moves an order to a new Kanban [status] (drag between columns).
  Future<void> setStatus(String orderId, String status) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.orders)..where((o) => o.id.equals(orderId)))
          .write(OrdersCompanion(
        status: Value(status),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueueOrder(orderId);
    });
  }

  Future<void> setPaymentStatus(String orderId, String paymentStatus) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.orders)..where((o) => o.id.equals(orderId)))
          .write(OrdersCompanion(
        paymentStatus: Value(paymentStatus),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueueOrder(orderId);
    });
  }

  /// Records delivery info for an order: township, assigned carrier, a
  /// manually-entered tracking number, and the delivery-leg status. Pass only
  /// what changed; omitted fields are left as-is.
  Future<void> setDelivery(
    String orderId, {
    String? township,
    String? carrier,
    String? trackingNumber,
    String? deliveryStatus,
  }) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.orders)..where((o) => o.id.equals(orderId)))
          .write(OrdersCompanion(
        township: township == null ? const Value.absent() : Value(township),
        deliveryCarrier:
            carrier == null ? const Value.absent() : Value(carrier),
        trackingNumber: trackingNumber == null
            ? const Value.absent()
            : Value(trackingNumber),
        deliveryStatus: deliveryStatus == null
            ? const Value.absent()
            : Value(deliveryStatus),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueueOrder(orderId);
    });
  }

  /// The primary "I gave this to the courier" action: records which carrier
  /// it went with and advances the order straight to `delivered` in one
  /// atomic write — the single step a shop owner needs, instead of
  /// separately picking a carrier then moving the pipeline stage. This is
  /// also what unlocks [convertToSale] (`status == 'delivered'`).
  Future<void> handOffToCarrier(String orderId, {required String carrier}) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.orders)..where((o) => o.id.equals(orderId)))
          .write(OrdersCompanion(
        deliveryCarrier: Value(carrier),
        status: const Value('delivered'),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueueOrder(orderId);
    });
  }

  /// Tombstones the order and its items.
  Future<void> deleteOrder(String orderId) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.orders)..where((o) => o.id.equals(orderId)))
          .write(OrdersCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueue('orders', orderId, 'delete', '{"id":"$orderId"}');

      final its = await (_db.select(_db.orderItems)
            ..where((i) => i.orderId.equals(orderId)))
          .get();
      for (final it in its) {
        await (_db.update(_db.orderItems)..where((i) => i.id.equals(it.id)))
            .write(OrderItemsCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(now),
          dirty: const Value(true),
        ));
        await _enqueue('order_items', it.id, 'delete', '{"id":"${it.id}"}');
      }
    });
  }

  /// Converts a delivered order into an append-only [Sales] row (+ items,
  /// payment, and stock movements). Idempotent: returns the existing sale id if
  /// already converted. This is the ONLY path that writes stock for an order.
  Future<String> convertToSale(
    String orderId, {
    String paymentMethod = 'cash',
    bool trackStock = true,
  }) async {
    final order = await getOrder(orderId);
    if (order.saleId != null) return order.saleId!;

    final lines = await items(orderId);
    final saleId = _uuid.v4();
    final now = DateTime.now();
    // Delivery fee folds into the sale subtotal (it isn't a line item and has
    // no discount), so the `subtotal − discount = total` invariant holds.
    final total = order.itemsTotal + order.deliveryFee;

    await _db.transaction(() async {
      final invoiceNo = await _nextInvoiceNo(now);
      await _db.into(_db.sales).insert(SalesCompanion.insert(
            id: saleId,
            shopId: _shopId,
            invoiceNo: invoiceNo,
            subtotal: Value(total),
            total: Value(total),
            paid: Value(total),
            paymentMethod: Value(paymentMethod),
            customerName: Value(order.customerName),
            customerPhone: Value(order.customerPhone),
            customerId: Value(order.customerId),
            note: Value('Order ${order.orderNo}'),
            deliveryAddress: Value(_combinedAddress(order)),
            finalizedAt: Value(now),
            updatedAt: Value(now),
          ));
      await _enqueue('sales', saleId, 'upsert', jsonEncode(
          (await _one(_db.sales, (t) => t.id.equals(saleId))).toJson()));

      for (final it in lines) {
        final siId = _uuid.v4();
        await _db.into(_db.saleItems).insert(SaleItemsCompanion.insert(
              id: siId,
              shopId: _shopId,
              saleId: saleId,
              productId: it.productId ?? '',
              nameSnapshot: it.nameSnapshot,
              priceSnapshot: it.priceSnapshot,
              qty: it.qty,
              lineTotal: it.lineTotal,
              updatedAt: Value(now),
            ));
        await _enqueue('sale_items', siId, 'upsert', jsonEncode(
            (await _one(_db.saleItems, (t) => t.id.equals(siId))).toJson()));

        if (trackStock && it.productId != null) {
          await _recordStockOut(it.productId!, it.qty, saleId, now);
        }
      }

      final payId = _uuid.v4();
      await _db.into(_db.payments).insert(PaymentsCompanion.insert(
            id: payId,
            shopId: _shopId,
            saleId: saleId,
            method: paymentMethod,
            amount: total,
            updatedAt: Value(now),
          ));
      await _enqueue('payments', payId, 'upsert', jsonEncode(
          (await _one(_db.payments, (t) => t.id.equals(payId))).toJson()));

      await (_db.update(_db.orders)..where((o) => o.id.equals(orderId)))
          .write(OrdersCompanion(
        saleId: Value(saleId),
        status: const Value('delivered'),
        paymentStatus: const Value('paid'),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueueOrder(orderId);
    });
    return saleId;
  }

  // ---- internals ---------------------------------------------------------

  /// [Order.deliveryAddress] + [Order.township] combined into the single
  /// free-text line `Sales.deliveryAddress` carries — null if neither is set.
  String? _combinedAddress(Order order) {
    final address = (order.deliveryAddress ?? '').trim();
    final township = (order.township ?? '').trim();
    if (address.isEmpty && township.isEmpty) return null;
    if (address.isEmpty) return township;
    if (township.isEmpty) return address;
    return '$address, $township';
  }

  Future<void> _recordStockOut(
      String productId, int qty, String saleId, DateTime now) async {
    final moveId = _uuid.v4();
    await _db.into(_db.stockMovements).insert(StockMovementsCompanion.insert(
          id: moveId,
          shopId: _shopId,
          productId: productId,
          type: 'sale',
          qtyDelta: -qty,
          refId: Value(saleId),
          updatedAt: Value(now),
        ));
    await _enqueue('stock_movements', moveId, 'upsert', jsonEncode(
        (await _one(_db.stockMovements, (t) => t.id.equals(moveId))).toJson()));

    final level = await (_db.select(_db.stockLevels)
          ..where((s) => s.productId.equals(productId)))
        .getSingleOrNull();
    if (level != null) {
      await (_db.update(_db.stockLevels)..where((s) => s.id.equals(level.id)))
          .write(StockLevelsCompanion(
        quantity: Value(level.quantity - qty),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueue('stock_levels', level.id, 'upsert', jsonEncode(
          (await _one(_db.stockLevels, (t) => t.id.equals(level.id))).toJson()));
    }
  }

  /// Per-shop, per-day sequential order number: `ORD-yyyyMMdd-NNN`.
  Future<String> _nextOrderNo(DateTime now) async {
    final dayStart = DateTime(now.year, now.month, now.day);
    final todays = await (_db.select(_db.orders)
          ..where((o) =>
              o.shopId.equals(_shopId) &
              o.createdAt.isBiggerOrEqualValue(dayStart)))
        .get();
    final seq = (todays.length + 1).toString().padLeft(3, '0');
    return 'ORD-${DateFormat('yyyyMMdd').format(now)}-$seq';
  }

  /// Per-shop, per-day sequential invoice number: `INV-yyyyMMdd-NNN`. Mirrors
  /// `SalesRepository` so converted orders share the shop's invoice sequence.
  Future<String> _nextInvoiceNo(DateTime now) async {
    final dayStart = DateTime(now.year, now.month, now.day);
    final todays = await (_db.select(_db.sales)
          ..where((s) =>
              s.shopId.equals(_shopId) &
              s.finalizedAt.isBiggerOrEqualValue(dayStart)))
        .get();
    final seq = (todays.length + 1).toString().padLeft(3, '0');
    return 'INV-${DateFormat('yyyyMMdd').format(now)}-$seq';
  }

  Future<D> _one<T extends Table, D>(
    TableInfo<T, D> table,
    Expression<bool> Function(T) filter,
  ) {
    return (_db.select(table)..where(filter)).getSingle();
  }

  Future<void> _enqueueOrder(String orderId) async {
    final row = await _one(_db.orders, (t) => t.id.equals(orderId));
    await _enqueue('orders', orderId, 'upsert', jsonEncode(row.toJson()));
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
