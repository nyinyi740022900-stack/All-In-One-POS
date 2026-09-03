import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Bound on a single Edge Function round trip. Without this, a stalled
/// connection (weak signal, dead Wi-Fi) leaves `functions.invoke` awaiting
/// forever — the caller's spinner looks frozen rather than failing into a
/// "no internet" message the user can act on.
const _invokeTimeout = Duration(seconds: 15);
const _refreshTimeout = Duration(seconds: 8);

/// Best-effort session refresh, bounded so a stalled connection can't hang a
/// caller that's already wrapping this in `try {} catch (_) {}` for the
/// "refresh failed, fall through to the original result" case — a silent
/// catch only guards against a thrown error, not an `await` that never
/// returns.
Future<void> refreshSessionBounded() async {
  try {
    await Supabase.instance.client.auth.refreshSession().timeout(_refreshTimeout);
  } catch (_) {}
}

/// Parses Edge Function JSON whether supabase_flutter decoded a Map, a
/// nested map with non-String keys, or left a JSON string.
Map<String, dynamic>? parseInvokeData(dynamic data) {
  if (data == null) return null;
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  if (data is String) {
    final trimmed = data.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return null;
}

String? errorCodeFromInvokeData(Map<String, dynamic>? data) {
  if (data == null) return null;
  final error = data['error'];
  if (error is String && error.isNotEmpty) return error;
  return null;
}

/// True only for actual connectivity failures — never for HTTP 4xx/5xx or
/// a JSON shape we failed to parse. Those used to be labelled "no internet"
/// and blocked Check for renewal on a phone that was clearly online.
bool isLikelyNetworkError(Object error) {
  if (error is FunctionException) return false;
  if (error is TimeoutException) return true;
  final text = error.toString().toLowerCase();
  return text.contains('socketexception') ||
      text.contains('clientexception') ||
      text.contains('failed host lookup') ||
      text.contains('failed to fetch') ||
      text.contains('xmlhttprequest') ||
      text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('network is unreachable') ||
      text.contains('network_error') ||
      (text.contains('timed out') && text.contains('connection'));
}

String? _errorCodeFromDetails(dynamic details) {
  final map = parseInvokeData(details);
  return errorCodeFromInvokeData(map);
}

/// Maps a thrown [functions.invoke] failure to a stable error code.
String classifyInvokeError(Object error) {
  if (isLikelyNetworkError(error)) return 'network_error';
  if (error is FunctionException) {
    final fromBody = _errorCodeFromDetails(error.details);
    // 401 with a prose body ("Invalid JWT") used to become an unmapped
    // code and show "Something went wrong" after a successful password.
    if (error.status == 401) {
      return fromBody == 'not_activated' ? 'not_activated' : 'not_authenticated';
    }
    if (error.status == 403) {
      // Every current 403 from `activate` carries its own `error: "forbidden"`
      // body, so this fallback is defensive only (a bodyless 403 from a
      // gateway/WAF in front of the function, say) — a permission failure
      // isn't a session problem, and 'not_authenticated' would tell the user
      // to just retry something that can never succeed.
      return fromBody ?? 'forbidden';
    }
    if (fromBody != null) return fromBody;
    return 'server_error';
  }
  return 'server_error';
}

/// Always send the *user* JWT. [FunctionsClient] copies default headers
/// that can still say `Authorization: Bearer <anon key>`; AuthHttpClient
/// then `putIfAbsent`s and never overwrites — so `activate` saw an anon
/// caller, returned 401 `not_authenticated`, and the app showed
/// "Something went wrong" after a successful email/password.
Future<FunctionResponse> invokeActivate(Map<String, dynamic> body) async {
  final client = Supabase.instance.client;
  var token = client.auth.currentSession?.accessToken;
  if (token == null) {
    await refreshSessionBounded();
    token = client.auth.currentSession?.accessToken;
  }
  return client.functions
      .invoke(
        'activate',
        body: body,
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        },
      )
      .timeout(_invokeTimeout);
}
