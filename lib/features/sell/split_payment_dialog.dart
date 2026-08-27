import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/input/thousands_formatter.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/database.dart';
import '../../data/repositories/sales_repository.dart' show PaymentEntry;
import '../../l10n/app_localizations.dart';
import 'payment_labels.dart';

/// Lets the cashier charge one sale across 2+ payment methods (e.g. cash +
/// KBZPay). Returns the confirmed entries, or null if cancelled. Save stays
/// disabled — rather than a submit-time error — until every row has a
/// distinct method, a positive amount, and the rows sum to exactly [total]
/// (v1 doesn't support change-due or a credit shortfall on a split sale).
Future<List<PaymentEntry>?> showSplitPaymentDialog(
  BuildContext context, {
  required int total,
  required List<String> methodIds,
  required List<PaymentAccount> accounts,
  List<PaymentEntry>? initial,
}) {
  return showDialog<List<PaymentEntry>>(
    context: context,
    builder: (_) => _SplitPaymentDialog(
      total: total,
      methodIds: methodIds,
      accounts: accounts,
      initial: initial,
    ),
  );
}

class _SplitRow {
  String method;
  final TextEditingController amount;
  _SplitRow(this.method, int initialAmount)
    : amount = TextEditingController(text: formatThousands(initialAmount));
}

class _SplitPaymentDialog extends StatefulWidget {
  const _SplitPaymentDialog({
    required this.total,
    required this.methodIds,
    required this.accounts,
    this.initial,
  });

  final int total;
  final List<String> methodIds;
  final List<PaymentAccount> accounts;
  final List<PaymentEntry>? initial;

  @override
  State<_SplitPaymentDialog> createState() => _SplitPaymentDialogState();
}

class _SplitPaymentDialogState extends State<_SplitPaymentDialog> {
  late final List<_SplitRow> _rows = _initialRows();

  List<_SplitRow> _initialRows() {
    final initial = widget.initial;
    if (initial != null && initial.length >= 2) {
      return [for (final e in initial) _SplitRow(e.method, e.amount)];
    }
    // Default to the first two available methods, the remainder pre-filled
    // on the second row — the common "cash covers most of it, the wallet
    // covers the rest" case then needs only one number typed.
    final a = widget.methodIds.isNotEmpty ? widget.methodIds[0] : 'cash';
    final b = widget.methodIds.length > 1 ? widget.methodIds[1] : 'kbzpay';
    return [_SplitRow(a, 0), _SplitRow(b, widget.total)];
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.amount.dispose();
    }
    super.dispose();
  }

  int _amountOf(_SplitRow r) => parseThousands(r.amount.text);
  int get _sum => _rows.fold(0, (a, r) => a + _amountOf(r));
  int get _remaining => widget.total - _sum;

  bool get _valid {
    if (_rows.length < 2) return false;
    if (_rows.map((r) => r.method).toSet().length != _rows.length) {
      return false; // no two rows on the same method
    }
    if (_rows.any((r) => _amountOf(r) <= 0)) return false;
    return _remaining == 0;
  }

  /// Methods still pickable for [current]'s dropdown — every method already
  /// used by another row is excluded, so two rows can never collide.
  List<String> _availableMethodsFor(_SplitRow current) {
    final usedElsewhere = _rows
        .where((r) => r != current)
        .map((r) => r.method)
        .toSet();
    return widget.methodIds.where((m) => !usedElsewhere.contains(m)).toList();
  }

  void _addRow() {
    final used = _rows.map((r) => r.method).toSet();
    final next = widget.methodIds.firstWhere(
      (m) => !used.contains(m),
      orElse: () => widget.methodIds.first,
    );
    setState(
      () => _rows.add(_SplitRow(next, _remaining > 0 ? _remaining : 0)),
    );
  }

  void _removeRow(_SplitRow row) {
    if (_rows.length <= 2) return;
    setState(() => _rows.remove(row));
    row.amount.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final currency = l.currencySymbol;
    final colors = AppColors.of(context);
    final canAddMore = _rows.length < widget.methodIds.length;

    return AlertDialog(
      title: Text(l.splitPaymentTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in _rows) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.space2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: DropdownButtonFormField<String>(
                        initialValue: row.method,
                        isExpanded: true,
                        decoration: const InputDecoration(isDense: true),
                        items: [
                          for (final m in _availableMethodsFor(row))
                            DropdownMenuItem(
                              value: m,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(paymentIcon(m), size: 16),
                                  const SizedBox(width: AppTheme.space1),
                                  Flexible(
                                    child: Text(
                                      paymentLabel(
                                        l,
                                        m,
                                        accounts: widget.accounts,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => row.method = v);
                        },
                      ),
                    ),
                    const SizedBox(width: AppTheme.space2),
                    Expanded(
                      flex: 4,
                      child: TextField(
                        controller: row.amount,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.end,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          ThousandsSeparatorInputFormatter(),
                        ],
                        decoration: const InputDecoration(isDense: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: l.splitPaymentRemoveMethod,
                      onPressed: _rows.length > 2
                          ? () => _removeRow(row)
                          : null,
                    ),
                  ],
                ),
              ),
            ],
            if (canAddMore)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add),
                  label: Text(l.splitPaymentAddMethod),
                ),
              ),
            const SizedBox(height: AppTheme.space2),
            Text(
              l.splitPaymentRemaining(Money(_remaining).withSymbol(currency)),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _remaining == 0 ? colors.success : colors.warning,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.of(context).pop([
                  for (final r in _rows) PaymentEntry(r.method, _amountOf(r)),
                ])
              : null,
          child: Text(l.commonSave),
        ),
      ],
    );
  }
}
