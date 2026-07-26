import 'dart:convert';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/env.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../printing/printing_providers.dart';
import 'license_model.dart';
import 'license_request.dart';
import '../sell/barcode_scanner_screen.dart';
import '../sell/payment_labels.dart';
import '../staff/staff_providers.dart';
import '../support/support_providers.dart';
import '../support/vendor_config.dart';
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
      final result =
          await ref.read(licenseControllerProvider.notifier).activate(_key.text);
      if (!result.ok) {
        final msg = result.errorCode == 'invalid_key' ||
                result.errorCode == 'device_mismatch'
            ? l.licenseInvalidKey
            : l.licenseActivateFailed;
        messenger.showSnackBar(SnackBar(content: Text(msg)));
      } else {
        // Apply the role the owner picked when generating this device's QR
        // (see DeviceProvisioning) — a no-op if this was a plain key (typed
        // manually, or an older QR with no role attached).
        if (_pendingRole != null) {
          await ref.read(staffControllerProvider).applyProvisionedRole(
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

  /// Scans a device key shown as a QR code on an already-activated device
  /// (see `_DevicesSection`'s "Add a device" flow) instead of typing it. The
  /// QR may carry a role alongside the key (DeviceProvisioning) — remembered
  /// here and applied once activation succeeds.
  Future<void> _scanKey() async {
    final code = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()));
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
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.licenseDeactivate)),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(licenseControllerProvider.notifier).deactivate();
    }
  }

  Future<void> _startTrial() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final ok =
          await ref.read(licenseControllerProvider.notifier).startFreeTrial();
      messenger.showSnackBar(SnackBar(
          content: Text(ok ? l.licenseTrialStarted : l.licenseTrialUsed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result =
          await ref.read(licenseControllerProvider.notifier).refreshOnline();
      final String msg;
      if (result.ok) {
        msg = l.licenseRefreshed;
      } else if (result.errorCode == 'invalid_key' ||
          result.errorCode == 'device_mismatch') {
        msg = l.licenseInvalidKey;
      } else {
        msg = l.licenseActivateFailed; // network / auth
      }
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(licenseControllerProvider);
    final status = state.status;

    return Scaffold(
      appBar: AppBar(title: Text(l.settingsLicense)),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.space4),
        children: [
          _StatusCard(status: status),
          const SizedBox(height: AppTheme.space2),
          _RefIdTile(),
          const SizedBox(height: AppTheme.space4),
          if (status.canSell) ...[
            FilledButton.icon(
              onPressed: () => _showRequestDialog(),
              icon: const Icon(Icons.autorenew),
              label: Text(l.licenseRenew),
            ),
            const SizedBox(height: AppTheme.space2),
            OutlinedButton.icon(
              onPressed: _busy ? null : _refresh,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              label: Text(l.licenseCheckRenewal),
            ),
            const SizedBox(height: AppTheme.space1),
            Text(l.licenseRenewHint,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppTheme.space2),
            TextButton.icon(
              onPressed: _confirmDeactivate,
              icon: const Icon(Icons.link_off),
              label: Text(l.licenseDeactivate),
            ),
            // A trial's shop_id is derived from this one device's id, so
            // "another device under the same shop" isn't a coherent idea
            // until the shop is on a real paid key.
            if (state.license?.plan != LicensePlan.trial) ...[
              const SizedBox(height: AppTheme.space4),
              const Divider(),
              const SizedBox(height: AppTheme.space2),
              const _DevicesSection(),
            ],
          ] else ...[
            Text(l.licenseActivateTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTheme.space1),
            Text(l.licenseGetKey,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppTheme.space3),
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
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(l.licenseActivateBtn),
            ),
            const SizedBox(height: AppTheme.space2),
            OutlinedButton.icon(
              onPressed: _busy ? null : _startTrial,
              icon: const Icon(Icons.card_giftcard),
              label: Text(l.licenseFreeTrial),
            ),
            if (Env.hasBackend) ...[
              const SizedBox(height: AppTheme.space5),
              const Divider(),
              const SizedBox(height: AppTheme.space2),
              Text(l.licenseNoKeyTitle,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppTheme.space1),
              Text(l.licenseNoKeyHint,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: AppTheme.space3),
              OutlinedButton.icon(
                onPressed: _showRequestDialog,
                icon: const Icon(Icons.shopping_cart_checkout),
                label: Text(l.licenseSubscribe),
              ),
            ],
          ],
        ],
      ),
    );
  }

  void _showThankYou(String viber) {
    final l = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 40),
        title: Text(l.licenseThankYouTitle),
        content: Text(
          viber.isEmpty
              ? l.licenseThankYou24h
              : '${l.licenseThankYou24h}\n\nViber: $viber',
          textAlign: TextAlign.center,
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.commonYes),
          ),
        ],
      ),
    );
  }

  /// Self-service subscription request for a user who has no key yet.
  Future<void> _showRequestDialog() async {
    final l = AppLocalizations.of(context);
    final cfg = await ref.read(vendorConfigProvider.future);
    final settings = ref.read(settingsRepositoryProvider);
    final deviceId = await settings.deviceId();
    final profile = await settings.shopProfile();
    if (!mounted) return;
    final cur = l.currencySymbol;
    // Prefill from the shop profile (blank for the default placeholder).
    final shopName = TextEditingController(
        text: profile.name == 'My Shop' ? '' : profile.name);
    final phone = TextEditingController();
    final amount = TextEditingController(text: '${cfg.priceFor('monthly')}');
    final txn = TextEditingController();
    final referral = TextEditingController();
    String method = 'kbzpay';
    String plan = 'monthly';
    int qty = 1;
    const methods = ['kbzpay', 'wavepay'];
    var busy = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(l.licenseSubscribe),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: shopName,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: l.shopName),
                ),
                const SizedBox(height: AppTheme.space2),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: l.customerPhone),
                ),
                const SizedBox(height: AppTheme.space3),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                        value: 'monthly',
                        label: Text(l.licensePlanMonthly)),
                    ButtonSegment(
                        value: 'yearly', label: Text(l.licensePlanYearly)),
                  ],
                  selected: {plan},
                  onSelectionChanged: (s) => setLocal(() {
                    plan = s.first;
                    qty = 1;
                    amount.text = '${cfg.priceFor(plan) * qty}';
                  }),
                ),
                const SizedBox(height: AppTheme.space3),
                Row(
                  children: [
                    Text(l.licenseDuration,
                        style: Theme.of(ctx).textTheme.labelLarge),
                    const Spacer(),
                    IconButton.filledTonal(
                      onPressed: qty > 1
                          ? () => setLocal(() {
                                qty--;
                                amount.text = '${cfg.priceFor(plan) * qty}';
                              })
                          : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.space3),
                      child: Text(
                          '$qty ${plan == 'yearly' ? l.unitYears : l.unitMonths}',
                          style: Theme.of(ctx).textTheme.titleMedium),
                    ),
                    IconButton.filledTonal(
                      onPressed: () => setLocal(() {
                        qty++;
                        amount.text = '${cfg.priceFor(plan) * qty}';
                      }),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.space2),
                Text(
                  '${Money(cfg.priceFor(plan)).withSymbol(cur)} × $qty = ${Money(cfg.priceFor(plan) * qty).withSymbol(cur)}',
                  textAlign: TextAlign.center,
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppTheme.space3),
                Wrap(
                  spacing: AppTheme.space2,
                  children: [
                    for (final m in methods)
                      ChoiceChip(
                        label: Text(paymentLabel(l, m)),
                        selected: method == m,
                        onSelected: (_) => setLocal(() => method = m),
                      ),
                  ],
                ),
                _PayToCard(config: cfg, method: method),
                const SizedBox(height: AppTheme.space2),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: l.licenseAmount),
                ),
                const SizedBox(height: AppTheme.space3),
                TextField(
                  controller: txn,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: InputDecoration(labelText: l.licenseTxnId),
                ),
                const SizedBox(height: AppTheme.space4),
                Container(
                  padding: const EdgeInsets.all(AppTheme.space3),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.card_giftcard,
                              size: 18,
                              color: Theme.of(ctx).colorScheme.primary),
                          const SizedBox(width: AppTheme.space2),
                          Text(l.referralHaveCode,
                              style: Theme.of(ctx)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: AppTheme.space1),
                      Text(l.referralHaveCodeHint,
                          style: Theme.of(ctx).textTheme.bodySmall),
                      const SizedBox(height: AppTheme.space2),
                      TextField(
                        controller: referral,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: l.referralCodeOptional,
                          hintText: 'REF-XXXX',
                          filled: true,
                          fillColor: Theme.of(ctx).colorScheme.surface,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: Text(l.commonCancel),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (shopName.text.trim().isEmpty) return;
                      setLocal(() => busy = true);
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await LicenseRequestService.submit(
                          shopName: shopName.text.trim(),
                          phone: phone.text.trim().isEmpty
                              ? null
                              : phone.text.trim(),
                          plan: plan,
                          months: plan == 'yearly' ? qty * 12 : qty,
                          method: method,
                          amount: int.tryParse(amount.text.trim()) ?? 0,
                          refNo: txn.text.trim().isEmpty
                              ? null
                              : txn.text.trim(),
                          deviceId: deviceId,
                          referredByCode: referral.text.trim().isEmpty
                              ? null
                              : referral.text.trim().toUpperCase(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) _showThankYou(cfg.supportViber);
                      } catch (_) {
                        setLocal(() => busy = false);
                        messenger.showSnackBar(
                            SnackBar(content: Text(l.licenseActivateFailed)));
                      }
                    },
              child: Text(l.licenseSubscribe),
            ),
          ],
        ),
      ),
    );
  }
}

