import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../license/license_providers.dart';
import '../printing/printing_providers.dart';
import 'account_repository.dart';

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return AccountRepository(
    ref.watch(licenseRepositoryProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(databaseProvider),
  );
});
