import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/features/account/account_repository.dart';
import 'package:mm_pos/features/account/social_auth.dart';
import 'package:mm_pos/features/license/license_model.dart';
import 'package:mm_pos/features/license/license_repository.dart';
import 'package:mm_pos/features/license/license_status.dart';

User _user({String role = 'owner', String? shop = 'cloud-shop'}) => User(
  id: 'user-1',
  appMetadata: {'role': role, 'shop_id': ?shop},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-10-04T00:00:00Z',
  email: 'owner@example.com',
);
CachedLicense _license(String shop) => CachedLicense(
  key: 'ACCOUNT',
  shopId: shop,
  plan: LicensePlan.free,
  expiresAt: DateTime(2099),
  activatedAt: DateTime(2026),
  lastVerifiedAt: DateTime(2026),
  deviceId: 'device-1',
);

class _Social extends SocialAuthService {
  String? failure;
  @override
  Set<SocialAuthProvider> get availableProviders => {SocialAuthProvider.google};
  @override
  Future<AuthResponse> signIn(SocialAuthProvider provider) async {
    if (failure != null) throw SocialAuthFailure(failure!);
    return AuthResponse(
      session: Session(
        accessToken: 'test-token',
        tokenType: 'bearer',
        user: _user(),
      ),
    );
  }

  @override
  Future<AuthResponse> link(SocialAuthProvider provider) async =>
      AuthResponse(user: _user());
  @override
  Future<SocialAuthProof> reauthenticate(SocialAuthProvider provider) async =>
      SocialAuthProof(provider, 'test-id-token');
}

class _LicenseRepository extends LicenseRepository {
  _LicenseRepository(super.settings);
  CachedLicense? cached;
  int saves = 0;
  @override
  Future<CachedLicense?> current() async => cached;
  @override
  Future<CachedLicense?> saveExternal(CachedLicense lic) async {
    cached = lic;
    saves++;
    return lic;
  }
}

class _Account extends AccountRepository {
  // Different fake types deliberately narrow the production dependencies.
  // ignore: use_super_parameters
  _Account(
    _LicenseRepository repo,
    SettingsRepository settings,
    AppDatabase db,
    _Social social,
  ) : super(repo, settings, db, socialAuth: social);
  User? user = _user();
  Map<String, dynamic> reply = {
    'ok': true,
    'needs_shop_name': false,
    'shop_id': 'cloud-shop',
  };
  final requests = <Map<String, dynamic>>[];
  int attaches = 0;
  String? attachFailure;
  CachedLicense target = _license('cloud-shop');
  @override
  User? get currentAuthUser => user;
  @override
  Set<SocialAuthProvider> get linkedSocialProviders => {
    SocialAuthProvider.google,
  };
  @override
  Future<Map<String, dynamic>?> invokeSocialAction(
    Map<String, dynamic> body,
  ) async {
    requests.add(body);
    return reply;
  }

