import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/locale_controller.dart';
import '../../data/repositories/settings_repository.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_screen.dart';
import '../printing/printing_providers.dart';

/// First-run, one-time flow: welcome + language, shop profile, license/trial
/// explainer, and an Owner/Staff-mode primer. Shown once per install (gated
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
  static const _pageCount = 4;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _pageCount - 1) {
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
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
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
                children: [
                  _WelcomePage(),
                  _ShopProfilePage(),
                  _LicensePage(),
                  _StaffModePage(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  for (var i = 0; i < _pageCount; i++)
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
                      onPressed: _next,
                      child: Text(_page == _pageCount - 1
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

class _LicensePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _OnboardPage(
      icon: Icons.verified_outlined,
      title: l.onboardLicenseTitle,
      body: l.onboardLicenseBody,
      extra: OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const LicenseScreen(),
        )),
        icon: const Icon(Icons.key_outlined),
        label: Text(l.onboardActivateNow),
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
