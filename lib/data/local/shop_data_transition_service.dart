import 'package:drift/drift.dart';

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
    final rows = await (_db.select(
      _db.outbox,
    )..where((o) => o.quarantined.equals(false))).get();
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

  /// Rewrites every synced table's `shop_id` from [fromShopId] to [toShopId]
  /// in place (one transaction), rekeys shop-scoped `app_settings` rows, and
  /// enqueues an outbox `upsert` for every row that moved so the now-
  /// relabeled data actually reaches the server under the new id.
  ///
  /// Used when a Free-plan shop (`shop_id = free-<deviceId>`, purely local,
  /// no server row — see `sync_providers.dart`'s `syncEngineProvider`)
  /// redeems a key or creates a real account: its historical local data must
  /// travel with it under the new server-assigned shop_id, not be silently
  /// stranded behind the old one.
  ///
  /// Naturally idempotent, by construction rather than an explicit crash
  /// flag: every step is `WHERE shop_id = fromShopId` (or the settings
  /// equivalent), so a table with nothing left at [fromShopId] contributes
  /// zero rewritten rows AND zero backfilled outbox rows on a second pass —
  /// safe to blindly re-run after a crash between this call and the
  /// subsequent file rename (see `DatabaseSession.reopenForShopPromotedFrom`
  /// and `resolvePendingShopPromotion`, which do exactly that on next
  /// launch if `SettingsRepository.pendingShopPromotion()` is still set).
  Future<void> promoteShopIdentity({
    required String fromShopId,
    required String toShopId,
  }) async {
    if (fromShopId.isEmpty || toShopId.isEmpty || fromShopId == toShopId) {
      return;
    }
    await _db.transaction(() async {
      await _promoteCategories(fromShopId, toShopId);
      await _promoteProducts(fromShopId, toShopId);
      await _promoteStockLevels(fromShopId, toShopId);
      await _promoteStockMovements(fromShopId, toShopId);
      await _promoteSales(fromShopId, toShopId);
      await _promoteSaleItems(fromShopId, toShopId);
      await _promotePayments(fromShopId, toShopId);
      await _promoteLicensePayments(fromShopId, toShopId);
      await _promoteCreditPayments(fromShopId, toShopId);
      await _promoteOrders(fromShopId, toShopId);
      await _promoteOrderItems(fromShopId, toShopId);
      await _promoteStaffMembers(fromShopId, toShopId);
      await _promoteCustomers(fromShopId, toShopId);
      await _promoteExpenses(fromShopId, toShopId);
      await _promoteCashSessions(fromShopId, toShopId);
      await _promoteDeviceLabels(fromShopId, toShopId);
      await _promoteRecurringExpenses(fromShopId, toShopId);
      await _promoteSuppliers(fromShopId, toShopId);
      await _promotePurchaseOrders(fromShopId, toShopId);
      await _promotePurchaseOrderItems(fromShopId, toShopId);
      await _promotePaymentAccounts(fromShopId, toShopId);
      await _promoteSupplierPayments(fromShopId, toShopId);
      await _promoteEquityEntries(fromShopId, toShopId);
      await _promoteShopProfiles(fromShopId, toShopId);
      // Shop-scoped settings (SettingsRepository._shopKey: `<base>.<shopId>`)
      // — device-global keys never carry a shop suffix, so this can't touch
      // them. `stock_lots` is deliberately excluded: local-only FIFO cache,
      // no `shop_id` column at all (see `tables.dart`).
      await _db.customStatement(
        'UPDATE app_settings SET key = REPLACE(key, ?, ?) WHERE key LIKE ?',
        ['.$fromShopId', '.$toShopId', '%.$fromShopId'],
      );
    });
  }

  Future<void> _enqueueOutbox(String entityTable, Iterable<String> ids) async {
    for (final id in ids) {
      await _db
          .into(_db.outbox)
          .insert(
            OutboxCompanion.insert(
              entityTable: entityTable,
              rowId: id,
              op: 'upsert',
            ),
          );
    }
  }

  Future<void> _promoteCategories(String from, String to) async {
    final rows = await (_db.select(
      _db.categories,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.categories)..where((t) => t.shopId.equals(from)))
        .write(CategoriesCompanion(shopId: Value(to)));
    await _enqueueOutbox(
      'categories',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promoteProducts(String from, String to) async {
    final rows = await (_db.select(
      _db.products,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.products)..where((t) => t.shopId.equals(from))).write(
      ProductsCompanion(shopId: Value(to)),
    );
    await _enqueueOutbox(
      'products',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promoteStockLevels(String from, String to) async {
    final rows = await (_db.select(
      _db.stockLevels,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.stockLevels)..where((t) => t.shopId.equals(from)))
        .write(StockLevelsCompanion(shopId: Value(to)));
    await _enqueueOutbox(
      'stock_levels',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promoteStockMovements(String from, String to) async {
    final rows = await (_db.select(
      _db.stockMovements,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.stockMovements)..where((t) => t.shopId.equals(from)))
        .write(StockMovementsCompanion(shopId: Value(to)));
    await _enqueueOutbox(
      'stock_movements',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promoteSales(String from, String to) async {
    final rows = await (_db.select(
      _db.sales,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.sales)..where((t) => t.shopId.equals(from))).write(
      SalesCompanion(shopId: Value(to)),
    );
    await _enqueueOutbox(
      'sales',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promoteSaleItems(String from, String to) async {
    final rows = await (_db.select(
      _db.saleItems,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.saleItems)..where((t) => t.shopId.equals(from)))
        .write(SaleItemsCompanion(shopId: Value(to)));
    await _enqueueOutbox(
      'sale_items',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promotePayments(String from, String to) async {
    final rows = await (_db.select(
      _db.payments,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.payments)..where((t) => t.shopId.equals(from))).write(
      PaymentsCompanion(shopId: Value(to)),
    );
    await _enqueueOutbox(
      'payments',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promoteLicensePayments(String from, String to) async {
    final rows = await (_db.select(
      _db.licensePayments,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.licensePayments)..where((t) => t.shopId.equals(from)))
        .write(LicensePaymentsCompanion(shopId: Value(to)));
    await _enqueueOutbox(
      'license_payments',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promoteCreditPayments(String from, String to) async {
    final rows = await (_db.select(
      _db.creditPayments,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.creditPayments)..where((t) => t.shopId.equals(from)))
        .write(CreditPaymentsCompanion(shopId: Value(to)));
    await _enqueueOutbox(
      'credit_payments',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promoteOrders(String from, String to) async {
    final rows = await (_db.select(
      _db.orders,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.orders)..where((t) => t.shopId.equals(from))).write(
      OrdersCompanion(shopId: Value(to)),
    );
    await _enqueueOutbox(
      'orders',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promoteOrderItems(String from, String to) async {
    final rows = await (_db.select(
      _db.orderItems,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.orderItems)..where((t) => t.shopId.equals(from)))
        .write(OrderItemsCompanion(shopId: Value(to)));
    await _enqueueOutbox(
      'order_items',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promoteStaffMembers(String from, String to) async {
    final rows = await (_db.select(
      _db.staffMembers,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.staffMembers)..where((t) => t.shopId.equals(from)))
        .write(StaffMembersCompanion(shopId: Value(to)));
    await _enqueueOutbox(
      'staff_members',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promoteCustomers(String from, String to) async {
    final rows = await (_db.select(
      _db.customers,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.customers)..where((t) => t.shopId.equals(from)))
        .write(CustomersCompanion(shopId: Value(to)));
    await _enqueueOutbox(
      'customers',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promoteExpenses(String from, String to) async {
    final rows = await (_db.select(
      _db.expenses,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.expenses)..where((t) => t.shopId.equals(from))).write(
      ExpensesCompanion(shopId: Value(to)),
    );
    await _enqueueOutbox(
      'expenses',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promoteCashSessions(String from, String to) async {
    final rows = await (_db.select(
      _db.cashSessions,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.cashSessions)..where((t) => t.shopId.equals(from)))
        .write(CashSessionsCompanion(shopId: Value(to)));
    await _enqueueOutbox(
      'cash_sessions',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promoteDeviceLabels(String from, String to) async {
    final rows = await (_db.select(
      _db.deviceLabels,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.deviceLabels)..where((t) => t.shopId.equals(from)))
        .write(DeviceLabelsCompanion(shopId: Value(to)));
    await _enqueueOutbox(
      'device_labels',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promoteRecurringExpenses(String from, String to) async {
    final rows = await (_db.select(
      _db.recurringExpenses,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.recurringExpenses)
          ..where((t) => t.shopId.equals(from)))
        .write(RecurringExpensesCompanion(shopId: Value(to)));
    await _enqueueOutbox(
      'recurring_expenses',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promoteSuppliers(String from, String to) async {
    final rows = await (_db.select(
      _db.suppliers,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.suppliers)..where((t) => t.shopId.equals(from)))
        .write(SuppliersCompanion(shopId: Value(to)));
    await _enqueueOutbox(
      'suppliers',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promotePurchaseOrders(String from, String to) async {
    final rows = await (_db.select(
      _db.purchaseOrders,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.purchaseOrders)..where((t) => t.shopId.equals(from)))
        .write(PurchaseOrdersCompanion(shopId: Value(to)));
    await _enqueueOutbox(
      'purchase_orders',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promotePurchaseOrderItems(String from, String to) async {
    final rows = await (_db.select(
      _db.purchaseOrderItems,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.purchaseOrderItems)
          ..where((t) => t.shopId.equals(from)))
        .write(PurchaseOrderItemsCompanion(shopId: Value(to)));
    await _enqueueOutbox(
      'purchase_order_items',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promotePaymentAccounts(String from, String to) async {
    final rows = await (_db.select(
      _db.paymentAccounts,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.paymentAccounts)..where((t) => t.shopId.equals(from)))
        .write(PaymentAccountsCompanion(shopId: Value(to)));
    await _enqueueOutbox(
      'payment_accounts',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promoteSupplierPayments(String from, String to) async {
    final rows = await (_db.select(
      _db.supplierPayments,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.supplierPayments)
          ..where((t) => t.shopId.equals(from)))
        .write(SupplierPaymentsCompanion(shopId: Value(to)));
    await _enqueueOutbox(
      'supplier_payments',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  Future<void> _promoteEquityEntries(String from, String to) async {
    final rows = await (_db.select(
      _db.equityEntries,
    )..where((t) => t.shopId.equals(from))).get();
    await (_db.update(_db.equityEntries)..where((t) => t.shopId.equals(from)))
        .write(EquityEntriesCompanion(shopId: Value(to)));
    await _enqueueOutbox(
      'equity_entries',
      rows.where((r) => !r.isDeleted).map((r) => r.id),
    );
  }

  /// `id == shopId` for this table (one row per shop) — unlike every other
  /// promote above, both columns must move together or the row would end up
  /// with a stale `id` that no longer matches its own `shopId`.
  Future<void> _promoteShopProfiles(String from, String to) async {
    final row = await (_db.select(
      _db.shopProfiles,
    )..where((t) => t.id.equals(from))).getSingleOrNull();
    if (row == null) return;
    await (_db.update(_db.shopProfiles)..where((t) => t.id.equals(from)))
        .write(ShopProfilesCompanion(id: Value(to), shopId: Value(to)));
    if (!row.isDeleted) {
      await _enqueueOutbox('shop_profiles', [to]);
    }
  }
}
