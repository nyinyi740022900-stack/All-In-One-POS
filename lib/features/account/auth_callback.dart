/// Keep auth payloads with Supabase's deep-link listener. Routing only needs a
/// safe status; tokens and server descriptions must never reach error UI.
String? authCallbackLocation(Uri uri) {
  final native =
      uri.scheme == 'allinonepos' &&
      uri.host == 'login-callback' &&
      (uri.path.isEmpty || uri.path == '/');
  final local =
      !uri.hasScheme &&
      !uri.hasAuthority &&
      (uri.path == '/login-callback' || uri.path == '/login-callback/');
  if (!native && !local) return null;
  Map<String, String> fragment;
  try {
    fragment = Uri.splitQueryString(uri.fragment);
  } on FormatException {
    return '/auth-callback?status=invalid';
  }
  final params = {...uri.queryParameters, ...fragment};
  final invalid =
      params.containsKey('error') ||
      params.containsKey('error_code') ||
      params.containsKey('error_description');
  return invalid ? '/auth-callback?status=invalid' : '/auth-callback';
}
