import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/locale_controller.dart';
import '../../data/repositories/settings_repository.dart';
import '../../l10n/app_localizations.dart';
import '../account/account_providers.dart';
import '../license/license_providers.dart';
import '../license/license_screen.dart';
import '../printing/printing_providers.dart';

/// First-run, one-time flow: mode choice (Offline/Online), welcome +
/// language, shop profile + license/trial (Offline) or a self-serve signup
/// (Online), and an Owner/Staff-mode primer. Shown once per install (gated
/// by `SettingsRepository.onboardingComplete`); never re-shown after.
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
  bool _signupDone = false;

  static const _onlineSignupPageIndex = 2;

  List<Widget> get _pages {
    if (_mode == 'online') {
      return [
        _ModeChoicePage(onChoose: _chooseMode),
        _WelcomePage(),
        _OnlineSignupPage(onSignedUp: () => setState(() => _signupDone = true)),
        _StaffModePage(),
      ];
    }
    if (_mode == 'offline') {
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
      (_mode == 'online' && _page == _onlineSignupPageIndex && !_signupDone);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _chooseMode(String mode) {
    setState(() => _mode = mode);
    Future.microtask(() => _controller.nextPage(
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut));
  }

  void _next(int pageCount) {
    if (_page == pageCount - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
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
            if (_mode != 'online')
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextButton(
                    onPressed: _finish,
                    child: Text(l.onboardSkip),
                  ),
                ),
              ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: pages,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  for (var i = 0; i < pages.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _page
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                  const Spacer(),
                  // A Row's non-flex children (this button) are always given
                  // an *unbounded* width to report their own natural size —
                  // completely normal Flex behavior. On this app's very
                  // first-ever frame in some environments (seen on both iOS
                  // and Android emulators, not on a real device), the
                  // button's internal Text/tap-target sizing has computed an
                  // infinite intrinsic width instead of falling back to its
                  // content width, crashing this whole screen permanently
                  // (the exception aborts the frame and nothing schedules a
                  // repaint afterwards). Capping the button's own max width
                  // gives it a concrete, finite constraint no matter what its
                  // internals compute, without changing how it looks in the
                  // normal case (its natural width is far below this cap).
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: FilledButton(
                      onPressed: _nextDisabled
                          ? null
                          : () => _next(pages.length),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 24),
          Text(title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
          if (extra != null) ...[const SizedBox(height: 20), extra!],
        ],
      ),
    );
  }
}

/// First page: Offline (device-key activation, unchanged) vs Online (real
/// shop account, registration required before entering the app). Tapping
/// either card both records the choice and advances — there's no separate
/// Next step for this page.
class _ModeChoicePage extends StatelessWidget {
  const _ModeChoicePage({required this.onChoose});
  final ValueChanged<String> onChoose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(l.onboardModeTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          _ModeCard(
            icon: Icons.wifi_off,
            title: l.onboardModeOfflineTitle,
            body: l.onboardModeOfflineBody,
            onTap: () => onChoose('offline'),
          ),
          const SizedBox(height: 16),
          _ModeCard(
            icon: Icons.cloud_outlined,
            title: l.onboardModeOnlineTitle,
            body: l.onboardModeOnlineBody,
            onTap: () => onChoose('online'),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(body, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomePage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final locale = ref.watch(localeControllerProvider);
    return _OnboardPage(
      icon: Icons.storefront,
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
    final existing = await repo.shopProfile();
    await repo.saveShopProfile(ShopProfile(
      name: _name.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      address: existing.address,
      footer: existing.footer,
    ));
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
    return SingleChildScrollView(
      child: _OnboardPage(
        icon: Icons.store_outlined,
        title: l.onboardShopTitle,
        body: l.onboardShopBody,
        extra: Column(
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: l.shopName),
              onChanged: (_) => _save(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: l.shopPhone),
              onChanged: (_) => _save(),
            ),
          ],
        ),
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
          const SizedBox(height: 8),
          // No key yet: enter the app immediately on the Free plan (Sell +
          // Inventory work forever, no signup/network call at all) — a real
          // key can be added later from Settings without losing any data.
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

/// Online path's signup — collects shop name (skipping the separate
/// `_ShopProfilePage`, since it's asked here instead) + a real email +
/// password, then calls `AccountRepository.signupShop()`. Blocks the
/// parent's Next button until signup actually succeeds — this page IS the
/// registration gate, not a shortcut past it.
class _OnlineSignupPage extends ConsumerStatefulWidget {
  const _OnlineSignupPage({required this.onSignedUp});
  final VoidCallback onSignedUp;

  @override
  ConsumerState<_OnlineSignupPage> createState() => _OnlineSignupPageState();
}

class _OnlineSignupPageState extends ConsumerState<_OnlineSignupPage> {
  final _shopName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _shopName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _errorMessage(AppLocalizations l, String? code) => switch (code) {
        'email_taken' => l.accountEmailTaken,
        'no_backend' => l.accountNoBackend,
        _ => l.accountActionFailed,
      };

  Future<void> _signup() async {
    final l = AppLocalizations.of(context);
    if (_shopName.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _password.text.isEmpty) {
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
      widget.onSignedUp();
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
    return SingleChildScrollView(
      child: _OnboardPage(
        icon: Icons.cloud_done_outlined,
        title: l.onboardOnlineTitle,
        body: l.onboardOnlineBody,
        extra: _done
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 8),
                  Flexible(child: Text(l.onboardOnlineDone)),
                ],
              )
            : Column(
                children: [
                  TextField(
                    controller: _shopName,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(labelText: l.shopName),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(labelText: l.accountEmail),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: InputDecoration(labelText: l.accountPassword),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _signup,
                    child: Text(l.onboardOnlineCreateAccount),
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
