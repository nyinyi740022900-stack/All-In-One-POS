import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

/// Shared "forgot password" flow — a Supabase password-reset email, deep
/// linking back into the app via `mmpos://login-callback`. Shown from both
/// the onboarding Sign-in tab and Settings → Shop login, which otherwise
/// duplicated this dialog verbatim.
///
/// The controller lives in this [StatefulWidget] (not the caller's method)
/// on purpose: a controller created here and disposed after `showDialog`
/// resolves stays bound to the still-visible TextField for the length of
/// the route's exit transition, whose cursor-blink ticker touches it — the
/// exact "used after being disposed" crash this codebase has fixed five
/// times elsewhere.
Future<void> showForgotPasswordDialog(
  BuildContext context, {
  String prefillEmail = '',
}) async {
  final l = AppLocalizations.of(context);
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => _ForgotPasswordDialog(prefillEmail: prefillEmail),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.accountResetPasswordSent)),
    );
  }
}

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({required this.prefillEmail});

  final String prefillEmail;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _email;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.prefillEmail);
  }

  @override
  void dispose() {
    // Runs only when this dialog's own widget tree is gone — never while
    // its TextField is still on screen.
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_email.text.trim().isEmpty) return;
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _email.text.trim(),
        redirectTo: 'mmpos://login-callback',
      );
    } catch (_) {
      // Supabase deliberately doesn't reveal whether the email exists —
      // show the same "check your email" outcome either way rather than
      // leaking account existence via an error.
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.accountResetPasswordTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.accountResetPasswordHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _email,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: l.accountEmail),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: _send,
          child: Text(l.accountResetPasswordSend),
        ),
      ],
    );
  }
}
