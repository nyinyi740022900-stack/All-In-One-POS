import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/intl.dart';

import '../../core/env.dart';
import '../../core/locale_controller.dart';
import '../../core/theme/app_theme.dart';
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
import '../account/account_providers.dart';
import '../account/branches_screen.dart';
import '../account/shop_login_screen.dart';
import '../account/staff_accounts_screen.dart';
import '../backup/backup_screen.dart';
import '../cash/cash_session_screen.dart';
import '../credit/credit_providers.dart';
import '../credit/credit_screen.dart';
import '../customers/customers_screen.dart';
import '../expenses/expense_screen.dart';
import '../purchasing/purchase_orders_screen.dart';
import '../accounts/payment_accounts_screen.dart';
import '../suppliers/suppliers_screen.dart';
import '../staff/staff_providers.dart';
import '../staff/staff_ui.dart';
import '../storefront/storefront_screen.dart';
import '../support/support_providers.dart';
import 'device_label_providers.dart';
import 'help_guide_screen.dart';
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
          ListTile(
            leading: const Icon(Icons.point_of_sale_outlined),
            title: Text(l.cashRegisterTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const CashSessionScreen(),
            )),
          ),
          _CreditTile(),
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: Text(l.customersTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const CustomersScreen(),
            )),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(l.expensesTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const ExpenseScreen(),
            )),
          ),
          ListTile(
            leading: const Icon(Icons.local_shipping_outlined),
            title: Text(l.suppliersTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const SuppliersScreen(),
            )),
          ),
          ListTile(
            leading: const Icon(Icons.shopping_cart_outlined),
            title: Text(l.purchaseOrdersTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const PurchaseOrdersScreen(),
            )),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: Text(l.paymentAccountsTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const PaymentAccountsScreen(),
            )),
          ),
          if (ref.watch(isOwnerProvider)) _StorefrontTile(),

          _SectionHeader(l.settingsSectionFinance),
          _LicenseTile(),
          ListTile(
            leading: const Icon(Icons.alternate_email),
            title: Text(l.accountShopLoginTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const ShopLoginScreen(),
            )),
          ),
          if (ref.read(accountRepositoryProvider).isSignedInWithRealAccount &&
              ref.watch(isOwnerProvider)) ...[
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: Text(l.staffAccountsTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const StaffAccountsScreen(),
              )),
            ),
            ListTile(
              leading: const Icon(Icons.store_mall_directory_outlined),
              title: Text(l.branchesTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const BranchesScreen(),
              )),
            ),
            _PricingTierTile(),
          ],
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
          _DeviceLabelTile(),
          _SyncTile(),

          _SectionHeader(l.settingsSectionHelp),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: Text(l.settingsAppGuide),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const HelpGuideScreen(),
            )),
          ),
          _SupportTile(),

          // Kept well away from the everyday settings above — this is where
          // an owner locks the device into Staff mode (or switches back with
          // the PIN), not something staff should stumble across while
          // browsing Settings. Hidden entirely for a single-device shop (see
          // showStaffModeSectionProvider) — Staff/Owner mode only matters
          // once there's a second device to hand off to someone else.
          if (ref.watch(showStaffModeSectionProvider)) ...[
            _SectionHeader(l.settingsSectionOwnerTools),
            const StaffModeCard(),
          ],
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
              // Pop via the dialog's own context — showDialog defaults to the
              // root navigator while this screen's own context belongs to
              // go_router's nested shell-branch navigator; popping via the
              // outer context pops the wrong navigator.
              builder: (dialogContext) => AlertDialog(
                title: Text(l.settingsTrackStock),
                content: Text(l.settingsTrackStockHint),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
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

class _LicenseTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_LicenseTile> createState() => _LicenseTileState();
}

class _LicenseTileState extends ConsumerState<_LicenseTile> {
  @override
  void initState() {
    super.initState();
    // The auto-downgrade may have already fired (e.g. at app launch, before
    // Settings was ever opened this session) — a plain `ref.listen`
    // registered at first build would miss that, since it only reacts to
    // changes AFTER registration. Checking the current value on the first
    // frame covers both "just fired" and "fired a while ago."
    WidgetsBinding.instance.addPostFrameCallback((_) => _showDowngradeNotice());
  }

