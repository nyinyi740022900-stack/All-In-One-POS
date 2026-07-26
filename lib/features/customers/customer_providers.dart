import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/database.dart';
import 'customer_repository.dart';

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepository(
      ref.watch(databaseProvider), ref.watch(shopIdProvider));
});

final customersStreamProvider = StreamProvider<List<Customer>>((ref) {
  return ref.watch(customerRepositoryProvider).watchCustomers();
});

/// Search query for the customer picker / directory screen.
final customerSearchProvider = StateProvider<String>((ref) => '');

final filteredCustomersProvider = Provider<List<Customer>>((ref) {
  final all = ref.watch(customersStreamProvider).valueOrNull ?? const [];
  final q = ref.watch(customerSearchProvider).trim().toLowerCase();
  if (q.isEmpty) return all;
  return all
      .where((c) =>
          c.name.toLowerCase().contains(q) ||
          (c.phone?.toLowerCase().contains(q) ?? false))
      .toList();
});
