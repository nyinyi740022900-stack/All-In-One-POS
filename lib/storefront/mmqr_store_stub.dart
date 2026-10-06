import 'storefront_api.dart';

/// No-op outside the browser. The MMQR surface is web-only (`/renew`); this
/// exists so widget tests and the mobile entrypoint can import the page
/// without pulling in `dart:js_interop`.
void saveMmqrOrder(String shopId, String plan, MmqrOrder order) {}

MmqrCachedOrder? loadMmqrOrder() => null;

void clearMmqrOrder() {}
