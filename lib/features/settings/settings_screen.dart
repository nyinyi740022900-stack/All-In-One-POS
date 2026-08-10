import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/intl.dart';

import '../../core/env.dart';
import '../../core/layout.dart';
import '../../core/locale_controller.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/sync/sync_providers.dart';
import '../account/branch_providers.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
import '../license/license_screen.dart';
import '../license/license_status.dart';
import '../printing/label_printer_settings_screen.dart';
import '../printing/printer_settings_screen.dart';
import '../printing/printing_providers.dart';
import '../referral/referral_screen.dart';
import '../../core/money.dart';
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
import '../equity/equity_screen.dart';
import '../suppliers/accounts_payable_providers.dart';
import '../suppliers/accounts_payable_screen.dart';
import '../suppliers/suppliers_screen.dart';
import '../staff/staff_providers.dart';
import '../staff/staff_ui.dart';
import '../storefront/storefront_screen.dart';
import '../support/support_providers.dart';
import '../onboarding/operating_mode_providers.dart';
import 'device_label_providers.dart';
import 'help_guide_screen.dart';
import 'shop_profile_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final locale = ref.watch(localeControllerProvider);
    final session = ref.watch(sessionScopeProvider);
    final isOwner = session.isEffectiveOwner;
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ContentWidth(
        child: ListView(
        children: [
          _SectionHeader(l.settingsSectionBusiness),
          ListTile(
            leading: const Icon(Icons.store),
            title: Text(l.settingsShop),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ShopProfileScreen()),
            ),
          ),
          if (isOwner) _TrackStockTile(),
          ListTile(
            leading: const Icon(Icons.point_of_sale_outlined),
            title: Text(l.cashRegisterTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CashSessionScreen()),
            ),
          ),
          _CreditTile(),
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: Text(l.customersTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const CustomersScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(l.expensesTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ExpenseScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.local_shipping_outlined),
            title: Text(l.suppliersTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SuppliersScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.shopping_cart_outlined),
            title: Text(l.purchaseOrdersTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PurchaseOrdersScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.credit_card_outlined),
            title: Text(l.paymentAccountsTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PaymentAccountsScreen()),
            ),
          ),
          _AccountsPayableTile(),
          _EquityTile(),
          if (isOwner && ref.watch(isOnlineModeProvider)) _StorefrontTile(),

          _SectionHeader(l.settingsSectionFinance),
          if (isOwner) _LicenseTile(),
          if (ref.watch(isOnlineModeProvider))
            ListTile(
              leading: const Icon(Icons.alternate_email),
              title: Text(l.accountShopLoginTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ShopLoginScreen()),
              ),
            ),
          if (ref.watch(isOnlineModeProvider) &&
              session.backendRole != null &&
              isOwner) ...[
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: Text(l.staffAccountsTitle),
              subtitle: Text(l.staffAccountsSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                if (!await requireOwnerPinReauth(
                      context,
                      ref,
                      capability: OwnerCapability.staffAccounts,
                    ) ||
                    !context.mounted) {
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const StaffAccountsScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.store_mall_directory_outlined),
              title: Text(l.branchesTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                if (!await requireOwnerPinReauth(
                      context,
                      ref,
                      capability: OwnerCapability.branches,
                    ) ||
                    !context.mounted) {
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BranchesScreen()),
                );
              },
            ),
          ],
          _ReferralTile(),
          if (isOwner)
            ListTile(
              leading: const Icon(Icons.backup),
              title: Text(l.backupTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const BackupScreen())),
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
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.sell),
            title: Text(l.settingsLabelPrinter),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const LabelPrinterSettingsScreen(),
              ),
            ),
          ),
          _DeviceLabelTile(),
          if (ref.watch(isOnlineModeProvider)) _SyncTile(),

          _SectionHeader(l.settingsSectionHelp),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: Text(l.settingsAppGuide),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const HelpGuideScreen())),
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
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space4,
        AppTheme.space5,
        AppTheme.space4,
        AppTheme.space2,
      ),
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
    final shopId = ref.watch(shopIdProvider);
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
                ref.read(settingsRepositoryProvider).setTrackStock(shopId, v),
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l.copied)));
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
      subtitle: Text(
        total > 0
            ? l.creditTotalDue(Money(total).withSymbol(l.currencySymbol))
            : l.creditNoneDue,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const CreditScreen())),
    );
  }
}

