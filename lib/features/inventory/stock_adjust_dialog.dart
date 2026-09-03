import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/thousands_formatter.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../printing/printing_providers.dart';
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
  final _unitCostController = TextEditingController();
  final _noteController = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _qtyController.dispose();
    _unitCostController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // A restock/adjustment is most often ±1 (one broken item, one unit
  // received) — clamping here mirrors the floor `_submit` already enforces
  // (can't restock below 1, can't adjust a product's stock below zero) so
  // the stepper can't walk the field into a state that would just bounce
  // back as an error on save.
  void _stepQty(int delta) {
    final current = int.tryParse(_qtyController.text.trim()) ?? 0;
    var next = current + delta;
    if (_mode == _Mode.restock) {
      if (next < 1) next = 1;
    } else {
      final floor = -widget.currentQuantity;
      if (next < floor) next = floor;
    }
    setState(() {
      _qtyController.text = next.toString();
      _error = null;
    });
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
    final after = widget.currentQuantity + delta;
    if (after < 0) {
      setState(() => _error = l.stockAdjustBelowZero(widget.currentQuantity));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.stockAdjustConfirmTitle),
        content: Text(l.stockAdjustConfirmBody(
            widget.productName, widget.currentQuantity, after)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.stockAdjustSave)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

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

    final unitCost = _mode == _Mode.restock &&
            _unitCostController.text.trim().isNotEmpty
        ? parseDecimalMinorUnits(_unitCostController.text.trim(),
            exponent: ref.read(shopCurrencyProvider).exponent)
        : null;

    final navigator = Navigator.of(context);
    try {
      await ref.read(inventoryRepositoryProvider).adjustStock(
            productId: widget.productId,
            delta: delta,
            type: _mode == _Mode.restock ? 'purchase' : 'adjustment',
            note: note,
            unitCost: unitCost,
          );
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        // A concurrent adjustment on another device can take stock below
        // zero between this dialog's own pre-check above and the write
        // actually landing — surfaced by the repository as a StateError.
        // Anything else is an unclassified failure.
        _error = e is StateError ? l.stockAdjustRace : l.commonUnexpectedError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final currencyExponent = ref.watch(shopCurrencyProvider).exponent;
    return AlertDialog(
      title: Text(l.stockAdjustTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.productName,
                style: Theme.of(context).textTheme.titleSmall),
            Text(l.stockAdjustCurrentStock(widget.currentQuantity),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppTheme.space3),
            SegmentedButton<_Mode>(
              // Material's default segment padding is horizontal-only, so
              // the segment height stays pinned at its 40dp minimum — and
              // "ပစ္စည်းအသစ်ထည့်" wraps to two lines (~41pt) and gets its
              // second line sliced off by the segment border. Observed live
              // in the `my` locale. Vertical padding lets the control grow
              // to whatever the translated label needs.
              style: SegmentedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.space3, vertical: AppTheme.space2),
              ),
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
            const SizedBox(height: AppTheme.space3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The typed-only field covered the common ±1 case (one item
                // received/broken) in three taps — keyboard open, type,
                // dismiss — instead of one.
                IconButton.filledTonal(
                  onPressed: () => _stepQty(-1),
                  icon: const Icon(Icons.remove),
                  tooltip: l.sellDecreaseQty,
                ),
                const SizedBox(width: AppTheme.space2),
                Expanded(
                  child: TextField(
                    controller: _qtyController,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.numberWithOptions(
                        signed: _mode == _Mode.adjust),
                    inputFormatters: [LengthLimitingTextInputFormatter(10)],
                    decoration: InputDecoration(
                      labelText: l.stockAdjustQuantity,
                      hintText: _mode == _Mode.restock
                          ? l.stockAdjustQuantityHintRestock
                          : l.stockAdjustQuantityHintAdjust,
                      errorText: _error,
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.space2),
                IconButton.filledTonal(
                  onPressed: () => _stepQty(1),
                  icon: const Icon(Icons.add),
                  tooltip: l.sellIncreaseQty,
                ),
              ],
            ),
            if (_mode == _Mode.restock) ...[
              const SizedBox(height: AppTheme.space3),
              TextField(
                controller: _unitCostController,
                keyboardType: TextInputType.numberWithOptions(
                    decimal: currencyExponent > 0),
                inputFormatters: [
                  DecimalMoneyInputFormatter(exponent: currencyExponent),
                  LengthLimitingTextInputFormatter(12),
                ],
                decoration: InputDecoration(
                  labelText: l.stockAdjustUnitCost,
                  hintText: l.stockAdjustUnitCostHint,
                ),
              ),
            ],
            if (_mode == _Mode.adjust) ...[
              const SizedBox(height: AppTheme.space3),
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
            const SizedBox(height: AppTheme.space3),
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
