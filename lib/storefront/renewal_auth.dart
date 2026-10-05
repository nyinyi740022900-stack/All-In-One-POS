import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/net/edge_invoke.dart';

/// Browser billing login never registers a POS device or creates a shop.
class RenewalAuth {
  SupabaseClient get _client => Supabase.instance.client;

  /// Keep the callback on this deployment; never forward tokens or a caller's
  /// arbitrary return URL to Google/Supabase.
  static Uri redirectUri(Uri page) => Uri(
    scheme: page.scheme,
    host: page.host,
    port: page.hasPort ? page.port : null,
    path: '/renew',
  );

  Future<bool> signInWithGoogle() => _client.auth
      .signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUri(Uri.base).toString(),
        queryParams: const {'prompt': 'select_account'},
      )
      .timeout(kEdgeInvokeTimeout);

  /// Resolve authoritative membership even when a freshly linked Google
  /// session has no role yet. Email, user_metadata and URL parameters never
  /// decide ownership. Refresh only after the server stamps its claims.
  Future<bool> prepareAccount() async {
    final accountId = _client.auth.currentUser?.id;
    if (accountId == null || _client.auth.currentUser!.isAnonymous) {
      throw StateError('account_required');
    }
    final response = await _client.functions.invokeBounded(
      'activate',
      body: const {'action': 'prepare_social_account'},
    );
    final data = response.data;
    if (_client.auth.currentUser?.id != accountId) {
      throw StateError('account_changed');
    }
    if (data is! Map || data['ok'] != true) {
      throw StateError('membership_unavailable');
    }
    if (data['needs_shop_name'] == true) return false;
    final refreshed = await _client.auth.refreshSession().timeout(
      kEdgeInvokeTimeout,
    );
    if (refreshed.user?.id != accountId ||
        _client.auth.currentUser?.id != accountId) {
      throw StateError('account_changed');
    }
    return refreshed.user?.appMetadata['role'] == 'owner';
  }
}
