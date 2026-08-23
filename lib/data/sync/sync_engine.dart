import 'package:drift/drift.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/database.dart';
import '../repositories/settings_repository.dart';
import 'force_apply.dart';
import 'hlc.dart';
import 'outbox_constants.dart';
import 'outbox_error.dart';
import 'sync_heal.dart';
import 'sync_mappers.dart';

/// Transport abstraction so the engine can be unit-tested with a fake backend.
abstract class SyncRemote {
  Future<void> upsert(
    String table,
    Map<String, dynamic> row, {
    String? onConflict,
  });
  Future<void> markDeleted(
    String table,
    String id,
    DateTime updatedAt, {
    String? shopId,
    String? hlc,
  });

  /// Rows for [shopId] changed after [since] (all rows if null), ordered by
  /// the server-stamped `received_at` ascending — never client clocks.
  Future<List<Map<String, dynamic>>> fetchChanges(
    String table,
    String shopId,
    DateTime? since,
  );

  /// Lightweight id→stamp lookup for specific rows — used by outbox
  /// reconciliation and the push-side HLC guard instead of fetching whole
  /// tables (audit M2 + H2 residual). Missing ids simply have no entry.
  /// Returns null on transport failure.
  Future<Map<String, ({String updatedAt, String? hlc})>?> fetchRowStampsByIds(
    String table,
    String shopId,
    Set<String> ids,
  );

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
  Future<void> upsert(
    String table,
    Map<String, dynamic> row, {
    String? onConflict,
  }) async {
    await _client.from(table).upsert(row, onConflict: onConflict);
  }

  @override
  Future<void> markDeleted(
    String table,
    String id,
    DateTime updatedAt, {
    String? shopId,
    String? hlc,
  }) async {
    var q = _client
        .from(table)
        .update({
          'is_deleted': true,
          'updated_at': updatedAt.toUtc().toIso8601String(),
        })
        .eq('id', id);
    if (shopId != null && shopId.isNotEmpty) {
      q = q.eq('shop_id', shopId);
    }
    await q;
  }

  static const _pageSize = 500;

