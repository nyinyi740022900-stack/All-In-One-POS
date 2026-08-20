import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Last successful email/password on THIS device.
///
/// Lives in the OS keychain/keystore (not Drift / AppSettings) so it is not
/// synced, not backed up into shop DB files, and does not roam to another
/// phone. Sign-out keeps it — that's the point of remembering. Account
/// deletion clears it.
class SavedLogin {
  const SavedLogin({required this.email, required this.password});
  final String email;
  final String password;
}

bool savedLoginMatchesEmail(String typed, String savedEmail) =>
    typed.trim().toLowerCase() == savedEmail.trim().toLowerCase();

class SavedLoginStore {
  SavedLoginStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  static const _emailKey = 'auth.saved_email';
  static const _passwordKey = 'auth.saved_password';

  Future<SavedLogin?> read() async {
    try {
      final email = (await _storage.read(key: _emailKey))?.trim() ?? '';
      final password = await _storage.read(key: _passwordKey) ?? '';
      if (email.isEmpty || password.isEmpty) return null;
      return SavedLogin(email: email, password: password);
    } catch (_) {
      return null;
    }
  }

  Future<void> save({required String email, required String password}) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty || password.isEmpty) return;
    try {
      await _storage.write(key: _emailKey, value: trimmed);
      await _storage.write(key: _passwordKey, value: password);
    } catch (_) {
      /* tests / locked keychain */
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _emailKey);
      await _storage.delete(key: _passwordKey);
    } catch (_) {}
  }
}

/// Prefills a sign-in form from [SavedLoginStore], and clears the password
/// field if the typed email is no longer the remembered one (so a second
/// account on the same phone does not inherit the first password).
class SavedLoginBinder {
  SavedLoginBinder({required this.email, required this.password});

  final TextEditingController email;
  final TextEditingController password;
  String? _savedEmail;
  String? _savedPassword;

  void attach() => email.addListener(_onEmailChanged);

  void detach() => email.removeListener(_onEmailChanged);

  Future<void> load(SavedLoginStore store) async {
    final saved = await store.read();
    if (saved == null) return;
    applySaved(saved);
  }

  /// Seeds the binder the same way [load] does after a successful read.
  /// Tests call this so they don't need a real Keychain/Keystore.
  void applySaved(SavedLogin saved) {
    _savedEmail = saved.email;
    _savedPassword = saved.password;
    if (email.text.isEmpty) email.text = saved.email;
    _onEmailChanged();
  }

  Future<void> remember(
    SavedLoginStore store, {
    required String email,
    required String password,
  }) {
    TextInput.finishAutofillContext();
    _savedEmail = email.trim();
    _savedPassword = password;
    return store.save(email: email, password: password);
  }

  void _onEmailChanged() {
    final savedEmail = _savedEmail;
    final savedPassword = _savedPassword;
    if (savedEmail == null || savedPassword == null) return;
    if (savedLoginMatchesEmail(email.text, savedEmail)) {
      if (password.text.isEmpty) password.text = savedPassword;
    } else if (password.text == savedPassword) {
      password.clear();
    }
  }

  /// After sign-out the password field was cleared; put it back if the
  /// email is still the remembered one.
  void refillIfMatch() => _onEmailChanged();

  void forget() {
    _savedEmail = null;
    _savedPassword = null;
    password.clear();
  }
}
