import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import 'inventory_providers.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final categories = ref.watch(categoriesStreamProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.categoriesTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.add),
        label: Text(l.categoryAdd),
      ),
      body: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.commonUnexpectedError)),
        data: (list) {
          if (list.isEmpty) {
            return EmptyStateView(
              icon: Icons.label_outline,
              title: l.categoriesEmpty,
            );
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = list[i];
              return ListTile(
                leading: const Icon(Icons.label_outline),
                // Two lines: a Myanmar category name runs ~20-40% longer
                // than its English source and this is the row's only label,
                // so it must not be ellipsized away.
                title: Text(c.name, maxLines: 2),
                // The row itself renames — which is what tapping a settings
                // row means everywhere else in this app — so the edit pencil
                // is gone and delete is no longer one 8pt gap away from it.
                onTap: () => _edit(context, ref, c),
                trailing: IconButton(
                  tooltip: l.commonDelete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context, ref, c),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// The `TextEditingController` lives inside [_CategoryNameDialog], not
  /// here. `await showDialog(...)` completes the moment the route is
  /// *popped*, not when its exit animation finishes, so disposing a
  /// locally-owned controller on the next line tears it out from under a
  /// `TextField` that is still on screen — "A TextEditingController was used
  /// after being disposed", then a cascade of framework assertions and a red
  /// screen. **This was observed crashing live** on Inventory ➜ Categories ➜
  /// add; the identical bug was fixed the same way in `checkout_sheet.dart`'s
  /// `_LineDiscountDialog`.
  Future<void> _edit(BuildContext context, WidgetRef ref,
      [Category? existing]) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _CategoryNameDialog(existing: existing),
    );
    if (name != null && name.isNotEmpty) {
      try {
        await ref.read(inventoryRepositoryProvider).upsertCategory(
              id: existing?.id,
              name: name,
              sort: existing?.sort ?? 0,
            );
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text(AppLocalizations.of(context).commonUnexpectedError)));
        }
      }
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Category c) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteConfirmTitle),
        content: Text('${c.name}\n\n${l.categoryDeleteConfirmBody}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            style: AppTheme.dangerFilledButtonStyle(ctx),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.commonDelete),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ref.read(inventoryRepositoryProvider).deleteCategory(c.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.commonUnexpectedError)));
        }
      }
    }
  }
}

/// Add/rename dialog. A `StatefulWidget` purely so its controller is owned by
/// something whose `dispose` runs when the route is actually gone — see
/// [CategoriesScreen._edit].
class _CategoryNameDialog extends StatefulWidget {
  const _CategoryNameDialog({this.existing});

  final Category? existing;

  @override
  State<_CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<_CategoryNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.existing?.name ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.existing == null ? l.categoryAdd : l.categoryEdit),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(labelText: l.categoryName),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l.commonSave)),
      ],
    );
  }
}
