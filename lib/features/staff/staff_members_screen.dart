import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
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
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.staffRemoveMember)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(staffRepositoryProvider).deactivateMember(m.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.staffMemberRemoved)));
    }
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref,
      [StaffMember? existing]) async {
    final l = AppLocalizations.of(context);
    final name = TextEditingController(text: existing?.name ?? '');
    // Never pre-filled with the existing PIN — it's stored hashed now, not
    // in a form that could be redisplayed. Blank means "keep the current
    // PIN" when editing (see the hint text below); required when adding.
    final pin = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? l.staffAddMember : l.staffEditMember),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: l.staffMemberName),
            ),
            const SizedBox(height: AppTheme.space2),
            TextField(
              controller: pin,
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
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.commonSave)),
        ],
      ),
    );
    // Adding a member always needs a PIN; editing may leave it blank to keep
    // the current one.
    final shouldSave = saved == true &&
        name.text.trim().isNotEmpty &&
        !(existing == null && pin.text.trim().isEmpty);
    if (shouldSave) {
      await ref.read(staffRepositoryProvider).upsertMember(
            id: existing?.id,
            name: name.text.trim(),
            pin: pin.text.trim().isEmpty ? null : pin.text.trim(),
          );
    }
    name.dispose();
    pin.dispose();
    if (shouldSave && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.staffMemberSaved)));
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
        error: (e, _) => Center(child: Text(l.commonUnexpectedError)),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.space5),
                child: Text(l.staffMembersEmpty, textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = list[i];
              return ListTile(
                leading: const Icon(Icons.badge_outlined),
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
