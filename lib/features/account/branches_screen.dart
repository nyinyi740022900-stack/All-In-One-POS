import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/sync/sync_providers.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
import '../license/premium_gate.dart';
import '../staff/staff_ui.dart';
import 'branch_providers.dart';
import 'branch_repository.dart';

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
    if (!ref.watch(isPremiumProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l.branchesTitle)),
        body: PremiumGate(featureName: l.branchesTitle, child: const SizedBox.shrink()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l.branchesTitle),
        actions: [
          OwnerOnlyGate(
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
      body: OwnerOnlyGate(child: _BranchesBody()),
      floatingActionButton: OwnerOnlyGate(
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
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.branchesCreate)),
        ],
      ),
    );
    final shopName = name.text.trim();
    name.dispose();
    if (submitted != true || !context.mounted) return;
    if (shopName.isEmpty) return;
    final result =
        await ref.read(branchRepositoryProvider).createBranch(shopName);
    if (!context.mounted) return;
    if (result.ok) {
      ref.invalidate(branchesProvider);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.branchesCreated)));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.accountActionFailed)));
    }
  }

  Future<void> _linkBranch(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final key = TextEditingController();
    final label = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.branchesLink),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.branchesLinkHint,
                style: Theme.of(ctx).textTheme.bodySmall),
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
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.branchesLink)),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.branchesLinked)));
    } else {
      final msg = switch (result.error) {
        'invalid_key' => l.branchesInvalidKey,
        _ => l.accountActionFailed,
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

class _BranchesBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final branchesAsync = ref.watch(branchesProvider);
    return branchesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(child: Text(l.accountActionFailed)),
      data: (branches) {
        if (branches.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.space5),
              child: Text(l.branchesEmpty, textAlign: TextAlign.center),
            ),
          );
        }
        return ListView.separated(
          itemCount: branches.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final b = branches[i];
            return ListTile(
              leading: Icon(
                  b.isCurrent ? Icons.storefront : Icons.storefront_outlined),
              title: Text(b.label?.isNotEmpty == true ? b.label! : b.shopId),
              subtitle: Text(b.shopId),
              trailing: b.isCurrent
                  ? Chip(label: Text(l.branchesCurrent))
                  : IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => _confirmUnlink(context, ref, b),
                    ),
              onTap: b.isCurrent ? null : () => _confirmSwitch(context, ref, b),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmSwitch(
      BuildContext context, WidgetRef ref, Branch b) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.branchesSwitchConfirmTitle),
        content: Text(
            l.branchesSwitchConfirmBody(b.label?.isNotEmpty == true ? b.label! : b.shopId)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.branchesSwitch)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final result = await ref.read(branchRepositoryProvider).switchBranch(b.shopId);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (result.ok && result.license != null) {
      ref.read(licenseControllerProvider.notifier).applyExternal(result.license!);
      ref.read(syncControllerProvider.notifier).sync();
      ref.invalidate(branchesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.branchesSwitched)));
      }
      return;
    }
    if (!context.mounted) return;
    final msg = result.error == 'branch_switch_pending_sync'
        ? l.branchesPendingSync
        : l.accountActionFailed;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _confirmUnlink(
      BuildContext context, WidgetRef ref, Branch b) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.branchesUnlinkConfirmTitle),
        content: Text(l.branchesUnlinkConfirmBody(
            b.label?.isNotEmpty == true ? b.label! : b.shopId)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.branchesUnlink)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final success = await ref.read(branchRepositoryProvider).unlinkBranch(b.shopId);
    if (!context.mounted) return;
    if (success) {
      ref.invalidate(branchesProvider);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.accountActionFailed)));
    }
  }
}
