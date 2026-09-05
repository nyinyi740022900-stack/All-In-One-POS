import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/layout.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/sync/sync_providers.dart';
import '../../l10n/app_localizations.dart';
import '../account/account_providers.dart';
import '../account/account_action_error.dart';
import '../account/auth_password_field.dart';
import '../account/forgot_password_dialog.dart';
import '../account/password_strength.dart';
import '../account/saved_login_store.dart';
import '../license/license_model.dart';
import '../license/license_providers.dart';
import '../printing/printing_providers.dart';
import 'onboarding_state.dart';

/// First-run, one-time flow: Welcome → Shop profile → Free plan (explained,
/// started automatically) → optional account sign-in → Staff mode intro.
/// Gated by `onboardingCompleteProvider` and hosted at the router route
/// `/onboarding` — a real route, not a MaterialApp.builder overlay, so
/// leaving it is an ordinary `context.go('/sell')` (the builder-overlay
/// variant's gate swap silently never painted on one owner device).
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({
    super.key,
    this.onDone,
    this.routed = false,
  });

  /// Optional extra hook (used by tests). The routed flow advances itself.
  final VoidCallback? onDone;

  /// True when hosted at `/onboarding`: finishing navigates via the router.
  final bool routed;

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  final _controller = PageController();
  int _page = 0;

  List<Widget> get _pages => [
    _WelcomePage(),
    _ShopProfilePage(),
    const _LicensePage(),
    _AccountPage(onDone: () => _next(_pages.length)),
    _StaffModePage(),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _busyNav = false;
  // Set the instant Get started is tapped. The flow swaps ITSELF to a
  // waiting screen through the exact same local-setState machinery the
  // working Next button uses — on the owner's device the tap provably ran
  // (the background persist landed) yet the app-level gate swap never
  // painted, so the last page just sat there looking dead. Visible progress
  // first; the app-level close follows.
  bool _completing = false;

  /// Get started — never wait on [_busyNav] or a Drift write. Those used to
  /// swallow the tap (button looked enabled, nothing happened).
  void _finishOnboarding() {
    if (_completing) return;
    // Release-visible breadcrumb: the owner's device ran the persist (a
    // restart landed on the daily gate) while the gate stayed painted —
    // this proves whether the tap reaches the handler at all.
    debugPrint('[onboarding] Get started tapped');
    setState(() => _completing = true);
    unawaited(_persistOnboardingComplete());
    widget.onDone?.call();
    if (!widget.routed) return;
    // The routed flow leaves via ordinary navigation — the same mechanism
    // as every tab/tab switch that provably works on every device.
    ref.read(onboardingForcedDoneProvider.notifier).state = true;
    ref.invalidate(onboardingCompleteProvider);
    context.go('/sell');
  }

  Future<void> _next(int pageCount) async {
    if (_page == pageCount - 1) {
      _finishOnboarding();
      return;
    }
    if (_busyNav) return;
    // Plan page: everyone starts Free. Key activation stays in Settings.
    if (_page == 2 &&
        ref.read(licenseControllerProvider).license == null) {
      setState(() => _busyNav = true);
      final ok = await ref
          .read(licenseControllerProvider.notifier)
          .continueFree();
      if (!mounted) return;
      setState(() => _busyNav = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).commonUnexpectedError)),
        );
        return;
      }
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

  Future<void> _persistOnboardingComplete() async {
    try {
      await ref
          .read(settingsRepositoryProvider)
          .markOnboardingComplete()
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Get started tapped: the very next paint is this waiting screen —
    // driven by the same local setState that makes Next work everywhere,
    // never by the app-level gate swap that silently failed on one device.
    if (_completing) {
      return Scaffold(body: AppLoadingView(message: l.commonPleaseWait));
    }
    final pages = _pages;
    // Email page: Sign in / Create account advance on success. Footer Next
    // used to skip past a failed login — keep Skip on the page instead.
    const accountPageIndex = 3;
    final busy = _busyNav && _page != pages.length - 1;
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
                  // The account page owns its navigation (Sign in / Skip for
                  // now on the page itself). Its footer button used to render
                  // permanently *disabled* — a greyed "Next" at the bottom of
                  // every other page's rhythm reads as broken, and owners
                  // reported tapping it and nothing happening. Absent beats
                  // dead.
                  if (_page != accountPageIndex)
                    // minimumSize is a real finite size on purpose: the
                    // theme default's width-infinity demand overflows this
                    // Row once page dots + Back share it (see git history).
                    FilledButton(
                      style: AppTheme.authFilledButtonStyle(
                        minimumSize: const Size(88, 52),
                      ),
                      onPressed: busy
                          ? null
                          : _page == pages.length - 1
                              ? _finishOnboarding
                              : () => _next(pages.length),
                      child: busy
                          ? const ButtonSpinner()
                          : Text(
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

/// The very first screen a new owner sees — brand-green wave header rather
/// than a generic Material icon.
///
/// It deliberately carries NO language toggle. A "Myanmar | English" control
/// as the first thing on the first screen reads to an overseas visitor as
/// "this is a Myanmar-only product", which costs more trust than the toggle
/// buys convenience — the same reasoning removed "Myanmar shops" from the
/// body copy. Language is device-global and lives in one place instead:
/// Settings → Shop profile's app-bar switcher.
class _WelcomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _OnboardPage(
      icon: Icons.storefront_rounded,
      preferShopLogo: true,
      title: l.onboardWelcomeTitle,
      body: l.onboardWelcomeBody,
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
  // Keyed by shopId (not a one-shot bool): a `PageView(children: ...)` keeps
  // every page's State alive off-screen, so this page's first build often
  // runs before the Account page (later in the flow) signs the device into
  // its real cloud shop. Re-hydrating whenever shopId changes means that if
  // the owner signs into an already-provisioned shop during this same
  // onboarding session, the fields pick up that shop's real profile (once
  // the sync-triggered hydration in `SyncController` lands it) instead of
  // staying stuck on the pre-sign-in placeholder.
  String? _hydratedForShopId;
  Timer? _saveDebounce;

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _footer.dispose();
    super.dispose();
  }

  // Debounced so rapid typing doesn't fire an unordered async DB write per
  // keystroke — each new keystroke cancels the pending save and reschedules,
  // so only the latest field state is ever written.
  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _save);
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
    if (!mounted) return;
    ref.invalidate(shopProfileProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final shopId = ref.watch(shopIdProvider);
    final async = ref.watch(shopProfileProvider);
    if (_hydratedForShopId != shopId && async.hasValue) {
      _name.text = async.value!.name;
      _phone.text = async.value!.phone ?? '';
      _address.text = async.value!.address ?? '';
      _footer.text = async.value!.footer ?? '';
      _hydratedForShopId = shopId;
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
            onChanged: (_) => _scheduleSave(),
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
            onChanged: (_) => _scheduleSave(),
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
            onChanged: (_) => _scheduleSave(),
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
            onChanged: (_) => _scheduleSave(),
          ),
        ],
      ),
    );
  }
}

