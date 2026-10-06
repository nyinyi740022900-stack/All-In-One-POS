import 'dart:convert';

import 'package:web/web.dart' as web;

import 'storefront_api.dart';

/// MMPay requires that returning from a banking app must not lose the order,
/// and that a refresh restores the same order and QR rather than issuing a
/// new one. A scanned QR outlives this tab, so the live order is cached in
/// `localStorage` and read back on load; the server's `mmqr_status` remains
/// the authority on what actually happened to it.
const _key = 'mmqr.active_order';

void saveMmqrOrder(String shopId, String plan, MmqrOrder order) {
  try {
    web.window.localStorage.setItem(
      _key,
      jsonEncode({'shop_id': shopId, 'plan': plan, ...order.toJson()}),
    );
  } catch (_) {
    // Private browsing, or storage disabled. The page still works for as long
    // as it stays open; only the restore-after-refresh affordance is lost.
  }
}

MmqrCachedOrder? loadMmqrOrder() {
  try {
    final raw = web.window.localStorage.getItem(_key);
    if (raw == null || raw.isEmpty) return null;
    final data = (jsonDecode(raw) as Map).cast<String, dynamic>();
    final shopId = data['shop_id'];
    final plan = data['plan'];
    if (shopId is! String || plan is! String) return null;
    return MmqrCachedOrder(
      shopId: shopId,
      plan: plan,
      order: MmqrOrder.fromMap(data),
    );
  } catch (_) {
    // Anything unreadable is treated as no cached order rather than as a
    // reason to fail the page.
    return null;
  }
}

void clearMmqrOrder() {
  try {
    web.window.localStorage.removeItem(_key);
  } catch (_) {
    // Nothing to do: a cache we cannot clear is re-validated on next load.
  }
}
