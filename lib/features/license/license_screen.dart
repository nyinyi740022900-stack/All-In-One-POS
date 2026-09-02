import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/build_flags.dart';
import '../../core/env.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../account/account_action_error.dart';
import '../account/account_providers.dart';
import '../printing/printing_providers.dart';
import 'license_model.dart';
import '../sell/barcode_scanner_screen.dart';
import '../staff/staff_providers.dart';
import '../staff/staff_ui.dart';
import '../support/support_providers.dart';
import '../support/viber_launch.dart';
import 'license_providers.dart';
import 'license_status.dart';
import '../../core/providers.dart';

part 'license_widgets.dart';

/// A device-add QR can carry more than a bare license key: the owner may
/// have picked "this new device is for Staff" (optionally naming which
/// roster member) at the moment they generated it, so activation can apply
/// that role immediately instead of needing a second manual step on the new
/// phone. Encodes as a plain key string for the common Owner case (keeps a
/// typed/manually-entered key working exactly as before); only becomes a
/// JSON blob when a role needs to travel with it.
class DeviceProvisioning {
  final String key;
  final String role;
  final String? staffMemberId;

  const DeviceProvisioning({
    required this.key,
    this.role = 'owner',
    this.staffMemberId,
  });

  String encode() {
    if (role != 'staff') return key;
    return jsonEncode({
      'key': key,
      'role': role,
      if (staffMemberId != null) 'staff_id': staffMemberId,
    });
  }

  factory DeviceProvisioning.decode(String scanned) {
    try {
      final m = jsonDecode(scanned) as Map<String, dynamic>;
      final key = m['key'] as String?;
      if (key == null || key.isEmpty) return DeviceProvisioning(key: scanned);
      return DeviceProvisioning(
        key: key,
        role: m['role'] as String? ?? 'owner',
        staffMemberId: m['staff_id'] as String?,
      );
    } catch (_) {
      return DeviceProvisioning(key: scanned);
    }
  }
}

class LicenseScreen extends ConsumerStatefulWidget {
  const LicenseScreen({super.key});

