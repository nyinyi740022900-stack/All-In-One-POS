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
  /// The shop's tenant id. Not a secret (RLS gates every read) — the guest
  /// checkout needs it to upload the payment proof into the shop's own
  /// `{shop_id}/` bucket folder, which is what the read policy (migration
  /// 0066) scopes visibility to.
  final String shopId;
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
    required this.shopId,
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
        shopId: s['shop_id'] as String? ?? '',
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

  /// Submits a subscription-renewal request from the /renew page — the shop
  /// owner identifies themselves by [deviceId] (their own "App Reference
  /// ID"), not a slug or session. Reviewed by the admin in the Requests tab.
  /// Returns the new `license_requests` row's id — a reference number the
  /// page can show the owner, mirroring [submitOrder]'s `order_no`.
  Future<String> submitLicenseRequest({
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
    final res = await _c.functions.invoke('storefront', body: {
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
    });
    if (res.status != 200 || (res.data is Map && res.data['ok'] != true)) {
      throw Exception(res.data is Map ? res.data['error'] : 'error');
    }
    return (res.data as Map)['request_id'] as String? ?? '';
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
