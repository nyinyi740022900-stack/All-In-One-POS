import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../local/database.dart';

const _syncMappersUuid = Uuid();

/// Describes how one table is serialized to Supabase and merged back.
///
/// [toRemote] reads the current local row and returns a snake_case map (or null
/// if the row vanished). [upsertLocal] applies a remote row using last-write-
/// wins: a remote change is only written when its `updated_at` is newer than
/// the local copy, so unsynced local edits are never clobbered.
class SyncTableDef {
  final String name;
  final Future<Map<String, dynamic>?> Function(AppDatabase db, String id)
      toRemote;
  final Future<void> Function(AppDatabase db, Map<String, dynamic> remote)
      upsertLocal;

  const SyncTableDef({
    required this.name,
    required this.toRemote,
    required this.upsertLocal,
  });
}

String _iso(DateTime d) => d.toUtc().toIso8601String();
DateTime _dt(dynamic v) => DateTime.parse(v as String).toLocal();
int _int(dynamic v) => (v as num).toInt();
bool _bool(dynamic v) => v == true;

/// Registry of all synced tables. `app_settings` and `outbox` are device-local
/// and intentionally excluded.
final syncTables = <SyncTableDef>[
  _categories,
  _products,
  _stockLevels,
  _stockMovements,
  _sales,
  _saleItems,
  _payments,
  _licensePayments,
  _creditPayments,
  _orders,
  _orderItems,
  _staffMembers,
  _customers,
  _expenses,
  _cashSessions,
  _deviceLabels,
  _recurringExpenses,
  _suppliers,
  _purchaseOrders,
  _purchaseOrderItems,
];

