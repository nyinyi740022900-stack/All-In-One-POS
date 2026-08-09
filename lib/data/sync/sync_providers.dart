import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/providers.dart';
import '../../features/license/license_model.dart';
import '../../features/license/license_providers.dart';
import '../../features/license/license_status.dart';
import '../../features/printing/printing_providers.dart';
import '../local/database.dart';
import 'outbox_constants.dart';
import 'sync_engine.dart';

/// Outbox rows that have failed to push at least [kOutboxStuckThreshold]
/// times and are not yet quarantined — rare; sync usually quarantines them
/// at the same threshold so branch switch is never blocked.
final stuckOutboxProvider = StreamProvider<List<OutboxData>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.outbox)
        ..where((o) =>
            o.quarantined.equals(false) &
            o.attempts.isBiggerOrEqualValue(kOutboxStuckThreshold))
        ..orderBy([(o) => OrderingTerm(expression: o.seq)]))
      .watch();
});

/// Active (non-quarantined) pending uploads — Sync Issues / drain gates.
final pendingOutboxRowsProvider = StreamProvider<List<OutboxData>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.outbox)
        ..where((o) => o.quarantined.equals(false))
        ..orderBy([(o) => OrderingTerm(expression: o.seq)]))
      .watch();
});

/// Poison rows held for Support (do not block branch switch or pending counts).
final quarantinedOutboxProvider = StreamProvider<List<OutboxData>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.outbox)
        ..where((o) => o.quarantined.equals(true))
        ..orderBy([(o) => OrderingTerm(expression: o.seq)]))
      .watch();
});

enum SyncPhase { disabled, idle, syncing, offline, error }

class SyncState {
  final SyncPhase phase;
  final DateTime? lastSyncedAt;
  final String? error;

  /// Snapshot after the last sync attempt — used so Settings never shows
  /// "Up to date" while the outbox still has pending/stuck uploads.
  final int pendingOutboxCount;
  final int stuckOutboxCount;

  const SyncState({
    required this.phase,
    this.lastSyncedAt,
    this.error,
    this.pendingOutboxCount = 0,
    this.stuckOutboxCount = 0,
  });

  bool get hasPendingUploads => pendingOutboxCount > 0;
  bool get hasStuckUploads => stuckOutboxCount > 0;

  SyncState copyWith({
    SyncPhase? phase,
    DateTime? lastSyncedAt,
    String? error,
    int? pendingOutboxCount,
    int? stuckOutboxCount,
  }) => SyncState(
    phase: phase ?? this.phase,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    error: error,
    pendingOutboxCount: pendingOutboxCount ?? this.pendingOutboxCount,
    stuckOutboxCount: stuckOutboxCount ?? this.stuckOutboxCount,
  );
}

/// The sync engine, available only when backend credentials are configured
/// AND the current license actually has a real server-side shop behind it.
/// The Free plan's `shopId` (`free-<deviceId>`) is synthesized purely
/// locally — no `licenses` row, no JWT `shop_id` claim — so every push would
/// be rejected by RLS forever, permanently filling the outbox and retrying
/// on every periodic sync for no reason. Free-plan data is local-only by
/// design; skip the sync engine entirely rather than let it grind on a shop
/// that doesn't exist server-side.
final syncEngineProvider = Provider<SyncEngine?>((ref) {
  if (!Env.hasBackend) return null;
  final license = ref.watch(licenseControllerProvider).license;
  if (license != null && license.plan == LicensePlan.free) return null;
  return SyncEngine(
    db: ref.watch(databaseProvider),
    remote: SupabaseSyncRemote(Supabase.instance.client),
    settings: ref.watch(settingsRepositoryProvider),
    shopId: ref.watch(shopIdProvider),
  );
});

final syncControllerProvider = StateNotifierProvider<SyncController, SyncState>(
  (ref) {
    return SyncController(ref);
  },
);

class SyncController extends StateNotifier<SyncState> {
  SyncController(this._ref)
    : super(
        SyncState(phase: Env.hasBackend ? SyncPhase.idle : SyncPhase.disabled),
      ) {
    if (Env.hasBackend) _init();
  }

  final Ref _ref;
  StreamSubscription? _connSub;
  Timer? _periodic;
  /// In-flight sync future — callers [sync] join this instead of early-return.
  Future<void>? _inFlight;
  /// When true, background triggers (connectivity / periodic / realtime) no-op;
  /// branch switch uses [sync] with [force] to drain while paused.
  bool _paused = false;

  // Realtime "Online" tier (an admin-granted premium flag — see
  // CachedLicense.realtimeEnabled): when on, a Postgres-changes subscription
  // triggers an immediate sync() instead of waiting for the 5-minute poll
  // below, which stays running regardless as the offline-safe fallback.
  RealtimeChannel? _realtimeChannel;
  Timer? _realtimeDebounce;
  String? _realtimeShopId;

