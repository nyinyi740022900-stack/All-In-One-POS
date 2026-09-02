import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../data/repositories/settings_repository.dart';

/// Vendor (company) info shown to shops: where to send license-renewal
/// payments and how to reach support. Sourced from the backend `app_config`
/// table and cached locally so it works offline.
class VendorConfig {
  final String kbzName;
  final String kbzNumber;
  final String waveName;
  final String waveNumber;
  final String supportViber;
  final int priceMonthly;
  final int priceYearly;
  final int priceMonthlyOnline;
  final int priceYearlyOnline;
  final int deviceFreeLimit;
  final int deviceExtraFee;

  /// Lemon Squeezy store subdomain + variant ids for the international
  /// (non-Myanmar) in-app subscribe path — see `_PurchasePaths` in
  /// `license_widgets.dart`. Empty until the owner sets them from the
  /// admin console's Config tab.
  final String lemonSqueezyStoreSlug;
  final String lemonSqueezyVariantMonthly;
  final String lemonSqueezyVariantYearly;

  const VendorConfig({
    this.kbzName = '',
    this.kbzNumber = '',
    this.waveName = '',
    this.waveNumber = '',
    this.supportViber = '',
    this.priceMonthly = 0,
    this.priceYearly = 0,
    this.priceMonthlyOnline = 0,
    this.priceYearlyOnline = 0,
    this.deviceFreeLimit = 3,
    this.deviceExtraFee = 0,
    this.lemonSqueezyStoreSlug = '',
    this.lemonSqueezyVariantMonthly = '',
    this.lemonSqueezyVariantYearly = '',
  });

  bool get hasKbz => kbzNumber.isNotEmpty;
  bool get hasWave => waveNumber.isNotEmpty;
  bool get hasSupport => supportViber.isNotEmpty;
  bool get hasLemonSqueezy =>
      lemonSqueezyStoreSlug.isNotEmpty &&
      lemonSqueezyVariantMonthly.isNotEmpty &&
      lemonSqueezyVariantYearly.isNotEmpty;

  /// [tier] is the shop's own `CachedLicense.tier` ('offline'/'online'),
  /// fixed at shop-creation time — see `CachedLicense.tier`. Online prices
  /// default to the offline ones until an admin explicitly sets a distinct
  /// `price.monthly.online`/`price.yearly.online`, so behavior is unchanged
  /// until that's configured.
  int priceFor(String plan, {String tier = 'offline'}) {
    if (tier == 'online') {
      return plan == 'yearly' ? priceYearlyOnline : priceMonthlyOnline;
    }
    return plan == 'yearly' ? priceYearly : priceMonthly;
  }

  factory VendorConfig.fromMap(Map<String, String> m) {
    final priceMonthly = int.tryParse(m['price.monthly'] ?? '') ?? 0;
    final priceYearly = int.tryParse(m['price.yearly'] ?? '') ?? 0;
    return VendorConfig(
      kbzName: m['pay.kbzpay.name'] ?? '',
      kbzNumber: m['pay.kbzpay.number'] ?? '',
      waveName: m['pay.wavepay.name'] ?? '',
      waveNumber: m['pay.wavepay.number'] ?? '',
      supportViber: m['support.viber'] ?? '',
      priceMonthly: priceMonthly,
      priceYearly: priceYearly,
      priceMonthlyOnline:
          int.tryParse(m['price.monthly.online'] ?? '') ?? priceMonthly,
      priceYearlyOnline:
          int.tryParse(m['price.yearly.online'] ?? '') ?? priceYearly,
      deviceFreeLimit: int.tryParse(m['device.free_limit'] ?? '') ?? 3,
      deviceExtraFee: int.tryParse(m['device.extra_fee'] ?? '') ?? 0,
      lemonSqueezyStoreSlug: m['pay.lemonsqueezy.store_slug'] ?? '',
      lemonSqueezyVariantMonthly: m['pay.lemonsqueezy.variant_monthly'] ?? '',
      lemonSqueezyVariantYearly: m['pay.lemonsqueezy.variant_yearly'] ?? '',
    );
  }

  Map<String, String> toMap() => {
        'pay.kbzpay.name': kbzName,
        'pay.kbzpay.number': kbzNumber,
        'pay.wavepay.name': waveName,
        'pay.wavepay.number': waveNumber,
        'support.viber': supportViber,
        'price.monthly': '$priceMonthly',
        'price.yearly': '$priceYearly',
        'price.monthly.online': '$priceMonthlyOnline',
        'price.yearly.online': '$priceYearlyOnline',
        'device.free_limit': '$deviceFreeLimit',
        'device.extra_fee': '$deviceExtraFee',
        'pay.lemonsqueezy.store_slug': lemonSqueezyStoreSlug,
        'pay.lemonsqueezy.variant_monthly': lemonSqueezyVariantMonthly,
        'pay.lemonsqueezy.variant_yearly': lemonSqueezyVariantYearly,
      };

  static const empty = VendorConfig();
}

class VendorConfigRepository {
  VendorConfigRepository(this._settings);

  final SettingsRepository _settings;

  /// Returns the cached config immediately usable, refreshing from the backend
  /// in the background when online. Online failures fall back to the cache.
  Future<VendorConfig> load() async {
    if (Env.hasBackend) {
      try {
        final rows = await Supabase.instance.client
            .from('app_config')
            .select('key, value');
        final map = <String, String>{
          for (final r in (rows as List))
            (r['key'] as String): (r['value'] as String? ?? ''),
        };
        final cfg = VendorConfig.fromMap(map);
        await _settings.setVendorConfigJson(jsonEncode(cfg.toMap()));
        return cfg;
      } catch (_) {
        // fall through to cache
      }
    }
    final raw = await _settings.vendorConfigJson();
    if (raw != null) {
      try {
        final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
        return VendorConfig.fromMap(
            m.map((k, v) => MapEntry(k, '${v ?? ''}')));
      } catch (_) {}
    }
    return VendorConfig.empty;
  }
}