// --- categories -------------------------------------------------------------
final _categories = SyncTableDef(
  name: 'categories',
  toRemote: (db, id) async {
    final r = await (db.select(db.categories)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    return {
      'id': r.id,
      'shop_id': r.shopId,
      'name': r.name,
      'sort': r.sort,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'is_deleted': r.isDeleted,
    };
  },
  upsertLocal: (db, m) async {
    final id = m['id'] as String;
    final updated = _dt(m['updated_at']);
    final local = await (db.select(db.categories)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && !local.updatedAt.isBefore(updated)) return;
    await db.into(db.categories).insertOnConflictUpdate(CategoriesCompanion(
          id: Value(id),
          shopId: Value(m['shop_id'] as String),
          name: Value(m['name'] as String),
          sort: Value(_int(m['sort'])),
          createdAt: Value(_dt(m['created_at'])),
          updatedAt: Value(updated),
          isDeleted: Value(_bool(m['is_deleted'])),
          dirty: const Value(false),
        ));
  },
);

// --- staff_members -----------------------------------------------------------
final _staffMembers = SyncTableDef(
  name: 'staff_members',
  toRemote: (db, id) async {
    final r = await (db.select(db.staffMembers)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    return {
      'id': r.id,
      'shop_id': r.shopId,
      'name': r.name,
      'pin': r.pin,
      'active': r.active,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'is_deleted': r.isDeleted,
    };
  },
  upsertLocal: (db, m) async {
    final id = m['id'] as String;
    final updated = _dt(m['updated_at']);
    final local = await (db.select(db.staffMembers)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && !local.updatedAt.isBefore(updated)) return;
    await db.into(db.staffMembers).insertOnConflictUpdate(
        StaffMembersCompanion(
          id: Value(id),
          shopId: Value(m['shop_id'] as String),
          name: Value(m['name'] as String),
          pin: Value(m['pin'] as String),
          active: Value(_bool(m['active'])),
          createdAt: Value(_dt(m['created_at'])),
          updatedAt: Value(updated),
          isDeleted: Value(_bool(m['is_deleted'])),
          dirty: const Value(false),
        ));
  },
);

// --- customers ---------------------------------------------------------------
final _customers = SyncTableDef(
  name: 'customers',
  toRemote: (db, id) async {
    final r = await (db.select(db.customers)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    return {
      'id': r.id,
      'shop_id': r.shopId,
      'name': r.name,
      'phone': r.phone,
      'address': r.address,
      'township': r.township,
      'tier': r.tier,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'is_deleted': r.isDeleted,
    };
  },
  upsertLocal: (db, m) async {
    final id = m['id'] as String;
    final updated = _dt(m['updated_at']);
    final local = await (db.select(db.customers)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && !local.updatedAt.isBefore(updated)) return;
    await db.into(db.customers).insertOnConflictUpdate(CustomersCompanion(
          id: Value(id),
          shopId: Value(m['shop_id'] as String),
          name: Value(m['name'] as String),
          phone: Value(m['phone'] as String?),
          address: Value(m['address'] as String?),
          township: Value(m['township'] as String?),
          tier: Value((m['tier'] as String?) ?? 'retail'),
          createdAt: Value(_dt(m['created_at'])),
          updatedAt: Value(updated),
          isDeleted: Value(_bool(m['is_deleted'])),
          dirty: const Value(false),
        ));
  },
);

// --- products ---------------------------------------------------------------
final _products = SyncTableDef(
  name: 'products',
  toRemote: (db, id) async {
    final r = await (db.select(db.products)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    return {
      'id': r.id,
      'shop_id': r.shopId,
      'name': r.name,
      'sku': r.sku,
      'barcode': r.barcode,
      'category_id': r.categoryId,
      'cost_price': r.costPrice,
      'sale_price': r.salePrice,
      'wholesale_price': r.wholesalePrice,
      'vip_price': r.vipPrice,
      'online_stock_limit': r.onlineStockLimit,
      'unit': r.unit,
      'image_path': r.imagePath,
      'image_url': r.imageUrl,
      'is_active': r.isActive,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'is_deleted': r.isDeleted,
    };
  },
  upsertLocal: (db, m) async {
    final id = m['id'] as String;
    final updated = _dt(m['updated_at']);
    final local = await (db.select(db.products)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && !local.updatedAt.isBefore(updated)) return;
    await db.into(db.products).insertOnConflictUpdate(ProductsCompanion(
          id: Value(id),
          shopId: Value(m['shop_id'] as String),
          name: Value(m['name'] as String),
          sku: Value(m['sku'] as String?),
          barcode: Value(m['barcode'] as String?),
          categoryId: Value(m['category_id'] as String?),
          costPrice: Value(_int(m['cost_price'])),
          salePrice: Value(_int(m['sale_price'])),
          wholesalePrice: Value(
              m['wholesale_price'] == null ? null : _int(m['wholesale_price'])),
          vipPrice:
              Value(m['vip_price'] == null ? null : _int(m['vip_price'])),
          onlineStockLimit: Value(m['online_stock_limit'] == null
              ? null
              : _int(m['online_stock_limit'])),
          unit: Value((m['unit'] as String?) ?? 'pcs'),
          imagePath: Value(m['image_path'] as String?),
          imageUrl: Value(m['image_url'] as String?),
          isActive: Value(m['is_active'] == null ? true : _bool(m['is_active'])),
          createdAt: Value(_dt(m['created_at'])),
          updatedAt: Value(updated),
          isDeleted: Value(_bool(m['is_deleted'])),
          dirty: const Value(false),
        ));
  },
);

// --- stock_levels -----------------------------------------------------------
final _stockLevels = SyncTableDef(
  name: 'stock_levels',
  toRemote: (db, id) async {
    final r = await (db.select(db.stockLevels)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    return {
      'id': r.id,
      'shop_id': r.shopId,
      'product_id': r.productId,
      'quantity': r.quantity,
      'reorder_level': r.reorderLevel,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'is_deleted': r.isDeleted,
    };
  },
  // `quantity` is a counter — CLAUDE.md explicitly forbids syncing a counter
  // as an absolute last-write-wins value (two offline devices selling the
  // same product would have one's decrement silently clobber the other's on
  // whichever pushes last). This device's own `quantity` is instead
  // reconciled purely from `stock_movements` deltas (see `_stockMovements`
  // below, the append-only, conflict-safe source of truth) — a pulled
  // `stock_levels` row only ever updates `reorder_level` (a real per-shop
  // setting, safe under LWW) and identity/tombstone fields.
  upsertLocal: (db, m) async {
    final id = m['id'] as String;
    final updated = _dt(m['updated_at']);
    final local = await (db.select(db.stockLevels)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && !local.updatedAt.isBefore(updated)) return;
    await db.into(db.stockLevels).insertOnConflictUpdate(StockLevelsCompanion(
          id: Value(id),
          shopId: Value(m['shop_id'] as String),
          productId: Value(m['product_id'] as String),
          reorderLevel: Value(_int(m['reorder_level'])),
          createdAt: Value(_dt(m['created_at'])),
          updatedAt: Value(updated),
          isDeleted: Value(_bool(m['is_deleted'])),
          dirty: const Value(false),
        ));
  },
);

// --- stock_movements --------------------------------------------------------
final _stockMovements = SyncTableDef(
  name: 'stock_movements',
  toRemote: (db, id) async {
    final r = await (db.select(db.stockMovements)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    return {
      'id': r.id,
      'shop_id': r.shopId,
      'product_id': r.productId,
      'type': r.type,
      'qty_delta': r.qtyDelta,
      'unit_cost': r.unitCost,
      'ref_id': r.refId,
      'note': r.note,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'is_deleted': r.isDeleted,
    };
  },
  upsertLocal: (db, m) async {
    final id = m['id'] as String;
    final updated = _dt(m['updated_at']);
    await db.transaction(() async {
      final local =
          await (db.select(db.stockMovements)..where((t) => t.id.equals(id)))
              .getSingleOrNull();
      if (local != null && !local.updatedAt.isBefore(updated)) return;
      // A movement never seen on this device before originated on ANOTHER
      // device — reconcile the cached `stock_levels.quantity` by applying its
      // delta now, exactly once. A movement this device created itself
      // already applied its delta at creation time (see
      // InventoryRepository.adjustStock/finalizeSale/etc.), so `local` being
      // non-null (already present, e.g. echoed back after a push) means
      // "already accounted for" and must NOT be re-applied.
      final isNewMovement = local == null;
      await db
          .into(db.stockMovements)
          .insertOnConflictUpdate(StockMovementsCompanion(
            id: Value(id),
            shopId: Value(m['shop_id'] as String),
            productId: Value(m['product_id'] as String),
            type: Value(m['type'] as String),
            qtyDelta: Value(_int(m['qty_delta'])),
            unitCost: Value(_int(m['unit_cost'])),
            refId: Value(m['ref_id'] as String?),
            note: Value(m['note'] as String?),
            createdAt: Value(_dt(m['created_at'])),
            updatedAt: Value(updated),
            isDeleted: Value(_bool(m['is_deleted'])),
            dirty: const Value(false),
          ));

      if (isNewMovement && !_bool(m['is_deleted'])) {
        final productId = m['product_id'] as String;
        final shopId = m['shop_id'] as String;
        final delta = _int(m['qty_delta']);
        final existingLevel = await (db.select(db.stockLevels)
              ..where((t) =>
                  t.productId.equals(productId) & t.shopId.equals(shopId)))
            .getSingleOrNull();
        final now = DateTime.now();
        if (existingLevel != null) {
          await (db.update(db.stockLevels)
                ..where((t) => t.id.equals(existingLevel.id)))
              .write(StockLevelsCompanion(
            quantity: Value(existingLevel.quantity + delta),
            updatedAt: Value(now),
            dirty: const Value(true),
          ));
        } else {
          await db.into(db.stockLevels).insert(StockLevelsCompanion.insert(
                id: _syncMappersUuid.v4(),
                shopId: shopId,
                productId: productId,
                quantity: Value(delta),
              ));
        }
      }
    });
  },
);

// --- sales ------------------------------------------------------------------
final _sales = SyncTableDef(
  name: 'sales',
  toRemote: (db, id) async {
    final r = await (db.select(db.sales)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    return {
      'id': r.id,
      'shop_id': r.shopId,
      'invoice_no': r.invoiceNo,
      'staff_id': r.staffId,
      'subtotal': r.subtotal,
      'discount': r.discount,
      'total': r.total,
      'paid': r.paid,
      'change_due': r.changeDue,
      'payment_method': r.paymentMethod,
      'customer_name': r.customerName,
      'customer_phone': r.customerPhone,
      'customer_id': r.customerId,
      'note': r.note,
      'refund_of_sale_id': r.refundOfSaleId,
      'device_id': r.deviceId,
      'delivery_address': r.deliveryAddress,
      'finalized_at': _iso(r.finalizedAt),
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'is_deleted': r.isDeleted,
    };
  },
  upsertLocal: (db, m) async {
    final id = m['id'] as String;
    final updated = _dt(m['updated_at']);
    final local = await (db.select(db.sales)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && !local.updatedAt.isBefore(updated)) return;
    await db.into(db.sales).insertOnConflictUpdate(SalesCompanion(
          id: Value(id),
          shopId: Value(m['shop_id'] as String),
          invoiceNo: Value(m['invoice_no'] as String),
          staffId: Value(m['staff_id'] as String?),
          subtotal: Value(_int(m['subtotal'])),
          discount: Value(_int(m['discount'])),
          total: Value(_int(m['total'])),
          paid: Value(_int(m['paid'])),
          changeDue: Value(_int(m['change_due'])),
          paymentMethod: Value((m['payment_method'] as String?) ?? 'cash'),
          customerName: Value(m['customer_name'] as String?),
          customerPhone: Value(m['customer_phone'] as String?),
          customerId: Value(m['customer_id'] as String?),
          note: Value(m['note'] as String?),
          refundOfSaleId: Value(m['refund_of_sale_id'] as String?),
          deviceId: Value(m['device_id'] as String?),
          deliveryAddress: Value(m['delivery_address'] as String?),
          finalizedAt: Value(_dt(m['finalized_at'])),
          createdAt: Value(_dt(m['created_at'])),
          updatedAt: Value(updated),
          isDeleted: Value(_bool(m['is_deleted'])),
          dirty: const Value(false),
        ));
  },
);

// --- sale_items -------------------------------------------------------------
final _saleItems = SyncTableDef(
  name: 'sale_items',
  toRemote: (db, id) async {
    final r = await (db.select(db.saleItems)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    return {
      'id': r.id,
      'shop_id': r.shopId,
      'sale_id': r.saleId,
      'product_id': r.productId,
      'name_snapshot': r.nameSnapshot,
      'price_snapshot': r.priceSnapshot,
      'qty': r.qty,
      'line_total': r.lineTotal,
      'cost_snapshot': r.costSnapshot,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'is_deleted': r.isDeleted,
    };
  },
  upsertLocal: (db, m) async {
    final id = m['id'] as String;
    final updated = _dt(m['updated_at']);
    final local = await (db.select(db.saleItems)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && !local.updatedAt.isBefore(updated)) return;
    await db.into(db.saleItems).insertOnConflictUpdate(SaleItemsCompanion(
          id: Value(id),
          shopId: Value(m['shop_id'] as String),
          saleId: Value(m['sale_id'] as String),
          productId: Value(m['product_id'] as String),
          nameSnapshot: Value(m['name_snapshot'] as String),
          priceSnapshot: Value(_int(m['price_snapshot'])),
          qty: Value(_int(m['qty'])),
          lineTotal: Value(_int(m['line_total'])),
          costSnapshot: Value(
              m['cost_snapshot'] == null ? null : _int(m['cost_snapshot'])),
          createdAt: Value(_dt(m['created_at'])),
          updatedAt: Value(updated),
          isDeleted: Value(_bool(m['is_deleted'])),
          dirty: const Value(false),
        ));
  },
);

// --- license_payments -------------------------------------------------------
final _licensePayments = SyncTableDef(
  name: 'license_payments',
  toRemote: (db, id) async {
    final r = await (db.select(db.licensePayments)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    return {
      'id': r.id,
      'shop_id': r.shopId,
      'license_key': r.licenseKey,
      'method': r.method,
      'amount': r.amount,
      'ref_no': r.refNo,
      'note': r.note,
      'shop_name': r.shopName,
      'reconciled': r.reconciled,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'is_deleted': r.isDeleted,
    };
  },
  upsertLocal: (db, m) async {
    final id = m['id'] as String;
    final updated = _dt(m['updated_at']);
    final local =
        await (db.select(db.licensePayments)..where((t) => t.id.equals(id)))
            .getSingleOrNull();
    if (local != null && !local.updatedAt.isBefore(updated)) return;
    await db
        .into(db.licensePayments)
        .insertOnConflictUpdate(LicensePaymentsCompanion(
          id: Value(id),
          shopId: Value(m['shop_id'] as String),
          licenseKey: Value(m['license_key'] as String),
          method: Value(m['method'] as String),
          amount: Value(_int(m['amount'])),
          refNo: Value(m['ref_no'] as String?),
          note: Value(m['note'] as String?),
          shopName: Value(m['shop_name'] as String?),
          reconciled: Value(_bool(m['reconciled'])),
          createdAt: Value(_dt(m['created_at'])),
          updatedAt: Value(updated),
          isDeleted: Value(_bool(m['is_deleted'])),
          dirty: const Value(false),
        ));
  },
);

// --- credit_payments --------------------------------------------------------
final _creditPayments = SyncTableDef(
  name: 'credit_payments',
  toRemote: (db, id) async {
    final r = await (db.select(db.creditPayments)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    return {
      'id': r.id,
      'shop_id': r.shopId,
      'customer_name': r.customerName,
      'customer_id': r.customerId,
      'method': r.method,
      'amount': r.amount,
      'note': r.note,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'is_deleted': r.isDeleted,
    };
  },
  upsertLocal: (db, m) async {
    final id = m['id'] as String;
    final updated = _dt(m['updated_at']);
    final local =
        await (db.select(db.creditPayments)..where((t) => t.id.equals(id)))
            .getSingleOrNull();
    if (local != null && !local.updatedAt.isBefore(updated)) return;
    await db
        .into(db.creditPayments)
        .insertOnConflictUpdate(CreditPaymentsCompanion(
          id: Value(id),
          shopId: Value(m['shop_id'] as String),
          customerName: Value(m['customer_name'] as String),
          customerId: Value(m['customer_id'] as String?),
          method: Value((m['method'] as String?) ?? 'cash'),
          amount: Value(_int(m['amount'])),
          note: Value(m['note'] as String?),
          createdAt: Value(_dt(m['created_at'])),
          updatedAt: Value(updated),
          isDeleted: Value(_bool(m['is_deleted'])),
          dirty: const Value(false),
        ));
  },
);

// --- orders -----------------------------------------------------------------
final _orders = SyncTableDef(
  name: 'orders',
  toRemote: (db, id) async {
    final r = await (db.select(db.orders)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    return {
      'id': r.id,
      'shop_id': r.shopId,
      'order_no': r.orderNo,
      'channel': r.channel,
      'status': r.status,
      'customer_name': r.customerName,
      'customer_phone': r.customerPhone,
      'delivery_address': r.deliveryAddress,
      'delivery_fee': r.deliveryFee,
      'items_total': r.itemsTotal,
      'payment_status': r.paymentStatus,
      'payment_method': r.paymentMethod,
      'note': r.note,
      'sale_id': r.saleId,
      'payment_proof_path': r.paymentProofPath,
      'township': r.township,
      'delivery_carrier': r.deliveryCarrier,
      'tracking_number': r.trackingNumber,
      'delivery_status': r.deliveryStatus,
      'customer_id': r.customerId,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'is_deleted': r.isDeleted,
    };
  },
  upsertLocal: (db, m) async {
    final id = m['id'] as String;
    final updated = _dt(m['updated_at']);
    final local = await (db.select(db.orders)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && !local.updatedAt.isBefore(updated)) return;
    await db.into(db.orders).insertOnConflictUpdate(OrdersCompanion(
          id: Value(id),
          shopId: Value(m['shop_id'] as String),
          orderNo: Value(m['order_no'] as String),
          channel: Value((m['channel'] as String?) ?? 'facebook'),
          status: Value((m['status'] as String?) ?? 'new'),
          customerName: Value(m['customer_name'] as String),
          customerPhone: Value(m['customer_phone'] as String?),
          deliveryAddress: Value(m['delivery_address'] as String?),
          deliveryFee: Value(_int(m['delivery_fee'])),
          itemsTotal: Value(_int(m['items_total'])),
          paymentStatus: Value((m['payment_status'] as String?) ?? 'unpaid'),
          paymentMethod: Value(m['payment_method'] as String?),
          note: Value(m['note'] as String?),
          saleId: Value(m['sale_id'] as String?),
          paymentProofPath: Value(m['payment_proof_path'] as String?),
          township: Value(m['township'] as String?),
          deliveryCarrier: Value(m['delivery_carrier'] as String?),
          trackingNumber: Value(m['tracking_number'] as String?),
          deliveryStatus: Value(m['delivery_status'] as String?),
          customerId: Value(m['customer_id'] as String?),
          createdAt: Value(_dt(m['created_at'])),
          updatedAt: Value(updated),
          isDeleted: Value(_bool(m['is_deleted'])),
          dirty: const Value(false),
        ));
  },
);

// --- order_items ------------------------------------------------------------
final _orderItems = SyncTableDef(
  name: 'order_items',
  toRemote: (db, id) async {
    final r = await (db.select(db.orderItems)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    return {
      'id': r.id,
      'shop_id': r.shopId,
      'order_id': r.orderId,
      'product_id': r.productId,
      'name_snapshot': r.nameSnapshot,
      'price_snapshot': r.priceSnapshot,
      'qty': r.qty,
      'line_total': r.lineTotal,
      'low_stock_at_order': r.lowStockAtOrder,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'is_deleted': r.isDeleted,
    };
  },
  upsertLocal: (db, m) async {
    final id = m['id'] as String;
    final updated = _dt(m['updated_at']);
    final local = await (db.select(db.orderItems)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && !local.updatedAt.isBefore(updated)) return;
    await db.into(db.orderItems).insertOnConflictUpdate(OrderItemsCompanion(
          id: Value(id),
          shopId: Value(m['shop_id'] as String),
          orderId: Value(m['order_id'] as String),
          productId: Value(m['product_id'] as String?),
          nameSnapshot: Value(m['name_snapshot'] as String),
          priceSnapshot: Value(_int(m['price_snapshot'])),
          qty: Value(_int(m['qty'])),
          lineTotal: Value(_int(m['line_total'])),
          lowStockAtOrder: Value(_bool(m['low_stock_at_order'])),
          createdAt: Value(_dt(m['created_at'])),
          updatedAt: Value(updated),
          isDeleted: Value(_bool(m['is_deleted'])),
          dirty: const Value(false),
        ));
  },
);

// --- payments ---------------------------------------------------------------
final _payments = SyncTableDef(
  name: 'payments',
  toRemote: (db, id) async {
    final r = await (db.select(db.payments)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    return {
      'id': r.id,
      'shop_id': r.shopId,
      'sale_id': r.saleId,
      'method': r.method,
      'amount': r.amount,
      'ref_no': r.refNo,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'is_deleted': r.isDeleted,
    };
  },
  upsertLocal: (db, m) async {
    final id = m['id'] as String;
    final updated = _dt(m['updated_at']);
    final local = await (db.select(db.payments)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && !local.updatedAt.isBefore(updated)) return;
    await db.into(db.payments).insertOnConflictUpdate(PaymentsCompanion(
          id: Value(id),
          shopId: Value(m['shop_id'] as String),
          saleId: Value(m['sale_id'] as String),
          method: Value(m['method'] as String),
          amount: Value(_int(m['amount'])),
          refNo: Value(m['ref_no'] as String?),
          createdAt: Value(_dt(m['created_at'])),
          updatedAt: Value(updated),
          isDeleted: Value(_bool(m['is_deleted'])),
          dirty: const Value(false),
        ));
  },
);

// --- expenses ----------------------------------------------------------
// receiptPhotoPath is deliberately absent from both directions: it's a local
// file path, never uploaded, so the remote row and every other device simply
// never have one — see the doc comment on Expenses in tables.dart.
final _expenses = SyncTableDef(
  name: 'expenses',
  toRemote: (db, id) async {
    final r = await (db.select(db.expenses)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    return {
      'id': r.id,
      'shop_id': r.shopId,
      'category': r.category,
      'amount': r.amount,
      'date': _iso(r.date),
      'note': r.note,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'is_deleted': r.isDeleted,
    };
  },
  upsertLocal: (db, m) async {
    final id = m['id'] as String;
    final updated = _dt(m['updated_at']);
    final local = await (db.select(db.expenses)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && !local.updatedAt.isBefore(updated)) return;
    await db.into(db.expenses).insertOnConflictUpdate(ExpensesCompanion(
          id: Value(id),
          shopId: Value(m['shop_id'] as String),
          category: Value(m['category'] as String),
          amount: Value(_int(m['amount'])),
          date: Value(_dt(m['date'])),
          note: Value(m['note'] as String?),
          createdAt: Value(_dt(m['created_at'])),
          updatedAt: Value(updated),
          isDeleted: Value(_bool(m['is_deleted'])),
          dirty: const Value(false),
        ));
  },
);

// --- cash_sessions -----------------------------------------------------
final _cashSessions = SyncTableDef(
  name: 'cash_sessions',
  toRemote: (db, id) async {
    final r = await (db.select(db.cashSessions)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    return {
      'id': r.id,
      'shop_id': r.shopId,
      'opened_at': _iso(r.openedAt),
      'opening_amount': r.openingAmount,
      'closed_at': r.closedAt == null ? null : _iso(r.closedAt!),
      'closing_amount': r.closingAmount,
      'note': r.note,
      'device_id': r.deviceId,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'is_deleted': r.isDeleted,
    };
  },
  upsertLocal: (db, m) async {
    final id = m['id'] as String;
    final updated = _dt(m['updated_at']);
    final local = await (db.select(db.cashSessions)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && !local.updatedAt.isBefore(updated)) return;
    await db.into(db.cashSessions).insertOnConflictUpdate(CashSessionsCompanion(
          id: Value(id),
          shopId: Value(m['shop_id'] as String),
          openedAt: Value(_dt(m['opened_at'])),
          openingAmount: Value(_int(m['opening_amount'])),
          closedAt: Value(
              m['closed_at'] == null ? null : _dt(m['closed_at'])),
          closingAmount: Value(
              m['closing_amount'] == null ? null : _int(m['closing_amount'])),
          note: Value(m['note'] as String?),
          deviceId: Value(m['device_id'] as String?),
          createdAt: Value(_dt(m['created_at'])),
          updatedAt: Value(updated),
          isDeleted: Value(_bool(m['is_deleted'])),
          dirty: const Value(false),
        ));
  },
);

// --- device_labels -----------------------------------------------------
final _deviceLabels = SyncTableDef(
  name: 'device_labels',
  toRemote: (db, id) async {
    final r = await (db.select(db.deviceLabels)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    return {
      'id': r.id,
      'shop_id': r.shopId,
      'device_id': r.deviceId,
      'label': r.label,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'is_deleted': r.isDeleted,
    };
  },
  upsertLocal: (db, m) async {
    final id = m['id'] as String;
    final updated = _dt(m['updated_at']);
    final local = await (db.select(db.deviceLabels)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && !local.updatedAt.isBefore(updated)) return;
    await db.into(db.deviceLabels).insertOnConflictUpdate(DeviceLabelsCompanion(
          id: Value(id),
          shopId: Value(m['shop_id'] as String),
          deviceId: Value(m['device_id'] as String),
          label: Value(m['label'] as String),
          createdAt: Value(_dt(m['created_at'])),
          updatedAt: Value(updated),
          isDeleted: Value(_bool(m['is_deleted'])),
          dirty: const Value(false),
        ));
  },
);

// --- recurring_expenses ------------------------------------------------------
final _recurringExpenses = SyncTableDef(
  name: 'recurring_expenses',
  toRemote: (db, id) async {
    final r = await (db.select(db.recurringExpenses)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    return {
      'id': r.id,
      'shop_id': r.shopId,
      'category': r.category,
      'amount': r.amount,
      'note': r.note,
      'active': r.active,
      'auto_generate': r.autoGenerate,
      'generation_timing': r.generationTiming,
      'last_generated_period': r.lastGeneratedPeriod,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'is_deleted': r.isDeleted,
    };
  },
  upsertLocal: (db, m) async {
    final id = m['id'] as String;
    final updated = _dt(m['updated_at']);
    final local = await (db.select(db.recurringExpenses)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && !local.updatedAt.isBefore(updated)) return;
    await db.into(db.recurringExpenses).insertOnConflictUpdate(
          RecurringExpensesCompanion(
            id: Value(id),
            shopId: Value(m['shop_id'] as String),
            category: Value(m['category'] as String),
            amount: Value(_int(m['amount'])),
            note: Value(m['note'] as String?),
            active: Value(_bool(m['active'])),
            autoGenerate: Value(_bool(m['auto_generate'])),
            generationTiming:
                Value(m['generation_timing'] as String? ?? 'month_start'),
            lastGeneratedPeriod: Value(m['last_generated_period'] as String?),
            createdAt: Value(_dt(m['created_at'])),
            updatedAt: Value(updated),
            isDeleted: Value(_bool(m['is_deleted'])),
            dirty: const Value(false),
          ),
        );
  },
);

// --- suppliers ----------------------------------------------------------
final _suppliers = SyncTableDef(
  name: 'suppliers',
  toRemote: (db, id) async {
    final r = await (db.select(db.suppliers)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    return {
      'id': r.id,
      'shop_id': r.shopId,
      'name': r.name,
      'phone': r.phone,
      'address': r.address,
      'note': r.note,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'is_deleted': r.isDeleted,
    };
  },
  upsertLocal: (db, m) async {
    final id = m['id'] as String;
    final updated = _dt(m['updated_at']);
    final local = await (db.select(db.suppliers)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && !local.updatedAt.isBefore(updated)) return;
    await db.into(db.suppliers).insertOnConflictUpdate(SuppliersCompanion(
          id: Value(id),
          shopId: Value(m['shop_id'] as String),
          name: Value(m['name'] as String),
          phone: Value(m['phone'] as String?),
          address: Value(m['address'] as String?),
          note: Value(m['note'] as String?),
          createdAt: Value(_dt(m['created_at'])),
          updatedAt: Value(updated),
          isDeleted: Value(_bool(m['is_deleted'])),
          dirty: const Value(false),
        ));
  },
);

// --- purchase_orders ------------------------------------------------------
final _purchaseOrders = SyncTableDef(
  name: 'purchase_orders',
  toRemote: (db, id) async {
    final r = await (db.select(db.purchaseOrders)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    return {
      'id': r.id,
      'shop_id': r.shopId,
      'po_no': r.poNo,
      'supplier_id': r.supplierId,
      'supplier_name': r.supplierName,
      'status': r.status,
      'items_total': r.itemsTotal,
      'note': r.note,
      'received_at': r.receivedAt == null ? null : _iso(r.receivedAt!),
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'is_deleted': r.isDeleted,
    };
  },
  upsertLocal: (db, m) async {
    final id = m['id'] as String;
    final updated = _dt(m['updated_at']);
    final local = await (db.select(db.purchaseOrders)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && !local.updatedAt.isBefore(updated)) return;
    await db.into(db.purchaseOrders).insertOnConflictUpdate(
          PurchaseOrdersCompanion(
            id: Value(id),
            shopId: Value(m['shop_id'] as String),
            poNo: Value(m['po_no'] as String),
            supplierId: Value(m['supplier_id'] as String?),
            supplierName: Value(m['supplier_name'] as String),
            status: Value((m['status'] as String?) ?? 'open'),
            itemsTotal: Value(_int(m['items_total'])),
            note: Value(m['note'] as String?),
            receivedAt: Value(
                m['received_at'] == null ? null : _dt(m['received_at'])),
            createdAt: Value(_dt(m['created_at'])),
            updatedAt: Value(updated),
            isDeleted: Value(_bool(m['is_deleted'])),
            dirty: const Value(false),
          ),
        );
  },
);

// --- purchase_order_items --------------------------------------------------
final _purchaseOrderItems = SyncTableDef(
  name: 'purchase_order_items',
  toRemote: (db, id) async {
    final r = await (db.select(db.purchaseOrderItems)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (r == null) return null;
    return {
      'id': r.id,
      'shop_id': r.shopId,
      'po_id': r.poId,
      'product_id': r.productId,
      'name_snapshot': r.nameSnapshot,
      'qty': r.qty,
      'unit_cost': r.unitCost,
      'line_total': r.lineTotal,
      'created_at': _iso(r.createdAt),
      'updated_at': _iso(r.updatedAt),
      'is_deleted': r.isDeleted,
    };
  },
  upsertLocal: (db, m) async {
    final id = m['id'] as String;
    final updated = _dt(m['updated_at']);
    final local = await (db.select(db.purchaseOrderItems)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (local != null && !local.updatedAt.isBefore(updated)) return;
    await db.into(db.purchaseOrderItems).insertOnConflictUpdate(
          PurchaseOrderItemsCompanion(
            id: Value(id),
            shopId: Value(m['shop_id'] as String),
            poId: Value(m['po_id'] as String),
            productId: Value(m['product_id'] as String),
            nameSnapshot: Value(m['name_snapshot'] as String),
            qty: Value(_int(m['qty'])),
            unitCost: Value(_int(m['unit_cost'])),
            lineTotal: Value(_int(m['line_total'])),
            createdAt: Value(_dt(m['created_at'])),
            updatedAt: Value(updated),
            isDeleted: Value(_bool(m['is_deleted'])),
            dirty: const Value(false),
          ),
        );
  },
);
