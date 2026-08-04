import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';

Future<void> main() async {
  // With a Sentry DSN configured, run inside Sentry so uncaught errors are
  // reported; otherwise run the app directly (crash reporting disabled).
  if (Env.hasCrashReporting) {
    await SentryFlutter.init(
      (o) {
        o.dsn = Env.sentryDsn;
        o.tracesSampleRate = 0.2;
      },
      appRunner: _bootstrap,
    );
  } else {
    await _bootstrap();
  }
}

Future<void> _bootstrap() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Surface framework errors and forward them to Sentry when enabled.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
      if (Env.hasCrashReporting) {
        Sentry.captureException(details.exception, stackTrace: details.stack);
      }
    };

    // Initialize Supabase only when backend config is provided. This lets the
    // app run fully offline (no credentials required).
    if (Env.hasBackend) {
      try {
        await Supabase.initialize(
          url: Env.supabaseUrl,
          // anon key == publishable key; safe to ship (RLS enforces access).
          publishableKey: Env.supabaseAnonKey,
          // PKCE is the recommended flow for a mobile deep-link password
          // reset (see PasswordRecoveryWatcher) — the implicit flow's
          // tokens-in-fragment shape doesn't suit the mmpos:// custom scheme.
          authOptions:
              const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
        );
      } catch (e) {
        // Never let a backend init failure block an offline-first app.
        debugPrint('Supabase init failed (continuing offline): $e');
      }
    }

    runApp(const ProviderScope(child: MmPosApp()));
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error');
    if (Env.hasCrashReporting) {
      Sentry.captureException(error, stackTrace: stack);
    }
  });
}
