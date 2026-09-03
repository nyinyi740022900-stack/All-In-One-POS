
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
            // `Value.absent()` when omitted, NOT `Value(null)`: this is an
      // upsert, so passing null actively WROTE null over any township
      // already on file. Harmless only while nothing populates the
      // column — a data-loss trap the moment something does.
      township: township == null ? const Value.absent() : Value(township),
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
  /// [phone]/[address] backfill the directory entry only where it didn't
  /// already have a value (never overwrites one already on file).
  Future<String> resolveOrCreate(String name,
      {String? phone, String? address}) async {
    final trimmed = name.trim();
    // `getSingleOrNull` THROWS when more than one row matches, and nothing
    // stops duplicate names: the directory has no uniqueness check, and two
    // devices creating "Ma Aye" offline both sync in. That turned every
    // credit sale to a duplicated name into a permanent, unexplained
    // checkout failure (the caller only surfaces a generic error). Take the
    // oldest match instead — it is the one other rows most likely already
    // reference, and merging duplicates is a directory problem, not a
    // reason to block the sale.
    final matches = await (_db.select(_db.customers)
          ..where((t) =>
              t.shopId.equals(_shopId) &
              t.isDeleted.equals(false) &
              t.name.lower().equals(trimmed.toLowerCase()))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
          ..limit(1))
        .get();
    final existing = matches.isEmpty ? null : matches.first;
    if (existing != null) {
      final needsPhone =
          (existing.phone ?? '').isEmpty && (phone ?? '').isNotEmpty;
      final needsAddress =
          (existing.address ?? '').isEmpty && (address ?? '').isNotEmpty;
      if (needsPhone || needsAddress) {
        await upsertCustomer(
          id: existing.id,
          name: existing.name,
          phone: needsPhone ? phone : existing.phone,
          address: needsAddress ? address : existing.address,
          tier: existing.tier,
        );
      }
      return existing.id;
    }
    return upsertCustomer(name: trimmed, phone: phone, address: address);
  }

  Future<void> _enqueue(String id) async {
    await _db.into(_db.outbox).insert(OutboxCompanion.insert(
          entityTable: 'customers',
          rowId: id,
          op: 'upsert',
        ));
  }
}
