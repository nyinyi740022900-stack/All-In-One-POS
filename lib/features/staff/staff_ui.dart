import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'staff_providers.dart';

String staffRoleLabel(AppLocalizations l, String role) {
  return role == 'owner' ? l.staffRoleOwner : l.staffRoleStaff;
}

/// Wraps owner-only content. In staff mode it shows a lock placeholder
/// instead of [child].
class OwnerOnlyGate extends ConsumerWidget {
  const OwnerOnlyGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isEffectiveOwnerProvider)) return child;
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline,
                size: 56, color: Theme.of(context).colorScheme.outlineVariant),
            const SizedBox(height: 12),
            Text(l.staffOwnerOnly,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(l.staffOwnerOnlyDesc, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// A small pill for app bars showing that the device is in staff mode.
class StaffBadge extends ConsumerWidget {
  const StaffBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isEffectiveOwnerProvider)) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.badge_outlined, size: 14),
          const SizedBox(width: 4),
          Text(AppLocalizations.of(context).staffBadge,
              style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
