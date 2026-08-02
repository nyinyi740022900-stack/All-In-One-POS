import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';

/// What the drawer should hold: [openingAmount] + every cash-tendered
/// [payments]/[repayments] − every [expenses] amount. Pure (no DB, no I/O)
/// so it's directly unit-testable — callers are expected to have already
/// filtered each list to the session's own `[openedAt, closedAt)` window.
///
/// Expenses has no payment-method column (see `Expenses` in tables.dart), so
/// every expense is assumed paid from the till — the common case for a small
/// shop's day-to-day purchases (tea, transport, a supply run). A shop that
/// pays some expenses by transfer will see the drawer read short by that
/// amount; noted here rather than silently treated as exact.
int computeExpectedCash({
  required int openingAmount,
  required List<Payment> payments,
  required List<CreditPayment> repayments,
  required List<Expense> expenses,
}) {
  final cashIn = payments
          .where((p) => p.method == 'cash')
          .fold<int>(0, (sum, p) => sum + p.amount) +
      repayments
          .where((r) => r.method == 'cash')
          .fold<int>(0, (sum, r) => sum + r.amount);
  final cashOut = expenses.fold<int>(0, (sum, e) => sum + e.amount);
  return openingAmount + cashIn - cashOut;
}

/// Cash-drawer sessions (opening float → closing count). See `CashSessions`
/// in tables.dart for the reconciliation rationale.
class CashSessionRepository {
  CashSessionRepository(this._db, this._shopId);

  final AppDatabase _db;
  final String _shopId;
  static const _uuid = Uuid();

  /// The shop's currently-open session, if any. App-side convention (not a
  /// DB constraint) is at most one open session per shop at a time.
  Stream<CashSession?> watchCurrentSession() {
    return (_db.select(_db.cashSessions)
          ..where((t) =>
              t.shopId.equals(_shopId) &
              t.isDeleted.equals(false) &
              t.closedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.openedAt)])
          ..limit(1))
        .watchSingleOrNull();
  }

  /// Every non-deleted expense for this shop, unfiltered by date — used only
  /// to trigger [expectedCash] recomputation when an expense changes (see
  /// `cash_providers.dart`), not for display.
  Stream<List<Expense>> watchAllExpenses() {
    return (_db.select(_db.expenses)
          ..where((t) => t.shopId.equals(_shopId) & t.isDeleted.equals(false)))
        .watch();
  }

  /// Every session, newest first — the register's history.
  Stream<List<CashSession>> watchSessions() {
    return (_db.select(_db.cashSessions)
          ..where((t) =>
              t.shopId.equals(_shopId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.openedAt)]))
        .watch();
  }

  Future<String> openSession({
    required int openingAmount,
    String? note,
    String? deviceId,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db.into(_db.cashSessions).insert(CashSessionsCompanion.insert(
            id: id,
            shopId: _shopId,
            openedAt: now,
            openingAmount: openingAmount,
            note: Value(note),
            deviceId: Value(deviceId),
            updatedAt: Value(now),
          ));
      await _enqueue(id);
    });
    return id;
  }

  Future<void> closeSession(
    String id, {
    required int closingAmount,
    String? note,
  }) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.cashSessions)..where((t) => t.id.equals(id)))
          .write(CashSessionsCompanion(
        closedAt: Value(now),
        closingAmount: Value(closingAmount),
        note: note == null ? const Value.absent() : Value(note),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueue(id);
    });
  }

  /// What the drawer should hold right now (or at close, if [session] is
  /// already closed) — fetches this shop's payments/repayments/expenses
  /// within the session's window and hands them to [computeExpectedCash].
  Future<int> expectedCash(CashSession session) async {
    final end = session.closedAt;

    final payments = await (_db.select(_db.payments)
          ..where((t) {
            var pred = t.shopId.equals(_shopId) &
                t.isDeleted.equals(false) &
                t.createdAt.isBiggerOrEqualValue(session.openedAt);
            if (end != null) pred = pred & t.createdAt.isSmallerThanValue(end);
            return pred;
          }))
        .get();
    final repayments = await (_db.select(_db.creditPayments)
          ..where((t) {
            var pred = t.shopId.equals(_shopId) &
                t.isDeleted.equals(false) &
                t.createdAt.isBiggerOrEqualValue(session.openedAt);
            if (end != null) pred = pred & t.createdAt.isSmallerThanValue(end);
            return pred;
          }))
        .get();
    final expenses = await (_db.select(_db.expenses)
          ..where((t) {
            var pred = t.shopId.equals(_shopId) &
                t.isDeleted.equals(false) &
                t.date.isBiggerOrEqualValue(session.openedAt);
            if (end != null) pred = pred & t.date.isSmallerThanValue(end);
            return pred;
          }))
        .get();

    return computeExpectedCash(
      openingAmount: session.openingAmount,
      payments: payments,
      repayments: repayments,
      expenses: expenses,
    );
  }

  Future<void> _enqueue(String id) async {
    final row = await (_db.select(_db.cashSessions)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    await _db.into(_db.outbox).insert(OutboxCompanion.insert(
          entityTable: 'cash_sessions',
          rowId: id,
          op: 'upsert',
          payload: jsonEncode(row.toJson()),
        ));
  }
}
