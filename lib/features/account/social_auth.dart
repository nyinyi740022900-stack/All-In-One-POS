import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';

enum SocialAuthProvider { google, apple }

/// Only stable codes leave this boundary; provider errors may contain tokens.
class SocialAuthFailure implements Exception {
  const SocialAuthFailure(this.code);
  final String code;
}

class SocialAuthProof {
  const SocialAuthProof(
    this.provider,
    this.idToken, {
    this.accessToken,
    this.nonce,
  });
  final SocialAuthProvider provider;
  final String idToken;
  final String? accessToken;
  final String? nonce;

  Map<String, dynamic> toRequest() => {
    'provider': provider.name,
    'id_token': idToken,
    if (accessToken != null) 'access_token': accessToken,
    if (nonce != null) 'nonce': nonce,
  };
}

/// Apple's native request gets the hash; Supabase gets the original nonce.
class SocialNonce {
  const SocialNonce(this.raw, this.sha256);
  final String raw;
  final String sha256;

  factory SocialNonce.generate() {
    final random = Random.secure();
    final raw = base64UrlEncode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    return SocialNonce(raw, crypto.sha256.convert(utf8.encode(raw)).toString());
  }
}

class SocialAuthConfig {
  const SocialAuthConfig({
    this.backendConfigured = false,
    this.googleEnabled = false,
    this.googleWebClientId = '',
    this.googleIosClientId = '',
    this.appleEnabled = false,
  });
  final bool backendConfigured;
  final bool googleEnabled;
  final String googleWebClientId;
  final String googleIosClientId;
  final bool appleEnabled;

  factory SocialAuthConfig.fromEnvironment() => SocialAuthConfig(
    backendConfigured: Env.hasBackend,
    googleEnabled: Env.googleAuthEnabled,
    googleWebClientId: Env.googleWebClientId,
    googleIosClientId: Env.googleIosClientId,
    appleEnabled: Env.appleAuthEnabled,
  );
}

typedef SocialTokenAcquirer =
    Future<SocialAuthProof> Function(
      SocialAuthProvider provider,
      SocialNonce? nonce,
    );
typedef SocialAuthExchange =
    Future<AuthResponse> Function(SocialAuthProof proof);

/// Native provider tokens are always verified by Supabase. Reauthentication
/// intentionally performs no Supabase call so deletion cannot switch sessions.
class SocialAuthService {
  SocialAuthService({
    this.client,
    this.httpClient,
    SocialAuthConfig? config,
    TargetPlatform? platform,
    bool? isWeb,
    this.acquireTokens,
    this.signInExchange,
    this.linkExchange,
  }) : _config = config ?? SocialAuthConfig.fromEnvironment(),
       _platform = platform ?? defaultTargetPlatform,
       _isWeb = isWeb ?? kIsWeb;

  final SupabaseClient? client;
  final http.Client? httpClient;
  final SocialAuthConfig _config;
  final TargetPlatform _platform;
  final bool _isWeb;
  final SocialTokenAcquirer? acquireTokens;
  final SocialAuthExchange? signInExchange;
  final SocialAuthExchange? linkExchange;
  static Future<void>? _googleInitialization;
  static SocialNonce? _googleNonce;
  static const _networkTimeout = Duration(seconds: 30);

  Set<SocialAuthProvider> get availableProviders {
    if (_isWeb || !_config.backendConfigured) return {};
    final mobile =
        _platform == TargetPlatform.iOS || _platform == TargetPlatform.android;
    return {
      if (mobile &&
          _config.googleEnabled &&
          _config.googleWebClientId.isNotEmpty &&
          (_platform != TargetPlatform.iOS ||
              _config.googleIosClientId.isNotEmpty))
        SocialAuthProvider.google,
      if (_platform == TargetPlatform.iOS && _config.appleEnabled)
        SocialAuthProvider.apple,
    };
  }

  Future<AuthResponse> signIn(SocialAuthProvider provider) async {
    final proof = await reauthenticate(provider);
    return _exchange(proof, link: false);
  }

