import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Attestation fields for the `activate` calls that hand out a trial or a
/// Premium receipt. The server (supabase/functions/_shared/play_integrity.ts)
/// verifies them with Google, records the verdict, and — only once the admin
/// sets `integrity.android_mode` to `enforce` — refuses a copy that fails.
///
/// Every call gets `platform` and `app_build`. Android calls in
/// [gatedActions] also get a one-time `integrity_nonce` and either an
/// `integrity_token` bound to it, or `integrity_error` saying why there is
/// none (no Play services, not configured, timeout). This never throws and
/// never blocks the call itself: deciding is the server's job.
class PlayIntegrity {
  PlayIntegrity._();

  /// Mirrors GATED_ACTIONS on the server.
  static const gatedActions = {
    'refresh_account_license',
    'resync_session',
    'switch_branch',
    'start_trial',
  };

  /// The Google Cloud project linked to the app in Play Console (a project
  /// NUMBER, public — not a secret). Empty → `integrity_error: not_configured`.
  static const cloudProjectNumber = String.fromEnvironment(
    'PLAY_INTEGRITY_CLOUD_PROJECT',
  );

  static const _channel = MethodChannel('com.allinonepos.app/integrity');
  // Bounded well inside the refresh call's own budget: a slow Play
  // services must cost one 'timeout' verdict, never the refresh itself.
  static const _tokenTimeout = Duration(seconds: 5);

  /// Adds the attestation fields to an `activate` request body.
  static Future<Map<String, dynamic>> attach(Map<String, dynamic> body) async {
    final action = body['action'];
    if (action is! String || !gatedActions.contains(action)) return body;
    return {...body, ...await fields(action, '${body['device_id'] ?? ''}')};
  }

  @visibleForTesting
  static Future<Map<String, Object?>> fields(
    String action,
    String deviceId, {
    Future<String?> Function(String requestHash)? tokenFor,
  }) async {
    final out = <String, Object?>{
      'platform': platform,
      'app_build': await _appBuild(),
    };
    if (out['platform'] != 'android') return out;
    final nonce = _nonce();
    out['integrity_nonce'] = nonce;
    if (tokenFor == null && cloudProjectNumber.isEmpty) {
      out['integrity_error'] = 'not_configured';
      return out;
    }
    final hash = requestHash(action, deviceId, nonce);
    try {
      final token = await (tokenFor ?? _token)(hash).timeout(_tokenTimeout);
      if (token == null || token.isEmpty) {
        out['integrity_error'] = 'empty_token';
      } else {
        out['integrity_token'] = token;
      }
    } on PlatformException catch (e) {
      out['integrity_error'] = e.code;
    } on TimeoutException {
      out['integrity_error'] = 'timeout';
    } catch (_) {
      out['integrity_error'] = 'exception';
    }
    return out;
  }

  /// Same string and hash as `requestHash` on the server.
  static String requestHash(String action, String deviceId, String nonce) =>
      sha256
          .convert(utf8.encode('aiopos.pi.v1|$action|$deviceId|$nonce'))
          .toString();

  @visibleForTesting
  static String platformFor({required bool web, required TargetPlatform os}) {
    if (web) return 'web';
    return switch (os) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  static String get platform =>
      platformFor(web: kIsWeb, os: defaultTargetPlatform);

  static Future<String?> _token(String hash) => _channel.invokeMethod<String>(
    'integrityToken',
    {'cloudProjectNumber': cloudProjectNumber, 'requestHash': hash},
  );

  static int? _build;
  static Future<int> _appBuild() async {
    if (_build != null) return _build!;
    try {
      final info = await PackageInfo.fromPlatform();
      return _build = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static String _nonce() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
