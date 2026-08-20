import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/layout.dart';
import '../../core/locale_controller.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/repositories/settings_repository.dart';
import '../../l10n/app_localizations.dart';
import '../account/account_providers.dart';
import '../account/auth_password_field.dart';
import '../account/forgot_password_dialog.dart';
import '../account/saved_login_store.dart';
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

  void _previous() {
    _controller.previousPage(
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
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _controller,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _page = i),
              children: pages,
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space5,
                AppTheme.space3,
                AppTheme.space5,
                AppTheme.space4,
              ),
              child: Row(
                children: [
                  for (var i = 0; i < pages.length; i++)
                    AnimatedContainer(
                      duration: AppTheme.motionFast,
                      margin: const EdgeInsets.only(right: AppTheme.space2),
                      width: i == _page ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusFull,
                        ),
                        color: i == _page
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  const Spacer(),
                  if (_page > 0) ...[
                    TextButton(
                      onPressed: _previous,
                      child: Text(l.onboardBack),
                    ),
                    const SizedBox(width: AppTheme.space2),
                  ],
                  // Explicit finite minimumSize: the theme's FilledButton
                  // default is Size.fromHeight(52), which sets width to
                  // double.infinity (most buttons in this app are meant to
                  // fill their container) — inside this Row, that infinite
                  // demand was being resolved against a maxWidth: 220
                  // ConstrainedBox into a forced 220pt-wide button no matter
                  // how short its text was, overflowing the Row on narrow
                  // phones once page dots + a "Back" button were also
                  // present. A real minimum width lets it size to content.
                  FilledButton(
                    style: AppTheme.authFilledButtonStyle(
                      minimumSize: const Size(88, 52),
                    ),
                    onPressed: () => _next(pages.length),
                    child: Text(
                      _page == pages.length - 1
                          ? l.onboardGetStarted
                          : l.onboardNext,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared page chrome: brand-green wave header, then title / body / extra
/// on the white page below. Extra (forms, CTAs) stretches full width so
/// fields aren't centred as a skinny column.
class _OnboardPage extends ConsumerWidget {
  const _OnboardPage({
    required this.icon,
    required this.title,
    required this.body,
    this.extra,
    this.preferShopLogo = false,
  });
  final IconData icon;
  final String title;
  final String body;
  final Widget? extra;

  /// Welcome / shop-profile pages use the storefront glyph. If the shop
  /// already has a logo (re-run, or set later in Settings), show that
  /// instead — same plate the daily gate uses.
  final bool preferShopLogo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logoUrl = preferShopLogo
        ? ref.watch(shopProfileProvider).asData?.value.logoUrl
        : null;
    return SizedBox.expand(
      child: Column(
        children: [
          BrandHeroPanel(icon: icon, imageUrl: logoUrl),
          Expanded(
            child: SizedBox.expand(
              child: ContentWidth(
                maxWidth: 480,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.space5,
                    AppTheme.space4,
                    AppTheme.space5,
                    AppTheme.space3,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                      if (extra != null) ...[
                        const SizedBox(height: AppTheme.space5),
                        extra!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The very first screen a new owner sees — brand-green wave header plus
/// the language toggle, rather than a generic Material icon.
class _WelcomePage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final locale = ref.watch(localeControllerProvider);
    return _OnboardPage(
      icon: Icons.storefront_rounded,
      preferShopLogo: true,
      title: l.onboardWelcomeTitle,
      body: l.onboardWelcomeBody,
      extra: SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'my', label: Text(l.languageMyanmar)),
          ButtonSegment(value: 'en', label: Text(l.languageEnglish)),
        ],
        selected: {locale},
        onSelectionChanged: (s) =>
            ref.read(localeControllerProvider.notifier).set(s.first),
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
  final _address = TextEditingController();
  final _footer = TextEditingController();
  bool _hydrated = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _footer.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    final repo = ref.read(settingsRepositoryProvider);
    final shopId = ref.read(shopIdProvider);
    await repo.saveShopProfile(
      shopId,
      ShopProfile(
        name: _name.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        footer: _footer.text.trim().isEmpty ? null : _footer.text.trim(),
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
      _address.text = async.value!.address ?? '';
      _footer.text = async.value!.footer ?? '';
      _hydrated = true;
    }
    return _OnboardPage(
      icon: Icons.store_outlined,
      preferShopLogo: true,
      title: l.onboardShopTitle,
      body: l.onboardShopBody,
      extra: Column(
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.organizationName],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l.shopName,
              prefixIcon: const AuthFieldIcon(Icons.store_outlined),
            ),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l.shopPhone,
              prefixIcon: const AuthFieldIcon(Icons.phone_outlined),
            ),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _address,
            textCapitalization: TextCapitalization.sentences,
            autofillHints: const [AutofillHints.fullStreetAddress],
            textInputAction: TextInputAction.next,
            minLines: 1,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: l.shopAddress,
              prefixIcon: const AuthFieldIcon(Icons.location_on_outlined),
            ),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _footer,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            minLines: 1,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: l.receiptFooter,
              prefixIcon: const AuthFieldIcon(Icons.receipt_long_outlined),
            ),
            onChanged: (_) => _save(),
          ),
        ],
      ),
    );
  }
}

class _LicensePage extends ConsumerStatefulWidget {
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
  ConsumerState<_LicensePage> createState() => _LicensePageState();
}

class _LicensePageState extends ConsumerState<_LicensePage> {
  bool _busy = false;

  Future<void> _activate() async {
    setState(() => _busy = true);
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LicenseScreen()));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ref.read(isPremiumProvider)) widget.onContinue();
  }

  Future<void> _continueFree() async {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    final ok = await ref
        .read(licenseControllerProvider.notifier)
        .continueFree();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      widget.onContinue();
    } else {
      messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _OnboardPage(
      icon: Icons.verified_outlined,
      title: l.onboardLicenseTitle,
      body: l.onboardLicenseBody,
      extra: Column(
        children: [
          OutlinedButton.icon(
            style: AppTheme.authOutlinedButtonStyle(),
            onPressed: _busy ? null : _activate,
            icon: const Icon(Icons.key_outlined),
            label: Text(l.onboardActivateNow),
          ),
          const SizedBox(height: AppTheme.space2),
          TextButton(
            onPressed: _busy ? null : _continueFree,
            child: _busy
                ? const ButtonSpinner(size: 16)
                : Text(l.onboardingContinueFree),
          ),
        ],
      ),
    );
  }
}

