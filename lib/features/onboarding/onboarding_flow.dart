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
import '../account/password_strength.dart';
import '../../l10n/app_localizations.dart';
import '../account/account_providers.dart';
import '../license/license_providers.dart';
import '../license/license_screen.dart';
import '../printing/printing_providers.dart';
import 'operating_mode_providers.dart';

/// First-run, one-time flow: compare Online/Offline → ack → choose (locked),
/// then Offline license/Free path or Online sign-in/register. Gated by
/// `SettingsRepository.onboardingComplete`.
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  final _controller = PageController();
  int _page = 0;
  String? _mode;
  bool _authDone = false;

  static const _onlineAuthPageIndex = 2;

  List<Widget> get _pages {
    if (_mode == SettingsRepository.operatingModeOnline) {
      return [
        _ModeChoicePage(onChoose: _chooseMode),
        _WelcomePage(),
        _OnlineAuthPage(onAuthenticated: () => setState(() => _authDone = true)),
      ];
    }
    if (_mode == SettingsRepository.operatingModeOffline) {
      return [
        _ModeChoicePage(onChoose: _chooseMode),
        _WelcomePage(),
        _ShopProfilePage(),
        _LicensePage(),
        _StaffModePage(),
      ];
    }
    return [_ModeChoicePage(onChoose: _chooseMode)];
  }

  bool get _nextDisabled =>
      _mode == null ||
      (_mode == SettingsRepository.operatingModeOnline &&
          _page == _onlineAuthPageIndex &&
          !_authDone);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _chooseMode(String mode) async {
    await lockOperatingMode(ref, mode);
    if (!mounted) return;
    setState(() => _mode = mode);
    await _controller.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
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
    ref.invalidate(operatingModeProvider);
    ref.invalidate(operatingModeConfirmedProvider);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final pages = _pages;
    final hideNext = _mode == null;
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
            if (!hideNext)
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
                        onPressed:
                            _nextDisabled ? null : () => _next(pages.length),
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

/// Compare Online vs Offline, require ack, then choose (locks permanently).
class _ModeChoicePage extends StatefulWidget {
  const _ModeChoicePage({required this.onChoose});
  final Future<void> Function(String mode) onChoose;

  @override
  State<_ModeChoicePage> createState() => _ModeChoicePageState();
}

class _ModeChoicePageState extends State<_ModeChoicePage> {
  bool _acked = false;
  bool _busy = false;

  Future<void> _pick(String mode) async {
    if (!_acked || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onChoose(mode);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final enabled = _acked && !_busy;
    return ContentWidth(
      maxWidth: 480,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.space5,
          vertical: AppTheme.space4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: BrandHero(size: 64)),
            const SizedBox(height: AppTheme.space5),
            Text(
              l.onboardModeCompareTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppTheme.space2),
            Text(
              l.onboardModeChooseHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppTheme.space5),
            _CompareCard(
              icon: Icons.cloud_outlined,
              title: l.onboardModeOnlineTitle,
              body: l.onboardModeOnlineBullets,
            ),
            const SizedBox(height: AppTheme.space3),
            _CompareCard(
              icon: Icons.wifi_off,
              title: l.onboardModeOfflineTitle,
              body: l.onboardModeOfflineBullets,
            ),
            const SizedBox(height: AppTheme.space4),
            CheckboxListTile(
              value: _acked,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _acked = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(l.onboardModeAckLabel),
            ),
            const SizedBox(height: AppTheme.space3),
            FilledButton(
              onPressed: enabled
                  ? () => _pick(SettingsRepository.operatingModeOnline)
                  : null,
              child: Text(l.onboardModeOnlineTitle),
            ),
            const SizedBox(height: AppTheme.space2),
            OutlinedButton(
              onPressed: enabled
                  ? () => _pick(SettingsRepository.operatingModeOffline)
                  : null,
              child: Text(l.onboardModeOfflineTitle),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompareCard extends StatelessWidget {
  const _CompareCard({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: AppTheme.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppTheme.space1),
                  Text(body, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
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
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const LicenseScreen(),
            )),
            icon: const Icon(Icons.key_outlined),
            label: Text(l.onboardActivateNow),
          ),
          const SizedBox(height: AppTheme.space2),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await ref.read(licenseControllerProvider.notifier).continueFree();
              if (context.mounted) {
                messenger.showSnackBar(
                    SnackBar(content: Text(l.licensePlanFree)));
              }
            },
            child: Text(l.onboardingContinueFree),
          ),
        ],
      ),
    );
  }
}

/// Online path: Register (signup) or Sign in — blocks Next until authenticated.
class _OnlineAuthPage extends ConsumerStatefulWidget {
  const _OnlineAuthPage({required this.onAuthenticated});
  final VoidCallback onAuthenticated;

  @override
  ConsumerState<_OnlineAuthPage> createState() => _OnlineAuthPageState();
}

class _OnlineAuthPageState extends ConsumerState<_OnlineAuthPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _shopName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _shopName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
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

  Future<void> _signup() async {
    final l = AppLocalizations.of(context);
    if (_shopName.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _password.text.isEmpty) {
      return;
    }
    if (_password.text != _confirmPassword.text) {
      setState(() => _error = l.accountPasswordMismatch);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref.read(accountRepositoryProvider).signupShop(
        _shopName.text.trim(), _email.text.trim(), _password.text);
    if (!mounted) return;
    if (result.ok && result.license != null) {
      ref
          .read(licenseControllerProvider.notifier)
          .applyExternal(result.license!);
      setState(() {
        _busy = false;
        _done = true;
      });
      widget.onAuthenticated();
    } else {
      setState(() {
        _busy = false;
        _error = _errorMessage(l, result.error);
      });
    }
  }

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
      widget.onAuthenticated();
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
        title: l.onboardOnlineTitle,
        body: l.onboardOnlineSignedIn,
      );
    }
    return ContentWidth(
      maxWidth: 480,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.space5),
        child: Column(
          children: [
            TabBar(
              controller: _tabs,
              tabs: [
                Tab(text: l.onboardOnlineTabRegister),
                Tab(text: l.onboardOnlineTabSignIn),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppTheme.space4,
                    ),
                    child: Column(
                      children: [
                        Text(l.onboardOnlineBody,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: AppTheme.space4),
                        TextField(
                          controller: _shopName,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [
                            AutofillHints.organizationName,
                          ],
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(labelText: l.shopName),
                        ),
                        const SizedBox(height: AppTheme.space3),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                          decoration:
                              InputDecoration(labelText: l.accountEmail),
                        ),
                        const SizedBox(height: AppTheme.space3),
                        AuthPasswordField(
                          controller: _password,
                          labelText: l.accountPassword,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.next,
                        ),
                        PasswordStrengthMeter(controller: _password),
                        const SizedBox(height: AppTheme.space3),
                        AuthPasswordField(
                          controller: _confirmPassword,
                          labelText: l.accountConfirmPassword,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _busy ? null : _signup(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: AppTheme.space3),
                          InlineErrorBanner(message: _error!),
                        ],
                        const SizedBox(height: AppTheme.space4),
                        FilledButton(
                          onPressed: _busy ? null : _signup,
                          child: Text(l.onboardOnlineCreateAccount),
                        ),
                      ],
                    ),
                  ),
                  SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppTheme.space4,
                    ),
                    child: Column(
                      children: [
                        Text(l.onboardOnlineSignInBody,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: AppTheme.space4),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                          decoration:
                              InputDecoration(labelText: l.accountEmail),
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
                      ],
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