  Future<AuthResponse> link(SocialAuthProvider provider) async {
    final main = client ?? Supabase.instance.client;
    var original = main.auth.currentSession;
    if (original == null) {
      throw const SocialAuthFailure('not_authenticated');
    }
    if (original.isExpired) {
      // An expired access token is not a different owner, and Supabase
      // refreshes this session routinely on its own. Refusing here made the
      // button fail *before* the Google sheet ever opened, which read on
      // screen as the app signing itself out: the account card only looks at
      // the user, so it went on showing the owner, the shop and the plan
      // while this call reported 'not_authenticated'.
      try {
        original = (await main.auth.refreshSession()).session;
      } on Exception {
        original = null;
      }
      if (original == null || original.isExpired) {
        throw const SocialAuthFailure('not_authenticated');
      }
    }
    final ownerId = original.user.id;
    final proof = await reauthenticate(provider);
    // The chooser can stay open while another tab/device flow changes the
    // app session. Do not send any linking mutation for a different account.
    // Compare the owner, not the token: a background refresh during the
    // chooser changes the access token without changing who is signed in.
    if (main.auth.currentSession == null ||
        main.auth.currentUser?.id != ownerId) {
      throw const SocialAuthFailure('not_authenticated');
    }
    return _exchange(proof, link: true);
  }

