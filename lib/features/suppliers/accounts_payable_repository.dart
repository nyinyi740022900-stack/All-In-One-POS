
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';
import 'accounts_payable.dart';

/// Reads received purchase orders + supplier payments and records new
/// payments — the write/read side of Accounts Payable. Aggregation itself
/// is the pure `aggregateAccountsPayable` (`accounts_payable.dart`).
class AccountsPayableRepository {
  AccountsPayableRepository(this._db, this._shopId);

  final AppDatabase _db;
  final String _shopId;
  static const _uuid = Uuid();

  /// Only `received` POs count toward Accounts Payable — an `open` one
  /// hasn't incurred a debt yet, a `cancelled` one never will.
  Stream<List<PurchaseOrder>> watchReceivedPOs() {
    return (_db.select(_db.purchaseOrders)
          ..where((t) =>
              t.shopId.equals(_shopId) &
              t.isDeleted.equals(false) &
              t.status.equals('received'))
          ..orderBy([(t) => OrderingTerm.desc(t.receivedAt)]))
        .watch();
  }

  Stream<List<SupplierPayment>> watchPayments() {
    return (_db.select(_db.supplierPayments)
          ..where((t) => t.shopId.equals(_shopId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Records a payment toward a supplier's outstanding balance and queues
  /// it for sync.
  Future<void> recordPayment({
    required String supplierName,
    String? supplierId,
    required int amount,
    String method = 'cash',
    String? note,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    await _db.transaction(() async {
      final pos = await (_db.select(_db.purchaseOrders)
            ..where((t) =>
                t.shopId.equals(_shopId) &
                t.isDeleted.equals(false) &
                t.status.equals('received')))
          .get();
      final existingPayments = await (_db.select(_db.supplierPayments)
            ..where((t) =>
                t.shopId.equals(_shopId) & t.isDeleted.equals(false)))
          .get();
      final key = poSupplierKeyFor(supplierId, supplierName);
      final balances = aggregateAccountsPayable(
        pos,
        existingPayments,
        includeSettled: true,
      );
      final match = balances.where((b) => b.key == key);
      final outstanding = match.isEmpty ? 0 : match.first.outstanding;
      if (amount > outstanding) {
        throw StateError('payment_exceeds_outstanding');
      }
      await _db.into(_db.supplierPayments).insert(
            SupplierPaymentsCompanion.insert(
              id: id,
              shopId: _shopId,
              supplierName: supplierName.trim(),
              supplierId: Value(supplierId),
              amount: amount,
              method: Value(method),
              note: Value(note),
              updatedAt: Value(now),
            ),
          );
      await _db.into(_db.outbox).insert(OutboxCompanion.insert(
            entityTable: 'supplier_payments',
            rowId: id,
            op: 'upsert',
          ));
    });
  }
}
