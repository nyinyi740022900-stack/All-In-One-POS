
import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';
import '../../data/repositories/stock_lots.dart';

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
        await _enqueue('order_items', o.id, 'delete');
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
        await _enqueue('order_items', itemId, 'upsert');
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

  /// Restores a cancelled order to the 'new' pipeline (audit QA-L1).
  ///
  /// Cancel-with-sale always refunds that sale first (see the detail sheet's
  /// return flow), so a cancelled order carrying a [Orders.saleId] points at
  /// an already-reversed, append-only refund pair. Simply flipping status
  /// back used to strand it: convert is gated on `saleId == null`, so the
  /// order sat in the pipeline unable to ever convert again. Restoring
  /// therefore DETACHES the refunded sale and resets payment state — the old
  /// sale/refund stay in the ledger for audit, and converting again mints a
  /// fresh sale.
  Future<void> restoreOrder(String orderId) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.orders)..where((o) => o.id.equals(orderId)))
          .write(OrdersCompanion(
        status: const Value('new'),
        saleId: const Value(null),
        paymentStatus: const Value('unpaid'),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueueOrder(orderId);
    });
  }

  /// Tombstones the order and its items.
  Future<void> deleteOrder(String orderId) async {    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.orders)..where((o) => o.id.equals(orderId)))
          .write(OrdersCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueue('orders', orderId, 'delete');

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
        await _enqueue('order_items', it.id, 'delete');
      }
    });
  }

  /// Converts a delivered order into an append-only [Sales] row (+ items,
  /// payment, and stock movements). Idempotent: returns the existing sale id
  /// if already converted — the guard is checked BOTH outside and INSIDE the
  /// write transaction (audit QA-H1): Drift serializes transactions, so two
  /// concurrent conversions (double-tap race) can no longer both pass an
  /// outside-only check; the loser re-reads the winner's committed saleId
  /// and returns it instead of minting a second append-only sale.
  Future<String> convertToSale(
    String orderId, {
    String paymentMethod = 'cash',
    int? paid,
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
    // Unpaid COD must not book the full ticket as collected (that inflated
    // Cash Register expected cash before the courier remitted). An explicit
    // [paid] wins; otherwise COD that's still unpaid collects 0, and every
    // other convert (counter cash/KBZPay, already-marked-paid) collects total.
    final collected = paid ??
        (order.paymentMethod == 'cod' && order.paymentStatus != 'paid'
            ? 0
            : total);

    var effectiveSaleId = saleId;
    await _db.transaction(() async {
      // Re-read inside the transaction — see the doc comment above.
      final fresh =
          await (_db.select(_db.orders)..where((o) => o.id.equals(orderId)))
              .getSingle();
      if (fresh.saleId != null) {
        effectiveSaleId = fresh.saleId!;
        return;
      }

      final invoiceNo = await _nextInvoiceNo(now);
      await _db.into(_db.sales).insert(SalesCompanion.insert(
            id: saleId,
            shopId: _shopId,
            invoiceNo: invoiceNo,
            subtotal: Value(total),
            total: Value(total),
            paid: Value(collected),
            paymentMethod: Value(paymentMethod),
            customerName: Value(order.customerName),
            customerPhone: Value(order.customerPhone),
            customerId: Value(order.customerId),
            note: Value('Order ${order.orderNo}'),
            deliveryAddress: Value(_combinedAddress(order)),
            finalizedAt: Value(now),
            updatedAt: Value(now),
          ));
      await _enqueue('sales', saleId, 'upsert');

      for (final it in lines) {
        // Stock movement (ledger) + decrement the cached level + FIFO cost
        // of goods sold — the same accounting the Sell-screen checkout does
        // (audit QA-C1). Skipping this used to leave costSnapshot null, so
        // refunding such a sale restored stock as a unit_cost-0 return
        // movement and the next ledger rebuild re-entered those units at
        // COST ZERO, overstating profit by their full real cost.
        final costSnapshot = trackStock && it.productId != null
            ? await _recordStockOut(it.productId!, it.qty, saleId, now)
            : null;

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
              costSnapshot: Value(costSnapshot),
              updatedAt: Value(now),
            ));
        await _enqueue('sale_items', siId, 'upsert');
      }

      if (collected > 0) {
        final payId = _uuid.v4();
        await _db.into(_db.payments).insert(PaymentsCompanion.insert(
              id: payId,
              shopId: _shopId,
              saleId: saleId,
              method: paymentMethod,
              amount: collected,
              updatedAt: Value(now),
            ));
        await _enqueue('payments', payId, 'upsert');
      }

      await (_db.update(_db.orders)..where((o) => o.id.equals(orderId)))
          .write(OrdersCompanion(
        saleId: Value(saleId),
        status: const Value('delivered'),
        paymentStatus: Value(
          collected >= total
              ? 'paid'
              : collected > 0
                  ? 'partial'
                  : order.paymentStatus,
        ),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueueOrder(orderId);
    });
    return effectiveSaleId;
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

  /// Records the sale's stock movement + FIFO cost of goods sold, mirroring
  /// `SalesRepository._recordStockOut` exactly (audit QA-C1) — consumes lots
  /// oldest-first (falling back to the product's flat cost for any
  /// shortfall), stamps the movement with the per-unit average, and returns
  /// the total cost for [SaleItems.costSnapshot].
  Future<int> _recordStockOut(
      String productId, int qty, String saleId, DateTime now) async {
    final product =
        await (_db.select(_db.products)..where((p) => p.id.equals(productId)))
            .getSingle();
    final cost = await consumeStockLots(_db,
        productId: productId, qty: qty, fallbackUnitCost: product.costPrice);

    final moveId = _uuid.v4();
    await _db.into(_db.stockMovements).insert(StockMovementsCompanion.insert(
          id: moveId,
          shopId: _shopId,
          productId: productId,
          type: 'sale',
          qtyDelta: -qty,
          unitCost: Value(qty > 0 ? (cost / qty).round() : 0),
          refId: Value(saleId),
          updatedAt: Value(now),
        ));
    await _enqueue('stock_movements', moveId, 'upsert');

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
      // No stock_levels enqueue — quantity is a counter reconciled from the
      // stock_movements ledger on every device, never an absolute LWW push.
    }

    return cost;
  }

  /// Per-shop, per-day sequential order number: `ORD-yyyyMMdd-NNN`.
  /// Max-seq scan over existing numbers rather than row-counting — same
  /// reasoning as SalesRepository's invoice numbers (audit M3).
  Future<String> _nextOrderNo(DateTime now) async {
    final prefix = 'ORD-${DateFormat('yyyyMMdd').format(now)}-';
    final rows = await (_db.select(_db.orders)
          ..where((o) =>
              o.shopId.equals(_shopId) & o.orderNo.like('$prefix%')))
        .get();
    var max = 0;
    for (final o in rows) {
      final n = int.tryParse(o.orderNo.substring(prefix.length));
      if (n != null && n > max) max = n;
    }
    return '$prefix${(max + 1).toString().padLeft(3, '0')}';
  }

  /// Per-shop, per-day sequential invoice number: `INV-yyyyMMdd-NNN`. Mirrors
  /// `SalesRepository` so converted orders share the shop's invoice sequence
  /// — including its max-seq scan (audit M3).
  Future<String> _nextInvoiceNo(DateTime now) async {
    final prefix = 'INV-${DateFormat('yyyyMMdd').format(now)}-';
    final rows = await (_db.select(_db.sales)
          ..where((s) =>
              s.shopId.equals(_shopId) & s.invoiceNo.like('$prefix%')))
        .get();
    var max = 0;
    for (final s in rows) {
      final n = int.tryParse(s.invoiceNo.substring(prefix.length));
      if (n != null && n > max) max = n;
    }
    return '$prefix${(max + 1).toString().padLeft(3, '0')}';
  }

  Future<void> _enqueueOrder(String orderId) async {
    await _enqueue('orders', orderId, 'upsert');
  }

  Future<void> _enqueue(String table, String rowId, String op) {
    return _db.into(_db.outbox).insert(OutboxCompanion.insert(
          entityTable: table,
          rowId: rowId,
          op: op,
        ));
  }
}
