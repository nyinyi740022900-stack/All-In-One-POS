import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../data/sync/sync_providers.dart';
import '../../l10n/app_localizations.dart';
import '../settings/sync_issues_screen.dart';
import '../license/license_providers.dart';
import '../license/premium_gate.dart';
import '../staff/staff_ui.dart';
import 'branch_providers.dart';
import 'branch_repository.dart';
import 'branch_switch_recovery_banner.dart';

/// Lets a real-login owner list, create, link, unlink, and switch between
/// branches (each its own shop_id/license) they own. Owner-only — see
/// OwnerOnlyGate. Creating a branch (just a name, no key) is the primary
/// path — this is a cloud account, so a new branch should be as easy as
/// naming it; linking an already-existing separate shop by its key stays
/// available as a secondary, less prominent action.
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
          child: const SizedBox.shrink(),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l.branchesTitle),
        actions: [
          OwnerOnlyGate(
            capability: OwnerCapability.branches,
            child: Builder(
              builder: (context) => IconButton(
                tooltip: l.branchesLink,
                icon: const Icon(Icons.key_outlined),
                onPressed: () => _linkBranch(context, ref),
              ),
            ),
          ),
        ],
      ),
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
    final name = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.branchesCreate),
        content: TextField(
          controller: name,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: l.shopName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.branchesCreate),
          ),
        ],
      ),
    );
    final shopName = name.text.trim();
    name.dispose();
    if (submitted != true || !context.mounted) return;
    if (shopName.isEmpty) return;
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

  Future<void> _linkBranch(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    if (!await requireOwnerPinReauth(
      context,
      ref,
      capability: OwnerCapability.branches,
    )) {
      return;
    }
    if (!context.mounted) return;
    final key = TextEditingController();
    final label = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.branchesLink),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.branchesLinkHint, style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: AppTheme.space2),
            TextField(
              controller: key,
              decoration: InputDecoration(labelText: l.branchesKeyLabel),
            ),
            const SizedBox(height: AppTheme.space2),
            TextField(
              controller: label,
              decoration: InputDecoration(labelText: l.branchesLabelField),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.branchesLink),
          ),
        ],
      ),
    );
    final keyText = key.text.trim();
    final labelText = label.text.trim();
    key.dispose();
    label.dispose();
    if (submitted != true || !context.mounted) return;
    if (keyText.isEmpty) return;
    final result = await ref
        .read(branchRepositoryProvider)
        .linkBranch(keyText, labelText);
    if (!context.mounted) return;
    if (result.ok) {
      ref.invalidate(branchesProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.branchesLinked)));
    } else {
      final msg = switch (result.error) {
        'invalid_key' => l.branchesInvalidKey,
        _ => l.accountActionFailed,
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
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
        borderRadius: BorderRadius.circular(AppTheme.radius),
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
  });

  final Branch branch;
  final int pendingOutboxCount;
  final String lastSyncedText;
  final Widget healthChip;
  final Widget trailing;

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
                Icon(
                  branch.isCurrent
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
                      const SizedBox(height: 2),
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
            Text(
              l.branchesRowPending(pendingOutboxCount),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 2),
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
            const SizedBox(height: 2),
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
            const SizedBox(height: 2),
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
  bool _triedProactiveSync = false;

  /// Pre-drains the outbox as soon as the owner opens the Branches list,
  /// rather than waiting for them to tap Switch — so by the time they pick a
  /// branch, the preflight check is more likely to already read "ready".
  /// Opportunistic and silent: a single pass, no dialog, no retry — the
  /// gated preflight before an actual switch still re-checks and drains
  /// properly via `syncUntilDrained`. Takes the already-watched pending
  /// count/online state from [build] instead of re-querying the repository,
  /// so this stays test-overridable via the same providers the rest of the
  /// screen reads.
  void _maybeStartProactiveSync(int pendingOutbox, bool online) {
    if (_triedProactiveSync || pendingOutbox == 0 || !online) return;
    _triedProactiveSync = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(syncControllerProvider.notifier).sync());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final branchesAsync = ref.watch(branchesProvider);
    final pendingOutbox =
        ref.watch(pendingOutboxCountProvider).valueOrNull ?? 0;
    final stuckOutbox = ref.watch(stuckOutboxProvider).valueOrNull ?? const [];
    final online = ref.watch(branchConnectivityProvider).valueOrNull ?? true;
    final syncState = ref.watch(syncControllerProvider);
    _maybeStartProactiveSync(pendingOutbox, online);
    return branchesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _branchListErrorMessage(l, error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.space2),
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
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.space5),
              child: Text(l.branchesEmpty, textAlign: TextAlign.center),
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
                          pendingOutbox,
                        ),
                        trailing: Wrap(
                          spacing: AppTheme.space2,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _confirmSwitch(context, ref, b),
                              icon: const Icon(Icons.swap_horiz, size: 18),
                              label: Text(l.branchesSwitch),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () => _confirmUnlink(context, ref, b),
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

  Widget _buildHealthChip(
    BuildContext context,
    bool online,
    int pendingOutbox,
  ) {
    final l = AppLocalizations.of(context);
    final safe = online && pendingOutbox == 0;
    return Chip(
      avatar: Icon(
        safe ? Icons.verified_outlined : Icons.sync_problem_outlined,
        size: 16,
      ),
      label: Text(
        safe ? l.branchesHealthSafeSwitch : l.branchesHealthSyncNeeded,
      ),
    );
  }

  Widget _buildStuckBanner(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // Do not use MaterialBanner as a Column child — its intrinsic layout
    // collapses content width to ~0 and wraps one character per line.
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: scheme.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.branchesStuckBannerTitle,
                        style: TextStyle(
                          color: scheme.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l.branchesStuckBannerBody,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await ref.read(syncControllerProvider.notifier).sync();
                  if (!context.mounted) return;
                  final stuck = ref.read(stuckOutboxProvider).valueOrNull ??
                      const [];
                  messenger.showSnackBar(SnackBar(
                    content: Text(
                      stuck.isEmpty
                          ? l.syncIdle
                          : l.branchesStuckBannerBody,
                    ),
                  ));
                },
                child: Text(l.branchesStuckBannerSyncNow),
              ),
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
                style: TextStyle(
                  color: canProceed ? null : Theme.of(ctx).colorScheme.error,
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
                        color: Theme.of(ctx).colorScheme.error,
                      ),
                      title: Text(
                        l.branchesPreflightStuck(info.stuckOutboxCount),
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
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
                          child:
                              (orderedSteps[i] ==
                                      _BranchSwitchUiStep.syncingNewData &&
                                  i == activeStep.index)
                              ? Consumer(
                                  builder: (context, ref, _) {
                                    final pending =
                                        ref
                                            .watch(pendingOutboxCountProvider)
                                            .valueOrNull ??
                                        0;
                                    return Text(
                                      pending > 0
                                          ? l.branchesSyncingRemaining(pending)
                                          : _branchSwitchStepLabel(
                                              l,
                                              orderedSteps[i],
                                            ),
                                    );
                                  },
                                )
                              : Text(
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

  Future<void> _confirmSwitch(
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
    if (action == _BranchSwitchAction.syncAndSwitch) {
      await ref.read(syncControllerProvider.notifier).syncUntilDrained();
      if (!context.mounted) return;
      final syncState = ref.read(syncControllerProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            syncState.phase == SyncPhase.error ? l.syncError : l.syncIdle,
          ),
        ),
      );
      final refreshed = await _runPreflight(ref);
      if (!context.mounted) return;
      // syncUntilDrained's retries can themselves push a genuinely-failing
      // row's attempts past kOutboxStuckThreshold — route straight to the
      // same "Fix Sync Issues" escape hatch the top-of-flow check offers,
      // instead of a dead-end "sync first" message the owner can never get
      // past by retrying Switch again.
      if (refreshed.stuckOutboxCount > 0) {
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
      if (refreshed.pendingOutboxCount > 0 || !refreshed.online) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l.branchesSwitchInProgressTitle),
            content: Text(
              refreshed.pendingOutboxCount > 0
                  ? l.branchesPreflightNeedSync
                  : l.branchesPreflightNeedOnline,
            ),
            actions: [
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

    final currentStep = ValueNotifier<_BranchSwitchUiStep>(
      _BranchSwitchUiStep.checkingDataSafety,
    );
    _showSwitchProgressDialog(context, currentStep);
    try {
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
        ref
            .read(licenseControllerProvider.notifier)
            .applyExternal(result.license!);
        ref.invalidate(branchesProvider);
        currentStep.value = _BranchSwitchUiStep.syncingNewData;
        await ref.read(syncControllerProvider.notifier).syncUntilDrained();
        if (!context.mounted) return;
        final verificationOk = await runPostSwitchVerification(
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
          SnackBar(content: Text(switchErrorMessage(l, result.error))),
        );
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
