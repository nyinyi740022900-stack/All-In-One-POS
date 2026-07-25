import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/inventory_repository.dart';
import 'package:mm_pos/features/orders/orders_providers.dart';
import 'package:mm_pos/features/orders/orders_repository.dart';

void main() {
  late AppDatabase db;
  late InventoryRepository inventory;
  late OrdersRepository orders;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    inventory = InventoryRepository(db, 'shop-1');
    orders = OrdersRepository(db, 'shop-1');
  });

  tearDown(() async => db.close());

  Future<String> seedProduct(
      {required String name, required int price, required int qty}) {
    return inventory.upsertProduct(
        name: name, salePrice: price, quantity: qty);
  }

  test('saveOrder writes order + items, computes itemsTotal and ORD number',
      () async {
    final id = await orders.saveOrder(
      customerName: 'Ma Ma',
      channel: 'facebook',
      deliveryFee: 1000,
      lines: const [
        OrderDraftLine(name: 'Lipstick', price: 12000, qty: 2),
        OrderDraftLine(name: 'Powder', price: 8000, qty: 1),
      ],
    );

    final order = await orders.getOrder(id);
    expect(order.itemsTotal, 32000); // 24000 + 8000
    expect(order.deliveryFee, 1000);
    expect(order.status, 'new');
    expect(order.paymentStatus, 'unpaid');
    expect(order.orderNo, startsWith('ORD-'));
    expect(await orders.items(id), hasLength(2));
  });

  test('setStatus moves the order across the pipeline', () async {
    final id = await orders.saveOrder(
      customerName: 'Ko Ko',
      channel: 'viber',
      lines: const [OrderDraftLine(name: 'Shirt', price: 15000, qty: 1)],
    );
    await orders.setStatus(id, 'confirmed');
    expect((await orders.getOrder(id)).status, 'confirmed');
    await orders.setStatus(id, 'packed');
    expect((await orders.getOrder(id)).status, 'packed');
  });

  test('setPaymentStatus updates and enqueues the order for sync', () async {
    final id = await orders.saveOrder(
      customerName: 'Nan Nan',
      channel: 'facebook',
      lines: const [OrderDraftLine(name: 'Bag', price: 20000, qty: 1)],
    );
    expect((await orders.getOrder(id)).paymentStatus, 'unpaid');

    await orders.setPaymentStatus(id, 'paid');
    expect((await orders.getOrder(id)).paymentStatus, 'paid');

    // Reversible — staff can undo a mistaken "mark as paid".
    await orders.setPaymentStatus(id, 'unpaid');
    expect((await orders.getOrder(id)).paymentStatus, 'unpaid');

    final outbox = (await db.select(db.outbox).get())
        .where((o) => o.entityTable == 'orders' && o.rowId == id)
        .toList();
    expect(outbox.length, greaterThanOrEqualTo(3)); // save + 2 status updates
  });

  test('editing replaces the item set and recomputes the total', () async {
    final id = await orders.saveOrder(
      customerName: 'Su',
      channel: 'phone',
      lines: const [OrderDraftLine(name: 'A', price: 1000, qty: 1)],
    );
    await orders.saveOrder(
      id: id,
      customerName: 'Su',
      channel: 'phone',
      lines: const [
        OrderDraftLine(name: 'B', price: 2000, qty: 2),
        OrderDraftLine(name: 'C', price: 500, qty: 1),
      ],
    );
    final order = await orders.getOrder(id);
    expect(order.itemsTotal, 4500);
    // Only the 2 live items remain (old one tombstoned).
    expect(await orders.items(id), hasLength(2));
  });

  test('convertToSale creates a sale + items + payment and deducts stock',
      () async {
    final pid = await seedProduct(name: 'Bag', price: 20000, qty: 5);
    final id = await orders.saveOrder(
      customerName: 'Nilar',
      channel: 'facebook',
      deliveryFee: 2000,
      lines: [
        OrderDraftLine(productId: pid, name: 'Bag', price: 20000, qty: 2),
      ],
    );
    await orders.setStatus(id, 'delivered');

    final saleId = await orders.convertToSale(id, paymentMethod: 'kbzpay');

    // Sale total = items (40000) + delivery (2000).
    final sale =
        await (db.select(db.sales)..where((s) => s.id.equals(saleId)))
            .getSingle();
    expect(sale.total, 42000);
    expect(sale.paid, 42000);
    // Delivery folds into subtotal so subtotal - discount == total holds.
    expect(sale.subtotal, 42000);
    expect(sale.discount, 0);
    expect(sale.invoiceNo, startsWith('INV-'));

    // Order is linked + marked paid.
    final order = await orders.getOrder(id);
    expect(order.saleId, saleId);
    expect(order.paymentStatus, 'paid');

    // Stock decremented 5 -> 3 via a 'sale' movement.
    final stock = await (db.select(db.stockLevels)
          ..where((s) => s.productId.equals(pid)))
        .getSingle();
    expect(stock.quantity, 3);
    final saleMove = (await db.select(db.stockMovements).get())
        .firstWhere((m) => m.type == 'sale');
    expect(saleMove.qtyDelta, -2);
  });

  test('convertToSale is idempotent (returns the same sale id)', () async {
    final id = await orders.saveOrder(
      customerName: 'Aye',
      channel: 'facebook',
      lines: const [OrderDraftLine(name: 'Free-text', price: 3000, qty: 1)],
    );
    await orders.setStatus(id, 'delivered');
    final first = await orders.convertToSale(id);
    final second = await orders.convertToSale(id);
    expect(first, second);
    // Exactly one sale exists.
    expect(await db.select(db.sales).get(), hasLength(1));
  });

  test('free-text line (no productId) converts without touching stock',
      () async {
    final id = await orders.saveOrder(
      customerName: 'Thet',
      channel: 'other',
      lines: const [OrderDraftLine(name: 'Custom cake', price: 25000, qty: 1)],
    );
    await orders.setStatus(id, 'delivered');
    await orders.convertToSale(id);
    // No stock movement because the line has no productId.
    expect(await db.select(db.stockMovements).get(), isEmpty);
    expect(await db.select(db.sales).get(), hasLength(1));
  });

  test('deleteOrder tombstones the order and drops it from the stream',
      () async {
    final id = await orders.saveOrder(
      customerName: 'X',
      channel: 'facebook',
      lines: const [OrderDraftLine(name: 'Y', price: 100, qty: 1)],
    );
    await orders.deleteOrder(id);
    expect((await orders.getOrder(id)).isDeleted, isTrue);
    expect(await orders.watchOrders().first, isEmpty);
  });

  test('setDelivery records township/carrier/tracking/status and preserves '
      'fields not passed', () async {
    final id = await orders.saveOrder(
      customerName: 'Delivery Test',
      channel: 'facebook',
      lines: const [OrderDraftLine(name: 'Item', price: 500, qty: 1)],
    );
    await orders.setDelivery(
      id,
      township: 'Bahan',
      carrier: 'ninja_van',
      trackingNumber: 'NV12345',
      deliveryStatus: 'booked',
    );
    var order = await orders.getOrder(id);
    expect(order.township, 'Bahan');
    expect(order.deliveryCarrier, 'ninja_van');
    expect(order.trackingNumber, 'NV12345');
    expect(order.deliveryStatus, 'booked');

    // Updating only the status leaves the other delivery fields untouched.
    await orders.setDelivery(id, deliveryStatus: 'out_for_delivery');
    order = await orders.getOrder(id);
    expect(order.township, 'Bahan');
    expect(order.trackingNumber, 'NV12345');
    expect(order.deliveryStatus, 'out_for_delivery');
  });

  test('outbox queues order + order_items rows for sync', () async {
    final id = await orders.saveOrder(
      customerName: 'Z',
      channel: 'facebook',
      lines: const [OrderDraftLine(name: 'Item', price: 500, qty: 1)],
    );
    await orders.setStatus(id, 'confirmed');
    final tables =
        (await db.select(db.outbox).get()).map((o) => o.entityTable).toSet();
    expect(tables, containsAll(<String>{'orders', 'order_items'}));
  });

  group('groupOrdersForBoard filtering', () {
    Future<List<Order>> seedBoard() async {
      final a = await orders.saveOrder(
        customerName: 'Aung Aung',
        customerPhone: '0912345678',
        channel: 'facebook',
        lines: const [OrderDraftLine(name: 'X', price: 1000, qty: 1)],
      );
      final b = await orders.saveOrder(
        customerName: 'Su Su',
        channel: 'viber',
        lines: const [OrderDraftLine(name: 'Y', price: 1000, qty: 1)],
      );
      await orders.setStatus(a, 'confirmed');
      await orders.setStatus(b, 'packed');
      return orders.watchOrders().first;
    }

    test('buckets by status into pipeline columns + cancelled', () async {
      final all = await seedBoard();
      final g = groupOrdersForBoard(all);
      expect(g['confirmed'], hasLength(1));
      expect(g['packed'], hasLength(1));
      expect(g['new'], isEmpty);
      expect(g.containsKey('cancelled'), isTrue);
    });

    test('search matches name, phone, or order number', () async {
      final all = await seedBoard();
      // by name
      expect(_count(groupOrdersForBoard(all, query: 'aung')), 1);
      // by phone
      expect(_count(groupOrdersForBoard(all, query: '2345')), 1);
      // by order number prefix
      expect(_count(groupOrdersForBoard(all, query: 'ORD-')), 2);
      // no match
      expect(_count(groupOrdersForBoard(all, query: 'zzz')), 0);
    });

    test('channel filter narrows to one channel', () async {
      final all = await seedBoard();
      expect(_count(groupOrdersForBoard(all, channel: 'viber')), 1);
      expect(_count(groupOrdersForBoard(all, channel: 'facebook')), 1);
      expect(_count(groupOrdersForBoard(all, channel: 'tiktok')), 0);
    });

    test('payment filter narrows by payment status', () async {
      final all = await seedBoard();
      // both seeded orders are unpaid by default
      expect(_count(groupOrdersForBoard(all, payment: 'unpaid')), 2);
      expect(_count(groupOrdersForBoard(all, payment: 'paid')), 0);
    });
  });
}

int _count(Map<String, List<Order>> g) =>
    g.values.fold(0, (s, list) => s + list.length);
