import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import 'account_providers.dart';
import 'auth_password_field.dart';
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
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _password.text),
      );
      final email =
          Supabase.instance.client.auth.currentUser?.email?.trim() ?? '';
      if (email.isNotEmpty) {
        await ref.read(savedLoginStoreProvider).save(
              email: email,
              password: _password.text,
            );
      }
      if (!mounted) return;
      ref.read(passwordRecoveryPendingProvider.notifier).state = false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.accountResetPasswordSuccess)));
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
    return AuthScaffold(
      appBar: AppBar(title: Text(l.accountResetPasswordTitle)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BrandHero(size: 64),
          const SizedBox(height: AppTheme.space5),
          AuthPasswordField(
            controller: _password,
            labelText: l.accountResetPasswordNewLabel,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.next,
            autofocus: true,
          ),
          const SizedBox(height: AppTheme.space3),
          AuthPasswordField(
            controller: _confirmPassword,
            labelText: l.accountConfirmPassword,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppTheme.space3),
            InlineErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppTheme.space5),
          FilledButton(
            style: AppTheme.authFilledButtonStyle(),
            onPressed: _busy ? null : _save,
            child: Text(l.accountResetPasswordSave),
          ),
        ],
      ),
    );
  }
}
