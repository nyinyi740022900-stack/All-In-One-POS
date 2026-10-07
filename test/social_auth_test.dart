import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:mm_pos/features/account/social_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const configured = SocialAuthConfig(
  backendConfigured: true,
  googleEnabled: true,
  googleWebClientId: 'web.apps.googleusercontent.com',
  googleIosClientId: 'ios.apps.googleusercontent.com',
  appleEnabled: true,
);

Map<String, dynamic> _sessionJson(String userId, {int lifetime = 3600}) {
  final token =
      '${base64UrlEncode(utf8.encode('{}'))}.${base64UrlEncode(utf8.encode(jsonEncode({'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + lifetime})))}.signature';
  return {
    'access_token': token,
    'refresh_token': 'refresh-$userId',
    'token_type': 'bearer',
    'expires_in': lifetime,
    'user': {
      'id': userId,
      'app_metadata': {},
      'user_metadata': {},
      'aud': 'authenticated',
      'created_at': '2026-10-04T00:00:00Z',
      'email': '$userId@example.com',
    },
  };
}

void main() {
  test('proof serializes only supplied credentials', () {
    expect(const SocialAuthProof(SocialAuthProvider.google, 'id').toRequest(), {
      'provider': 'google',
      'id_token': 'id',
    });
    expect(
      const SocialAuthProof(
        SocialAuthProvider.apple,
        'id',
        nonce: 'raw',
        accessToken: 'access',
      ).toRequest(),
      {
        'provider': 'apple',
        'id_token': 'id',
        'nonce': 'raw',
        'access_token': 'access',
      },
    );
  });
  test('absent configuration and desktop/web hide providers', () {
    expect(
      SocialAuthService(
        config: const SocialAuthConfig(),
        platform: TargetPlatform.iOS,
      ).availableProviders,
      isEmpty,
    );
    expect(
      SocialAuthService(
        config: configured,
        platform: TargetPlatform.linux,
      ).availableProviders,
      isEmpty,
    );
    expect(
      SocialAuthService(
        config: configured,
        platform: TargetPlatform.iOS,
        isWeb: true,
      ).availableProviders,
      isEmpty,
    );
  });
  test('iOS offers both and Android only Google', () {
    expect(
      SocialAuthService(
        config: configured,
        platform: TargetPlatform.iOS,
      ).availableProviders,
      SocialAuthProvider.values,
    );
    expect(
      SocialAuthService(
        config: configured,
        platform: TargetPlatform.android,
      ).availableProviders,
      [SocialAuthProvider.google],
    );
    expect(
      SocialAuthService(
        config: const SocialAuthConfig(
          backendConfigured: true,
          googleEnabled: true,
          googleWebClientId: 'web',
        ),
        platform: TargetPlatform.iOS,
      ).availableProviders,
      isEmpty,
    );
  });
  test(
    'unavailable configuration fails before native token acquisition',
    () async {
      final service = SocialAuthService(
        config: const SocialAuthConfig(),
        acquireTokens: (_, _) async => throw StateError('should not acquire'),
      );
      await expectLater(
        service.signIn(SocialAuthProvider.google),
        throwsA(
          isA<SocialAuthFailure>().having(
            (e) => e.code,
            'code',
            'social_auth_unavailable',
          ),
        ),
      );
    },
  );
  test(
    'cancellation remains silent and does not exchange credentials',
    () async {
      final service = SocialAuthService(
        config: configured,
        platform: TargetPlatform.iOS,
        acquireTokens: (_, _) async =>
            throw const SocialAuthFailure('auth_cancelled'),
        signInExchange: (_) async => throw StateError('should not exchange'),
      );
      await expectLater(
        service.signIn(SocialAuthProvider.google),
        throwsA(
          isA<SocialAuthFailure>().having(
            (e) => e.code,
            'code',
            'auth_cancelled',
          ),
        ),
      );
    },
  );
  test(
    'Apple nonce is random and hash sent to native adapter matches raw proof',
    () async {
      final challenges = <SocialNonce>[];
      final service = SocialAuthService(
        config: configured,
        platform: TargetPlatform.iOS,
        acquireTokens: (provider, nonce) async {
          challenges.add(nonce!);
          return SocialAuthProof(provider, 'id', nonce: nonce.raw);
        },
      );
      final first = await service.reauthenticate(SocialAuthProvider.apple);
      final second = await service.reauthenticate(SocialAuthProvider.apple);
      expect(first.nonce, isNot(second.nonce));
      expect(first.nonce!.length, greaterThanOrEqualTo(32));
      expect(
        challenges.first.sha256,
        sha256.convert(utf8.encode(first.nonce!)).toString(),
      );
    },
  );
  test(
    'reauthentication acquires fresh proof without replacing Supabase session',
    () async {
      var calls = 0;
      final service = SocialAuthService(
        config: configured,
        platform: TargetPlatform.android,
        acquireTokens: (p, _) async => SocialAuthProof(p, 'fresh-${++calls}'),
        signInExchange: (_) async =>
            throw StateError('must not change session'),
        linkExchange: (_) async => throw StateError('must not link'),
      );
      expect(
        (await service.reauthenticate(SocialAuthProvider.google)).idToken,
        'fresh-1',
      );
      expect(
        (await service.reauthenticate(SocialAuthProvider.google)).idToken,
        'fresh-2',
      );
    },
  );
  test(
    'rejects empty token, wrong provider and wrong Apple nonce before exchange',
    () async {
      for (final proof in [
        const SocialAuthProof(SocialAuthProvider.google, ''),
        const SocialAuthProof(SocialAuthProvider.apple, 'id'),
      ]) {
        final service = SocialAuthService(
          config: configured,
          platform: TargetPlatform.iOS,
          acquireTokens: (_, _) async => proof,
        );
        await expectLater(
          service.reauthenticate(SocialAuthProvider.google),
          throwsA(isA<SocialAuthFailure>()),
        );
      }
      final service = SocialAuthService(
        config: configured,
        platform: TargetPlatform.iOS,
        acquireTokens: (p, _) async => SocialAuthProof(p, 'id', nonce: 'wrong'),
      );
      await expectLater(
        service.reauthenticate(SocialAuthProvider.apple),
        throwsA(isA<SocialAuthFailure>()),
      );
    },
  );
  test('an expired access token is refreshed, not treated as a sign-out', () async {
    // The symptom this covers: tapping "Link another Google account" failed
    // instantly, with no Google sheet, while the account card still showed
    // the owner signed in with their shop and plan.
    var refreshed = 0;
    final main = SupabaseClient(
      'https://auth.example.test',
      'anon',
      httpClient: MockClient((request) async {
        refreshed++;
        return http.Response(jsonEncode(_sessionJson('owner')), 200);
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await main.auth.setInitialSession(
      jsonEncode(_sessionJson('owner', lifetime: -30)),
    );
    expect(main.auth.currentSession!.isExpired, isTrue);
    var chooserOpened = 0;
    final service = SocialAuthService(
      client: main,
      config: configured,
      platform: TargetPlatform.android,
      acquireTokens: (p, _) async {
        chooserOpened++;
        return SocialAuthProof(p, 'id');
      },
      linkExchange: (_) async => AuthResponse(),
    );
    await service.link(SocialAuthProvider.google);
    expect(refreshed, 1);
    expect(chooserOpened, 1, reason: 'the Google sheet must actually open');
    await main.dispose();
  });
  test('a token refresh during the chooser does not cancel the link', () async {
    // Supabase refreshes the session on its own while the native sheet is
    // open. Comparing access tokens made that routine refresh look like a
    // different owner had taken over the app session.
    final main = SupabaseClient(
      'https://auth.example.test',
      'anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await main.auth.setInitialSession(jsonEncode(_sessionJson('owner')));
    var exchanges = 0;
    final service = SocialAuthService(
      client: main,
      config: configured,
      platform: TargetPlatform.android,
      acquireTokens: (p, _) async {
        // Same owner, brand new token — exactly what a refresh produces.
        await main.auth.setInitialSession(
          jsonEncode(_sessionJson('owner', lifetime: 7200)),
        );
        return SocialAuthProof(p, 'id');
      },
      linkExchange: (_) async {
        exchanges++;
        return AuthResponse();
      },
    );
    await service.link(SocialAuthProvider.google);
    expect(exchanges, 1);
    await main.dispose();
  });
  test(
    'owner switching during Google chooser cannot link to the new account',
    () async {
      final main = SupabaseClient(
        'https://auth.example.test',
        'anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await main.auth.setInitialSession(jsonEncode(_sessionJson('owner')));
      var exchanges = 0;
      final service = SocialAuthService(
        client: main,
        config: configured,
        platform: TargetPlatform.android,
        acquireTokens: (provider, _) async {
          await main.auth.setInitialSession(
            jsonEncode(_sessionJson('other-owner')),
          );
          return SocialAuthProof(provider, 'selected-google');
        },
        linkExchange: (_) async {
          exchanges++;
          return AuthResponse();
        },
      );
      await expectLater(
        service.link(SocialAuthProvider.google),
        throwsA(
          isA<SocialAuthFailure>().having(
            (e) => e.code,
            'code',
            'not_authenticated',
          ),
        ),
      );
      expect(exchanges, 0);
      expect(main.auth.currentUser!.id, 'other-owner');
      await main.dispose();
    },
  );
  test('sign-in and link use separate exchanges', () async {
    final main = SupabaseClient(
      'https://auth.example.test',
      'anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await main.auth.setInitialSession(jsonEncode(_sessionJson('owner')));
    final exchanged = <String>[];
    final service = SocialAuthService(
      client: main,
      config: configured,
      platform: TargetPlatform.android,
      acquireTokens: (p, _) async => SocialAuthProof(p, 'id'),
      signInExchange: (proof) async {
        exchanged.add('sign:${proof.idToken}');
        return AuthResponse();
      },
      linkExchange: (proof) async {
        exchanged.add('link:${proof.idToken}');
        return AuthResponse();
      },
    );
    await service.signIn(SocialAuthProvider.google);
    await service.link(SocialAuthProvider.google);
    expect(exchanged, ['sign:id', 'link:id']);
    await main.dispose();
  });
  test(
    'native Google and Apple cancellation codes map to auth_cancelled',
    () async {
      for (final error in [
        const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
        const SignInWithAppleAuthorizationException(
          code: AuthorizationErrorCode.canceled,
          message: 'sensitive',
        ),
      ]) {
        final service = SocialAuthService(
          config: configured,
          platform: TargetPlatform.iOS,
          acquireTokens: (_, _) async => throw error,
        );
        await expectLater(
          service.reauthenticate(SocialAuthProvider.google),
          throwsA(
            isA<SocialAuthFailure>().having(
              (e) => e.code,
              'code',
              'auth_cancelled',
            ),
          ),
        );
      }
    },
  );
  test(
    'native configuration error is unavailable and no sensitive description escapes',
    () async {
      final service = SocialAuthService(
        config: configured,
        platform: TargetPlatform.android,
        acquireTokens: (_, _) async => throw const GoogleSignInException(
          code: GoogleSignInExceptionCode.clientConfigurationError,
          description: 'token-sensitive',
        ),
      );
      await expectLater(
        service.signIn(SocialAuthProvider.google),
        throwsA(
          isA<SocialAuthFailure>().having(
            (e) => e.code,
            'code',
            'social_auth_unavailable',
          ),
        ),
      );
    },
  );
  testWidgets('network exchange times out after native dialog finishes', (
    tester,
  ) async {
    final service = SocialAuthService(
      config: configured,
      platform: TargetPlatform.android,
      acquireTokens: (p, _) async => SocialAuthProof(p, 'id'),
      signInExchange: (_) => Completer<AuthResponse>().future,
    );
    final result = expectLater(
      service.signIn(SocialAuthProvider.google),
      throwsA(
        isA<SocialAuthFailure>().having(
          (e) => e.code,
          'code',
          'social_auth_failed',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    await result;
  });
  testWidgets(
    'late successful token exchange after timeout cannot replace app session',
    (tester) async {
      final delayed = Completer<http.Response>();
      final transport = MockClient((_) => delayed.future);
      final mainClient = (await tester.runAsync(
        () async => SupabaseClient(
          'https://auth.example.test',
          'anon-key',
          httpClient: transport,
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      ))!;
      final service = SocialAuthService(
        client: mainClient,
        httpClient: transport,
        config: configured,
        platform: TargetPlatform.android,
        acquireTokens: (p, _) async => SocialAuthProof(p, 'id'),
      );
      final result = expectLater(
        service.signIn(SocialAuthProvider.google),
        throwsA(isA<SocialAuthFailure>()),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 31));
      await result;
      final token =
          '${base64UrlEncode(utf8.encode('{}'))}.${base64UrlEncode(utf8.encode(jsonEncode({'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})))}.signature';
      delayed.complete(
        http.Response(
          jsonEncode({
            'access_token': token,
            'refresh_token': 'refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'late-user',
              'app_metadata': {},
              'user_metadata': {},
              'aud': 'authenticated',
              'created_at': '2026-10-04T00:00:00Z',
              'email': 'late@example.com',
            },
          }),
          200,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(mainClient.auth.currentUser, isNull);
      await tester.runAsync(mainClient.dispose);
    },
  );
  test(
    'timely verified session is adopted without another auth HTTP request',
    () async {
      final calls = <http.Request>[];
      final transport = MockClient((request) async {
        calls.add(request);
        return http.Response(jsonEncode(_sessionJson('new-user')), 200);
      });
      final mainClient = SupabaseClient(
        'https://auth.example.test',
        'anon-key',
        httpClient: MockClient(
          (_) async => throw StateError('adoption must be local'),
        ),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final service = SocialAuthService(
        client: mainClient,
        httpClient: transport,
        config: configured,
        platform: TargetPlatform.android,
        acquireTokens: (p, _) async => SocialAuthProof(p, 'provider-token'),
      );
      final result = await service.signIn(SocialAuthProvider.google);
      expect(result.user!.id, 'new-user');
      expect(mainClient.auth.currentUser!.id, 'new-user');
      expect(calls.single.url.path, '/auth/v1/token');
      expect(jsonDecode(calls.single.body)['id_token'], 'provider-token');
      await mainClient.dispose();
    },
  );
  test('a Google nonce is forwarded to Supabase with the token', () async {
    // Supabase answers 400 "Passed nonce and nonce in id_token should either
    // both exist or not" when the token carries a nonce it was not given.
    // Google echoes the OIDC nonce into the token, so dropping it here is
    // what turned every Google sign-in into "Could not sign in".
    final mainClient = SupabaseClient(
      'https://auth.example.test',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    String? sentNonce;
    final transport = MockClient((request) async {
      sentNonce = jsonDecode(request.body)['nonce'] as String?;
      return http.Response(jsonEncode(_sessionJson('google-user')), 200);
    });
    final service = SocialAuthService(
      client: mainClient,
      httpClient: transport,
      config: configured,
      platform: TargetPlatform.android,
      acquireTokens: (p, _) async =>
          SocialAuthProof(p, 'provider-token', nonce: 'raw-nonce'),
    );
    await service.signIn(SocialAuthProvider.google);
    expect(sentNonce, 'raw-nonce');
    await mainClient.dispose();
  });
  test(
    'link uses existing bearer identity and adopts only the same user',
    () async {
      for (final target in ['owner', 'different-user']) {
        final mainClient = SupabaseClient(
          'https://auth.example.test',
          'anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
        await mainClient.auth.recoverSession(jsonEncode(_sessionJson('owner')));
        final originalToken = mainClient.auth.currentSession!.accessToken;
        final transport = MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer $originalToken');
          expect(jsonDecode(request.body)['link_identity'], true);
          return http.Response(jsonEncode(_sessionJson(target)), 200);
        });
        final service = SocialAuthService(
          client: mainClient,
          httpClient: transport,
          config: configured,
          platform: TargetPlatform.android,
          acquireTokens: (p, _) async => SocialAuthProof(p, 'provider-token'),
        );
        if (target == 'owner') {
          expect(
            (await service.link(SocialAuthProvider.google)).user!.id,
            'owner',
          );
        } else {
          await expectLater(
            service.link(SocialAuthProvider.google),
            throwsA(
              isA<SocialAuthFailure>().having(
                (e) => e.code,
                'code',
                'not_authenticated',
              ),
            ),
          );
        }
        expect(mainClient.auth.currentUser!.id, 'owner');
        await mainClient.dispose();
      }
    },
  );
  test(
    'concurrent main session change prevents stale exchange adoption',
    () async {
      final mainClient = SupabaseClient(
        'https://auth.example.test',
        'anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await mainClient.auth.recoverSession(jsonEncode(_sessionJson('owner')));
      final transport = MockClient((_) async {
        await mainClient.auth.recoverSession(
          jsonEncode(_sessionJson('other-user', lifetime: 7200)),
        );
        return http.Response(jsonEncode(_sessionJson('social-user')), 200);
      });
      final service = SocialAuthService(
        client: mainClient,
        httpClient: transport,
        config: configured,
        platform: TargetPlatform.android,
        acquireTokens: (p, _) async => SocialAuthProof(p, 'provider-token'),
      );
      await expectLater(
        service.signIn(SocialAuthProvider.google),
        throwsA(
          isA<SocialAuthFailure>().having(
            (e) => e.code,
            'code',
            'not_authenticated',
          ),
        ),
      );
      expect(mainClient.auth.currentUser!.id, 'other-user');
      await mainClient.dispose();
    },
  );
  test(
    'near-expired exchange session is rejected without refresh or adoption',
    () async {
      final mainClient = SupabaseClient(
        'https://auth.example.test',
        'anon-key',
        httpClient: MockClient(
          (_) async => throw StateError('must not refresh'),
        ),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final transport = MockClient(
        (_) async => http.Response(
          jsonEncode(_sessionJson('near-expiry', lifetime: 40)),
          200,
        ),
      );
      final service = SocialAuthService(
        client: mainClient,
        httpClient: transport,
        config: configured,
        platform: TargetPlatform.android,
        acquireTokens: (p, _) async => SocialAuthProof(p, 'provider-token'),
      );
      await expectLater(
        service.signIn(SocialAuthProvider.google),
        throwsA(isA<SocialAuthFailure>()),
      );
      expect(mainClient.auth.currentUser, isNull);
      await mainClient.dispose();
    },
  );
}
