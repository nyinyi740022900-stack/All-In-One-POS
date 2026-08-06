import 'dart:convert';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/image_util.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../account/account_providers.dart';
import '../printing/printing_providers.dart';
import 'license_model.dart';
import 'license_request.dart';
import '../sell/barcode_scanner_screen.dart';
import '../sell/payment_labels.dart';
import '../staff/staff_providers.dart';
import '../staff/staff_ui.dart';
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

  Future<void> _startTrial() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final ok = await ref
          .read(licenseControllerProvider.notifier)
          .startFreeTrial();
      messenger.showSnackBar(
        SnackBar(
          content: Text(ok ? l.licenseTrialStarted : l.licenseTrialUsed),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
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
              // Which dialog to show follows whether this device is
              // *currently* signed in with a real account — not the shop's
              // stored pricing tier, which can stay 'online' after a
              // sign-out (see AccountRepository.signOut). Dispatching on
              // tier alone would show the Online dialog's "not signed in"
              // warning and nudge a signed-out device toward signing back
              // in just to renew, instead of letting it use the plain
              // key-request flow it can complete right now.
              onPressed: () =>
                  ref.read(accountRepositoryProvider).isSignedInWithRealAccount
                  ? _showOnlineSubscribeDialog()
                  : _showOfflineKeyDialog(),
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
            // A Free-plan shop that just paid for a first-time key (via the
            // Upgrade dialog above) has nowhere else to type/scan it in —
            // Free is always `canSell`, so this branch is otherwise all this
            // device ever sees; the key-entry fields below only render in
            // the `else` (not-activated) branch further down. Same reasoning
            // for the trial button — it used to live only in that `else`
            // branch, making it permanently unreachable once a device is on
            // Free plan (the primary path into Free plan in the first
            // place), even though the trial is meant as Free plan's own
            // try-Premium-for-free on-ramp.
            if (state.license?.plan == LicensePlan.free) ...[
              const SizedBox(height: AppTheme.space2),
              OutlinedButton.icon(
                onPressed: _busy ? null : _startTrial,
                icon: const Icon(Icons.card_giftcard),
                label: Text(l.licenseFreeTrial),
              ),
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
                l.licenseRenewHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppTheme.space2),
              TextButton.icon(
                onPressed: _confirmDeactivate,
                icon: const Icon(Icons.link_off),
                label: Text(l.licenseDeactivate),
              ),
            ],
            // A trial's or the Free plan's shop_id is derived from this one
            // device's id, so "another device under the same shop" isn't a
            // coherent idea until the shop is on a real paid key.
            if (state.license?.plan != LicensePlan.trial &&
                state.license?.plan != LicensePlan.free) ...[
              const SizedBox(height: AppTheme.space4),
              const Divider(),
              const SizedBox(height: AppTheme.space2),
              const _DevicesSection(),
            ],
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
            OutlinedButton.icon(
              onPressed: _busy ? null : _startTrial,
              icon: const Icon(Icons.card_giftcard),
              label: Text(l.licenseFreeTrial),
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
                onPressed: _showOfflineKeyDialog,
                icon: const Icon(Icons.shopping_cart_checkout),
                label: Text(l.licenseGetKeyTitle),
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

  /// Same pick→compress flow as the storefront guest checkout's payment
  /// proof (`storefront_page.dart._pickProof`) — reused here rather than
  /// duplicated logic, just returning the picked/compressed bytes instead
  /// of mutating `State` fields, since these dialogs live inside a
  /// `StatefulBuilder`, not a full `ConsumerStatefulWidget`.
  Future<({Uint8List bytes, String ext, String name})?>
  _pickPaymentProof() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = res?.files.firstOrNull;
    if (file == null || file.bytes == null) return null;
    final c = compressImage(
      Uint8List.fromList(file.bytes!),
      fallbackExt: (file.extension ?? 'jpg').toLowerCase(),
    );
    return (bytes: c.bytes, ext: c.ext, name: file.name);
  }

  /// Uploads to the private `payment-proofs` bucket, same as
  /// `StorefrontApi.uploadPaymentProof` — anon uploads are allowed by
  /// policy (migration 0018); the admin console reads it back later via a
  /// signed URL (0022).
  Future<String> _uploadPaymentProof(Uint8List bytes, String ext) async {
    final path =
        'proof-${DateTime.now().millisecondsSinceEpoch}-${bytes.length}.$ext';
    await Supabase.instance.client.storage
        .from('payment-proofs')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: false),
        );
    return path;
  }

  /// The plan/duration/payment-method/amount/txn-id/referral block shared by
  /// both the Offline and Online request dialogs — the manual
  /// KBZPay/WavePay payment mechanism itself doesn't differ by tier, only
  /// the identity section around it does.
  List<Widget> _buildPaymentFields({
    required BuildContext ctx,
    required AppLocalizations l,
    required VendorConfig cfg,
    required String tier,
    required String cur,
    required TextEditingController amount,
    required TextEditingController txn,
    required TextEditingController referral,
    required String Function() getMethod,
    required String Function() getPlan,
    required int Function() getQty,
    required void Function(String) setMethod,
    required void Function(String) setPlan,
    required void Function(int) setQty,
    required void Function(void Function()) setLocal,
    required String? Function() getProofName,
    required Future<void> Function() onPickProof,
    required VoidCallback onRemoveProof,
  }) {
    final plan = getPlan();
    final qty = getQty();
    final method = getMethod();
    const methods = ['kbzpay', 'wavepay'];
    return [
      SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'monthly', label: Text(l.licensePlanMonthly)),
          ButtonSegment(value: 'yearly', label: Text(l.licensePlanYearly)),
        ],
        selected: {plan},
        onSelectionChanged: (s) => setLocal(() {
          setPlan(s.first);
          setQty(1);
          amount.text = '${cfg.priceFor(s.first, tier: tier)}';
        }),
      ),
      const SizedBox(height: AppTheme.space3),
      Row(
        children: [
          Text(l.licenseDuration, style: Theme.of(ctx).textTheme.labelLarge),
          const Spacer(),
          IconButton.filledTonal(
            onPressed: qty > 1
                ? () => setLocal(() {
                    setQty(qty - 1);
                    amount.text =
                        '${cfg.priceFor(plan, tier: tier) * (qty - 1)}';
                  })
                : null,
            icon: const Icon(Icons.remove),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.space3),
            child: Text(
              '$qty ${plan == 'yearly' ? l.unitYears : l.unitMonths}',
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
          ),
          IconButton.filledTonal(
            onPressed: () => setLocal(() {
              setQty(qty + 1);
              amount.text = '${cfg.priceFor(plan, tier: tier) * (qty + 1)}';
            }),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      const SizedBox(height: AppTheme.space2),
      Text(
        '${Money(cfg.priceFor(plan, tier: tier)).withSymbol(cur)} × $qty = ${Money(cfg.priceFor(plan, tier: tier) * qty).withSymbol(cur)}',
        textAlign: TextAlign.center,
        style: Theme.of(
          ctx,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: AppTheme.space3),
      Wrap(
        spacing: AppTheme.space2,
        children: [
          for (final m in methods)
            ChoiceChip(
              label: Text(paymentLabel(l, m)),
              selected: method == m,
              onSelected: (_) => setLocal(() => setMethod(m)),
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
      const SizedBox(height: AppTheme.space3),
      if (getProofName() == null)
        OutlinedButton.icon(
          onPressed: onPickProof,
          icon: const Icon(Icons.attach_file),
          label: Text(l.licensePaymentProofAttach),
        )
      else
        Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Colors.green,
              size: 18,
            ),
            const SizedBox(width: AppTheme.space2),
            Expanded(
              child: Text(
                '${l.licensePaymentProofAttached}: ${getProofName()}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(icon: const Icon(Icons.close), onPressed: onRemoveProof),
          ],
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
                Icon(
                  Icons.card_giftcard,
                  size: 18,
                  color: Theme.of(ctx).colorScheme.primary,
                ),
                const SizedBox(width: AppTheme.space2),
                Text(
                  l.referralHaveCode,
                  style: Theme.of(
                    ctx,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.space1),
            Text(
              l.referralHaveCodeHint,
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
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
    ];
  }

  /// Offline (device-key) tier: shop name + phone are collected manually
  /// since there's no account to read them from — same manual
  /// KBZPay/WavePay-then-admin-approval flow as before.
  Future<void> _showOfflineKeyDialog() async {
    final l = AppLocalizations.of(context);
    final cfg = await ref.read(vendorConfigProvider.future);
    final settings = ref.read(settingsRepositoryProvider);
    final deviceId = await settings.deviceId();
    final profile = await ref.read(shopProfileProvider.future);
    if (!mounted) return;
    const tier = 'offline';
    final cur = l.currencySymbol;
    // Prefill from the shop profile (blank for the default placeholder).
    final shopName = TextEditingController(
      text: profile.name == 'My Shop' ? '' : profile.name,
    );
    final phone = TextEditingController();
    final amount = TextEditingController(
      text: '${cfg.priceFor('monthly', tier: tier)}',
    );
    final txn = TextEditingController();
    final referral = TextEditingController();
    String method = 'kbzpay';
    String plan = 'monthly';
    int qty = 1;
    var busy = false;
    Uint8List? proofBytes;
    String? proofExt;
    String? proofName;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(l.licenseGetKeyTitle),
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
                ..._buildPaymentFields(
                  ctx: ctx,
                  l: l,
                  cfg: cfg,
                  tier: tier,
                  cur: cur,
                  amount: amount,
                  txn: txn,
                  referral: referral,
                  getMethod: () => method,
                  getPlan: () => plan,
                  getQty: () => qty,
                  setMethod: (v) => method = v,
                  setPlan: (v) => plan = v,
                  setQty: (v) => qty = v,
                  setLocal: setLocal,
                  getProofName: () => proofName,
                  onPickProof: () async {
                    final picked = await _pickPaymentProof();
                    if (picked == null) return;
                    setLocal(() {
                      proofBytes = picked.bytes;
                      proofExt = picked.ext;
                      proofName = picked.name;
                    });
                  },
                  onRemoveProof: () => setLocal(() {
                    proofBytes = null;
                    proofExt = null;
                    proofName = null;
                  }),
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
                        String? proofPath;
                        if (proofBytes != null) {
                          proofPath = await _uploadPaymentProof(
                            proofBytes!,
                            proofExt ?? 'jpg',
                          );
                        }
                        await LicenseRequestService.submit(
                          shopId: ref
                              .read(licenseControllerProvider)
                              .license
                              ?.shopId,
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
                          tier: tier,
                          paymentProofPath: proofPath,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) _showThankYou(cfg.supportViber);
                      } catch (_) {
                        setLocal(() => busy = false);
                        messenger.showSnackBar(
                          SnackBar(content: Text(l.licenseActivateFailed)),
                        );
                      }
                    },
              child: Text(l.licenseGetKeyTitle),
            ),
          ],
        ),
      ),
    );
    shopName.dispose();
    phone.dispose();
    amount.dispose();
    txn.dispose();
    referral.dispose();
  }

  /// Online: only ever opened when this device is currently signed in with
  /// a real account (see the Renew/Upgrade button's dispatch), so the shop
  /// name + contact identity are already known from the signed-in
  /// account/profile — nothing to type, just the payment details. Same
  /// manual KBZPay/WavePay-then-admin-approval mechanism as Offline; the
  /// request is simply tagged tier: 'online' and applies to the account,
  /// not a key.
  Future<void> _showOnlineSubscribeDialog() async {
    final l = AppLocalizations.of(context);
    final cfg = await ref.read(vendorConfigProvider.future);
    final settings = ref.read(settingsRepositoryProvider);
    final deviceId = await settings.deviceId();
    final profile = await ref.read(shopProfileProvider.future);
    if (!mounted) return;
    const tier = 'online';
    final cur = l.currencySymbol;
    final accountEmail = ref
        .read(accountRepositoryProvider)
        .currentAccountEmail;
    final amount = TextEditingController(
      text: '${cfg.priceFor('monthly', tier: tier)}',
    );
    final txn = TextEditingController();
    final referral = TextEditingController();
    String method = 'kbzpay';
    String plan = 'monthly';
    int qty = 1;
    var busy = false;
    Uint8List? proofBytes;
    String? proofExt;
    String? proofName;

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
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.verified_user,
                      color: Colors.green,
                    ),
                    title: Text(profile.name),
                    subtitle: Text(accountEmail ?? ''),
                  ),
                ),
                const SizedBox(height: AppTheme.space3),
                ..._buildPaymentFields(
                  ctx: ctx,
                  l: l,
                  cfg: cfg,
                  tier: tier,
                  cur: cur,
                  amount: amount,
                  txn: txn,
                  referral: referral,
                  getMethod: () => method,
                  getPlan: () => plan,
                  getQty: () => qty,
                  setMethod: (v) => method = v,
                  setPlan: (v) => plan = v,
                  setQty: (v) => qty = v,
                  setLocal: setLocal,
                  getProofName: () => proofName,
                  onPickProof: () async {
                    final picked = await _pickPaymentProof();
                    if (picked == null) return;
                    setLocal(() {
                      proofBytes = picked.bytes;
                      proofExt = picked.ext;
                      proofName = picked.name;
                    });
                  },
                  onRemoveProof: () => setLocal(() {
                    proofBytes = null;
                    proofExt = null;
                    proofName = null;
                  }),
                ),
                const SizedBox(height: AppTheme.space2),
                Text(
                  l.licenseOnlineApplyHint,
                  style: Theme.of(ctx).textTheme.bodySmall,
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
                      setLocal(() => busy = true);
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        String? proofPath;
                        if (proofBytes != null) {
                          proofPath = await _uploadPaymentProof(
                            proofBytes!,
                            proofExt ?? 'jpg',
                          );
                        }
                        await LicenseRequestService.submit(
                          shopId: ref
                              .read(licenseControllerProvider)
                              .license
                              ?.shopId,
                          shopName: profile.name,
                          phone: null,
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
                          tier: tier,
                          paymentProofPath: proofPath,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) _showThankYou(cfg.supportViber);
                      } catch (_) {
                        setLocal(() => busy = false);
                        messenger.showSnackBar(
                          SnackBar(content: Text(l.licenseActivateFailed)),
                        );
                      }
                    },
              child: Text(l.licenseSubscribe),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    txn.dispose();
    referral.dispose();
  }
}
