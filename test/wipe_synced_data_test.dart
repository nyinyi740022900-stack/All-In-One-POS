import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/inventory_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  test('wipeSyncedData clears shop-scoped tables and sync cursors, keeps '
      'other local settings', () async {
    final inventory = InventoryRepository(db, 'shop-1');
    await inventory.upsertProduct(name: 'Coke', salePrice: 700, quantity: 10);
    expect(await db.select(db.products).get(), isNotEmpty);
    expect(await db.select(db.stockLevels).get(), isNotEmpty);

    await db.into(db.appSettings).insert(
        const AppSettingsCompanion(
            key: Value('sync.cursor.products'), value: Value('2026-01-01')));
    await db.into(db.appSettings).insert(
        const AppSettingsCompanion(
            key: Value('printer.address'), value: Value('00:11:22')));

    await db.wipeSyncedData();

    expect(await db.select(db.products).get(), isEmpty);
    expect(await db.select(db.stockLevels).get(), isEmpty);

    final settings = await db.select(db.appSettings).get();
    expect(settings.map((s) => s.key), isNot(contains('sync.cursor.products')));
    expect(settings.map((s) => s.key), contains('printer.address'));
  });
}
