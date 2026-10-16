import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqlite3/sqlite3.dart';

/// At-rest encryption of the on-device Drift files (SQLite3MultipleCiphers,
/// selected in `pubspec.yaml` `hooks:`). Plan and risk notes:
/// `docs/db_encryption_plan.md`.
///
/// One random 256-bit key per device, kept in the platform keystore, opens
/// every file on the device (all shops + the device sidecar) — so a shop
/// switch, a shop-identity promotion (file rename) and the legacy→per-shop
/// copy all keep working without re-keying.
///
/// Whether a file is encrypted is read from its header, never from a
/// setting, so the answer can't disagree with the file itself.
///
/// The cardinal rule: a file that won't open is **never** deleted or
/// recreated here. Losing the key must surface as [DbKeyUnavailableException]
/// (a recovery screen), not as a silently empty shop.
class DbEncryption {
  DbEncryption._();

  /// Kill switch for *new* encryption (`--dart-define=DB_ENCRYPTION=false`).
  /// Off: plaintext files are left alone and new files are created plaintext;
  /// files that are already encrypted still open with the device key.
  static const bool enabledByBuild = bool.fromEnvironment(
    'DB_ENCRYPTION',
    defaultValue: true,
  );

  static String? _hexKey;

  /// The key loaded by [prepare]; null before it runs or when no key exists.
  @visibleForTesting
  static String? get loadedKey => _hexKey;

  @visibleForTesting
  static void resetForTest() => _hexKey = null;

  /// Drift `setup` callback for [file]: keys the connection when the file is
  /// already encrypted, or when it is about to be created and a key exists.
  /// Returns null for a plaintext file (opened exactly as before).
  ///
  /// The returned closure only captures a String, so it is safe to send to
  /// `NativeDatabase.createInBackground`'s isolate.
  static void Function(Database)? setupFor(File file, {bool? enabled}) {
    final key = _hexKey;
    final state = DbFileStateX.of(file);
    switch (state) {
      case DbFileState.encrypted:
        if (key == null) {
          throw DbKeyUnavailableException(
            DbLockReason.keyMissing,
            files: [p.basename(file.path)],
          );
        }
        return (db) => applyKey(db, key);
      case DbFileState.missing:
        if (key == null || !(enabled ?? enabledByBuild)) return null;
        return (db) => applyKey(db, key);
      case DbFileState.plaintext:
        return null;
    }
  }

  /// `PRAGMA key` for a hex key (hex only — no quoting hazard), then a read
  /// so a wrong key fails here, at open, instead of on some later query.
  static void applyKey(Database db, String hexKey) {
    assert(RegExp(r'^[0-9a-f]{64}$').hasMatch(hexKey));
    db.execute("PRAGMA key = '$hexKey'");
    db.select('SELECT count(*) FROM sqlite_master');
  }

  /// Runs once at startup, before any Drift file opens: finishes an
  /// interrupted migration, loads (or creates) the device key, and encrypts
  /// every plaintext database file in [documentsDir] in place.
  ///
  /// Throws [DbKeyUnavailableException] only when an encrypted file exists
  /// and its key can't be read — every other failure leaves the affected file
  /// plaintext and working, and is retried next launch.
  static Future<DbPrepareResult> prepare(
    String documentsDir, {
    DbKeyStore? store,
    bool? enabled,
  }) async {
    final on = enabled ?? enabledByBuild;
    final keyStore = store ?? DbKeyStore();
    final dir = Directory(documentsDir);
    if (!await dir.exists()) return const DbPrepareResult();

    // 1. A `.pre-encrypt` copy means a migration never confirmed — the app
    //    has not opened the file since (prepare runs first), so the copy is
    //    the newest data. Put it back and migrate again from scratch.
    var restored = 0;
    for (final pre in _listFiles(dir, (n) => n.endsWith(_preSuffix))) {
      final target = pre.path.substring(0, pre.path.length - _preSuffix.length);
      await _restore(pre, File(target));
      restored++;
    }

    final files = _listFiles(dir, isDatabaseFileName);
    final encrypted = files
        .where((f) => DbFileStateX.of(f) == DbFileState.encrypted)
        .toList();
    final plaintext = files
        .where((f) => DbFileStateX.of(f) == DbFileState.plaintext)
        .toList();

    // 2. The key.
    String? key;
    try {
      key = await keyStore.read();
    } catch (e) {
      _breadcrumb('key read failed: ${e.runtimeType}');
      if (encrypted.isNotEmpty) {
        throw DbKeyUnavailableException(
          DbLockReason.keyUnreadable,
          files: encrypted.map((f) => p.basename(f.path)).toList(),
        );
      }
      // Nothing encrypted yet: stay plaintext this launch, try again next.
      _hexKey = null;
      return DbPrepareResult(restored: restored, skippedNoKey: true);
    }
    if (key == null && encrypted.isNotEmpty) {
      throw DbKeyUnavailableException(
        DbLockReason.keyMissing,
        files: encrypted.map((f) => p.basename(f.path)).toList(),
      );
    }
    if (key == null && on) {
      try {
        key = await keyStore.create();
      } catch (e) {
        _breadcrumb('key create failed: ${e.runtimeType}');
        key = null;
      }
    }
    _hexKey = key;
    if (key == null || !on) {
      return DbPrepareResult(restored: restored, skippedNoKey: key == null);
    }

    // 3. Encrypt each plaintext file, verified, with rollback.
    var migrated = 0;
    final failed = <String>[];
    for (final file in plaintext) {
      final name = p.basename(file.path);
      try {
        await Isolate.run(() => migrateFile(file.path, key!));
        migrated++;
        _breadcrumb('encrypted $name');
      } catch (e, st) {
        failed.add(name);
        _breadcrumb('encrypt failed $name: ${e.runtimeType}');
        if (!kDebugMode) {
          unawaited(Sentry.captureException(e, stackTrace: st));
        }
      }
    }
    return DbPrepareResult(
      restored: restored,
      migrated: migrated,
      failed: failed,
    );
  }

