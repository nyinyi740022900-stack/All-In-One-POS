part of 'license_screen.dart';

String _planName(AppLocalizations l, LicensePlan plan) => switch (plan) {
      LicensePlan.yearly => l.licensePlanYearly,
      LicensePlan.monthly => l.licensePlanMonthly,
      LicensePlan.trial => l.licenseFreeTrial,
    };

/// Shows the unique App Reference ID / Shop Code (the admin extends by this).
class _RefIdTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final id = ref.watch(deviceIdProvider).valueOrNull;
    if (id == null) return const SizedBox.shrink();
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: const Icon(Icons.qr_code_2),
        title: Text(l.licenseRefId),
        subtitle: Text(id, style: const TextStyle(fontFamily: 'monospace')),
        trailing: IconButton(
          icon: const Icon(Icons.copy),
          tooltip: l.commonCopy,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: id));
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(l.copied)));
            }
          },
        ),
      ),
    );
  }
}

class _PayToCard extends StatelessWidget {
  const _PayToCard({required this.config, required this.method});

  final VendorConfig config;
  final String method;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (String name, String number) = switch (method) {
      'kbzpay' => (config.kbzName, config.kbzNumber),
      'wavepay' => (config.waveName, config.waveNumber),
      _ => ('', ''),
    };
    if (number.isEmpty) return const SizedBox(height: AppTheme.space2);

    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.space2),
      child: Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space3),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.licensePayTo,
                        style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 2),
                    Text('${paymentLabel(l, method)} · $number',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (name.isNotEmpty) Text(name),
                  ],
                ),
              ),
              IconButton(
                tooltip: l.commonCopy,
                icon: const Icon(Icons.copy),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: number));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l.copied)));
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lists the shop's device slots and lets the owner add or release one.
/// Devices are meaningless offline/on a trial — the caller only shows this
/// once the shop has a real paid key (see build() in license_screen.dart).
class _DevicesSection extends ConsumerWidget {
  const _DevicesSection();

