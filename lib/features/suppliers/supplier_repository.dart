
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';

/// The shop's supplier directory — same shape as `CustomerRepository`, used
/// by `PurchaseOrderRepository`. See `Suppliers` in tables.dart.
class SupplierRepository {
  SupplierRepository(this._db, this._shopId);

  final AppDatabase _db;
  final String _shopId;
  static const _uuid = Uuid();

  Stream<List<Supplier>> watchSuppliers() {
    return (_db.select(_db.suppliers)
          ..where((t) => t.shopId.equals(_shopId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .watch();
  }

  Future<Supplier?> getSupplier(String id) {
    return (_db.select(_db.suppliers)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<String> upsertSupplier({
    String? id,
    required String name,
    String? phone,
    String? address,
    String? note,
  }) async {
    final supplierId = id ?? _uuid.v4();
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db.into(_db.suppliers).insertOnConflictUpdate(
            SuppliersCompanion(
              id: Value(supplierId),
              shopId: Value(_shopId),
              name: Value(name),
              phone: Value(phone),
              address: Value(address),
              note: Value(note),
              updatedAt: Value(now),
              dirty: const Value(true),
            ),
          );
      await _enqueue(supplierId);
    });
    return supplierId;
  }

  Future<void> deleteSupplier(String id) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.suppliers)..where((t) => t.id.equals(id)))
          .write(SuppliersCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueue(id);
    });
  }

  Future<void> _enqueue(String id) async {
    await _db.into(_db.outbox).insert(OutboxCompanion.insert(
          entityTable: 'suppliers',
          rowId: id,
          op: 'upsert',
        ));
  }
}
