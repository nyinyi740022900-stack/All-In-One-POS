import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/sync/sync_providers.dart';
import '../../l10n/app_localizations.dart';
import '../settings/sync_issues_screen.dart';
import '../license/license_providers.dart';
import '../license/premium_gate.dart';
import '../staff/staff_ui.dart';
import 'branch_providers.dart';
import 'branch_repository.dart';

/// Lets a real-login owner list, create, unlink, and switch between branches
/// (each its own shop_id/license) they own. Owner-only — see OwnerOnlyGate.
/// Creating a branch (just a name, no key) is the only in-app add path for
/// the online/email model; a second device sees the same list after login.
class BranchesScreen extends ConsumerWidget {
  const BranchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    if (ref.watch(licenseControllerProvider).loading ||
        !ref.watch(isPremiumProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l.branchesTitle)),
        body: PremiumGate(
          featureName: l.branchesTitle,
          benefits: [l.branchesBenefit1, l.branchesBenefit2],
          child: const SizedBox.shrink(),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.branchesTitle)),
      body: OwnerOnlyGate(
        capability: OwnerCapability.branches,
        child: _BranchesBody(),
      ),
      floatingActionButton: OwnerOnlyGate(
        capability: OwnerCapability.branches,
        child: Builder(
          builder: (context) => FloatingActionButton.extended(
            onPressed: () => _createBranch(context, ref),
            icon: const Icon(Icons.add_business),
            label: Text(l.branchesCreate),
          ),
        ),
      ),
    );
  }

  /// The `TextEditingController` lives inside [_CreateBranchDialog], not
  /// here. `await showDialog(...)` completes the moment the route is
  /// *popped*, not when its exit animation finishes, so disposing a
  /// locally-owned controller on the next line tears it out from under a
  /// `TextField` that is still on screen — "A TextEditingController was used
  /// after being disposed", then a cascade of framework assertions and a red
  /// screen. Same shape already fixed in `checkout_sheet.dart`'s
  /// `_LineDiscountDialog`, `categories_screen.dart`'s `_CategoryNameDialog`,
  /// `customers_screen.dart`'s `_CustomerEditorDialog` and
  /// `payment_accounts_screen.dart`'s `_PaymentAccountEditorDialog`.
  Future<void> _createBranch(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    if (!await requireOwnerPinReauth(
      context,
      ref,
      capability: OwnerCapability.branches,
    )) {
      return;
    }
    if (!context.mounted) return;
    final shopName = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateBranchDialog(),
    );
    if (shopName == null || shopName.isEmpty || !context.mounted) return;
    final result = await ref
        .read(branchRepositoryProvider)
        .createBranch(shopName);
    if (!context.mounted) return;
    if (result.ok) {
      ref.invalidate(branchesProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.branchesCreated)));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.accountActionFailed)));
    }
  }
}

/// Add-branch dialog. A `StatefulWidget` purely so its controller is owned by
/// something whose `dispose` runs when the route is actually gone — see
/// [BranchesScreen._createBranch].
class _CreateBranchDialog extends StatefulWidget {
  const _CreateBranchDialog();

  @override
  State<_CreateBranchDialog> createState() => _CreateBranchDialogState();
}

class _CreateBranchDialogState extends State<_CreateBranchDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.branchesCreate),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(labelText: l.shopName),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l.branchesCreate)),
      ],
    );
  }
}

enum _BranchSwitchAction { cancel, syncAndSwitch }

class _BranchPreflightInfo {
  final int pendingOutboxCount;
  final int stuckOutboxCount;
  final bool online;
  final DateTime? lastSyncedAt;

  const _BranchPreflightInfo({
    required this.pendingOutboxCount,
    required this.stuckOutboxCount,
    required this.online,
    required this.lastSyncedAt,
  });
}

enum _BranchSwitchUiStep {
  checkingDataSafety,
  switchingAccountClaim,
  refreshingSession,
  clearingOldData,
  syncingNewData,
}

