import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'inventory_providers.dart';

enum _Mode { restock, adjust }

enum _Reason { damaged, lost, count, other }

String _reasonLabel(AppLocalizations l, _Reason r) => switch (r) {
      _Reason.damaged => l.stockReasonDamaged,
      _Reason.lost => l.stockReasonLost,
      _Reason.count => l.stockReasonCount,
      _Reason.other => l.stockReasonOther,
    };

/// Opens a dialog to restock (always increases) or adjust (signed
/// correction with a reason) one product's stock. Writes a proper ledger
/// entry via [InventoryRepository.adjustStock] — unlike the product editor's
/// quantity field, which silently sets an absolute value with no reason.
Future<void> showStockAdjustDialog(
  BuildContext context,
  WidgetRef ref, {
  required String productId,
  required String productName,
  required int currentQuantity,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _StockAdjustDialog(
      productId: productId,
      productName: productName,
      currentQuantity: currentQuantity,
    ),
  );
}

class _StockAdjustDialog extends ConsumerStatefulWidget {
  const _StockAdjustDialog({
    required this.productId,
    required this.productName,
    required this.currentQuantity,
  });

  final String productId;
  final String productName;
  final int currentQuantity;

  @override
  ConsumerState<_StockAdjustDialog> createState() =>
      _StockAdjustDialogState();
}

class _StockAdjustDialogState extends ConsumerState<_StockAdjustDialog> {
  _Mode _mode = _Mode.restock;
  _Reason _reason = _Reason.damaged;
  final _qtyController = TextEditingController();
  final _noteController = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _qtyController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final raw = _qtyController.text.trim();
    final entered = int.tryParse(raw);
    if (entered == null || entered == 0) {
      setState(() => _error = l.stockAdjustInvalid);
      return;
    }
    final delta = _mode == _Mode.restock ? entered.abs() : entered;

    setState(() {
      _saving = true;
      _error = null;
    });

    final note = switch (_mode) {
      _Mode.restock =>
        _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      _Mode.adjust => _noteController.text.trim().isEmpty
          ? _reasonLabel(l, _reason)
          : '${_reasonLabel(l, _reason)} — ${_noteController.text.trim()}',
    };

    final navigator = Navigator.of(context);
    await ref.read(inventoryRepositoryProvider).adjustStock(
          productId: widget.productId,
          delta: delta,
          type: _mode == _Mode.restock ? 'purchase' : 'adjustment',
          note: note,
        );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.stockAdjustTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.productName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(l.stockAdjustCurrentStock(widget.currentQuantity),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            SegmentedButton<_Mode>(
              segments: [
                ButtonSegment(
                    value: _Mode.restock,
                    label: Text(l.stockAdjustModeRestock)),
                ButtonSegment(
                    value: _Mode.adjust, label: Text(l.stockAdjustModeAdjust)),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _qtyController,
              keyboardType:
                  TextInputType.numberWithOptions(signed: _mode == _Mode.adjust),
              decoration: InputDecoration(
                labelText: l.stockAdjustQuantity,
                hintText: _mode == _Mode.restock
                    ? l.stockAdjustQuantityHintRestock
                    : l.stockAdjustQuantityHintAdjust,
                errorText: _error,
              ),
            ),
            if (_mode == _Mode.adjust) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<_Reason>(
                initialValue: _reason,
                decoration: InputDecoration(labelText: l.stockAdjustReason),
                items: [
                  for (final r in _Reason.values)
                    DropdownMenuItem(value: r, child: Text(_reasonLabel(l, r))),
                ],
                onChanged: (r) => setState(() => _reason = r ?? _reason),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: InputDecoration(labelText: l.stockAdjustNote),
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
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l.stockAdjustSave),
        ),
      ],
    );
  }
}
