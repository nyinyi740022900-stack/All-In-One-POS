import 'package:drift/drift.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/database.dart';
import '../repositories/settings_repository.dart';
import 'force_apply.dart';
import 'outbox_constants.dart';
import 'outbox_error.dart';
import 'sync_heal.dart';
import 'sync_mappers.dart';

/// Transport abstraction so the engine can be unit-tested with a fake backend.
abstract class SyncRemote {
  Future<void> upsert(String table, Map<String, dynamic> row,
      {String? onConflict});
  Future<void> markDeleted(
    String table,
    String id,
    DateTime updatedAt, {
    String? shopId,
  });

  /// Rows for [shopId] changed strictly after [since] (all rows if null),
  /// ordered by `updated_at` ascending.
  Future<List<Map<String, dynamic>>> fetchChanges(
      String table, String shopId, DateTime? since);

  /// Service-role heal via Edge Function (or in-memory for tests).
  Future<ForceApplyResult> forceApply({
    required String table,
    required String op,
    required String id,
    Map<String, dynamic>? row,
    String? onConflict,
  });
}

/// Supabase-backed transport (PostgREST upsert / filtered select).
class SupabaseSyncRemote implements SyncRemote {
  SupabaseSyncRemote(this._client);
  final SupabaseClient _client;

  @override
  Future<void> upsert(String table, Map<String, dynamic> row,
      {String? onConflict}) async {
    await _client.from(table).upsert(row, onConflict: onConflict);
  }

  @override
  Future<void> markDeleted(
    String table,
    String id,
    DateTime updatedAt, {
    String? shopId,
  }) async {
    var q = _client.from(table).update({
      'is_deleted': true,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    }).eq('id', id);
    if (shopId != null && shopId.isNotEmpty) {
      q = q.eq('shop_id', shopId);
    }
    await q;
  }

  static const _pageSize = 500;

  @override
  Future<List<Map<String, dynamic>>> fetchChanges(
      String table, String shopId, DateTime? since) async {
    final all = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final filter = _client.from(table).select().eq('shop_id', shopId);
      final scoped = since != null
          ? filter.gte('updated_at', since.toUtc().toIso8601String())
          : filter;
      final page = await scoped
          .order('updated_at', ascending: true)
          .range(offset, offset + _pageSize - 1);
      final rows = (page as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      all.addAll(rows);
      if (rows.length < _pageSize) break;
      offset += _pageSize;
    }
    return all;
  }

  @override
  Future<ForceApplyResult> forceApply({
    required String table,
    required String op,
    required String id,
    Map<String, dynamic>? row,
    String? onConflict,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'sync_force_apply',
        body: {
          'table': table,
          'op': op,
          'id': id,
          'row': ?row,
          'on_conflict': ?onConflict,
        },
      );
      final data = res.data;
      if (data is! Map) {
        return const ForceApplyResult(ForceApplyStatus.transient,
            detail: 'bad_response');
      }
      final map = Map<String, dynamic>.from(data);
      final status = map['status'] as String? ?? 'transient';
      final detail = map['detail'] as String?;
      return ForceApplyResult(
        switch (status) {
          'applied' => ForceApplyStatus.applied,
          'already_there' => ForceApplyStatus.alreadyThere,
          'rejected_invalid' => ForceApplyStatus.rejectedInvalid,
          _ => ForceApplyStatus.transient,
        },
        detail: detail,
      );
    } catch (e) {
      return ForceApplyResult(ForceApplyStatus.transient, detail: e.toString());
    }
  }
}

class SyncResult {
  final int pushed;
  final int pulled;
  const SyncResult(this.pushed, this.pulled);
}

/// Drains the outbox to the backend, then pulls remote changes and merges them
/// with last-write-wins. Failures auto-heal (remote-exists / FK pull /
/// force-apply) so owners never Discard or call Support for sync.
class SyncEngine {
  SyncEngine({
    required this.db,
    required this.remote,
    required this.settings,
    required this.shopId,
    List<SyncTableDef>? tables,
  }) : tables = tables ?? syncTables {
    _byName = {for (final t in this.tables) t.name: t};
  }

