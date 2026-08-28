import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import '../accounts/payment_account_providers.dart';
import 'expense_repository.dart';
import 'expense_screen.dart' show categoryIcon, categoryLabel;
import 'recurring_expense_providers.dart';

/// Manage recurring-expense templates (rent, wages, etc.) — see
/// `RecurringExpenses` in tables.dart. Reached from the Expenses screen.
class RecurringExpensesScreen extends ConsumerWidget {
  const RecurringExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final templates =
        ref.watch(recurringExpenseTemplatesProvider).valueOrNull ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(l.recurringExpenseTitle)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openDialog(context),
        child: const Icon(Icons.add),
      ),
      body: templates.isEmpty
          ? EmptyStateView(
              icon: Icons.repeat,
              title: l.recurringExpenseEmpty,
            )
          : ListView.separated(
              itemCount: templates.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final t = templates[i];
                return ListTile(
                  leading: IconAvatar(icon: categoryIcon(t.category)),
                  title: Text(categoryLabel(l, t.category)),
                  subtitle: Text(
                    t.note == null || t.note!.isEmpty
                        ? Money(t.amount).withSymbol(l.currencySymbol)
                        : '${Money(t.amount).withSymbol(l.currencySymbol)} · ${t.note}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Switch(
                    value: t.active,
                    onChanged: (v) async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await ref
                            .read(recurringExpenseRepositoryProvider)
                            .setActive(t.id, v);
                      } catch (e) {
                        messenger.showSnackBar(SnackBar(
                            content: Text(l.commonUnexpectedError)));
                      }
                    },
                  ),
                  onTap: () => _openDialog(context, existing: t),
                );
              },
            ),
    );
  }

  Future<void> _openDialog(BuildContext context, {RecurringExpense? existing}) {
    return showDialog<void>(
      context: context,
      builder: (_) => _TemplateDialog(existing: existing),
    );
  }
}

class _TemplateDialog extends ConsumerStatefulWidget {
  const _TemplateDialog({this.existing});
  final RecurringExpense? existing;

  @override
  ConsumerState<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends ConsumerState<_TemplateDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late String _category;
  late bool _autoGenerate;
  late String _generationTiming;
  String? _accountId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _category = e?.category ?? expenseCategories.first;
    _autoGenerate = e?.autoGenerate ?? false;
    _generationTiming = e?.generationTiming ?? 'month_start';
    _accountId = e?.accountId;
    if (e != null) {
      _amount.text = '${e.amount}';
      _note.text = e.note ?? '';
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(recurringExpenseRepositoryProvider).upsertTemplate(
            id: widget.existing?.id,
            category: _category,
            amount: amount,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            active: widget.existing?.active ?? true,
            autoGenerate: _autoGenerate,
            generationTiming: _generationTiming,
            accountId: _accountId,
          );
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(l.recurringExpenseSaved)));
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text(l.commonUnexpectedError)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.recurringExpenseDeleteConfirmTitle),
        content: Text(l.recurringExpenseDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            style: AppTheme.dangerFilledButtonStyle(dialogContext),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(recurringExpenseRepositoryProvider)
          .deleteTemplate(widget.existing!.id);
      navigator.pop();
      messenger
          .showSnackBar(SnackBar(content: Text(l.recurringExpenseDeleted)));
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text(l.commonUnexpectedError)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.existing == null
          ? l.recurringExpenseAdd
          : l.recurringExpenseEdit),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _amount,
              autofocus: widget.existing == null,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: l.expenseAmount),
            ),
            const SizedBox(height: AppTheme.space3),
            Wrap(
              spacing: AppTheme.space2,
              runSpacing: AppTheme.space2,
              children: [
                for (final c in expenseCategories)
                  ChoiceChip(
                    label: Text(categoryLabel(l, c)),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.space3),
            Text(l.expensePaidFrom, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: AppTheme.space1),
            Wrap(
              spacing: AppTheme.space2,
              runSpacing: AppTheme.space2,
              children: [
                ChoiceChip(
                  label: Text(l.paymentCash),
                  selected: _accountId == null,
                  onSelected: (_) => setState(() => _accountId = null),
                ),
                for (final a in ref.watch(paymentAccountsProvider).valueOrNull ??
                    const [])
                  ChoiceChip(
                    label: Text(a.name),
                    selected: _accountId == a.id,
                    onSelected: (_) => setState(() => _accountId = a.id),
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.space3),
            TextField(
              controller: _note,
              decoration: InputDecoration(labelText: l.expenseNote),
            ),
            const SizedBox(height: AppTheme.space3),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.recurringExpenseAutoGenerate),
              subtitle: Text(l.recurringExpenseAutoGenerateHint),
              value: _autoGenerate,
              onChanged: (v) => setState(() => _autoGenerate = v),
            ),
            if (_autoGenerate) ...[
              const SizedBox(height: AppTheme.space2),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                      value: 'month_start',
                      label: Text(l.recurringExpenseTimingStart)),
                  ButtonSegment(
                      value: 'month_end',
                      label: Text(l.recurringExpenseTimingEnd)),
                ],
                selected: {_generationTiming},
                onSelectionChanged: (s) =>
                    setState(() => _generationTiming = s.first),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            onPressed: _saving ? null : _delete,
            child: Text(l.commonDelete,
                style: TextStyle(color: AppColors.of(context).danger)),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(l.commonSave),
        ),
      ],
    );
  }
}
