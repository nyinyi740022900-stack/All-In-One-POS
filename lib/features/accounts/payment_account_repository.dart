import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';
import '../../data/repositories/settings_repository.dart';

/// A running balance for one [PaymentAccounts] row: [openingBalance] plus
/// every payment/repayment tendered into this account, minus every expense
/// or supplier payment paid from it. Pure (no DB, no I/O) — mirrors
/// `computeExpectedCash` (`cash_session_repository.dart`), generalized
/// from a hardcoded `'cash'` filter to any account id. Never stored —
/// always derived at read time (see the doc comment on `PaymentAccounts`
/// in tables.dart for why).
int computeAccountBalance({
  required int openingBalance,
  required List<Payment> payments,
  required List<CreditPayment> repayments,
  required List<Expense> expenses,
  required List<SupplierPayment> supplierPayments,
  required String accountId,
}) {
  final inflow = payments
          .where((p) => p.method == accountId)
          .fold<int>(0, (sum, p) => sum + p.amount) +
      repayments
          .where((r) => r.method == accountId)
          .fold<int>(0, (sum, r) => sum + r.amount);
  final outflow = expenses
          .where((e) => e.accountId == accountId)
          .fold<int>(0, (sum, e) => sum + e.amount) +
      supplierPayments
          .where((p) => p.method == accountId)
          .fold<int>(0, (sum, p) => sum + p.amount);
  return openingBalance + inflow - outflow;
}

/// The shop's payment-account directory (KBZPay, WavePay, or any custom one
/// the owner adds) — same shape as `SupplierRepository`. Cash stays a
/// separate, untouched concept (Cash Register/`CashSessionRepository`).
class PaymentAccountRepository {
  PaymentAccountRepository(this._db, this._shopId, this._settings);

  final AppDatabase _db;
  final String _shopId;
  final SettingsRepository _settings;
  static const _uuid = Uuid();

  /// The 4 payment methods the app has always offered by default — seeded
  /// once (see [ensureDefaultsSeeded]) using these exact ids/names so
  /// existing sales (`Sales.paymentMethod`/`Payments.method` already
  /// storing e.g. `'kbzpay'`) keep resolving to the same account with no
  /// data migration needed.
  ///
  /// Ids are **per-shop codes**, not global UUIDs. Locally (one shop DB
  /// file) `id` is unique; on Supabase the PK is `(shop_id, id)` so every
  /// branch can own its own `kbzpay` row (migration `0054`).
  static const defaultAccounts = {
    'kbzpay': 'KBZPay',
    'wavepay': 'WavePay',
    'ayapay': 'AYA Pay',
    'cbpay': 'CB Pay',
  };

  Stream<List<PaymentAccount>> watchAccounts() {
    return (_db.select(_db.paymentAccounts)
          ..where((t) => t.shopId.equals(_shopId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .watch();
  }

  Future<PaymentAccount?> getAccount(String id) {
    return (_db.select(_db.paymentAccounts)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<String> upsertAccount({
    String? id,
    required String name,
    int openingBalance = 0,
  }) async {
    final accountId = id ?? _uuid.v4();
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db.into(_db.paymentAccounts).insertOnConflictUpdate(
            PaymentAccountsCompanion(
              id: Value(accountId),
              shopId: Value(_shopId),
              name: Value(name),
              openingBalance: Value(openingBalance),
              updatedAt: Value(now),
              dirty: const Value(true),
            ),
          );
      await _enqueue(accountId);
    });
    return accountId;
  }

  Future<void> deleteAccount(String id) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.paymentAccounts)..where((t) => t.id.equals(id)))
          .write(PaymentAccountsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueue(id);
    });
  }

  /// The account's current balance, all-time (not windowed like a Cash
  /// Register session — a digital account isn't opened/closed daily).
  Future<int> balanceFor(PaymentAccount account) async {
    final payments = await (_db.select(_db.payments)
          ..where((t) => t.shopId.equals(_shopId) & t.isDeleted.equals(false)))
        .get();
    final repayments = await (_db.select(_db.creditPayments)
          ..where((t) => t.shopId.equals(_shopId) & t.isDeleted.equals(false)))
        .get();
    final expenses = await (_db.select(_db.expenses)
          ..where((t) => t.shopId.equals(_shopId) & t.isDeleted.equals(false)))
        .get();
    final supplierPayments = await (_db.select(_db.supplierPayments)
          ..where((t) => t.shopId.equals(_shopId) & t.isDeleted.equals(false)))
        .get();
    return computeAccountBalance(
      openingBalance: account.openingBalance,
      payments: payments,
      repayments: repayments,
      expenses: expenses,
      supplierPayments: supplierPayments,
      accountId: account.id,
    );
  }

  /// One-shot **per shop**: seeds the 4 default accounts the app has always
  /// offered, so an upgrading shop's checkout looks identical to before.
  /// No-ops after the first successful run for this shop (persisted flag),
  /// so a shop that later deletes some/all of them never has them silently
  /// reappear — but a *different* shop this device later switches/adds a
  /// branch to still gets seeded on its own first run.
  Future<void> ensureDefaultsSeeded() async {
    if (await _settings.paymentAccountsSeeded(_shopId)) return;
    final now = DateTime.now();
    await _db.transaction(() async {
      for (final entry in defaultAccounts.entries) {
        await _db.into(_db.paymentAccounts).insertOnConflictUpdate(
              PaymentAccountsCompanion(
                id: Value(entry.key),
                shopId: Value(_shopId),
                name: Value(entry.value),
                openingBalance: const Value(0),
                updatedAt: Value(now),
                dirty: const Value(true),
              ),
            );
        await _enqueue(entry.key);
      }
    });
    await _settings.setPaymentAccountsSeeded(_shopId);
  }

  Future<void> _enqueue(String id) async {
    final row = await (_db.select(_db.paymentAccounts)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    await _db.into(_db.outbox).insert(OutboxCompanion.insert(
          entityTable: 'payment_accounts',
          rowId: id,
          op: 'upsert',
          payload: jsonEncode(row.toJson()),
        ));
  }
}
