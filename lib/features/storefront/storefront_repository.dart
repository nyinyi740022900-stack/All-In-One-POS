import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/image_util.dart';
import '../../data/sync/outbox_error.dart';

/// Public base URL where the storefront web app is hosted. A shop's page is
/// `$storefrontBaseUrl/<slug>`.
const storefrontBaseUrl = 'https://shop.allinonepos.app';

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

/// Canonical form for storefront block-list matching: strip spaces/dashes,
/// then map `+959` / `959` / a leading `9` onto local `09…`.
String normalizeStorefrontPhone(String raw) {
  var v = raw.trim().replaceAll(RegExp(r'[\s-]'), '');
  if (v.startsWith('+959')) {
    v = '09${v.substring(4)}';
  } else if (v.startsWith('959')) {
    v = '09${v.substring(3)}';
  } else if (v.startsWith('9') && !v.startsWith('09')) {
    v = '0$v';
  }
  return v;
}

final _ipv4 = RegExp(r'^(\d{1,3}(?:\.\d{1,3}){3})(?::\d+)?$');
final _bracketedIpv6 = RegExp(r'^\[([0-9a-f:.]+)\](?::\d+)?$');
final _embeddedIpv4 = RegExp(r'^(.*):(\d{1,3}(?:\.\d{1,3}){3})$');

/// Canonical client IP for storefront block-list matching. Uses only the
/// last `X-Forwarded-For` hop (the one the last trusted proxy added), strips
/// a `:port` (IPv4) or `[addr]:port` (IPv6), canonicalizes IPv6 (RFC 5952).
/// Empty for blank / `unknown` / private / loopback / garbage so those cannot
/// land on the block-list. Does not walk left into client-supplied hops.
String normalizeStorefrontIp(String raw) {
  final hops = raw
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (hops.isEmpty) return '';
  final n = _normalizeOneHop(hops.last);
  if (n.isEmpty || _isNonPublicIp(n)) return '';
  return n;
}

String _normalizeOneHop(String raw) {
  var v = raw.trim().toLowerCase();
  if (v.isEmpty || v == 'unknown' || v == 'null') return '';

  final bracket = _bracketedIpv6.firstMatch(v);
  if (bracket != null) v = bracket.group(1)!;

  final v4 = _ipv4.firstMatch(v);
  if (v4 != null) {
    final ip = v4.group(1)!;
    if (!_validIpv4(ip)) return '';
    if (ip == '0.0.0.0' || ip.startsWith('127.')) return '';
    return ip;
  }

  final groups = _parseIpv6Groups(v);
  if (groups == null) return '';
  if (groups.every((g) => g == 0)) return '';
  if (groups.length == 8 &&
      groups[0] == 0 &&
      groups[1] == 0 &&
      groups[2] == 0 &&
      groups[3] == 0 &&
      groups[4] == 0 &&
      groups[5] == 0 &&
      groups[6] == 0 &&
      groups[7] == 1) {
    return '';
  }
  final mappedV4 = _ipv4FromIpv6(groups);
  if (mappedV4 != null) {
    if (!_validIpv4(mappedV4)) return '';
    if (mappedV4 == '0.0.0.0' || mappedV4.startsWith('127.')) return '';
    return mappedV4;
  }
  return _canonicalIpv6(groups);
}

bool _isNonPublicIp(String ip) {
  if (ip.contains('.')) return _isNonPublicIpv4(ip);
  return _isNonPublicIpv6(ip);
}

bool _isNonPublicIpv4(String ip) {
  final p = ip.split('.').map(int.parse).toList();
  if (p.length != 4) return true;
  final a = p[0];
  final b = p[1];
  if (a == 10) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  if (a == 192 && b == 168) return true;
  if (a == 169 && b == 254) return true;
  return false;
}

bool _isNonPublicIpv6(String ip) {
  final g = _parseIpv6Groups(ip);
  if (g == null || g.length != 8) return true;
  if (g[0] & 0xffc0 == 0xfe80) return true; // link-local
  if (g[0] & 0xfe00 == 0xfc00) return true; // unique local
  return false;
}

bool _validIpv4(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return false;
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return false;
    if (p.length > 1 && p.startsWith('0')) return false;
  }
  return true;
}

