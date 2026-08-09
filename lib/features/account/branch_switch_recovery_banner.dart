import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/sync/sync_providers.dart';
import '../../l10n/app_localizations.dart';
import 'branch_providers.dart';
import 'branch_repository.dart';

/// Maps a branch-switch/list error code to its localized message. Shared by
/// the recovery banner and the switch confirmation flow.
String switchErrorMessage(AppLocalizations l, String? code) {
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

/// Verifies the device actually landed on [targetShopId] after a switch.
/// On failure, offers to retry sync-and-verify once more before giving up.
Future<bool> runPostSwitchVerification(
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
    await ref.read(syncControllerProvider.notifier).syncUntilDrained();
    final second = await ref
        .read(branchRepositoryProvider)
        .verifyPostSwitch(targetShopId);
    return second.ok;
  }
  return false;
}

/// Retries sync + post-switch verification for an interrupted branch
/// switch, then clears the recovery record on success or re-marks it
/// (with the fresh error) on failure. Shared by the manual "Retry sync"
/// banner action and the background startup/connectivity watcher.
Future<void> retryPendingSync(
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
  await ref.read(syncControllerProvider.notifier).syncUntilDrained();
  if (!context.mounted) return;
  final ok = await runPostSwitchVerification(
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

/// App-shell-wide banner for an interrupted branch switch — mounted once in
/// [_ShellScaffold] (core/router.dart) so it's visible on every tab, not
/// just when the owner happens to reopen Settings > Branches.
class BranchSwitchRecoveryBanner extends ConsumerWidget {
  const BranchSwitchRecoveryBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(branchSwitchRecoveryProvider).valueOrNull;
    if (recovery == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final hint = recovery.lastError == null
        ? l.branchesRecoveryBody(recovery.toShopId)
        : l.branchesRecoveryBodyWithError(
            recovery.toShopId,
            switchErrorMessage(l, recovery.lastError),
          );
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.restore_outlined,
                  color: scheme.onSecondaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hint,
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
                  onPressed: () => retryPendingSync(context, ref, recovery),
                  child: Text(l.branchesRecoveryRetrySync),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
