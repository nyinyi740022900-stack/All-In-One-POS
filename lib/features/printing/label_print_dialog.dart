import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'label_data.dart';
import 'printing_providers.dart';

/// Prints [data] to whichever printer is configured — prefers a dedicated
/// label printer (real adhesive stickers) and falls back to a strip on the
/// receipt printer; shows a message and does nothing if neither is set up.
Future<void> showLabelPrintDialog(
  BuildContext context,
  WidgetRef ref, {
  required LabelData data,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _LabelPrintDialog(data: data),
  );
}

class _LabelPrintDialog extends ConsumerStatefulWidget {
  const _LabelPrintDialog({required this.data});
  final LabelData data;

  @override
  ConsumerState<_LabelPrintDialog> createState() => _LabelPrintDialogState();
}

class _LabelPrintDialogState extends ConsumerState<_LabelPrintDialog> {
  int _copies = 1;
  bool _printing = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final labelConfig = ref.watch(labelPrinterConfigProvider).valueOrNull;
    final printerConfig = ref.watch(printerConfigProvider).valueOrNull;
    final useDedicated = labelConfig?.hasPrinter ?? false;
    final useStrip = !useDedicated && (printerConfig?.hasPrinter ?? false);
    final hasTarget = useDedicated || useStrip;

    return AlertDialog(
      title: Text(l.labelPrintDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.data.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(widget.data.priceText),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l.labelCopies),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _copies > 1
                        ? () => setState(() => _copies--)
                        : null,
                  ),
                  Text('$_copies', style: const TextStyle(fontSize: 16)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _copies < 50
                        ? () => setState(() => _copies++)
                        : null,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hasTarget
                ? (useDedicated
                    ? l.labelPrintTargetDedicated
                    : l.labelPrintTargetStrip)
                : l.labelPrintNoTarget,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: hasTarget
                      ? Theme.of(context).colorScheme.outline
                      : Theme.of(context).colorScheme.error,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: !hasTarget || _printing
              ? null
              : () async {
                  setState(() => _printing = true);
                  final svc = ref.read(printerServiceProvider);
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);
                  final result = useDedicated
                      ? await svc.printTsplLabel(
                          widget.data,
                          size: labelConfig!.size,
                          mac: labelConfig.mac!,
                          copies: _copies,
                        )
                      : await svc.printLabel(
                          widget.data,
                          paper: printerConfig!.paper,
                          mac: printerConfig.mac!,
                          copies: _copies,
                        );
                  if (!mounted) return;
                  navigator.pop();
                  messenger.showSnackBar(SnackBar(
                      content:
                          Text(result.ok ? l.printSuccess : l.printFailed)));
                },
          child: _printing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l.inventoryPrintLabel),
        ),
      ],
    );
  }
}