/// Eight 16-bit groups, or null if [s] is not a valid IPv6 textual form.
/// Accepts IPv4-embedded tails (`::ffff:192.0.2.1`).
List<int>? _parseIpv6Groups(String s) {
  if (s.isEmpty || s.contains(':::')) return null;
  String head = s;
  String? dotted;
  if (s.contains('.')) {
    final embedded = _embeddedIpv4.firstMatch(s);
    if (embedded == null) return null;
    head = embedded.group(1)!;
    dotted = embedded.group(2)!;
    if (head == ':') head = '::';
    if (!_validIpv4(dotted)) return null;
  }
  final prefix = _parseIpv6N(head, dotted == null ? 8 : 6);
  if (prefix == null) return null;
  if (dotted == null) return prefix;
  final o = dotted.split('.').map(int.parse).toList();
  return [...prefix, (o[0] << 8) | o[1], (o[2] << 8) | o[3]];
}

List<int>? _parseIpv6N(String s, int n) {
  final sides = s.split('::');
  if (sides.length > 2) return null;

  List<int>? parseSide(String side) {
    if (side.isEmpty) return [];
    final parts = side.split(':');
    final out = <int>[];
    for (final p in parts) {
      if (p.isEmpty || p.length > 4 || !RegExp(r'^[0-9a-f]+$').hasMatch(p)) {
        return null;
      }
      out.add(int.parse(p, radix: 16));
    }
    return out;
  }

  if (sides.length == 1) {
    final g = parseSide(s);
    if (g == null || g.length != n) return null;
    return g;
  }
  final left = parseSide(sides[0]);
  final right = parseSide(sides[1]);
  if (left == null || right == null) return null;
  final missing = n - left.length - right.length;
  if (missing < 1) return null;
  return [...left, ...List.filled(missing, 0), ...right];
}

/// IPv4-mapped (`::ffff:a.b.c.d`) or IPv4-compatible (`::a.b.c.d`, not ::/::1).
String? _ipv4FromIpv6(List<int> g) {
  if (g.length != 8) return null;
  if (g[0] != 0 || g[1] != 0 || g[2] != 0 || g[3] != 0 || g[4] != 0) {
    return null;
  }
  final mapped = g[5] == 0xffff;
  final compatible = g[5] == 0;
  if (!mapped && !compatible) return null;
  if (compatible && g[6] == 0 && g[7] <= 1) return null;
  final a = (g[6] >> 8) & 0xff;
  final b = g[6] & 0xff;
  final c = (g[7] >> 8) & 0xff;
  final d = g[7] & 0xff;
  return '$a.$b.$c.$d';
}

/// RFC 5952: lowercase hex, no leading zeros, `::` for the longest zero run
/// of 2+ groups (leftmost on a tie).
String _canonicalIpv6(List<int> g) {
  var bestStart = -1;
  var bestLen = 0;
  var i = 0;
  while (i < 8) {
    if (g[i] != 0) {
      i++;
      continue;
    }
    var j = i;
    while (j < 8 && g[j] == 0) {
      j++;
    }
    final len = j - i;
    if (len > bestLen) {
      bestStart = i;
      bestLen = len;
    }
    i = j;
  }
  String hex(int n) => n.toRadixString(16);
  if (bestLen < 2) return g.map(hex).join(':');
  final left = g.sublist(0, bestStart).map(hex).join(':');
  final right = g.sublist(bestStart + bestLen).map(hex).join(':');
  if (left.isEmpty) return '::$right';
  if (right.isEmpty) return '$left::';
  return '$left::$right';
}

/// An IP the owner has blocked from placing new storefront orders,
/// usually after a scam/spam order.
class BlockedCustomer {
  final String ip;
  final String? reason;
  const BlockedCustomer(this.ip, this.reason);
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
          (m) => BlockedCustomer(
            (m['ip'] as String?) ?? '',
            m['reason'] as String?,
          ),
        )
        .where((b) => b.ip.isNotEmpty)
        .toList();
  }

  /// Returns `false` when [ip] could not be normalized to a blockable
  /// address (nothing was written) so callers can tell success apart
  /// from a no-op. Blocking the same address twice is still a no-op
  /// upsert (returns `true`).
  Future<bool> block(String ip, {String? reason}) {
    final normalized = normalizeStorefrontIp(ip);
    if (normalized.isEmpty) return Future.value(false);
    return _withRlsRetry(() async {
      await _c.from('storefront_blocklist').upsert({
        'shop_id': _shopId,
        'ip': normalized,
        'reason': reason,
      }, onConflict: 'shop_id,ip');
      return true;
    });
  }

  Future<void> unblock(String ip) {
    final normalized = normalizeStorefrontIp(ip);
    return _withRlsRetry(() async {
      await _c
          .from('storefront_blocklist')
          .delete()
          .eq('shop_id', _shopId)
          .eq('ip', ip);
      if (normalized.isNotEmpty && normalized != ip) {
        await _c
            .from('storefront_blocklist')
            .delete()
            .eq('shop_id', _shopId)
            .eq('ip', normalized);
      }
    });
  }
}
