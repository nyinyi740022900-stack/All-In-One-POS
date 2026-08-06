import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsRepository(db);
  });

  tearDown(() async => db.close());

  test('cleanupDeprecatedStaffModeSettings removes local role/PIN settings',
      () async {
    const oldKeys = [
      'staff.role',
      'staff.pin_hash',
      'staff.pin',
      'staff.pin_failed_attempts',
      'staff.pin_locked_until',
      'staff.active_id',
    ];
    for (final key in oldKeys) {
      await db.into(db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion(key: Value(key), value: const Value('v')),
          );
    }
    await settings.cleanupDeprecatedStaffModeSettings();

    final rows = await db.select(db.appSettings).get();
    final keys = rows.map((r) => r.key).toSet();
    for (final key in oldKeys) {
      expect(keys, isNot(contains(key)));
    }
    expect(keys, contains('migration.staff_mode_cleanup.v1'));
  });

  test('cleanupDeprecatedStaffModeSettings is idempotent', () async {
    await settings.cleanupDeprecatedStaffModeSettings();
    await settings.cleanupDeprecatedStaffModeSettings();

    final rows = await db.select(db.appSettings).get();
    final cleanupRows =
        rows.where((r) => r.key == 'migration.staff_mode_cleanup.v1').toList();
    expect(cleanupRows, hasLength(1));
    expect(cleanupRows.single.value, 'true');
  });
}
