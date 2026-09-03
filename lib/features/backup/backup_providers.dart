import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/shop_data_transition_service.dart';
import '../printing/printing_providers.dart';
import 'backup_service.dart';

final backupServiceProvider = Provider<BackupService>((ref) {
  final db = ref.watch(databaseProvider);
  return BackupService(
    db,
    ref.watch(settingsRepositoryProvider),
    // So a restore can refuse another shop's file, and refuse to destroy
    // writes that have not reached the cloud yet.
    shopId: ref.watch(shopIdProvider),
    guard: ShopDataTransitionService(db),
  );
});
