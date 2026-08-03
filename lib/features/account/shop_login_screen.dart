import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/sync/sync_providers.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
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
    final result = await ref
        .read(accountRepositoryProvider)
        .signInAndClaimDevice(_email.text.trim(), _password.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      if (result.license != null) {
        ref.read(licenseControllerProvider.notifier).applyExternal(result.license!);
        ref.read(syncControllerProvider.notifier).sync();
      }
      messenger.showSnackBar(SnackBar(content: Text(l.accountSignedIn)));
      _password.clear();
    } else {
      messenger.showSnackBar(
          SnackBar(content: Text(_errorMessage(l, result.error))));
    }
  }

  Future<void> _signOut() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(accountRepositoryProvider).signOut();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l.accountSignedOut)));
    setState(() {});
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
              obscureText: true,
              decoration: InputDecoration(labelText: l.accountPassword),
            ),
            const SizedBox(height: AppTheme.space4),
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