  Future<SocialAuthProof> reauthenticate(SocialAuthProvider provider) async {
    if (!availableProviders.contains(provider)) {
      throw const SocialAuthFailure('social_auth_unavailable');
    }
    final nonce = provider == SocialAuthProvider.apple
        ? SocialNonce.generate()
        : null;
    try {
      // User interaction has no timeout: a late dialog result must never trigger
      // a hidden sign-in after the caller has already reported a failure.
      final proof = await (acquireTokens ?? _nativeTokens)(provider, nonce);
      if (proof.provider != provider ||
          proof.idToken.trim().isEmpty ||
          (nonce != null && proof.nonce != nonce.raw)) {
        throw const SocialAuthFailure('social_auth_failed');
      }
      return proof;
    } on SocialAuthFailure {
      rethrow;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const SocialAuthFailure('auth_cancelled');
      }
      if (error.code == GoogleSignInExceptionCode.clientConfigurationError ||
          error.code == GoogleSignInExceptionCode.providerConfigurationError) {
        throw const SocialAuthFailure('social_auth_unavailable');
      }
      throw const SocialAuthFailure('social_auth_failed');
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        throw const SocialAuthFailure('auth_cancelled');
      }
      throw const SocialAuthFailure('social_auth_failed');
    } catch (_) {
      throw const SocialAuthFailure('social_auth_failed');
    }
  }

  Future<SocialAuthProof> _nativeTokens(
    SocialAuthProvider provider,
    SocialNonce? nonce,
  ) async {
    switch (provider) {
      case SocialAuthProvider.google:
        final google = GoogleSignIn.instance;
        // Google's sign-in always puts a nonce in the ID token, so Supabase
        // has to be given the matching one — without it the exchange fails
        // with "Passed nonce and nonce in id_token should either both exist
        // or not", which reached the owner as "Could not sign in with this
        // account". Supabase compares the SHA-256 of what it is handed
        // against the token's claim, so this is the same split Apple uses:
        // the provider is given the hash (it echoes it verbatim into the
        // token) and Supabase the original. Sending the raw value to both
        // is what produced the follow-up "invalid nonce: Nonces mismatch".
        // google_sign_in only accepts a nonce at initialize(), which runs
        // once per process, so it is fixed for this app run and has to be
        // remembered here for every later exchange.
        _googleNonce ??= SocialNonce.generate();
        // Google 7.x requires exactly one initialization per singleton, even
        // when multiple repositories are created as the active shop changes.
        _googleInitialization ??= google.initialize(
          clientId: _platform == TargetPlatform.iOS
              ? _config.googleIosClientId
              : null,
          serverClientId: _config.googleWebClientId,
          nonce: _googleNonce!.sha256,
        );
        await _googleInitialization!.timeout(_networkTimeout);
        if (!google.supportsAuthenticate()) {
          throw const SocialAuthFailure('social_auth_unavailable');
        }
        final account = await google.authenticate();
        return SocialAuthProof(
          provider,
          account.authentication.idToken ?? '',
          nonce: _googleNonce!.raw,
        );
      case SocialAuthProvider.apple:
        if (!await SignInWithApple.isAvailable().timeout(_networkTimeout)) {
          throw const SocialAuthFailure('social_auth_unavailable');
        }
        final credential = await SignInWithApple.getAppleIDCredential(
          scopes: [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
          nonce: nonce!.sha256,
        );
        return SocialAuthProof(
          provider,
          credential.identityToken ?? '',
          nonce: nonce.raw,
        );
    }
  }

  Future<AuthResponse> _exchange(
    SocialAuthProof proof, {
    required bool link,
  }) async {
    try {
      final exchange = link ? linkExchange : signInExchange;
      if (exchange != null) {
        return await exchange(proof).timeout(_networkTimeout);
      }
      return await _isolatedExchange(proof, link: link);
    } on SocialAuthFailure {
      rethrow;
    } on AuthException catch (error) {
      // Preserve Supabase's stable codes (never provider description/message).
      throw SocialAuthFailure(error.code ?? 'social_auth_failed');
    } catch (_) {
      throw const SocialAuthFailure('social_auth_failed');
    }
  }

  Future<AuthResponse> _isolatedExchange(
    SocialAuthProof proof, {
    required bool link,
  }) async {
    final main = client ?? Supabase.instance.client;
    final original = main.auth.currentSession;
    if (link && (original == null || original.isExpired)) {
      throw const SocialAuthFailure('not_authenticated');
    }
    final transport = _BoundedAuthHttpClient(
      httpClient ?? http.Client(),
      ownsDelegate: httpClient == null,
    );
    final isolated = GoTrueClient(
      url: main.rest.url.replaceFirst(RegExp(r'/rest/v1/?$'), '/auth/v1'),
      headers: Map<String, String>.from(main.auth.headers),
      autoRefreshToken: false,
      httpClient: transport,
    );
    try {
      if (link) {
        // Restore into the isolated client only. Its bearer JWT tells Supabase
        // which user's identity to link without changing the application's JWT.
        await isolated.setInitialSession(jsonEncode(original!.toJson()));
      }
      final provider = proof.provider == SocialAuthProvider.google
          ? OAuthProvider.google
          : OAuthProvider.apple;
      final response =
          await (link
                  ? isolated.linkIdentityWithIdToken(
                      provider: provider,
                      idToken: proof.idToken,
                      accessToken: proof.accessToken,
                      nonce: proof.nonce,
                    )
                  : isolated.signInWithIdToken(
                      provider: provider,
                      idToken: proof.idToken,
                      accessToken: proof.accessToken,
                      nonce: proof.nonce,
                    ))
              .timeout(_networkTimeout);
      final session = response.session;
      // Reject unexpected short-lived server sessions before local adoption.
      final minimumExpiry =
          DateTime.now()
              .add(const Duration(minutes: 1))
              .millisecondsSinceEpoch ~/
          1000;
      if (session == null ||
          session.expiresAt == null ||
          session.expiresAt! <= minimumExpiry) {
        throw const SocialAuthFailure('social_auth_failed');
      }
      // Linking compares owners for the same reason [link] does: a refresh
      // in flight is not a session swap. Signing in still compares tokens —
      // there is no session of our own to refresh in that case, so any change
      // at all means something else signed in concurrently.
      final swapped = link
          ? main.auth.currentUser?.id != original!.user.id ||
                session.user.id != original.user.id
          : main.auth.currentSession?.accessToken != original?.accessToken;
      if (swapped) {
        throw const SocialAuthFailure('not_authenticated');
      }
      // No timeout around a shared-session mutation: the bounded exchange has
      // already completed. A late isolated result can never reach this point.
      await main.auth.setInitialSession(jsonEncode(session.toJson()));
      return AuthResponse(session: main.auth.currentSession);
    } finally {
      isolated.dispose();
      transport.close();
    }
  }
}

/// Bounds native Auth HTTP headers and body reads. Only the isolated auth
/// client sees a late response, and disposal closes the owned socket client.
class _BoundedAuthHttpClient extends http.BaseClient {
  _BoundedAuthHttpClient(this.delegate, {required this.ownsDelegate});
  final http.Client delegate;
  final bool ownsDelegate;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await delegate
        .send(request)
        .timeout(SocialAuthService._networkTimeout);
    return http.StreamedResponse(
      response.stream.timeout(SocialAuthService._networkTimeout),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() {
    if (ownsDelegate) delegate.close();
  }
}
