import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

/// Callback arrival is not proof that an email changed: secure email change
/// may still be waiting for the other inbox, or Supabase may still be parsing.
class AuthCallbackScreen extends StatelessWidget {
  const AuthCallbackScreen({super.key, required this.invalid});
  final bool invalid;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.accountConfirmationTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.space4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    invalid ? Icons.link_off : Icons.mark_email_read_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: AppTheme.space4),
                  Text(
                    invalid
                        ? l.accountConfirmationInvalid
                        : l.accountConfirmationReturn,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppTheme.space3),
                  Text(
                    invalid
                        ? l.accountConfirmationInvalidHelp
                        : l.accountConfirmationReturnHelp,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTheme.space4),
                  FilledButton(
                    onPressed: () => context.go('/settings'),
                    child: Text(l.navShop),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
