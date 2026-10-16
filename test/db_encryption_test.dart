import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/local/db_encryption.dart';
import 'package:mm_pos/data/local/shop_db_migrator.dart';
import 'package:path/path.dart' as p;

/// In-memory stand-in for the platform keystore.
class _MemKeyStore extends DbKeyStore {
  _MemKeyStore({this.readThrows = false});
  String? value;
  bool readThrows;
  int creates = 0;
  bool cleared = false;

  @override
  Future<String?> read() async {
    if (readThrows) throw const FormatException('keystore unavailable');
    return value;
  }

  @override
  Future<String> create() async {
    creates++;
    value = List.filled(32, 'ab').join();
    return value!;
  }

  @override
  Future<void> clearUnreadable() async {
    cleared = true;
    value = null;
    readThrows = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    DbEncryption.resetForTest();
    tmp = await Directory.systemTemp.createTemp('mm_pos_db_enc_');
    // AppDatabase.forFile asks path_provider for sqlite3's temp dir.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tmp.path,
        );
  });

  tearDown(() async {
    DbEncryption.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  File fileFor(String name) => File(p.join(tmp.path, name));
  String shopFile(String shopId) =>
      AppDatabase.fileNameForShop(shopId); // mm_pos_<id>.sqlite

  /// A plaintext Drift file with [sales] rows, as every build before
  /// encryption left on disk.
  Future<void> seedPlain(String name, {int sales = 3}) async {
    final db = AppDatabase.forTesting(NativeDatabase(fileFor(name)));
    await db.customSelect('SELECT 1').get(); // creates the schema
    for (var i = 0; i < sales; i++) {
      await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              id: '$name-$i',
              shopId: 's',
              invoiceNo: 'INV-$i',
              total: Value(1000 + i),
            ),
          );
    }
    await db.close();
  }

  /// Opens [name] the way production does (forFile → setupFor) and counts.
  Future<int> salesIn(String name) async {
    final db = AppDatabase.forFile(fileFor(name));
    try {
      return (await db.select(db.sales).get()).length;
    } finally {
      await db.close();
    }
  }

  DbFileState stateOf(String name) => DbFileStateX.of(fileFor(name));

  test('encrypts every plaintext shop, device and legacy file in place, '
      'keeping every row', () async {
    await seedPlain(shopFile('shop-a'), sales: 3);
    await seedPlain(shopFile('shop-b'), sales: 5);
    await seedPlain(AppDatabase.kDeviceDbFileName, sales: 0);
    await seedPlain('${AppDatabase.kLegacyDbFileName}.bak', sales: 2);
    final store = _MemKeyStore();

    final result = await DbEncryption.prepare(
      tmp.path,
      store: store,
      enabled: true,
    );

    expect(result.migrated, 4);
    expect(result.failed, isEmpty);
    expect(store.creates, 1, reason: 'one key for the whole device');
    for (final name in [
      shopFile('shop-a'),
      shopFile('shop-b'),
      AppDatabase.kDeviceDbFileName,
      '${AppDatabase.kLegacyDbFileName}.bak',
    ]) {
      expect(stateOf(name), DbFileState.encrypted, reason: name);
    }
    expect(await salesIn(shopFile('shop-a')), 3);
    expect(await salesIn(shopFile('shop-b')), 5);
    expect(
      tmp.listSync().where((f) => f.path.endsWith('.pre-encrypt')),
      isEmpty,
      reason: 'safety copies are removed once verified',
    );
  });

  test('a shop opened after prepare (branch switch) is created encrypted, '
      'and a second launch re-uses the key without re-encrypting', () async {
    final store = _MemKeyStore();
    await DbEncryption.prepare(tmp.path, store: store, enabled: true);
    final db = AppDatabase.forFile(fileFor(shopFile('new-branch')));
    await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(id: 'x', shopId: 's', invoiceNo: 'INV-1'),
        );
    await db.close();
    expect(stateOf(shopFile('new-branch')), DbFileState.encrypted);

    DbEncryption.resetForTest();
    final again = await DbEncryption.prepare(
      tmp.path,
      store: store,
      enabled: true,
    );
    expect(again.migrated, 0);
    expect(store.creates, 1);
    expect(await salesIn(shopFile('new-branch')), 1);
  });

  test('encrypted files with no key throw — and are left byte-for-byte '
      'untouched, never recreated empty', () async {
    await seedPlain(shopFile('shop-a'));
    await DbEncryption.prepare(tmp.path, store: _MemKeyStore(), enabled: true);
    final before = fileFor(shopFile('shop-a')).readAsBytesSync();

    DbEncryption.resetForTest();
    await expectLater(
      DbEncryption.prepare(tmp.path, store: _MemKeyStore(), enabled: true),
      throwsA(
        isA<DbKeyUnavailableException>().having(
          (e) => e.reason,
          'reason',
          DbLockReason.keyMissing,
        ),
      ),
    );
    expect(fileFor(shopFile('shop-a')).readAsBytesSync(), before);
    // Opening it anyway (a stray forFile) refuses rather than creating rows.
    expect(
      () => DbEncryption.setupFor(fileFor(shopFile('shop-a'))),
      throwsA(isA<DbKeyUnavailableException>()),
    );
  });

  test(
    'an unreadable keystore locks only when encrypted files exist',
    () async {
      await seedPlain(shopFile('shop-a'));
      final flaky = _MemKeyStore(readThrows: true);
      final plain = await DbEncryption.prepare(
        tmp.path,
        store: flaky,
        enabled: true,
      );
      expect(plain.skippedNoKey, isTrue);
      expect(stateOf(shopFile('shop-a')), DbFileState.plaintext);
      expect(await salesIn(shopFile('shop-a')), 3, reason: 'still usable');

      final store = _MemKeyStore();
      DbEncryption.resetForTest();
      await DbEncryption.prepare(tmp.path, store: store, enabled: true);
      DbEncryption.resetForTest();
      store.readThrows = true;
      await expectLater(
        DbEncryption.prepare(tmp.path, store: store, enabled: true),
        throwsA(
          isA<DbKeyUnavailableException>().having(
            (e) => e.reason,
            'reason',
            DbLockReason.keyUnreadable,
          ),
        ),
      );
    },
  );

  test('wrong key fails to open and changes nothing', () async {
    await seedPlain(shopFile('shop-a'));
    await DbEncryption.prepare(tmp.path, store: _MemKeyStore(), enabled: true);
    final before = fileFor(shopFile('shop-a')).readAsBytesSync();
    final wrong = List.filled(32, 'cd').join();
    final db = AppDatabase.forTesting(
      NativeDatabase(
        fileFor(shopFile('shop-a')),
        setup: (raw) => DbEncryption.applyKey(raw, wrong),
      ),
    );
    await expectLater(db.select(db.sales).get(), throwsA(anything));
    await db.close();
    expect(fileFor(shopFile('shop-a')).readAsBytesSync(), before);
  });

  test('a crash mid-migration is rolled back from the safety copy, then '
      'migrated again', () async {
    await seedPlain(shopFile('shop-a'), sales: 4);
    final good = fileFor(shopFile('shop-a'));
    // Crash state: safety copy written, the file itself half-rewritten.
    good.copySync('${good.path}.pre-encrypt');
    good.writeAsBytesSync(List.filled(4096, 7));

    final result = await DbEncryption.prepare(
      tmp.path,
      store: _MemKeyStore(),
      enabled: true,
    );
    expect(result.restored, 1);
    expect(result.migrated, 1);
    expect(stateOf(shopFile('shop-a')), DbFileState.encrypted);
    expect(await salesIn(shopFile('shop-a')), 4);
    expect(File('${good.path}.pre-encrypt').existsSync(), isFalse);
  });

  test('a damaged plaintext file is not encrypted: left as it was, reported, '
      'others still migrate', () async {
    await seedPlain(shopFile('shop-a'));
    final damaged = fileFor(shopFile('shop-bad'));
    // Valid header, garbage pages: quick_check / open fails.
    damaged.writeAsBytesSync([
      ...'SQLite format 3\u0000'.codeUnits,
      ...List.filled(8192, 0x5a),
    ]);
    final before = damaged.readAsBytesSync();

    final result = await DbEncryption.prepare(
      tmp.path,
      store: _MemKeyStore(),
      enabled: true,
    );
    expect(result.failed, [shopFile('shop-bad')]);
    expect(result.migrated, 1);
    expect(damaged.readAsBytesSync(), before);
    expect(File('${damaged.path}.pre-encrypt').existsSync(), isFalse);
  });

  test('kill switch off: plaintext stays plaintext and no key is made, but '
      'an already-encrypted file still opens', () async {
    final store = _MemKeyStore();
    await seedPlain(shopFile('enc'));
    await DbEncryption.prepare(tmp.path, store: store, enabled: true);
    await seedPlain(shopFile('plain'));

    DbEncryption.resetForTest();
    final off = await DbEncryption.prepare(
      tmp.path,
      store: store,
      enabled: false,
    );
    expect(off.migrated, 0);
    expect(stateOf(shopFile('plain')), DbFileState.plaintext);
    expect(await salesIn(shopFile('enc')), 3);
    expect(await salesIn(shopFile('plain')), 3);

    final fresh = _MemKeyStore();
    DbEncryption.resetForTest();
    await DbEncryption.prepare(
      Directory.systemTemp.createTempSync('mm_pos_db_off_').path,
      store: fresh,
      enabled: false,
    );
    expect(fresh.creates, 0);
  });

  test(
    'legacy → per-shop copy keeps working on an encrypted legacy file',
    () async {
      await seedPlain(AppDatabase.kLegacyDbFileName, sales: 2);
      await DbEncryption.prepare(
        tmp.path,
        store: _MemKeyStore(),
        enabled: true,
      );
      expect(stateOf(AppDatabase.kLegacyDbFileName), DbFileState.encrypted);

      await materializeShopFileFromLegacy(
        documentsDir: tmp.path,
        shopId: 'shop-x',
      );
      expect(stateOf(shopFile('shop-x')), DbFileState.encrypted);
      expect(await salesIn(shopFile('shop-x')), 2);
    },
  );

  test('start with an empty shop moves locked files aside, deletes none, '
      'and the next launch starts clean with a new key', () async {
    await seedPlain(shopFile('shop-a'));
    await DbEncryption.prepare(tmp.path, store: _MemKeyStore(), enabled: true);
    DbEncryption.resetForTest();
    final lost = _MemKeyStore(readThrows: true);

    final aside = await DbEncryption.setAsideLockedFiles(tmp.path, store: lost);
    expect(lost.cleared, isTrue);
    expect(
      File(p.join(aside, shopFile('shop-a'))).existsSync(),
      isTrue,
      reason: 'moved, not deleted',
    );
    expect(fileFor(shopFile('shop-a')).existsSync(), isFalse);

    final result = await DbEncryption.prepare(
      tmp.path,
      store: lost,
      enabled: true,
    );
    expect(result.skippedNoKey, isFalse);
    expect(lost.creates, 1);
  });

  test('only this app\'s database files are touched', () {
    expect(DbEncryption.isDatabaseFileName('mm_pos.sqlite'), isTrue);
    expect(DbEncryption.isDatabaseFileName('mm_pos_device.sqlite'), isTrue);
    expect(DbEncryption.isDatabaseFileName('mm_pos_shop-1.sqlite'), isTrue);
    expect(DbEncryption.isDatabaseFileName('mm_pos.sqlite.bak'), isTrue);
    expect(DbEncryption.isDatabaseFileName('mm_pos.sqlite-journal'), isFalse);
    expect(DbEncryption.isDatabaseFileName('libCachedImageData.db'), isFalse);
    expect(DbEncryption.isDatabaseFileName('license.json'), isFalse);
  });
}
