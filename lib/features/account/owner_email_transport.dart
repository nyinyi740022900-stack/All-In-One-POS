import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Email changes require the owner's existing bearer. The SDK's updateUser
/// mutates its session after HTTP completion, so isolate it until we know this
/// is still the same session. A late result must never replace another owner.
Future<User> requestOwnerEmail(
  SupabaseClient main,
  String email, {
  http.Client? transport,
}) async {
  final original = main.auth.currentSession;
  if (original == null ||
      original.isExpired ||
      original.user.isAnonymous ||
      original.user.appMetadata['role'] != 'owner') {
    throw StateError('owner_session_required');
  }
  final client = transport ?? http.Client();
  final isolated = GoTrueClient(
    url: main.rest.url.replaceFirst(RegExp(r'/rest/v1/?$'), '/auth/v1'),
    headers: Map<String, String>.from(main.auth.headers),
    autoRefreshToken: false,
    httpClient: client,
  );
  try {
    await isolated.setInitialSession(jsonEncode(original.toJson()));
    final response = await isolated
        .updateUser(
          UserAttributes(email: email),
          emailRedirectTo: 'allinonepos://login-callback',
        )
        .timeout(const Duration(seconds: 30));
    final user = response.user;
    if (user == null ||
        user.id != original.user.id ||
        main.auth.currentSession?.accessToken != original.accessToken ||
        main.auth.currentUser?.id != original.user.id) {
      throw StateError('owner_session_changed');
    }
    await main.auth.setInitialSession(
      jsonEncode(original.copyWith(user: user).toJson()),
    );
    return user;
  } finally {
    isolated.dispose();
    if (transport == null) client.close();
  }
}
