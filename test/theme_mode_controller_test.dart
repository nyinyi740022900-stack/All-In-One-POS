import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/core/theme_mode_controller.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/data/local/database.dart';

void main() {
  ProviderContainer containerWith(AppDatabase db) {
    final c = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(c.dispose);
    return c;
  }

  AppDatabase freshDb() {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    return db;
  }

  test('defaults to following the phone, so an upgrade changes nothing',
      () async {
    final c = containerWith(freshDb());
    expect(c.read(themeModeControllerProvider), 'system');
    expect(themeModeFromCode(c.read(themeModeControllerProvider)),
        ThemeMode.system);
  });

  test('a chosen mode is applied and persisted', () async {
    final db = freshDb();
    final c = containerWith(db);

    await c.read(themeModeControllerProvider.notifier).set('light');
    expect(c.read(themeModeControllerProvider), 'light');
    expect(await SettingsRepository(db).savedThemeMode(), 'light');

    await c.read(themeModeControllerProvider.notifier).set('dark');
    expect(await SettingsRepository(db).savedThemeMode(), 'dark');
  });

  test('a saved choice is restored on the next launch', () async {
    final db = freshDb();
    await SettingsRepository(db).saveThemeMode('dark');

    final c = containerWith(db);
    // Construction kicks off the async load; let it land.
    c.read(themeModeControllerProvider);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(themeModeControllerProvider), 'dark');
  });

  test('an unsupported code is ignored rather than blanking the screen',
      () async {
    final c = containerWith(freshDb());
    await c.read(themeModeControllerProvider.notifier).set('dark');
    await c.read(themeModeControllerProvider.notifier).set('sepia');
    expect(c.read(themeModeControllerProvider), 'dark');
  });

  test('every offered choice maps to a real ThemeMode', () {
    // Guards the switch in themeModeFromCode against a new option being added
    // to the picker without a case here — which would silently fall through
    // to `system` and make the new choice do nothing.
    expect(supportedThemeModes, {'system', 'light', 'dark'});
    expect(themeModeFromCode('light'), ThemeMode.light);
    expect(themeModeFromCode('dark'), ThemeMode.dark);
    expect(themeModeFromCode('system'), ThemeMode.system);
  });
}