  final AppDatabase db;
  final SyncRemote remote;
  final SettingsRepository settings;
  final String shopId;
  final List<SyncTableDef> tables;
  late final Map<String, SyncTableDef> _byName;
  bool _didFkPullThisSync = false;

  Future<SyncResult> syncNow() async {
    _didFkPullThisSync = false;
    await _resetHealableRlsFailures();
    await _reconcileUpsertsAlreadyRemote();
    await _healForeignKeyFailures();
    await _quarantineAlreadyStuck();
    final pushed = await _push();
    await _forceApplyHeldRows();
    final pulled = await _pull();
    return SyncResult(pushed, pulled);
  }

  Future<void> _quarantineAlreadyStuck() async {
    final items = await (db.select(db.outbox)
          ..where((o) =>
              o.quarantined.equals(false) &
              o.attempts.isBiggerOrEqualValue(kOutboxStuckThreshold)))
        .get();
    for (final item in items) {
      await (db.update(db.outbox)..where((o) => o.seq.equals(item.seq)))
          .write(const OutboxCompanion(quarantined: Value(true)));
      await _logQuarantine(
        item,
        item.lastError ?? 'stuck_threshold',
        classifyOutboxError(item.lastError),
      );
    }
  }

  Future<void> _resetHealableRlsFailures() async {
    final items = await db.select(db.outbox).get();
    for (final item in items) {
      if (!isRlsOutboxError(item.lastError)) continue;
      await (db.update(db.outbox)..where((o) => o.seq.equals(item.seq)))
          .write(const OutboxCompanion(
        attempts: Value(0),
        lastError: Value(null),
        quarantined: Value(false),
      ));
    }
  }

  /// Includes quarantined rows — held duplicates must still clear.
  Future<void> _reconcileUpsertsAlreadyRemote() async {
    final items = await (db.select(db.outbox)
          ..where((o) => o.op.equals('upsert')))
        .get();
    if (items.isEmpty || shopId.isEmpty) return;

    final byTable = <String, List<OutboxData>>{};
    for (final item in items) {
      (byTable[item.entityTable] ??= []).add(item);
    }

    for (final entry in byTable.entries) {
      if (!_byName.containsKey(entry.key)) continue;
      List<Map<String, dynamic>> remoteRows;
      try {
        remoteRows = await remote.fetchChanges(entry.key, shopId, null);
      } catch (_) {
        continue;
      }
      final remoteIds = remoteRows.map((r) => r['id'] as String).toSet();
      for (final item in entry.value) {
        if (!remoteIds.contains(item.rowId)) continue;
        await _dropOutboxAsAlreadyRemote(item);
      }
    }
  }

  /// Pull all sync tables once when any outbox row has an FK error, then
  /// reset those rows so the next push can succeed with parents present.
  Future<void> _healForeignKeyFailures() async {
    final items = await db.select(db.outbox).get();
    final fkItems = items.where((i) => isForeignKeyOutboxError(i.lastError));
    if (fkItems.isEmpty || shopId.isEmpty) return;

    await _pullAllTablesOnce();
    for (final item in fkItems) {
      await (db.update(db.outbox)..where((o) => o.seq.equals(item.seq)))
          .write(const OutboxCompanion(
        attempts: Value(0),
        lastError: Value(null),
        quarantined: Value(false),
      ));
    }
  }

  Future<void> _pullAllTablesOnce() async {
    if (_didFkPullThisSync || shopId.isEmpty) return;
    _didFkPullThisSync = true;
    for (final def in tables) {
      try {
        final changes = await remote.fetchChanges(def.name, shopId, null);
        for (final row in changes) {
          await def.upsertLocal(db, row);
        }
      } catch (_) {
        // Best-effort parent heal.
      }
    }
  }