  /// Rows for [shopId] with server-stamped `received_at` strictly newer than
  /// [since] (all rows if null), ordered by `received_at` ascending — the
  /// change-feed cursor domain (see migration 0064: device clocks never
  /// decide what a pull sees, only the server's stamps do).
  ///
  /// Pages by KEYSET (`received_at`, `id`) rather than offset: a concurrent
  /// insert during paging shifts offsets (skipping or duplicating rows),
  /// while a keyset cursor is immune to rows landing before it. The `or`
  /// clause keeps rows sharing the boundary stamp's exact microsecond —
  /// PostgREST ANDs it with the shop filter.
  @override
  Future<List<Map<String, dynamic>>> fetchChanges(
    String table,
    String shopId,
    DateTime? since,
  ) async {
    final all = <Map<String, dynamic>>[];
    String? cursorStamp = since
        ?.toUtc()
        .toIso8601String(); // inclusive on first page
    String? cursorId; // set after each page → strict keyset continuation
    while (true) {
      var q = _client.from(table).select().eq('shop_id', shopId);
      if (cursorStamp != null) {
        q = cursorId == null
            ? q.gte('received_at', cursorStamp)
            : q.or(
                'received_at.gt.$cursorStamp,'
                'and(received_at.eq.$cursorStamp,id.gt.$cursorId)',
              );
      }
      final page = await q
          .order('received_at')
          .order('id')
          .range(0, _pageSize - 1);
      final rows = (page as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      all.addAll(rows);
      if (rows.length < _pageSize) break;
      cursorStamp = rows.last['received_at'] as String?;
      cursorId = rows.last['id'] as String;
    }
    return all;
  }

  @override
  Future<Map<String, ({String updatedAt, String? hlc})>?> fetchRowStampsByIds(
    String table,
    String shopId,
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return {};
    try {
      // Chunk the IN filter: this becomes a GET query string, and a device
      // coming back from a long offline stretch can hold hundreds of pending
      // ids (~36 bytes each as UUIDs) — past ~8–16 KB of URL, gateways start
      // rejecting with 414 and the probe would read as "fetch failed" and
      // keep every row queued forever. 100 ids ≈ 3.6 KB per request.
      const chunkSize = 100;
      final idList = ids.toList();
      final merged = <String, ({String updatedAt, String? hlc})>{};
      for (var i = 0; i < idList.length; i += chunkSize) {
        final chunk = idList.sublist(
            i, i + chunkSize > idList.length ? idList.length : i + chunkSize);
        final rows = await _client
            .from(table)
            .select('id,updated_at,hlc')
            .eq('shop_id', shopId)
            .inFilter('id', chunk);
        for (final r in rows as List) {
          merged[r['id'] as String] = (
            updatedAt: r['updated_at'] as String,
            hlc: r['hlc'] as String?,
          );
        }
      }
      return merged;
    } catch (_) {
      return null;
    }
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
        return const ForceApplyResult(
          ForceApplyStatus.transient,
          detail: 'bad_response',
        );
      }
      final map = Map<String, dynamic>.from(data);
      final status = map['status'] as String? ?? 'transient';
      final detail = map['detail'] as String?;
      return ForceApplyResult(switch (status) {
        'applied' => ForceApplyStatus.applied,
        'already_there' => ForceApplyStatus.alreadyThere,
        'rejected_invalid' => ForceApplyStatus.rejectedInvalid,
        _ => ForceApplyStatus.transient,
      }, detail: detail);
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
  bool _didSessionRefreshThisSync = false;
  String? _deviceIdCache;

  Future<String> _deviceId() async {
    final cached = _deviceIdCache;
    if (cached != null) return cached;
    return _deviceIdCache = await settings.deviceId();
  }

  Future<SyncResult> syncNow() async {
    _didFkPullThisSync = false;
    _didSessionRefreshThisSync = false;
    await _resetHealableRlsFailures();
    await _reconcileUpsertsAlreadyRemote();
    await _healForeignKeyFailures();
    final pushed = await _push();
    await _forceApplyHeldRows();
    final pulled = await _pull();
    return SyncResult(pushed, pulled);
  }

  Future<void> _resetHealableRlsFailures() async {
    // SQL-side LIKE pre-filter (audit M2) — never loads the whole outbox
    // just to find the rare RLS-failed rows. Patterns mirror
    // classifyOutboxError's matchers.
    final items =
        await (db.select(db.outbox)..where(
              (o) =>
                  o.lastError.like('%row-level security%') |
                  o.lastError.like('%42501%'),
            ))
            .get();
    for (final item in items) {
      if (!isRlsOutboxError(item.lastError)) continue;
      await (db.update(db.outbox)..where((o) => o.seq.equals(item.seq))).write(
        const OutboxCompanion(
          attempts: Value(0),
          lastError: Value(null),
          quarantined: Value(false),
        ),
      );
    }
  }

  /// Remote `updated_at` (ISO string) per row id for [table], or null when
  /// the fetch failed (offline blip) — callers must then keep every pending
  /// row and let the normal push path decide.
  Future<Map<String, ({String updatedAt, String? hlc})>?> _remoteStampsById(
    String table,
    Set<String> ids,
  ) async {
    if (shopId.isEmpty) return null;
    return remote.fetchRowStampsByIds(table, shopId, ids);
  }

  /// True only when the remote copy of [item]'s row is strictly newer than
  /// the local row (or the local row is gone) — i.e. dropping [item]'s
  /// pending upsert cannot lose a local change. Mere id presence on the
  /// remote is NOT enough: every already-synced row's id exists remotely
  /// from its original creation push, so dropping on id alone would silently
  /// discard every offline edit to a mutable row (order status moves,
  /// product price changes, cash-session closes, …).
  ///
  /// Equal timestamps also count as "not newer": Drift stores DateTimes with
  /// second precision, so an edit made within the same wall-clock second as
  /// the previously-synced write carries an identical `updated_at` with
  /// different content. Keeping the row only ever costs one redundant
  /// idempotent upsert; dropping it could lose the edit.
  Future<bool> _remoteNewerThanLocal(OutboxData item) async {
    final def = _byName[item.entityTable];
    if (def == null || shopId.isEmpty) return false;
    final localRow = await def.toRemote(db, item.rowId);
    if (localRow == null) return true; // local row gone — nothing to upload
    final timestamps = await _remoteStampsById(item.entityTable, {item.rowId});
    if (timestamps == null) return false; // fetch failed — keep & retry
    final remoteStamp = timestamps[item.rowId];
    if (remoteStamp == null) {
      return false; // not remote yet — genuine pending write
    }
    return DateTime.parse(remoteStamp.updatedAt).toLocal().isAfter(
      DateTime.parse(localRow['updated_at'] as String).toLocal(),
    );
  }

  /// Includes quarantined rows — held duplicates must still clear.
  ///
  /// A pending upsert is dropped as "already remote" only when the remote
  /// copy is strictly newer than the local row (see [_remoteNewerThanLocal]);
  /// equal/older remote copies stay queued so the push can converge them.
  Future<void> _reconcileUpsertsAlreadyRemote() async {
    final items = await (db.select(
      db.outbox,
    )..where((o) => o.op.equals('upsert'))).get();
    if (items.isEmpty || shopId.isEmpty) return;

    final byTable = <String, List<OutboxData>>{};
    for (final item in items) {
      (byTable[item.entityTable] ??= []).add(item);
    }

    for (final entry in byTable.entries) {
      final def = _byName[entry.key];
      if (def == null) continue;
      // Only probe the pending ids themselves (audit M2) — a full-table
      // fetch per pending table per sync was O(shop) network for what is
      // almost always a handful of rows.
      final remoteTimestamps = await _remoteStampsById(
        entry.key,
        entry.value.map((i) => i.rowId).toSet(),
      );
      if (remoteTimestamps == null) continue; // offline blip — push will decide
      // Chunk the toRemote reads so one vanished row can't stall the batch.
      for (final item in entry.value) {
        final localRow = await def.toRemote(db, item.rowId);
        if (localRow == null) {
          // Local row gone since enqueue — nothing to upload (the same rule
          // _pushOne applies).
          await _removeOutbox(item.seq);
          continue;
        }
        final remoteStamp = remoteTimestamps[item.rowId];
        if (remoteStamp == null) continue; // not remote yet — must push
        final remoteUpdated = DateTime.parse(remoteStamp.updatedAt).toLocal();
        final localUpdated = DateTime.parse(
          localRow['updated_at'] as String,
        ).toLocal();
        if (remoteUpdated.isAfter(localUpdated)) {
          // Remote is strictly newer — the pull below applies it; keeping
          // this outbox row would just re-push stale data.
          await _dropOutboxAsAlreadyRemote(item);
        }
      }
    }
  }

  /// Pull all sync tables once when any outbox row has an FK error, then
  /// reset those rows so the next push can succeed with parents present.
  Future<void> _healForeignKeyFailures() async {
    // Same SQL-side pre-filter as _resetHealableRlsFailures (audit M2).
    final items =
        await (db.select(db.outbox)..where(
              (o) =>
                  o.lastError.like('%foreign key%') |
                  o.lastError.like('%23503%'),
            ))
            .get();
    final fkItems = items.where((i) => isForeignKeyOutboxError(i.lastError));
    if (fkItems.isEmpty || shopId.isEmpty) return;

    await _pullAllTablesOnce();
    for (final item in fkItems) {
      await (db.update(db.outbox)..where((o) => o.seq.equals(item.seq))).write(
        const OutboxCompanion(
          attempts: Value(0),
          lastError: Value(null),
          quarantined: Value(false),
        ),
      );
    }
  }

  Future<void> _pullAllTablesOnce() async {
    if (_didFkPullThisSync || shopId.isEmpty) return;
    _didFkPullThisSync = true;
    for (final def in tables) {
      try {
        final changes = await remote.fetchChanges(def.name, shopId, null);
        // One transaction per table (see _pull for why) — the FK heal used
        // to invalidate every watching stream once PER ROW across EVERY
        // table, right when pushes are already failing.
        await db.transaction(() async {
          for (final row in changes) {
            try {
              await def.upsertLocal(db, row);
            } catch (_) {
              // Best-effort parent heal: one bad row must not roll back its
              // siblings — catching inside the transaction keeps it to a
              // statement-level rollback, so the rest of the batch applies.
            }
          }
        });
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
    await db.customStatement('UPDATE $table SET dirty = 0 WHERE id = ?', [id]);
  }

  Future<int> _push() async {
    var count = 0;
    final items =
        await (db.select(db.outbox)
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
        await _clearDirty(item.entityTable, item.rowId);
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
                errorClass == OutboxErrorClass.uniqueViolation)) {
          // Only drop when the remote copy is strictly newer than the local
          // row — id presence alone would discard a legitimate local edit
          // that merely failed to push for RLS/unique reasons (same rule as
          // _reconcileUpsertsAlreadyRemote). Equal/older remote copies stay
          // queued for retry / session-refresh heal / force-apply.
          try {
            if (await _remoteNewerThanLocal(item)) {
              await _dropOutboxAsAlreadyRemote(item);
              continue;
            }
          } catch (_) {}
        }

        if (errorClass == OutboxErrorClass.foreignKey && !_didFkPullThisSync) {
          await _pullAllTablesOnce();
          try {
            await _pushOne(item, def);
            await _clearDirty(item.entityTable, item.rowId);
            await _removeOutbox(item.seq);
            count++;
            continue;
          } catch (e2) {
            await _recordPushFailure(
              item,
              e2.toString(),
              classifyOutboxError(e2.toString()),
            );
            continue;
          }
        }

        // A 42501 that isn't "already exists remotely" (handled above) means
        // this device's JWT shop_id claim may be stale rather than the write
        // itself being wrong — the same class of bug that broke Storefront
        // publish (see StorefrontRepository._withRlsRetry). Retry a session
        // refresh once per sync cycle before recording a failure, so real
        // synced data self-heals instead of silently piling up as stuck /
        // quarantined outbox rows forever.
        if (errorClass == OutboxErrorClass.rls42501 &&
            !_didSessionRefreshThisSync) {
          _didSessionRefreshThisSync = true;
          try {
            await Supabase.instance.client.auth.refreshSession();
            await _pushOne(item, def);
            await _clearDirty(item.entityTable, item.rowId);
            await _removeOutbox(item.seq);
            count++;
            continue;
          } catch (e2) {
            await _recordPushFailure(
              item,
              e2.toString(),
              classifyOutboxError(e2.toString()),
            );
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
      // Stamp the tombstone with the row's own deletion timestamp (audit M5)
      // rather than "now" — the repository already wrote it, and re-reading
      // keeps retries idempotent instead of advancing the tombstone each try.
      var stamp = DateTime.now();
      final existing = await def.toRemote(db, item.rowId);
      final existingTs = existing?['updated_at'];
      if (existingTs is String) stamp = DateTime.parse(existingTs);
      await remote.markDeleted(
        item.entityTable,
        item.rowId,
        stamp,
        shopId: shopId.isEmpty ? null : shopId,
        hlc: await mintHlc(db, await _deviceId()),
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
    // Mint a fresh HLC for this version (audit H2 residual): written back to
    // the local row AND carried in the payload, so every replica arbitrates
    // this write with the same totally-ordered stamp. Outbox order preserves
    // a device's own edit sequence across its queued rows.
    final hlc = await mintHlc(db, await _deviceId());

    // Push-side guard: if the remote already holds a STRICTLY higher-HLC
    // version of this row (another device pushed after we read it), skip —
    // overwriting would regress the server below the version other replicas
    // already converged on. Dropping our stale outbox entry lets the pull
    // bring us the winner. The server therefore advances monotonically per
    // row and every device converges on the same value.
    if (shopId.isNotEmpty) {
      final stamps = await remote.fetchRowStampsByIds(
        item.entityTable,
        shopId,
        {item.rowId},
      );
      final remoteStamp = stamps?[item.rowId];
      if (remoteStamp != null && compareHlc(remoteStamp.hlc, hlc) > 0) {
        return;
      }
    }

    await db.customStatement('UPDATE ${def.name} SET hlc = ? WHERE id = ?', [
      hlc,
      item.rowId,
    ]);
    row['hlc'] = hlc;
    await remote.upsert(item.entityTable, row, onConflict: def.onConflict);
  }

  Future<void> _recordPushFailure(
    OutboxData item,
    String err,
    OutboxErrorClass errorClass,
  ) async {
    final newAttempts = item.attempts + 1;
    final shouldQuarantine = newAttempts >= kOutboxStuckThreshold;
    await (db.update(db.outbox)..where((o) => o.seq.equals(item.seq))).write(
      OutboxCompanion(
        attempts: Value(newAttempts),
        lastError: Value(err),
        quarantined: Value(shouldQuarantine),
      ),
    );
    if (shouldQuarantine) {
      await _logQuarantine(item, err, errorClass);
    }
  }

  /// Held / stuck rows: service-role force-apply until cloud converges.
  Future<void> _forceApplyHeldRows() async {
    if (shopId.isEmpty) return;
    final items =
        await (db.select(db.outbox)..where(
              (o) =>
                  o.quarantined.equals(true) |
                  o.attempts.isBiggerOrEqualValue(kOutboxStuckThreshold),
            ))
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
            await (db.update(
              db.outbox,
            )..where((o) => o.seq.equals(item.seq))).write(
              OutboxCompanion(
                quarantined: const Value(true),
                lastError: Value(result.detail ?? 'rejected_invalid'),
              ),
            );
          }
        case ForceApplyStatus.transient:
          await (db.update(
            db.outbox,
          )..where((o) => o.seq.equals(item.seq))).write(
            OutboxCompanion(
              quarantined: const Value(true),
              lastError: Value(result.detail ?? 'transient'),
            ),
          );
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

  /// How far back each pull re-fetches past its cursor. Closes the
  /// commit-order race (a transaction that STARTED before another can COMMIT
  /// after it, landing a `received_at` stamp below the watermark the other
  /// row already pushed the cursor past). Re-applying an already-seen row is
  /// idempotent — every mapper's LWW guard no-ops on equal-or-older
  /// `updated_at` and `_stockMovements` only applies deltas for rows it has
  /// never seen — so the overlap costs a little bandwidth, never correctness.
  static const _pullOverlap = Duration(minutes: 2);

  Future<int> _pull() async {
    var count = 0;
    for (final def in tables) {
      final since = await settings.syncReceivedCursor(def.name);
      // Rewind the watermark by the overlap window; the mappers dedupe.
      final effectiveSince = since?.subtract(_pullOverlap);
      final changes = await remote.fetchChanges(
        def.name,
        shopId,
        effectiveSince,
      );

      DateTime? maxSeen = since;
      String? strongest;
      // ONE transaction per table: Drift accumulates stream invalidations
      // inside a transaction and dispatches them ONCE at commit, so a 500-row
      // page re-fires each listening provider (Sell grid, Inventory,
      // Analytics, cart stock caps…) a single time instead of once per row —
      // the pull used to rebuild the whole Sell screen mid-checkout for
      // every synced row (audit C1).
      if (changes.isNotEmpty) {
        await db.transaction(() async {
          for (final row in changes) {
            final rowReceived = _receivedAtOf(row);
            bool applied;
            try {
              applied = await def.upsertLocal(db, row);
            } catch (_) {
              // A row that can't apply locally must not wedge the whole pull
              // — the cursor still advances past it (same contract as
              // _pullAllTablesOnce). Concrete case: a pulled refund
              // duplicating a refund this device already recorded offline,
              // now blocked by the sales_refund_once unique index (schema
              // v32 / migration 0067) — this device keeps its own reversal,
              // the cloud keeps the first-pushed one, both books net exactly
              // one reversal. Caught INSIDE the transaction so only this
              // statement rolls back; its siblings still commit.
              applied = false;
            }
            // Count only NEW feed events (stamp past the cursor). Rows inside
            // the overlap window re-fetched every cycle — including identical
            // tie re-writes from the dirty-aware merge — are deliberately not
            // recounted, or `pulled` would never settle back to zero.
            if (applied && (since == null || rowReceived.isAfter(since))) {
              count++;
            }
            final currentMax = maxSeen;
            if (currentMax == null || rowReceived.isAfter(currentMax)) {
              maxSeen = rowReceived;
            }
            final h = row['hlc'] as String?;
            if (h != null &&
                (strongest == null || compareHlc(h, strongest) > 0)) {
              strongest = h;
            }
          }
        });
      }

      // Copy out of the closure-mutated variable so the compiler can
      // promote it past the null check again.
      final newCursor = maxSeen;
      if (newCursor != null && (since == null || newCursor.isAfter(since))) {
        await settings.setSyncReceivedCursor(def.name, newCursor);
      }

      // Advance the HLC past the strongest stamp seen this cycle (Lamport
      // receive rule) so future local edits/pushes sort after everything
      // observed (audit H2 residual). Runs after the transaction commits so
      // the clock write can never be rolled back with a failed batch.
      if (strongest != null) {
        await receiveHlc(db, strongest);
      }
    }
    return count;
  }

  DateTime _receivedAtOf(Map<String, dynamic> row) =>
      DateTime.parse(row['received_at'] as String).toUtc();

  Future<void> _removeOutbox(int seq) {
    return (db.delete(db.outbox)..where((o) => o.seq.equals(seq))).go();
  }
}
