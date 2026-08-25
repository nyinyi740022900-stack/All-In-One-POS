import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/intl.dart';

import '../../core/build_flags.dart';
import '../../core/env.dart';
import '../../core/layout.dart';
import '../../core/locale_controller.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/sync/sync_providers.dart';
import '../account/account_providers.dart';
import '../account/branch_providers.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
import '../license/license_screen.dart';
import '../license/license_status.dart';
import '../license/premium_gate.dart';
import '../printing/label_printer_settings_screen.dart';
import '../printing/printer_settings_screen.dart';
import '../printing/printing_providers.dart';
import 'barcode_scanner_help_screen.dart';
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
import '../support/viber_launch.dart';
import 'device_label_providers.dart';
import 'help_guide_screen.dart';
import 'shop_profile_screen.dart';

String _accountTileSubtitle(AppLocalizations l, WidgetRef ref) {
  if (!ref.watch(hasRealAccountSessionProvider)) {
    return l.accountProfileSubtitleSignedOut;
  }
  final email = ref.watch(accountRepositoryProvider).currentAccountEmail;
  if (email != null && email.isNotEmpty) return email;
  return l.accountProfileSubtitleSignedOut;
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final locale = ref.watch(localeControllerProvider);
    final session = ref.watch(sessionScopeProvider);
    final isOwner = session.isEffectiveOwner;
    final showOwnerCloudTiles = ref.watch(showStaffModeSectionProvider);
    final premium = ref.watch(isPremiumProvider);
    final signedIn = ref.watch(hasRealAccountSessionProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppTheme.space5),
          children: [
            // Business: day-to-day shop operations. Money/accounting tiles
            // (Credit book, Expenses, Payment accounts, Accounts payable,
            // Owner's equity) deliberately live under Finance below instead —
            // they used to be mixed in here while a section literally called
            // "Finance" held License/Shop Login/Staff/Branches/Referral/Backup
            // instead, none of which are money-related. Regrouped after the
            // owner spotted the mismatch directly from a Settings screenshot.
            AppSectionHeader(l.settingsSectionBusiness),
            SettingsGroup(
              children: [
                ListTile(
                  leading: const IconAvatar(icon: Icons.store),
                  title: Text(l.settingsShop),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ShopProfileScreen(),
                    ),
                  ),
                ),
                if (isOwner) _TrackStockTile(),
                ListTile(
                  leading: const IconAvatar(icon: Icons.point_of_sale_outlined),
                  title: Text(l.cashRegisterTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CashSessionScreen(),
                    ),
                  ),
                ),
                ListTile(
                  leading: const IconAvatar(icon: Icons.people_outline),
                  title: Text(l.customersTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CustomersScreen()),
                  ),
                ),
                ListTile(
                  leading: const IconAvatar(
                    icon: Icons.local_shipping_outlined,
                  ),
                  title: Text(l.suppliersTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SuppliersScreen()),
                  ),
                ),
                ListTile(
                  leading: const IconAvatar(icon: Icons.shopping_cart_outlined),
                  title: Text(l.purchaseOrdersTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PurchaseOrdersScreen(),
                    ),
                  ),
                ),
                if (Env.hasBackend && showOwnerCloudTiles)
                  isOwner && premium
                      ? _StorefrontTile()
                      : _LockedTile(
                          icon: Icons.storefront,
                          title: l.storefrontTitle,
                          explanation: !isOwner
                              ? l.settingsOwnerModeRequired
                              : (signedIn
                                    ? l.premiumFeatureBodyOnline
                                    : l.premiumFeatureBody),
                          unlockLabel: !isOwner
                              ? l.staffSwitchTo(l.staffRoleOwner)
                              : upgradeCtaLabel(l),
                          onUnlock: !isOwner
                              ? () {
                                  switchStaffRole(context, ref, 'owner');
                                }
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const LicenseScreen(),
                                  ),
                                ),
                        ),
              ],
            ),

            // Finance: money/accounting only.
            AppSectionHeader(l.settingsSectionFinance),
            SettingsGroup(
              children: [
                _CreditTile(),
                ListTile(
                  leading: const IconAvatar(icon: Icons.receipt_long_outlined),
                  title: Text(l.expensesTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ExpenseScreen()),
                  ),
                ),
                ListTile(
                  leading: const IconAvatar(icon: Icons.credit_card_outlined),
                  title: Text(l.paymentAccountsTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PaymentAccountsScreen(),
                    ),
                  ),
                ),
                _AccountsPayableTile(),
                _EquityTile(),
              ],
            ),

            // Account & Team: subscription, sign-in, and who has access.
            AppSectionHeader(l.settingsSectionAccountTeam),
            SettingsGroup(
              children: [
                if (isOwner) _LicenseTile(),
                ListTile(
                  leading: const IconAvatar(
                    icon: Icons.account_circle_outlined,
                  ),
                  title: Text(l.accountShopLoginTitle),
                  subtitle: Text(
                    _accountTileSubtitle(l, ref),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ShopLoginScreen()),
                  ),
                ),
                // Hidden only for invited email staff. Local PIN staff still
                // see the tiles (locked) so Switch-to-Staff cannot make
                // Branches/Staff accounts vanish from Account & Team.
                if (showOwnerCloudTiles)
                  if (isOwner &&
                      signedIn &&
                      session.backendRole != 'staff') ...[
                    ListTile(
                      leading: const IconAvatar(
                        icon: Icons.admin_panel_settings_outlined,
                      ),
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
                      leading: const IconAvatar(
                        icon: Icons.store_mall_directory_outlined,
                      ),
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
                          MaterialPageRoute(
                            builder: (_) => const BranchesScreen(),
                          ),
                        );
                      },
                    ),
                  ] else if (!isOwner) ...[
                    _LockedTile(
                      icon: Icons.admin_panel_settings_outlined,
                      title: l.staffAccountsTitle,
                      explanation: l.settingsOwnerModeRequired,
                      unlockLabel: l.staffSwitchTo(l.staffRoleOwner),
                      onUnlock: () {
                        switchStaffRole(context, ref, 'owner');
                      },
                    ),
                    _LockedTile(
                      icon: Icons.store_mall_directory_outlined,
                      title: l.branchesTitle,
                      explanation: l.settingsOwnerModeRequired,
                      unlockLabel: l.staffSwitchTo(l.staffRoleOwner),
                      onUnlock: () {
                        switchStaffRole(context, ref, 'owner');
                      },
                    ),
                  ] else ...[
                    _LockedTile(
                      icon: Icons.admin_panel_settings_outlined,
                      title: l.staffAccountsTitle,
                      explanation: l.settingsSignInRequired,
                      unlockLabel: l.settingsSignIn,
                      onUnlock: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ShopLoginScreen(),
                        ),
                      ),
                    ),
                    _LockedTile(
                      icon: Icons.store_mall_directory_outlined,
                      title: l.branchesTitle,
                      explanation: l.settingsSignInRequired,
                      unlockLabel: l.settingsSignIn,
                      onUnlock: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ShopLoginScreen(),
                        ),
                      ),
                    ),
                  ],
                _ReferralTile(),
              ],
            ),

            // Device: local device settings + data, no longer "& Staff" —
            // Staff Accounts moved to Account & Team above; Backup moved here,
            // it's device/data, not account.
            AppSectionHeader(l.settingsSectionDevice),
            SettingsGroup(
              children: [
                ListTile(
                  leading: const IconAvatar(icon: Icons.language),
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
                      DropdownMenuItem(
                        value: 'my',
                        child: Text(l.languageMyanmar),
                      ),
                      DropdownMenuItem(
                        value: 'en',
                        child: Text(l.languageEnglish),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const IconAvatar(icon: Icons.print),
                  title: Text(l.settingsPrinter),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PrinterSettingsScreen(),
                    ),
                  ),
                ),
                ListTile(
                  leading: const IconAvatar(
                    icon: Icons.document_scanner_outlined,
                  ),
                  title: Text(l.scannerSettings),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const BarcodeScannerHelpScreen(),
                    ),
                  ),
                ),
                ListTile(
                  leading: const IconAvatar(icon: Icons.sell),
                  title: Text(l.settingsLabelPrinter),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LabelPrinterSettingsScreen(),
                    ),
                  ),
                ),
                _DeviceLabelTile(),
                if (Env.hasBackend)
                  premium
                      ? _SyncTile()
                      : _LockedTile(
                          icon: Icons.cloud_sync,
                          title: l.settingsSync,
                          explanation: signedIn
                              ? l.premiumFeatureBodyOnline
                              : l.premiumFeatureBody,
                          unlockLabel: upgradeCtaLabel(l),
                          onUnlock: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const LicenseScreen(),
                            ),
                          ),
                        ),
                if (isOwner)
                  ListTile(
                    leading: const IconAvatar(icon: Icons.backup),
                    title: Text(l.backupTitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const BackupScreen()),
                    ),
                  ),
              ],
            ),

            AppSectionHeader(l.settingsSectionHelp),
            SettingsGroup(
              children: [
                ListTile(
                  leading: const IconAvatar(icon: Icons.help_outline),
                  title: Text(l.settingsAppGuide),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HelpGuideScreen()),
                  ),
                ),
                _SupportTile(),
              ],
            ),

            // Device PIN + Owner/Staff switch — works with or without an
            // email login. Hidden only for invited email staff: they sign
            // out from Account instead of managing the shop PIN.
            if (ref.watch(showStaffModeSectionProvider)) ...[
              AppSectionHeader(l.settingsSectionOwnerTools),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppTheme.space3),
                child: StaffModeCard(),
              ),
            ],
          ],
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
      leading: const IconAvatar(icon: Icons.inventory),
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
            onChanged: (v) async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref
                    .read(settingsRepositoryProvider)
                    .setTrackStock(shopId, v);
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text(l.commonUnexpectedError)),
                );
              }
            },
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
      leading: const IconAvatar(icon: Icons.support_agent),
      title: Text(l.settingsSupport),
      subtitle: Text('Viber · $viber'),
      trailing: IconButton(
        icon: const Icon(Icons.copy),
        tooltip: l.commonCopy,
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: viber));
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l.copied)));
          }
        },
      ),
      onTap: () => openSupportViber(context, number: viber),
    );
  }
}

