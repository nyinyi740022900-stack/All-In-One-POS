import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/database.dart';
import '../data/local/database_session.dart';

/// Opened in [main] via override. Null in unit/widget tests that only override
/// [databaseProvider].
final databaseSessionProvider = ChangeNotifierProvider<DatabaseSession?>((
  ref,
) {
  return null;
});

/// Active shop-scoped Drift database (rebinds when [DatabaseSession] swaps).
final databaseProvider = Provider<AppDatabase>((ref) {
  final session = ref.watch(databaseSessionProvider);
  if (session != null) return session.shopDb;
  throw StateError(
    'databaseProvider requires databaseSessionProvider (main) '
    'or an override (tests)',
  );
});

/// Device-global sidecar DB. Falls back to [databaseProvider] when no session
/// (tests override shop DB only).
final deviceDatabaseProvider = Provider<AppDatabase>((ref) {
  final session = ref.watch(databaseSessionProvider);
  if (session != null) return session.deviceDb;
  return ref.watch(databaseProvider);
});

/// The active shop id. Set at license activation (Phase 5). For local-only
/// development we use a fixed demo shop so rows have a valid scope.
final shopIdProvider = StateProvider<String>(
  (ref) => kDebugMode ? 'demo-shop' : '',
);
