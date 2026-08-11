import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/layout.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/sync/sync_providers.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
import '../license/license_status.dart';
import '../onboarding/operating_mode_providers.dart';
import 'account_providers.dart';
import 'auth_password_field.dart';
import 'forgot_password_dialog.dart';
import 'password_strength.dart';

/// Real email/password login for the shop, additive to the existing
/// device-key activation (which stays exactly as-is). Lets the owner create
/// a login, sign in with it on another device, and sign out.
class ShopLoginScreen extends ConsumerStatefulWidget {
  const ShopLoginScreen({super.key});

  @override
  ConsumerState<ShopLoginScreen> createState() => _ShopLoginScreenState();
}

class _ShopLoginScreenState extends ConsumerState<ShopLoginScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this)
    ..addListener(_onTabChanged);
  final _createEmail = TextEditingController();
  final _createPassword = TextEditingController();
  final _signInEmail = TextEditingController();
  final _signInPassword = TextEditingController();
  bool _busy = false;

  // No TabBarView here (a fixed-height one clipped Myanmar labels that wrap
  // to two lines) — the tab body is switched manually, sized to content via
  // AnimatedSize, so this just triggers a rebuild on tab tap.
  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _createEmail.dispose();
    _createPassword.dispose();
    _signInEmail.dispose();
    _signInPassword.dispose();
    super.dispose();
  }

  String _errorMessage(AppLocalizations l, String? code) => switch (code) {
    'email_taken' => l.accountEmailTaken,
    'not_activated' => l.accountNotActivated,
    'no_backend' => l.accountNoBackend,
    'pending_sync' => l.accountPendingSync,
    'stuck_outbox' => l.branchesSwitchBlockedStuckOutbox,
    'wrong_password' => l.accountDeleteWrongPassword,
    'forbidden' => l.accountDeleteOwnerOnly,
    _ => l.accountActionFailed,
  };

  Future<void> _createLogin() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (_createEmail.text.trim().isEmpty || _createPassword.text.isEmpty) {
      return;
    }
    setState(() => _busy = true);
    final result = await ref
        .read(accountRepositoryProvider)
        .createShopLogin(_createEmail.text.trim(), _createPassword.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      if (result.license != null) {
        ref
            .read(licenseControllerProvider.notifier)
            .applyExternal(result.license!);
      }
      messenger.showSnackBar(SnackBar(content: Text(l.accountLoginCreated)));
      _createPassword.clear();
      setState(() {});
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(_errorMessage(l, result.error))),
      );
    }
  }

  Future<void> _signIn() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (_signInEmail.text.trim().isEmpty || _signInPassword.text.isEmpty) {
      return;
    }
    setState(() => _busy = true);
    var result = await ref
        .read(accountRepositoryProvider)
        .signInAndClaimDevice(_signInEmail.text.trim(), _signInPassword.text);
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
              child: Text(l.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.accountSignIn),
            ),
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
      result = await ref
          .read(accountRepositoryProvider)
          .confirmWipeAndClaimDevice();
      if (!mounted) return;
    }

    setState(() => _busy = false);
    if (result.ok) {
      if (result.license != null) {
        ref
            .read(licenseControllerProvider.notifier)
            .applyExternal(result.license!);
        ref.read(syncControllerProvider.notifier).sync();
      }
      ref.invalidate(backendAccountRoleProvider);
      messenger.showSnackBar(SnackBar(content: Text(l.accountSignedIn)));
      _signInPassword.clear();
      setState(() {});
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(_errorMessage(l, result.error))),
      );
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
    final losesPremium =
        license != null &&
        license.tier == 'online' &&
        license.plan != LicensePlan.free;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.accountSignOutConfirmTitle),
        content: Text(
          losesPremium
              ? l.accountSignOutPremiumConfirmBody
              : l.accountSignOutConfirmBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.accountSignOut),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await ref.read(accountRepositoryProvider).signOut();
    if (!mounted) return;
    if (result.license != null) {
      ref
          .read(licenseControllerProvider.notifier)
          .applyExternal(result.license!);
    }
    ref.invalidate(backendAccountRoleProvider);
    ref.invalidate(onlineDailyGateNeededProvider);
    messenger.showSnackBar(SnackBar(content: Text(l.accountSignedOut)));
    setState(() {});
  }

  Future<void> _deleteAccount() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final account = ref.read(accountRepositoryProvider);
    if (account.currentAccountRole != 'owner') {
      messenger.showSnackBar(
        SnackBar(content: Text(l.accountDeleteOwnerOnly)),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.accountDeleteConfirmTitle),
        content: Text(l.accountDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.accountDeleteAccount),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.accountDeleteAccount),
        content: AuthPasswordField(
          controller: password,
          labelText: l.accountDeletePasswordLabel,
          autofillHints: const [AutofillHints.password],
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.accountDeleteAccount),
          ),
        ],
      ),
    );
    final pwd = password.text;
    password.dispose();
    if (ok != true || pwd.isEmpty || !mounted) return;

    setState(() => _busy = true);
    final result = await ref
        .read(accountRepositoryProvider)
        .deleteAccount(pwd);
    if (!mounted) return;

    if (!result.ok) {
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text(_errorMessage(l, result.error))),
      );
      return;
    }

    // Cloud account gone — local Free plan + wipe so this device is clean.
    final entered = await ref
        .read(licenseControllerProvider.notifier)
        .continueFree();
    if (!entered) {
      // Pending outbox blocked Free entry — still clear license cache best-effort.
      await ref.read(licenseControllerProvider.notifier).deactivate();
    }
    ref.invalidate(backendAccountRoleProvider);
    ref.invalidate(onlineDailyGateNeededProvider);
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(content: Text(l.accountDeleteSuccess)));
    setState(() {});
  }

  Widget _registerForm(AppLocalizations l) {
    return Column(
      key: const ValueKey('register'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _createEmail,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: l.accountEmail),
        ),
        const SizedBox(height: AppTheme.space3),
        AuthPasswordField(
          controller: _createPassword,
          labelText: l.accountPassword,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _createLogin(),
        ),
        PasswordStrengthMeter(controller: _createPassword),
        const SizedBox(height: AppTheme.space3),
        FilledButton(
          onPressed: _busy ? null : _createLogin,
          child: Text(l.accountCreateShopLogin),
        ),
      ],
    );
  }

  Widget _signInForm(AppLocalizations l) {
    return Column(
      key: const ValueKey('signIn'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _signInEmail,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: l.accountEmail),
        ),
        const SizedBox(height: AppTheme.space3),
        AuthPasswordField(
          controller: _signInPassword,
          labelText: l.accountPassword,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _signIn(),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _busy
                ? null
                : () => showForgotPasswordDialog(
                    context,
                    prefillEmail: _signInEmail.text.trim(),
                  ),
            child: Text(l.accountForgotPassword),
          ),
        ),
        const SizedBox(height: AppTheme.space2),
        FilledButton(
          onPressed: _busy ? null : _signIn,
          child: Text(l.accountSignIn),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final account = ref.read(accountRepositoryProvider);
    final signedIn = account.isSignedInWithRealAccount;

    return Scaffold(
      appBar: AppBar(title: Text(l.accountShopLoginTitle)),
      body: ContentWidth(
        maxWidth: 480,
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.space4),
          children: [
            if (!signedIn) ...[
              const Center(child: BrandHero(size: 56)),
              const SizedBox(height: AppTheme.space4),
            ],
            Text(
              l.accountShopLoginHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppTheme.space4),
            if (signedIn)
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.verified_user,
                        color: AppColors.of(context).success,
                      ),
                      title: Text(account.currentAccountEmail ?? ''),
                      subtitle: Text(account.currentAccountRole ?? ''),
                      trailing: TextButton(
                        onPressed: _busy ? null : _signOut,
                        child: Text(l.accountSignOut),
                      ),
                    ),
                    if (account.currentAccountRole == 'owner')
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppTheme.space4,
                          0,
                          AppTheme.space4,
                          AppTheme.space3,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _deleteAccount,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.error,
                              side: BorderSide(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            icon: const Icon(Icons.delete_forever_outlined),
                            label: Text(l.accountDeleteAccount),
                          ),
                        ),
                      ),
                  ],
                ),
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.space4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TabBar(
                        controller: _tabs,
                        tabs: [
                          Tab(text: l.onboardOnlineTabRegister),
                          Tab(text: l.onboardOnlineTabSignIn),
                        ],
                      ),
                      const SizedBox(height: AppTheme.space4),
                      // No `TabBarView` — a fixed-height one clipped
                      // Myanmar labels that wrap to two lines. AnimatedSize
                      // lets each tab's body claim exactly the height it
                      // needs in either language.
                      AnimatedSize(
                        duration: AppTheme.motionMedium,
                        curve: AppTheme.curveStandard,
                        alignment: Alignment.topCenter,
                        child: _tabs.index == 0
                            ? _registerForm(l)
                            : _signInForm(l),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
