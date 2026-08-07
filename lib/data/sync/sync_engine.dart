import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/database.dart';
import '../repositories/settings_repository.dart';
import 'sync_mappers.dart';

/// Transport abstraction so the engine can be unit-tested with a fake backend.
abstract class SyncRemote {
  Future<void> upsert(String table, Map<String, dynamic> row,
      {String? onConflict});
  Future<void> markDeleted(String table, String id, DateTime updatedAt);

  /// Rows for [shopId] changed strictly after [since] (all rows if null),
  /// ordered by `updated_at` ascending.
  Future<List<Map<String, dynamic>>> fetchChanges(
      String table, String shopId, DateTime? since);
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
  Future<void> markDeleted(String table, String id, DateTime updatedAt) async {
    await _client.from(table).update({
      'is_deleted': true,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    }).eq('id', id);
  }

  // Page size kept well under PostgREST's default `max_rows` (commonly
  // 1000) so a single page is never itself silently truncated by the server.
  static const _pageSize = 500;

  @override
  Future<List<Map<String, dynamic>>> fetchChanges(
      String table, String shopId, DateTime? since) async {
    // Two changes to the same or different rows within the same second get
    // an identical `updated_at` — Drift's DateTimeColumn stores it as whole
    // Unix seconds, so app-level microsecond timestamps are truncated on
    // write. A strict `gt` cursor filter would then permanently drop
    // whichever tied row lands exactly on the next pull's cursor boundary
    // (its `updated_at` can never be "after" a cursor equal to itself).
    // Using an inclusive `gte` instead means a boundary row may be re-fetched
    // on the following pull, but every `upsertLocal` mapper already no-ops a
    // row it has already applied (LWW / already-seen-id checks), so the
    // redundant re-fetch is a harmless, bounded cost — not a correctness
    // problem — and cursor advancement still only happens once a strictly
    // newer row actually arrives.
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
}

class SyncResult {
  final int pushed;
  final int pulled;
  const SyncResult(this.pushed, this.pulled);
}

/// Drains the outbox to the backend, then pulls remote changes and merges them
/// with last-write-wins. Both directions are resumable: outbox rows are removed
/// only after a successful push, and pull cursors advance per table, so an
/// interrupted sync simply continues next time.
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

  Future<SyncResult> syncNow() async {
    // Known heal: payment_accounts once used a global PK on `id` (`kbzpay`
    // etc.), so branch B's upsert hit RLS 42501 forever. Migration 0054 made
    // the PK `(shop_id, id)` — reset those stuck counters so Sync Now retries
    // and succeeds without asking anyone to Discard.
    await _resetPaymentAccountsRlsFailures();
    final pushed = await _push();
    final pulled = await _pull();
    return SyncResult(pushed, pulled);
  }

  Future<void> _resetPaymentAccountsRlsFailures() async {
    final items = await (db.select(db.outbox)
          ..where((o) => o.entityTable.equals('payment_accounts')))
        .get();
    for (final item in items) {
      if (!_isPaymentAccountsRlsError(item.lastError)) continue;
      await (db.update(db.outbox)..where((o) => o.seq.equals(item.seq)))
          .write(const OutboxCompanion(
        attempts: Value(0),
        lastError: Value(null),
      ));
    }
  }

  static bool _isPaymentAccountsRlsError(String? lastError) {
    if (lastError == null || lastError.isEmpty) return false;
    final lower = lastError.toLowerCase();
    return lower.contains('row-level security') || lower.contains('42501');
  }

  Future<int> _push() async {
    var count = 0;
    final items = await (db.select(db.outbox)
          ..orderBy([(o) => OrderingTerm(expression: o.seq)]))
        .get();

    for (final item in items) {
      final def = _byName[item.entityTable];
      if (def == null) {
        await _removeOutbox(item.seq);
        continue;
      }
      try {
        if (item.op == 'delete') {
          await remote.markDeleted(
              item.entityTable, item.rowId, DateTime.now());
        } else {
          final row = await def.toRemote(db, item.rowId);
          if (row != null) {
            await remote.upsert(
              item.entityTable,
              row,
              onConflict: def.onConflict,
            );
          }
        }
        await _removeOutbox(item.seq);
        count++;
      } catch (e) {
        // One row failing (schema drift, a transient error, a bad payload)
        // must NOT wedge the whole outbox — record the attempt and move on so
        // later rows (e.g. a license payment) still reach the server. The
        // failed row stays queued and is retried on the next sync. The error
        // itself is also recorded (not just swallowed) so a row that can
        // never succeed — a "poison pill" — surfaces to the owner via the
        // Sync issues screen instead of retrying forever invisibly behind an
        // otherwise-accurate "Up to date" status.
        await (db.update(db.outbox)..where((o) => o.seq.equals(item.seq)))
            .write(OutboxCompanion(
          attempts: Value(item.attempts + 1),
          lastError: Value(e.toString()),
        ));
      }
    }
    return count;
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
        final rowUpdated = DateTime.parse(row['updated_at'] as String).toLocal();
        // Already applied this exact row the last time the cursor sat on
        // this same timestamp — the inclusive pull filter re-fetches it,
        // but it must not be re-applied or re-counted.
        if (since != null &&
            rowUpdated.isAtSameMomentAs(since) &&
            seenAtCursor.contains(rowId)) {
          continue;
        }
        await def.upsertLocal(db, row);
        count++;
        if (maxSeen == null || rowUpdated.isAfter(maxSeen)) maxSeen = rowUpdated;
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
