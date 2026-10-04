import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/license/entitlement.dart';
import 'package:mm_pos/features/license/license_model.dart';
import 'package:mm_pos/features/license/license_status.dart';

String _b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');

/// Signs a receipt the way `_shared/entitlement.ts` does, with a test keypair.
Future<({String token, String pubHex})> _sign({
  String shopId = 'shop-1',
  String plan = 'monthly',
  int exp = 2000000000,
  int iat = 1700000000,
  int version = 2,
  String userId = 'u',
  String deviceId = 'd',
  int revision = 3,
}) async {
  final kp = await Ed25519().newKeyPair();
  final pub = (await kp.extractPublicKey()).bytes;
  final payload = _b64(
    utf8.encode(
      jsonEncode({
        'v': version,
        'shop_id': shopId,
        'user_id': userId,
        'device_id': deviceId,
        'revision': revision,
        'plan': plan,
        'exp': exp,
        'iat': iat,
      }),
    ),
  );
  final sig = await Ed25519().sign(
    utf8.encode('${Entitlement.prefix}$payload'),
    keyPair: kp,
  );
  return (
    token: '${Entitlement.prefix}$payload.${_b64(sig.bytes)}',
    pubHex: pub.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
  );
}

CachedLicense _cached({
  String shopId = 'shop-1',
  LicensePlan plan = LicensePlan.monthly,
  DateTime? expiresAt,
}) => CachedLicense(
  key: 'k',
  shopId: shopId,
  plan: plan,
  expiresAt: expiresAt ?? DateTime.utc(2030),
  activatedAt: DateTime.utc(2026),
  lastVerifiedAt: DateTime.utc(2026),
  deviceId: 'd',
);

