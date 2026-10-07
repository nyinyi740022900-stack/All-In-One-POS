import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:mm_pos/data/local/database_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/features/account/account_repository.dart';
import 'package:mm_pos/features/printing/printing_providers.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/features/license/license_model.dart';
import 'package:mm_pos/features/license/license_providers.dart';
import 'package:mm_pos/features/license/license_repository.dart';
import 'package:mm_pos/features/license/license_status.dart';

class _RemoteRepository extends LicenseRepository {
  _RemoteRepository(super.settings);
  ActivationResult response = const ActivationResult.failure('network_error');
  Completer<ActivationResult>? pending;
  Completer<CachedLicense?>? pendingCurrent;
  @override
  Future<CachedLicense?> current() => pendingCurrent?.future ?? super.current();
  @override
  bool get hasEmailSession => true;
  @override
  String? get currentUserId => 'user';
  String? accountRole;
  String? accountShop;
  @override
  String? get currentAccountRole => accountRole;
  @override
  String? get currentSessionShopId => accountShop;
  @override
  Future<ActivationResult> refreshAccountLicense({
    bool persist = true,
    bool reclaimDevice = false,
  }) async {
    // Stands in for what the real call does on its way to an answer: it
    // refreshes the Supabase session, which emits onAuthStateChange, which
    // makes the controller re-apply its own license.
    await duringRequest?.call();
    return pending?.future ?? response;
  }

  Future<void> Function()? duringRequest;
}

class _ShopSession extends ChangeNotifier implements DatabaseSession {
  _ShopSession(this.shopDb, this.target, this.deviceDb);
  @override
  AppDatabase shopDb;
  final AppDatabase target;
  @override
  final AppDatabase deviceDb;
  @override
  String? shopId;
  @override
  Future<void> reopenForShop(String toShopId) async {
    shopDb = target;
    shopId = toShopId;
    notifyListeners();
    await Future<void>.delayed(Duration.zero);
  }
  @override
  Future<void> reopenForShopPromotedFrom({required String fromShopId, required String toShopId}) => reopenForShop(toShopId);
  @override
  Future<void> disposeSessions() async {}
}

class _Account extends AccountRepository {
  _Account(super.license, super.settings, super.db);
  String? role = 'staff';
  @override
  String? get currentAccountRole => role;
}

