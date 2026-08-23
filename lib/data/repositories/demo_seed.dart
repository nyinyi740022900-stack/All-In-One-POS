import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../local/database.dart';
import '../repositories/settings_repository.dart';
import 'inventory_repository.dart';

/// One row of the debug-only minimart catalogue. Also used to recognize
/// accidental duplicate copies (same name **and** SKU) on a real shop.
class DemoSeedItem {
  final String name;
  final String sku;
  final int sale;
  final int cost;
  final int qty;
  final int reorder;
  const DemoSeedItem(
      this.name, this.sku, this.sale, this.cost, this.qty, this.reorder);
}

/// Seeds a handful of typical Myanmar minimart products for **debug**
/// first-run only. Production builds never call this — a real shop that
/// opened Inventory on an empty local DB (fresh install, branch switch wipe,
/// or before the first sync pull) used to get a second copy of Coca-Cola /
/// soap / etc. with new UUIDs, then keep both after cloud products arrived.
class DemoSeed {
  DemoSeed(
    this._db,
    this._repo,
    this._shopId, {
    bool? enabled,
  }) : _enabled = enabled ?? kDebugMode;

  final AppDatabase _db;
  final InventoryRepository _repo;
  final String _shopId;
  final bool _enabled;

  static const catalog = <DemoSeedItem>[
    DemoSeedItem('ကိုကာကိုလာ (ဗူး)', 'Coca-Cola can', 700, 550, 24, 6),
    DemoSeedItem('ရွှေဖီ ကော်ဖီမစ်', '3-in-1 coffee', 300, 220, 100, 20),
    DemoSeedItem('အုန်းနို့ ဘီစကွတ်', 'Coconut biscuit', 500, 380, 40, 10),
    DemoSeedItem('ရေသန့် (၁ လီတာ)', 'Drinking water 1L', 400, 250, 60, 12),
    DemoSeedItem('မီးခြစ်', 'Match box', 100, 60, 200, 30),
    DemoSeedItem('ဆပ်ပြာ', 'Bar soap', 800, 600, 30, 8),
  ];

  /// One in-flight seed per shop, so two overlapping Inventory mounts
  /// cannot both see "empty" and insert two catalogues. Cleared when the
  /// flight finishes (success or failure) so a failed seed can retry.
  static final _inFlight = <String, Future<void>>{};

  Future<void> ensureSeeded() {
    if (!_enabled || _shopId.isEmpty) return Future.value();
    return _inFlight.putIfAbsent(_shopId, () async {
      try {
        await _seed();
      } finally {
        _inFlight.remove(_shopId);
      }
    });
  }

  Future<void> _seed() async {
    final existing = await (_db.select(_db.products)
          ..where((p) => p.shopId.equals(_shopId)))
        .get();
    if (existing.isNotEmpty) return;

    for (final it in catalog) {
      await _repo.upsertProduct(
        name: it.name,
        sku: it.sku,
        salePrice: it.sale,
        costPrice: it.cost,
        quantity: it.qty,
        reorderLevel: it.reorder,
      );
    }
  }

  /// True only for a row that still looks like a debug-seed insert: same
  /// Myanmar name **and** English SKU as the catalogue. A shop that stocked
  /// two real products named e.g. ဆပ်ပြာ with their own SKUs is left alone.
  static bool isSeedCopy(Product p) {
    final sku = p.sku ?? '';
    if (sku.isEmpty) return false;
    for (final i in catalog) {
      if (i.name == p.name && i.sku == sku) return true;
    }
    return false;
  }

  /// Tombstones extra copies of the demo catalogue (name + SKU), keeping
  /// the row the shop actually used (photo, sales, or stock that moved).
  /// Invoices keep their `nameSnapshot`, so history is unchanged.
  /// Idempotent: a single live seed row per name is a no-op.
  Future<int> collapseDuplicates() async {
    if (_shopId.isEmpty) return 0;
    final live = await (_db.select(_db.products)
          ..where((p) =>
              p.shopId.equals(_shopId) & p.isDeleted.equals(false)))
        .get();
    final groups = <String, List<Product>>{};
    for (final p in live) {
      if (!isSeedCopy(p)) continue;
      (groups[p.name] ??= []).add(p);
    }

    var removed = 0;
    for (final group in groups.values) {
      if (group.length < 2) continue;
      final keeperId = await _keeperId(group);
      for (final p in group) {
        if (p.id == keeperId) continue;
        await _repo.deleteProduct(p.id);
        removed++;
      }
    }
    return removed;
  }

  Future<String> _keeperId(List<Product> group) async {
    String? bestId;
    var bestScore = -1;
    DateTime? bestCreated;
    for (final p in group) {
      final score = await _score(p);
      final better = score > bestScore ||
          (score == bestScore &&
              (bestCreated == null || p.createdAt.isBefore(bestCreated)));
      if (better) {
        bestScore = score;
        bestId = p.id;
        bestCreated = p.createdAt;
      }
    }
    return bestId!;
  }

  Future<int> _score(Product p) async {
    var score = 0;
    if ((p.imageUrl ?? '').trim().isNotEmpty) score += 1000;
    final sales = await (_db.select(_db.stockMovements)
          ..where((m) =>
              m.productId.equals(p.id) &
              m.shopId.equals(_shopId) &
              m.type.equals('sale')))
        .get();
    score += sales.length * 10;
    final otherMoves = await (_db.select(_db.stockMovements)
          ..where((m) =>
              m.productId.equals(p.id) &
              m.shopId.equals(_shopId) &
              m.type.isNotValue('opening')))
        .get();
    if (otherMoves.isNotEmpty) score += 5;
    final stock = await (_db.select(_db.stockLevels)
          ..where((s) => s.productId.equals(p.id)))
        .get();
    final qty = stock.isEmpty ? 0 : stock.first.quantity;
    final seedQty = catalog
        .where((i) => i.name == p.name)
        .map((i) => i.qty)
        .firstOrNull;
    if (seedQty != null && qty != seedQty) score += 20;
    return score;
  }

  /// Test-only: the process-wide lock survives across DemoSeed instances.
  @visibleForTesting
  static void resetInFlightForTest() => _inFlight.clear();
}

/// Everything Inventory's first frame used to do inline on EVERY tab mount
/// (audit M2), now behind a one-shot per-shop flag:
///   1. debug-only demo seeding (unchanged),
///   2. the #177 duplicate-seed cleanup — runs ONCE per shop per device,
///      then [SettingsRepository.seedCleanupDone] short-circuits every later
///      mount so release builds stop full-table-scanning `products` each
///      time the tab opens. Shop-scoped key: branch switch must still clean
///      the next shop once.
Future<void> runInventoryStartupMaintenance({
  required AppDatabase db,
  required InventoryRepository repo,
  required String shopId,
  SettingsRepository? settings,
}) async {
  if (shopId.isEmpty) return;
  final seed = DemoSeed(db, repo, shopId);
  await seed.ensureSeeded();

  // Null settings (callers without one, older tests) keeps the old
  // always-run behaviour rather than silently skipping cleanup.
  final skipCleanup =
      settings != null && await settings.seedCleanupDone(shopId);
  if (skipCleanup) return;

  await seed.collapseDuplicates();
  await settings?.setSeedCleanupDone(shopId);
}
