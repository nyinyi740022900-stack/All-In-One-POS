import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/layout.dart';
import '../../core/locale_controller.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/repositories/settings_repository.dart';
import '../account/auth_password_field.dart';
import '../account/forgot_password_dialog.dart';
import '../../l10n/app_localizations.dart';
import '../account/account_providers.dart';
import '../license/license_providers.dart';
import '../license/license_screen.dart';
import '../printing/printing_providers.dart';

/// First-run, one-time flow: Welcome → Shop profile → License (key / free) →
/// optional account sign-in (skippable — no more permanent mode choice) →
/// Staff mode intro. Gated by `SettingsRepository.onboardingComplete`.
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  final _controller = PageController();
  int _page = 0;

  List<Widget> get _pages => [
        _WelcomePage(),
        _ShopProfilePage(),
        _LicensePage(onContinue: () => _next(_pages.length)),
        _AccountPage(onDone: () => _next(_pages.length)),
        _StaffModePage(),
      ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next(int pageCount) {
    if (_page == pageCount - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _finish() async {
    await ref.read(settingsRepositoryProvider).markOnboardingComplete();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final pages = _pages;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: pages,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTheme.space5),
              child: Row(
                children: [
                  for (var i = 0; i < pages.length; i++)
                    AnimatedContainer(
                      duration: AppTheme.motionFast,
                      margin: const EdgeInsets.only(right: AppTheme.space2),
                      width: i == _page ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusFull),
                        color: i == _page
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  const Spacer(),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: FilledButton(
                      onPressed: () => _next(pages.length),
                      child: Text(_page == pages.length - 1
                          ? l.onboardGetStarted
                          : l.onboardNext),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared page chrome: icon, title, body text, centered.
class _OnboardPage extends StatelessWidget {
  const _OnboardPage({
    required this.icon,
    required this.title,
    required this.body,
    this.extra,
  });
  final IconData icon;
  final String title;
  final String body;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return ContentWidth(
      maxWidth: 480,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.space5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: AppTheme.space5),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppTheme.space3),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (extra != null) ...[const SizedBox(height: AppTheme.space5), extra!],
          ],
        ),
      ),
    );
  }
}

/// The very first screen a new owner sees, so it gets the [BrandHero] lockup
/// rather than delegating to [_OnboardPage]'s generic Material icon.
class _WelcomePage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final locale = ref.watch(localeControllerProvider);
    return ContentWidth(
      maxWidth: 480,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.space5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const BrandHero(showName: false),
            const SizedBox(height: AppTheme.space5),
            Text(
              l.onboardWelcomeTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppTheme.space3),
            Text(
              l.onboardWelcomeBody,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppTheme.space5),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'my', label: Text(l.languageMyanmar)),
                ButtonSegment(value: 'en', label: Text(l.languageEnglish)),
              ],
              selected: {locale},
              onSelectionChanged: (s) =>
                  ref.read(localeControllerProvider.notifier).set(s.first),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopProfilePage extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ShopProfilePage> createState() => _ShopProfilePageState();
}

class _ShopProfilePageState extends ConsumerState<_ShopProfilePage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _hydrated = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    final repo = ref.read(settingsRepositoryProvider);
    final shopId = ref.read(shopIdProvider);
    final existing = await repo.shopProfile(shopId);
    await repo.saveShopProfile(
      shopId,
      ShopProfile(
        name: _name.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        address: existing.address,
        footer: existing.footer,
      ),
    );
    ref.invalidate(shopProfileProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(shopProfileProvider);
    if (!_hydrated && async.hasValue) {
      _name.text = async.value!.name;
      _phone.text = async.value!.phone ?? '';
      _hydrated = true;
    }
    return _OnboardPage(
      icon: Icons.store_outlined,
      title: l.onboardShopTitle,
      body: l.onboardShopBody,
      extra: Column(
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.organizationName],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: l.shopName),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: l.shopPhone),
            onChanged: (_) => _save(),
          ),
        ],
      ),
    );
  }
}

class _LicensePage extends ConsumerWidget {
  const _LicensePage({required this.onContinue});

