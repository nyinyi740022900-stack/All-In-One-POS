import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../invoices/receipt_data.dart';
import 'printer_connection.dart';
import 'printer_service.dart';
import 'printer_transport_section.dart';
import 'printing_providers.dart';

class PrinterSettingsScreen extends ConsumerStatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  ConsumerState<PrinterSettingsScreen> createState() =>
      _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends ConsumerState<PrinterSettingsScreen> {
  bool _testing = false;

  /// Pairs [address] as the active printer. Same one-time paper-size prompt
  /// as Bluetooth pairing — a newly-typed IP has no remembered size yet.
  Future<void> _savePrinter({
    required String address,
    required String name,
    required PrinterConnection connection,
  }) async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.setPrinter(address, name, connection: connection);
    if (await settings.hasPaperSizeForPrinter(address)) return;
    if (!mounted) return;
    final suggested = suggestPaperSizeFromDeviceName(name) ?? PaperSize.mm58;
    final chosen = await _choosePaperSizeDialog(initial: suggested);
    if (chosen != null) {
      await settings.setPaperSizeForPrinter(address, chosen);
    }
  }

  Future<PaperSize?> _choosePaperSizeDialog({required PaperSize initial}) {
    final l = AppLocalizations.of(context);
    var selected = initial;
    return showDialog<PaperSize>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l.printerChoosePaperSizeTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.printerChoosePaperSizeHint,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: AppTheme.space3),
              SegmentedButton<PaperSize>(
                segments: [
                  ButtonSegment(value: PaperSize.mm58, label: Text(l.paper58)),
                  ButtonSegment(value: PaperSize.mm80, label: Text(l.paper80)),
                ],
                selected: {selected},
                onSelectionChanged: (s) =>
                    setDialogState(() => selected = s.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: Text(l.commonSave),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testPrint() async {
    final config = ref.read(printerConfigProvider).valueOrNull;
    if (config == null || !config.hasPrinter) return;
    setState(() => _testing = true);
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final sample = ReceiptData(
        shopName: 'MM POS',
        invoiceNo: 'TEST-0001',
        dateTime: DateTime.now(),
        items: const [
          ReceiptLineItem(
            name: 'စမ်းသပ် ပစ္စည်း',
            qty: 1,
            unitPrice: 1000,
            lineTotal: 1000,
          ),
        ],
        subtotal: 1000,
        discount: 0,
        total: 1000,
        paid: 1000,
        change: 0,
        paymentMethod: l.paymentCash,
        footer: l.receiptThankYou,
      );
      final result = await ref
          .read(printerServiceProvider)
          .printReceipt(
            sample,
            paper: config.paper,
            mac: config.mac!,
            labels: receiptLabels(l),
            connection: config.connection,
          );
      messenger.showSnackBar(
        SnackBar(content: Text(printerTransportErrorMessage(l, result))),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final config = ref.watch(printerConfigProvider).valueOrNull;
    final settings = ref.read(settingsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.printerSettings)),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.space4),
        children: [
          SectionHeader(title: l.printerPaperSize),
          SegmentedButton<PaperSize>(
            segments: [
              ButtonSegment(value: PaperSize.mm58, label: Text(l.paper58)),
              ButtonSegment(value: PaperSize.mm80, label: Text(l.paper80)),
            ],
            selected: {config?.paper ?? PaperSize.mm58},
            onSelectionChanged: (s) => (config != null && config.hasPrinter)
                ? settings.setPaperSizeForPrinter(config.mac!, s.first)
                : settings.setPaperSize(s.first),
          ),
          const SizedBox(height: AppTheme.space5),
          SectionHeader(title: l.printerPdfPaperSize),
          Text(
            l.printerPdfPaperSizeHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppTheme.space2),
          SegmentedButton<PdfPaperSize>(
            segments: [
              ButtonSegment(value: PdfPaperSize.a4, label: Text(l.paperA4)),
              ButtonSegment(value: PdfPaperSize.a5, label: Text(l.paperA5)),
            ],
            selected: {config?.pdfPaperSize ?? PdfPaperSize.a4},
            onSelectionChanged: (s) => settings.setPdfPaperSize(s.first),
          ),
          const SizedBox(height: AppTheme.space5),
          PrinterTransportSection(
            savedAddress: config?.mac,
            savedName: config?.name,
            savedConnection: config?.connection ?? PrinterConnection.bluetooth,
            hasPrinter: config?.hasPrinter ?? false,
            onSave: _savePrinter,
            onTestPrint: _testPrint,
            testing: _testing,
          ),
        ],
      ),
    );
  }
}
