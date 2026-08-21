part of 'license_screen.dart';

String _planName(AppLocalizations l, LicensePlan plan) => switch (plan) {
  LicensePlan.yearly => l.licensePlanYearly,
  LicensePlan.monthly => l.licensePlanMonthly,
  LicensePlan.trial => l.licensePlanTrial,
  LicensePlan.free => l.licensePlanFree,
};

/// Shows the unique App Reference ID / Shop Code (the admin extends by this).
/// Offline / device-key model only — Online uses [_AccountEmailTile] instead.
class _RefIdTile extends ConsumerWidget {
  const _RefIdTile();

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
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(l.copied)));
            }
          },
        ),
      ),
    );
  }
}

/// Online Support identity — shop account email, not a device license key.
class _AccountEmailTile extends ConsumerWidget {
  const _AccountEmailTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    String? email;
    try {
      email = ref.watch(accountRepositoryProvider).currentAccountEmail;
    } catch (_) {
      email = null;
    }
    final text = (email != null && email.isNotEmpty)
        ? email
        : l.licenseAccountEmailMissing;
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: const Icon(Icons.alternate_email),
        title: Text(l.licenseAccountEmail),
        subtitle: Text(text),
        trailing: email != null && email.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.copy),
                tooltip: l.commonCopy,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: email!));
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(l.copied)));
                  }
                },
              )
            : null,
      ),
    );
  }
}

/// Lists the shop's bound devices. Extra phones sign in and tap Check for
/// renewal — Support raises the cap from the admin panel (no key).
class _DevicesSection extends ConsumerWidget {
  const _DevicesSection();


  Future<void> _confirmRelease(
    BuildContext context,
    WidgetRef ref,
    ShopDevice d,
  ) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deviceReleaseConfirmTitle),
        content: Text(l.deviceReleaseConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.deviceRelease),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final released = await ref
        .read(licenseRepositoryProvider)
        .releaseDevice(d.deviceId!);
    if (released) {
      ref.invalidate(shopDevicesProvider);
      ref.invalidate(shopDeviceAllowanceProvider);
      messenger.showSnackBar(SnackBar(content: Text(l.deviceReleased)));
    } else {
      messenger.showSnackBar(SnackBar(content: Text(l.deviceRequestFailed)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final devices = ref.watch(shopDevicesProvider);
    final allowance = ref.watch(shopDeviceAllowanceProvider).valueOrNull ??
        ShopDeviceAllowance.none;
    final cfg = ref.watch(vendorConfigProvider).valueOrNull;
    final myDeviceId = ref.watch(deviceIdProvider).valueOrNull;
    final freeLimit = cfg?.deviceFreeLimit ?? 3;
    final extraQuota = extraDeviceQuota(freeLimit) +
        allowance.activeExtraSlots(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.deviceSectionTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppTheme.space1),
        devices.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppTheme.space2),
            child: LinearProgressIndicator(),
          ),
          error: (e, _) => Text(l.commonUnexpectedError),
          data: (list) {
            final bound = list.where((d) => d.isBound).length;
            final used = extraDevicesUsed(bound);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.deviceCount(used, extraQuota),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
                      subtitle: Text(
                        d.lastVerifiedAt == null
                            ? l.deviceNeverVerified
                            : l.deviceLastActive(
                                DateFormat(
                                  'yyyy-MM-dd HH:mm',
                                ).format(d.lastVerifiedAt!),
                              ),
                      ),
                      trailing: TextButton(
                        onPressed: () => _confirmRelease(context, ref, d),
                        child: Text(l.deviceRelease),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: AppTheme.space2),
                  child: Text(
                    l.deviceAddOnlineHint(extraQuota),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            );
          },
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
    final colors = AppColors.of(context);

    final (String label, Color color, IconData icon) = switch (status.kind) {
      LicenseStatusKind.active => (
        l.licenseStatusActive,
        colors.success,
        Icons.verified,
      ),
      LicenseStatusKind.grace => (
        l.licenseStatusGrace,
        colors.warning,
        Icons.timelapse,
      ),
      LicenseStatusKind.expired => (
        l.licenseStatusExpired,
        colors.danger,
        Icons.error,
      ),
      LicenseStatusKind.none => (
        l.licenseStatusNone,
        scheme.outline,
        Icons.info_outline,
      ),
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
                  Text(
                    label,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: color),
                  ),
                  if (status.plan != null)
                    Text(
                      '${l.licensePlanLabel}: ${_planName(l, status.plan!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  // The Free plan never expires (see computeLicenseStatus) —
                  // its expiresAt is a meaningless placeholder, not a real date.
                  if (status.expiresAt != null &&
                      status.plan != LicensePlan.free)
                    Text(
                      l.licenseExpires(
                        DateFormat('yyyy-MM-dd').format(status.expiresAt!),
                      ),
                    ),
                  if (status.kind == LicenseStatusKind.grace)
                    Text(
                      l.licenseGraceLeft(status.graceDaysLeft),
                      style: TextStyle(color: color),
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

/// Two equal purchase paths (website vs Viber) then a separate "already
/// paid?" check — the License screen used to put a Viber-copy action in a
/// button labelled Renew, hide the actual number, and list Pay online as if
/// it were a different kind of thing.
class _PurchasePaths extends ConsumerWidget {
  const _PurchasePaths({
    required this.busy,
    required this.hasAccount,
    required this.showCheckRenewal,
    required this.onPayOnline,
    required this.onContactViber,
    required this.onCheckRenewal,
  });

  final bool busy;
  final bool hasAccount;
  final bool showCheckRenewal;
  final VoidCallback onPayOnline;
  final VoidCallback onContactViber;
  final VoidCallback onCheckRenewal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final viber = ref.watch(vendorConfigProvider).valueOrNull?.supportViber;
    final hasViber = viber != null && viber.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.licenseBuyOrRenewTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppTheme.space1),
        Text(
          l.licenseBuyOrRenewIntro,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppTheme.space3),
        FilledButton.icon(
          onPressed: busy ? null : onPayOnline,
          icon: const Icon(Icons.open_in_new),
          label: Text(l.licensePayOnline),
        ),
        const SizedBox(height: AppTheme.space1),
        Text(
          l.licensePayOnlineHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppTheme.space3),
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: ListTile(
            leading: const Icon(Icons.chat_outlined),
            title: Text(l.licenseContactViber),
            subtitle: Text(
              hasViber ? 'Viber · $viber' : l.licenseTrialViberMissing,
            ),
            trailing: hasViber
                ? IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: l.commonCopy,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: viber));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${l.copied}: Viber · $viber'),
                          ),
                        );
                      }
                    },
                  )
                : null,
            onTap: hasViber ? onContactViber : null,
          ),
        ),
        const SizedBox(height: AppTheme.space1),
        Text(
          hasAccount
              ? l.licenseContactViberHintOnline
              : l.licenseContactViberHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (hasAccount) ...[
          const SizedBox(height: AppTheme.space1),
          Text(
            l.licenseOnlineApplyHint,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
        if (showCheckRenewal) ...[
          const SizedBox(height: AppTheme.space4),
          Text(
            l.licenseAfterPaymentTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppTheme.space2),
          OutlinedButton.icon(
            onPressed: busy ? null : onCheckRenewal,
            icon: busy
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
        ],
      ],
    );
  }
}