class _AccountsPayableTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final total = ref.watch(accountsPayableTotalProvider);
    return ListTile(
      leading: const Icon(Icons.request_quote_outlined),
      title: Text(l.accountsPayableTitle),
      subtitle: Text(
        total > 0
            ? l.creditTotalDue(Money(total).withSymbol(l.currencySymbol))
            : l.apNoneDue,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const AccountsPayableScreen())),
    );
  }
}

class _EquityTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return ListTile(
      leading: const Icon(Icons.savings_outlined),
      title: Text(l.equityTitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const OwnerEquityScreen())),
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.licenseDowngradedToFreeNotice)));
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
    final colors = AppColors.of(context);
    final (
      String label,
      Color color,
    ) = licState.license?.plan == LicensePlan.free
        ? (l.licensePlanFree, Theme.of(context).colorScheme.outline)
        : switch (status.kind) {
            LicenseStatusKind.active => (l.licenseStatusActive, colors.success),
            LicenseStatusKind.grace => (l.licenseStatusGrace, colors.warning),
            LicenseStatusKind.expired => (
              l.licenseStatusExpired,
              colors.danger,
            ),
            LicenseStatusKind.none => (
              l.licenseStatusNone,
              Theme.of(context).colorScheme.outline,
            ),
          };
    final mode = ref.watch(operatingModeProvider).valueOrNull;
    final modeLabel = mode == SettingsRepository.operatingModeOnline
        ? l.operatingModeOnline
        : mode == SettingsRepository.operatingModeOffline
            ? l.operatingModeOffline
            : null;
    return ListTile(
      leading: const Icon(Icons.key),
      title: Text(l.settingsLicense),
      subtitle: Text(
        modeLabel == null ? label : '$label · ${l.operatingModeLabel}: $modeLabel',
        style: TextStyle(color: color),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const LicenseScreen())),
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
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const StorefrontScreen())),
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
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ReferralScreen())),
    );
  }
}

class _SyncTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final sync = ref.watch(syncControllerProvider);
    final pending =
        ref.watch(pendingOutboxCountProvider).valueOrNull ??
        sync.pendingOutboxCount;
    final stuckCount =
        (ref.watch(stuckOutboxProvider).valueOrNull ?? const []).length;
    final effectiveStuck =
        stuckCount > 0 ? stuckCount : sync.stuckOutboxCount;

    final (String status, IconData icon) = switch (sync.phase) {
      SyncPhase.disabled => (l.syncDisabled, Icons.cloud_off),
      SyncPhase.syncing => (l.syncSyncing, Icons.cloud_sync),
      SyncPhase.offline => (l.syncOffline, Icons.cloud_off),
      SyncPhase.error => (sync.error ?? l.syncError, Icons.error_outline),
      SyncPhase.idle => effectiveStuck > 0
          ? (l.syncHasIssues, Icons.warning_amber_rounded)
          : (pending > 0
                ? (l.syncPendingUploads, Icons.cloud_upload_outlined)
                : (l.syncIdle, Icons.cloud_done)),
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

    return Column(
      children: [
        ListTile(
          leading: Icon(icon),
          title: Text('${l.settingsSync} — $status'),
          subtitle: subtitle.isEmpty ? null : Text(subtitle),
          trailing: sync.phase == SyncPhase.disabled
              ? null
              : (sync.phase == SyncPhase.syncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.sync),
                        tooltip: l.syncNow,
                        onPressed: () => ref
                            .read(syncControllerProvider.notifier)
                            .sync(force: true),
                      )),
        ),
        // Sync Issues is intentionally NOT listed here — poison-pill
        // remediation is an owner escape hatch from Branches when switch
        // is blocked, not an everyday Settings warning for cashiers.
      ],
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
    BuildContext context,
    WidgetRef ref,
    String? current,
  ) async {
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
