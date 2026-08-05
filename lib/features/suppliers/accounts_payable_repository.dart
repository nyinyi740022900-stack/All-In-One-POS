import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';

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
      final row = await (_db.select(_db.supplierPayments)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      await _db.into(_db.outbox).insert(OutboxCompanion.insert(
            entityTable: 'supplier_payments',
            rowId: id,
            op: 'upsert',
            payload: jsonEncode(row.toJson()),
          ));
    });
  }
}
