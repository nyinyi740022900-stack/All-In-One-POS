import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../features/sell/cart.dart';
import '../local/database.dart';
import 'stock_lots.dart';

/// Result of finalizing a sale.
class SaleResult {
  final String saleId;
  final String invoiceNo;
  const SaleResult(this.saleId, this.invoiceNo);
}

/// Handles checkout. A sale is written **append-only** together with its
/// items, payment, and stock movements — all inside one transaction so the
/// books can never end up half-written. Every row is queued to the Outbox.
class SalesRepository {
  SalesRepository(this._db, this._shopId);

  final AppDatabase _db;
  final String _shopId;
  static const _uuid = Uuid();

  Stream<List<Sale>> watchSales() {
    return (_db.select(_db.sales)
          ..where((s) => s.shopId.equals(_shopId) & s.isDeleted.equals(false))
          ..orderBy([(s) => OrderingTerm.desc(s.finalizedAt)]))
        .watch();
  }

  Future<Sale> getSale(String saleId) {
    return (_db.select(_db.sales)..where((s) => s.id.equals(saleId)))
        .getSingle();
  }

  Future<List<SaleItem>> saleItems(String saleId) {
    return (_db.select(_db.saleItems)
          ..where((i) => i.saleId.equals(saleId))
          ..orderBy([(i) => OrderingTerm(expression: i.createdAt)]))
        .get();
  }

  /// The refund row that reverses [saleId], if any (a sale can only be
  /// refunded once — this both detects an existing refund and enforces that).
  Future<Sale?> refundOf(String saleId) {
    return (_db.select(_db.sales)
          ..where((s) => s.refundOfSaleId.equals(saleId)))
        .getSingleOrNull();
  }

  /// Reverses [saleId] as a new, append-only refund sale — the original row
  /// is never touched (sales stay an immutable ledger). Restores stock via
  /// `'return'` movements (skipped for invoice-only shops / free-text lines
  /// with no product), and records a negative payment for whatever cash was
  /// actually collected on the original (so a partially-paid credit sale only
  /// reverses what was truly tendered, not the full billed total).
  ///
  /// Throws [StateError] if [saleId] has already been refunded.
  Future<SaleResult> refundSale(String saleId, {bool trackStock = true}) async {
    if (await refundOf(saleId) != null) {
      throw StateError('already_refunded');
    }
    final original = await getSale(saleId);
    final originalItems = await saleItems(saleId);

    final refundId = _uuid.v4();
    final now = DateTime.now();
    late final String refundNo;

    await _db.transaction(() async {
      refundNo = await _nextRefundNo(now);

      final refund = SalesCompanion.insert(
        id: refundId,
        shopId: _shopId,
        invoiceNo: refundNo,
        subtotal: Value(-original.subtotal),
        discount: Value(-original.discount),
        total: Value(-original.total),
        paid: Value(-original.paid),
        paymentMethod: Value(original.paymentMethod),
        customerName: Value(original.customerName),
        customerPhone: Value(original.customerPhone),
        customerId: Value(original.customerId),
        note: Value('Refund of ${original.invoiceNo}'),
        refundOfSaleId: Value(saleId),
        finalizedAt: Value(now),
        updatedAt: Value(now),
      );
      await _db.into(_db.sales).insert(refund);
      await _enqueue('sales', refundId, jsonEncode(
          (await _one(_db.sales, (t) => t.id.equals(refundId))).toJson()));

      for (final item in originalItems) {
        final itemId = _uuid.v4();
        await _db.into(_db.saleItems).insert(SaleItemsCompanion.insert(
              id: itemId,
              shopId: _shopId,
              saleId: refundId,
              productId: item.productId,
              nameSnapshot: item.nameSnapshot,
              priceSnapshot: item.priceSnapshot,
              qty: -item.qty,
              lineTotal: -item.lineTotal,
              costSnapshot: Value(
                  item.costSnapshot == null ? null : -item.costSnapshot!),
              updatedAt: Value(now),
            ));
        await _enqueue('sale_items', itemId, jsonEncode(
            (await _one(_db.saleItems, (t) => t.id.equals(itemId))).toJson()));

        if (trackStock) {
          // Restore the original cost basis, not whatever it costs today —
          // this is the same physical stock coming back. Per-unit average
          // when we know the line's exact COGS; null (no lot pushed) for a
          // pre-FIFO sale with no costSnapshot, since there's nothing to
          // restore it at.
          final unitCost = item.costSnapshot == null || item.qty == 0
              ? null
              : (item.costSnapshot! / item.qty).round();
          await _recordStockReturn(
              item.productId, item.qty, refundId, now, unitCost);
        }
      }

      // Reverses exactly what was collected on the original — a credit sale
      // that was never paid refunds no cash (there's nothing to give back).
      if (original.paid != 0) {
        final payId = _uuid.v4();
        await _db.into(_db.payments).insert(PaymentsCompanion.insert(
              id: payId,
              shopId: _shopId,
              saleId: refundId,
              method: original.paymentMethod,
              amount: -original.paid,
              updatedAt: Value(now),
            ));
        await _enqueue('payments', payId, jsonEncode(
            (await _one(_db.payments, (t) => t.id.equals(payId))).toJson()));
      }

      // If the original was still owed money (an unpaid/partial credit sale),
      // close that obligation via the existing FIFO repayment mechanism —
      // the customer no longer owes for goods they've returned. Reuses
      // CreditRepository's own ledger rather than mutating the sale.
      final owed = original.total - original.paid;
      if (owed > 0 &&
          original.customerName != null &&
          original.customerName!.trim().isNotEmpty) {
        final repayId = _uuid.v4();
        await _db.into(_db.creditPayments).insert(
            CreditPaymentsCompanion.insert(
              id: repayId,
              shopId: _shopId,
              customerName: original.customerName!.trim(),
              customerId: Value(original.customerId),
              amount: owed,
              note: Value('Refund closure for ${original.invoiceNo}'),
              updatedAt: Value(now),
            ));
        await _enqueue('credit_payments', repayId, jsonEncode(
            (await _one(_db.creditPayments, (t) => t.id.equals(repayId)))
                .toJson()));
      }
    });

    return SaleResult(refundId, refundNo);
  }

