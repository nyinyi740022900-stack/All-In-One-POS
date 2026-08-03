import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import 'supplier_providers.dart';

/// Supplier directory: browse/add/edit/delete the shop's saved suppliers —
/// used when creating a Purchase Order. See `SupplierRepository`.
class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Supplier s) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.supplierDeleteConfirmTitle),
        content: Text(l.supplierDeleteConfirmBody(s.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.commonDelete)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(supplierRepositoryProvider).deleteSupplier(s.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.supplierDeleted)));
    }
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref,
      [Supplier? existing]) async {
    final l = AppLocalizations.of(context);
    final name = TextEditingController(text: existing?.name ?? '');
    final phone = TextEditingController(text: existing?.phone ?? '');
    final address = TextEditingController(text: existing?.address ?? '');
    final note = TextEditingController(text: existing?.note ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? l.supplierAdd : l.supplierEdit),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: l.supplierNameLabel),
              ),
              const SizedBox(height: AppTheme.space2),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: l.customerPhone),
              ),
              const SizedBox(height: AppTheme.space2),
              TextField(
                controller: address,
                decoration: InputDecoration(labelText: l.customerAddress),
              ),
              const SizedBox(height: AppTheme.space2),
              TextField(
                controller: note,
                decoration: InputDecoration(labelText: l.expenseNote),
              ),
            ],
          ),
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
    if (saved != true || name.text.trim().isEmpty) return;

    await ref.read(supplierRepositoryProvider).upsertSupplier(
          id: existing?.id,
          name: name.text.trim(),
          phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
          address: address.text.trim().isEmpty ? null : address.text.trim(),
          note: note.text.trim().isEmpty ? null : note.text.trim(),
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.supplierSaved)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final suppliers = ref.watch(suppliersProvider).valueOrNull ?? const [];
    final loading = ref.watch(suppliersProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: Text(l.suppliersTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add),
        label: Text(l.supplierAdd),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : suppliers.isEmpty
              ? Center(child: Text(l.suppliersEmpty))
              : ListView.separated(
                  itemCount: suppliers.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final s = suppliers[i];
                    final subtitleParts = [
                      if ((s.phone ?? '').isNotEmpty) s.phone!,
                      if ((s.address ?? '').isNotEmpty) s.address!,
                    ];
                    return ListTile(
                      leading: const CircleAvatar(
                          child: Icon(Icons.local_shipping_outlined)),
                      title: Text(s.name),
                      subtitle: subtitleParts.isEmpty
                          ? null
                          : Text(subtitleParts.join(' · '),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(context, ref, s),
                      ),
                      onTap: () => _openEditor(context, ref, s),
                    );
                  },
                ),
    );
  }
}
