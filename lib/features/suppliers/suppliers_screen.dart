import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/phone_validator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import 'accounts_payable.dart';
import 'accounts_payable_providers.dart';
import 'supplier_providers.dart';

/// Supplier directory: browse/add/edit/delete the shop's saved suppliers —
/// used when creating a Purchase Order. See `SupplierRepository`.
class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Supplier s) async {
    final l = AppLocalizations.of(context);
    final currency = l.currencySymbol;
    final key = poSupplierKeyFor(s.id, s.name);
    final balance = ref
        .read(supplierBalancesProvider)
        .where((b) => b.key == key)
        .firstOrNull;
    final outstanding = balance?.outstanding ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.supplierDeleteConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.supplierDeleteConfirmBody(s.name)),
            if (outstanding > 0) ...[
              const SizedBox(height: AppTheme.space3),
              Text(
                l.supplierDeleteConfirmApWarning(
                    s.name, Money(outstanding).withSymbol(currency)),
                style: Theme.of(ctx)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.of(ctx).danger),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              style: AppTheme.dangerFilledButtonStyle(ctx),
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
    final draft = await showDialog<_SupplierDraft>(
      context: context,
      builder: (_) => _SupplierEditorDialog(existing: existing),
    );
    if (draft == null) return;
    await ref.read(supplierRepositoryProvider).upsertSupplier(
          id: existing?.id,
          name: draft.name,
          phone: draft.phone.isEmpty ? null : draft.phone,
          address: draft.address.isEmpty ? null : draft.address,
          note: draft.note.isEmpty ? null : draft.note,
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
              ? EmptyStateView(
                  icon: Icons.local_shipping_outlined,
                  title: l.suppliersEmpty,
                  actionLabel: l.supplierAdd,
                  onAction: () => _openEditor(context, ref),
                )
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
                      leading:
                          const IconAvatar(icon: Icons.local_shipping_outlined),
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

/// Result of [_SupplierEditorDialog] — plain strings (already trimmed) so the
/// caller never has to touch a disposed controller.
class _SupplierDraft {
  const _SupplierDraft({
    required this.name,
    required this.phone,
    required this.address,
    required this.note,
  });
  final String name;
  final String phone;
  final String address;
  final String note;
}

/// Owns its own four [TextEditingController]s so `dispose()` runs on the
/// dialog route's real teardown rather than a `showDialog` `await` that
/// resolves on *pop* — this was the exact "four controllers" instance of the
/// dispose-after-`await` crash flagged for this file (same pattern already
/// fixed in `checkout_sheet.dart`, `categories_screen.dart`,
/// `customers_screen.dart`, `payment_accounts_screen.dart`).
class _SupplierEditorDialog extends StatefulWidget {
  const _SupplierEditorDialog({this.existing});
  final Supplier? existing;

  @override
  State<_SupplierEditorDialog> createState() => _SupplierEditorDialogState();
}

class _SupplierEditorDialogState extends State<_SupplierEditorDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _phone =
      TextEditingController(text: widget.existing?.phone ?? '');
  late final _address =
      TextEditingController(text: widget.existing?.address ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');

  @override
  void initState() {
    super.initState();
    // Live-updates the phone format hint below.
    _phone.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final existing = widget.existing;
    return AlertDialog(
      title: Text(existing == null ? l.supplierAdd : l.supplierEdit),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: l.supplierNameLabel),
            ),
            const SizedBox(height: AppTheme.space2),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: l.customerPhone,
                helperText: looksLikeMyanmarPhone(_phone.text)
                    ? null
                    : l.phoneFormatHint,
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: AppTheme.space2),
            TextField(
              controller: _address,
              decoration: InputDecoration(labelText: l.customerAddress),
            ),
            const SizedBox(height: AppTheme.space2),
            TextField(
              controller: _note,
              decoration: InputDecoration(labelText: l.expenseNote),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              _SupplierDraft(
                name: name,
                phone: _phone.text.trim(),
                address: _address.text.trim(),
                note: _note.text.trim(),
              ),
            );
          },
          child: Text(l.commonSave),
        ),
      ],
    );
  }
}
