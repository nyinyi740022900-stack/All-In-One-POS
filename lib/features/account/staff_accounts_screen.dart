import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
import '../license/premium_gate.dart';
import '../staff/staff_ui.dart';
import 'account_providers.dart';
import 'account_repository.dart';

/// Owner-only view of invited real staff accounts (email/password login),
/// additive to the device-local PIN roster in [StaffMembersScreen] — that
/// screen and this one coexist as separate options in Settings.
class StaffAccountsScreen extends ConsumerWidget {
  const StaffAccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    if (!ref.watch(isPremiumProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l.staffAccountsTitle)),
        body: PremiumGate(featureName: l.staffAccountsTitle, child: const SizedBox.shrink()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.staffAccountsTitle)),
      body: OwnerOnlyGate(child: _StaffAccountsBody()),
      floatingActionButton: OwnerOnlyGate(
        child: Builder(
          builder: (context) => FloatingActionButton.extended(
            onPressed: () => _invite(context, ref),
            icon: const Icon(Icons.person_add),
            label: Text(l.staffAccountsInvite),
          ),
        ),
      ),
    );
  }

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final email = TextEditingController();
    final password = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.staffAccountsInvite),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: l.accountEmail),
            ),
            const SizedBox(height: AppTheme.space2),
            TextField(
              controller: password,
              obscureText: true,
              decoration: InputDecoration(labelText: l.accountPassword),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.staffAccountsInvite)),
        ],
      ),
    );
    if (submitted != true || !context.mounted) return;
    if (email.text.trim().isEmpty || password.text.isEmpty) return;
    final result = await ref
        .read(accountRepositoryProvider)
        .inviteStaff(email.text.trim(), password.text);
    if (!context.mounted) return;
    if (result.ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.accountLoginCreated)));
      ref.invalidate(staffAccountsProvider);
    } else {
      final msg = switch (result.error) {
        'email_taken' => l.accountEmailTaken,
        _ => l.accountActionFailed,
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

final staffAccountsProvider = FutureProvider.autoDispose<List<StaffAccount>>(
    (ref) => ref.watch(accountRepositoryProvider).listStaffAccounts());

class _StaffAccountsBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final staffAsync = ref.watch(staffAccountsProvider);
    return staffAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(child: Text(l.accountActionFailed)),
      data: (staff) {
        if (staff.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.space5),
              child: Text(l.staffAccountsEmpty, textAlign: TextAlign.center),
            ),
          );
        }
        return ListView.separated(
          itemCount: staff.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final s = staff[i];
            return ListTile(
              leading: Icon(s.banned ? Icons.person_off : Icons.person),
              title: Text(s.email),
              subtitle: Text(s.banned
                  ? l.staffAccountsRevoked
                  : l.staffAccountsActive),
              trailing: s.banned
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => _confirmRevoke(context, ref, s),
                    ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmRevoke(
      BuildContext context, WidgetRef ref, StaffAccount s) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.staffAccountsRevokeConfirmTitle),
        content: Text(l.staffAccountsRevokeConfirmBody(s.email)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.staffAccountsRevoke)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final success = await ref.read(accountRepositoryProvider).revokeStaff(s.userId);
    if (!context.mounted) return;
    if (success) {
      ref.invalidate(staffAccountsProvider);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.accountActionFailed)));
    }
  }
}
