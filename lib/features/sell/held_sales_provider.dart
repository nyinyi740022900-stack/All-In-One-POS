import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/money.dart';
import 'cart.dart';

/// A parked cart: the customer said "wait, I'll grab one more thing" and the
/// counter has a next customer *now*. Session-scoped by design — a hold is
/// minutes old, not days; persisting it would need a synced table for
/// something that mostly exists to survive the next ten minutes.
class HeldSale {
  final String id;
  final DateTime at;
  final CartState cart;

  const HeldSale({required this.id, required this.at, required this.cart});

  int get itemCount => cart.itemCount;
  Money get total => cart.total;
}

class HeldSalesNotifier extends StateNotifier<List<HeldSale>> {
  HeldSalesNotifier() : super(const []);

  static const _uuid = Uuid();

  /// Parks [cart] at the front of the list; returns its id.
  String hold(CartState cart) {
    final held = HeldSale(id: _uuid.v4(), at: DateTime.now(), cart: cart);
    state = [held, ...state];
    return held.id;
  }

  /// Removes and returns the held sale with [id], or null if already gone.
  CartState? resume(String id) {
    for (final h in state) {
      if (h.id == id) {
        state = state.where((e) => e.id != id).toList();
        return h.cart;
      }
    }
    return null;
  }

  void remove(String id) {
    state = state.where((e) => e.id != id).toList();
  }
}

final heldSalesProvider =
    StateNotifierProvider<HeldSalesNotifier, List<HeldSale>>(
      (ref) => HeldSalesNotifier(),
    );