  Future<void> _init() async {
    // Establish an auth session. Anonymous for now; Phase 5 replaces this with
    // a license-bound session carrying the shop_id claim.
    await _ensureSession();

    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) sync();
    });
    // Safety-net periodic sync every 5 minutes — always runs, realtime or not.
    _periodic = Timer.periodic(const Duration(minutes: 5), (_) => sync());

    _ref.listen<LicenseState>(
      licenseControllerProvider,
      (_, next) => _updateRealtimeSubscription(next.license),
      fireImmediately: true,
    );

    unawaited(sync());
  }

  void _updateRealtimeSubscription(CachedLicense? license) {
    final shopId = license?.realtimeEnabled == true ? license?.shopId : null;
    if (shopId == _realtimeShopId) return; // no change
    _teardownRealtime();
    if (shopId == null) return;

    _realtimeShopId = shopId;
    final client = Supabase.instance.client;
    var channel = client.channel('shop-$shopId-realtime');
    for (final table in const ['sales', 'stock_levels', 'orders']) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'shop_id',
          value: shopId,
        ),
        callback: (_) => _onRealtimeChange(),
      );
    }
    _realtimeChannel = channel..subscribe();
  }

  /// Debounced so a burst of related writes (e.g. finalizeSale touching
  /// sales + sale_items + payments + stock_levels together) triggers one
  /// sync(), not one per row.
  void _onRealtimeChange() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(seconds: 2), sync);
  }

  void _teardownRealtime() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = null;
    final channel = _realtimeChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
      _realtimeChannel = null;
    }
    _realtimeShopId = null;
  }

  Future<void> _ensureSession() async {
    try {
      final auth = Supabase.instance.client.auth;
      if (auth.currentSession == null) {
        await auth.signInAnonymously();
      }
    } catch (_) {
      // Auth may be unavailable offline; sync() will retry.
    }
  }

  /// Stops connectivity / periodic / realtime from starting new syncs.
  /// In-flight work is still joinable via [sync].
  void pauseBackgroundSync() => _paused = true;

  void resumeBackgroundSync() => _paused = false;

  /// Drains the outbox (push) then pulls. Concurrent callers **join** the
  /// same in-flight run instead of silently returning. Pass [force]: true
  /// while background sync is paused (branch switch critical section).
  Future<void> sync({bool force = false}) async {
    if (_paused && !force) return;
    final existing = _inFlight;
    if (existing != null) return existing;

    final engine = _ref.read(syncEngineProvider);
    if (engine == null) {
      await _refreshOutboxTruth();
      return;
    }

    late final Future<void> run;
    run = _runSync(engine);
    _inFlight = run;
    try {
      await run;
    } finally {
      if (identical(_inFlight, run)) _inFlight = null;
    }
  }

  /// Repeatedly syncs until the outbox is empty, no progress is made, or
  /// [maxRounds] is hit. Used by branch switch so a single transient fail
  /// does not immediately abort with "sync first".
  Future<({int pending, int stuck})> drainForSwitch({int maxRounds = 3}) async {
    var previousPending = -1;
    for (var round = 0; round < maxRounds; round++) {
      await sync(force: true);
      final truth = await _outboxCounts();
      if (truth.pending == 0) return truth;
      if (truth.pending == previousPending) return truth;
      previousPending = truth.pending;
    }
    return _outboxCounts();
  }

  Future<void> _runSync(SyncEngine engine) async {
    state = state.copyWith(phase: SyncPhase.syncing, error: null);
    try {
      if (Supabase.instance.client.auth.currentSession == null) {
        await _ensureSession();
      }
      await engine.syncNow();
      final truth = await _outboxCounts();
      state = state.copyWith(
        phase: SyncPhase.idle,
        lastSyncedAt: DateTime.now(),
        error: null,
        pendingOutboxCount: truth.pending,
        stuckOutboxCount: truth.stuck,
      );
    } catch (e) {
      final truth = await _outboxCounts();
      state = state.copyWith(
        phase: SyncPhase.error,
        error: e.toString(),
        pendingOutboxCount: truth.pending,
        stuckOutboxCount: truth.stuck,
      );
    }
  }

  Future<({int pending, int stuck})> _outboxCounts() async {
    final db = _ref.read(databaseProvider);
    final rows = await (db.select(db.outbox)
          ..where((o) => o.quarantined.equals(false)))
        .get();
    final stuck =
        rows.where((r) => r.attempts >= kOutboxStuckThreshold).length;
    return (pending: rows.length, stuck: stuck);
  }

  Future<void> _refreshOutboxTruth() async {
    final truth = await _outboxCounts();
    state = state.copyWith(
      pendingOutboxCount: truth.pending,
      stuckOutboxCount: truth.stuck,
    );
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _periodic?.cancel();
    _teardownRealtime();
    super.dispose();
  }
}