class _SectionHint extends StatelessWidget {
  const _SectionHint({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.space3),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.branch,
    required this.pendingOutboxCount,
    required this.lastSyncedText,
    required this.healthChip,
    required this.trailing,
    this.showDevicePending = false,
  });

  final Branch branch;
  final int pendingOutboxCount;
  final String lastSyncedText;
  final Widget healthChip;
  final Widget trailing;

  /// When true, pending count is this device's active-shop outbox (not the
  /// other branch's cloud state).
  final bool showDevicePending;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final label = branch.label?.isNotEmpty == true
        ? branch.label!
        : branch.shopId;
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.space2),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconAvatar(
                  icon: branch.isCurrent
                      ? Icons.storefront
                      : Icons.storefront_outlined,
                ),
                const SizedBox(width: AppTheme.space2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppTheme.space1),
                      Text(
                        branch.shopId,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppTheme.space2),
                healthChip,
              ],
            ),
            const SizedBox(height: AppTheme.space2),
            if (showDevicePending) ...[
              Text(
                l.branchesRowPending(pendingOutboxCount),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppTheme.space1),
            ],
            Text(
              l.branchesRowLastSync(lastSyncedText),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppTheme.space2),
            Align(alignment: Alignment.centerRight, child: trailing),
          ],
        ),
      ),
    );
  }
}

class _CurrentBranchPinnedCard extends StatelessWidget {
  const _CurrentBranchPinnedCard({
    required this.branch,
    required this.pendingOutboxCount,
    required this.lastSyncedText,
    required this.healthChip,
  });

