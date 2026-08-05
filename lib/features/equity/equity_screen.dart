import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/database.dart';
import '../../l10n/app_localizations.dart';
import '../license/license_providers.dart';
import '../license/premium_gate.dart';
import 'equity_calculator.dart';
import 'equity_providers.dart';

/// Owner's Equity: capital contributions + drawings, plus Retained
/// Earnings (cumulative Net Profit since inception) — deliberately
/// separate from Expenses so a drawing never reduces the P&L's Net
/// Profit. Toward an eventual Balance Sheet.
class OwnerEquityScreen extends ConsumerWidget {
  const OwnerEquityScreen({super.key});

  Widget _row(BuildContext context, String label, int amount, String currency,
      {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: bold
                  ? Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)
                  : Theme.of(context).textTheme.bodyMedium),
          Text(Money(amount).withSymbol(currency),
              style: bold
                  ? Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)
                  : Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    if (ref.watch(licenseControllerProvider).loading ||
        !ref.watch(isPremiumProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l.equityTitle)),
        body: PremiumGate(featureName: l.equityTitle, child: const SizedBox.shrink()),
      );
    }
    final cur = l.currencySymbol;
    final entries = ref.watch(equityEntriesProvider).valueOrNull ?? const [];
    final summaryAsync = ref.watch(equitySummaryProvider);
    final df = DateFormat('yyyy-MM-dd');

    return Scaffold(
      appBar: AppBar(title: Text(l.equityTitle)),
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
            child: summaryAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Text(l.commonUnexpectedError),
              data: (s) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(context, l.equityPaidInCapital, s.paidInCapital, cur),
                  _row(context, l.equityRetainedEarnings, s.retainedEarnings,
                      cur),
                  const Divider(),
                  _row(context, l.equityTotal, s.totalEquity, cur, bold: true),
                ],
              ),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(child: Text(l.equityEmpty))
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      final isContribution = e.type == equityTypeContribution;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isContribution
                              ? Colors.green.withValues(alpha: 0.15)
                              : Theme.of(context)
                                  .colorScheme
                                  .error
                                  .withValues(alpha: 0.15),
                          child: Icon(
                            isContribution
                                ? Icons.add_circle_outline
                                : Icons.remove_circle_outline,
                            color: isContribution
                                ? Colors.green
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                        title: Text(isContribution
                            ? l.equityContribution
                            : l.equityDrawing),
                        subtitle: Text(
                          e.note == null || e.note!.isEmpty
                              ? df.format(e.date)
                              : '${df.format(e.date)} · ${e.note}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          '${isContribution ? '+' : '-'}${Money(e.amount).withSymbol(cur)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isContribution
                                ? Colors.green
                                : Theme.of(context).colorScheme.error,
                          ),
                        ),
                        onLongPress: () => _confirmDelete(context, ref, e),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, EquityEntry e) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.equityDeleteConfirmTitle),
        content: Text(l.equityDeleteConfirmBody),
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
    if (ok != true) return;
    await ref.read(equityRepositoryProvider).deleteEntry(e.id);
  }

  Future<void> _openDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const _EquityEntryDialog(),
    );
  }
}

class _EquityEntryDialog extends ConsumerStatefulWidget {
  const _EquityEntryDialog();

  @override
  ConsumerState<_EquityEntryDialog> createState() => _EquityEntryDialogState();
}

class _EquityEntryDialogState extends ConsumerState<_EquityEntryDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _type = equityTypeContribution;
  DateTime _date = DateTime.now();
  bool _saving = false;

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

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(equityRepositoryProvider).addEntry(
            type: _type,
            amount: amount,
            date: _date,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(l.equitySaved)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final df = DateFormat('yyyy-MM-dd');
    return AlertDialog(
      title: Text(l.equityAdd),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                    value: equityTypeContribution,
                    label: Text(l.equityContribution)),
                ButtonSegment(
                    value: equityTypeDrawing, label: Text(l.equityDrawing)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: AppTheme.space3),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              decoration: InputDecoration(labelText: l.equityAmount),
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
          ],
        ),
      ),
      actions: [
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
