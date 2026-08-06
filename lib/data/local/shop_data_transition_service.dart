import '../sync/outbox_constants.dart';
import 'database.dart';

class ShopTransitionPrecheck {
  final int pendingOutboxCount;
  final int stuckOutboxCount;

  const ShopTransitionPrecheck({
    required this.pendingOutboxCount,
    required this.stuckOutboxCount,
  });

  bool get hasPendingWrites => pendingOutboxCount > 0;
  bool get hasStuckWrites => stuckOutboxCount > 0;
}

/// Centralized guard for destructive local transitions (branch switch,
/// account re-scope). Keeps all call sites on the same safety rules:
/// - never clear local shop data while pending writes exist
/// - explicitly block when any outbox row looks permanently stuck
class ShopDataTransitionService {
  ShopDataTransitionService(this._db);
  final AppDatabase _db;

  Future<ShopTransitionPrecheck> precheck() async {
    final rows = await _db.select(_db.outbox).get();
    final stuckCount = rows
        .where((r) => r.attempts >= kOutboxStuckThreshold)
        .length;
    return ShopTransitionPrecheck(
      pendingOutboxCount: rows.length,
      stuckOutboxCount: stuckCount,
    );
  }

  Future<String?> assertSafeToClear() async {
    final info = await precheck();
    if (info.hasStuckWrites) return 'stuck_outbox';
    if (info.hasPendingWrites) return 'pending_sync';
    return null;
  }

  Future<void> clearShopScopedData() => _db.wipeSyncedData();
}
