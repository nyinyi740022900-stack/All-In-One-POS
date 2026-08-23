
import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';

/// SHA-256 of `memberId:pin`, prefixed so [StaffRepository.verifyPin] can
/// tell a hashed row from a legacy plaintext one at a glance. Salting with
/// the member's own id (a random UUID, unique per row) means no separate
/// salt column is needed. Not a general-purpose auth secret (see the table
/// doc comment) — just enough to stop a copy of the synced `staff_members`
/// table from handing out everyone's PIN in the clear.
String _hashPin(String memberId, String pin) {
  final digest = sha256.convert(utf8.encode('$memberId:$pin'));
  return 'v1:$digest';
}

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

  /// Verifies [pin] against the stored hash. Rows written before hashing was
  /// added still hold a plaintext PIN (no `v1:` prefix) — a successful
  /// plaintext match is upgraded to a hash in place, so the roster migrates
  /// itself the first time each member's PIN is used, with no separate
  /// migration step.
  Future<StaffMember?> verifyPin(String memberId, String pin) async {
    final m = await (_db.select(_db.staffMembers)
          ..where((t) => t.id.equals(memberId)))
        .getSingleOrNull();
    if (m == null) return null;
    if (m.pin.startsWith('v1:')) {
      return m.pin == _hashPin(memberId, pin) ? m : null;
    }
    if (m.pin != pin) return null;
    await _db.transaction(() async {
      await (_db.update(_db.staffMembers)..where((t) => t.id.equals(memberId)))
          .write(StaffMembersCompanion(
        pin: Value(_hashPin(memberId, pin)),
        updatedAt: Value(DateTime.now()),
        dirty: const Value(true),
      ));
      await _enqueue(memberId);
    });
    return m;
  }

  /// [pin] is required when adding a new member ([id] null). When editing an
  /// existing member, pass null/empty to leave their PIN unchanged — the
  /// editor UI never re-displays a stored PIN (it's a hash now), so "leave
  /// blank to keep the current PIN" is the only way to edit just the name.
  Future<String> upsertMember({String? id, required String name, String? pin}) async {
    final memberId = id ?? _uuid.v4();
    final now = DateTime.now();
    String pinHash;
    if (pin != null && pin.isNotEmpty) {
      pinHash = _hashPin(memberId, pin);
    } else if (id != null) {
      final existing = await (_db.select(_db.staffMembers)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (existing == null) {
        throw ArgumentError('pin is required: no existing member to keep it from');
      }
      pinHash = existing.pin;
    } else {
      throw ArgumentError('pin is required for a new staff member');
    }
    await _db.transaction(() async {
      await _db.into(_db.staffMembers).insertOnConflictUpdate(
          StaffMembersCompanion(
            id: Value(memberId),
            shopId: Value(_shopId),
            name: Value(name),
            pin: Value(pinHash),
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
    await _db.into(_db.outbox).insert(OutboxCompanion.insert(
          entityTable: 'staff_members',
          rowId: memberId,
          op: 'upsert',
        ));
  }
}
