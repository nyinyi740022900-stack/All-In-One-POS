import 'package:drift/drift.dart';

import '../local/database.dart';

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
          quantity: Value(_int(m['quantity'])),
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
    final local =
        await (db.select(db.stockMovements)..where((t) => t.id.equals(id)))
            .getSingleOrNull();
    if (local != null && !local.updatedAt.isBefore(updated)) return;
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
      'tax': r.tax,
      'total': r.total,
      'paid': r.paid,
      'change_due': r.changeDue,
      'payment_method': r.paymentMethod,
      'customer_name': r.customerName,
      'customer_phone': r.customerPhone,
      'customer_id': r.customerId,
      'note': r.note,
      'refund_of_sale_id': r.refundOfSaleId,
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
          tax: Value(_int(m['tax'])),
          total: Value(_int(m['total'])),
          paid: Value(_int(m['paid'])),
          changeDue: Value(_int(m['change_due'])),
          paymentMethod: Value((m['payment_method'] as String?) ?? 'cash'),
          customerName: Value(m['customer_name'] as String?),
          customerPhone: Value(m['customer_phone'] as String?),
          customerId: Value(m['customer_id'] as String?),
          note: Value(m['note'] as String?),
          refundOfSaleId: Value(m['refund_of_sale_id'] as String?),
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
