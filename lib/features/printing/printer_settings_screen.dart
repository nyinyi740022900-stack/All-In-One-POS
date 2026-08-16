import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
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

  /// Pairs [d] as the active printer. If it has no remembered paper size
  /// yet (a genuinely new printer, not just re-selecting a previously
  /// configured one), asks once — pre-selecting a best-effort guess from
  /// the device name (see [suggestPaperSizeFromDeviceName]) — since the
  /// Bluetooth pairing API exposes no real capability info to detect this
  /// automatically.
  Future<void> _pairDevice(BtDevice d) async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.setPrinter(d.mac, d.name);
    if (await settings.hasPaperSizeForPrinter(d.mac)) return;
    if (!mounted) return;
    final suggested = suggestPaperSizeFromDeviceName(d.name) ?? PaperSize.mm58;
    final chosen = await _choosePaperSizeDialog(initial: suggested);
    if (chosen != null) {
      await settings.setPaperSizeForPrinter(d.mac, chosen);
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
              Text(l.printerChoosePaperSizeHint,
                  style: Theme.of(ctx).textTheme.bodySmall),
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
          SectionHeader(title: l.printerPaperSize),
          SegmentedButton<PaperSize>(
            segments: [
              ButtonSegment(value: PaperSize.mm58, label: Text(l.paper58)),
              ButtonSegment(value: PaperSize.mm80, label: Text(l.paper80)),
            ],
            selected: {config?.paper ?? PaperSize.mm58},
            // A connected printer remembers its own size from here on;
            // with none paired yet, this sets the device-wide default a
            // newly-paired printer starts from (see _pairDevice).
            onSelectionChanged: (s) =>
                (config != null && config.hasPrinter)
                    ? settings.setPaperSizeForPrinter(config.mac!, s.first)
                    : settings.setPaperSize(s.first),
          ),
          const SizedBox(height: AppTheme.space5),

          SectionHeader(title: l.printerPdfPaperSize),
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

          SectionHeader(
            title: l.printerPaired,
            trailing: TextButton.icon(
              onPressed: _loading ? null : _loadDevices,
              icon: _loading
                  ? const ButtonSpinner(size: 16)
                  : const Icon(Icons.bluetooth_searching),
              label: Text(l.printerSelectDevice),
            ),
          ),

          if (config != null && config.hasPrinter)
            Card(
              child: ListTile(
                leading: const IconAvatar(
                  icon: Icons.print,
                  tone: StatusTone.positive,
                ),
                title: Text(config.name ?? config.mac!),
                subtitle: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(config.mac!)),
                    const SizedBox(width: AppTheme.space2),
                    StatusPill(
                      label: l.printerConnected,
                      tone: StatusTone.positive,
                    ),
                  ],
                ),
                trailing: _testing
                    ? const ButtonSpinner()
                    : TextButton(
                        onPressed: () =>
                            _testPrint(config.paper, config.mac!),
                        child: Text(l.printerTestPrint),
                      ),
              ),
            ),

          if (_devices != null && _devices!.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.space4),
              child: EmptyStateView(
                icon: Icons.bluetooth_disabled,
                title: l.printerNoDevicesFound,
              ),
            )
          else if (_devices != null)
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < _devices!.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _PairedDeviceTile(
                      device: _devices![i],
                      isSelected: config?.mac == _devices![i].mac,
                      onTap: () => _pairDevice(_devices![i]),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One row in the "pick a different printer" list — harmonizes with the
/// active-printer card above it (same [IconAvatar]/positive-tone language)
/// while staying in the bare-`ListTile` vocabulary the rest of the app's
/// directory lists (Suppliers, Customers) already use. The currently-paired
/// device gets a tinted background plus a check mark, since scanning nearby
/// Bluetooth devices can list several with near-identical names ("Printer",
/// "BT Printer") and the plain `ListTile.selected` text tint alone was easy
/// to miss at a glance.
class _PairedDeviceTile extends StatelessWidget {
  const _PairedDeviceTile({
    required this.device,
    required this.isSelected,
    required this.onTap,
  });

  final BtDevice device;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: IconAvatar(
        icon: Icons.bluetooth,
        tone: isSelected ? StatusTone.positive : null,
      ),
      title: Text(device.name.isEmpty ? device.mac : device.name),
      subtitle: Text(device.mac),
      selected: isSelected,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      trailing: isSelected
          ? Icon(Icons.check_circle, color: AppColors.of(context).success)
          : null,
      onTap: onTap,
    );
  }
}
