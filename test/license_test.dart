import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/features/license/license_model.dart';
import 'package:mm_pos/features/license/license_providers.dart';
import 'package:mm_pos/features/license/license_repository.dart';
import 'package:mm_pos/features/license/license_screen.dart';
import 'package:mm_pos/features/license/license_status.dart';

void main() {
  group('DeviceProvisioning', () {
    test('an owner-role device encodes as a plain key (backward compatible '
        'with manual entry / older scanners)', () {
      const p = DeviceProvisioning(key: 'MMPOS-AAAA-BBBB-CCCC');
      expect(p.encode(), 'MMPOS-AAAA-BBBB-CCCC');
    });

    test('a staff-role device round-trips key + role + staffMemberId '
        'through a QR-safe JSON encoding', () {
      const p = DeviceProvisioning(
        key: 'MMPOS-AAAA-BBBB-CCCC',
        role: 'staff',
        staffMemberId: 'staff-1',
      );
      final decoded = DeviceProvisioning.decode(p.encode());
      expect(decoded.key, 'MMPOS-AAAA-BBBB-CCCC');
      expect(decoded.role, 'staff');
      expect(decoded.staffMemberId, 'staff-1');
    });

    test('decoding a plain (non-JSON) key falls back to owner role', () {
      final decoded = DeviceProvisioning.decode('MMPOS-AAAA-BBBB-CCCC');
      expect(decoded.key, 'MMPOS-AAAA-BBBB-CCCC');
      expect(decoded.role, 'owner');
      expect(decoded.staffMemberId, isNull);
    });

    test('decoding garbage JSON with no key field falls back to treating '
        'the whole input as the key', () {
      final decoded = DeviceProvisioning.decode('{"foo":"bar"}');
      expect(decoded.key, '{"foo":"bar"}');
      expect(decoded.role, 'owner');
    });
  });

  group('CachedLicense JSON round-trip', () {
    test('realtimeEnabled survives toJson/fromJson', () {
      final lic = CachedLicense(
        key: 'MMPOS-TEST',
        shopId: 'shop-1',
        plan: LicensePlan.yearly,
        expiresAt: DateTime(2027, 1, 1),
        activatedAt: DateTime(2026, 1, 1),
        lastVerifiedAt: DateTime(2026, 6, 1),
        deviceId: 'device-1',
        realtimeEnabled: true,
      );
      final restored = CachedLicense.fromJson(lic.toJson());
      expect(restored.realtimeEnabled, isTrue);
    });

    test('defaults to false for older cached JSON with no such field', () {
      final restored = CachedLicense.fromJson({
        'key': 'MMPOS-OLD',
        'shop_id': 'shop-1',
        'plan': 'monthly',
        'expires_at': DateTime(2027, 1, 1).toIso8601String(),
        'activated_at': DateTime(2026, 1, 1).toIso8601String(),
        'device_id': 'device-1',
      });
      expect(restored.realtimeEnabled, isFalse);
    });
  });

  group('computeLicenseStatus', () {
    final now = DateTime(2026, 7, 10, 12);

    test('none when not activated / no expiry', () {
      expect(computeLicenseStatus(expiresAt: null, now: now).kind,
          LicenseStatusKind.none);
      expect(
          computeLicenseStatus(
                  expiresAt: now.add(const Duration(days: 5)),
                  now: now,
                  activated: false)
              .kind,
          LicenseStatusKind.none);
    });

    test('active before expiry', () {
      final s = computeLicenseStatus(
          expiresAt: now.add(const Duration(days: 3)), now: now);
      expect(s.kind, LicenseStatusKind.active);
      expect(s.canSell, isTrue);
      expect(s.isReadOnly, isFalse);
    });

    test('grace within the window, still sellable', () {
      final s = computeLicenseStatus(
          expiresAt: now.subtract(const Duration(days: 2)),
          now: now,
          graceDays: 7);
      expect(s.kind, LicenseStatusKind.grace);
      expect(s.canSell, isTrue);
      expect(s.graceDaysLeft, 5);
    });

    test('expired past grace still sells — Premium is locked, not the till', () {
      final s = computeLicenseStatus(
          expiresAt: now.subtract(const Duration(days: 10)),
          now: now,
          graceDays: 7);
      expect(s.kind, LicenseStatusKind.expired);
      expect(s.canSell, isTrue);
      expect(s.isReadOnly, isFalse);
    });

    test('exact expiry moment is still active', () {
      final s = computeLicenseStatus(expiresAt: now, now: now);
      expect(s.kind, LicenseStatusKind.active);
    });

    test('the Free plan is always active/sellable, even long past its '
        'nominal expiresAt', () {
      final s = computeLicenseStatus(
        expiresAt: now.subtract(const Duration(days: 3650)),
        now: now,
        plan: LicensePlan.free,
      );
      expect(s.kind, LicenseStatusKind.active);
      expect(s.canSell, isTrue);
      expect(s.isReadOnly, isFalse);
    });
  });

  group('LicenseRepository (offline / no backend)', () {
    late AppDatabase db;
    late SettingsRepository settings;
    late LicenseRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      settings = SettingsRepository(db);
      repo = LicenseRepository(settings);
    });

    tearDown(() async => db.close());

    test('activate falls back to a 14-day trial with no backend', () async {
      final result = await repo.activate('ANY-KEY');
      expect(result.ok, isTrue);
      expect(result.license, isNotNull);
      expect(result.license!.plan, LicensePlan.trial);
      expect(result.license!.expiresAt.isAfter(DateTime.now()), isTrue);

      // Persisted and re-readable.
      final cached = await repo.current();
      expect(cached?.key, 'ANY-KEY');
    });

    test('empty key is rejected', () async {
      final result = await repo.activate('   ');
      expect(result.ok, isFalse);
      expect(result.errorCode, 'empty_key');
    });

    test('deactivate clears the cached license', () async {
      await repo.activate('K');
      await repo.deactivate();
      expect(await repo.current(), isNull);
    });

    test('self-serve trial needs a backend', () async {
      final result = await repo.startFreeTrial('My Shop');
      expect(result.ok, isFalse);
      expect(result.errorCode, 'no_backend');
      expect(await repo.current(), isNull);
    });

    test('device id is stable across calls', () async {
      final a = await settings.deviceId();
      final b = await settings.deviceId();
      expect(a, equals(b));
      expect(a, isNotEmpty);
    });

    test('startFreePlan grants an always-active Free license with no key',
        () async {
      final lic = await repo.startFreePlan();
      expect(lic.plan, LicensePlan.free);
      expect(lic.key, 'FREE');
      expect(lic.shopId, isNotEmpty);

      final cached = await repo.current();
      expect(cached?.plan, LicensePlan.free);
    });

    test('downgradeToFree preserves shopId/deviceId/tier of the original '
        'license', () async {
      final result = await repo.activate('SOME-KEY');
      final original = result.license!;

      final free = await repo.downgradeToFree(original);
      expect(free.plan, LicensePlan.free);
      expect(free.shopId, original.shopId);
      expect(free.deviceId, original.deviceId);
      expect(free.tier, original.tier);
    });

    test('multi-device actions are no-ops with no backend', () async {
      expect(await repo.listDevices(), isEmpty);
      final slot = await repo.requestDeviceSlot();
      expect(slot.ok, isFalse);
      expect(slot.errorCode, 'no_backend');
      expect(await repo.releaseDevice('some-device'), isFalse);
    });
  });

  group('LicenseState.isPremium', () {
    CachedLicense license({required LicensePlan plan, required DateTime expiresAt}) {
      final now = DateTime.now();
      return CachedLicense(
        key: 'K',
        shopId: 'shop-1',
        plan: plan,
        expiresAt: expiresAt,
        activatedAt: now,
        lastVerifiedAt: now,
        deviceId: 'dev-1',
      );
    }

    test('no license at all is not premium', () {
      const state = LicenseState();
      expect(state.isPremium, isFalse);
      expect(state.loading, isTrue);
      expect(state.canSell, isFalse);
    });

    test('an active paid plan is premium', () {
      final lic = license(
          plan: LicensePlan.monthly,
          expiresAt: DateTime.now().add(const Duration(days: 10)));
      final status = computeLicenseStatus(
          expiresAt: lic.expiresAt, now: DateTime.now(), plan: lic.plan);
      final state = LicenseState(license: lic, status: status, loading: false);
      expect(state.isPremium, isTrue);
    });

    test('the Free plan is never premium, even though it can still sell', () {
      final lic = license(
          plan: LicensePlan.free,
          expiresAt: DateTime.now().subtract(const Duration(days: 3650)));
      final status = computeLicenseStatus(
          expiresAt: lic.expiresAt, now: DateTime.now(), plan: lic.plan);
      final state = LicenseState(license: lic, status: status, loading: false);
      expect(state.canSell, isTrue);
      expect(state.isPremium, isFalse);
    });

    test('an expired paid plan is not premium', () {
      final lic = license(
          plan: LicensePlan.monthly,
          expiresAt: DateTime.now().subtract(const Duration(days: 30)));
      final status = computeLicenseStatus(
          expiresAt: lic.expiresAt, now: DateTime.now(), plan: lic.plan);
      final state = LicenseState(license: lic, status: status, loading: false);
      expect(state.canSell, isTrue);
      expect(state.isPremium, isFalse);
    });
  });

  group('applyOfflineFallback (refreshOnline\'s network-failure branch)', () {
    CachedLicense license({
      required DateTime expiresAt,
      String key = 'MMPOS-REAL-KEY',
    }) {
      final now = DateTime(2026, 8, 16, 12);
      return CachedLicense(
        key: key,
        shopId: 'shop-1',
        plan: LicensePlan.monthly,
        expiresAt: expiresAt,
        activatedAt: now,
        lastVerifiedAt: now,
        deviceId: 'dev-1',
      );
    }

    test('extends expiresAt to the offline token\'s when that\'s later, '
        'keeping the license\'s own key/shopId/plan unchanged', () {
      final now = DateTime(2026, 8, 16, 12);
      final current = license(expiresAt: now.subtract(const Duration(days: 10)));
      final verifiedFallback = license(
        key: 'MMPOS1.token.sig', // offline token's own synthetic identity
        expiresAt: now.add(const Duration(days: 20)),
      );

      final result = applyOfflineFallback(
        current: current,
        verifiedFallback: verifiedFallback,
        now: now,
      );

      expect(result, isNotNull);
      expect(result!.key, current.key); // NOT replaced by the token
      expect(result.shopId, current.shopId);
      expect(result.plan, current.plan);
      expect(result.expiresAt, verifiedFallback.expiresAt);
      expect(result.lastVerifiedAt, now);
    });

    test('never shortens expiresAt if the cached license is already valid '
        'further out than the fallback token', () {
      final now = DateTime(2026, 8, 16, 12);
      final current = license(expiresAt: now.add(const Duration(days: 60)));
      final verifiedFallback = license(expiresAt: now.add(const Duration(days: 20)));

      final result = applyOfflineFallback(
        current: current,
        verifiedFallback: verifiedFallback,
        now: now,
      );

      expect(result!.expiresAt, current.expiresAt); // unchanged, still later
    });

    test('returns null when the fallback token is itself already expired '
        '— nothing to extend trust with', () {
      final now = DateTime(2026, 8, 16, 12);
      final current = license(expiresAt: now.subtract(const Duration(days: 10)));
      final verifiedFallback =
          license(expiresAt: now.subtract(const Duration(days: 1)));

      final result = applyOfflineFallback(
        current: current,
        verifiedFallback: verifiedFallback,
        now: now,
      );

      expect(result, isNull);
    });
  });
}
