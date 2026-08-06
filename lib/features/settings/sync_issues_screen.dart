import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../data/local/database.dart';
import '../../data/sync/sync_providers.dart';
import '../../l10n/app_localizations.dart';
import '../staff/staff_ui.dart';
import '../staff/staff_providers.dart';

/// Lists outbox rows that have failed to push [kOutboxStuckThreshold]+ times
/// — a "poison pill" that would otherwise retry forever, invisibly, behind
/// an accurate-looking "Up to date" sync status (see `SyncEngine._push`'s
/// per-row error isolation, and `stuckOutboxProvider`'s doc comment).
/// Owner-only: discarding a row is real, unrecoverable local data loss for
/// whatever that one write was.
class SyncIssuesScreen extends ConsumerWidget {
  const SyncIssuesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final stuck = ref.watch(stuckOutboxProvider).valueOrNull ?? const [];
    final isOwner = ref.watch(isEffectiveOwnerProvider);
    final df = DateFormat('yyyy-MM-dd HH:mm');

    return Scaffold(
      appBar: AppBar(title: Text(l.syncIssuesTitle(stuck.length))),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.space4),
        children: [
          if (stuck.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.space6),
              child: Center(child: Text(l.syncIssuesEmpty)),
            )
          else ...[
            for (final row in stuck) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.space4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row.entityTable} · ${row.op}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppTheme.space1),
                      Text(l.syncIssuesAttempts(row.attempts)),
                      Text(df.format(row.enqueuedAt)),
                      if (row.lastError != null) ...[
                        const SizedBox(height: AppTheme.space2),
                        Text(
                          row.lastError!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: AppTheme.space3),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: isOwner
                              ? () => _confirmDiscard(context, ref, row)
                              : null,
                          icon: const Icon(Icons.delete_outline),
                          label: Text(l.syncIssuesDiscard),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.space3),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDiscard(
    BuildContext context,
    WidgetRef ref,
    OutboxData row,
  ) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.syncIssuesDiscardConfirmTitle),
        content: Text(l.syncIssuesDiscardConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;
    if (!await requireOwnerPinReauth(
      context,
      ref,
      capability: OwnerCapability.syncIssuesDiscard,
    )) {
      return;
    }
    await ref.read(syncControllerProvider.notifier).discardOutboxRow(row.seq);
  }
}