  Future<void> _dropOutboxAsAlreadyRemote(OutboxData item) async {
    await _removeOutbox(item.seq);
    await _clearDirty(item.entityTable, item.rowId);
  }

  Future<void> _clearDirty(String table, String id) async {
    if (!_byName.containsKey(table)) return;
    await db.customStatement(
      'UPDATE $table SET dirty = 0 WHERE id = ?',
      [id],
    );
  }

  Future<int> _push() async {
    var count = 0;
    final items = await (db.select(db.outbox)
          ..where((o) => o.quarantined.equals(false))
          ..orderBy([(o) => OrderingTerm(expression: o.seq)]))
        .get();

    for (final item in items) {
      final def = _byName[item.entityTable];
      if (def == null) {
        await _removeOutbox(item.seq);
        continue;
      }
      try {
        await _pushOne(item, def);
        await _removeOutbox(item.seq);
        count++;
      } catch (e) {
        final err = e.toString();
        if (item.op == 'delete' && isNotFoundOutboxError(err)) {
          await _removeOutbox(item.seq);
          count++;
          continue;
        }

        final errorClass = classifyOutboxError(err);
        if (item.op == 'upsert' &&
            (errorClass == OutboxErrorClass.rls42501 ||
                errorClass == OutboxErrorClass.uniqueViolation) &&
            shopId.isNotEmpty) {
          try {
            final remoteRows =
                await remote.fetchChanges(item.entityTable, shopId, null);
            final remoteIds =
                remoteRows.map((r) => r['id'] as String).toSet();
            if (remoteIds.contains(item.rowId)) {
              await _dropOutboxAsAlreadyRemote(item);
              continue;
            }
          } catch (_) {}
        }

        if (errorClass == OutboxErrorClass.foreignKey && !_didFkPullThisSync) {
          await _pullAllTablesOnce();
          try {
            await _pushOne(item, def);
            await _removeOutbox(item.seq);
            count++;
            continue;
          } catch (e2) {
            await _recordPushFailure(item, e2.toString(),
                classifyOutboxError(e2.toString()));
            continue;
          }
        }

        await _recordPushFailure(item, err, errorClass);
      }
    }
    return count;
  }

  Future<void> _pushOne(OutboxData item, SyncTableDef def) async {
    if (item.op == 'delete') {
      await remote.markDeleted(
        item.entityTable,
        item.rowId,
        DateTime.now(),
        shopId: shopId.isEmpty ? null : shopId,
      );
      return;
    }
    final row = await def.toRemote(db, item.rowId);
    if (row == null) {
      // Local row gone — nothing to upload.
      return;
    }
    if (shopId.isNotEmpty) {
      row['shop_id'] = shopId;
    }
    await remote.upsert(
      item.entityTable,
      row,
      onConflict: def.onConflict,
    );
  }

  Future<void> _recordPushFailure(
    OutboxData item,
    String err,
    OutboxErrorClass errorClass,
  ) async {
    final newAttempts = item.attempts + 1;
    final shouldQuarantine = newAttempts >= kOutboxStuckThreshold;
    await (db.update(db.outbox)..where((o) => o.seq.equals(item.seq)))
        .write(OutboxCompanion(
      attempts: Value(newAttempts),
      lastError: Value(err),
      quarantined: Value(shouldQuarantine),
    ));
    if (shouldQuarantine) {
      await _logQuarantine(item, err, errorClass);
    }
  }