  /// Encrypts one plaintext file in place. Synchronous; run off the UI
  /// isolate. On any failure the original bytes are put back before the
  /// error is rethrown, so the caller is left with the working plaintext file.
  @visibleForTesting
  static void migrateFile(String path, String hexKey) {
    final file = File(path);
    final pre = File('$path$_preSuffix');

    // a. Open plaintext. Opening replays a hot rollback journal if a crash
    //    left one, so the copy below is consistent.
    final before = _snapshot(sqlite3.open(path));

    // b. Safety copy (same directory, same OS file protection).
    file.copySync(pre.path);
    try {
      // c. Encrypt in place.
      final db = sqlite3.open(path);
      try {
        db.execute("PRAGMA rekey = '$hexKey'");
      } finally {
        db.close();
      }
      if (DbFileStateX.of(file) != DbFileState.encrypted) {
        throw StateError('rekey left the header readable');
      }
      // d. Reopen with the key: same tables, same row counts.
      final check = sqlite3.open(path);
      try {
        applyKey(check, hexKey);
      } catch (_) {
        check.close();
        rethrow;
      }
      final after = _snapshot(check);
      if (!mapEquals(before, after)) {
        throw StateError('row counts changed during encryption');
      }
    } catch (_) {
      _restoreSync(pre, file);
      rethrow;
    }
    pre.deleteSync();
  }

  /// Integrity + per-table row counts; disposes [db].
  static Map<String, int> _snapshot(Database db) {
    try {
      final ok = db.select('PRAGMA quick_check').first.values.first;
      if (ok != 'ok') throw StateError('quick_check: $ok');
      final tables = db
          .select(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%'",
          )
          .map((r) => r['name'] as String);
      return {
        for (final t in tables)
          t: db.select('SELECT count(*) AS c FROM "$t"').first['c'] as int,
      };
    } finally {
      db.close();
    }
  }

