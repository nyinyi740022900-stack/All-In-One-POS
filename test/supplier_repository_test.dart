import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/suppliers/supplier_repository.dart';

void main() {
  late AppDatabase db;
  late SupplierRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = SupplierRepository(db, 'shop-1');
  });

  tearDown(() async => db.close());

  test('upsertSupplier creates a row and enqueues outbox', () async {
    final id = await repo.upsertSupplier(name: 'Acme Distribution');
    final rows = await repo.watchSuppliers().first;
    expect(rows, hasLength(1));
    expect(rows.single.id, id);
    expect(rows.single.name, 'Acme Distribution');

    final outbox = await db.select(db.outbox).get();
    expect(outbox.any((o) => o.entityTable == 'suppliers'), isTrue);
  });

  test('upsertSupplier with an existing id renames in place (one row)',
      () async {
    final id = await repo.upsertSupplier(name: 'Acme');
    await repo.upsertSupplier(id: id, name: 'Acme Distribution Co.');

    final rows = await repo.watchSuppliers().first;
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Acme Distribution Co.');
  });

  test('deleteSupplier soft-deletes, excluded from watchSuppliers', () async {
    final id = await repo.upsertSupplier(name: 'Acme');
    await repo.deleteSupplier(id);

    expect(await repo.watchSuppliers().first, isEmpty);
    final raw =
        await (db.select(db.suppliers)..where((t) => t.id.equals(id)))
            .getSingle();
    expect(raw.isDeleted, isTrue);
  });

  test('watchSuppliers excludes other shops', () async {
    await repo.upsertSupplier(name: 'Acme');
    final otherShop = SupplierRepository(db, 'shop-2');
    await otherShop.upsertSupplier(name: 'Other Co');

    final rows = await repo.watchSuppliers().first;
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Acme');
  });
}