class _CreditTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final total = ref.watch(creditOutstandingTotalProvider);
    return ListTile(
      leading: const IconAvatar(icon: Icons.account_balance_wallet),
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
      leading: const IconAvatar(icon: Icons.request_quote_outlined),
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
      leading: const IconAvatar(icon: Icons.savings_outlined),
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
    // Plan status is the primary fact; whether a cloud account is linked is
    // a secondary, live readout — no more permanent "shop mode" to report.
    final hasAccount = ref.watch(hasRealAccountSessionProvider);
    return ListTile(
      leading: const IconAvatar(icon: Icons.key),
      title: Text(l.settingsLicense),
      subtitle: Text(
        hasAccount ? '$label · ${l.licenseAccountLinked}' : label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const LicenseScreen())),
    );
  }
}

/// A tile for a feature that's currently locked (Premium or a shop account
/// required) — shown dimmed with a lock icon instead of vanishing entirely,
/// so a Free/offline shop discovers the capability exists rather than never
/// knowing. Tapping explains why and offers a way to unlock it, instead of
/// navigating straight into the feature.
class _LockedTile extends StatelessWidget {
  const _LockedTile({
    required this.icon,
    required this.title,
    required this.explanation,
    required this.unlockLabel,
    required this.onUnlock,
  });
  final IconData icon;
  final String title;
  final String explanation;
  final String unlockLabel;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListTile(
      leading: IconAvatar(icon: icon),
      title: Text(title),
      trailing: Icon(
        Icons.lock_outline,
        color: Theme.of(context).colorScheme.primary,
      ),
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(explanation),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.commonCancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                onUnlock();
              },
              child: Text(unlockLabel),
            ),
          ],
        ),
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
      leading: const IconAvatar(icon: Icons.storefront),
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
    //
    // Also commerce end to end — it quotes the monthly price, pays a
    // commission when a referred shop *pays*, and redeems that balance for
    // licence days — so a store build (see kCommerceUiEnabled) hides the
    // entrance outright rather than trying to launder the wording.
    if (!Env.hasBackend ||
        !kCommerceUiEnabled ||
        status.kind == LicenseStatusKind.none) {
      return const SizedBox.shrink();
    }
    return ListTile(
      leading: const IconAvatar(icon: Icons.card_giftcard),
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
    final effectiveStuck = stuckCount > 0 ? stuckCount : sync.stuckOutboxCount;

    final (String status, IconData icon) = switch (sync.phase) {
      SyncPhase.disabled => (l.syncDisabled, Icons.cloud_off),
      SyncPhase.syncing => (l.syncSyncing, Icons.cloud_sync),
      SyncPhase.offline => (l.syncOffline, Icons.cloud_off),
      SyncPhase.error => (sync.error ?? l.syncError, Icons.error_outline),
      SyncPhase.idle =>
        effectiveStuck > 0
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
          leading: IconAvatar(icon: icon),
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
      leading: const IconAvatar(icon: Icons.devices_outlined),
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
    final label = await showDialog<String>(
      context: context,
      // Use the dialog's own context (not the outer Settings-screen one) to
      // pop — showDialog pushes onto the root navigator by default, but the
      // outer context here belongs to a go_router shell branch's own nested
      // navigator, which only ever holds this one page; popping *that* one
      // instead crashes the whole shell branch ("no pages left to show").
      builder: (_) => _DeviceLabelDialog(initial: current ?? ''),
    );
    if (label == null) return;
    try {
      final deviceId = await ref.read(deviceIdProvider.future);
      await ref.read(deviceLabelRepositoryProvider).setLabel(deviceId, label);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).commonUnexpectedError),
          ),
        );
      }
    }
  }
}

/// Owns its own [TextEditingController] so `dispose()` runs on the dialog
/// route's real teardown rather than the moment `showDialog`'s future
/// resolves on *pop* (which is before the exit animation finishes) — a
/// controller created and disposed inline around `await showDialog` crashes
/// with "A TextEditingController was used after being disposed" because the
/// still-animating `TextField` outlives it. Same fix as
/// `checkout_sheet.dart`'s (since-replaced) line-discount dialog and friends.
class _DeviceLabelDialog extends StatefulWidget {
  const _DeviceLabelDialog({required this.initial});
  final String initial;

  @override
  State<_DeviceLabelDialog> createState() => _DeviceLabelDialogState();
}

class _DeviceLabelDialogState extends State<_DeviceLabelDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.settingsDeviceName),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: l.settingsDeviceNameHint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l.commonSave),
        ),
      ],
    );
  }
}
