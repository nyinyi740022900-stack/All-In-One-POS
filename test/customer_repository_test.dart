import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/customers/customer_repository.dart';

void main() {
  late AppDatabase db;
  late CustomerRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = CustomerRepository(db, 'shop-1');
  });

  tearDown(() async => db.close());

  test('upsertCustomer persists and enqueues outbox', () async {
    final id = await repo.upsertCustomer(name: 'Daw Mya', phone: '09123');
    final c = await repo.getCustomer(id);
    expect(c!.name, 'Daw Mya');
    expect(c.phone, '09123');
    expect(c.tier, 'retail'); // default when not specified

    final outbox = await db.select(db.outbox).get();
    expect(outbox.any((o) => o.entityTable == 'customers'), isTrue);
  });

  test('upsertCustomer persists a wholesale/vip tier', () async {
    final id = await repo.upsertCustomer(name: 'Big Shop', tier: 'wholesale');
    final c = await repo.getCustomer(id);
    expect(c!.tier, 'wholesale');
  });

  test('watchCustomers excludes deleted rows', () async {
    final id = await repo.upsertCustomer(name: 'Ko Ko');
    expect(await repo.watchCustomers().first, hasLength(1));
    await repo.deleteCustomer(id);
    expect(await repo.watchCustomers().first, isEmpty);
  });

  group('resolveOrCreate', () {
    test('creates a new customer the first time a name is seen', () async {
      final id = await repo.resolveOrCreate('Su Su', phone: '09999');
      final c = await repo.getCustomer(id);
      expect(c!.name, 'Su Su');
      expect(c.phone, '09999');
    });

    test('reuses the existing customer on an exact (case-insensitive) '
        'name match', () async {
      final first = await repo.resolveOrCreate('Aung Aung');
      final second = await repo.resolveOrCreate('aung aung');
      expect(second, first);
      expect(await repo.watchCustomers().first, hasLength(1));
    });

    test('backfills a phone number onto an existing customer that had none',
        () async {
      final id = await repo.resolveOrCreate('Mi Mi');
      await repo.resolveOrCreate('Mi Mi', phone: '09111');
      final c = await repo.getCustomer(id);
      expect(c!.phone, '09111');
    });

    test('never overwrites a phone number already on file', () async {
      final id = await repo.resolveOrCreate('Nan Nan', phone: '09222');
      await repo.resolveOrCreate('Nan Nan', phone: '09333');
      final c = await repo.getCustomer(id);
      expect(c!.phone, '09222'); // unchanged
    });

    test('backfills an address onto an existing customer that had none',
        () async {
      final id = await repo.resolveOrCreate('Thida');
      await repo.resolveOrCreate('Thida', address: '123 Pyay Road');
      final c = await repo.getCustomer(id);
      expect(c!.address, '123 Pyay Road');
    });

    test('never overwrites an address already on file', () async {
      final id =
          await repo.resolveOrCreate('Kyaw Kyaw', address: 'Yangon');
      await repo.resolveOrCreate('Kyaw Kyaw', address: 'Mandalay');
      final c = await repo.getCustomer(id);
      expect(c!.address, 'Yangon'); // unchanged
    });
    test('a duplicated name resolves instead of throwing (blocked sales)',
        () async {
      // Two devices creating "Ma Aye" offline both sync in, and the
      // directory has no uniqueness check — so duplicates are normal, not
      // exotic. `getSingleOrNull` THREW on them, and because a credit sale
      // forces directory linkage, every checkout for that customer failed
      // permanently behind a generic error with nothing pointing at the
      // cause. Resolving to the oldest match keeps the sale possible;
      // merging duplicates is a directory chore, not a checkout blocker.
      final first = await repo.resolveOrCreate('Ma Aye');
      await repo.upsertCustomer(id: 'dupe-2', name: 'Ma Aye');

      final resolved = await repo.resolveOrCreate('Ma Aye');
      expect(resolved, first,
          reason: 'should settle on the oldest row, not throw or fork.');
    });

    test('a duplicate differing only by case also resolves', () async {
      final first = await repo.resolveOrCreate('Su Su');
      await repo.upsertCustomer(id: 'dupe-case', name: 'SU SU');
      final resolved = await repo.resolveOrCreate('su su');
      expect(resolved, first);
    });
  });
}