class _LicensePage extends StatelessWidget {
  const _LicensePage();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _OnboardPage(
      icon: Icons.verified_outlined,
      title: l.onboardLicenseTitle,
      body: l.onboardLicenseBody,
    );
  }
}

/// Optional — email for a new shop (Create account) or an existing one
/// (Sign in). Skippable; revisitable later via Settings → Account.
class _AccountPage extends ConsumerStatefulWidget {
  const _AccountPage({required this.onDone});
  final VoidCallback onDone;

  @override
  ConsumerState<_AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<_AccountPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _shopName = TextEditingController();
  late final SavedLoginBinder _savedLogin;
  bool _busy = false;
  bool _done = false;
  // Defaults to Create account: this page is reached during first-run
  // onboarding, where the overwhelming majority of visitors have never had
  // an account — Sign in as the default asked a brand-new user to find the
  // one tab meant for someone else first.
  bool _register = true;
  bool _showBenefits = false;
  // Set on a blocked submit attempt so the offending field(s) show an
  // inline errorText instead of (or alongside) the generic banner — cleared
  // whenever the tab is switched so a stale field error doesn't linger.
  bool _attemptedSubmit = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _savedLogin = SavedLoginBinder(email: _email, password: _password)
      ..attach();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _savedLogin.load(ref.read(savedLoginStoreProvider));
      if (!mounted) return;
      final name = ref.read(shopProfileProvider).asData?.value.name.trim();
      if (name != null && name.isNotEmpty && _shopName.text.isEmpty) {
        _shopName.text = name;
      }
    });
  }

  @override
  void dispose() {
    _savedLogin.detach();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _shopName.dispose();
    super.dispose();
  }

  String _errorMessage(AppLocalizations l, String? code) =>
      accountActionErrorMessage(l, code);

  // The field-level errorText below is computed straight from controller
  // text each build, but a controller changing doesn't itself trigger a
  // rebuild — this forces one so a field's error clears the moment the user
  // fixes it, without repainting on every keystroke before there's an error
  // to clear.
  void _onFieldChanged() {
    if (_attemptedSubmit) setState(() {});
  }

  bool get _attachToThisShop =>
      !isReplaceableLocalLicense(ref.read(licenseControllerProvider).license);

  Future<void> _submit() async {
    // `onPressed: _busy ? null : _submit` can't block a second tap landing
    // in the frame before the first tap's setState(_busy=true) repaints the
    // disabled button — guard here too so a fast double-tap can't fire two
    // concurrent sign-in/create-account attempts.
    if (_busy) return;
    if (_register) {
      await _createAccount();
    } else {
      await _signIn();
    }
  }

  Future<void> _createAccount() async {
    final l = AppLocalizations.of(context);
    if (_email.text.trim().isEmpty ||
        _password.text.isEmpty ||
        (!_attachToThisShop && _shopName.text.trim().isEmpty)) {
      // Silent returns here used to read as a dead button — the offending
      // field(s) now show their own errorText below instead of one generic
      // banner naming nothing specific.
      setState(() {
        _attemptedSubmit = true;
        _error = null;
      });
      return;
    }
    if (_password.text != _confirmPassword.text) {
      setState(() {
        _attemptedSubmit = true;
        _error = null;
      });
      return;
    }
    final attach = _attachToThisShop;
    setState(() {
      _busy = true;
      _error = null;
    });
    if (attach) {
      final created = await ref
          .read(accountRepositoryProvider)
          .createShopLogin(_email.text.trim(), _password.text);
      if (!mounted) return;
      if (!created.ok) {
        if (created.error == 'email_taken') {
          // The login this call wanted may already exist because an earlier
          // attempt in this same flow created it and only the immediately-
          // chained sign-in below failed (a transient error, say) — retry via
          // sign-in with the same credentials instead of dead-ending on
          // "already registered": it succeeds silently if this was really
          // our own earlier attempt, and reports the accurate wrong-password
          // error if it wasn't.
          await _signIn();
          return;
        }
        setState(() {
          _busy = false;
          _error = _errorMessage(l, created.error);
        });
        return;
      }
      if (created.license != null) {
        await ref
            .read(licenseControllerProvider.notifier)
            .applyExternal(created.license!);
      }
      if (!mounted) return;
      await _signIn();
      return;
    }
    final result = await ref
        .read(accountRepositoryProvider)
        .signupShop(
          _shopName.text.trim(),
          _email.text.trim(),
          _password.text,
        );
    if (!mounted) return;
    if (result.ok && result.license != null) {
      await _finishWithLicense(result.license!);
    } else {
      setState(() {
        _busy = false;
        _error = _errorMessage(l, result.error);
      });
    }
  }

  Future<void> _signIn() async {
    final l = AppLocalizations.of(context);
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      // Same as _createAccount: the offending field(s) show their own
      // errorText below instead of one generic banner.
      setState(() {
        _attemptedSubmit = true;
        _error = null;
      });
      return;
    }
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
      await _finishWithLicense(result.license!);
    } else {
      setState(() {
        _busy = false;
        _error = _errorMessage(l, result.error);
      });
    }
  }

  Future<void> _finishWithLicense(CachedLicense license) async {
    await _savedLogin.remember(
      ref.read(savedLoginStoreProvider),
      email: _email.text.trim(),
      password: _password.text,
    );
    if (!mounted) return;
    await ref.read(licenseControllerProvider.notifier).applyExternal(license);
    ref.invalidate(hasRealAccountSessionProvider);
    // Awaited (not fire-and-forget): this shop's real `shop_profiles` row
    // pulls down as part of this sync, and `SyncController` hydrates it into
    // the AppSettings KV the Shop Profile page/screen read right after —
    // waiting here means that hydration has already landed by the time the
    // rest of onboarding (and Settings → Shop, immediately afterward) reads
    // it, instead of racing a background sync that might still be running.
    await ref.read(syncControllerProvider.notifier).sync();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _done = true;
    });
    widget.onDone();
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _showBenefits = !_showBenefits),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppTheme.space1,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l.onboardAccountWhyEmail,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Icon(
                      _showBenefits
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
            if (_showBenefits) ...[
              const SizedBox(height: AppTheme.space1),
              Text(
                l.onboardAccountBenefits,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: AppTheme.space4),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(l.onboardOnlineTabSignIn),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(l.onboardOnlineTabRegister),
                ),
              ],
              selected: {_register},
              onSelectionChanged: _busy
                  ? null
                  : (s) => setState(() {
                      _register = s.first;
                      _error = null;
                      _attemptedSubmit = false;
                    }),
            ),
            const SizedBox(height: AppTheme.space4),
            if (_register && !_attachToThisShop) ...[
              TextField(
                controller: _shopName,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.organizationName],
                textInputAction: TextInputAction.next,
                onChanged: (_) => _onFieldChanged(),
                decoration: InputDecoration(
                  labelText: l.shopName,
                  prefixIcon: const AuthFieldIcon(Icons.store_outlined),
                  errorText: _attemptedSubmit && _shopName.text.trim().isEmpty
                      ? l.validationRequired
                      : null,
                ),
              ),
              const SizedBox(height: AppTheme.space3),
            ],
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              textInputAction: TextInputAction.next,
              onChanged: (_) => _onFieldChanged(),
              decoration: InputDecoration(
                labelText: l.accountEmail,
                prefixIcon: const AuthFieldIcon(Icons.mail_outline),
                errorText: _attemptedSubmit && _email.text.trim().isEmpty
                    ? l.validationRequired
                    : null,
              ),
            ),
            const SizedBox(height: AppTheme.space3),
            AuthPasswordField(
              controller: _password,
              labelText: l.accountPassword,
              autofillHints: _register
                  ? const [AutofillHints.newPassword]
                  : const [AutofillHints.password],
              helperText: _register ? null : l.accountPasswordRememberedHint,
              errorText: _attemptedSubmit && _password.text.isEmpty
                  ? l.validationRequired
                  : null,
              textInputAction: _register
                  ? TextInputAction.next
                  : TextInputAction.done,
              onSubmitted: (_) {
                if (!_busy && !_register) _signIn();
              },
              onChanged: (_) => _onFieldChanged(),
            ),
            if (_register) ...[
              PasswordStrengthMeter(controller: _password),
              const SizedBox(height: AppTheme.space3),
              AuthPasswordField(
                controller: _confirmPassword,
                labelText: l.accountConfirmPassword,
                autofillHints: const [AutofillHints.newPassword],
                errorText:
                    _attemptedSubmit && _password.text != _confirmPassword.text
                        ? l.accountPasswordMismatch
                        : null,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!_busy) _createAccount();
                },
                onChanged: (_) => _onFieldChanged(),
              ),
            ],
            if (!_register)
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
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const ButtonSpinner()
                  : Text(
                      _register
                          ? l.onboardOnlineCreateAccount
                          : l.accountSignIn,
                    ),
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
