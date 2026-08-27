import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/sync/outbox_error.dart';
import '../../data/sync/sync_providers.dart';
import '../../l10n/app_localizations.dart';

/// Shows held uploads that background sync / force-apply is finishing.
/// Owners never Discard and never need Support for sync convergence.
class SyncIssuesScreen extends ConsumerWidget {
  const SyncIssuesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final quarantined =
        ref.watch(quarantinedOutboxProvider).valueOrNull ?? const [];
    final pending =
        ref.watch(pendingOutboxRowsProvider).valueOrNull ?? const [];
    final df = DateFormat('yyyy-MM-dd HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: Text(l.syncIssuesTitle(quarantined.length + pending.length)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.space4),
        children: [
          Text(
            l.syncIssuesBackgroundHint,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppTheme.space3),
          FilledButton.icon(
            onPressed: () =>
                ref.read(syncControllerProvider.notifier).sync(force: true),
            icon: const Icon(Icons.sync),
            label: Text(l.syncNow),
          ),
          if (pending.isNotEmpty) ...[
            const SizedBox(height: AppTheme.space3),
            Text(
              l.syncIssuesPendingHint(pending.length),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: AppTheme.space4),
          if (quarantined.isEmpty && pending.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.space4),
              child: EmptyStateView(
                icon: Icons.cloud_done_outlined,
                title: l.syncIssuesEmpty,
              ),
            )
          else
            for (final row in quarantined) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.space4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const IconAvatar(
                        icon: Icons.error_outline,
                        tone: StatusTone.critical,
                      ),
                      const SizedBox(width: AppTheme.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.syncIssuesQuarantinedRow(row.entityTable),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: AppTheme.space1),
                            Text(
                              df.format(row.enqueuedAt),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: AppTheme.space2),
                            StatusPill(
                              label: l.syncIssuesQuarantinedHeld,
                              tone: StatusTone.critical,
                            ),
                            // A generic "held" pill doesn't tell an owner
                            // whether this needs support or will resolve on
                            // its own — an invoice-number collision (two
                            // devices offline at once, see migration 0074)
                            // is the one case that genuinely needs the
                            // owner to act, so it gets its own explanation.
                            if (isInvoiceNoCollisionError(row.lastError)) ...[
                              const SizedBox(height: AppTheme.space2),
                              Text(
                                l.syncIssuesInvoiceCollision,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: AppColors.of(context).danger,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.space3),
            ],
        ],
      ),
    );
  }
}