void main() {
  group('Entitlement.verify', () {
    test('rejects legacy, unsupported and unbound signed receipts', () async {
      for (final args in [
        await _sign(version: 1),
        await _sign(version: 3),
        await _sign(userId: ''),
        await _sign(deviceId: ''),
        await _sign(plan: 'unknown'),
        await _sign(revision: -1),
      ]) {
        expect(
          await Entitlement.verify(args.token, publicKeyHex: args.pubHex),
          isNull,
        );
      }
    });

    test('accepts a receipt signed by the matching key', () async {
      final s = await _sign();
      final e = await Entitlement.verify(s.token, publicKeyHex: s.pubHex);
      expect(e, isNotNull);
      expect(e!.shopId, 'shop-1');
      expect(e.plan, LicensePlan.monthly);
      expect(e.expiresAt.millisecondsSinceEpoch, 2000000000 * 1000);
      expect(e.issuedAt.millisecondsSinceEpoch, 1700000000 * 1000);
    });

    test('rejects a receipt signed by a different key', () async {
      final s = await _sign();
      final other = await _sign();
      expect(
        await Entitlement.verify(s.token, publicKeyHex: other.pubHex),
        isNull,
      );
    });

    test('rejects a payload edited after signing (extended expiry)', () async {
      final s = await _sign(exp: 1800000000);
      final parts = s.token.split('.');
      final forged = _b64(
        utf8.encode(
          jsonEncode({
            'v': 1,
            'shop_id': 'shop-1',
            'plan': 'monthly',
            'exp': 9999999999,
            'iat': 1700000000,
          }),
        ),
      );
      final tampered = '${parts[0]}.$forged.${parts[2]}';
      expect(
        await Entitlement.verify(tampered, publicKeyHex: s.pubHex),
        isNull,
      );
    });

    test(
      'rejects null, empty, wrong prefix and garbage without throwing',
      () async {
        for (final t in [
          null,
          '',
          'MMPOS1.a.b',
          'AIOE1.',
          'AIOE1.x.y',
          'nope',
        ]) {
          expect(await Entitlement.verify(t), isNull, reason: '$t');
        }
      },
    );

    test('the shipped key does not verify a receipt from a test key', () async {
      expect((await _sign()).token.isNotEmpty, isTrue);
      expect(await Entitlement.verify((await _sign()).token), isNull);
    });
  });

  group('resolveEntitlement', () {
    final ent = Entitlement(
      shopId: 'shop-1',
      userId: 'u',
      deviceId: 'd',
      revision: 3,
      plan: LicensePlan.yearly,
      expiresAt: DateTime.utc(2027),
      issuedAt: DateTime.utc(2026, 10),
    );

    test('a verified receipt overrides the editable plan and expiry', () {
      final r = resolveEntitlement(
        cached: _cached(expiresAt: DateTime.utc(2099)), // edited far out
        entitlement: ent,
        enforce: true,
        userId: 'u',
        deviceId: 'd',
      );
      expect(r.entitled, isTrue);
      expect(r.license.expiresAt, DateTime.utc(2027));
      expect(r.license.plan, LicensePlan.yearly);
    });

    test('wrong user/device and older revision do not unlock Premium', () {
      for (final binding in [
        (user: 'other', device: 'd', revision: 0),
        (user: 'u', device: 'other', revision: 0),
        (user: 'u', device: 'd', revision: 4),
      ]) {
        expect(
          resolveEntitlement(
            cached: _cached(),
            entitlement: ent,
            enforce: true,
            userId: binding.user,
            deviceId: binding.device,
            highestRevision: binding.revision,
          ).entitled,
          isFalse,
        );
      }
    });
    test('no receipt on a paid plan is not entitled', () {
      final r = resolveEntitlement(
        cached: _cached(),
        entitlement: null,
        enforce: true,
        userId: 'u',
        deviceId: 'd',
      );
      expect(r.entitled, isFalse);
    });

    test("another shop's receipt is not accepted", () {
      final r = resolveEntitlement(
        cached: _cached(shopId: 'shop-2'),
        entitlement: ent,
        enforce: true,
        userId: 'u',
        deviceId: 'd',
      );
      expect(r.entitled, isFalse);
    });

    test(
      'Free needs no receipt, and a build with no backend skips the check',
      () {
        expect(
          resolveEntitlement(
            cached: _cached(plan: LicensePlan.free),
            entitlement: null,
            enforce: true,
            userId: 'u',
            deviceId: 'd',
          ).entitled,
          isTrue,
        );
        expect(
          resolveEntitlement(
            cached: _cached(),
            entitlement: null,
            enforce: false,
          ).entitled,
          isTrue,
        );
      },
    );
  });

  group('resolveTrustedTime', () {
    Entitlement receipt(DateTime iat) => Entitlement(
      shopId: 's',
      plan: LicensePlan.monthly,
      expiresAt: DateTime.utc(2030),
      issuedAt: iat,
    );

    test('winding the clock back does not move time back', () {
      final t = resolveTrustedTime(
        deviceNow: DateTime.utc(2026, 1, 1),
        lastSeen: DateTime.utc(2026, 10, 1),
        lastReceiptIssuedAt: DateTime.utc(2026, 9, 1),
        entitlement: receipt(DateTime.utc(2026, 9, 1)),
      );
      expect(t.now, DateTime.utc(2026, 10, 1));
    });

    test('time moves forward normally', () {
      final t = resolveTrustedTime(
        deviceNow: DateTime.utc(2026, 11, 1),
        lastSeen: DateTime.utc(2026, 10, 1),
        lastReceiptIssuedAt: DateTime.utc(2026, 9, 1),
        entitlement: receipt(DateTime.utc(2026, 9, 1)),
      );
      expect(t.now, DateTime.utc(2026, 11, 1));
      expect(t.lastSeen, DateTime.utc(2026, 11, 1));
    });

    test('a NEWER receipt resets a clock that was once set too far ahead', () {
      final t = resolveTrustedTime(
        deviceNow: DateTime.utc(2026, 10, 2),
        lastSeen: DateTime.utc(2027, 10, 1), // stuck a year ahead
        lastReceiptIssuedAt: DateTime.utc(2026, 9, 1),
        entitlement: receipt(DateTime.utc(2026, 10, 2)),
      );
      expect(t.now, DateTime.utc(2026, 10, 2));
      expect(t.lastSeen, DateTime.utc(2026, 10, 2));
    });

    test('replaying an OLD receipt resets nothing', () {
      final t = resolveTrustedTime(
        deviceNow: DateTime.utc(2026, 1, 1),
        lastSeen: DateTime.utc(2026, 10, 1),
        lastReceiptIssuedAt: DateTime.utc(2026, 9, 1),
        entitlement: receipt(DateTime.utc(2026, 8, 1)),
      );
      expect(t.now, DateTime.utc(2026, 10, 1));
    });

    test('first ever run just uses the device clock', () {
      final t = resolveTrustedTime(
        deviceNow: DateTime.utc(2026, 10, 2),
        lastSeen: null,
        lastReceiptIssuedAt: null,
        entitlement: null,
      );
      expect(t.now, DateTime.utc(2026, 10, 2));
    });
  });
}
