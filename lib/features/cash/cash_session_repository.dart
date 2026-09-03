
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';

/// What the drawer should hold: [openingAmount] + every cash-tendered
/// [payments]/[repayments] + [topUps] − every [expenses] amount − cash
/// [supplierPayments]. Pure (no DB, no I/O) so it's directly unit-testable —
/// callers are expected to have already filtered each list to the session's
/// own `[openedAt, closedAt)` window.
///
/// An expense's `accountId` (added by the Payment Accounts feature) marks it
/// as paid from a non-cash account; a null `accountId` means it came out of
/// the till, same convention `payment_account_repository.dart` uses in
/// reverse. Only till-paid expenses should reduce the drawer. A supplier
/// payment with `method == 'cash'` likewise empties the till (the Accounts
/// Payable mirror of a cash expense) and is subtracted here — omitting it
/// left the drawer's expected figure permanently too high whenever a supplier
/// was paid in cash (regression: supplier payments were added by the
/// Accounts Payable feature but `computeExpectedCash` was never updated to
/// fold them). [topUps] is cash physically added to the drawer mid-session
/// (e.g. the owner covering a shortfall from their own pocket) — see
/// `CashTopUps`' doc comment in tables.dart for why this is deliberately
/// separate from Owner's Equity's Contribution/Drawing ledger.
int computeExpectedCash({
  required int openingAmount,
  required List<Payment> payments,
  required List<CreditPayment> repayments,
  required List<Expense> expenses,
  required List<SupplierPayment> supplierPayments,
  required List<CashTopUp> topUps,
}) {
  final cashIn = payments
          .where((p) => p.method == 'cash')
          .fold<int>(0, (sum, p) => sum + p.amount) +
      repayments
          .where((r) => r.method == 'cash')
          .fold<int>(0, (sum, r) => sum + r.amount) +
      topUps.fold<int>(0, (sum, t) => sum + t.amount);
  final cashOut = expenses
      .where((e) => e.accountId == null)
      .fold<int>(0, (sum, e) => sum + e.amount) +
      supplierPayments
          .where((p) => p.method == 'cash')
          .fold<int>(0, (sum, p) => sum + p.amount);
  return openingAmount + cashIn - cashOut;
}

/// Itemized breakdown behind one session's [CashSessionRepository.reportFor]
/// — same inputs [computeExpectedCash] folds into a single int, kept apart
/// here for a printable/shareable end-of-day summary. [variance] and
/// [closingAmount] are null while the session is still open.
class CashSessionReport {
  final int openingAmount;
  final int cashSalesTotal;
  final int cashRepaymentsTotal;
  final int topUpsTotal;
  final int expensesTotal;
  final int supplierPaymentsTotal;
  final int expectedCash;
  final int? closingAmount;
  final int? variance;

  const CashSessionReport({
    required this.openingAmount,
    required this.cashSalesTotal,
    required this.cashRepaymentsTotal,
    required this.topUpsTotal,
    required this.expensesTotal,
    required this.supplierPaymentsTotal,
    required this.expectedCash,
    required this.closingAmount,
    required this.variance,
  });
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

  /// Every non-deleted supplier payment for this shop, unfiltered by date —
  /// mirrors [watchAllExpenses], used only to trigger [expectedCash]
  /// recomputation when one is recorded (a cash-paid supplier payment empties
  /// the till). The caller filters by session window itself.
  Stream<List<SupplierPayment>> watchAllSupplierPayments() {
    return (_db.select(_db.supplierPayments)
            ..where((t) => t.shopId.equals(_shopId) & t.isDeleted.equals(false)))
        .watch();
  }

  /// Every non-deleted sale payment for this shop, unfiltered by date —
  /// mirrors [watchAllExpenses]/[watchAllSupplierPayments]. [expectedCash]
  /// reads `payments` directly but nothing was watching that table; a sale
  /// and its payment land in separate sync-pull transactions (see
  /// sync_mappers.dart's syncTables order), so relying on `salesStreamProvider`
  /// alone as a proxy could miss a payment that arrives in its own later
  /// transaction, leaving the drawer's expected-cash figure stale.
  Stream<List<Payment>> watchAllPayments() {
    return (_db.select(_db.payments)
            ..where((t) => t.shopId.equals(_shopId) & t.isDeleted.equals(false)))
        .watch();
  }