  @override
  Future<void> refreshAuthenticatedSession() async {}
  @override
  Future<AccountActionResult> attachAccountLicense({
    CachedLicense? fallback,
    bool persist = true,
  }) async {
    attaches++;
    if (attachFailure != null) {
      return AccountActionResult.failure(attachFailure);
    }
    return AccountActionResult.success('user-1', license: fallback ?? target);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late SettingsRepository settings;
  late _LicenseRepository licenses;
  late _Social social;
  late _Account account;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsRepository(db);
    licenses = _LicenseRepository(settings);
    social = _Social();
    account = _Account(licenses, settings, db, social);
  });
  tearDown(() => db.close());
  test(
    'same account attaches its original shop instead of creating a shop',
    () async {
      licenses.cached = _license('cloud-shop');
      final result = await account.signInWithSocial(SocialAuthProvider.google);
      expect(result.ok, isTrue);
      expect(result.license!.shopId, 'cloud-shop');
      expect(account.requests.single['action'], 'prepare_social_account');
      expect(account.attaches, 1);
    },
  );
  test(
    'first social account asks for a name without attaching or overwriting local identity',
    () async {
      licenses.cached = _license('free-device');
      account.reply = {'ok': true, 'needs_shop_name': true};
      final result = await account.signInWithSocial(SocialAuthProvider.google);
      expect(result.needsShopName, isTrue);
      expect(account.attaches, 0);
      expect(licenses.cached!.shopId, 'free-device');
    },
  );
  test(
    'different real shop requires confirmation before changing cached identity',
    () async {
      licenses.cached = _license('other-shop');
      final result = await account.signInWithSocial(SocialAuthProvider.google);
      expect(result.needsWipeConfirmation, isTrue);
      expect(account.attaches, 0);
      expect(licenses.cached!.shopId, 'other-shop');
    },
  );
  test(
    'cancelling provider selection does not call the server or change local identity',
    () async {
      social.failure = 'auth_cancelled';
      licenses.cached = _license('old-shop');
      final result = await account.signInWithSocial(SocialAuthProvider.google);
      expect(result.error, 'auth_cancelled');
      expect(account.requests, isEmpty);
      expect(licenses.cached!.shopId, 'old-shop');
    },
  );
  test(
    'local Free identity promotes only after device attachment succeeds',
    () async {
      licenses.cached = _license('free-device');
      final result = await account.signInWithSocial(SocialAuthProvider.google);
      expect(result.ok, isTrue);
      expect(licenses.cached!.shopId, 'cloud-shop');
      expect(licenses.saves, 1);
    },
  );
  test(
    'Free promotion moves only current shop rows and retains other-shop data',
    () async {
      licenses.cached = _license('free-device');
      for (final shop in ['free-device', 'other-shop']) {
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(id: shop, shopId: shop, name: shop),
            );
      }
      final result = await account.signInWithSocial(SocialAuthProvider.google);
      expect(result.ok, isTrue);
      final rows = await db.select(db.categories).get();
      expect(
        rows.singleWhere((r) => r.id == 'free-device').shopId,
        'cloud-shop',
      );
      expect(
        rows.singleWhere((r) => r.id == 'other-shop').shopId,
        'other-shop',
      );
      final outbox = await db.select(db.outbox).get();
      expect(
        outbox.where((r) => r.entityTable == 'categories').single.rowId,
        'free-device',
      );
      expect(await settings.pendingShopPromotion(), isNull);
    },
  );
  test('unrefreshed membership cannot attach another shop', () async {
    account.user = _user(shop: 'stale-shop');
    final result = await account.signInWithSocial(SocialAuthProvider.google);
    expect(result.error, 'not_authenticated');
    expect(account.attaches, 0);
    expect(licenses.saves, 0);
  });
  test('failed device attachment keeps local Free data identity', () async {
    licenses.cached = _license('free-device');
    account.attachFailure = 'device_limit_reached';
    final result = await account.signInWithSocial(SocialAuthProvider.google);
    expect(result.error, 'device_limit_reached');
    expect(licenses.cached!.shopId, 'free-device');
    expect(licenses.saves, 0);
  });
  test(
    'first signup attaches the server shop and keeps trial explicit',
    () async {
      account.reply = {'ok': true, 'shop_id': 'cloud-shop'};
      final result = await account.completeSocialSignup('  My shop  ');
      expect(result.ok, isTrue);
      expect(account.requests.single['action'], 'signup_social_shop');
      expect(account.requests.single['shop_name'], 'My shop');
      expect(account.requests.single.containsKey('trial'), isFalse);
      expect(account.attaches, 1);
    },
  );
  test('linking retains the authenticated user and local license', () async {
    licenses.cached = _license('cloud-shop');
    final result = await account.linkSocialIdentity(SocialAuthProvider.google);
    expect(result.ok, isTrue);
    expect(result.userId, 'user-1');
    expect(account.requests, isEmpty);
    expect(licenses.saves, 0);
  });
  test(
    'authenticated password signup retries use attachment authority',
    () async {
      account.reply = {'ok': true, 'shop_id': 'cloud-shop'};
      final result = await account.signupShop(
        'My shop',
        'ignored@example.com',
        'ignored',
      );
      expect(result.ok, isTrue);
      expect(account.requests.single['action'], 'signup_social_shop');
      expect(account.attaches, 1);
      expect(result.license, same(account.target));
    },
  );
  test(
    'staff cannot use first-shop social signup to become an owner',
    () async {
      account.user = _user(role: 'staff');
      final result = await account.completeSocialSignup('New shop');
      expect(result.error, 'forbidden');
      expect(account.requests, isEmpty);
    },
  );
  test(
    'social deletion requires local owner authorization before provider proof',
    () async {
      account.user = _user(role: 'staff');
      final result = await account.deleteAccountWithSocial(
        SocialAuthProvider.google,
      );
      expect(result.error, 'forbidden');
      expect(account.requests, isEmpty);
    },
  );
  test(
    'social-only deletion sends proof to server without requiring a password',
    () async {
      account.reply = {'ok': true};
      final result = await account.deleteAccountWithSocial(
        SocialAuthProvider.google,
      );
      expect(result.ok, isTrue);
      expect(account.requests.single['action'], 'delete_account');
      expect(account.requests.single['id_token'], 'test-id-token');
      expect(account.requests.single.containsKey('password'), isFalse);
    },
  );
}