  /// Finalizes [cart] and returns the new invoice reference.
  Future<SaleResult> finalizeSale({
    required CartState cart,
    required String paymentMethod,
    required int paid,
    String? customerName,
    String? customerPhone,
    String? customerId,
    String? staffId,
    bool trackStock = true,
  }) async {
    if (cart.isEmpty) {
      throw StateError('Cannot finalize an empty cart');
    }

    final saleId = _uuid.v4();
    final now = DateTime.now();
    final subtotal = cart.subtotal.kyat;
    final total = cart.total.kyat;
    final change = paid > total ? paid - total : 0;

    await _db.transaction(() async {
      final invoiceNo = await _nextInvoiceNo(now);

      final sale = SalesCompanion.insert(
        id: saleId,
        shopId: _shopId,
        invoiceNo: invoiceNo,
        staffId: Value(staffId),
        subtotal: Value(subtotal),
        discount: Value(cart.discount),
        total: Value(total),
        paid: Value(paid),
        changeDue: Value(change),
        paymentMethod: Value(paymentMethod),
        customerName: Value(customerName),
        customerPhone: Value(customerPhone),
        customerId: Value(customerId),
        finalizedAt: Value(now),
        updatedAt: Value(now),
      );
      await _db.into(_db.sales).insert(sale);
      await _enqueue('sales', saleId, jsonEncode(
          (await _one(_db.sales, (t) => t.id.equals(saleId))).toJson()));

      for (final line in cart.lines) {
        // Stock movement (ledger) + decrement the cached level + FIFO cost
        // of goods sold. Skipped for invoice-only shops that don't track
        // inventory — costSnapshot then stays null (Analytics falls back to
        // the product's flat cost price for those lines).
        final costSnapshot = trackStock
            ? await _recordStockOut(line.product.id, line.qty, saleId, now)
            : null;

        final itemId = _uuid.v4();
        await _db.into(_db.saleItems).insert(SaleItemsCompanion.insert(
              id: itemId,
              shopId: _shopId,
              saleId: saleId,
              productId: line.product.id,
              nameSnapshot: line.product.name,
              priceSnapshot: cart.unitPriceFor(line).kyat,
              qty: line.qty,
              lineTotal: cart.lineTotalFor(line).kyat,
              costSnapshot: Value(costSnapshot),
              updatedAt: Value(now),
            ));
        await _enqueue('sale_items', itemId, jsonEncode(
            (await _one(_db.saleItems, (t) => t.id.equals(itemId))).toJson()));
      }

      // Tender actually collected. For cash/digital this equals the total
      // (change is handled separately); for a credit sale it may be a partial
      // down-payment (or 0), leaving total − paid owed by the customer.
      final settled = paid > total ? total : paid;
      final payId = _uuid.v4();
      await _db.into(_db.payments).insert(PaymentsCompanion.insert(
            id: payId,
            shopId: _shopId,
            saleId: saleId,
            method: paymentMethod,
            amount: settled,
            updatedAt: Value(now),
          ));
      await _enqueue('payments', payId, jsonEncode(
          (await _one(_db.payments, (t) => t.id.equals(payId))).toJson()));
    });

    // Re-read invoice number for the return value.
    final saved = await _one(_db.sales, (t) => t.id.equals(saleId));
    return SaleResult(saleId, saved.invoiceNo);
  }