  /// Every non-deleted cash top-up for this shop, unfiltered by date —
  /// mirrors [watchAllExpenses]/[watchAllSupplierPayments], used only to
  /// trigger [expectedCash] recomputation when one is recorded.
  Stream<List<CashTopUp>> watchAllTopUps() {
    return (_db.select(_db.cashTopUps)
            ..where((t) => t.shopId.equals(_shopId) & t.isDeleted.equals(false)))
        .watch();
  }

  /// Records cash physically added to the drawer mid-session — see
  /// `CashTopUps`' doc comment in tables.dart. Not scoped to a specific
  /// session id; it's picked up by whichever session's window it falls in
  /// (same convention as an [Expense]/[SupplierPayment]).
  Future<String> addTopUp({required int amount, String? note}) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db.into(_db.cashTopUps).insert(CashTopUpsCompanion.insert(
            id: id,
            shopId: _shopId,
            amount: amount,
            note: Value(note),
            updatedAt: Value(now),
            dirty: const Value(true),
          ));
      await _enqueueTopUp(id);
    });
    return id;
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
      // Audit QA-M4: at most one open session per shop. The check lives
      // INSIDE the transaction (Drift serializes transactions) so a
      // double-tap or a stale "closed" screen can't race a second session
      // into existence — overlapping windows would double-count cash-in on
      // both. Cross-device offline opens remain a documented residual.
      final open = await (_db.select(_db.cashSessions)
            ..where((t) =>
                t.shopId.equals(_shopId) &
                t.isDeleted.equals(false) &
                t.closedAt.isNull())
            ..limit(1))
          .get();
      if (open.isNotEmpty) {
        throw StateError('session_already_open');
      }
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
      final existing = await (_db.select(_db.cashSessions)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (existing == null) {
        throw StateError('session_not_found');
      }
      if (existing.closedAt != null) {
        throw StateError('already_closed');
      }
      // Snapshot while still open so later till-expense edits cannot
      // rewrite this session's expected/variance (P6).
      final expected = await expectedCash(existing);
      await (_db.update(_db.cashSessions)..where((t) => t.id.equals(id)))
          .write(CashSessionsCompanion(
        closedAt: Value(now),
        closingAmount: Value(closingAmount),
        expectedCashAtClose: Value(expected),
        note: note == null ? const Value.absent() : Value(note),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueue(id);
    });
  }

  /// What the drawer should hold right now (or at close, if [session] is
  /// already closed) — fetches this shop's payments/repayments/expenses/
  /// supplier payments within the session's window and hands them to
  /// [computeExpectedCash].
  Future<int> expectedCash(CashSession session) async {
    if (session.closedAt != null && session.expectedCashAtClose != null) {
      return session.expectedCashAtClose!;
    }
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
                  // Fold by createdAt, NOT the business `date` (audit QA-M6):
                  // the cash physically left the till when the expense was
                  // RECORDED, so a back-dated entry made during this session
                  // must still reduce the drawer — while an entry recorded
                  // yesterday but dated today correctly belongs to the
                  // previous session. Reports/P&L keep using `date`.
                  t.createdAt.isBiggerOrEqualValue(session.openedAt);
              if (end != null) {
                pred = pred & t.createdAt.isSmallerThanValue(end);
              }
              return pred;
            }))
        .get();
    final supplierPayments = await (_db.select(_db.supplierPayments)
            ..where((t) {
              var pred = t.shopId.equals(_shopId) &
                  t.isDeleted.equals(false) &
                  t.createdAt.isBiggerOrEqualValue(session.openedAt);
              if (end != null) pred = pred & t.createdAt.isSmallerThanValue(end);
              return pred;
            }))
        .get();
    final topUps = await (_db.select(_db.cashTopUps)
            ..where((t) {
              var pred = t.shopId.equals(_shopId) &
                  t.isDeleted.equals(false) &
                  t.createdAt.isBiggerOrEqualValue(session.openedAt);
              if (end != null) pred = pred & t.createdAt.isSmallerThanValue(end);
              return pred;
            }))
        .get();

    return computeExpectedCash(
      openingAmount: session.openingAmount,
      payments: payments,
      repayments: repayments,
      expenses: expenses,
      supplierPayments: supplierPayments,
      topUps: topUps,
    );
  }

  /// Same window/queries as [expectedCash], kept as per-category subtotals
  /// for a printable/shareable end-of-day summary — added alongside
  /// [expectedCash] rather than refactored out of it (the same function
  /// already calls all four), so the same `computeExpectedCash` logic is
  /// the single source of truth.
  Future<CashSessionReport> reportFor(CashSession session) async {
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
                  // Same createdAt window as [expectedCash] — the itemized
                  // report must reconcile against the same physical drawer
                  // math (audit QA-M6).
                  t.createdAt.isBiggerOrEqualValue(session.openedAt);
              if (end != null) {
                pred = pred & t.createdAt.isSmallerThanValue(end);
              }
              return pred;
            }))
        .get();
    final supplierPayments = await (_db.select(_db.supplierPayments)
            ..where((t) {
              var pred = t.shopId.equals(_shopId) &
                  t.isDeleted.equals(false) &
                  t.createdAt.isBiggerOrEqualValue(session.openedAt);
              if (end != null) {
                pred = pred & t.createdAt.isSmallerThanValue(end);
              }
              return pred;
            }))
        .get();
    final topUps = await (_db.select(_db.cashTopUps)
            ..where((t) {
              var pred = t.shopId.equals(_shopId) &
                  t.isDeleted.equals(false) &
                  t.createdAt.isBiggerOrEqualValue(session.openedAt);
              if (end != null) {
                pred = pred & t.createdAt.isSmallerThanValue(end);
              }
              return pred;
            }))
        .get();

    final cashSalesTotal = payments
        .where((p) => p.method == 'cash')
        .fold<int>(0, (sum, p) => sum + p.amount);
    final cashRepaymentsTotal = repayments
        .where((r) => r.method == 'cash')
        .fold<int>(0, (sum, r) => sum + r.amount);
    final topUpsTotal = topUps.fold<int>(0, (sum, t) => sum + t.amount);
    final expensesTotal = expenses
        .where((e) => e.accountId == null)
        .fold<int>(0, (sum, e) => sum + e.amount);
    final supplierPaymentsTotal = supplierPayments
        .where((p) => p.method == 'cash')
        .fold<int>(0, (sum, p) => sum + p.amount);
    final liveExpected = session.openingAmount +
        cashSalesTotal +
        cashRepaymentsTotal +
        topUpsTotal -
        expensesTotal -
        supplierPaymentsTotal;
    final expectedCash =
        (session.closedAt != null && session.expectedCashAtClose != null)
            ? session.expectedCashAtClose!
            : liveExpected;

    return CashSessionReport(
      openingAmount: session.openingAmount,
      cashSalesTotal: cashSalesTotal,
      cashRepaymentsTotal: cashRepaymentsTotal,
      topUpsTotal: topUpsTotal,
      expensesTotal: expensesTotal,
      supplierPaymentsTotal: supplierPaymentsTotal,
      expectedCash: expectedCash,
      closingAmount: session.closingAmount,
      variance: session.closingAmount == null
          ? null
          : session.closingAmount! - expectedCash,
    );
  }

  /// Physical cash this shop holds for the books: open session's live
  /// expected, else the last counted close, else all-time till movements
  /// (shops that never opened Cash Register).
  Future<int> physicalCashNow() async {
    final open = await (_db.select(_db.cashSessions)
          ..where((t) =>
              t.shopId.equals(_shopId) &
              t.isDeleted.equals(false) &
              t.closedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.openedAt)])
          ..limit(1))
        .getSingleOrNull();
    if (open != null) return expectedCash(open);

    final lastClosed = await (_db.select(_db.cashSessions)
          ..where((t) =>
              t.shopId.equals(_shopId) &
              t.isDeleted.equals(false) &
              t.closedAt.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.closedAt)])
          ..limit(1))
        .getSingleOrNull();
    if (lastClosed != null) {
      // The counted/expected figure at close is only the base — cash
      // activity can still be recorded with no session open (an expense,
      // supplier payment, credit repayment, or top-up none of which require
      // one), and without folding those in here the Balance Sheet's cash
      // line would stay frozen at last night's closing count until the
      // next session is both opened AND closed. Fold in everything dated
      // after the close, same shape as the never-opened-a-session fold
      // below, added on top of the closing base instead of from zero.
      final base =
          lastClosed.closingAmount ?? lastClosed.expectedCashAtClose ?? 0;
      final closedAt = lastClosed.closedAt!;
      final paymentsAfter = await (_db.select(_db.payments)
            ..where((t) =>
                t.shopId.equals(_shopId) &
                t.isDeleted.equals(false) &
                t.createdAt.isBiggerThanValue(closedAt)))
          .get();
      final repaymentsAfter = await (_db.select(_db.creditPayments)
            ..where((t) =>
                t.shopId.equals(_shopId) &
                t.isDeleted.equals(false) &
                t.createdAt.isBiggerThanValue(closedAt)))
          .get();
      final expensesAfter = await (_db.select(_db.expenses)
            ..where((t) =>
                t.shopId.equals(_shopId) &
                t.isDeleted.equals(false) &
                t.createdAt.isBiggerThanValue(closedAt)))
          .get();
      final supplierPaymentsAfter = await (_db.select(_db.supplierPayments)
            ..where((t) =>
                t.shopId.equals(_shopId) &
                t.isDeleted.equals(false) &
                t.createdAt.isBiggerThanValue(closedAt)))
          .get();
      final topUpsAfter = await (_db.select(_db.cashTopUps)
            ..where((t) =>
                t.shopId.equals(_shopId) &
                t.isDeleted.equals(false) &
                t.createdAt.isBiggerThanValue(closedAt)))
          .get();
      final deltaSinceClose = computeExpectedCash(
        openingAmount: 0,
        payments: paymentsAfter,
        repayments: repaymentsAfter,
        expenses: expensesAfter,
        supplierPayments: supplierPaymentsAfter,
        topUps: topUpsAfter,
      );
      return base + deltaSinceClose;
    }

    final payments = await (_db.select(_db.payments)
          ..where((t) =>
              t.shopId.equals(_shopId) & t.isDeleted.equals(false)))
        .get();
    final repayments = await (_db.select(_db.creditPayments)
          ..where((t) =>
              t.shopId.equals(_shopId) & t.isDeleted.equals(false)))
        .get();
    final expenses = await (_db.select(_db.expenses)
          ..where((t) =>
              t.shopId.equals(_shopId) & t.isDeleted.equals(false)))
        .get();
    final supplierPayments = await (_db.select(_db.supplierPayments)
          ..where((t) =>
              t.shopId.equals(_shopId) & t.isDeleted.equals(false)))
        .get();
    final topUps = await (_db.select(_db.cashTopUps)
          ..where((t) =>
              t.shopId.equals(_shopId) & t.isDeleted.equals(false)))
        .get();
    return computeExpectedCash(
      openingAmount: 0,
      payments: payments,
      repayments: repayments,
      expenses: expenses,
      supplierPayments: supplierPayments,
      topUps: topUps,
    );
  }

  Future<void> _enqueue(String id) async {
    await _db.into(_db.outbox).insert(OutboxCompanion.insert(
          entityTable: 'cash_sessions',
          rowId: id,
          op: 'upsert',
        ));
  }

  Future<void> _enqueueTopUp(String id) async {
    await _db.into(_db.outbox).insert(OutboxCompanion.insert(
          entityTable: 'cash_top_ups',
          rowId: id,
          op: 'upsert',
        ));
  }
}
