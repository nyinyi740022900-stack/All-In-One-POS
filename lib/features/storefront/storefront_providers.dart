import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'storefront_repository.dart';

/// Riverpod providers for [StorefrontRepository] — kept out of
/// `storefront_repository.dart` itself because that file is also imported by
/// the *public* storefront web build, which cannot pull in
/// `core/providers.dart` (native `dart:ffi` via Drift/`sqlite3_flutter_libs`
/// — see that file's own comment). Only the main app's screens
/// (`shop_profile_screen.dart`, `storefront_screen.dart`,
/// `order_detail_sheet.dart`, `order_invoice.dart`) import this file.
final storefrontRepositoryProvider = Provider<StorefrontRepository>((ref) {
  return StorefrontRepository(ref.watch(shopIdProvider));
});

final myStorefrontProvider = FutureProvider<StorefrontRow?>((ref) {
  return ref.watch(storefrontRepositoryProvider).mine();
});

final blockedCustomersProvider = FutureProvider<List<BlockedCustomer>>((ref) {
  return ref.watch(storefrontRepositoryProvider).listBlocked();
});
