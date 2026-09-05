import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import 'notification_center_providers.dart';
import 'notification_center_repository.dart';

/// The list behind the bell in the Sell app bar.
///
/// Opening it marks everything read — the badge is "there is something you
/// have not seen", and by this point you are looking at it. A per-row read
/// toggle would be busywork for a list nobody curates.
class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends ConsumerState<NotificationCenterScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame: this writes to the DB, which rebuilds the
    // provider the opening screen is already building against.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final shopId = ref.read(shopIdProvider);
      await ref.read(notificationCenterRepositoryProvider).markAllRead(shopId);
    });
  }

  String _stamp(BuildContext context, DateTime dt) {
    final local = dt.toLocal();
    final date = MaterialLocalizations.of(context).formatShortDate(local);
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(local));
    return '$date $time';
  }

  IconData _icon(String kind) => switch (kind) {
    NotificationKinds.storefrontOrder => Icons.shopping_bag_outlined,
    NotificationKinds.licenseExpiry => Icons.workspace_premium_outlined,
    _ => Icons.notifications_none,
  };

  Future<void> _clear(AppLocalizations l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.notificationsClearConfirmTitle),
        content: Text(l.notificationsClearConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            style: AppTheme.dangerFilledButtonStyle(ctx),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.notificationsClear),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref
        .read(notificationCenterRepositoryProvider)
        .clear(ref.read(shopIdProvider));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final items = ref.watch(notificationCenterProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.notificationsTitle),
        actions: [
          if (items.valueOrNull?.isNotEmpty ?? false)
            IconButton(
              tooltip: l.notificationsClear,
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _clear(l),
            ),
        ],
      ),
      body: items.when(
        loading: () => const AppLoadingView(),
        error: (_, _) => EmptyStateView(
          icon: Icons.notifications_off_outlined,
          title: l.commonUnexpectedError,
        ),
        data: (rows) {
          // A row whose `kind` this build does not know renders as null —
          // drop it rather than showing a blank tile.
          final visible = <({AppNotification row, NotificationText text})>[];
          for (final r in rows) {
            final t = notificationText(l, r);
            if (t != null) visible.add((row: r, text: t));
          }
          if (visible.isEmpty) {
            return EmptyStateView(
              icon: Icons.notifications_none,
              title: l.notificationsEmpty,
              message: l.notificationsEmptyHint,
            );
          }
          return ContentWidth(
            maxWidth: 560,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.space2),
              itemCount: visible.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final it = visible[i];
                return ListTile(
                  leading: IconAvatar(icon: _icon(it.row.kind)),
                  title: Text(it.text.title),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it.text.body),
                      const SizedBox(height: AppTheme.space1),
                      Text(
                        _stamp(context, it.row.createdAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// The bell for an app bar: badge when something is unread, plain when not.
///
/// Placed rightmost in Sell's actions — Sell is the tab the app opens on and
/// the one an owner sits on all day, which is where every other app people
/// here use (Facebook, Viber, Messenger) puts its bell.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    // A failed or still-loading count is shown as no badge rather than as an
    // error: the bell must never be the thing that breaks the Sell screen.
    final unread = ref.watch(notificationUnreadCountProvider).valueOrNull ?? 0;

    final button = IconButton(
      tooltip: l.notificationsTitle,
      icon: const Icon(Icons.notifications_none),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NotificationCenterScreen()),
      ),
    );

    if (unread == 0) return button;
    return Badge.count(count: unread, child: button);
  }
}
