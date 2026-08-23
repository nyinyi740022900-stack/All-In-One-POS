import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';
import 'core/providers.dart';
import 'data/local/database_session.dart';
import 'features/desktop/windows_shortcut.dart';

Future<void> main() async {
  // With a Sentry DSN configured, run inside Sentry so uncaught errors are
  // reported; otherwise run the app directly (crash reporting disabled).
  if (Env.hasCrashReporting) {
    await SentryFlutter.init((o) {
      o.dsn = Env.sentryDsn;
      o.tracesSampleRate = 0.2;
    }, appRunner: _bootstrap);
  } else {
    await _bootstrap();
  }
}

Future<void> _bootstrap() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Audit H2 follow-up: product thumbs load via cached_network_image,
      // whose disk store runs on sqflite. sqflite ships no native Windows
      // implementation — it needs the FFI factory (sqlite3_flutter_libs
      // already provides the sqlite3 dll for this project). Without this,
      // every photo on the Windows POS would fail its disk-cache open and
      // fall back to the initials plate forever.
      if (!kIsWeb && Platform.isWindows) {
        sqflite_ffi.sqfliteFfiInit();
        sqflite_ffi.databaseFactory = sqflite_ffi.databaseFactoryFfi;
      }

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
      //
      // Audit M5: the backend client setup and the local SQLite session are
      // independent — start BOTH at once instead of serialising two plugin
      // round-trips ahead of the first frame. Both must still settle before
      // runApp: the first build reads the DB session AND (on paid plans)
      // drives Supabase auth through the sync/license controllers.
      final bootStopwatch = Stopwatch()..start();
      final dbSessionFuture = DatabaseSession.open();
      final supabaseInit = Env.hasBackend
          ? () async {
              try {
                await Supabase.initialize(
                  url: Env.supabaseUrl,
                  // anon key == publishable key; safe to ship (RLS enforces access).
                  publishableKey: Env.supabaseAnonKey,
                  // PKCE is the recommended flow for a mobile deep-link password
                  // reset (see PasswordRecoveryWatcher) — the implicit flow's
                  // tokens-in-fragment shape doesn't suit the mmpos:// custom scheme.
                  authOptions: const FlutterAuthClientOptions(
                    authFlowType: AuthFlowType.pkce,
                  ),
                );
              } catch (e) {
                // Never let a backend init failure block an offline-first app.
                debugPrint('Supabase init failed (continuing offline): $e');
              }
            }()
          : Future<void>.value();

      final session = await dbSessionFuture;
      await supabaseInit;
      if (kDebugMode) {
        debugPrint(
            'boot: db + backend ready in ${bootStopwatch.elapsedMilliseconds}ms');
      }

      runApp(
        ProviderScope(
          overrides: [
            databaseSessionProvider.overrideWith((ref) {
              ref.onDispose(session.disposeSessions);
              return session;
            }),
          ],
          child: const MmPosApp(),
        ),
      );
      unawaited(ensureWindowsAppShortcuts());
    },
    (error, stack) {
      debugPrint('Uncaught zone error: $error');
      if (Env.hasCrashReporting) {
        Sentry.captureException(error, stackTrace: stack);
      }
    },
  );
}
