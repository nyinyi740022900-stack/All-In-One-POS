import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/inventory_repository.dart';
import 'package:mm_pos/data/repositories/sales_repository.dart';
import 'package:mm_pos/features/backup/backup_service.dart';
import 'package:mm_pos/features/expenses/expense_repository.dart';
import 'package:mm_pos/features/sell/cart.dart';

void main() {
  late AppDatabase db;
  late BackupService backup;
  late InventoryRepository inventory;
  late SalesRepository sales;
  late ExpenseRepository expenses;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    backup = BackupService(db);
    inventory = InventoryRepository(db, 'shop-1');
    sales = SalesRepository(db, 'shop-1');
    expenses = ExpenseRepository(db, 'shop-1');
  });

  tearDown(() async => db.close());

  test('export → mutate → import restores the exact snapshot', () async {
    // Seed one product and a sale.
    final id = await inventory.upsertProduct(
        name: 'Coke', salePrice: 700, quantity: 10);
    final product = (await inventory.watchProducts().first)
        .firstWhere((p) => p.product.id == id)
        .product;
    await sales.finalizeSale(
      cart: CartState(lines: [CartLine(product: product, qty: 2)]),
      paymentMethod: 'cash',
      paid: 1400,
    );

    final snapshot = await backup.exportJson();
    expect(snapshot, contains('Coke'));
    expect(snapshot, contains('"app": "mm_pos"'));

    // Mutate after the backup: add a second product.
    await inventory.upsertProduct(
        name: 'Ghost', salePrice: 1, quantity: 1);
    expect(await db.select(db.products).get(), hasLength(2));

    // Restore replaces everything with the snapshot.
    final written = await backup.importReplaceAll(snapshot);
    expect(written, greaterThan(0));

    final products = await db.select(db.products).get();
    expect(products, hasLength(1));
    expect(products.single.name, 'Coke');
    // The sale + its item came back too.
    expect(await db.select(db.sales).get(), hasLength(1));
    expect(await db.select(db.saleItems).get(), hasLength(1));
  });

  test('expenses round-trip through export/import', () async {
    await expenses.upsertExpense(
      category: 'rent',
      amount: 150000,
      date: DateTime(2026, 7, 1),
      note: 'July rent',
    );
    final snapshot = await backup.exportJson();

    await db.delete(db.expenses).go();
    expect(await db.select(db.expenses).get(), isEmpty);

    await backup.importReplaceAll(snapshot);
    final restored = await db.select(db.expenses).get();
    expect(restored, hasLength(1));
    expect(restored.single.category, 'rent');
    expect(restored.single.amount, 150000);
  });

  test('device-local tables are not touched by import', () async {
    // A license/device row lives in app_settings; import must not wipe it.
    await db.into(db.appSettings).insert(
        AppSettingsCompanion.insert(key: 'device.id', value: 'dev-123'));
    final snapshot = await backup.exportJson();

    await backup.importReplaceAll(snapshot);

    final row = await (db.select(db.appSettings)
          ..where((s) => s.key.equals('device.id')))
        .getSingleOrNull();
    expect(row?.value, 'dev-123');
  });

  test('rejects a non-MM-POS file', () async {
    expect(
      () => backup.importReplaceAll('{"app":"something-else"}'),
      throwsFormatException,
    );
  });
}
