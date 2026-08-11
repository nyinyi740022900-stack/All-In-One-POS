import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

/// Shared "forgot password" flow — a Supabase password-reset email, deep
/// linking back into the app via `mmpos://login-callback`. Shown from both
/// the onboarding Sign-in tab and Settings → Shop login, which otherwise
/// duplicated this dialog verbatim.
Future<void> showForgotPasswordDialog(
  BuildContext context, {
  String prefillEmail = '',
}) async {
  final l = AppLocalizations.of(context);
  final email = TextEditingController(text: prefillEmail);
  final sent = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.accountResetPasswordTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.accountResetPasswordHint,
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: email,
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
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: () async {
            if (email.text.trim().isEmpty) return;
            try {
              await Supabase.instance.client.auth.resetPasswordForEmail(
                email.text.trim(),
                redirectTo: 'mmpos://login-callback',
              );
            } catch (_) {
              // Supabase deliberately doesn't reveal whether the email
              // exists — show the same "check your email" outcome either
              // way rather than leaking account existence via an error.
            }
            if (ctx.mounted) Navigator.pop(ctx, true);
          },
          child: Text(l.accountResetPasswordSend),
        ),
      ],
    ),
  );
  email.dispose();
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.accountResetPasswordSent)));
  }
}
