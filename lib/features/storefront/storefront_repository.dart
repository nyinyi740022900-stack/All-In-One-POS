import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/image_util.dart';

/// Public base URL where the storefront web app is hosted. A shop's page is
/// `$storefrontBaseUrl/<slug>`.
const storefrontBaseUrl = 'https://goldposmm-shop.vercel.app';

/// The shop's own storefront config (online-only; not part of Drift/sync).
class StorefrontRow {
  final String slug;
  final String? displayName;
  final String? phone;
  final String? address;
  final String? logoUrl;
  final String? payKpay;
  final String? payKpayName;
  final String? payWave;
  final String? payWaveName;
  final bool enabled;
  const StorefrontRow({
    required this.slug,
    this.displayName,
    this.phone,
    this.address,
    this.logoUrl,
    this.payKpay,
    this.payKpayName,
    this.payWave,
    this.payWaveName,
    this.enabled = true,
  });

  String get url => '$storefrontBaseUrl/$slug';
}

/// A phone number the owner has blocked from placing new storefront orders,
/// usually after a scam/spam order.
class BlockedCustomer {
  final String phone;
  final String? reason;
  const BlockedCustomer(this.phone, this.reason);
}

/// Manages the signed-in shop's storefront row. All access is RLS-scoped to the
/// caller's own `shop_id` (policy `storefront_owner`). Online-only.
class StorefrontRepository {
  StorefrontRepository(this._shopId);
  final String _shopId;
  SupabaseClient get _c => Supabase.instance.client;

  Future<StorefrontRow?> mine() async {
    final rows = await _c.from('storefronts').select() as List;
    if (rows.isEmpty) return null;
    final m = (rows.first as Map).cast<String, dynamic>();
    return StorefrontRow(
      slug: m['slug'] as String,
      displayName: m['display_name'] as String?,
      phone: m['phone'] as String?,
      address: m['address'] as String?,
      logoUrl: m['logo_url'] as String?,
      payKpay: m['pay_kpay'] as String?,
      payKpayName: m['pay_kpay_name'] as String?,
      payWave: m['pay_wave'] as String?,
      payWaveName: m['pay_wave_name'] as String?,
      enabled: m['enabled'] as bool? ?? true,
    );
  }

  /// Publishes (creates) the storefront if absent, generating a slug from the
  /// shop name; returns the row. If one already exists, re-enables it.
  Future<StorefrontRow> publish({
    required String displayName,
    String? phone,
    String? address,
  }) async {
    final existing = await mine();
    if (existing != null) {
      await _c
          .from('storefronts')
          .update({'enabled': true}).eq('shop_id', _shopId);
      return StorefrontRow(
          slug: existing.slug,
          displayName: existing.displayName,
          enabled: true);
    }
    final slug =
        await _c.rpc('gen_storefront_slug', params: {'p_name': displayName})
            as String;
    await _c.from('storefronts').insert({
      'shop_id': _shopId,
      'slug': slug,
      'display_name': displayName,
      'phone': phone,
      'address': address,
      'enabled': true,
    });
    return StorefrontRow(slug: slug, displayName: displayName, enabled: true);
  }

  Future<void> setEnabled(bool enabled) async {
    await _c
        .from('storefronts')
        .update({'enabled': enabled}).eq('shop_id', _shopId);
  }

  /// Updates display fields on an existing storefront (name/phone/address
  /// shown to customers, the logo, and the KBZPay/WavePay name+number shown
  /// at checkout). Pass only what changed; omitted fields are left as-is.
  /// Pass an empty string (not null) to clear a payment field the owner
  /// removed.
  Future<void> updateProfile({
    String? displayName,
    String? phone,
    String? address,
    String? logoUrl,
    String? payKpay,
    String? payKpayName,
    String? payWave,
    String? payWaveName,
  }) async {
    final patch = <String, dynamic>{
      'display_name': ?displayName,
      'phone': ?phone,
      'address': ?address,
      'logo_url': ?logoUrl,
      'pay_kpay': ?payKpay,
      'pay_kpay_name': ?payKpayName,
      'pay_wave': ?payWave,
      'pay_wave_name': ?payWaveName,
    };
    if (patch.isEmpty) return;
    await _c.from('storefronts').update(patch).eq('shop_id', _shopId);
  }

  /// Uploads a logo image to the shared public product-images bucket and
  /// returns its public URL.
  Future<String> uploadLogo(List<int> bytes, String ext) async {
    final c = compressImage(Uint8List.fromList(bytes), fallbackExt: ext);
    final path =
        'logo-$_shopId-${DateTime.now().millisecondsSinceEpoch}.${c.ext}';
    final storage = _c.storage.from('product-images');
    await storage.uploadBinary(path, c.bytes,
        fileOptions: const FileOptions(upsert: true));
    return storage.getPublicUrl(path);
  }

  Future<List<BlockedCustomer>> listBlocked() async {
    final rows = await _c
        .from('storefront_blocklist')
        .select()
        .eq('shop_id', _shopId)
        .order('created_at', ascending: false) as List;
    return rows
        .map((e) => (e as Map).cast<String, dynamic>())
        .map((m) => BlockedCustomer(m['phone'] as String, m['reason'] as String?))
        .toList();
  }

  /// Blocks [phone] from placing new storefront orders on this shop. Blocking
  /// the same number twice is a no-op (upsert on the shop_id+phone unique
  /// index) rather than an error.
  Future<void> block(String phone, {String? reason}) async {
    await _c.from('storefront_blocklist').upsert({
      'shop_id': _shopId,
      'phone': phone,
      'reason': reason,
    }, onConflict: 'shop_id,phone');
  }

  Future<void> unblock(String phone) async {
    await _c
        .from('storefront_blocklist')
        .delete()
        .eq('shop_id', _shopId)
        .eq('phone', phone);
  }
}
