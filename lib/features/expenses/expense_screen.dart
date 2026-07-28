import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/image_util.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import 'expense_providers.dart';
import 'expense_repository.dart';

IconData _categoryIcon(String category) {
  switch (category) {
    case 'rent':
      return Icons.store_outlined;
    case 'utilities':
      return Icons.bolt_outlined;
    case 'wages':
      return Icons.badge_outlined;
    case 'transport':
      return Icons.local_shipping_outlined;
    case 'packaging':
      return Icons.inventory_2_outlined;
    case 'other':
    default:
      return Icons.receipt_long_outlined;
  }
}

String categoryLabel(AppLocalizations l, String category) {
  switch (category) {
    case 'rent':
      return l.expenseCategoryRent;
    case 'utilities':
      return l.expenseCategoryUtilities;
    case 'wages':
      return l.expenseCategoryWages;
    case 'transport':
      return l.expenseCategoryTransport;
    case 'packaging':
      return l.expenseCategoryPackaging;
    case 'other':
    default:
      return l.expenseCategoryOther;
  }
}

/// The shop's non-inventory operating expenses (rent, utilities, wages,
/// transport, packaging). Reached from the Analytics dashboard's "Total
/// expenses" card, since that's where the owner thinks about profit.
class ExpenseScreen extends ConsumerWidget {
  const ExpenseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final cur = l.currencySymbol;
    final expenses =
        ref.watch(expensesInRangeProvider).valueOrNull ?? const <Expense>[];
    final total = ref.watch(expensesTotalProvider);
    final df = DateFormat('yyyy-MM-dd');

    return Scaffold(
      appBar: AppBar(title: Text(l.expensesTitle)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openDialog(context),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(AppTheme.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.expensesTotal,
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(Money(total).withSymbol(cur),
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: expenses.isEmpty
                ? Center(child: Text(l.expensesEmpty))
                : ListView.separated(
                    itemCount: expenses.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final e = expenses[i];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Icon(_categoryIcon(e.category)),
                        ),
                        title: Text(categoryLabel(l, e.category)),
                        subtitle: Text(
                          e.note == null || e.note!.isEmpty
                              ? df.format(e.date)
                              : '${df.format(e.date)} · ${e.note}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          Money(e.amount).withSymbol(cur),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onTap: () => _openDialog(context, existing: e),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDialog(BuildContext context, {Expense? existing}) {
    return showDialog<void>(
      context: context,
      builder: (_) => _ExpenseDialog(existing: existing),
    );
  }
}

class _ExpenseDialog extends ConsumerStatefulWidget {
  const _ExpenseDialog({this.existing});
  final Expense? existing;

  @override
  ConsumerState<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends ConsumerState<_ExpenseDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late String _category;
  late DateTime _date;
  String? _receiptPhotoPath;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _category = e?.category ?? expenseCategories.first;
    _date = e?.date ?? DateTime.now();
    _receiptPhotoPath = e?.receiptPhotoPath;
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickReceiptPhoto() async {
    final res =
        await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = res?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    final c = compressImage(Uint8List.fromList(file.bytes!),
        fallbackExt: (file.extension ?? 'jpg').toLowerCase());
    final path = await ref
        .read(expenseRepositoryProvider)
        .saveReceiptPhoto(c.bytes, ext: c.ext);
    if (mounted) setState(() => _receiptPhotoPath = path);
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(expenseRepositoryProvider).upsertExpense(
            id: widget.existing?.id,
            category: _category,
            amount: amount,
            date: _date,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            receiptPhotoPath: _receiptPhotoPath,
          );
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(l.expenseSaved)));
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
      builder: (_) => AlertDialog(
        title: Text(l.expenseDeleteConfirmTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(expenseRepositoryProvider).deleteExpense(widget.existing!.id);
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(l.expenseDeleted)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final df = DateFormat('yyyy-MM-dd');
    final photoExists =
        _receiptPhotoPath != null && File(_receiptPhotoPath!).existsSync();

    return AlertDialog(
      title: Text(widget.existing == null ? l.expenseAdd : l.expenseEdit),
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
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(df.format(_date)),
            ),
            const SizedBox(height: AppTheme.space3),
            TextField(
              controller: _note,
              decoration: InputDecoration(labelText: l.expenseNote),
            ),
            const SizedBox(height: AppTheme.space3),
            OutlinedButton.icon(
              onPressed: _pickReceiptPhoto,
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: Text(photoExists
                  ? l.expenseReceiptPhotoReplace
                  : l.expenseReceiptPhotoAdd),
            ),
            if (_receiptPhotoPath != null && !photoExists)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(l.expenseReceiptPhotoMissing,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l.expenseReceiptPhotoHint,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            onPressed: _saving ? null : _delete,
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: Text(l.commonDelete),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
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