  void _showDowngradeNotice() {
    if (!mounted) return;
    if (!ref.read(pendingPlanDowngradeNoticeProvider)) return;
    ref.read(pendingPlanDowngradeNoticeProvider.notifier).state = false;
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.licenseDowngradedToFreeNotice)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Covers the mirror case `initState`'s postFrame check can't: the
    // auto-downgrade firing (e.g. via the 6-hour silent re-verify) while
    // this tile is already mounted and visible.
    ref.listen<bool>(pendingPlanDowngradeNoticeProvider, (_, pending) {
      if (pending) _showDowngradeNotice();
    });
    final licState = ref.watch(licenseControllerProvider);
    final status = licState.status;
    final (String label, Color color) = licState.license?.plan == LicensePlan.free
        ? (l.licensePlanFree, Theme.of(context).colorScheme.outline)
        : switch (status.kind) {
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

/// Self-service switch between Offline/Online pricing tier — fixed at
/// shop-creation time otherwise (see `CachedLicense.tier`), so a shop that
/// wants to actually change which price applies needs this. Only affects
/// the *suggested* amount on the next renewal request, never shopId/data.
class _PricingTierTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final tier = ref.watch(licenseControllerProvider).license?.tier ?? 'offline';
    final isOnline = tier == 'online';
    final otherTier = isOnline ? 'offline' : 'online';
    return ListTile(
      leading: const Icon(Icons.price_change_outlined),
      title: Text(l.pricingTierTitle),
      subtitle: Text(isOnline ? l.pricingTierOnline : l.pricingTierOffline),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: l.pricingTierWhatsTheDifference,
            onPressed: () => _showComparisonSheet(context, l),
          ),
          TextButton(
            onPressed: () => _confirmSwitch(context, ref, otherTier),
            child: Text(otherTier == 'online'
                ? l.pricingTierSwitchToOnline
                : l.pricingTierSwitchToOffline),
          ),
        ],
      ),
    );
  }

  Future<void> _showComparisonSheet(
      BuildContext context, AppLocalizations l) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppTheme.space4, 0,
              AppTheme.space4, AppTheme.space5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.pricingTierCompareTitle,
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: AppTheme.space4),
              _TierExplainCard(
                icon: Icons.cloud_outlined,
                title: l.pricingTierOnline,
                body: l.pricingTierOnlineExplain,
              ),
              const SizedBox(height: AppTheme.space3),
              _TierExplainCard(
                icon: Icons.smartphone_outlined,
                title: l.pricingTierOffline,
                body: l.pricingTierOfflineExplain,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmSwitch(
      BuildContext context, WidgetRef ref, String newTier) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(newTier == 'online'
            ? l.pricingTierSwitchToOnline
            : l.pricingTierSwitchToOffline),
        content: Text(l.pricingTierConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.commonOk)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final result =
        await ref.read(accountRepositoryProvider).setPricingTier(newTier);
    if (!context.mounted) return;
    if (result.ok && result.license != null) {
      ref.read(licenseControllerProvider.notifier).applyExternal(result.license!);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.accountActionFailed)));
    }
  }
}

class _TierExplainCard extends StatelessWidget {
  const _TierExplainCard(
      {required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.space3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: AppTheme.space2),
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: AppTheme.space1),
          Text(body, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
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

/// Lets the owner give *this* device a friendly name (e.g. "Counter A"),
/// synced so every other device can show it too — see the doc comment on
/// `DeviceLabels` in tables.dart for why this can't be a local setting.
class _DeviceLabelTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final label = ref.watch(myDeviceLabelProvider);
    return ListTile(
      leading: const Icon(Icons.devices_outlined),
      title: Text(l.settingsDeviceName),
      subtitle: Text(label ?? l.settingsDeviceNameUnset),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _editLabel(context, ref, label),
    );
  }

  Future<void> _editLabel(
      BuildContext context, WidgetRef ref, String? current) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController(text: current ?? '');
    final saved = await showDialog<bool>(
      context: context,
      // Use the dialog's own context (not the outer Settings-screen one) to
      // pop — showDialog pushes onto the root navigator by default, but the
      // outer context here belongs to a go_router shell branch's own nested
      // navigator, which only ever holds this one page; popping *that* one
      // instead crashes the whole shell branch ("no pages left to show").
      builder: (dialogContext) => AlertDialog(
        title: Text(l.settingsDeviceName),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l.settingsDeviceNameHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.commonSave),
          ),
        ],
      ),
    );
    final label = controller.text.trim();
    controller.dispose();
    if (saved != true) return;
    final deviceId = await ref.read(deviceIdProvider.future);
    await ref.read(deviceLabelRepositoryProvider).setLabel(deviceId, label);
  }
}
