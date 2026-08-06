import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

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
  const StoreProduct(this.id, this.name, this.price, this.unit, this.imageUrl,
      {this.onlineAvailable});
}

/// Public shop info + payment numbers shown to customers.
class StoreInfo {
  final String? displayName;
  final String? phone;
  final String? address;
  final String? payKpay;
  final String? payKpayName;
  final String? payWave;
  final String? payWaveName;
  final String? logoUrl;
  final bool acceptingOrders;
  final bool requireTransferProof;
  final bool hoursEnabled;
  final int? openMinute;
  final int? closeMinute;

  const StoreInfo({
    this.displayName,
    this.phone,
    this.address,
    this.payKpay,
    this.payKpayName,
    this.payWave,
    this.payWaveName,
    this.logoUrl,
    this.acceptingOrders = true,
    this.requireTransferProof = true,
    this.hoursEnabled = false,
    this.openMinute,
    this.closeMinute,
  });
}

class Catalog {
  final StoreInfo info;
  final List<StoreProduct> products;
  const Catalog(this.info, this.products);
}

/// One line the customer wants to order.
class OrderLine {
  final String productId;
  final String name;
  final int price;
  final int qty;
  const OrderLine(this.productId, this.name, this.price, this.qty);
}

/// Talks to the `storefront` Edge Function. The browser only ever holds the
/// anon key; the function reads/writes across RLS with the service role.
class StorefrontApi {
  SupabaseClient get _c => Supabase.instance.client;

  Future<Catalog> fetchCatalog(String slug) async {
    final res = await _c.functions
        .invoke('storefront', body: {'action': 'catalog', 'slug': slug});
    if (res.status != 200) {
      throw Exception(res.data is Map ? res.data['error'] : 'error');
    }
    final data = (res.data as Map).cast<String, dynamic>();
    final s = (data['storefront'] as Map).cast<String, dynamic>();
    final products = (data['products'] as List)
        .map((e) => (e as Map).cast<String, dynamic>())
        .map((m) => StoreProduct(
              m['id'] as String,
              m['name'] as String,
              (m['sale_price'] as num?)?.toInt() ?? 0,
              (m['unit'] as String?) ?? 'pcs',
              m['image_url'] as String?,
              onlineAvailable: (m['online_available'] as num?)?.toInt(),
            ))
        .toList();
    return Catalog(
      StoreInfo(
        displayName: s['display_name'] as String?,
        phone: s['phone'] as String?,
        address: s['address'] as String?,
        payKpay: s['pay_kpay'] as String?,
        payKpayName: s['pay_kpay_name'] as String?,
        payWave: s['pay_wave'] as String?,
        payWaveName: s['pay_wave_name'] as String?,
        logoUrl: s['logo_url'] as String?,
        acceptingOrders: s['accepting_orders'] as bool? ?? true,
        requireTransferProof: s['require_transfer_proof'] as bool? ?? true,
        hoursEnabled: s['hours_enabled'] as bool? ?? false,
        openMinute: (s['open_minute'] as num?)?.toInt(),
        closeMinute: (s['close_minute'] as num?)?.toInt(),
      ),
      products,
    );
  }

  /// Uploads a payment screenshot to the private `payment-proofs` bucket and
  /// returns its storage path (to attach to the order). Anon uploads are
  /// allowed by policy; reads happen later via signed URLs on the shop side.
  Future<String> uploadPaymentProof(List<int> bytes, String ext) async {
    final path =
        'proof-${DateTime.now().millisecondsSinceEpoch}-${bytes.length}.$ext';
    await _c.storage.from('payment-proofs').uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: const FileOptions(upsert: false),
        );
    return path;
  }

  /// Submits a guest order. [paymentMethod] is `'transfer'` (KPay/Wave,
  /// usually with a screenshot) or `'cod'` (cash on delivery) — the shop sees
  /// a different workflow cue for each. Returns the order number.
  Future<String> submitOrder({
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
    final res = await _c.functions.invoke('storefront', body: {
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
          }
      ],
    });
    if (res.status != 200 || (res.data is Map && res.data['ok'] != true)) {
      throw Exception(res.data is Map ? res.data['error'] : 'error');
    }
    return (res.data as Map)['order_no'] as String;
  }
}
