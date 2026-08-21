import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

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
      return fromBody ?? 'not_authenticated';
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
    try {
      await client.auth.refreshSession();
    } catch (_) {}
    token = client.auth.currentSession?.accessToken;
  }
  return client.functions.invoke(
    'activate',
    body: body,
    headers: {
      if (token != null) 'Authorization': 'Bearer $token',
    },
  );
}
