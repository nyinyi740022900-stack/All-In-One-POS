import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../data/sync/sync_providers.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
import '../license/license_status.dart';
import 'account_providers.dart';

/// Real email/password login for the shop, additive to the existing
/// device-key activation (which stays exactly as-is). Lets the owner create
/// a login, sign in with it on another device, and sign out.
class ShopLoginScreen extends ConsumerStatefulWidget {
  const ShopLoginScreen({super.key});

  @override
  ConsumerState<ShopLoginScreen> createState() => _ShopLoginScreenState();
}

class _ShopLoginScreenState extends ConsumerState<ShopLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _errorMessage(AppLocalizations l, String? code) => switch (code) {
        'email_taken' => l.accountEmailTaken,
        'not_activated' => l.accountNotActivated,
        'no_backend' => l.accountNoBackend,
        'pending_sync' => l.accountPendingSync,
        _ => l.accountActionFailed,
      };

  Future<void> _createLogin() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (_email.text.trim().isEmpty || _password.text.isEmpty) return;
    setState(() => _busy = true);
    final result = await ref
        .read(accountRepositoryProvider)
        .createShopLogin(_email.text.trim(), _password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      if (result.license != null) {
        ref.read(licenseControllerProvider.notifier).applyExternal(result.license!);
      }
      messenger.showSnackBar(SnackBar(content: Text(l.accountLoginCreated)));
      _password.clear();
    } else {
      messenger.showSnackBar(
          SnackBar(content: Text(_errorMessage(l, result.error))));
    }
  }

  Future<void> _signIn() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (_email.text.trim().isEmpty || _password.text.isEmpty) return;
    setState(() => _busy = true);
    var result = await ref
        .read(accountRepositoryProvider)
        .signInAndClaimDevice(_email.text.trim(), _password.text);
    if (!mounted) return;

    if (result.needsWipeConfirmation) {
      setState(() => _busy = false);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.accountSignInWipeConfirmTitle),
          content: Text(l.accountSignInWipeConfirmBody),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.commonCancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l.accountSignIn)),
          ],
        ),
      );
      if (!mounted) return;
      if (confirmed != true) {
        // Already signed in to the OTHER shop's auth session at this point —
        // back out cleanly rather than leave local data mismatched with it.
        // Deliberately the raw Supabase sign-out, NOT
        // AccountRepository.signOut() — that method's Premium-downgrade
        // logic reads THIS device's still-original (never applied) cached
        // license, so routing through it here would incorrectly downgrade
        // the original shop the owner never asked to sign out of.
        await Supabase.instance.client.auth.signOut();
        return;
      }
      setState(() => _busy = true);
      result =
          await ref.read(accountRepositoryProvider).confirmWipeAndClaimDevice();
      if (!mounted) return;
    }

    setState(() => _busy = false);
    if (result.ok) {
      if (result.license != null) {
        ref.read(licenseControllerProvider.notifier).applyExternal(result.license!);
        ref.read(syncControllerProvider.notifier).sync();
      }
      ref.invalidate(backendAccountRoleProvider);
      messenger.showSnackBar(SnackBar(content: Text(l.accountSignedIn)));
      _password.clear();
      setState(() {});
    } else {
      messenger.showSnackBar(
          SnackBar(content: Text(_errorMessage(l, result.error))));
    }
  }

  Future<void> _signOut() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // This device loses Premium on sign-out only when its Premium came from
    // being an authenticated Online-tier user in the first place — a
    // key-activated (Offline-tier) device's Premium is independent of any
    // auth session, so its sign-out keeps the generic wording.
    final license = ref.read(licenseControllerProvider).license;
    final losesPremium = license != null &&
        license.tier == 'online' &&
        license.plan != LicensePlan.free;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.accountSignOutConfirmTitle),
        content: Text(losesPremium
            ? l.accountSignOutPremiumConfirmBody
            : l.accountSignOutConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.accountSignOut)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await ref.read(accountRepositoryProvider).signOut();
    if (!mounted) return;
    if (result.license != null) {
      ref.read(licenseControllerProvider.notifier).applyExternal(result.license!);
    }
    ref.invalidate(backendAccountRoleProvider);
    messenger.showSnackBar(SnackBar(content: Text(l.accountSignedOut)));
    setState(() {});
  }

  Future<void> _showForgotPasswordDialog() async {
    final l = AppLocalizations.of(context);
    final email = TextEditingController(text: _email.text.trim());
    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.accountResetPasswordTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.accountResetPasswordHint,
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: AppTheme.space3),
            TextField(
              controller: email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: l.accountEmail),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
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
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.accountResetPasswordSent)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final account = ref.read(accountRepositoryProvider);
    final signedIn = account.isSignedInWithRealAccount;

    return Scaffold(
      appBar: AppBar(title: Text(l.accountShopLoginTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.space4),
        children: [
          Text(l.accountShopLoginHint,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppTheme.space4),
          if (signedIn)
            Card(
              child: ListTile(
                leading: const Icon(Icons.verified_user, color: Colors.green),
                title: Text(account.currentAccountEmail ?? ''),
                subtitle: Text(account.currentAccountRole ?? ''),
                trailing: TextButton(
                  onPressed: _signOut,
                  child: Text(l.accountSignOut),
                ),
              ),
            )
          else ...[
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: l.accountEmail),
            ),
            const SizedBox(height: AppTheme.space2),
            TextField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: l.accountPassword,
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy ? null : _showForgotPasswordDialog,
                child: Text(l.accountForgotPassword),
              ),
            ),
            const SizedBox(height: AppTheme.space2),
            FilledButton(
              onPressed: _busy ? null : _createLogin,
              child: Text(l.accountCreateShopLogin),
            ),
            const SizedBox(height: AppTheme.space2),
            OutlinedButton(
              onPressed: _busy ? null : _signIn,
              child: Text(l.accountSignIn),
            ),
          ],
        ],
      ),
    );
  }
}
