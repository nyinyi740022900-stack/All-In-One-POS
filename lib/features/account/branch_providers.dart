import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../core/providers.dart';
import '../license/license_providers.dart';
import '../printing/printing_providers.dart';
import 'branch_repository.dart';

final branchRepositoryProvider = Provider<BranchRepository>((ref) {
  return BranchRepository(
    ref.watch(databaseProvider),
    ref.watch(licenseRepositoryProvider),
    ref.watch(settingsRepositoryProvider),
    onShopDbSwap: (toShopId) async {
      final session = ref.read(databaseSessionProvider);
      await session?.reopenForShop(toShopId);
    },
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

final branchConnectivityProvider = StreamProvider.autoDispose<bool>((
  ref,
) async* {
  final connectivity = Connectivity();
  final initial = await connectivity.checkConnectivity();
  yield initial.any((r) => r != ConnectivityResult.none);
  yield* connectivity.onConnectivityChanged.map(
    (results) => results.any((r) => r != ConnectivityResult.none),
  );
});
