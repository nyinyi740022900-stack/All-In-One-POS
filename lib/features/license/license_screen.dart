import 'dart:convert';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../account/account_providers.dart';
import '../printing/printing_providers.dart';
import 'license_model.dart';
import '../sell/barcode_scanner_screen.dart';
import '../staff/staff_providers.dart';
import '../staff/staff_ui.dart';
import '../support/support_providers.dart';
import 'license_providers.dart';
import 'license_status.dart';

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

  /// Scans a device key shown as a QR code on an already-activated device
  /// (see `_DevicesSection`'s "Add a device" flow) instead of typing it. The
  /// QR may carry a role alongside the key (DeviceProvisioning) — remembered
  /// here and applied once activation succeeds.
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

  /// Premium renew/upgrade is Support-only (no in-app KBZPay/WavePay/proof) —
  /// store billing compliance: digital unlock must not solicit external pay
  /// inside the binary.
  Future<void> _contactSupportForPremium() {
    final l = AppLocalizations.of(context);
    final hasAccount = ref.read(hasRealAccountSessionProvider);
    return _contactSupport(
      title: l.licenseContactSupportTitle,
      body: hasAccount
          ? l.licensePremiumContactHintOnline
          : l.licensePremiumContactHint,
    );
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
    await Clipboard.setData(ClipboardData(text: viber));
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('${l.copied}: Viber · $viber')),
    );
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
    final uri = Uri.https('allinonepos-shop.vercel.app', '/renew', {
      if (shopName != null && shopName.isNotEmpty) 'name': shopName,
      if (lic != null && lic.deviceId.isNotEmpty) 'device_id': lic.deviceId,
      if (email != null && email.isNotEmpty) 'email': email,
    });
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
      } else if (result.errorCode == 'invalid_key' ||
          result.errorCode == 'device_mismatch') {
        msg = l.licenseInvalidKey;
      } else if (result.errorCode == 'rate_limited') {
        msg = l.licenseRateLimited;
      } else if (result.errorCode == 'network_error') {
        msg = l.commonNetworkError;
      } else {
        msg = l.licenseActivateFailed; // auth
      }
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (!ref.watch(isEffectiveOwnerProvider)) {
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
            FilledButton.icon(
              onPressed: _busy ? null : _contactSupportForPremium,
              icon: Icon(
                state.license?.plan == LicensePlan.free
                    ? Icons.workspace_premium_outlined
                    : Icons.autorenew,
              ),
              label: Text(
                state.license?.plan == LicensePlan.free
                    ? l.premiumUpgradeCta
                    : l.licenseRenew,
              ),
            ),
            const SizedBox(height: AppTheme.space1),
            Text(
              hasAccount
                  ? l.licensePremiumContactHintOnline
                  : l.licensePremiumContactHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (hasAccount) ...[
              const SizedBox(height: AppTheme.space1),
              Text(
                l.licenseOnlineApplyHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            const SizedBox(height: AppTheme.space2),
            OutlinedButton.icon(
              onPressed: _openRenewPage,
              icon: const Icon(Icons.open_in_new),
              label: Text(l.licensePayOnline),
            ),
            const SizedBox(height: AppTheme.space1),
            Text(
              l.licensePayOnlineHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            // Free-plan try-Premium on-ramp: self-serve for a no-account
            // device (start_trial action, one trial per device_id
            // permanently); Contact-Support-only for a real account that's
            // lapsed to Free — minting a second, disconnected trial shop_id
            // for an account with real billing history would fragment its
            // data rather than help it.
            if (state.license?.plan == LicensePlan.free) ...[
              const SizedBox(height: AppTheme.space2),
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
            // Nothing to check/deactivate for the Free plan — there's no key
            // or subscription behind it, just a local marker.
            if (state.license?.plan != LicensePlan.free) ...[
              const SizedBox(height: AppTheme.space2),
              OutlinedButton.icon(
                onPressed: _busy ? null : _refresh,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(l.licenseCheckRenewal),
              ),
              const SizedBox(height: AppTheme.space1),
              Text(
                hasAccount ? l.licenseRenewHintOnline : l.licenseRenewHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
              _DevicesSection(hasAccount: hasAccount),
            ],
          ] else if (hasAccount) ...[
            // Real account without canSell: recover via Support on the
            // account — never push key typing as the primary path.
            Text(
              l.licenseContactSupportTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppTheme.space1),
            Text(
              l.licensePremiumContactHintOnline,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppTheme.space1),
            Text(
              l.licenseOnlineApplyHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppTheme.space3),
            FilledButton.icon(
              onPressed: _busy ? null : _contactSupportForPremium,
              icon: const Icon(Icons.support_agent),
              label: Text(l.licenseContactSupportTitle),
            ),
            const SizedBox(height: AppTheme.space2),
            OutlinedButton.icon(
              onPressed: _openRenewPage,
              icon: const Icon(Icons.open_in_new),
              label: Text(l.licensePayOnline),
            ),
            const SizedBox(height: AppTheme.space2),
            OutlinedButton.icon(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
              label: Text(l.licenseCheckRenewal),
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
            if (Env.hasBackend) ...[
              const SizedBox(height: AppTheme.space5),
              const Divider(),
              const SizedBox(height: AppTheme.space2),
              Text(
                l.licenseNoKeyTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppTheme.space1),
              Text(
                l.licenseNoKeyHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppTheme.space3),
              OutlinedButton.icon(
                onPressed: _busy ? null : _contactSupportForPremium,
                icon: const Icon(Icons.support_agent),
                label: Text(l.licenseContactSupportTitle),
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