class _ClockController extends LicenseController {
  _ClockController(super.ref);
  @override
  DateTime currentTime = DateTime.now();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late SettingsRepository settings;
  late _RemoteRepository repo;
  late ProviderContainer container;
  late CachedLicense paid;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsRepository(db);
    repo = _RemoteRepository(settings);
    paid = CachedLicense(
      key: 'ACCOUNT',
      shopId: 'shop-1',
      plan: LicensePlan.monthly,
      expiresAt: DateTime.now().subtract(const Duration(days: 20)),
      activatedAt: DateTime(2026),
      lastVerifiedAt: DateTime(2026),
      deviceId: await settings.deviceId(),
    );
    await repo.saveExternal(paid);
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        settingsRepositoryProvider.overrideWithValue(settings),
        licenseRepositoryProvider.overrideWithValue(repo),
        licenseControllerProvider.overrideWith(
          (ref) => _ClockController(ref)..load(),
        ),
      ],
    );
    await container.read(licenseControllerProvider.notifier).load();
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test(
    'local lapse retains account identity and paid evidence for renewal',
    () async {
      final state = container.read(licenseControllerProvider);
      expect(state.status.kind, LicenseStatusKind.expired);
      expect(state.isPremium, isFalse);
      expect(state.canSell, isTrue);
      expect((await repo.current())?.key, paid.key);
      expect((await repo.current())?.plan, LicensePlan.monthly);
    },
  );
  test(
    'timeout retains cached account evidence but explicit revocation removes Premium',
    () async {
      final controller = container.read(licenseControllerProvider.notifier);
      await controller.refreshOnline();
      expect((await repo.current())?.plan, LicensePlan.monthly);
      repo.response = const ActivationResult.failure('device_released');
      await controller.refreshOnline();
      expect(container.read(licenseControllerProvider).isPremium, isFalse);
      expect((await repo.current())?.plan, LicensePlan.free);
      expect((await repo.current())?.shopId, paid.shopId);
      expect((await repo.current())?.key, paid.key);
    },
  );
  test(
    'local expiry recheck lapses without a successful network request',
    () async {
      final controller =
          container.read(licenseControllerProvider.notifier)
              as _ClockController;
      final active = paid.copyWith(
        expiresAt: controller.currentTime.add(const Duration(days: 1)),
      );
      await repo.saveExternal(active);
      await controller.applyExternal(active);
      expect(container.read(licenseControllerProvider).isPremium, isTrue);
      controller.currentTime = controller.currentTime.add(
        const Duration(days: 16),
      );
      await controller.recomputeExpiry();
      expect(
        container.read(licenseControllerProvider).status.kind,
        LicenseStatusKind.expired,
      );
      expect(container.read(licenseControllerProvider).isPremium, isFalse);
      expect(container.read(licenseControllerProvider).canSell, isTrue);
      expect((await repo.current())?.key, 'ACCOUNT');
    },
  );

  test(
    'provisioned staff keeps local role after backend session loss',
    () async {
      final account = _Account(repo, settings, db);
      repo.response = ActivationResult.success(paid);
      expect((await account.attachAccountLicense()).ok, isTrue);
      account.role =
          null; // Supabase clears the session, without a manual signout.
      expect(await settings.staffRole(paid.shopId), 'staff');
    },
  );

  test(
    'verified owner attachment may restore owner after staff floor',
    () async {
      final account = _Account(repo, settings, db)..role = 'owner';
      await settings.setStaffRole(paid.shopId, 'staff');
      repo.response = ActivationResult.success(paid);
      expect((await account.attachAccountLicense()).ok, isTrue);
      expect(await settings.staffRole(paid.shopId), 'owner');
    },
  );

  test('newly provisioned staff floor survives auth loss in the freshly reopened target database', () async {
    final targetDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(targetDb.close);
    final targetLicense = CachedLicense(key: 'ACCOUNT', shopId: 'shop-2', plan: LicensePlan.free,
      expiresAt: DateTime(2026), activatedAt: DateTime(2026), lastVerifiedAt: DateTime(2026), deviceId: paid.deviceId);
    repo.response = ActivationResult.success(targetLicense);
    repo.accountRole = 'staff'; repo.accountShop = 'shop-2';
    final account = _Account(repo, settings, db);
    final attached = await account.attachAccountLicense();
    expect(attached.ok, isTrue);
    expect(await SettingsRepository(targetDb).staffRole('shop-2'), 'owner');
    final session = _ShopSession(db, targetDb, db);
    final targetContainer = ProviderContainer(overrides: [
      databaseSessionProvider.overrideWith((ref) => session),
      licenseRepositoryProvider.overrideWithValue(repo),
      licenseControllerProvider.overrideWith((ref) => _ClockController(ref)),
    ]);
    addTearDown(targetContainer.dispose);
    final controller = targetContainer.read(licenseControllerProvider.notifier);
    await controller.applyExternal(attached.license!);
    expect(identical(targetContainer.read(databaseProvider), targetDb), isTrue);
    repo.accountRole = null; account.role = null;
    await controller.recomputeExpiry();
    final targetSettings = targetContainer.read(settingsRepositoryProvider);
    expect(await targetSettings.staffRole('shop-2'), 'staff');
  });

  test(
    'background refresh cannot switch to another account shop with local writes',
    () async {
      await db
          .into(db.outbox)
          .insert(
            OutboxCompanion.insert(
              entityTable: 'products',
              rowId: 'pending-local',
              op: 'upsert',
            ),
          );
      final other = CachedLicense(
        key: 'ACCOUNT',
        shopId: 'shop-2',
        plan: LicensePlan.monthly,
        expiresAt: DateTime.now().add(const Duration(days: 30)),
        activatedAt: DateTime(2026),
        lastVerifiedAt: DateTime(2026),
        deviceId: paid.deviceId,
      );
      repo.response = ActivationResult.success(other);
      final result = await container
          .read(licenseControllerProvider.notifier)
          .refreshOnline();
      expect(result.ok, isFalse);
      expect(result.errorCode, 'shop_transition_required');
      expect(
        container.read(licenseControllerProvider).license?.shopId,
        'shop-1',
      );
      expect((await repo.current())?.shopId, 'shop-1');
      expect((await db.select(db.outbox).get()).single.rowId, 'pending-local');
    },
  );

  test('late startup load cannot replace a newer selected shop', () async {
    repo.pendingCurrent = Completer<CachedLicense?>();
    final loadingContainer = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db), settingsRepositoryProvider.overrideWithValue(settings),
      licenseRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(loadingContainer.dispose);
    final controller = loadingContainer.read(licenseControllerProvider.notifier);
    final loading = controller.load();
    final other = CachedLicense(key: 'ACCOUNT', shopId: 'shop-2', plan: LicensePlan.free,
      expiresAt: DateTime(2026), activatedAt: DateTime(2026), lastVerifiedAt: DateTime(2026), deviceId: paid.deviceId);
    await controller.applyExternal(other);
    repo.pendingCurrent!.complete(paid);
    await loading;
    expect(loadingContainer.read(licenseControllerProvider).license?.shopId, 'shop-2');
  });

  test(
    'Check for renewal survives the session refresh it performs itself',
    () async {
      // The refresh re-authenticates, which re-applies the license underneath
      // the caller. That is this request's own side effect, not a competing
      // change, and it must not be read as a stale answer: when it was, Check
      // for renewal failed every time on an account session and the only
      // recovery anyone found was signing out and back in.
      final controller = container.read(licenseControllerProvider.notifier);
      repo.duringRequest = () => controller.recomputeExpiry();
      final renewed = paid.copyWith(
        plan: LicensePlan.yearly,
        expiresAt: DateTime(2027, 10, 16),
      );
      repo.response = ActivationResult.success(renewed);

      final result = await controller.refreshOnline();

      expect(result.ok, isTrue, reason: result.errorCode);
      expect(result.errorCode, isNot('stale_response'));
      expect(
        container.read(licenseControllerProvider).license?.plan,
        LicensePlan.yearly,
      );
      // persist: false is passed to the repository, so the controller is the
      // one that has to write the renewed term through.
      expect((await repo.current())?.plan, LicensePlan.yearly);
    },
  );
  test(
    'late refresh cannot restore a previous shop after transition',
    () async {
      final controller = container.read(licenseControllerProvider.notifier);
      repo.pending = Completer<ActivationResult>();
      final refreshing = controller.refreshOnline();
      final other = CachedLicense(
        key: 'ACCOUNT',
        shopId: 'shop-2',
        plan: LicensePlan.free,
        expiresAt: DateTime(2026),
        activatedAt: DateTime(2026),
        lastVerifiedAt: DateTime(2026),
        deviceId: paid.deviceId,
      );
      await repo.saveExternal(other);
      await controller.applyExternal(other);
      repo.pending!.complete(ActivationResult.success(paid));
      expect((await refreshing).errorCode, 'stale_response');
      expect(
        container.read(licenseControllerProvider).license?.shopId,
        'shop-2',
      );
      expect((await repo.current())?.shopId, 'shop-2');
    },
  );
}
