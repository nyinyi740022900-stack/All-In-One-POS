import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../invoices/receipt_data.dart';
import 'printer_service.dart';
import 'printing_providers.dart';

class PrinterSettingsScreen extends ConsumerStatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  ConsumerState<PrinterSettingsScreen> createState() =>
      _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState
    extends ConsumerState<PrinterSettingsScreen> {
  List<BtDevice>? _devices;
  bool _loading = false;
  bool _testing = false;

  Future<void> _loadDevices() async {
    setState(() => _loading = true);
    final svc = ref.read(printerServiceProvider);
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await svc.bluetoothEnabled) {
        messenger.showSnackBar(SnackBar(content: Text(l.bluetoothOff)));
        return;
      }
      final list = await svc.pairedDevices();
      if (mounted) setState(() => _devices = list);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _testPrint(PaperSize paper, String mac) async {
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
              name: 'စမ်းသပ် ပစ္စည်း', qty: 1, unitPrice: 1000, lineTotal: 1000),
        ],
        subtotal: 1000,
        discount: 0,
        total: 1000,
        paid: 1000,
        change: 0,
        paymentMethod: l.paymentCash,
        footer: l.receiptThankYou,
      );
      final result = await ref.read(printerServiceProvider).printReceipt(
            sample,
            paper: paper,
            mac: mac,
            labels: receiptLabels(l),
          );
      messenger.showSnackBar(SnackBar(
          content: Text(result.ok ? l.printSuccess : l.printFailed)));
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
          Text(l.printerPaperSize,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppTheme.space2),
          SegmentedButton<PaperSize>(
            segments: [
              ButtonSegment(value: PaperSize.mm58, label: Text(l.paper58)),
              ButtonSegment(value: PaperSize.mm80, label: Text(l.paper80)),
            ],
            selected: {config?.paper ?? PaperSize.mm58},
            onSelectionChanged: (s) => settings.setPaperSize(s.first),
          ),
          const SizedBox(height: AppTheme.space5),

          Text(l.printerPdfPaperSize,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppTheme.space1),
          Text(l.printerPdfPaperSizeHint,
              style: Theme.of(context).textTheme.bodySmall),
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

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l.printerPaired,
                  style: Theme.of(context).textTheme.titleMedium),
              TextButton.icon(
                onPressed: _loading ? null : _loadDevices,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.bluetooth_searching),
                label: Text(l.printerSelectDevice),
              ),
            ],
          ),

          if (config != null && config.hasPrinter)
            Card(
              child: ListTile(
                leading: const Icon(Icons.print, color: Colors.green),
                title: Text(config.name ?? config.mac!),
                subtitle: Text(config.mac!),
                trailing: _testing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton(
                        onPressed: () =>
                            _testPrint(config.paper, config.mac!),
                        child: Text(l.printerTestPrint),
                      ),
              ),
            ),

          if (_devices != null)
            ...(_devices!.map((d) => ListTile(
                  leading: const Icon(Icons.bluetooth),
                  title: Text(d.name.isEmpty ? d.mac : d.name),
                  subtitle: Text(d.mac),
                  selected: config?.mac == d.mac,
                  onTap: () => settings.setPrinter(d.mac, d.name),
                ))),
        ],
      ),
    );
  }
}
