import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../license/license_providers.dart';
import '../printing/printing_providers.dart';
import 'branch_repository.dart';

final branchRepositoryProvider = Provider<BranchRepository>((ref) {
  return BranchRepository(
    ref.watch(databaseProvider),
    ref.watch(licenseRepositoryProvider),
    ref.watch(settingsRepositoryProvider),
  );
});

final branchesProvider = FutureProvider.autoDispose<List<Branch>>((ref) {
  return ref.watch(branchRepositoryProvider).listBranches();
});

final branchSwitchRecoveryProvider =
    StreamProvider.autoDispose<BranchSwitchRecoveryState?>((ref) {
      return ref.watch(branchRepositoryProvider).watchSwitchRecoveryState();
    });

final pendingOutboxCountProvider = StreamProvider.autoDispose<int>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.outbox).watch().map((rows) => rows.length);
});