/// Optional — sign in to an existing shop account for cloud sync, backup,
/// and multi-device login, whatever plan was just chosen on the License
/// page. Skippable; revisitable later via Settings > Account, which is
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
  late final SavedLoginBinder _savedLogin;
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _savedLogin = SavedLoginBinder(email: _email, password: _password)
      ..attach();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _savedLogin.load(ref.read(savedLoginStoreProvider));
    });
  }

  @override
  void dispose() {
    _savedLogin.detach();
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
    'trial_already_used' => l.accountTrialAlreadyUsed,
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
      await _savedLogin.remember(
        ref.read(savedLoginStoreProvider),
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
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
      extra: AutofillGroup(
        child: Column(
          children: [
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l.accountEmail,
                prefixIcon: const AuthFieldIcon(Icons.mail_outline),
              ),
            ),
            const SizedBox(height: AppTheme.space3),
            AuthPasswordField(
              controller: _password,
              labelText: l.accountPassword,
              autofillHints: const [AutofillHints.password],
              helperText: l.accountPasswordRememberedHint,
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
                        prefillEmail: _email.text.trim(),
                      ),
                child: Text(l.accountForgotPassword),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppTheme.space2),
              InlineErrorBanner(message: _error!),
            ],
            const SizedBox(height: AppTheme.space3),
            FilledButton(
              style: AppTheme.authFilledButtonStyle(),
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
