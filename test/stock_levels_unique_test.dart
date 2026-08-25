import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  group('stock_levels (shop_id, product_id) uniqueness', () {
    test('a fresh database rejects a second row for the same product', () {
      // The sync layer can mint this row from a foreign movement delta
      // before the canonical row arrives; without the constraint that
      // phantom plus the canonical insert produced TWO rows for one
      // product, and every getSingleOrNull keyed on product then threw —
      // crashing checkout/restock on that device.
      expect(
        () => db.into(db.stockLevels).insert(StockLevelsCompanion.insert(
              id: 'row-a',
              shopId: 'shop-1',
              productId: 'prod-1',
            )),
        returnsNormally,
      );
      expect(
        () => db.into(db.stockLevels).insert(StockLevelsCompanion.insert(
              id: 'row-b',
              shopId: 'shop-1',
              productId: 'prod-1',
            )),
        throwsA(anything),
      );
    });

    test('the same product in a different shop is still allowed', () async {
      await db.into(db.stockLevels).insert(StockLevelsCompanion.insert(
            id: 'shop1-row',
            shopId: 'shop-1',
            productId: 'prod-1',
          ));
      await db.into(db.stockLevels).insert(StockLevelsCompanion.insert(
            id: 'shop2-row',
            shopId: 'shop-2',
            productId: 'prod-1',
            quantity: const Value(5),
          ));
      expect(await db.select(db.stockLevels).get(), hasLength(2));
    });
  });
}
