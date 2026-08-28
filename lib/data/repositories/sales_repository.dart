
import 'package:drift/drift.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../features/credit/credit_repository.dart';
import '../../features/sell/cart.dart';
import '../local/database.dart';
import 'stock_lots.dart';

/// Result of finalizing a sale.
class SaleResult {
  final String saleId;
  final String invoiceNo;
  const SaleResult(this.saleId, this.invoiceNo);
}

/// One method's share of a split-payment sale — see `finalizeSale`'s
/// `payments` parameter.
class PaymentEntry {
  final String method;
  final int amount;
  const PaymentEntry(this.method, this.amount);
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

  /// Every line item across every sale, shop-wide — the Sales Report's
  /// by-product filter needs to know which `saleId`s touched a matching
  /// product, and the report already loads all-time sales the same way
  /// (`watchSales`), so this stays consistent with that existing scale.
  Stream<List<SaleItem>> watchAllSaleItems() {
    return (_db.select(_db.saleItems)
          ..where((i) => i.shopId.equals(_shopId) & i.isDeleted.equals(false)))
        .watch();
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
    final original = await getSale(saleId);
    final originalItems = await saleItems(saleId);

    final refundId = _uuid.v4();
    final now = DateTime.now();
    late final String refundNo;

    await _db.transaction(() async {
      // Single-refund guard — INSIDE the transaction (audit H-1). Drift
      // transactions are serialized, so this is atomic against concurrent
      // local refunds; the `sales_refund_once` unique index (schema v32 /
      // remote migration 0067) is the cross-device backstop, failing a
      // second device's push loudly into sync quarantine instead of letting
      // a duplicate reversal double-restore stock and double-reverse cash.
      if (await refundOf(saleId) != null) {
        throw StateError('already_refunded');
      }
      refundNo = await _nextRefundNo(now);

      // Did the original sale actually deduct stock? An invoice-only shop
      // (trackStock=false) records no stock-out movement — its refund must
      // not reopen any lot either (audit QA-C1 guard).
      final stockOuts = await (_db.select(_db.stockMovements)
            ..where(
                (m) => m.refId.equals(saleId) & m.type.equals('sale'))
            ..limit(1))
          .get();
      final originalTrackedStock = stockOuts.isNotEmpty;

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
      await _enqueue('sales', refundId);

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
        await _enqueue('sale_items', itemId);

        if (trackStock &&
            item.productId.isNotEmpty &&
            originalTrackedStock) {
          // Restore the original cost basis, not whatever it costs today —
          // this is the same physical stock coming back. Per-unit average
          // when we know the line's exact COGS. Audit QA-C1: lines with no
          // costSnapshot (legacy order conversions, pre-FIFO sales) used to
          // reopen NO lot while their return movement stamped unit_cost 0 —
          // the next ledger rebuild then re-entered those units at COST
          // ZERO and every later sale of them overstated profit by their
          // full real cost. Fall back to the product's current cost so the
          // lot reopens at a real figure; skipped when there is no product
          // (free-text line) or the original never deducted stock.
          int? unitCost;
          if (item.qty != 0) {
            if (item.costSnapshot != null) {
              unitCost = (item.costSnapshot! / item.qty).round();
            } else {
              final product = await (_db.select(_db.products)
                    ..where((p) => p.id.equals(item.productId)))
                  .getSingleOrNull();
              unitCost = product?.costPrice;
            }
          }
          await _recordStockReturn(
              item.productId, item.qty, refundId, now, unitCost);
        }
      }

      // Reverses exactly what was collected on the original, method for
      // method — a credit sale that was never paid refunds no cash (there's
      // nothing to give back), and a split sale reverses each method by its
      // own original share (not lumped into one row under
      // `original.paymentMethod`, which would be `'split'` for these and a
      // meaningless method to reverse cash/wallet balances against).
      //
      // Mirrors the actual `Payments` rows rather than `original.paid`:
      // `original.paid` is the raw amount tendered, which can exceed what
      // was actually kept when change was given (`finalizeSale`'s
      // `settled = paid > total ? total : paid`) — reversing the raw
      // tendered figure would over-refund by the change already handed
      // back at sale time.
      final originalPayments = await (_db.select(_db.payments)
            ..where((p) => p.saleId.equals(saleId)))
          .get();
      for (final p in originalPayments) {
        if (p.amount == 0) continue;
        final payId = _uuid.v4();
        await _db.into(_db.payments).insert(PaymentsCompanion.insert(
              id: payId,
              shopId: _shopId,
              saleId: refundId,
              method: p.method,
              amount: -p.amount,
              updatedAt: Value(now),
            ));
        await _enqueue('payments', payId);
      }

      // If the original was still owed money (an unpaid/partial credit
      // sale), close that obligation via the existing FIFO repayment
      // mechanism — the customer no longer owes for goods they've returned.
      // Reuses CreditRepository's own ledger rather than mutating the sale.
      //
      // The closure amount is what is STILL owed on this specific invoice
      // after every recorded repayment is FIFO-allocated across the
      // customer's open invoices (audit H-2) — NOT raw `total - paid`,
      // which double-counts debt the credit book already absorbed and used
      // to mint a phantom credit that wiped the customer's other real
      // debts. Method stays 'credit' so Cash Register's expected-cash math
      // (which folds only method='cash' rows) never counts this non-cash
      // bookkeeping entry as money in the drawer.
      final owedRemaining = await _remainingCreditOwed(original);
      if (owedRemaining > 0 &&
          original.customerName != null &&
          original.customerName!.trim().isNotEmpty) {
        final repayId = _uuid.v4();
        await _db.into(_db.creditPayments).insert(
            CreditPaymentsCompanion.insert(
              id: repayId,
              shopId: _shopId,
              customerName: original.customerName!.trim(),
              customerId: Value(original.customerId),
              amount: owedRemaining,
              method: const Value('credit'),
              note: Value('Refund closure for ${original.invoiceNo}'),
              updatedAt: Value(now),
            ));
        await _enqueue('credit_payments', repayId);
      }
    });