  final Branch branch;
  final int pendingOutboxCount;
  final String lastSyncedText;
  final Widget healthChip;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final label = branch.label?.isNotEmpty == true
        ? branch.label!
        : branch.shopId;
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.space2),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.push_pin_outlined),
                const SizedBox(width: AppTheme.space2),
                Expanded(
                  child: Text(
                    l.branchesPinnedCurrentTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                healthChip,
              ],
            ),
            const SizedBox(height: AppTheme.space2),
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTheme.space1),
            Text(
              branch.shopId,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTheme.space1),
            Text(
              l.branchesPinnedCurrentHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppTheme.space2),
            Text(
              l.branchesRowPending(pendingOutboxCount),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppTheme.space1),
            Text(
              l.branchesRowLastSync(lastSyncedText),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchesBody extends ConsumerStatefulWidget {
  @override
  ConsumerState<_BranchesBody> createState() => _BranchesBodyState();
}

class _BranchesBodyState extends ConsumerState<_BranchesBody> {
  /// True while a switch flow is running — disables Switch/Unlink so a second
  /// tap doesn't stack, and gives immediate feedback before dialogs appear.
  bool _switchInFlight = false;

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final l = AppLocalizations.of(context);
    final branchesAsync = ref.watch(branchesProvider);
    final recovery = ref.watch(branchSwitchRecoveryProvider).valueOrNull;
    final pendingOutbox =
        ref.watch(pendingOutboxCountProvider).valueOrNull ?? 0;
    final stuckOutbox = ref.watch(stuckOutboxProvider).valueOrNull ?? const [];
    final quarantined =
        ref.watch(quarantinedOutboxProvider).valueOrNull ?? const [];
    final online = ref.watch(branchConnectivityProvider).valueOrNull ?? true;
    final syncState = ref.watch(syncControllerProvider);
    return branchesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: AppColors.of(context).muted,
              ),
              const SizedBox(height: AppTheme.space3),
              Text(
                _branchListErrorMessage(l, error),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppTheme.space4),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(branchesProvider),
                icon: const Icon(Icons.refresh),
                label: Text(l.syncNow),
              ),
            ],
          ),
        ),
      ),
      data: (branches) {
        if (branches.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AppTheme.space5),
            child: EmptyStateView(
              icon: Icons.store_mall_directory_outlined,
              title: l.branchesEmpty,
            ),
          );
        }
        final activeShopId = ref
            .watch(licenseControllerProvider)
            .license
            ?.shopId;
        var currentBranches = branches.where((b) => b.isCurrent).toList();
        var otherBranches = branches.where((b) => !b.isCurrent).toList();

        // Defensive UX fallback: if backend branch metadata is stale/missing,
        // still pin the currently active shop so owners always know where this
        // device is scoped and can reason about switching.
        if (currentBranches.isEmpty &&
            activeShopId != null &&
            activeShopId.isNotEmpty) {
          final fallback = otherBranches
              .where((b) => b.shopId == activeShopId)
              .toList(growable: false);
          if (fallback.isNotEmpty) {
            currentBranches = [
              Branch(
                shopId: fallback.first.shopId,
                label: fallback.first.label,
                isCurrent: true,
              ),
            ];
            otherBranches = otherBranches
                .where((b) => b.shopId != activeShopId)
                .toList();
          } else {
            currentBranches = [
              Branch(shopId: activeShopId, label: null, isCurrent: true),
            ];
          }
        }
        return Column(
          children: [
            if (stuckOutbox.isNotEmpty) _buildStuckBanner(context, ref),
            if (quarantined.isNotEmpty) _buildQuarantineBanner(context),
            if (recovery != null) _buildRecoveryBanner(context, ref, recovery),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space3,
                  AppTheme.space3,
                  AppTheme.space3,
                  AppTheme.space6,
                ),
                children: [
                  Text(
                    l.branchesSectionCurrent,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppTheme.space2),
                  if (currentBranches.isEmpty)
                    _SectionHint(message: l.branchesEmpty)
                  else
                    ...currentBranches.map(
                      (b) => _CurrentBranchPinnedCard(
                        branch: b,
                        pendingOutboxCount: pendingOutbox,
                        lastSyncedText: _formatLastSync(
                          context,
                          syncState.lastSyncedAt,
                        ),
                        healthChip: _buildHealthChip(
                          context,
                          online,
                          pendingOutbox,
                        ),
                      ),
                    ),
                  const SizedBox(height: AppTheme.space4),
                  Text(
                    l.branchesSectionOther,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppTheme.space2),
                  if (otherBranches.isEmpty)
                    _SectionHint(message: l.branchesNoOther)
                  else
                    ...otherBranches.map(
                      (b) => _BranchCard(
                        branch: b,
                        pendingOutboxCount: pendingOutbox,
                        lastSyncedText: _formatLastSync(
                          context,
                          syncState.lastSyncedAt,
                        ),
                        healthChip: _buildHealthChip(
                          context,
                          online,
                          // Health for other cards is about switch safety on
                          // *this* device — still use device pending, but do
                          // not list the pending count on the other card.
                          pendingOutbox,
                        ),
                        showDevicePending: false,
                        trailing: Wrap(
                          spacing: AppTheme.space2,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _switchInFlight
                                  ? null
                                  : () => _confirmSwitch(context, ref, b),
                              icon: _switchInFlight
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.swap_horiz, size: 18),
                              label: Text(l.branchesSwitch),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _switchInFlight
                                  ? null
                                  : () => _confirmUnlink(context, ref, b),
                              style: FilledButton.styleFrom(
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.error,
                              ),
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                size: 18,
                              ),
                              label: Text(l.branchesUnlink),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // A generic `Chip` rendered both states in the exact same neutral fill —
  // "Safe to switch" and "Sync needed" only differed by a 16px icon glyph,
  // easy to miss in a busy card header. `StatusPill` is the component this
  // app already converged on for a two-state signal like this (Orders,
  // Invoices, Customers) — safe reads positive/green, needs-sync reads
  // attention/amber, at a glance rather than on close reading.
  Widget _buildHealthChip(
    BuildContext context,
    bool online,
    int pendingOutbox,
  ) {
    final l = AppLocalizations.of(context);
    final safe = online && pendingOutbox == 0;
    return StatusPill(
      label: safe ? l.branchesHealthSafeSwitch : l.branchesHealthSyncNeeded,
      tone: safe ? StatusTone.positive : StatusTone.attention,
      icon: safe ? Icons.verified_outlined : Icons.sync_problem_outlined,
    );
  }

  // Three near-identical banners in this file (stuck / quarantine /
  // recovery) used to reach for three different raw `ColorScheme` fills —
  // `errorContainer`, `surfaceContainerHighest` + a `primary` icon, and
  // `secondaryContainer` — none of them from the `AppColors` soft-fill tier
  // the rest of the app's banners/pills converged on (see Sell's licence
  // banners, Inventory's low-stock banner, `StatusPill`). Reassigned here by
  // what each one actually *means*, not by what looked closest to the old
  // color: stuck **blocks switching** and needs an immediate fix, so it gets
  // the most severe tone (`critical`/danger); quarantine is explicitly
  // non-blocking, self-resolving background work with nothing for the owner
  // to do (`neutral`/muted — the "real but not urgent" tier); an interrupted
  // switch that's offering a direct "Retry sync" action sits in between
  // (`attention`/warning — open, needs an action, not wrong yet).
  Widget _buildStuckBanner(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    // Do not use MaterialBanner as a Column child — its intrinsic layout
    // collapses content width to ~0 and wraps one character per line.
    return Material(
      color: colors.dangerSurface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space3,
          AppTheme.space3,
          AppTheme.space3,
          AppTheme.space2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: colors.danger),
                const SizedBox(width: AppTheme.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.branchesStuckBannerTitle,
                        style: textTheme.titleSmall?.copyWith(
                          color: colors.danger,
                        ),
                      ),
                      const SizedBox(height: AppTheme.space1),
                      Text(
                        l.branchesStuckBannerBody,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.space2),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SyncIssuesScreen(),
                      ),
                    );
                  },
                  child: Text(l.branchesStuckBannerReview),
                ),
                FilledButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await ref
                        .read(syncControllerProvider.notifier)
                        .sync(force: true);
                    if (!context.mounted) return;
                    final stuck =
                        ref.read(stuckOutboxProvider).valueOrNull ?? const [];
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          stuck.isEmpty
                              ? l.syncIdle
                              : l.branchesStuckBannerBody,
                        ),
                      ),
                    );
                  },
                  child: Text(l.branchesStuckBannerSyncNow),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuarantineBanner(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: colors.neutralSurface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space3,
          AppTheme.space3,
          AppTheme.space3,
          AppTheme.space2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: colors.muted),
                const SizedBox(width: AppTheme.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.branchesQuarantineBannerTitle,
                        style: textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppTheme.space1),
                      Text(
                        l.branchesQuarantineBannerBody,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.space2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SyncIssuesScreen()),
                  );
                },
                child: Text(l.branchesQuarantineBannerOpen),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecoveryBanner(
    BuildContext context,
    WidgetRef ref,
    BranchSwitchRecoveryState recovery,
  ) {
    final l = AppLocalizations.of(context);
    final hint = recovery.lastError == null
        ? l.branchesRecoveryBody(recovery.toShopId)
        : l.branchesRecoveryBodyWithError(
            recovery.toShopId,
            _switchErrorMessage(l, recovery.lastError),
          );
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: colors.warningSurface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space3,
          AppTheme.space3,
          AppTheme.space3,
          AppTheme.space2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.restore_outlined, color: colors.warning),
                const SizedBox(width: AppTheme.space3),
                Expanded(
                  child: Text(
                    hint,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.warning,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.space2),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () async {
                    await ref
                        .read(branchRepositoryProvider)
                        .clearSwitchRecoveryState();
                  },
                  child: Text(l.branchesRecoveryDismiss),
                ),
                FilledButton(
                  onPressed: () => _retryPendingSync(context, ref, recovery),
                  child: Text(l.branchesRecoveryRetrySync),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<_BranchPreflightInfo> _runPreflight(WidgetRef ref) async {
    final transition = await ref
        .read(branchRepositoryProvider)
        .transitionPrecheck();
    bool online = true;
    try {
      final results = await Connectivity().checkConnectivity();
      online = results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      online = true;
    }
    final lastSyncedAt = ref.read(syncControllerProvider).lastSyncedAt;
    return _BranchPreflightInfo(
      pendingOutboxCount: transition.pendingOutboxCount,
      stuckOutboxCount: transition.stuckOutboxCount,
      online: online,
      lastSyncedAt: lastSyncedAt,
    );
  }

  String _formatLastSync(BuildContext context, DateTime? dt) {
    final l = AppLocalizations.of(context);
    if (dt == null) return l.syncNever;
    final local = dt.toLocal();
    final date = MaterialLocalizations.of(context).formatShortDate(local);
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(local));
    return '$date $time';
  }

  String _branchSwitchStepLabel(AppLocalizations l, _BranchSwitchUiStep step) {
    return switch (step) {
      _BranchSwitchUiStep.checkingDataSafety =>
        l.branchesSwitchStepCheckingDataSafety,
      _BranchSwitchUiStep.switchingAccountClaim =>
        l.branchesSwitchStepSwitchingAccountClaim,
      _BranchSwitchUiStep.refreshingSession =>
        l.branchesSwitchStepRefreshingSession,
      _BranchSwitchUiStep.clearingOldData =>
        l.branchesSwitchStepClearingOldData,
      _BranchSwitchUiStep.syncingNewData => l.branchesSwitchStepSyncingNewData,
    };
  }

  _BranchSwitchUiStep _mapRepoStep(BranchSwitchStep step) {
    return switch (step) {
      BranchSwitchStep.checkingDataSafety =>
        _BranchSwitchUiStep.checkingDataSafety,
      BranchSwitchStep.switchingAccountClaim =>
        _BranchSwitchUiStep.switchingAccountClaim,
      BranchSwitchStep.refreshingSession =>
        _BranchSwitchUiStep.refreshingSession,
      BranchSwitchStep.clearingOldData => _BranchSwitchUiStep.clearingOldData,
    };
  }

  String _switchErrorMessage(AppLocalizations l, String? code) {
    return switch (code) {
      'branch_switch_pending_sync' => l.branchesPendingSync,
      'stuck_outbox' => l.branchesSwitchBlockedStuckOutbox,
      'network_error' => l.branchesNetworkRetry,
      'auth_expired' => l.branchesAuthExpired,
      'invalid_branch_state' => l.branchesInvalidState,
      'not_linked' => l.branchesInvalidState,
      'forbidden' => l.branchesInvalidState,
      'post_switch_verify_failed' => l.branchesVerifyBody,
      _ => l.accountActionFailed,
    };
  }

  String _branchListErrorMessage(AppLocalizations l, Object error) {
    if (error is BranchListException) {
      return switch (error.code) {
        'auth_expired' => l.branchesAuthExpired,
        'network_error' => l.branchesNetworkRetry,
        'forbidden' || 'not_linked' => l.branchesInvalidState,
        _ => l.accountActionFailed,
      };
    }
    return l.accountActionFailed;
  }

  Future<_BranchSwitchAction?> _showPreflightDialog(
    BuildContext context,
    Branch b,
    _BranchPreflightInfo info,
  ) {
    final l = AppLocalizations.of(context);
    final branchLabel = b.label?.isNotEmpty == true ? b.label! : b.shopId;
    final canProceed = info.online && info.stuckOutboxCount == 0;
    final networkText = info.online
        ? l.branchesNetworkOnline
        : l.branchesNetworkOffline;
    final summaryStatus = !info.online
        ? l.branchesPreflightNeedOnline
        : (info.stuckOutboxCount > 0
              ? l.branchesSwitchBlockedStuckOutbox
              : l.branchesPreflightSummaryReady);
    return showModalBottomSheet<_BranchSwitchAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space4,
            0,
            AppTheme.space4,
            AppTheme.space4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.branchesPreflightTitle(branchLabel),
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: AppTheme.space2),
              Text(branchLabel, style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: AppTheme.space1),
              Text(l.branchesPreflightNetwork(networkText)),
              const SizedBox(height: AppTheme.space2),
              Text(
                summaryStatus,
                style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                  color: canProceed ? null : AppColors.of(ctx).danger,
                ),
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(l.branchesPreflightDetails),
                children: [
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.storefront_outlined),
                    title: Text(l.branchesPreflightTarget),
                    subtitle: Text(b.shopId),
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.sync_problem_outlined),
                    title: Text(
                      l.branchesPreflightPending(info.pendingOutboxCount),
                    ),
                  ),
                  if (info.stuckOutboxCount > 0)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.of(ctx).danger,
                      ),
                      title: Text(
                        l.branchesPreflightStuck(info.stuckOutboxCount),
                        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                          color: AppColors.of(ctx).danger,
                        ),
                      ),
                    ),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history_outlined),
                    title: Text(
                      l.branchesPreflightLastSync(
                        _formatLastSync(ctx, info.lastSyncedAt),
                      ),
                    ),
                  ),
                ],
              ),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                overflowSpacing: AppTheme.space2,
                spacing: AppTheme.space2,
                children: [
                  TextButton(
                    onPressed: () =>
                        Navigator.of(ctx).pop(_BranchSwitchAction.cancel),
                    child: Text(l.commonCancel),
                  ),
                  FilledButton(
                    onPressed: canProceed
                        ? () => Navigator.of(
                            ctx,
                          ).pop(_BranchSwitchAction.syncAndSwitch)
                        : null,
                    child: Text(l.branchesPreflightSyncAndSwitch),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSwitchProgressDialog(
    BuildContext context,
    ValueNotifier<_BranchSwitchUiStep> currentStep,
  ) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        final l = AppLocalizations.of(context);
        final orderedSteps = _BranchSwitchUiStep.values;
        return AlertDialog(
          title: Text(l.branchesSwitchInProgressTitle),
          content: ValueListenableBuilder<_BranchSwitchUiStep>(
            valueListenable: currentStep,
            builder: (context, activeStep, child) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < orderedSteps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.space2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (i < activeStep.index)
                          Icon(
                            Icons.check_circle,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        else if (i == activeStep.index)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            Icons.radio_button_unchecked,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        const SizedBox(width: AppTheme.space2),
                        Expanded(
                          child: Text(
                            _branchSwitchStepLabel(l, orderedSteps[i]),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _runPostSwitchVerification(
    BuildContext context,
    WidgetRef ref,
    String targetShopId,
  ) async {
    final l = AppLocalizations.of(context);
    final verify = await ref
        .read(branchRepositoryProvider)
        .verifyPostSwitch(targetShopId);
    if (verify.ok) return true;
    if (!context.mounted) return false;
    final action = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.branchesVerifyTitle),
        content: Text(l.branchesVerifyBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.branchesVerifyFinishBackground),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.branchesVerifyRetryNow),
          ),
        ],
      ),
    );
    if (action == true) {
      await ref.read(syncControllerProvider.notifier).sync(force: true);
      if (!context.mounted) return false;
      final second = await ref
          .read(branchRepositoryProvider)
          .verifyPostSwitch(targetShopId);
      return second.ok;
    }
    return false;
  }

  Future<void> _retryPendingSync(
    BuildContext context,
    WidgetRef ref,
    BranchSwitchRecoveryState recovery,
  ) async {
    final l = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(l.branchesRecoveryRetrySync),
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: AppTheme.space4),
            Expanded(child: Text(l.branchesSwitchStepSyncingNewData)),
          ],
        ),
      ),
    );
    await ref.read(syncControllerProvider.notifier).sync(force: true);
    if (!context.mounted) return;
    final ok = await _runPostSwitchVerification(
      context,
      ref,
      recovery.toShopId,
    );
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      if (ok) {
        await ref.read(branchRepositoryProvider).clearSwitchRecoveryState();
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.branchesRecoveryResolved)));
      } else {
        await ref
            .read(branchRepositoryProvider)
            .markSwitchNeedsSyncRetry(
              toShopId: recovery.toShopId,
              fromShopId: recovery.fromShopId,
              token: recovery.token,
              lastError: 'post_switch_verify_failed',
            );
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.branchesRecoveryStillPending)));
      }
    }
  }

  Future<void> _confirmSwitch(
    BuildContext context,
    WidgetRef ref,
    Branch b,
  ) async {
    if (_switchInFlight) return;
    setState(() => _switchInFlight = true);
    try {
      await _confirmSwitchBody(context, ref, b);
    } finally {
      if (mounted) setState(() => _switchInFlight = false);
    }
  }

  Future<void> _confirmSwitchBody(
    BuildContext context,
    WidgetRef ref,
    Branch b,
  ) async {
    final l = AppLocalizations.of(context);
    if (!await requireOwnerPinReauth(
      context,
      ref,
      capability: OwnerCapability.branches,
    )) {
      return;
    }
    if (!context.mounted) return;
    final stuck = ref.read(stuckOutboxProvider).valueOrNull ?? const [];
    if (stuck.isNotEmpty) {
      final openIssues = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.branchesSwitchBlockedTitle),
          content: Text(l.branchesSwitchBlockedStuckOutbox),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.branchesSwitchFixSyncIssues),
            ),
          ],
        ),
      );
      if (openIssues == true && context.mounted) {
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const SyncIssuesScreen()));
      }
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.branchesSwitchConfirmTitle),
        content: Text(
          l.branchesSwitchConfirmBody(
            b.label?.isNotEmpty == true ? b.label! : b.shopId,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.branchesSwitch),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final preflight = await _runPreflight(ref);
    if (!context.mounted) return;
    final action = await _showPreflightDialog(context, b, preflight);
    if (!context.mounted ||
        action == null ||
        action == _BranchSwitchAction.cancel) {
      return;
    }

    // Show progress BEFORE sync/switch awaits so the user never sees a blank
    // second after dismissing the preflight sheet (showDialog paints next frame).
    final currentStep = ValueNotifier<_BranchSwitchUiStep>(
      _BranchSwitchUiStep.checkingDataSafety,
    );
    _showSwitchProgressDialog(context, currentStep);
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) {
      currentStep.dispose();
      return;
    }

    try {
      final sync = ref.read(syncControllerProvider.notifier);
      sync.pauseBackgroundSync();
      try {
        if (action == _BranchSwitchAction.syncAndSwitch) {
          final drained = await sync.drainForSwitch();
          if (!context.mounted) return;
          final syncState = ref.read(syncControllerProvider);
          final refreshed = await _runPreflight(ref);
          if (!context.mounted) return;
          final pending = refreshed.pendingOutboxCount > 0
              ? refreshed.pendingOutboxCount
              : drained.pending;
          final stuck = refreshed.stuckOutboxCount > 0
              ? refreshed.stuckOutboxCount
              : drained.stuck;
          if (pending > 0 ||
              stuck > 0 ||
              !refreshed.online ||
              syncState.phase == SyncPhase.error) {
            Navigator.of(context, rootNavigator: true).pop();
            await showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(l.branchesSwitchInProgressTitle),
                content: Text(
                  syncState.phase == SyncPhase.error
                      ? l.syncError
                      : (!refreshed.online
                            ? l.branchesPreflightNeedOnline
                            : (pending > 0
                                  ? l.branchesSwitchUploadFailed(pending)
                                  : l.branchesPreflightStuck(stuck))),
                ),
                actions: [
                  if (pending > 0 || stuck > 0)
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SyncIssuesScreen(),
                          ),
                        );
                      },
                      child: Text(l.branchesStuckBannerReview),
                    ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(l.commonOk),
                  ),
                ],
              ),
            );
            return;
          }
        }

        final existingRecovery = await ref
            .read(branchRepositoryProvider)
            .switchRecoveryState();
        final recoveryToken = existingRecovery?.toShopId == b.shopId
            ? existingRecovery?.token
            : null;
        final result = await ref
            .read(branchRepositoryProvider)
            .switchBranch(
              b.shopId,
              onStep: (step) => currentStep.value = _mapRepoStep(step),
              idempotencyToken: recoveryToken,
            );
        if (!context.mounted) return;

        if (result.ok && result.license != null) {
          // onLicenseReady already applied; keep applyExternal for tests /
          // older call sites that skip the callback.
          ref
              .read(licenseControllerProvider.notifier)
              .applyExternal(result.license!);
          ref.invalidate(branchesProvider);
          currentStep.value = _BranchSwitchUiStep.syncingNewData;
          await sync.sync(force: true);
          if (!context.mounted) return;
          final verificationOk = await _runPostSwitchVerification(
            context,
            ref,
            b.shopId,
          );
          if (verificationOk) {
            await ref.read(branchRepositoryProvider).clearSwitchRecoveryState();
          } else {
            final fromShopId = existingRecovery?.fromShopId ?? '';
            await ref
                .read(branchRepositoryProvider)
                .markSwitchNeedsSyncRetry(
                  toShopId: b.shopId,
                  fromShopId: fromShopId,
                  token: recoveryToken ?? existingRecovery?.token,
                  lastError: 'post_switch_verify_failed',
                );
          }
          if (context.mounted) {
            Navigator.of(context, rootNavigator: true).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  verificationOk
                      ? l.branchesSwitched
                      : l.branchesRecoveryStillPending,
                ),
              ),
            );
          }
          return;
        }
        await ref
            .read(branchRepositoryProvider)
            .markSwitchNeedsSyncRetry(
              toShopId: b.shopId,
              fromShopId: existingRecovery?.fromShopId ?? '',
              token: recoveryToken,
              lastError: result.error,
            );
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_switchErrorMessage(l, result.error))),
          );
        }
      } finally {
        sync.resumeBackgroundSync();
      }
    } finally {
      currentStep.dispose();
    }
  }

  Future<void> _confirmUnlink(
    BuildContext context,
    WidgetRef ref,
    Branch b,
  ) async {
    final l = AppLocalizations.of(context);
    if (!await requireOwnerPinReauth(
      context,
      ref,
      capability: OwnerCapability.branches,
    )) {
      return;
    }
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.branchesUnlinkConfirmTitle),
        content: Text(
          l.branchesUnlinkConfirmBody(
            b.label?.isNotEmpty == true ? b.label! : b.shopId,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            style: AppTheme.dangerFilledButtonStyle(ctx),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.branchesUnlink),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final success = await ref
        .read(branchRepositoryProvider)
        .unlinkBranch(b.shopId);
    if (!context.mounted) return;
    if (success) {
      ref.invalidate(branchesProvider);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.accountActionFailed)));
    }
  }
}
