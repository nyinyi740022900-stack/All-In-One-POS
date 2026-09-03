import 'package:supabase_flutter/supabase_flutter.dart';

/// Bound on a single Edge Function round trip.
///
/// `functions.invoke` has no timeout of its own: a stalled connection (weak
/// signal, a dead Wi-Fi that still associates, a captive portal) leaves the
/// `await` pending indefinitely, so whatever spinner the caller showed has no
/// way to ever resolve. The owner hit this on Create Account — the button
/// span forever rather than failing into a "no internet" message (#298).
///
/// #298 fixed it at the one call site it was reported on. This is the same
/// bound applied where it actually belongs — the transport — because the
/// other 27 call sites (the whole admin console, the storefront API, branch
/// switching, and the sync engine's force-apply) were still unbounded, i.e.
/// still able to hang exactly the same way.
const kEdgeInvokeTimeout = Duration(seconds: 15);

/// `invoke`, but it always ends.
///
/// Use this instead of `functions.invoke` everywhere — `edge_invoke_test.dart`
/// fails on a bare `functions.invoke(` outside this file, so a new call site
/// cannot reintroduce an unbounded await by omission.
///
/// A [TimeoutException] from here is classified as `network_error` by
/// `classifyInvokeError`, so callers surface "no internet" rather than a
/// generic failure.
extension BoundedEdgeInvoke on FunctionsClient {
  Future<FunctionResponse> invokeBounded(
    String functionName, {
    Object? body,
    Map<String, String>? headers,
    Duration timeout = kEdgeInvokeTimeout,
  }) {
    return invoke(functionName, body: body, headers: headers)
        .timeout(timeout);
  }
}
