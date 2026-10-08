import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/net/edge_invoke.dart';

import '../core/payment_method.dart';

/// A product shown on the public storefront.
class StoreProduct {
  final String id;
  final String name;
  final int price;
  final String unit;
  final String? imageUrl;

  /// Remaining units the owner will sell online, if they've set an
  /// `onlineStockLimit` on this product (independent of real in-store
  /// stock). Null means no cap — sell as normal.
  final int? onlineAvailable;

  /// The product's category, if it has one — drives the storefront's
  /// category filter chips. Null products just never match a chip other
  /// than "All".
  final String? categoryId;
  const StoreProduct(
    this.id,
    this.name,
    this.price,
    this.unit,
    this.imageUrl, {
    this.onlineAvailable,
    this.categoryId,
  });
}

/// A category the storefront can filter its product grid by — only
/// categories actually used by a published product are sent (see the
/// Edge Function), so this list never shows an empty filter.
class StoreCategory {
  final String id;
  final String name;
  const StoreCategory(this.id, this.name);
}

/// Public shop info + payment numbers shown to customers.
class StoreInfo {
  /// The shop's tenant id. Not a secret (RLS gates every read) — the guest
  /// checkout needs it to upload the payment proof into the shop's own
  /// `{shop_id}/` bucket folder, which is what the read policy (migration
  /// 0066) scopes visibility to.
  final String shopId;
  final String? displayName;
  final String? phone;
  final String? address;
  final List<PaymentMethod> paymentMethods;
  final String? logoUrl;
  final bool acceptingOrders;
  final bool requireTransferProof;
  final bool hoursEnabled;
  final int? openMinute;
  final int? closeMinute;
  final String currencyCode;

  const StoreInfo({
    required this.shopId,
    this.displayName,
    this.phone,
    this.address,
    this.paymentMethods = const [],
    this.logoUrl,
    this.acceptingOrders = true,
    this.requireTransferProof = true,
    this.hoursEnabled = false,
    this.openMinute,
    this.closeMinute,
    this.currencyCode = 'MMK',
  });
}

class Catalog {
  final StoreInfo info;
  final List<StoreProduct> products;
  final List<StoreCategory> categories;
  const Catalog(this.info, this.products, [this.categories = const []]);
}

/// One line the customer wants to order.
class OrderLine {
  final String productId;
  final String name;
  final int price;
  final int qty;
  const OrderLine(this.productId, this.name, this.price, this.qty);
}

/// What [StorefrontApi.submitOrder] hands back: the order number plus the
/// prices the server actually charged (re-read from the product row, never
/// taken from the client catalog fetch).
class SubmitOrderResult {
  const SubmitOrderResult({
    required this.orderNo,
    this.itemsTotal,
    this.lines = const [],
  });
  final String orderNo;
  final int? itemsTotal;
  final List<OrderLine> lines;

  factory SubmitOrderResult.fromMap(Map<String, dynamic> m) {
    final rawLines = m['lines'];
    final lines = rawLines is List
        ? rawLines
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .map(
                (l) => OrderLine(
                  l['product_id'] as String? ?? '',
                  l['name'] as String? ?? '',
                  (l['price'] as num?)?.toInt() ?? 0,
                  (l['qty'] as num?)?.toInt() ?? 0,
                ),
              )
              .where((l) => l.productId.isNotEmpty)
              .toList()
        : const <OrderLine>[];
    return SubmitOrderResult(
      orderNo: m['order_no'] as String? ?? '',
      itemsTotal: (m['items_total'] as num?)?.toInt(),
      lines: lines,
    );
  }
}

/// Talks to the `storefront` Edge Function. The browser only ever holds the
/// anon key; the function reads/writes across RLS with the service role.
class StorefrontApi {
  SupabaseClient get _c => Supabase.instance.client;

