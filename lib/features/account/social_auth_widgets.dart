import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import 'account_repository.dart';
import 'social_auth.dart';

/// An empty provider set occupies no space, including separators.
class SocialAuthButtons extends StatelessWidget {
  const SocialAuthButtons({
    super.key,
    required this.providers,
    required this.busy,
    required this.onSelected,
    this.linking = false,
    this.showSeparator = true,
  });

  final Set<SocialAuthProvider> providers;
  final bool busy;
  final ValueChanged<SocialAuthProvider> onSelected;
  final bool linking;
  final bool showSeparator;

  @override
  Widget build(BuildContext context) {
    if (providers.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final provider in SocialAuthProvider.values)
          if (providers.contains(provider)) ...[
            OutlinedButton(
              key: ValueKey('social-${provider.name}'),
              style: AppTheme.authOutlinedButtonStyle(),
              onPressed: busy ? null : () => onSelected(provider),
              child: Text(switch ((provider, linking)) {
                (SocialAuthProvider.google, false) => l.accountContinueGoogle,
                (SocialAuthProvider.apple, false) => l.accountContinueApple,
                (SocialAuthProvider.google, true) => l.accountLinkGoogle,
                (SocialAuthProvider.apple, true) => l.accountLinkApple,
              }, textAlign: TextAlign.center),
            ),
            const SizedBox(height: AppTheme.space2),
          ],
        if (showSeparator) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.space2),
            child: Text(l.accountOrEmail, textAlign: TextAlign.center),
          ),
          const SizedBox(height: AppTheme.space2),
        ],
      ],
    );
  }
}

/// Shared orchestration so every entry point handles first-shop setup and a
/// switch to another real shop identically. Callers keep their busy guard set
/// until this future completes and apply the returned license as usual.
Future<AccountActionResult?> runSocialSignIn(
  BuildContext context, {
  required Future<AccountActionResult> Function() signIn,
  required Future<AccountActionResult> Function(String) completeSignup,
  required Future<AccountActionResult> Function() confirmSwitch,
  Future<void> Function()? cancelSession,
  bool Function()? canRecoverDevice,
}) async {
  final abandon =
      cancelSession ?? () => Supabase.instance.client.auth.signOut();
  Future<void> abandonUnfinished(AccountActionResult result) async {
    final deviceRecovery =
        (result.error == 'device_limit_reached' ||
            result.error == 'free_device_replacement_required') &&
        (canRecoverDevice?.call() ?? false);
    if (!result.ok &&
        result.error != 'auth_cancelled' &&
        result.error != 'social_auth_unavailable' &&
        !deviceRecovery) {
      await abandon();
    }
  }

  var result = await signIn();
  if (!context.mounted) {
    await abandonUnfinished(result);
    return null;
  }
  if (result.error == 'auth_cancelled') return null;
  if (result.needsShopName) {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _SocialShopNameDialog(),
    );
    if (!context.mounted) {
      await abandon();
      return null;
    }
    if (name == null) {
      await abandon();
      return null;
    }
    result = await completeSignup(name);
    if (!context.mounted) {
      await abandonUnfinished(result);
      return null;
    }
  }
  if (result.needsWipeConfirmation) {
    final l = AppLocalizations.of(context);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.accountSignInWipeConfirmTitle),
        content: SingleChildScrollView(
          child: Text(l.accountSignInWipeConfirmBody),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.accountSignIn),
          ),
        ],
      ),
    );
    if (!context.mounted) {
      await abandon();
      return null;
    }
    if (accepted != true) {
      await abandon();
      return null;
    }
    result = await confirmSwitch();
  }
  await abandonUnfinished(result);
  return context.mounted && result.error != 'auth_cancelled' ? result : null;
}

Future<SocialAuthProvider?> chooseSocialReauthentication(
  BuildContext context,
  Set<SocialAuthProvider> providers,
) async {
  if (providers.isEmpty) return null;
  final l = AppLocalizations.of(context);
  return showDialog<SocialAuthProvider>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.accountSocialReauthenticateTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.accountSocialReauthenticateBody),
            const SizedBox(height: AppTheme.space3),
            SocialAuthButtons(
              providers: providers,
              busy: false,
              showSeparator: false,
              onSelected: (provider) => Navigator.pop(ctx, provider),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l.commonCancel),
        ),
      ],
    ),
  );
}

class _SocialShopNameDialog extends StatefulWidget {
  const _SocialShopNameDialog();

  @override
  State<_SocialShopNameDialog> createState() => _SocialShopNameDialogState();
}

class _SocialShopNameDialogState extends State<_SocialShopNameDialog> {
  final _name = TextEditingController();
  bool _required = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _required = true);
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.accountSocialShopTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.accountSocialShopBody),
            const SizedBox(height: AppTheme.space3),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: l.shopName,
                errorText: _required ? l.validationRequired : null,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l.accountSocialCreateShop),
        ),
      ],
    );
  }
}
