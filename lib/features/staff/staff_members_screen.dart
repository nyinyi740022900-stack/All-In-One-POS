import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import 'staff_providers.dart';

/// Owner-only CRUD for the shop's named staff roster (see StaffMembers).
class StaffMembersScreen extends ConsumerWidget {
  const StaffMembersScreen({super.key});

  Future<void> _confirmRemove(
      BuildContext context, WidgetRef ref, StaffMember m) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.staffRemoveConfirmTitle),
        content: Text(l.staffRemoveConfirmBody(m.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              style: AppTheme.dangerFilledButtonStyle(ctx),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.staffRemoveMember)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(staffRepositoryProvider).deactivateMember(m.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.staffMemberRemoved)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.commonUnexpectedError)),
        );
      }
    }
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref,
      [StaffMember? existing]) async {
    final l = AppLocalizations.of(context);
    final draft = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _StaffMemberDialog(existing: existing),
    );
    if (draft == null) return;
    final (name, pin) = draft;
    try {
      await ref.read(staffRepositoryProvider).upsertMember(
            id: existing?.id,
            name: name,
            pin: pin.isEmpty ? null : pin,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.staffMemberSaved)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.commonUnexpectedError)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final members = ref.watch(staffMembersProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.staffMembersTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add),
        label: Text(l.staffAddMember),
      ),
      body: members.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(AppTheme.space5),
          child: EmptyStateView(
            icon: Icons.error_outline,
            title: l.commonUnexpectedError,
            actionLabel: l.commonRetry,
            onAction: () => ref.invalidate(staffMembersProvider),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(AppTheme.space5),
              child: EmptyStateView(
                icon: Icons.badge_outlined,
                title: l.staffMembersEmpty,
              ),
            );
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = list[i];
              return ListTile(
                leading: const IconAvatar(icon: Icons.badge_outlined),
                title: Text(m.name),
                onTap: () => _openEditor(context, ref, m),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l.staffRemoveMember,
                  onPressed: () => _confirmRemove(context, ref, m),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Owns its own [TextEditingController]s so `dispose()` runs on the dialog
/// route's real teardown rather than a `showDialog` `await` that resolves on
/// *pop* (before the exit animation finishes) — the previous inline version
/// disposed both controllers right after that `await`, which is the same
/// "TextEditingController used after being disposed" crash pattern fixed
/// repeatedly elsewhere this session (`checkout_sheet.dart`,
/// `categories_screen.dart`, `customers_screen.dart`,
/// `payment_accounts_screen.dart`).
class _StaffMemberDialog extends StatefulWidget {
  const _StaffMemberDialog({this.existing});
  final StaffMember? existing;

  @override
  State<_StaffMemberDialog> createState() => _StaffMemberDialogState();
}

class _StaffMemberDialogState extends State<_StaffMemberDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  // Never pre-filled with the existing PIN — it's stored hashed now, not in a
  // form that could be redisplayed. Blank means "keep the current PIN" when
  // editing (see the hint text below); required when adding.
  final _pin = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final existing = widget.existing;
    return AlertDialog(
      title: Text(existing == null ? l.staffAddMember : l.staffEditMember),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l.staffMemberName),
          ),
          const SizedBox(height: AppTheme.space2),
          TextField(
            controller: _pin,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: InputDecoration(
              labelText: l.staffMemberPin,
              hintText: existing == null ? null : l.staffMemberPinKeepHint,
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
            final name = _name.text.trim();
            final pin = _pin.text.trim();
            // Adding a member always needs a PIN; editing may leave it blank
            // to keep the current one.
            if (name.isEmpty || (existing == null && pin.isEmpty)) return;
            Navigator.pop(context, (name, pin));
          },
          child: Text(l.commonSave),
        ),
      ],
    );
  }
}
