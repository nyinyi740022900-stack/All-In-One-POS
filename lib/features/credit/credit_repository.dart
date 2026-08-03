import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';

/// A customer's outstanding credit, aggregated from their credit sales minus
/// repayments. Grouped by [customerId] when the sale/repayment was linked to
/// the customer directory, falling back to a case-insensitive name match for
/// older rows (or one-off sales where no directory entry was picked) — see
/// [creditKeyFor]. [key] is the stable grouping key either way; use it (not
/// [name]) for navigation/lookups so a directory customer's rename doesn't
/// orphan their history.
class CreditCustomer {
  final String key;
  final String? customerId;
  final String name;
  final String? phone;
  final int billed; // Σ total of credit sales
  final int paid; // Σ down-payments on those sales + Σ repayments
  final int openInvoices;

  const CreditCustomer({
    required this.key,
    this.customerId,
    required this.name,
    this.phone,
    required this.billed,
    required this.paid,
    required this.openInvoices,
  });

  int get outstanding {
    final o = billed - paid;
    return o < 0 ? 0 : o;
  }
}

/// The stable grouping key for a customer within the credit book: their
/// directory id if linked, otherwise a normalized form of their typed name.
/// Public (not just used internally) so UI code can match a [Sale]/
/// [CreditPayment] against a [CreditCustomer.key] without duplicating this
/// logic — see `CreditCustomerScreen`.
String creditKeyFor(String? customerId, String name) {
  if (customerId != null && customerId.isNotEmpty) return 'id:$customerId';
  return 'name:${name.trim().toLowerCase()}';
}

/// Reads/writes the credit book. Credit sales themselves live in [Sales]
/// (`paymentMethod = 'credit'`); this repository adds repayments and the
/// per-customer aggregation.
class CreditRepository {
  CreditRepository(this._db, this._shopId);

  final AppDatabase _db;
  final String _shopId;
  static const _uuid = Uuid();

  /// Sales that carry an outstanding balance — any sale where less than the
  /// total was paid, regardless of the tendered method. Newest first.
  Stream<List<Sale>> watchCreditSales() {
    return (_db.select(_db.sales)
          ..where((s) =>
              s.shopId.equals(_shopId) &
              s.isDeleted.equals(false) &
              s.paid.isSmallerThan(s.total))
          ..orderBy([(s) => OrderingTerm.desc(s.finalizedAt)]))
        .watch();
  }

  Stream<List<CreditPayment>> watchRepayments() {
    return (_db.select(_db.creditPayments)
          ..where((p) => p.shopId.equals(_shopId) & p.isDeleted.equals(false))
          ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
        .watch();
  }

  /// Folds credit sales + repayments into a per-customer balance. By default
  /// only customers who still owe money are returned (largest balance
  /// first) — pass [includeSettled] to also get customers whose credit is
  /// fully paid off (outstanding 0), so their repayment history (exact
  /// date/time of each payment) stays reachable after the last one settles
  /// it, instead of the customer just disappearing from the credit book.
  static List<CreditCustomer> aggregate(
    List<Sale> creditSales,
    List<CreditPayment> repayments, {
    bool includeSettled = false,
  }) {
    final billed = <String, int>{};
    final paid = <String, int>{};
    final openInvoices = <String, int>{};
    final phone = <String, String>{};
    final name = <String, String>{};
    final customerId = <String, String>{};

    for (final s in creditSales) {
      final n = (s.customerName ?? '').trim();
      if (n.isEmpty) continue;
      final key = creditKeyFor(s.customerId, n);
      billed[key] = (billed[key] ?? 0) + s.total;
      paid[key] = (paid[key] ?? 0) + s.paid;
      if (s.total - s.paid > 0) {
        openInvoices[key] = (openInvoices[key] ?? 0) + 1;
      }
      name[key] = n;
      if (s.customerId != null) customerId[key] = s.customerId!;
      final ph = (s.customerPhone ?? '').trim();
      if (ph.isNotEmpty) phone[key] = ph;
    }
    for (final r in repayments) {
      final n = r.customerName.trim();
      if (n.isEmpty) continue;
      final key = creditKeyFor(r.customerId, n);
      paid[key] = (paid[key] ?? 0) + r.amount;
      name.putIfAbsent(key, () => n);
      if (r.customerId != null) customerId.putIfAbsent(key, () => r.customerId!);
    }

    final customers = <CreditCustomer>[];
    for (final key in billed.keys) {
      final c = CreditCustomer(
        key: key,
        customerId: customerId[key],
        name: name[key] ?? '',
        phone: phone[key],
        billed: billed[key] ?? 0,
        paid: paid[key] ?? 0,
        openInvoices: openInvoices[key] ?? 0,
      );
      if (includeSettled || c.outstanding > 0) customers.add(c);
    }
    customers.sort((a, b) => b.outstanding.compareTo(a.outstanding));
    return customers;
  }

  /// Allocates each customer's repayments across their credit invoices,
  /// **oldest first**, and returns the remaining owed per sale id. Once an
  /// invoice is fully covered by repayments its owed drops to 0 (so it
  /// disappears from the credit list even though the sale row is append-only).
  static Map<String, int> owedBySale(
    List<Sale> creditSales,
    List<CreditPayment> repayments,
  ) {
    final byCustomer = <String, List<Sale>>{};
    for (final s in creditSales) {
      final key = creditKeyFor(s.customerId, (s.customerName ?? '').trim());
      byCustomer.putIfAbsent(key, () => []).add(s);
    }
    final pool = <String, int>{};
    for (final r in repayments) {
      final key = creditKeyFor(r.customerId, r.customerName.trim());
      pool[key] = (pool[key] ?? 0) + r.amount;
    }
    final result = <String, int>{};
    byCustomer.forEach((key, sales) {
      final sorted = [...sales]
        ..sort((a, b) => a.finalizedAt.compareTo(b.finalizedAt));
      var remaining = pool[key] ?? 0;
      for (final s in sorted) {
        final owed = s.total - s.paid;
        if (owed <= 0) {
          result[s.id] = 0;
          continue;
        }
        final applied = remaining >= owed ? owed : remaining;
        remaining -= applied;
        result[s.id] = owed - applied;
      }
    });
    return result;
  }

  /// Records a repayment against a customer's outstanding credit and queues it
  /// for sync.
  Future<void> recordRepayment({
    required String customerName,
    String? customerId,
    required int amount,
    String method = 'cash',
    String? note,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db.into(_db.creditPayments).insert(CreditPaymentsCompanion.insert(
            id: id,
            shopId: _shopId,
            customerName: customerName.trim(),
            customerId: Value(customerId),
            amount: amount,
            method: Value(method),
            note: Value(note),
            updatedAt: Value(now),
          ));
      final row = await (_db.select(_db.creditPayments)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      await _db.into(_db.outbox).insert(OutboxCompanion.insert(
            entityTable: 'credit_payments',
            rowId: id,
            op: 'upsert',
            payload: jsonEncode(row.toJson()),
          ));
    });
  }
}
