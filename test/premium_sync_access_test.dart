import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/sync/sync_providers.dart';
import 'package:mm_pos/features/license/license_model.dart';
import 'package:mm_pos/features/license/license_providers.dart';
import 'package:mm_pos/features/license/license_status.dart';

LicenseState snapshot({LicensePlan plan = LicensePlan.monthly,
  LicenseStatusKind kind = LicenseStatusKind.active, bool entitled = true,
  String shopId = 'shop-a', bool loading = false}) => LicenseState(
  loading: loading, entitled: entitled,
  license: CachedLicense(key: 'SIGNUP', shopId: shopId, plan: plan,
    expiresAt: DateTime(2027), activatedAt: DateTime(2026),
    lastVerifiedAt: DateTime(2026), deviceId: 'phone'),
  status: LicenseStatus(kind: kind),
);

void main() {
  test('business sync requires verified, current shop Premium', () {
    expect(canSyncShop(snapshot()), isTrue);
    expect(canSyncShop(snapshot(kind: LicenseStatusKind.grace)), isTrue);
    expect(canSyncShop(snapshot(plan: LicensePlan.trial)), isTrue);
    expect(canSyncShop(snapshot(plan: LicensePlan.free)), isFalse);
    expect(canSyncShop(snapshot(kind: LicenseStatusKind.expired)), isFalse);
    expect(canSyncShop(snapshot(entitled: false)), isFalse);
    expect(canSyncShop(snapshot(shopId: 'free-local')), isFalse);
    expect(canSyncShop(snapshot(shopId: '')), isFalse);
    expect(canSyncShop(snapshot(loading: true)), isFalse);
  });
}