  /// Moves every database file (and its journal) into a dated folder so the
  /// owner can start an empty shop when the key is gone. No file is deleted —
  /// removing a shop's books is not this code's call. The unreadable key
  /// entry is cleared so a fresh one can be stored; after that the moved
  /// files can only be read if the old key value is somehow recovered.
  static Future<String> setAsideLockedFiles(
    String documentsDir, {
    DbKeyStore? store,
  }) async {
    final dir = Directory(documentsDir);
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9]'), '')
        .substring(0, 14);
    final aside = Directory(p.join(documentsDir, 'locked_$stamp'));
    await aside.create(recursive: true);
    for (final f in _listFiles(
      dir,
      (n) => isDatabaseFileName(n) || _isSidecarOf(n) || n.endsWith(_preSuffix),
    )) {
      await f.rename(p.join(aside.path, p.basename(f.path)));
    }
    try {
      await (store ?? DbKeyStore()).clearUnreadable();
    } catch (_) {}
    _breadcrumb('locked files set aside');
    return aside.path;
  }

  /// `mm_pos.sqlite`, `mm_pos_device.sqlite`, `mm_pos_<shop>.sqlite`, and the
  /// legacy `mm_pos.sqlite.bak` left by the per-shop cutover.
  static bool isDatabaseFileName(String name) =>
      name.startsWith('mm_pos') &&
      (name.endsWith('.sqlite') || name.endsWith('.sqlite.bak'));

  static bool _isSidecarOf(String name) =>
      name.startsWith('mm_pos') &&
      (name.endsWith('-journal') ||
          name.endsWith('-wal') ||
          name.endsWith('-shm'));

  static const _preSuffix = '.pre-encrypt';

  static List<File> _listFiles(Directory dir, bool Function(String) match) =>
      dir
          .listSync(followLinks: false)
          .whereType<File>()
          .where((f) => match(p.basename(f.path)))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  /// Copy-then-rename so a crash mid-restore never leaves a half file.
  static Future<void> _restore(File pre, File target) async {
    final tmp = File('${target.path}.restore');
    await pre.copy(tmp.path);
    await tmp.rename(target.path);
    final journal = File('${target.path}-journal');
    if (await journal.exists()) await journal.delete();
    await pre.delete();
  }

  static void _restoreSync(File pre, File target) {
    final tmp = File('${target.path}.restore');
    pre.copySync(tmp.path);
    tmp.renameSync(target.path);
    final journal = File('${target.path}-journal');
    if (journal.existsSync()) journal.deleteSync();
    pre.deleteSync();
  }

  static void _breadcrumb(String message) {
    debugPrint('db-encryption: $message');
    Sentry.addBreadcrumb(
      Breadcrumb(category: 'db.encryption', message: message),
    );
  }
}

enum DbFileState { missing, plaintext, encrypted }

extension DbFileStateX on DbFileState {
  static const _header = 'SQLite format 3\u0000';

  /// From the first 16 bytes: an unencrypted SQLite file always starts with
  /// the magic string; an encrypted one is indistinguishable from noise.
  static DbFileState of(File file) {
    if (!file.existsSync()) return DbFileState.missing;
    final raf = file.openSync();
    try {
      if (raf.lengthSync() == 0) return DbFileState.missing;
      final head = raf.readSync(16);
      return String.fromCharCodes(head) == _header
          ? DbFileState.plaintext
          : DbFileState.encrypted;
    } finally {
      raf.closeSync();
    }
  }
}

class DbPrepareResult {
  const DbPrepareResult({
    this.restored = 0,
    this.migrated = 0,
    this.failed = const [],
    this.skippedNoKey = false,
  });

  /// Interrupted migrations rolled back to their safety copy.
  final int restored;
  final int migrated;

  /// Files left plaintext this launch (retried next launch).
  final List<String> failed;

  /// No key could be read or stored — everything stayed plaintext.
  final bool skippedNoKey;
}

enum DbLockReason {
  /// The keystore has no key, but encrypted files exist.
  keyMissing,

  /// The keystore threw — may be transient, so Retry is offered first.
  keyUnreadable,
}

class DbKeyUnavailableException implements Exception {
  DbKeyUnavailableException(this.reason, {this.files = const []});
  final DbLockReason reason;
  final List<String> files;

  @override
  String toString() =>
      'DbKeyUnavailableException(${reason.name}, ${files.join(', ')})';
}

/// Device-wide key custody. Device-global by design (one key for every shop
/// file on this device) — it is not an `AppSettings` key and must never be
/// written into a shop database.
class DbKeyStore {
  DbKeyStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // `first_unlock` (not `…_this_device`): the key travels with an
            // encrypted iCloud / Finder backup to a new iPhone, together with
            // the Documents files it opens. A ThisDeviceOnly key would turn
            // every phone upgrade into a locked shop.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;
  static const storageKey = 'db.encryption_key.v1';

  /// Null when no key was ever stored; throws when the keystore fails.
  Future<String?> read() async {
    final v = await _storage.read(key: storageKey);
    if (v == null || v.isEmpty) return null;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(v)) {
      throw const FormatException('stored database key is malformed');
    }
    return v;
  }

  /// Generates, stores and reads back a new key — a key that can't be read
  /// back is never used to encrypt anything.
  Future<String> create() async {
    final rnd = Random.secure();
    final key = List.generate(
      32,
      (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await _storage.write(key: storageKey, value: key);
    final back = await read();
    if (back != key) throw StateError('database key did not read back');
    return key;
  }

  /// Only for [DbEncryption.setAsideLockedFiles]: the old key is unreadable
  /// (or absent) and its files are already moved aside.
  Future<void> clearUnreadable() => _storage.delete(key: storageKey);
}
