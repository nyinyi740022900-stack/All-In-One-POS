import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';

/// Owns the shop's staff roster (name + PIN profiles) — see `StaffMembers`
/// in tables.dart for why this is deliberately lightweight (no real login
/// account). Synced like any other shop entity via the outbox.
class StaffRepository {
  StaffRepository(this._db, this._shopId);

  final AppDatabase _db;
  final String _shopId;
  static const _uuid = Uuid();

  Stream<List<StaffMember>> watchActiveMembers() {
    return (_db.select(_db.staffMembers)
          ..where((t) =>
              t.shopId.equals(_shopId) &
              t.isDeleted.equals(false) &
              t.active.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .watch();
  }

  Future<StaffMember?> verifyPin(String memberId, String pin) async {
    final m = await (_db.select(_db.staffMembers)
          ..where((t) => t.id.equals(memberId)))
        .getSingleOrNull();
    if (m == null || m.pin != pin) return null;
    return m;
  }

  Future<String> upsertMember({String? id, required String name, required String pin}) async {
    final memberId = id ?? _uuid.v4();
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db.into(_db.staffMembers).insertOnConflictUpdate(
          StaffMembersCompanion(
            id: Value(memberId),
            shopId: Value(_shopId),
            name: Value(name),
            pin: Value(pin),
            active: const Value(true),
            updatedAt: Value(now),
            dirty: const Value(true),
          ));
      await _enqueue(memberId);
    });
    return memberId;
  }

  /// Soft-removes a staff member from the roster. Kept (tombstoned), not hard
  /// deleted, so old sales' `staffId` still resolves for history.
  Future<void> deactivateMember(String memberId) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.staffMembers)..where((t) => t.id.equals(memberId)))
          .write(StaffMembersCompanion(
        active: const Value(false),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueue(memberId);
    });
  }

  Future<void> _enqueue(String memberId) async {
    final row = await (_db.select(_db.staffMembers)
          ..where((t) => t.id.equals(memberId)))
        .getSingle();
    await _db.into(_db.outbox).insert(OutboxCompanion.insert(
          entityTable: 'staff_members',
          rowId: memberId,
          op: 'upsert',
          payload: jsonEncode(row.toJson()),
        ));
  }
}