  // ---- internals ---------------------------------------------------------

  /// Records the sale's stock movement + FIFO cost of goods sold, returning
  /// the total cost consumed (for [SaleItems.costSnapshot]).
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
          // Weighted per-unit average, for the ledger's own display — the
          // exact total (no rounding) lives on SaleItems.costSnapshot, which
          // is what Analytics actually sums for profit.
          unitCost: Value(qty > 0 ? (cost / qty).round() : 0),
          refId: Value(saleId),
          updatedAt: Value(now),
        ));
    await _enqueue('stock_movements', moveId, jsonEncode(
        (await _one(_db.stockMovements, (t) => t.id.equals(moveId))).toJson()));

    // Decrement the denormalized stock level if present.
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
      await _enqueue('stock_levels', level.id, jsonEncode(
          (await _one(_db.stockLevels, (t) => t.id.equals(level.id))).toJson()));
    }

    return cost;
  }

  /// Per-shop, per-day sequential invoice number: `INV-yyyyMMdd-NNN`.
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

  /// Per-shop, per-day sequential refund number: `RFD-yyyyMMdd-NNN` — a
  /// separate sequence from invoices so a refund reads as its own document
  /// (a credit note), not just another invoice.
  Future<String> _nextRefundNo(DateTime now) async {
    final dayStart = DateTime(now.year, now.month, now.day);
    final todays = await (_db.select(_db.sales)
          ..where((s) =>
              s.shopId.equals(_shopId) &
              s.refundOfSaleId.isNotNull() &
              s.finalizedAt.isBiggerOrEqualValue(dayStart)))
        .get();
    final seq = (todays.length + 1).toString().padLeft(3, '0');
    return 'RFD-${DateFormat('yyyyMMdd').format(now)}-$seq';
  }

  /// Restores stock for a refunded item — the inverse of [_recordStockOut].
  /// [unitCost] (the original sale's per-unit COGS) reopens a lot at that
  /// cost so the next sale of this product still costs correctly; null skips
  /// the lot (nothing to restore it at — a pre-FIFO sale).
  Future<void> _recordStockReturn(String productId, int qty,
      String refundSaleId, DateTime now, int? unitCost) async {
    if (unitCost != null) {
      await pushStockLot(_db, productId: productId, qty: qty, unitCost: unitCost);
    }

    final moveId = _uuid.v4();
    await _db.into(_db.stockMovements).insert(StockMovementsCompanion.insert(
          id: moveId,
          shopId: _shopId,
          productId: productId,
          type: 'return',
          qtyDelta: qty,
          unitCost: Value(unitCost ?? 0),
          refId: Value(refundSaleId),
          updatedAt: Value(now),
        ));
    await _enqueue('stock_movements', moveId, jsonEncode(
        (await _one(_db.stockMovements, (t) => t.id.equals(moveId))).toJson()));

    final level = await (_db.select(_db.stockLevels)
          ..where((s) => s.productId.equals(productId)))
        .getSingleOrNull();
    if (level != null) {
      await (_db.update(_db.stockLevels)..where((s) => s.id.equals(level.id)))
          .write(StockLevelsCompanion(
        quantity: Value(level.quantity + qty),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueue('stock_levels', level.id, jsonEncode(
          (await _one(_db.stockLevels, (t) => t.id.equals(level.id))).toJson()));
    }
  }

  Future<D> _one<T extends Table, D>(
    TableInfo<T, D> table,
    Expression<bool> Function(T) filter,
  ) {
    return (_db.select(table)..where(filter)).getSingle();
  }

  Future<void> _enqueue(String table, String rowId, String payload) {
    return _db.into(_db.outbox).insert(OutboxCompanion.insert(
          entityTable: table,
          rowId: rowId,
          op: 'upsert',
          payload: payload,
        ));
  }
}