  @override
  ConsumerState<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends ConsumerState<LicenseScreen> {
  final _key = TextEditingController();
  bool _busy = false;
  // Set when the scanned/entered key carried a role (see DeviceProvisioning)
  // — applied once, right after a successful activation.
  String? _pendingRole;
  String? _pendingStaffMemberId;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(licenseControllerProvider.notifier)
          .activate(_key.text);
      if (!result.ok) {
        final msg =
            result.errorCode == 'invalid_key' ||
                result.errorCode == 'device_mismatch'
            ? l.licenseInvalidKey
            : result.errorCode == 'rate_limited'
            ? l.licenseRateLimited
            : result.errorCode == 'network_error'
            ? l.commonNetworkError
            : l.licenseActivateFailed;
        messenger.showSnackBar(SnackBar(content: Text(msg)));
      } else {
        // Apply the role the owner picked when generating this device's QR
        // (see DeviceProvisioning) — a no-op if this was a plain key (typed
        // manually, or an older QR with no role attached).
        if (_pendingRole != null) {
          await ref
              .read(staffControllerProvider)
              .applyProvisionedRole(
                _pendingRole!,
                staffMemberId: _pendingStaffMemberId,
              );
          _pendingRole = null;
          _pendingStaffMemberId = null;
        }
        messenger.showSnackBar(SnackBar(content: Text(l.licenseActivated)));
        _key.clear();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Self-serve, no-account Premium trial — the "Try Premium" button's
  /// primary path (replaces the old Viber-only flow for a device with no
  /// real account; see `_contactSupportForTrial`, kept as a fallback for
  /// no-connectivity or an already-used device that needs a human override).
  Future<void> _startSelfServeTrial() async {
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

  /// Scans a device key shown as a QR code (older Offline add-device
  /// flow) instead of typing it. The QR may carry a role alongside the key.
  Future<void> _scanKey() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (code != null && code.isNotEmpty && mounted) {
      final provisioning = DeviceProvisioning.decode(code);
      setState(() {
        _key.text = provisioning.key;
        _pendingRole = provisioning.role;
        _pendingStaffMemberId = provisioning.staffMemberId;
      });
    }
  }

  Future<void> _confirmDeactivate() async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.licenseDeactivate),
        content: Text(l.licenseDeactivateConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.licenseDeactivate),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(licenseControllerProvider.notifier).deactivate();
    }
  }

  Future<void> _contactSupportForTrial() {
    final l = AppLocalizations.of(context);
    final hasAccount = ref.read(hasRealAccountSessionProvider);
    return _contactSupport(
      title: l.licenseFreeTrial,
      body: hasAccount
          ? l.licenseTrialContactHintOnline
          : l.licenseTrialContactHint,
    );
  }

  /// Opens a Viber chat with the admin-configured Support number.
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

  Future<void> _contactSupport({
    required String title,
    required String body,
  }) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final viber = ref.read(vendorConfigProvider).valueOrNull?.supportViber;
    if (viber == null || viber.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.licenseTrialViberMissing)),
      );
      return;
    }
    final opened = await launchViberChat(viber);
    if (opened || !mounted) return;
    await Clipboard.setData(ClipboardData(text: viber));
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l.supportViberOpenFailed)));
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.commonOk),
          ),
        ],
      ),
    );
  }

  /// Opens the public web payment-request form (`/renew` on the Storefront
  /// web app) — not part of the app binary, so it's not subject to Apple
  /// 5.1.1(v) (no in-app payment solicitation); it's just a web link, same
  /// as any "visit our website" URL. Restores an actual on-ramp for
  /// Confirm/Decline in the admin dashboard's Requests tab, which otherwise
  /// only Support-via-Viber can feed. Pre-fills what the app already knows
  /// (shop name, App Reference ID, account email if signed in) as query
  /// params — plain visible text, nothing sensitive, and the page itself
  /// already reads/writes these same fields, so a shop opening this from
  /// Settings doesn't have to retype what the app already has.
  Future<void> _openRenewPage() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final lic = ref.read(licenseControllerProvider).license;
    final email = ref.read(accountRepositoryProvider).currentAccountEmail;
    String? shopName;
    try {
      shopName = (await ref.read(shopProfileProvider.future)).name;
    } catch (_) {}
    var deviceId = lic?.deviceId ?? '';
    if (deviceId.isEmpty) {
      deviceId = ref.read(deviceIdProvider).valueOrNull ?? '';
    }
    final uri = Uri.https('shop.allinonepos.app', '/renew', {
      if (shopName != null && shopName.isNotEmpty) 'name': shopName,
      if (deviceId.isNotEmpty) 'device_id': deviceId,
      if (email != null && email.isNotEmpty) 'email': email,
    });
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    }
  }

  /// `_PurchasePaths.onPayOnline` — the single "Pay online" action, for
  /// every shop regardless of country. When Lemon Squeezy is configured,
  /// asks Myanmar vs International right here at the moment of subscribing
  /// (owner's explicit request, replacing the earlier persistent
  /// `ShopProfile.country` flag — that field/column still exists but is no
  /// longer read by the app) and dispatches to [_openRenewPage] or
  /// [_openLemonSqueezyCheckout] accordingly. Before Lemon Squeezy is
  /// configured there's only one real path, so it skips straight to
  /// [_openRenewPage] rather than showing a chooser with one dead option.
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
            child: Text(l.licenseRegionMyanmar),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'intl'),
            child: Text(l.licenseRegionInternational),
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

  /// International purchase path — a hosted Lemon Squeezy checkout URL,
  /// same external-launch shape as [_openRenewPage]. Only reachable via
  /// [_choosePurchaseRegion], which already requires `kCommerceUiEnabled`
  /// (see the store build's commerce gate) and a configured Lemon Squeezy
  /// store.
  Future<void> _openLemonSqueezyCheckout() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final cfg = await ref.read(vendorConfigProvider.future);
    if (!cfg.hasLemonSqueezy) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
      }
      return;
    }
    if (!mounted) return;
    final plan = await showDialog<LicensePlan>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.licenseBuyOrRenewTitle),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, LicensePlan.monthly),
            child: Text(l.licensePlanMonthly),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, LicensePlan.yearly),
            child: Text(l.licensePlanYearly),
          ),
        ],
      ),
    );
    if (plan == null) return;
    final variant = plan == LicensePlan.yearly
        ? cfg.lemonSqueezyVariantYearly
        : cfg.lemonSqueezyVariantMonthly;
    final lic = ref.read(licenseControllerProvider).license;
    var deviceId = lic?.deviceId ?? '';
    if (deviceId.isEmpty) {
      deviceId = ref.read(deviceIdProvider).valueOrNull ?? '';
    }
    final shopId = ref.read(shopIdProvider);
    final uri = Uri.https(
      '${cfg.lemonSqueezyStoreSlug}.lemonsqueezy.com',
      '/checkout/buy/$variant',
      {
        'checkout[custom][shop_id]': shopId,
        if (deviceId.isNotEmpty) 'checkout[custom][device_id]': deviceId,
      },
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    }
  }

  Future<void> _refresh() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(licenseControllerProvider.notifier)
          .refreshOnline();
      final String msg;
      if (result.ok) {
        msg = l.licenseRefreshed;
        ref.invalidate(shopDevicesProvider);
        ref.invalidate(shopDeviceAllowanceProvider);
      } else if (result.errorCode == 'invalid_key' ||
          result.errorCode == 'device_mismatch') {
        msg = l.licenseInvalidKey;
      } else if (result.errorCode == 'rate_limited') {
        msg = l.licenseRateLimited;
      } else {
        msg = accountActionErrorMessage(l, result.errorCode);
      }
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _repairSession() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(licenseControllerProvider.notifier)
          .repairSession();
      final String msg;
      if (result.ok) {
        msg = l.licenseFixConnectionSuccess;
      } else if (result.errorCode == 'rate_limited') {
        msg = l.licenseRateLimited;
      } else if (result.errorCode == 'network_error') {
        msg = l.commonNetworkError;
      } else {
        msg = l.licenseActivateFailed;
      }
      messenger.showSnackBar(SnackBar(content: Text(msg)));
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
    final status = state.status;
    final hasAccount = ref.watch(hasRealAccountSessionProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.settingsLicense)),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.space4),
        children: [
          _StatusCard(status: status),
          const SizedBox(height: AppTheme.space2),
          if (hasAccount) const _AccountEmailTile() else const _RefIdTile(),
          const SizedBox(height: AppTheme.space4),
          if (status.canSell) ...[
            _PurchasePaths(
              busy: _busy,
              hasAccount: hasAccount,
              showCheckRenewal: state.license?.plan != LicensePlan.free,
              onPayOnline: _choosePurchaseRegion,
              onContactViber: _contactSupportForPremium,
              onCheckRenewal: _refresh,
            ),
            // Free-plan try-Premium on-ramp: self-serve for a no-account
            // device (start_trial action, one trial per device_id
            // permanently); Contact-Support-only for a real account that's
            // lapsed to Free — minting a second, disconnected trial shop_id
            // for an account with real billing history would fragment its
            // data rather than help it.
            if (state.license?.plan == LicensePlan.free) ...[
              const SizedBox(height: AppTheme.space4),
              if (!hasAccount) ...[
                FilledButton.icon(
                  onPressed: _busy ? null : _startSelfServeTrial,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.workspace_premium_outlined),
                  label: Text(l.licenseFreeTrial),
                ),
                const SizedBox(height: AppTheme.space1),
                Text(
                  l.licenseTrialSelfServeHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppTheme.space1),
                TextButton(
                  onPressed: _busy ? null : _contactSupportForTrial,
                  child: Text(l.licenseContactSupportTitle),
                ),
              ] else ...[
                OutlinedButton.icon(
                  onPressed: _busy ? null : _contactSupportForTrial,
                  icon: const Icon(Icons.support_agent),
                  label: Text(l.licenseFreeTrial),
                ),
                const SizedBox(height: AppTheme.space1),
                Text(
                  l.licenseTrialContactHintOnline,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              // No account: redeem a device license key. Real account: cloud
              // Premium only — never show key entry (that's the no-account
              // model).
              if (!hasAccount) ...[
                const SizedBox(height: AppTheme.space4),
                const Divider(),
                const SizedBox(height: AppTheme.space2),
                Text(
                  l.licenseHaveKeyTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppTheme.space1),
                Text(
                  l.licenseGetKey,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppTheme.space3),
                ..._buildKeyEntryFields(l),
              ],
            ],
            // Nothing to deactivate for the Free plan — there's no key or
            // subscription behind it, just a local marker.
            if (state.license?.plan != LicensePlan.free) ...[
              if (!hasAccount) ...[
                const SizedBox(height: AppTheme.space2),
                TextButton.icon(
                  onPressed: _busy ? null : _repairSession,
                  icon: const Icon(Icons.build_outlined),
                  label: Text(l.licenseFixConnection),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.space4,
                  ),
                  child: Text(
                    l.licenseFixConnectionHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
              const SizedBox(height: AppTheme.space2),
              TextButton.icon(
                onPressed: _confirmDeactivate,
                icon: const Icon(Icons.link_off),
                label: Text(l.licenseDeactivate),
              ),
            ],
            // Offline paid: device-key slots. Online paid: list + sign-in hint
            // (no key QR — that is the Offline add-device model).
            if (state.license?.plan != LicensePlan.trial &&
                state.license?.plan != LicensePlan.free) ...[
              const SizedBox(height: AppTheme.space4),
              const Divider(),
              const SizedBox(height: AppTheme.space2),
              _DevicesSection(),
            ],
          ] else if (hasAccount) ...[
            // Real account without canSell: recover via website or Viber —
            // never push key typing as the primary path.
            _PurchasePaths(
              busy: _busy,
              hasAccount: true,
              showCheckRenewal: true,
              onPayOnline: _choosePurchaseRegion,
              onContactViber: _contactSupportForPremium,
              onCheckRenewal: _refresh,
            ),
          ] else ...[
            Text(
              l.licenseActivateTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppTheme.space1),
            Text(l.licenseGetKey, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppTheme.space3),
            ..._buildKeyEntryFields(l),
            const SizedBox(height: AppTheme.space2),
            FilledButton.icon(
              onPressed: _busy ? null : _startSelfServeTrial,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.workspace_premium_outlined),
              label: Text(l.licenseFreeTrial),
            ),
            const SizedBox(height: AppTheme.space1),
            Text(
              l.licenseTrialSelfServeHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppTheme.space1),
            TextButton(
              onPressed: _busy ? null : _contactSupportForTrial,
              child: Text(l.licenseContactSupportTitle),
            ),
            // Commerce-only tail. This device has never been activated, so
            // the block has no "check my renewal" half to keep — it is
            // purely "here is where to buy". A store build (see
            // kCommerceUiEnabled) drops it, divider and all, rather than
            // render a heading with nothing actionable under it.
            if (Env.hasBackend && kCommerceUiEnabled) ...[
              const SizedBox(height: AppTheme.space5),
              const Divider(),
              const SizedBox(height: AppTheme.space2),
              _PurchasePaths(
                busy: _busy,
                hasAccount: false,
                showCheckRenewal: false,
                onPayOnline: _choosePurchaseRegion,
                onContactViber: _contactSupportForPremium,
                onCheckRenewal: _refresh,
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// The key `TextField` (+ QR-scan icon) and Activate button — shared by
  /// the not-activated screen and the Free-plan "Already have a license
  /// key?" section, since both are really the same action (redeem a key on
  /// this device), just reachable from different states.
  List<Widget> _buildKeyEntryFields(AppLocalizations l) {
    return [
      TextField(
        controller: _key,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          labelText: l.licenseKeyLabel,
          suffixIcon: IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: l.scanBarcode,
            onPressed: _scanKey,
          ),
        ),
      ),
      const SizedBox(height: AppTheme.space3),
      FilledButton.icon(
        onPressed: _busy ? null : _activate,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check),
        label: Text(l.licenseActivateBtn),
      ),
    ];
  }
}
