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

/// Result of [ShopDataTransitionService.prepareShopSwitch].
class ShopSwitchPreparation {
  final String fromShopId;
  final String toShopId;
  final String targetDbFileName;
  final bool usedWipeFallback;

  const ShopSwitchPreparation({
    required this.fromShopId,
    required this.toShopId,
    required this.targetDbFileName,
    required this.usedWipeFallback,
  });
}

/// Centralized guard for destructive / shop-scope transitions.
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

  /// When [AppDatabase.usePerShopDbFiles] is true, skips wipe — caller must
  /// reopen the target shop DB file. Otherwise wipes the shared legacy DB.
  Future<ShopSwitchPreparation> prepareShopSwitch({
    required String fromShopId,
    required String toShopId,
  }) async {
    final targetDbFileName = AppDatabase.fileNameForShop(toShopId);
    final useSwap = AppDatabase.usePerShopDbFiles && toShopId.isNotEmpty;
    if (!useSwap) {
      await clearShopScopedData();
    }
    return ShopSwitchPreparation(
      fromShopId: fromShopId,
      toShopId: toShopId,
      targetDbFileName: targetDbFileName,
      usedWipeFallback: !useSwap,
    );
  }
}
