import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/build_flags.dart';
import '../../core/net/edge_invoke.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../account/account_action_error.dart';
import '../account/account_providers.dart';
import '../account/shop_login_screen.dart';
import '../printing/printing_providers.dart';
import '../staff/staff_providers.dart';
import '../staff/staff_ui.dart';
import '../support/support_providers.dart';
import '../support/viber_launch.dart';
import 'license_model.dart';
import 'license_providers.dart';
import 'license_status.dart';
part 'license_widgets.dart';

class LicenseScreen extends ConsumerStatefulWidget {
  const LicenseScreen({super.key});
  @override
  ConsumerState<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends ConsumerState<LicenseScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _awaitingExternalPayment = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingExternalPayment) {
      _awaitingExternalPayment = false;
      _refresh();
    }
  }

  Future<void> _openAccount() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ShopLoginScreen()));
    if (!mounted) return;
    ref.invalidate(hasRealAccountSessionProvider);
    ref.invalidate(backendAccountRoleProvider);
  }

  Future<void> _startSelfServeTrial() async {
    if (!ref.read(hasRealAccountSessionProvider)) {
      await _openAccount();
      return;
    }
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.licenseFreeTrial),
        content: Text(l.licenseTrialStartConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.licenseFreeTrial),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final profile = await ref.read(shopProfileProvider.future);
      final result = await ref
          .read(licenseControllerProvider.notifier)
          .startFreeTrial(profile.name);
      if (!mounted) return;
      if (result.ok) {
        messenger.showSnackBar(SnackBar(content: Text(l.licenseTrialStarted)));
      } else {
        final msg = switch (result.errorCode) {
          'trial_already_used' => l.licenseTrialUsed,
          'rate_limited' => l.licenseRateLimited,
          'network_error' => l.commonNetworkError,
          _ => l.licenseActivateFailed,
        };
        messenger.showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choosePurchaseRegion() async {
    final cfg = await ref.read(vendorConfigProvider.future);
    if (!cfg.hasLemonSqueezy) {
      await _openRenewPage();
      return;
    }
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    final region = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.licenseChooseRegionTitle),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'mm'),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined),
                const SizedBox(width: AppTheme.space3),
                Text(l.licenseRegionMyanmar),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'intl'),
            child: Row(
              children: [
                const Icon(Icons.public_outlined),
                const SizedBox(width: AppTheme.space3),
                Text(l.licenseRegionInternational),
              ],
            ),
          ),
        ],
      ),
    );
    if (region == 'mm') {
      await _openRenewPage();
    } else if (region == 'intl') {
      await _openLemonSqueezyCheckout();
    }
  }

  Future<void> _contactSupportForPremium() async {
    final l = AppLocalizations.of(context);
    final viber = ref.read(vendorConfigProvider).valueOrNull?.supportViber;
    if (viber == null || viber.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.licenseTrialViberMissing)));
      return;
    }
    await openSupportViber(context, number: viber);
  }

  Future<void> _openRenewPage() async {
    final lic = ref.read(licenseControllerProvider).license;
    if (!ref.read(hasRealAccountSessionProvider)) {
      await _openAccount();
      return;
    }
    final uri = Uri.https('shop.allinonepos.app', '/renew', {
      if (lic != null) 'shop_id': lic.shopId,
    });
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _awaitingExternalPayment = true;
    }
  }

  Future<void> _openLemonSqueezyCheckout() async {
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final plan = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.licensePlanLabel),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'monthly'),
            child: Text(l.licensePlanMonthly),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'yearly'),
            child: Text(l.licensePlanYearly),
          ),
        ],
      ),
    );
    if (plan == null || !mounted) return;
    final shopId = ref.read(shopIdProvider);
    try {
      final res = await Supabase.instance.client.functions.invokeBounded(
        'storefront',
        body: {'action': 'create_checkout', 'shop_id': shopId, 'plan': plan},
      );
      final data = res.data as Map<String, dynamic>?;
      final url = data?['url'] as String?;
      if (data?['ok'] == false || data?['error'] != null || url == null) {
        // The server refuses to sell rather than mis-term a purchase when the
        // gateway keys or variant config are wrong — say so instead of
        // blaming the network.
        throw StateError(
          data?['error'] == 'checkout_unavailable'
              ? 'checkout_unavailable'
              : 'checkout_failed',
        );
      }
      final uri = Uri.parse(url);
      if (uri.scheme != 'https' ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('checkout_failed');
      }
      _awaitingExternalPayment = true;
    } catch (error) {
      if (mounted) {
        final unavailable =
            error is StateError && error.message == 'checkout_unavailable';
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              unavailable
                  ? l.licenseCheckoutUnavailable
                  : l.commonUnexpectedError,
            ),
          ),
        );
      }
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(licenseControllerProvider.notifier)
          .refreshOnline();
      if (!mounted) return;
      if (result.ok) ref.invalidate(shopDevicesProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.ok
                ? l.licenseRefreshed
                : accountActionErrorMessage(l, result.errorCode),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (!ref.watch(hasOwnerCapabilityProvider(OwnerCapability.license))) {
      return Scaffold(
        appBar: AppBar(title: Text(l.settingsLicense)),
        body: const OwnerOnlyGate(
          capability: OwnerCapability.license,
          child: SizedBox.shrink(),
        ),
      );
    }
    final state = ref.watch(licenseControllerProvider);
    final hasAccount = ref.watch(hasRealAccountSessionProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsLicense)),
      body: state.loading
          ? const AppLoadingView()
          : ListView(
              padding: const EdgeInsets.all(AppTheme.space4),
              children: [
                _StatusCard(status: state.status),
                if (state.status.kind == LicenseStatusKind.verificationRequired)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppTheme.space2,
                    ),
                    child: Text(l.licenseVerificationRequiredBody),
                  ),
                const SizedBox(height: AppTheme.space4),
                if (!hasAccount)
                  FilledButton.icon(
                    onPressed: _busy ? null : _openAccount,
                    icon: const Icon(Icons.login),
                    label: Text(l.licenseAccountRequired),
                  ),
                if (hasAccount) ...[
                  const _AccountEmailTile(),
                  const SizedBox(height: AppTheme.space4),
                  if (kCommerceUiEnabled && !state.isPremium) ...[
                    FilledButton.icon(
                      onPressed: _busy ? null : _startSelfServeTrial,
                      icon: const Icon(Icons.workspace_premium_outlined),
                      label: Text(l.licenseFreeTrial),
                    ),
                    const SizedBox(height: AppTheme.space2),
                    Text(l.licenseTrialSelfServeHint),
                    const SizedBox(height: AppTheme.space4),
                  ],
                  _PurchasePaths(
                    busy: _busy,
                    hasAccount: true,
                    showCheckRenewal: true,
                    onPayOnline: _choosePurchaseRegion,
                    onContactViber: _contactSupportForPremium,
                    onCheckRenewal: _refresh,
                  ),
                  const SizedBox(height: AppTheme.space4),
                  const _DevicesSection(),
                ],
              ],
            ),
    );
  }
}
