import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

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
    final res = await _c.functions.invoke(
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
  Future<SubmitOrderResult> submitOrder({
    required String slug,
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
    final res = await _c.functions.invoke(
      'storefront',
      body: {
        'action': 'submit_order',
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
  Future<SubmittedLicenseRequest> submitLicenseRequest({
    required String shopName,
    required String deviceId,
    String? email,
    String? phone,
    required String plan,
    required int months,
    String? method,
    required int amount,
    String? refNo,
    String? paymentProofPath,
    String? hp,
  }) async {
    final res = await _c.functions.invoke(
      'storefront',
      body: {
        'action': 'submit_license_request',
        'shop_name': shopName,
        'device_id': deviceId,
        'email': email,
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
    final res = await _c.functions.invoke(
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
  Future<List<RenewalRequestSummary>> fetchMyRequests() async {
    final res = await _c.functions.invoke(
      'storefront',
      body: {'action': 'my_requests'},
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

  /// Payment-account info (KBZPay/WavePay name+number) to show a shop owner
  /// on the /renew page — read directly from `app_config`, anon-readable
  /// (`0006_app_config.sql`), same source `VendorConfigRepository` uses on
  /// the mobile app. No Edge Function needed for a plain table read.
  Future<Map<String, String>> fetchPaymentConfig() async {
    final rows = await _c
        .from('app_config')
        .select('key, value')
        .inFilter('key', const [
          'pay.kbzpay.name',
          'pay.kbzpay.number',
          'pay.wavepay.name',
          'pay.wavepay.number',
          'price.monthly',
          'price.yearly',
        ]);
    return {
      for (final r in (rows as List))
        (r['key'] as String): (r['value'] as String? ?? ''),
    };
  }
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
    this.deviceIdTail,
    this.method,
    this.refNo,
    this.issuedKey,
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
  final String? deviceIdTail;
  final String? method;
  final String? refNo;

  /// Only ever non-null once [status] is 'fulfilled'.
  final String? issuedKey;
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
    deviceIdTail: m['device_id_tail'] as String?,
    method: m['method'] as String?,
    refNo: m['ref_no'] as String?,
    issuedKey: m['issued_key'] as String?,
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
