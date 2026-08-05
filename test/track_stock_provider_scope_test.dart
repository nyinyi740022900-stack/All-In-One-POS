import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('trackStockProvider follows active shop scope', () async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    final settings = container.read(settingsRepositoryProvider);
    await settings.setTrackStock('shop-main', false);
    await settings.setTrackStock('shop-branch', true);

    // Start on main shop => false.
    container.read(shopIdProvider.notifier).state = 'shop-main';
    final mainValue = await container.read(trackStockProvider.future);
    expect(mainValue, isFalse);

    // Switch to branch => true (provider rebinds to scoped key).
    container.read(shopIdProvider.notifier).state = 'shop-branch';
    final branchValue = await container.read(trackStockProvider.future);
    expect(branchValue, isTrue);
  });
}