  Future<void> _addDevice(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    // Pick the new device's intended role FIRST — so it can be baked into
    // the QR and applied automatically on activation, instead of needing a
    // second manual "switch to Staff" step on the new phone (easy to forget,
    // which would leave it in full Owner mode).
    final picked = await _pickDeviceRole(context, ref);
    if (picked == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final result =
        await ref.read(licenseRepositoryProvider).requestDeviceSlot();
    if (!context.mounted) return;

    if (result.ok) {
      ref.invalidate(shopDevicesProvider);
      await showDialog<void>(
        context: context,
        builder: (_) => _NewDeviceKeyDialog(
          provisioning: DeviceProvisioning(
            key: result.key!,
            role: picked.role,
            staffMemberId: picked.staffMemberId,
          ),
        ),
      );
      return;
    }
    if (result.errorCode == 'payment_required') {
      final cfg = await ref.read(vendorConfigProvider.future);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _DevicePaymentRequiredDialog(
          fee: result.fee ?? cfg.deviceExtraFee,
          freeLimit: cfg.deviceFreeLimit,
          viber: cfg.supportViber,
        ),
      );
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(l.deviceRequestFailed)));
  }

  /// Lets the owner choose the new device's intended role (and, for Staff,
  /// which roster member) before a slot is even claimed. Null = cancelled.
  Future<({String role, String? staffMemberId})?> _pickDeviceRole(
      BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final members = ref.read(staffMembersProvider).valueOrNull ?? const [];
    var role = 'owner';
    String? staffMemberId;

    return showDialog<({String role, String? staffMemberId})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(l.deviceRoleTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.deviceRoleHint,
                  style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: AppTheme.space3),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'owner', label: Text(l.staffRoleOwner)),
                  ButtonSegment(value: 'staff', label: Text(l.staffRoleStaff)),
                ],
                selected: {role},
                onSelectionChanged: (s) => setLocal(() {
                  role = s.first;
                  if (role == 'owner') staffMemberId = null;
                }),
              ),
              if (role == 'staff' && members.isNotEmpty) ...[
                const SizedBox(height: AppTheme.space3),
                DropdownButtonFormField<String?>(
                  initialValue: staffMemberId,
                  decoration:
                      InputDecoration(labelText: l.deviceRoleStaffMember),
                  items: [
                    DropdownMenuItem<String?>(
                        value: null, child: Text(l.staffNoNamedStaff)),
                    for (final m in members)
                      DropdownMenuItem<String?>(
                          value: m.id, child: Text(m.name)),
                  ],
                  onChanged: (v) => setLocal(() => staffMemberId = v),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx)
                  .pop((role: role, staffMemberId: staffMemberId)),
              child: Text(l.commonYes),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRelease(
      BuildContext context, WidgetRef ref, ShopDevice d) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deviceReleaseConfirmTitle),
        content: Text(l.deviceReleaseConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.deviceRelease)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final released =
        await ref.read(licenseRepositoryProvider).releaseDevice(d.deviceId!);
    if (released) {
      ref.invalidate(shopDevicesProvider);
      messenger.showSnackBar(SnackBar(content: Text(l.deviceReleased)));
    } else {
      messenger.showSnackBar(SnackBar(content: Text(l.deviceRequestFailed)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final devices = ref.watch(shopDevicesProvider);
    final cfg = ref.watch(vendorConfigProvider).valueOrNull;
    final myDeviceId = ref.watch(deviceIdProvider).valueOrNull;
    final freeLimit = cfg?.deviceFreeLimit ?? 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.deviceSectionTitle,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppTheme.space1),
        devices.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppTheme.space2),
            child: LinearProgressIndicator(),
          ),
          error: (e, _) => Text('$e'),
          data: (list) {
            final used = list.where((d) => d.isBound).length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.deviceCount(used, freeLimit),
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: AppTheme.space2),
                for (final d in list.where((d) => d.isBound))
                  Card(
                    margin: const EdgeInsets.only(bottom: AppTheme.space2),
                    child: ListTile(
                      leading: const Icon(Icons.smartphone),
                      title: Text(
                        d.deviceId == myDeviceId
                            ? l.deviceThisDevice
                            : '${d.deviceId!.substring(0, 8)}…',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      subtitle: Text(d.lastVerifiedAt == null
                          ? l.deviceNeverVerified
                          : l.deviceLastActive(
                              DateFormat('yyyy-MM-dd HH:mm')
                                  .format(d.lastVerifiedAt!))),
                      trailing: TextButton(
                        onPressed: () => _confirmRelease(context, ref, d),
                        child: Text(l.deviceRelease),
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _addDevice(context, ref),
                  icon: const Icon(Icons.add),
                  label: Text(l.deviceAdd),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _NewDeviceKeyDialog extends StatelessWidget {
  const _NewDeviceKeyDialog({required this.provisioning});
  final DeviceProvisioning provisioning;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.deviceKeyReadyTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.deviceKeyReadyHint, textAlign: TextAlign.center),
          const SizedBox(height: AppTheme.space4),
          BarcodeWidget(
            barcode: Barcode.qrCode(),
            data: provisioning.encode(),
            width: 180,
            height: 180,
          ),
          const SizedBox(height: AppTheme.space3),
          SelectableText(provisioning.key,
              style: const TextStyle(
                  fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          if (provisioning.role == 'staff') ...[
            const SizedBox(height: AppTheme.space2),
            Text(l.deviceRoleAppliesOnScan,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: provisioning.key));
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(l.deviceKeyCopied)));
            }
          },
          icon: const Icon(Icons.copy),
          label: Text(l.commonCopy),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonYes),
        ),
      ],
    );
  }
}

class _DevicePaymentRequiredDialog extends StatelessWidget {
  const _DevicePaymentRequiredDialog({
    required this.fee,
    required this.freeLimit,
    required this.viber,
  });
  final int fee;
  final int freeLimit;
  final String viber;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final feeText = Money(fee).withSymbol(l.currencySymbol);
    return AlertDialog(
      title: Text(l.devicePaymentRequiredTitle),
      content: Text(
        l.devicePaymentRequiredBody(freeLimit, feeText) +
            (viber.isEmpty ? '' : '\n\nViber: $viber'),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonYes),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final LicenseStatus status;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    final (String label, Color color, IconData icon) = switch (status.kind) {
      LicenseStatusKind.active =>
        (l.licenseStatusActive, Colors.green, Icons.verified),
      LicenseStatusKind.grace =>
        (l.licenseStatusGrace, Colors.orange, Icons.timelapse),
      LicenseStatusKind.expired =>
        (l.licenseStatusExpired, scheme.error, Icons.error),
      LicenseStatusKind.none =>
        (l.licenseStatusNone, scheme.outline, Icons.info_outline),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space4),
        child: Row(
          children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(width: AppTheme.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: color)),
                  if (status.plan != null)
                    Text('${l.licensePlanLabel}: ${_planName(l, status.plan!)}',
                        style: Theme.of(context).textTheme.bodySmall),
                  if (status.expiresAt != null)
                    Text(l.licenseExpires(
                        DateFormat('yyyy-MM-dd').format(status.expiresAt!))),
                  if (status.kind == LicenseStatusKind.grace)
                    Text(l.licenseGraceLeft(status.graceDaysLeft),
                        style: TextStyle(color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