  /// Advances onboarding to the next page. Called automatically once a
  /// choice here actually resolves — either "Continue Free" succeeds, or
  /// [LicenseScreen] is popped after a successful activation — so the owner
  /// never has to separately hunt for the bottom "Next" button too. Before
  /// this, "Continue Free" only showed a toast and left the owner sitting on
  /// this same page with no visible feedback that anything happened at
  /// all — indistinguishable from the tap simply not registering.
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return _OnboardPage(
      icon: Icons.verified_outlined,
      title: l.onboardLicenseTitle,
      body: l.onboardLicenseBody,
      extra: Column(
        children: [
          OutlinedButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const LicenseScreen(),
              ));
              if (context.mounted && ref.read(isPremiumProvider)) {
                onContinue();
              }
            },
            icon: const Icon(Icons.key_outlined),
            label: Text(l.onboardActivateNow),
          ),
          const SizedBox(height: AppTheme.space2),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final ok =
                  await ref.read(licenseControllerProvider.notifier).continueFree();
              if (!context.mounted) return;
              if (ok) {
                onContinue();
              } else {
                messenger.showSnackBar(
                    SnackBar(content: Text(l.commonUnexpectedError)));
              }
            },
            child: Text(l.onboardingContinueFree),
          ),
        ],
      ),
    );
  }
}

/// Optional — sign in to an existing shop account for cloud sync, backup,
/// and multi-device login, whatever plan was just chosen on the License
/// page. Skippable; revisitable later via Settings > Shop Login, which is
/// also where "create a new shop account" lives (deliberately not offered
/// here too — signing up for a brand-new shop mid-onboarding, right after
/// activating a key or continuing Free on the previous page, would silently
/// strand whatever was just chosen behind two competing shop identities).
class _AccountPage extends ConsumerStatefulWidget {
  const _AccountPage({required this.onDone});
  final VoidCallback onDone;

  @override
  ConsumerState<_AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<_AccountPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _errorMessage(AppLocalizations l, String? code) => switch (code) {
        'email_taken' => l.accountEmailTaken,
        'no_backend' => l.accountNoBackend,
        'not_activated' => l.accountNotActivated,
        'pending_sync' => l.accountPendingSync,
        'stuck_outbox' => l.branchesSwitchBlockedStuckOutbox,
        _ => l.accountActionFailed,
      };

  Future<void> _signIn() async {
    final l = AppLocalizations.of(context);
    if (_email.text.trim().isEmpty || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
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
        await Supabase.instance.client.auth.signOut();
        return;
      }
      setState(() => _busy = true);
      result = await ref
          .read(accountRepositoryProvider)
          .confirmWipeAndClaimDevice();
      if (!mounted) return;
    }

    if (result.ok && result.license != null) {
      ref
          .read(licenseControllerProvider.notifier)
          .applyExternal(result.license!);
      setState(() {
        _busy = false;
        _done = true;
      });
    } else {
      setState(() {
        _busy = false;
        _error = _errorMessage(l, result.error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_done) {
      return _OnboardPage(
        icon: Icons.cloud_done_outlined,
        title: l.onboardAccountSignedInTitle,
        body: l.onboardOnlineSignedIn,
      );
    }
    return _OnboardPage(
      icon: Icons.cloud_outlined,
      title: l.onboardAccountTitle,
      body: l.onboardAccountBody,
      extra: Column(
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: l.accountEmail),
          ),
          const SizedBox(height: AppTheme.space3),
          AuthPasswordField(
            controller: _password,
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
                  : () => showForgotPasswordDialog(context,
                      prefillEmail: _email.text.trim()),
              child: Text(l.accountForgotPassword),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppTheme.space2),
            InlineErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppTheme.space3),
          FilledButton(
            onPressed: _busy ? null : _signIn,
            child: Text(l.accountSignIn),
          ),
          const SizedBox(height: AppTheme.space2),
          TextButton(
            onPressed: _busy ? null : widget.onDone,
            child: Text(l.onboardAccountSkip),
          ),
        ],
      ),
    );
  }
}

class _StaffModePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _OnboardPage(
      icon: Icons.badge_outlined,
      title: l.onboardStaffTitle,
      body: l.onboardStaffBody,
    );
  }
}
