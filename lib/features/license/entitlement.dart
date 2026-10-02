import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'license_model.dart';
import 'license_status.dart';

/// A server-signed receipt of what a shop is entitled to.
///
/// The phone caches the plan and expiry as plain JSON, which can be edited to
/// push the expiry out. The server signs `{shop, plan, expiry, issued-at}` with
/// an Ed25519 key only it holds (`supabase/functions/_shared/entitlement.ts`);
/// Premium is only honoured when the cached license carries a receipt that
/// verifies here, and the receipt's own expiry — not the editable JSON field —
/// is what counts.
///
/// Not an offline licence code: nobody types it, and getting or renewing one
/// still needs the internet.
class Entitlement {
  const Entitlement({
    required this.shopId,
    required this.plan,
    required this.expiresAt,
    required this.issuedAt,
  });

  final String shopId;
  final LicensePlan plan;
  final DateTime expiresAt;

  /// Server clock when the receipt was signed — a trusted "now" at that moment.
  final DateTime issuedAt;

  static const prefix = 'AIOE1.';

  /// Ed25519 public key (hex). Safe to ship — it can only verify signatures.
  /// The matching private seed is the `ENTITLEMENT_SIGNING_KEY_HEX` Supabase
  /// secret and is never in the repo.
  static const publicKeyHex =
      '9f236bcfb541c39e0c89a211b04b9a8467766f332e458be1bde10593b3870958';

  /// Verifies [token] and returns its contents, or null if it is missing,
  /// malformed, or not signed by our key. [publicKeyHex] is overridable so
  /// tests can sign with their own keypair.
  static Future<Entitlement?> verify(
    String? token, {
    String? publicKeyHex,
  }) async {
    if (token == null) return null;
    final parts = token.trim().split('.');
    if (parts.length != 3 || '${parts[0]}.' != prefix) return null;
    try {
      final ok = await Ed25519().verify(
        utf8.encode('$prefix${parts[1]}'),
        signature: Signature(
          base64Url.decode(_pad(parts[2])),
          publicKey: SimplePublicKey(
            _hex(publicKeyHex ?? Entitlement.publicKeyHex),
            type: KeyPairType.ed25519,
          ),
        ),
      );
      if (!ok) return null;
      final payload =
          jsonDecode(utf8.decode(base64Url.decode(_pad(parts[1]))))
              as Map<String, dynamic>;
      final shopId = payload['shop_id'] as String?;
      final exp = payload['exp'];
      final iat = payload['iat'];
      if (shopId == null || shopId.isEmpty || exp is! int || iat is! int) {
        return null;
      }
      return Entitlement(
        shopId: shopId,
        plan: _plan(payload['plan'] as String?),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true),
        issuedAt: DateTime.fromMillisecondsSinceEpoch(iat * 1000, isUtc: true),
      );
    } catch (_) {
      return null;
    }
  }

  static LicensePlan _plan(String? s) => switch (s) {
        'yearly' => LicensePlan.yearly,
        'monthly' => LicensePlan.monthly,
        'free' => LicensePlan.free,
        _ => LicensePlan.trial,
      };

  static String _pad(String s) => s + '=' * ((4 - s.length % 4) % 4);

  static List<int> _hex(String h) => [
        for (var i = 0; i < h.length; i += 2)
          int.parse(h.substring(i, i + 2), radix: 16),
      ];
}

/// What the app should believe about a cached license once its receipt has
/// been checked.
class ResolvedEntitlement {
  const ResolvedEntitlement({required this.license, required this.entitled});

  /// The cached license, with its plan/expiry replaced by the receipt's when
  /// there is one. Identity (key, shop) is never touched.
  final CachedLicense license;

  /// False when a paid/trial plan has no receipt that verifies — Premium stays
  /// locked (selling is unaffected) until the next online check brings one.
  final bool entitled;
}

/// Decides whether [cached] may be honoured as Premium.
///
/// * Free needs no receipt — it grants nothing.
/// * [enforce] is false only for a build with no backend (local dev/demo),
///   where there is no server to sign anything.
/// * Otherwise the receipt must verify AND be for this shop; then its own
///   plan and expiry override whatever the editable cache says.
ResolvedEntitlement resolveEntitlement({
  required CachedLicense cached,
  required Entitlement? entitlement,
  required bool enforce,
}) {
  if (cached.plan == LicensePlan.free || !enforce) {
    return ResolvedEntitlement(license: cached, entitled: true);
  }
  if (entitlement == null || entitlement.shopId != cached.shopId) {
    return ResolvedEntitlement(license: cached, entitled: false);
  }
  return ResolvedEntitlement(
    license: cached.copyWith(
      plan: entitlement.plan,
      expiresAt: entitlement.expiresAt,
    ),
    entitled: true,
  );
}

/// The clock the license check runs on, plus the state to persist.
class TrustedTime {
  const TrustedTime({
    required this.now,
    required this.lastSeen,
    required this.lastReceiptIssuedAt,
  });
  final DateTime now;
  final DateTime lastSeen;
  final DateTime? lastReceiptIssuedAt;
}

/// A clock that can't be wound back.
///
/// Rolling the phone's date back would otherwise make an expired license look
/// current, so time only moves forward: `now = max(device clock, last time we
/// saw)`. The one thing allowed to move it back is a **newer** server receipt
/// (its `iat` is later than any receipt seen before) — that is a trusted
/// reading, and it is what un-sticks a phone whose clock was once set too far
/// ahead. A replayed old receipt has an old `iat` and resets nothing.
///
/// This stops a shopkeeper changing the date in Settings; it is not meant to
/// stop someone who can edit the app's own storage (they can clear [lastSeen]).
TrustedTime resolveTrustedTime({
  required DateTime deviceNow,
  required DateTime? lastSeen,
  required DateTime? lastReceiptIssuedAt,
  required Entitlement? entitlement,
}) {
  final fresh = entitlement != null &&
      (lastReceiptIssuedAt == null ||
          entitlement.issuedAt.isAfter(lastReceiptIssuedAt));
  if (fresh) {
    return TrustedTime(
      now: entitlement.issuedAt,
      lastSeen: entitlement.issuedAt,
      lastReceiptIssuedAt: entitlement.issuedAt,
    );
  }
  final floor = lastSeen ?? deviceNow;
  final now = deviceNow.isAfter(floor) ? deviceNow : floor;
  return TrustedTime(
    now: now,
    lastSeen: now,
    lastReceiptIssuedAt: lastReceiptIssuedAt,
  );
}
