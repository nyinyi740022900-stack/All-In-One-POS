import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import 'password_recovery_watcher.dart';

/// Shown full-screen (via `app.dart`'s `builder:` override) when a
/// password-recovery deep link just opened the app. Lets the owner set a new
/// password for the account the reset email was sent to, then returns
/// control to the normal app.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    if (_password.text.isEmpty) return;
    if (_password.text != _confirmPassword.text) {
      setState(() => _error = l.accountPasswordMismatch);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: _password.text));
      if (!mounted) return;
      ref.read(passwordRecoveryPendingProvider.notifier).state = false;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.accountResetPasswordSuccess)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = l.accountActionFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.accountResetPasswordTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.space4),
        children: [
          TextField(
            controller: _password,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l.accountResetPasswordNewLabel,
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.space2),
          TextField(
            controller: _confirmPassword,
            obscureText: _obscure,
            decoration: InputDecoration(labelText: l.accountConfirmPassword),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppTheme.space2),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: AppTheme.space4),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(l.accountResetPasswordSave),
          ),
        ],
      ),
    );
  }
}
