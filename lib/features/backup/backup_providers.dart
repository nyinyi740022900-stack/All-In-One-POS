import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../printing/printing_providers.dart';
import 'backup_service.dart';

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
      ref.watch(databaseProvider), ref.watch(settingsRepositoryProvider));
});
