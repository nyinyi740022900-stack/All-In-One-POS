import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/image_util.dart';
import '../../data/sync/outbox_error.dart';

/// Public base URL where the storefront web app is hosted. A shop's page is
/// `$storefrontBaseUrl/<slug>`.
const storefrontBaseUrl = 'https://allinonepos-shop.vercel.app';

/// OG preview URL for Facebook/Viber crawlers (Edge Function HTML card).
String storefrontOgUrl(String slug) {
  final base = Env.supabaseUrl.replaceAll(RegExp(r'/+$'), '');
  return '$base/functions/v1/storefront?action=og&slug=${Uri.encodeComponent(slug)}';
}

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
  final bool hoursEnabled;
  final int? openMinute;
  final int? closeMinute;
  final bool requireTransferProof;

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
    this.hoursEnabled = false,
    this.openMinute,
    this.closeMinute,
    this.requireTransferProof = true,
  });

  String get url => '$storefrontBaseUrl/$slug';

  static StorefrontRow fromMap(Map<String, dynamic> m) => StorefrontRow(
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
    hoursEnabled: m['hours_enabled'] as bool? ?? false,
    openMinute: (m['open_minute'] as num?)?.toInt(),
    closeMinute: (m['close_minute'] as num?)?.toInt(),
    requireTransferProof: m['require_transfer_proof'] as bool? ?? true,
  );
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
    return StorefrontRow.fromMap(m);
  }

  /// Publishes (creates) the storefront if absent, generating a slug from the
  /// shop name; returns the row. If one already exists, re-enables it.
  Future<StorefrontRow> publish({
    required String displayName,
    String? phone,
    String? address,
  }) {
    return _withRlsRetry(
      () => _publishImpl(
        displayName: displayName,
        phone: phone,
        address: address,
      ),
    );
  }

  Future<StorefrontRow> _publishImpl({
    required String displayName,
    String? phone,
    String? address,
  }) async {
    final existing = await mine();
    if (existing != null) {
      await _c
          .from('storefronts')
          .update({'enabled': true})
          .eq('shop_id', _shopId);
      return (await mine())!;
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
    return (await mine())!;
  }

  Future<void> setEnabled(bool enabled) {
    return _withRlsRetry(
      () => _c
          .from('storefronts')
          .update({'enabled': enabled})
          .eq('shop_id', _shopId),
    );
  }

  /// A freshly-granted shop_id claim (e.g. self-serve trial, sign-in) can lag
  /// behind on an already-cached Supabase session until it next auto-refreshes,
  /// making an otherwise-correct write fail RLS (`42501`) with no obvious way
  /// for the caller to recover. Retry once after forcing a session refresh,
  /// so a stale JWT self-heals instead of surfacing as a dead-end error.
  Future<T> _withRlsRetry<T>(Future<T> Function() op) async {
    try {
      return await op();
    } catch (e) {
      if (classifyOutboxError(e.toString()) != OutboxErrorClass.rls42501) {
        rethrow;
      }
      try {
        await _c.auth.refreshSession();
      } catch (_) {
        throw e;
      }
      return await op();
    }
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
    bool? hoursEnabled,
    int? openMinute,
    int? closeMinute,
    bool? requireTransferProof,
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
      'hours_enabled': ?hoursEnabled,
      'open_minute': ?openMinute,
      'close_minute': ?closeMinute,
      'require_transfer_proof': ?requireTransferProof,
    };
    if (patch.isEmpty) return;
    await _withRlsRetry(
      () => _c.from('storefronts').update(patch).eq('shop_id', _shopId),
    );
  }

  /// Uploads a logo image to the shared public product-images bucket and
  /// returns its public URL.
  Future<String> uploadLogo(List<int> bytes, String ext) async {
    final c = await compressImage(Uint8List.fromList(bytes), fallbackExt: ext);
    final path =
        'logo-$_shopId-${DateTime.now().millisecondsSinceEpoch}.${c.ext}';
    final storage = _c.storage.from('product-images');
    await storage.uploadBinary(
      path,
      c.bytes,
      fileOptions: const FileOptions(upsert: true),
    );
    return storage.getPublicUrl(path);
  }

  Future<List<BlockedCustomer>> listBlocked() async {
    final rows =
        await _c
                .from('storefront_blocklist')
                .select()
                .eq('shop_id', _shopId)
                .order('created_at', ascending: false)
            as List;
    return rows
        .map((e) => (e as Map).cast<String, dynamic>())
        .map(
          (m) => BlockedCustomer(m['phone'] as String, m['reason'] as String?),
        )
        .toList();
  }

  /// Blocks [phone] from placing new storefront orders on this shop. Blocking
  /// the same number twice is a no-op (upsert on the shop_id+phone unique
  /// index) rather than an error.
  Future<void> block(String phone, {String? reason}) {
    return _withRlsRetry(
      () => _c.from('storefront_blocklist').upsert({
        'shop_id': _shopId,
        'phone': phone,
        'reason': reason,
      }, onConflict: 'shop_id,phone'),
    );
  }

  Future<void> unblock(String phone) {
    return _withRlsRetry(
      () => _c
          .from('storefront_blocklist')
          .delete()
          .eq('shop_id', _shopId)
          .eq('phone', phone),
    );
  }
}