  Future<Catalog> fetchCatalog(String slug) async {
    final res = await _c.functions.invokeBounded(
      'storefront',
      body: {'action': 'catalog', 'slug': slug},
    );
    if (res.status != 200) {
      throw Exception(res.data is Map ? res.data['error'] : 'error');
    }
    final data = (res.data as Map).cast<String, dynamic>();
    final s = (data['storefront'] as Map).cast<String, dynamic>();
    final products = (data['products'] as List)
        .map((e) => (e as Map).cast<String, dynamic>())
        .map(
          (m) => StoreProduct(
            m['id'] as String,
            m['name'] as String,
            (m['sale_price'] as num?)?.toInt() ?? 0,
            (m['unit'] as String?) ?? 'pcs',
            m['image_url'] as String?,
            onlineAvailable: (m['online_available'] as num?)?.toInt(),
            categoryId: m['category_id'] as String?,
          ),
        )
        .toList();
    final categoriesRaw = data['categories'];
    final categories = categoriesRaw is List
        ? categoriesRaw
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .map(
                (m) => StoreCategory(
                  m['id'] as String? ?? '',
                  m['name'] as String? ?? '',
                ),
              )
              .where((c) => c.id.isNotEmpty)
              .toList()
        : const <StoreCategory>[];
    return Catalog(
      StoreInfo(
        shopId: s['shop_id'] as String? ?? '',
        displayName: s['display_name'] as String?,
        phone: s['phone'] as String?,
        address: s['address'] as String?,
        paymentMethods: PaymentMethod.listFromJson(s['payment_methods']),
        logoUrl: s['logo_url'] as String?,
        currencyCode: s['currency_code'] as String? ?? 'MMK',
        acceptingOrders: s['accepting_orders'] as bool? ?? true,
        requireTransferProof: s['require_transfer_proof'] as bool? ?? true,
        hoursEnabled: s['hours_enabled'] as bool? ?? false,
        openMinute: (s['open_minute'] as num?)?.toInt(),
        closeMinute: (s['close_minute'] as num?)?.toInt(),
      ),
      products,
      categories,
    );
  }

