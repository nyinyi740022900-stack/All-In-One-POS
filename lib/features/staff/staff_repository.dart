
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';
import 'owner_permission.dart';

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
  bool _legacyHashStarted = false;

  Stream<List<StaffMember>> watchActiveMembers() {
    if (!_legacyHashStarted) {
      _legacyHashStarted = true;
      unawaited(hashLegacyPins());
    }
    return (_db.select(_db.staffMembers)
          ..where((t) =>
              t.shopId.equals(_shopId) &
              t.isDeleted.equals(false) &
              t.active.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .watch();
  }

  /// One-shot: hash leftover plaintext PINs so unused roster members are
  /// not stored in the clear until their first login (N14).
  Future<void> hashLegacyPins() async {
    final rows = await (_db.select(_db.staffMembers)
          ..where((t) =>
              t.shopId.equals(_shopId) & t.isDeleted.equals(false)))
        .get();
    for (final m in rows) {
      if (m.pin.startsWith('v1:')) continue;
      await _db.transaction(() async {
        await (_db.update(_db.staffMembers)..where((t) => t.id.equals(m.id)))
            .write(StaffMembersCompanion(
          pin: Value(_hashPin(m.id, m.pin)),
          updatedAt: Value(DateTime.now()),
          dirty: const Value(true),
        ));
        await _enqueue(m.id);
      });
    }
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
  /// [email] is optional — when set, it links this roster row to an
  /// invited-email `StaffAccount` sharing the same address (see
  /// `StaffMembers.email`'s doc comment in tables.dart); pass an empty
  /// string to clear a previously-set email.
  Future<String> upsertMember({
    String? id,
    required String name,
    String? pin,
    String? email,
  }) async {
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
    final normalizedEmail = (email ?? '').trim().toLowerCase();
    await _db.transaction(() async {
      await _db.into(_db.staffMembers).insertOnConflictUpdate(
          StaffMembersCompanion(
            id: Value(memberId),
            shopId: Value(_shopId),
            name: Value(name),
            pin: Value(pinHash),
            active: const Value(true),
            email: Value(normalizedEmail.isEmpty ? null : normalizedEmail),
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

  /// Which [OwnerCapability]s [staffMemberId] has been explicitly granted —
  /// empty means none (default-deny; see [StaffPermissions]' doc comment).
  /// Unknown capability strings (e.g. from a future app version's enum
  /// member reaching an older device) are skipped rather than crashing.
  Stream<Set<OwnerCapability>> watchGrantedCapabilities(String staffMemberId) {
    return (_db.select(_db.staffPermissions)
          ..where((t) =>
              t.staffMemberId.equals(staffMemberId) & t.isDeleted.equals(false)))
        .watch()
        .map((rows) {
      final out = <OwnerCapability>{};
      for (final r in rows) {
        for (final c in OwnerCapability.values) {
          if (c.name == r.capability) {
            out.add(c);
            break;
          }
        }
      }
      return out;
    });
  }

  /// Grants or revokes one [capability] for [staffMemberId]. Revoking
  /// tombstones the existing row (`isDeleted = true`) rather than deleting
  /// it, so there is always exactly one row per (staffMemberId, capability)
  /// pair that flips state in place — matching [upsertMember]'s tombstone
  /// convention for the roster itself.
  Future<void> setCapabilityGranted(
    String staffMemberId,
    OwnerCapability capability,
    bool granted,
  ) async {
    final now = DateTime.now();
    final existing = await (_db.select(_db.staffPermissions)
          ..where((t) =>
              t.staffMemberId.equals(staffMemberId) &
              t.capability.equals(capability.name)))
        .getSingleOrNull();
    if (existing == null) {
      if (!granted) return; // nothing to revoke
      final id = _uuid.v4();
      await _db.transaction(() async {
        await _db.into(_db.staffPermissions).insert(
              StaffPermissionsCompanion.insert(
                id: id,
                shopId: _shopId,
                staffMemberId: staffMemberId,
                capability: capability.name,
                updatedAt: Value(now),
                dirty: const Value(true),
              ),
            );
        await _enqueuePermission(id);
      });
      return;
    }
    await _db.transaction(() async {
      await (_db.update(_db.staffPermissions)
            ..where((t) => t.id.equals(existing.id)))
          .write(StaffPermissionsCompanion(
        isDeleted: Value(!granted),
        updatedAt: Value(now),
        dirty: const Value(true),
      ));
      await _enqueuePermission(existing.id);
    });
  }

  Future<void> _enqueuePermission(String id) async {
    await _db.into(_db.outbox).insert(OutboxCompanion.insert(
          entityTable: 'staff_permissions',
          rowId: id,
          op: 'upsert',
        ));
  }
}
