import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/intl.dart';

import '../../core/env.dart';
import '../../core/locale_controller.dart';
import '../../data/sync/sync_providers.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
import '../license/license_screen.dart';
import '../license/license_status.dart';
import '../printing/label_printer_settings_screen.dart';
import '../printing/printer_settings_screen.dart';
import '../printing/printing_providers.dart';
import '../referral/referral_screen.dart';
import '../../core/money.dart';
import '../backup/backup_screen.dart';
import '../credit/credit_providers.dart';
import '../credit/credit_screen.dart';
import '../customers/customers_screen.dart';
import '../staff/staff_providers.dart';
import '../staff/staff_ui.dart';
import '../storefront/storefront_screen.dart';
import '../support/support_providers.dart';
import 'shop_profile_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final locale = ref.watch(localeControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ListView(
        children: [
          _SectionHeader(l.settingsSectionBusiness),
          ListTile(
            leading: const Icon(Icons.store),
            title: Text(l.settingsShop),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const ShopProfileScreen(),
            )),
          ),
          _TrackStockTile(),
          _CreditTile(),
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: Text(l.customersTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const CustomersScreen(),
            )),
          ),
          if (ref.watch(isOwnerProvider)) _StorefrontTile(),

          _SectionHeader(l.settingsSectionFinance),
          _LicenseTile(),
          _ReferralTile(),
          ListTile(
            leading: const Icon(Icons.backup),
            title: Text(l.backupTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const BackupScreen(),
            )),
          ),

          _SectionHeader(l.settingsSectionDevice),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(l.settingsLanguage),
            trailing: DropdownButton<String>(
              value: locale,
              underline: const SizedBox.shrink(),
              onChanged: (v) {
                if (v != null) {
                  ref.read(localeControllerProvider.notifier).set(v);
                }
              },
              items: [
                DropdownMenuItem(value: 'my', child: Text(l.languageMyanmar)),
                DropdownMenuItem(value: 'en', child: Text(l.languageEnglish)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.print),
            title: Text(l.settingsPrinter),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const PrinterSettingsScreen(),
            )),
          ),
          ListTile(
            leading: const Icon(Icons.sell),
            title: Text(l.settingsLabelPrinter),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const LabelPrinterSettingsScreen(),
            )),
          ),
          _SyncTile(),

          _SectionHeader(l.settingsSectionHelp),
          _SupportTile(),

          // Kept well away from the everyday settings above — this is where
          // an owner locks the device into Staff mode (or switches back with
          // the PIN), not something staff should stumble across while
          // browsing Settings.
          _SectionHeader(l.settingsSectionOwnerTools),
          const StaffModeCard(),
        ],
      ),
    );
  }
}

/// A small uppercase label that groups the settings list into sections, so a
/// screen with a dozen+ tiles reads as a few short lists instead of one flat
/// wall (Business / Finance / Device & Staff / Help).
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

class _TrackStockTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final tracking = ref.watch(trackStockProvider).valueOrNull ?? true;
    return ListTile(
      leading: const Icon(Icons.inventory),
      title: Text(l.settingsTrackStock),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            tooltip: l.settingsTrackStockHint,
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: Text(l.settingsTrackStock),
                content: Text(l.settingsTrackStockHint),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l.commonOk),
                  ),
                ],
              ),
            ),
          ),
          Switch(
            value: tracking,
            onChanged: (v) =>
                ref.read(settingsRepositoryProvider).setTrackStock(v),
          ),
        ],
      ),
    );
  }
}

class _SupportTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final viber = ref.watch(vendorConfigProvider).valueOrNull?.supportViber;
    if (viber == null || viber.isEmpty) return const SizedBox.shrink();
    return ListTile(
      leading: const Icon(Icons.support_agent),
      title: Text(l.settingsSupport),
      subtitle: Text('Viber · $viber'),
      trailing: const Icon(Icons.copy),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: viber));
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(l.copied)));
        }
      },
    );
  }
}

class _CreditTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final total = ref.watch(creditOutstandingTotalProvider);
    return ListTile(
      leading: const Icon(Icons.account_balance_wallet),
      title: Text(l.creditTitle),
      subtitle: Text(total > 0
          ? l.creditTotalDue(Money(total).withSymbol(l.currencySymbol))
          : l.creditNoneDue),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const CreditScreen(),
      )),
    );
  }
}

class _LicenseTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final status = ref.watch(licenseControllerProvider).status;
    final (String label, Color color) = switch (status.kind) {
      LicenseStatusKind.active => (l.licenseStatusActive, Colors.green),
      LicenseStatusKind.grace => (l.licenseStatusGrace, Colors.orange),
      LicenseStatusKind.expired =>
        (l.licenseStatusExpired, Theme.of(context).colorScheme.error),
      LicenseStatusKind.none =>
        (l.licenseStatusNone, Theme.of(context).colorScheme.outline),
    };
    return ListTile(
      leading: const Icon(Icons.key),
      title: Text(l.settingsLicense),
      subtitle: Text(label, style: TextStyle(color: color)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const LicenseScreen(),
      )),
    );
  }
}

class _StorefrontTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    // Storefront config lives on the server; only offer it with a backend.
    if (!Env.hasBackend) return const SizedBox.shrink();
    return ListTile(
      leading: const Icon(Icons.storefront),
      title: Text(l.storefrontTitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const StorefrontScreen(),
      )),
    );
  }
}

class _ReferralTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final status = ref.watch(licenseControllerProvider).status;
    // Referral earnings live on the server and key off an activated shop, so
    // only surface this once there's a backend and a license that has been
    // activated. Still shown when expired/grace so a lapsed shop can redeem its
    // balance toward renewal — only hidden when never activated.
    if (!Env.hasBackend || status.kind == LicenseStatusKind.none) {
      return const SizedBox.shrink();
    }
    return ListTile(
      leading: const Icon(Icons.card_giftcard),
      title: Text(l.referralTitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const ReferralScreen(),
      )),
    );
  }
}

class _SyncTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final sync = ref.watch(syncControllerProvider);

    final (String status, IconData icon) = switch (sync.phase) {
      SyncPhase.disabled => (l.syncDisabled, Icons.cloud_off),
      SyncPhase.syncing => (l.syncSyncing, Icons.cloud_sync),
      SyncPhase.idle => (l.syncIdle, Icons.cloud_done),
      SyncPhase.offline => (l.syncOffline, Icons.cloud_off),
      SyncPhase.error => (sync.error ?? l.syncError, Icons.error_outline),
    };

    final lastSynced = sync.lastSyncedAt != null
        ? l.syncLastSynced(DateFormat('HH:mm').format(sync.lastSyncedAt!))
        : (sync.phase == SyncPhase.disabled ? '' : l.syncNever);
    final realtimeOn =
        ref.watch(licenseControllerProvider).license?.realtimeEnabled ?? false;
    final subtitle = [
      if (lastSynced.isNotEmpty) lastSynced,
      if (realtimeOn) l.syncRealtimeOn,
    ].join(' · ');

    return ListTile(
      leading: Icon(icon),
      title: Text('${l.settingsSync} — $status'),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: sync.phase == SyncPhase.disabled
          ? null
          : (sync.phase == SyncPhase.syncing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(
                  icon: const Icon(Icons.sync),
                  tooltip: l.syncNow,
                  onPressed: () =>
                      ref.read(syncControllerProvider.notifier).sync(),
                )),
    );
  }
}