  /// Uploads a payment screenshot to the private `payment-proofs` bucket
  /// and returns its storage path (to attach to the order). [folder] is the
  /// path prefix the caller may write into: the shop's `{shop_id}/` folder
  /// for storefront orders, `_admin/` for license-request proofs — the read
  /// policy (migration 0066) scopes visibility by that first segment, and
  /// the anon-INSERT policy only accepts those two shapes. Anon uploads are
  /// allowed by policy; reads happen later via signed URLs on the shop side.
  Future<String> uploadPaymentProof(
    List<int> bytes,
    String ext, {
    required String folder,
  }) async {
    final path =
        '$folder/proof-${DateTime.now().millisecondsSinceEpoch}-${bytes.length}.$ext';
    await _c.storage
        .from('payment-proofs')
        .uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(upsert: false),
        );
    return path;
  }

  /// Submits a guest order. [paymentMethod] is `'transfer'` (KPay/Wave,
  /// usually with a screenshot) or `'cod'` (cash on delivery) — the shop sees
  /// a different workflow cue for each. Returns the order number plus the
  /// server-charged line prices/total (confirmation PNG must use those, not
  /// the first catalog fetch).
  /// [clientOrderId] is the browser-generated order id. Pass the SAME value
  /// on every retry of one checkout: the server resolves a repeat to the
  /// order it already created instead of making a second one. Without it, a
  /// submit that commits just past the 15s invoke timeout looks like a plain
  /// failure to the customer, who taps Place Order again — and the shop
  /// packs and ships two orders for one transfer.
  Future<SubmitOrderResult> submitOrder({
    required String slug,
    required String clientOrderId,
    required String customerName,
    String? phone,
    String? address,
    String? township,
    String? note,
    required String paymentMethod,
    String? paymentProofPath,
    required List<OrderLine> lines,
    String? hp,
  }) async {
    final res = await _c.functions.invokeBounded(
      'storefront',
      body: {
        'action': 'submit_order',
        'client_order_id': clientOrderId,
        'slug': slug,
        'customer_name': customerName,
        'phone': phone,
        'address': address,
        'township': township,
        'note': note,
        'payment_method': paymentMethod,
        'payment_proof_path': paymentProofPath,
        'hp': hp,
        'lines': [
          for (final l in lines)
            {
              'product_id': l.productId,
              'name': l.name,
              'price': l.price,
              'qty': l.qty,
            },
        ],
      },
    );
    if (res.status != 200 || (res.data is Map && res.data['ok'] != true)) {
      throw Exception(res.data is Map ? res.data['error'] : 'error');
    }
    return SubmitOrderResult.fromMap((res.data as Map).cast<String, dynamic>());
  }

  /// Submits a subscription-renewal request from the /renew page — the shop
  /// owner identifies themselves by [deviceId] (their own "App Reference
  /// ID"), not a slug or session. Reviewed by the admin in the Requests tab.
  /// Returns the new row's id plus its human-quotable `invoice_no`, so the
  /// page can show the receipt straight away and hand the owner a link to
  /// come back to.
  /// [clientRequestId] must be the SAME value on every retry of one
  /// submission — see [submitOrder]. A duplicate here is worse than a
  /// duplicate order: two pending renewals for one transfer, and an admin
  /// confirming both mints two licences.
  Future<SubmittedLicenseRequest> submitLicenseRequest({
    required String clientRequestId,
    required String shopId,
    String? phone,
    required String plan,
    required int months,
    String? method,
    required int amount,
    String? refNo,
    String? paymentProofPath,
    String? hp,
  }) async {
    final res = await _c.functions.invokeBounded(
      'storefront',
      body: {
        'action': 'submit_license_request',
        'client_request_id': clientRequestId,
        'shop_id': shopId,
        'phone': phone,
        'plan': plan,
        'months': months,
        'method': method,
        'amount': amount,
        'ref_no': refNo,
        'payment_proof_path': paymentProofPath,
        'hp': hp,
      },
    );
    if (res.status != 200 || (res.data is Map && res.data['ok'] != true)) {
      throw Exception(res.data is Map ? res.data['error'] : 'error');
    }
    final data = res.data as Map;
    return SubmittedLicenseRequest(
      requestId: data['request_id'] as String? ?? '',
      invoiceNo: data['invoice_no'] as String?,
    );
  }

  /// Fetches the public receipt for a submitted renewal request.
  ///
  /// Keyed by the request id alone — it is a server-generated UUID handed
  /// only to the browser that submitted, so it works as an order-tracking
  /// link. The Edge Function decides what is safe to return; this method
  /// deliberately does not ask for anything else.
  Future<RenewalReceipt> fetchReceipt(String requestId) async {
    final res = await _c.functions.invokeBounded(
      'storefront',
      body: {'action': 'receipt', 'request_id': requestId},
    );
    if (res.status != 200 || res.data is! Map || res.data['receipt'] == null) {
      throw Exception(res.data is Map ? res.data['error'] : 'error');
    }
    return RenewalReceipt.fromMap(
      (res.data['receipt'] as Map).cast<String, dynamic>(),
    );
  }

  /// The /renew page's optional sign-in convenience layer: the signed-in
  /// shop's own past renewal requests. Requires an active Supabase Auth
  /// session — `functions.invoke` automatically sends the current session's
  /// access token as the Authorization header once signed in, same as any
  /// other authenticated call from the mobile app. Throws (rather than
  /// returning an empty list) when not signed in, so a caller can tell
  /// "no session" apart from "signed in, genuinely no requests yet".
  Future<BillingShops> fetchBillingShops() async {
    final response = await _c.functions.invokeBounded(
      'storefront',
      body: {'action': 'list_billing_shops'},
    );
    if (response.data is! Map || (response.data as Map)['shops'] is! List) {
      throw const FormatException('Missing shops');
    }
    final data = response.data as Map;
    return BillingShops(
      shops: (data['shops'] as List)
          .map((row) => (row as Map).cast<String, dynamic>())
          .toList(),
      // Absent means no: an older function that does not report this must not
      // make the page offer a card checkout it cannot complete.
      cardPayment: data['card_payment'] == true,
      mmqrPayment: data['mmqr_payment'] == true,
    );
  }

  /// What this shop's card subscription is doing, and where to cancel it.
  ///
  /// Returns null when there is nothing to manage — no subscription, or a
  /// processor this project has no keys for. A failure to reach the processor
  /// also returns null rather than throwing: the renewal page's primary job is
  /// selling a term, and it must not be blocked by a status panel.
  Future<CardSubscription?> cardSubscription({required String shopId}) async {
    try {
      final response = await _c.functions.invokeBounded(
        'storefront',
        body: {'action': 'card_subscription', 'shop_id': shopId},
      );
      final data = response.data;
      if (data is! Map || data['active'] != true) return null;
      // Absent, malformed or pointing anywhere but the processor all collapse
      // to no link, rather than a button that leads somewhere unexpected.
      final uri = Uri.tryParse('${data['management_url'] ?? ''}');
      final portal =
          uri != null &&
              uri.scheme == 'https' &&
              uri.host.endsWith('.lemonsqueezy.com')
          ? uri
          : null;
      return CardSubscription(
        status: '${data['status'] ?? ''}',
        renewsAt: DateTime.tryParse('${data['renews_at'] ?? ''}'),
        endsAt: DateTime.tryParse('${data['ends_at'] ?? ''}'),
        managementUrl: portal,
      );
    } catch (_) {
      return null;
    }
  }

  /// Starts an international card purchase for [shopId] and returns the
  /// processor's hosted checkout URL.
  ///
  /// The server picks the amount, the term and the mode: this call sends only
  /// which shop and which plan. Throws [CheckoutUnavailable] when the gateway
  /// is not configured, or configured wrongly — the server refuses to sell
  /// rather than charge the wrong price for a term.
  Future<String> createCheckout({
    required String shopId,
    required String plan,
  }) async {
    final FunctionResponse response;
    try {
      response = await _c.functions.invokeBounded(
        'storefront',
        body: {'action': 'create_checkout', 'shop_id': shopId, 'plan': plan},
        // Catalog verification plus an expired subscription lookup and checkout
        // creation can take four bounded 15-second processor round trips.
        timeout: const Duration(seconds: 75),
      );
    } on FunctionException catch (error) {
      // Supabase throws for 409/502/503; those responses never reach response.data.
      if (error.details is Map) _throwCheckoutError(error.details as Map);
      rethrow;
    }
    final data = response.data is Map
        ? (response.data as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final url = data['url'] as String?;
    _throwCheckoutError(data);
    if (url == null || !url.startsWith('https://')) {
      throw const FormatException('Missing checkout url');
    }
    return url;
  }

  static void _throwCheckoutError(Map data) {
    switch (data['error']) {
      case 'checkout_unavailable':
        throw CheckoutUnavailable();
      case 'checkout_in_progress':
        throw CheckoutInProgress();
      case 'subscription_already_exists':
        final raw = data['management_url'];
        final uri = raw is String ? Uri.tryParse(raw) : null;
        throw CheckoutAlreadySubscribed(
          uri != null &&
                  uri.scheme == 'https' &&
                  uri.host.endsWith('.lemonsqueezy.com')
              ? uri
              : null,
        );
    }
  }

  /// Issues an MMQR for [shopId]. The server picks the amount and the term;
  /// this call sends only which shop and which plan.
  ///
  /// Returns null when the order was already paid and has just been settled
  /// server-side — the paid-but-webhook-lost case, which the server heals by
  /// re-querying rather than leaving to a support message.
  Future<MmqrOrder?> createMmqr({
    required String shopId,
    required String plan,
  }) async {
    final FunctionResponse response;
    try {
      response = await _c.functions.invokeBounded(
        'storefront',
        body: {'action': 'create_mmqr', 'shop_id': shopId, 'plan': plan},
        // Reservation, an optional status re-query and the order itself are up
        // to three bounded pairs of MMPay round trips.
        timeout: const Duration(seconds: 75),
      );
    } on FunctionException catch (error) {
      if (error.details is Map) _throwCheckoutError(error.details as Map);
      rethrow;
    }
    final data = response.data is Map
        ? (response.data as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    _throwCheckoutError(data);
    if (data['already_paid'] == true) return null;
    return MmqrOrder.fromMap(data);
  }

  /// Asks the server what MMPay says about [orderId]. The page polls this, and
  /// it is what makes a renewal land when the callback is late rather than
  /// only when it is on time.
  Future<MmqrStatus> mmqrStatus({
    required String shopId,
    required String orderId,
  }) async {
    final FunctionResponse response;
    try {
      response = await _c.functions.invokeBounded(
        'storefront',
        body: {
          'action': 'mmqr_status',
          'shop_id': shopId,
          'order_id': orderId,
        },
        timeout: const Duration(seconds: 45),
      );
    } on FunctionException catch (error) {
      final details = error.details;
      // A row the server no longer has is a finished or abandoned order, not
      // an error the owner can act on.
      if (details is Map && details['error'] == 'not_found') {
        return MmqrStatus.expired;
      }
      rethrow;
    }
    final data = response.data is Map
        ? (response.data as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return MmqrStatus.parse(data['status'] as String?);
  }

  /// Cancels a live order. MMPay's own rules forbid issuing a second QR until
  /// the owner explicitly cancels the first, so this is a real cancel, not a
  /// page reset. Returns true when the order turned out to be paid after all.
  Future<bool> cancelMmqr({
    required String shopId,
    required String orderId,
  }) async {
    final response = await _c.functions.invokeBounded(
      'storefront',
      body: {'action': 'cancel_mmqr', 'shop_id': shopId, 'order_id': orderId},
      timeout: const Duration(seconds: 45),
    );
    final data = response.data is Map
        ? (response.data as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return data['already_paid'] == true;
  }

  Future<List<RenewalRequestSummary>> fetchMyRequests(String shopId) async {
    final res = await _c.functions.invokeBounded(
      'storefront',
      body: {'action': 'my_requests', 'shop_id': shopId},
    );
    if (res.status != 200 || res.data is! Map) {
      throw Exception(res.data is Map ? res.data['error'] : 'error');
    }
    final rows = (res.data as Map)['requests'];
    if (rows is! List) return const [];
    return rows
        .map((e) => (e as Map).cast<String, dynamic>())
        .map(RenewalRequestSummary.fromMap)
        .toList();
  }

  /// Payment-account info (KBZPay/WavePay name+number) plus the support
  /// Viber number, to show a shop owner on the /renew page — read directly
  /// from `app_config`, anon-readable (`0006_app_config.sql`), same source
  /// `VendorConfigRepository` uses on the mobile app. No Edge Function
  /// needed for a plain table read.
  Future<Map<String, String>> fetchPaymentConfig() async {
    final rows = await _c
        .from('app_config')
        .select('key, value')
        .inFilter('key', const [
          'pay.kbzpay.name',
          'pay.kbzpay.number',
          'pay.wavepay.name',
          'pay.wavepay.number',
          'support.viber',
        ]);
    return {
      for (final r in (rows as List))
        (r['key'] as String): (r['value'] as String? ?? ''),
    };
  }
}

/// The shops an owner may pay for, and whether card payment is on offer.
/// An active card subscription, as the processor reports it right now.
class CardSubscription {
  const CardSubscription({
    required this.status,
    this.renewsAt,
    this.endsAt,
    this.managementUrl,
  });

  /// The processor's own word: active, on_trial, past_due, cancelled, paused.
  final String status;

  /// When it charges again. Null once cancelled — [endsAt] applies instead.
  final DateTime? renewsAt;

  /// When a cancelled subscription stops. The term already paid for is not
  /// cut short, so this is a date in the future, not an ending today.
  final DateTime? endsAt;

  /// The processor's signed customer portal, where the owner cancels, resumes
  /// or changes the card. Expires, so it is fetched per visit, never stored.
  final Uri? managementUrl;

  bool get isCancelled => status == 'cancelled';
}

class BillingShops {
  const BillingShops({
    required this.shops,
    required this.cardPayment,
    required this.mmqrPayment,
  });

  final List<Map<String, dynamic>> shops;

  /// Whether the server can take an international card payment right now.
  /// False on a project with no processor secrets — and on one whose test-mode
  /// configuration is not allowed, so a misconfiguration hides the option
  /// instead of offering a checkout that refuses itself.
  final bool cardPayment;

  /// Whether the server can issue an MMQR right now. Same rule as
  /// [cardPayment]: absent means no, so an older function cannot make the page
  /// offer a QR it has no keys to produce.
  final bool mmqrPayment;
}

/// A live MMQR order: the EMVCo string to render, and when our own window
/// closes. MMPay publishes no expiry of its own — `status` is its authority —
/// so [expiresAt] is the 15-minute window the compliance rules require a
/// visible timer for.
class MmqrOrder {
  const MmqrOrder({
    required this.orderId,
    required this.qr,
    required this.amount,
    required this.expiresAt,
  });

  factory MmqrOrder.fromMap(Map<String, dynamic> data) {
    final qr = data['qr'];
    final orderId = data['order_id'];
    final rawExpiry = data['expires_at'];
    final expiresAt = rawExpiry is String ? DateTime.tryParse(rawExpiry) : null;
    if (qr is! String || qr.isEmpty || orderId is! String || expiresAt == null) {
      throw const FormatException('Missing MMQR order');
    }
    return MmqrOrder(
      orderId: orderId,
      qr: qr,
      amount: (data['amount'] as num?)?.toInt() ?? 0,
      expiresAt: expiresAt.toUtc(),
    );
  }

  final String orderId;

  /// The EMVCo MMQR payload. Rendered as a QR code and never altered —
  /// MMPay's compliance rules forbid modifying it.
  final String qr;

  /// Always MMK. The surface may not show any other currency beside it.
  final int amount;
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => {
    'order_id': orderId,
    'qr': qr,
    'amount': amount,
    'expires_at': expiresAt.toIso8601String(),
  };

  Duration remaining(DateTime now) {
    final left = expiresAt.difference(now.toUtc());
    return left.isNegative ? Duration.zero : left;
  }
}

/// A cached order restored after a refresh, with the shop and plan it belongs
/// to so it can never be shown against a different shop.
class MmqrCachedOrder {
  const MmqrCachedOrder({
    required this.shopId,
    required this.plan,
    required this.order,
  });

  final String shopId;
  final String plan;
  final MmqrOrder order;
}

/// Where an order stands, as MMPay itself reports it.
enum MmqrStatus { pending, success, failed, cancelled, expired, refunded;

  static MmqrStatus parse(String? raw) => switch (raw?.toUpperCase()) {
    'SUCCESS' => MmqrStatus.success,
    'FAILED' => MmqrStatus.failed,
    'CANCELLED' => MmqrStatus.cancelled,
    'EXPIRED' => MmqrStatus.expired,
    'REFUNDED' => MmqrStatus.refunded,
    _ => MmqrStatus.pending,
  };

  bool get isPaid => this == MmqrStatus.success;

  /// Terminal and unpaid: the owner may start a fresh order.
  bool get isDead =>
      this == MmqrStatus.failed ||
      this == MmqrStatus.cancelled ||
      this == MmqrStatus.expired;
}

/// The gateway cannot sell right now: not configured, or configured wrongly.
class CheckoutUnavailable implements Exception {}

class CheckoutInProgress implements Exception {}

class CheckoutAlreadySubscribed implements Exception {
  const CheckoutAlreadySubscribed(this.managementUrl);
  final Uri? managementUrl;
}

/// One renewal request as the public receipt page sees it.
///
/// [status] is the licence lifecycle (pending / fulfilled / rejected);
/// [paymentStatus] is the money lifecycle (manual / awaiting / paid / …).
/// They move independently on purpose — a gateway can confirm payment while
/// minting the licence is still in flight, and the shop needs to see that
/// rather than an unexplained "pending".
class RenewalReceipt {
  const RenewalReceipt({
    required this.invoiceNo,
    required this.shopName,
    required this.plan,
    required this.months,
    required this.amount,
    required this.status,
    required this.paymentStatus,
    required this.createdAt,
    this.method,
    this.refNo,
    this.rejectReason,
    this.paidAt,
  });

  final String invoiceNo;
  final String shopName;
  final String plan;
  final int months;
  final int amount;

  /// 'pending' | 'fulfilled' | 'rejected'
  final String status;

  /// 'manual' | 'awaiting' | 'paid' | 'failed' | 'expired'
  final String paymentStatus;

  final DateTime? createdAt;
  final String? method;
  final String? refNo;

  final String? rejectReason;
  final DateTime? paidAt;

  bool get isPending => status == 'pending';
  bool get isFulfilled => status == 'fulfilled';
  bool get isRejected => status == 'rejected';

  /// Money confirmed but the licence not minted yet — the one state that
  /// looks like a plain "pending" but is not the shop's problem to chase.
  bool get isPaidNotFulfilled => paymentStatus == 'paid' && isPending;

  static DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  factory RenewalReceipt.fromMap(Map<String, dynamic> m) => RenewalReceipt(
    invoiceNo: (m['invoice_no'] as String?) ?? '',
    shopName: (m['shop_name'] as String?) ?? '',
    plan: (m['plan'] as String?) ?? 'monthly',
    months: (m['months'] as num?)?.toInt() ?? 1,
    amount: (m['amount'] as num?)?.toInt() ?? 0,
    status: (m['status'] as String?) ?? 'pending',
    paymentStatus: (m['payment_status'] as String?) ?? 'manual',
    createdAt: _date(m['created_at']),
    method: m['method'] as String?,
    refNo: m['ref_no'] as String?,
    rejectReason: m['reject_reason'] as String?,
    paidAt: _date(m['paid_at']),
  );
}

/// What [StorefrontApi.submitLicenseRequest] hands back: the id the receipt
/// link is keyed by, and the number the shop will actually quote.
class SubmittedLicenseRequest {
  const SubmittedLicenseRequest({required this.requestId, this.invoiceNo});
  final String requestId;
  final String? invoiceNo;
}

/// One row of [StorefrontApi.fetchMyRequests] — deliberately a lighter shape
/// than [RenewalReceipt] (no `payment_proof_path`/phone/email even server-
/// side; see `handleMyRequests`'s doc comment): just enough for a history
/// list, with [id] to open the full [RenewalReceipt] on tap.
class RenewalRequestSummary {
  const RenewalRequestSummary({
    required this.id,
    required this.invoiceNo,
    required this.plan,
    required this.months,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.method,
  });

  final String id;
  final String invoiceNo;
  final String plan;
  final int months;
  final int amount;

  /// 'pending' | 'fulfilled' | 'rejected'
  final String status;
  final DateTime? createdAt;
  final String? method;

  factory RenewalRequestSummary.fromMap(Map<String, dynamic> m) =>
      RenewalRequestSummary(
        id: (m['id'] as String?) ?? '',
        invoiceNo: (m['invoice_no'] as String?) ?? '',
        plan: (m['plan'] as String?) ?? 'monthly',
        months: (m['months'] as num?)?.toInt() ?? 1,
        amount: (m['amount'] as num?)?.toInt() ?? 0,
        status: (m['status'] as String?) ?? 'pending',
        createdAt: m['created_at'] is String
            ? DateTime.tryParse(m['created_at'] as String)?.toLocal()
            : null,
        method: m['method'] as String?,
      );
}