  /// Held / stuck rows: service-role force-apply until cloud converges.
  Future<void> _forceApplyHeldRows() async {
    if (shopId.isEmpty) return;
    final items = await (db.select(db.outbox)
          ..where((o) =>
              o.quarantined.equals(true) |
              o.attempts.isBiggerOrEqualValue(kOutboxStuckThreshold)))
        .get();
    for (final item in items) {
      final def = _byName[item.entityTable];
      if (def == null) {
        await _removeOutbox(item.seq);
        continue;
      }

      Map<String, dynamic>? row;
      if (item.op != 'delete') {
        row = await def.toRemote(db, item.rowId);
        if (row == null) {
          await _removeOutbox(item.seq);
          continue;
        }
        row['shop_id'] = shopId;
      }

      final result = await remote.forceApply(
        table: item.entityTable,
        op: item.op,
        id: item.rowId,
        row: row,
        onConflict: def.onConflict,
      );

      switch (result.status) {
        case ForceApplyStatus.applied:
        case ForceApplyStatus.alreadyThere:
          await _dropOutboxAsAlreadyRemote(item);
        case ForceApplyStatus.rejectedInvalid:
          if (!isLedgerSyncTable(item.entityTable)) {
            // Non-ledger orphan — clear outbox; local row may stay for UI.
            await _removeOutbox(item.seq);
            await _clearDirty(item.entityTable, item.rowId);
          } else {
            await _logQuarantine(
              item,
              result.detail ?? 'rejected_invalid',
              OutboxErrorClass.unknown,
            );
            await (db.update(db.outbox)..where((o) => o.seq.equals(item.seq)))
                .write(OutboxCompanion(
              quarantined: const Value(true),
              lastError: Value(result.detail ?? 'rejected_invalid'),
            ));
          }
        case ForceApplyStatus.transient:
          await (db.update(db.outbox)..where((o) => o.seq.equals(item.seq)))
              .write(OutboxCompanion(
            quarantined: const Value(true),
            lastError: Value(result.detail ?? 'transient'),
          ));
      }
    }
  }

  Future<void> _logQuarantine(
    OutboxData item,
    String err,
    OutboxErrorClass errorClass,
  ) async {
    try {
      await Sentry.captureMessage(
        'Outbox row held for auto force-apply',
        level: SentryLevel.warning,
        withScope: (scope) {
          scope.setTag('outbox.table', item.entityTable);
          scope.setTag('outbox.op', item.op);
          scope.setTag('outbox.error_class', errorClass.name);
          scope.setContexts('outbox', {
            'shop_id': shopId,
            'row_id': item.rowId,
            'seq': item.seq,
            'attempts': item.attempts + 1,
            'last_error': err.length > 500 ? err.substring(0, 500) : err,
          });
        },
      );
    } catch (_) {}
  }

  Future<int> _pull() async {
    var count = 0;
    for (final def in tables) {
      final since = await settings.syncCursor(def.name);
      final seenAtCursor = await settings.syncCursorTieIds(def.name);
      final changes = await remote.fetchChanges(def.name, shopId, since);

      DateTime? maxSeen = since;
      for (final row in changes) {
        final rowId = row['id'] as String;
        final rowUpdated =
            DateTime.parse(row['updated_at'] as String).toLocal();
        if (since != null &&
            rowUpdated.isAtSameMomentAs(since) &&
            seenAtCursor.contains(rowId)) {
          continue;
        }
        await def.upsertLocal(db, row);
        count++;
        if (maxSeen == null || rowUpdated.isAfter(maxSeen)) {
          maxSeen = rowUpdated;
        }
      }

      if (maxSeen != null) {
        final idsAtMax = changes
            .where((r) => DateTime.parse(r['updated_at'] as String)
                .toLocal()
                .isAtSameMomentAs(maxSeen!))
            .map((r) => r['id'] as String)
            .toSet();
        if (since == null || maxSeen.isAfter(since)) {
          await settings.setSyncCursor(def.name, maxSeen);
          await settings.setSyncCursorTieIds(def.name, idsAtMax);
        } else if (idsAtMax.difference(seenAtCursor).isNotEmpty) {
          await settings.setSyncCursorTieIds(
              def.name, {...seenAtCursor, ...idsAtMax});
        }
      }
    }
    return count;
  }

  Future<void> _removeOutbox(int seq) {
    return (db.delete(db.outbox)..where((o) => o.seq.equals(seq))).go();
  }
}
