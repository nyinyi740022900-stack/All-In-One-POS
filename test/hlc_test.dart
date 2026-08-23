import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/sync/hlc.dart';
import 'package:mm_pos/data/sync/sync_mappers.dart';

void main() {
  group('pure HLC ordering', () {
    test('tuple compare: wall, then counter, then device', () {
      expect(compareHlc('100:0:a', '100:0:a'), 0);
      expect(compareHlc('100:0:a', '99:999:b'), greaterThan(0));
      expect(compareHlc('100:1:a', '100:0:z'), greaterThan(0));
      expect(compareHlc('100:0:b', '100:0:a'), greaterThan(0),
          reason: 'device id breaks wall+counter ties deterministically');
      expect(compareHlc(null, '100:0:a'), lessThan(0),
          reason: 'legacy rows without an HLC sort lowest');
      expect(compareHlc('garbage', '100:0:a'), lessThan(0));
    });

    test('synth is deterministic for the same inputs', () {
      final t = DateTime.utc(2026, 8, 22, 10, 0, 0);
      expect(synthHlc(t, 'row-1'), synthHlc(t, 'row-1'));
      expect(synthHlc(t, 'row-1'), isNot(synthHlc(t, 'row-2')));
      // Server-stamp derived: always parses back as a valid tuple.
      expect(tryParseHlc(synthHlc(t, 'row-1')), isNotNull);
    });
  });

  group('clock state (DB-backed)', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async => db.close());

    test('mint is strictly monotonic within one device', () async {
      final a = await mintHlc(db, 'device-a',
          now: DateTime.fromMillisecondsSinceEpoch(1000));
      final b = await mintHlc(db, 'device-a',
          now: DateTime.fromMillisecondsSinceEpoch(2000));
      final c = await mintHlc(db, 'device-a',
          now: DateTime.fromMillisecondsSinceEpoch(2000));
      expect(compareHlc(a, b), lessThan(0));
      expect(compareHlc(b, c), lessThan(0),
          reason: 'same-ms mints advance the counter');
    });

    test('a wall clock that jumps BACKWARDS never regresses the clock',
        () async {
      await mintHlc(db, 'device-a',
          now: DateTime.fromMillisecondsSinceEpoch(5000));
      final afterSkew = await mintHlc(db, 'device-a',
          now: DateTime.fromMillisecondsSinceEpoch(1000));
      expect(tryParseHlc(afterSkew)!.wall, greaterThanOrEqualTo(5000),
          reason: 'the classic skew failure of raw updated_at LWW');
    });

    test('receive advances future mints past everything observed', () async {
      final before = await mintHlc(db, 'device-a',
          now: DateTime.fromMillisecondsSinceEpoch(1000));
      // A far-future foreign stamp lands (another device pushed later).
      await receiveHlc(db, '9999999999999:7:device-b');
      final after = await mintHlc(db, 'device-a',
          now: DateTime.fromMillisecondsSinceEpoch(1000));
      expect(compareHlc(before, after), lessThan(0));
      expect(compareHlc('9999999999999:7:device-b', after), lessThan(0),
          reason: 'next local edit must outrank the received row');
    });

    test('receive ignores malformed stamps', () async {
      await receiveHlc(db, null);
      await receiveHlc(db, 'not-an-hlc');
      final h = await mintHlc(db, 'device-a',
          now: DateTime.fromMillisecondsSinceEpoch(1000));
      expect(tryParseHlc(h), isNotNull);
    });
  });

  group('integration with a real synced table', () {
    late AppDatabase db;
    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });
    tearDown(() async => db.close());
    test('a pushed row carries its minted hlc; a higher-hlc pull wins over '
        'an equal-updated_at local copy regardless of device clocks',
        () async {
      final t =
          DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true);
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: 'p-hlc',
            shopId: 'shop-1',
            name: 'Local Version',
            salePrice: const Value(1),
            createdAt: Value(t),
            updatedAt: Value(t),
            dirty: const Value(false), // already cloud-reflected
          ));

      // Remote row: SAME updated_at second, but carries a higher HLC
      // (its device pushed physically later). Old updated_at LWW called
      // this a tie and split-brained; HLC arbitrates deterministically.
      final remote = {
        'id': 'p-hlc',
        'shop_id': 'shop-1',
        'name': 'Remote Winner',
        'sku': null,
        'barcode': null,
        'category_id': null,
        'cost_price': 0,
        'sale_price': 1,
        'wholesale_price': null,
        'vip_price': null,
        'online_stock_limit': null,
        'unit': 'pcs',
        'image_path': null,
        'image_url': null,
        'is_active': true,
        'created_at': t.toIso8601String(),
        'updated_at': t.toIso8601String(),
        'received_at': t.add(const Duration(seconds: 5)).toIso8601String(),
        'hlc': '1700000005000:0:device-b',
        'is_deleted': false,
      };
      final def = syncTables.firstWhere((d) => d.name == 'products');
      final applied = await def.upsertLocal(db, remote);
      expect(applied, isTrue);

      final row = await (db.select(db.products)
            ..where((t2) => t2.id.equals('p-hlc')))
          .getSingle();
      expect(row.name, 'Remote Winner');
      expect(row.hlc, '1700000005000:0:device-b');

      // And the clock advanced past it for this device's next edits.
      final minted = await mintHlc(db, 'device-a');
      expect(compareHlc(remote['hlc'] as String, minted), lessThan(0));
    });
  });
}
