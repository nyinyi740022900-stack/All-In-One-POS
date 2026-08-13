import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
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
    if (ref.watch(licenseControllerProvider).loading ||
        !ref.watch(isPremiumProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l.staffAccountsTitle)),
        body: PremiumGate(
          featureName: l.staffAccountsTitle,
          child: const SizedBox.shrink(),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.staffAccountsTitle)),
      body: OwnerOnlyGate(
        capability: OwnerCapability.staffAccounts,
        child: _StaffAccountsBody(),
      ),
      floatingActionButton: OwnerOnlyGate(
        capability: OwnerCapability.staffAccounts,
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
    final credentials = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _StaffInviteDialog(),
    );
    if (credentials == null || !context.mounted) return;
    final (email, password) = credentials;
    final result = await ref
        .read(accountRepositoryProvider)
        .inviteStaff(email, password);
    if (!context.mounted) return;
    if (result.ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.accountLoginCreated)));
      ref.invalidate(staffAccountsProvider);
    } else {
      final msg = switch (result.error) {
        'email_taken' => l.accountEmailTaken,
        _ => l.accountActionFailed,
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

/// Owns its own [TextEditingController]s so `dispose()` runs on the dialog
/// route's real teardown rather than a `showDialog` `await` that resolves on
/// *pop* — see `_DeviceLabelDialog` in `settings_screen.dart` for the same
/// fix and the crash it avoids. This dialog previously left both controllers
/// undisposed for the whole app session (a leak, not a crash, since nothing
/// used them after the `await`) — owning them here fixes that too.
class _StaffInviteDialog extends StatefulWidget {
  const _StaffInviteDialog();

  @override
  State<_StaffInviteDialog> createState() => _StaffInviteDialogState();
}

class _StaffInviteDialogState extends State<_StaffInviteDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.staffAccountsInvite),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _email,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(labelText: l.accountEmail),
          ),
          const SizedBox(height: AppTheme.space2),
          TextField(
            controller: _password,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: l.accountPassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            final email = _email.text.trim();
            final password = _password.text;
            if (email.isEmpty || password.isEmpty) return;
            Navigator.pop(context, (email, password));
          },
          child: Text(l.staffAccountsInvite),
        ),
      ],
    );
  }
}

final staffAccountsProvider = FutureProvider.autoDispose<List<StaffAccount>>(
  (ref) => ref.watch(accountRepositoryProvider).listStaffAccounts(),
);

class _StaffAccountsBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final staffAsync = ref.watch(staffAccountsProvider);
    return staffAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Padding(
        padding: const EdgeInsets.all(AppTheme.space5),
        child: EmptyStateView(
          icon: Icons.error_outline,
          title: l.accountActionFailed,
        ),
      ),
      data: (staff) {
        if (staff.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AppTheme.space5),
            child: EmptyStateView(
              icon: Icons.people_outline,
              title: l.staffAccountsEmpty,
            ),
          );
        }
        return ListView.separated(
          itemCount: staff.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final s = staff[i];
            return ListTile(
              leading: IconAvatar(
                icon: s.banned ? Icons.person_off : Icons.person,
                tone: s.banned ? StatusTone.neutral : null,
              ),
              title: Text(s.email),
              subtitle: s.banned
                  ? Padding(
                      padding: const EdgeInsets.only(top: AppTheme.space1),
                      child: StatusPill(
                        label: l.staffAccountsRevoked,
                        tone: StatusTone.neutral,
                      ),
                    )
                  : Text(l.staffAccountsActive),
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
    BuildContext context,
    WidgetRef ref,
    StaffAccount s,
  ) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.staffAccountsRevokeConfirmTitle),
        content: Text(l.staffAccountsRevokeConfirmBody(s.email)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            style: AppTheme.dangerFilledButtonStyle(ctx),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.staffAccountsRevoke),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final success = await ref
        .read(accountRepositoryProvider)
        .revokeStaff(s.userId);
    if (!context.mounted) return;
    if (success) {
      ref.invalidate(staffAccountsProvider);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.accountActionFailed)));
    }
  }
}