    return SaleResult(refundId, refundNo);
  }

  /// What the customer still genuinely owes on [original] after every
  /// recorded repayment is FIFO-allocated across their open invoices
  /// (audit H-2). Falls back to the raw billed-minus-paid figure only when
  /// the sale can't be found in the allocation map (e.g. no customer name).
  Future<int> _remainingCreditOwed(Sale original) async {
    final creditSales = await (_db.select(_db.sales)
          ..where((s) =>
              s.shopId.equals(_shopId) &
              s.isDeleted.equals(false) &
              s.paid.isSmallerThan(s.total)))
        .get();
    final repayments = await (_db.select(_db.creditPayments)
          ..where((p) =>
              p.shopId.equals(_shopId) & p.isDeleted.equals(false)))
        .get();
    final owed = CreditRepository.owedBySale(creditSales, repayments);
    return owed[original.id] ?? (original.total - original.paid);
  }

  /// Finalizes [cart] and returns the new invoice reference.
  ///
  /// Pass either a single [paymentMethod]/[paid] pair (the common case), or
  /// a non-empty [payments] list to charge the sale across multiple methods
  /// in one go (e.g. cash + KBZPay) — when [payments] is given, it takes
  /// over entirely: `Sales.paymentMethod` becomes `'split'` and one
  /// `Payments` row is written per entry instead of the usual single row.
  /// The caller (the checkout UI) is responsible for ensuring the entries
  /// sum to exactly the cart's total — this does not defensively rebalance
  /// a mismatched split, the same trust-the-caller boundary already used
  /// for the scalar [paid] amount.
  Future<SaleResult> finalizeSale({
    required CartState cart,
    String? paymentMethod,
    int? paid,
    List<PaymentEntry>? payments,
    String? customerName,
    String? customerPhone,
    String? customerId,
    String? staffId,
    String? deviceId,
    bool trackStock = true,
  }) async {
    if (cart.isEmpty) {
      throw StateError('Cannot finalize an empty cart');
    }
    final isSplit = payments != null && payments.isNotEmpty;
    if (!isSplit && (paymentMethod == null || paid == null)) {
      throw ArgumentError(
        'paymentMethod and paid are required unless payments is given',
      );
    }

    final saleId = _uuid.v4();
    final now = DateTime.now();
    final subtotal = cart.subtotal.kyat;
    final total = cart.total.kyat;
    final effectivePaid = isSplit
        ? payments.fold<int>(0, (a, e) => a + e.amount)
        : paid!;
    // A split sale always fully settles the total — the checkout UI's own
    // credit/owed section deliberately excludes `_method == 'split'`, so
    // there is no "partial split, rest on credit" case this would wrongly
    // reject. A real (not `assert`, which release builds strip) check here
    // closes the gap the checkout UI leaves: nothing stops some other
    // caller from reaching this method with a mismatched split and writing
    // a sale for less than its goods are worth with no error anywhere.
    if (isSplit && effectivePaid != total) {
      throw ArgumentError(
        'Split payments ($effectivePaid) must sum to the sale total ($total)',
      );
    }
    final effectiveMethod = isSplit ? 'split' : paymentMethod!;
    final change = effectivePaid > total ? effectivePaid - total : 0;

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
        paid: Value(effectivePaid),
        changeDue: Value(change),
        paymentMethod: Value(effectiveMethod),
        customerName: Value(customerName),
        customerPhone: Value(customerPhone),
        customerId: Value(customerId),
        deviceId: Value(deviceId),
        finalizedAt: Value(now),
        updatedAt: Value(now),
      );
      await _db.into(_db.sales).insert(sale);
      await _enqueue('sales', saleId);

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
        await _enqueue('sale_items', itemId);
      }

      if (isSplit) {
        // One row per method — the checkout UI already guaranteed these sum
        // to the total, so unlike the single-method path below there's no
        // "settled vs. change" distinction to make per entry.
        for (final entry in payments) {
          final payId = _uuid.v4();
          await _db.into(_db.payments).insert(PaymentsCompanion.insert(
                id: payId,
                shopId: _shopId,
                saleId: saleId,
                method: entry.method,
                amount: entry.amount,
                updatedAt: Value(now),
              ));
          await _enqueue('payments', payId);
        }
      } else {
        // Tender actually collected. For cash/digital this equals the total
        // (change is handled separately); for a credit sale it may be a
        // partial down-payment (or 0), leaving total − paid owed by the
        // customer. A cash/wallet deposit on the credit path must land as
        // method=cash so Cash Register expected cash includes it — stamping
        // the Payments row as 'credit' hid the physical notes in the till.
        final settled = effectivePaid > total ? total : effectivePaid;
        if (settled > 0) {
          final payId = _uuid.v4();
          final tenderMethod =
              paymentMethod == 'credit' ? 'cash' : paymentMethod!;
          await _db.into(_db.payments).insert(PaymentsCompanion.insert(
                id: payId,
                shopId: _shopId,
                saleId: saleId,
                method: tenderMethod,
                amount: settled,
                updatedAt: Value(now),
              ));
          await _enqueue('payments', payId);
        }
      }
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
    await _enqueue('stock_movements', moveId);

    // Decrement the denormalized stock level if present. Local cache only —
    // NO stock_levels outbox enqueue: `quantity` is a counter reconciled from
    // the append-only movement ledger above on every device (see
    // sync_mappers.dart's _stockLevels), never an absolute LWW sync value.
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
    }

    return cost;
  }

  /// Per-shop, per-day sequential invoice number: `INV-yyyyMMdd-NNN`.
  ///
  /// Scans today's existing numbers for the MAX sequence rather than
  /// counting rows (audit M3): counting breaks whenever non-invoice sale
  /// rows share the day (refund credit-notes) or a pulled/pushed row makes
  /// counts and sequences disagree, producing duplicate numbers. Max-scan
  /// is idempotent against any mix. Cross-device caveat: two devices
  /// offline simultaneously can still mint the same number (there is no
  /// server-side uniqueness by design — the ledger keys on row id), but the
  /// window is now limited to truly simultaneous generation.
  Future<String> _nextInvoiceNo(DateTime now) async {
    final prefix = 'INV-${DateFormat('yyyyMMdd').format(now)}-';
    final seq = await _maxSeqForPrefix(prefix);
    return '$prefix${(seq + 1).toString().padLeft(3, '0')}';
  }

  /// Per-shop, per-day sequential refund number: `RFD-yyyyMMdd-NNN` — a
  /// separate sequence from invoices so a refund reads as its own document
  /// (a credit note), not just another invoice. Same max-seq scan as
  /// [_nextInvoiceNo].
  Future<String> _nextRefundNo(DateTime now) async {
    final prefix = 'RFD-${DateFormat('yyyyMMdd').format(now)}-';
    final seq = await _maxSeqForPrefix(prefix);
    return '$prefix${(seq + 1).toString().padLeft(3, '0')}';
  }

  /// Scans today's invoice numbers for [prefix] (already shop-scoped) and
  /// returns the max numeric suffix.
  Future<int> _maxSeqForPrefix(String prefix) async {
    final rows = await (_db.select(_db.sales)
          ..where((s) =>
              s.shopId.equals(_shopId) & s.invoiceNo.like('$prefix%')))
        .get();
    var max = 0;
    for (final r in rows) {
      final no = r.invoiceNo;
      if (!no.startsWith(prefix)) continue;
      final n = int.tryParse(no.substring(prefix.length));
      if (n != null && n > max) max = n;
    }
    return max;
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
    await _enqueue('stock_movements', moveId);

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
      // No stock_levels enqueue — same counter rule as _recordStockOut.
    }
  }

  Future<D> _one<T extends Table, D>(
    TableInfo<T, D> table,
    Expression<bool> Function(T) filter,
  ) {
    return (_db.select(table)..where(filter)).getSingle();
  }

  Future<void> _enqueue(String table, String rowId) {
    return _db.into(_db.outbox).insert(OutboxCompanion.insert(
          entityTable: table,
          rowId: rowId,
          op: 'upsert',
        ));
  }
}
