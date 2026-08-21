import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/features/support/vendor_config.dart';

void main() {
  test('fromMap / toMap round-trips the config keys', () {
    const cfg = VendorConfig(
      kbzName: 'ACME',
      kbzNumber: '09111',
      waveName: 'ACME',
      waveNumber: '09222',
      supportViber: '09333',
    );
    final restored = VendorConfig.fromMap(cfg.toMap());
    expect(restored.kbzNumber, '09111');
    expect(restored.waveNumber, '09222');
    expect(restored.supportViber, '09333');
    expect(restored.hasKbz, isTrue);
    expect(restored.hasSupport, isTrue);
  });

  test('empty config reports nothing configured', () {
    expect(VendorConfig.empty.hasKbz, isFalse);
    expect(VendorConfig.empty.hasWave, isFalse);
    expect(VendorConfig.empty.hasSupport, isFalse);
  });

  test('missing device.free_limit defaults to 3 (main + 2 extras)', () {
    expect(VendorConfig.fromMap({}).deviceFreeLimit, 3);
    expect(const VendorConfig().deviceFreeLimit, 3);
  });

  test('priceFor: online price defaults to the offline price when unset',
      () {
    final cfg = VendorConfig.fromMap({
      'price.monthly': '15000',
      'price.yearly': '150000',
    });
    expect(cfg.priceFor('monthly', tier: 'online'), 15000);
    expect(cfg.priceFor('yearly', tier: 'online'), 150000);
  });

  test('priceFor: an explicitly-set online price overrides the default', () {
    final cfg = VendorConfig.fromMap({
      'price.monthly': '15000',
      'price.yearly': '150000',
      'price.monthly.online': '25000',
      'price.yearly.online': '250000',
    });
    expect(cfg.priceFor('monthly'), 15000);
    expect(cfg.priceFor('monthly', tier: 'online'), 25000);
    expect(cfg.priceFor('yearly', tier: 'online'), 250000);
  });

  test('load() falls back to the cached config when offline', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = SettingsRepository(db);
    // Seed a cached config (as an online refresh would have written).
    await settings.setVendorConfigJson(jsonEncode(const VendorConfig(
      kbzNumber: '09777',
      supportViber: '09888',
    ).toMap()));

    // No backend configured in tests → load() reads the cache.
    final cfg = await VendorConfigRepository(settings).load();
    expect(cfg.kbzNumber, '09777');
    expect(cfg.supportViber, '09888');
  });
}
