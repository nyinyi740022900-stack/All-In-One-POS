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
/// times — see `SyncEngine._push`'s per-row error isolation for why a
/// single bad row doesn't otherwise surface anywhere.
final stuckOutboxProvider = StreamProvider<List<OutboxData>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.outbox)
        ..where((o) => o.attempts.isBiggerOrEqualValue(kOutboxStuckThreshold))
        ..orderBy([(o) => OrderingTerm(expression: o.seq)]))
      .watch();
});

enum SyncPhase { disabled, idle, syncing, offline, error }

class SyncState {
  final SyncPhase phase;
  final DateTime? lastSyncedAt;
  final String? error;

  const SyncState({required this.phase, this.lastSyncedAt, this.error});

  SyncState copyWith({
    SyncPhase? phase,
    DateTime? lastSyncedAt,
    String? error,
  }) => SyncState(
    phase: phase ?? this.phase,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    error: error,
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
  bool _running = false;

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

  /// Permanently drops one stuck outbox row (see [stuckOutboxProvider]) —
  /// the only way to unwedge a genuine poison pill, since it can never
  /// succeed on its own. Discards that one local change; every other
  /// already-synced write for the same entity is unaffected. Callers must
  /// get explicit owner confirmation first — this is real, unrecoverable
  /// data loss for whatever that one write was.
  Future<void> discardOutboxRow(int seq) async {
    final db = _ref.read(databaseProvider);
    await (db.delete(db.outbox)..where((o) => o.seq.equals(seq))).go();
  }

  Future<void> sync() async {
    final engine = _ref.read(syncEngineProvider);
    if (engine == null || _running) return;
    _running = true;
    state = state.copyWith(phase: SyncPhase.syncing, error: null);
    try {
      if (Supabase.instance.client.auth.currentSession == null) {
        await _ensureSession();
      }
      await engine.syncNow();
      state = state.copyWith(
        phase: SyncPhase.idle,
        lastSyncedAt: DateTime.now(),
        error: null,
      );
    } catch (e) {
      state = state.copyWith(phase: SyncPhase.error, error: e.toString());
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _periodic?.cancel();
    _teardownRealtime();
    super.dispose();
  }
}
