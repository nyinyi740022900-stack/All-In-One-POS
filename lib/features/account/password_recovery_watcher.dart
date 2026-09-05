import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';

/// Flips to `true` when a password-recovery deep link
/// (`allinonepos://login-callback`, or the pre-rebrand `mmpos://` scheme for
/// links from before an install updates) just opened the app — `app.dart`'s `builder:` override shows
/// `ResetPasswordScreen` full-screen while this is true, same mechanism
/// already used for `OnboardingFlow`. Set back to `false` by
/// `ResetPasswordScreen` once the new password is saved.
final passwordRecoveryPendingProvider = StateProvider<bool>((ref) => false);

/// Listens to Supabase's own auth-state stream for the whole app lifetime
/// (kept alive via [passwordRecoveryWatcherProvider], watched once in
/// `app.dart`) — `supabase_flutter` parses the incoming deep link's tokens
/// itself and fires `AuthChangeEvent.passwordRecovery` on this stream; no
/// app-side deep-link package/plumbing is needed beyond registering the URL
/// scheme natively (see `ios/Runner/Info.plist` /
/// `android/app/src/main/AndroidManifest.xml`).
class PasswordRecoveryWatcher {
  PasswordRecoveryWatcher(this._ref) {
    if (!Env.hasBackend) return;
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        _ref.read(passwordRecoveryPendingProvider.notifier).state = true;
      }
    });
  }

  final Ref _ref;
  StreamSubscription<AuthState>? _sub;

  void dispose() => _sub?.cancel();
}

/// Kept alive for the app's lifetime (watched in `app.dart`, same pattern as
/// `storefrontOrderWatcherProvider`).
final passwordRecoveryWatcherProvider = Provider<PasswordRecoveryWatcher>((ref) {
  final watcher = PasswordRecoveryWatcher(ref);
  ref.onDispose(watcher.dispose);
  return watcher;
});
