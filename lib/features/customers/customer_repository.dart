import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';

/// The shop's customer directory — enter a name/phone/address once and
/// reuse it on invoices/orders instead of retyping. See `Customers` in
/// tables.dart for the sync/snapshot design.
class CustomerRepository {
  CustomerRepository(this._db, this._shopId);

  final AppDatabase _db;
  final String _shopId;
  static const _uuid = Uuid();

  Stream<List<Customer>> watchCustomers() {
    return (_db.select(_db.customers)
          ..where((t) => t.shopId.equals(_shopId) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .watch();
  }

  Future<Customer?> getCustomer(String id) {
    return (_db.select(_db.customers)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<String> upsertCustomer({
    String? id,
    required String name,
    String? phone,
    String? address,
    String? township,
    String tier = 'retail',
  }) async {
    final customerId = id ?? _uuid.v4();
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db.into(_db.customers).insertOnConflictUpdate(
          CustomersCompanion(
            id: Value(customerId),
            shopId: Value(_shopId),
            name: Value(name),
            phone: Value(phone),
            address: Value(address),
            township: Value(township),
            tier: Value(tier),
            updatedAt: Value(now),
            dirty: const Value(true),
          ));
      await _enqueue(customerId);
    });
    return customerId;
  }

  Future<void> deleteCustomer(String id) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.customers)..where((t) => t.id.equals(id)))
          .write(CustomersCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueue(id);
    });
  }

  /// Resolves a typed customer name to a directory entry: reuses an existing
  /// customer with the exact same name (case-insensitive) if one exists —
  /// so a seller who always types the same name for a regular still gets
  /// them linked to one directory entry — otherwise creates a new one.
  /// [phone] backfills the directory entry's phone only if it didn't have
  /// one already (never overwrites a phone number already on file).
  Future<String> resolveOrCreate(String name, {String? phone}) async {
    final trimmed = name.trim();
    final existing = await (_db.select(_db.customers)
          ..where((t) =>
              t.shopId.equals(_shopId) &
              t.isDeleted.equals(false) &
              t.name.lower().equals(trimmed.toLowerCase())))
        .getSingleOrNull();
    if (existing != null) {
      if ((existing.phone ?? '').isEmpty &&
          phone != null &&
          phone.isNotEmpty) {
        await upsertCustomer(
            id: existing.id, name: existing.name, phone: phone);
      }
      return existing.id;
    }
    return upsertCustomer(name: trimmed, phone: phone);
  }

  Future<void> _enqueue(String id) async {
    final row =
        await (_db.select(_db.customers)..where((t) => t.id.equals(id)))
            .getSingle();
    await _db.into(_db.outbox).insert(OutboxCompanion.insert(
          entityTable: 'customers',
          rowId: id,
          op: 'upsert',
          payload: jsonEncode(row.toJson()),
        ));
  }
}
