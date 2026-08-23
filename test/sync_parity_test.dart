import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/sync/sync_heal.dart';
import 'package:mm_pos/data/sync/sync_mappers.dart';

/// Three-way parity guard (audit Low #2): every synced table must line up
/// across ALL of
///   1. the Drift schema (registered in AppDatabase),
///   2. the syncTables mapper registry,
///   3. the Supabase migrations (table created + RLS shop_isolation),
/// and every mapper-emitted column must exist in the SQL schema — a new
/// column added on one side without the others fails HERE instead of
/// silently diverging on devices.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  final migrationsDir = Directory('supabase/migrations');
  final sqlAll = migrationsDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .map((f) => f.readAsStringSync())
      .join('\n');
  final sql0012 = File('supabase/migrations/0012_drop_dev_policies.sql')
      .readAsStringSync()
      .replaceAll('\n', ' ');

  /// Columns that exist locally but are deliberately never synced.
  const localOnlyColumns = <String, Set<String>>{
    'expenses': {'receipt_photo_path'}, // local file path only — see mappers
  };

  bool hasRlsPolicy(String table) {
    final explicit = RegExp(
      'shop_isolation\\s+on\\s+$table\\b',
      caseSensitive: false,
    ).hasMatch(sqlAll);
    // 0012 re-created shop_isolation for the core tables via a dynamic
    // foreach array — membership in that array counts as covered.
    final in0012 = sql0012.contains("'$table'");
    return explicit || in0012;
  }

  test('every syncTables entry exists in the Drift schema, exactly once, '
      'with an RLS shop_isolation policy remotely', () {
    final driftTables = {for (final t in db.allTables) t.entityName: t};

    final names = syncTables.map((d) => d.name).toList();
    expect(names.toSet().length, names.length,
        reason: 'duplicate registry entries would double-push a table');

    for (final def in syncTables) {
      expect(driftTables, contains(def.name),
          reason: '${def.name} is in syncTables but not registered as a '
              'Drift table');
      expect(hasRlsPolicy(def.name), isTrue,
          reason: '${def.name} has no shop_isolation policy in the '
              'supabase/migrations — pushes would be default-deny or, worse, '
              'cross-shop readable');
      expect(
        RegExp('create table( if not exists)? ${def.name}\\b',
                caseSensitive: false)
            .hasMatch(sqlAll),
        isTrue,
        reason: '${def.name} has no CREATE TABLE in the migrations',
      );
    }
  });

  test('every non-ledger heal entry is a real synced table (audit Low #1 '
      'parity — a typo would silently shrink protection)', () {
    final names = syncTables.map((d) => d.name).toSet();
    for (final t in kNonLedgerSyncTables) {
      expect(names, contains(t),
          reason: '$t is in kNonLedgerSyncTables but not in syncTables');
    }
    // Spot-check the protection inversion: ledgers are protected, and an
    // unknown table name defaults to protected (never silently droppable).
    expect(isLedgerSyncTable('sales'), isTrue);
    expect(isLedgerSyncTable('stock_movements'), isTrue);
    expect(isLedgerSyncTable('brand_new_future_table'), isTrue,
        reason: 'unknown tables must default to protected');
    expect(isLedgerSyncTable('customers'), isFalse);
  });

  test('mapper keys line up with SQL columns both ways (toRemote emits '
      'every required column and nothing unknown; upsertLocal round-trips)',
      () async {
    final driftTables = {for (final t in db.allTables) t.entityName: t};

    for (final def in syncTables) {
      final table = driftTables[def.name]!;
      final localOnly = localOnlyColumns[def.name] ?? const <String>{};
      final sqlColumns = {
        for (final entry in table.columnsByName.entries)
          if (!localOnly.contains(entry.key)) entry.key: entry.value,
      };

      // Insert one fully-populated dummy row via raw SQL so toRemote has
      // something to serialize. Every column gets a type-correct literal;
      // id is fixed so we can read it back.
      final colNames = <String>[];
      final colValues = <String>[];
      for (final c in table.columnsByName.values) {
        // Force a CLEAN local copy so upsertLocal's M4 tie branch re-applies.
        if (c.$name == 'dirty') {
          colNames.add('"dirty"');
          colValues.add('0');
          continue;
        }
        if (c.$name == 'id') {
          colNames.add('"id"');
          colValues.add("'parity-row'");
          continue;
        }
        colNames.add('"${c.$name}"');
        colValues.add(switch (c.type) {
          DriftSqlType.string => "'x'",
          DriftSqlType.bool => '1',
          DriftSqlType.dateTime =>
            (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
          _ => '1',
        });
      }
      await db.customStatement(
        'INSERT OR REPLACE INTO "${table.entityName}" '
        '(${colNames.join(', ')}) VALUES (${colValues.join(', ')})',
      );

      final remote = await def.toRemote(db, 'parity-row');
      expect(remote, isNotNull,
          reason: '${def.name}.toRemote could not serialize a fully '
              'populated row');

      // Nothing unknown goes to the server (a renamed/typo'd key would
      // make PostgREST reject every push of this table with PGRST204).
      final unknownKeys =
          remote!.keys.toSet().difference(sqlColumns.keys.toSet());
      expect(unknownKeys, isEmpty,
          reason: '${def.name}.toRemote emits columns that do not exist in '
              'the SQL schema: $unknownKeys');

      // Every NOT NULL column without a server-side default MUST be pushed,
      // or the upsert fails with a NOT NULL violation on the server.
      final missingRequired = <String>[];
      for (final entry in sqlColumns.entries) {
        final c = entry.value;
        final serverDefault = entry.key == 'received_at'; // 0064 trigger/def
        if (!c.$nullable && c.defaultValue == null && !serverDefault) {
          if (!remote.keys.contains(entry.key)) missingRequired.add(entry.key);
        }
      }
      expect(missingRequired, isEmpty,
          reason: '${def.name}.toRemote omits NOT NULL columns: '
              '$missingRequired — pushes would violate NOT NULL remotely');

      // Round-trip: applying our own serialized row back must not throw and
      // must report success (the mapper understands every key it emits).
      final applied = await def.upsertLocal(db, remote);
      expect(applied, isTrue,
          reason: '${def.name}.upsertLocal failed to re-apply its own '
              'toRemote output');
    }
  });
}
