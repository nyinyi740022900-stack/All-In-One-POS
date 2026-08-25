import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../invoices/receipt_data.dart';
import 'picker_field.dart';
import 'printer_connection.dart';
import 'printer_models.dart';
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
  /// A device name that matches a known [PrinterModelPreset] (Xprinter,
  /// Epson TM-…, Rongta, …) pre-selects that model and its paper width so
  /// the prompt starts from the right answer.
  Future<void> _savePrinter({
    required String address,
    required String name,
    required PrinterConnection connection,
  }) async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.setPrinter(address, name, connection: connection);
    final suggestedModel = suggestPrinterModelFromName(name);
    if (suggestedModel != null) {
      await settings.setPrinterModel(address, suggestedModel.id);
    }
    if (await settings.hasPaperSizeForPrinter(address)) return;
    final suggested = suggestedModel?.recommendedPaper ??
        suggestPaperSizeFromDeviceName(name) ??
        PaperSize.mm58;
    if (!mounted) return;
    final chosen = await _choosePaperSizeDialog(initial: suggested);
    if (chosen != null) {
      await settings.setPaperSizeForPrinter(address, chosen);
    } else if (suggestedModel != null) {
      // Dismissed without choosing: still apply the preset's own width so
      // the stored model and paper never contradict each other.
      await settings.setPaperSizeForPrinter(address, suggestedModel.recommendedPaper);
    }
  }

  Future<PaperSize?> _choosePaperSizeDialog({required PaperSize initial}) {
    final l = AppLocalizations.of(context);
    return showAppPickerSheet<PaperSize>(
      context: context,
      title: l.printerChoosePaperSizeTitle,
      subtitle: l.printerChoosePaperSizeHint,
      selected: initial,
      options: [
        PickerOption(value: PaperSize.mm58, label: l.paper58),
        PickerOption(value: PaperSize.mm80, label: l.paper80),
        PickerOption(value: PaperSize.mm80Narrow, label: l.paper80Narrow),
      ],
    );
  }

  /// Stored model id → picker value: a known preset maps to itself; null
  /// or an unlisted id shows as "Other / not listed" so the choice sticks
  /// instead of snapping back to some unrelated preset.
  String _modelValue(String? modelId) =>
      printerModelById(modelId)?.id ?? kPrinterModelCustomId;

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
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.commonUnexpectedError)));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// Applies a chosen printer model: remembers the preset id for this
  /// printer, then (for a real preset, not "Other") also applies its
  /// recommended paper size — the whole point of the picker is not having
  /// to know whether your Epson head is 180 dpi or 203 dpi.
  Future<void> _pickModel(String modelId) async {
    final config = ref.read(printerConfigProvider).valueOrNull;
    if (config == null || !config.hasPrinter) return;
    final settings = ref.read(settingsRepositoryProvider);
    await settings.setPrinterModel(config.mac!, modelId);
    final preset = printerModelById(modelId);
    if (preset != null) {
      await settings.setPaperSizeForPrinter(
        config.mac!,
        preset.recommendedPaper,
      );
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
          AppPickerField<PaperSize>(
            label: l.printerPaperSize,
            value: config?.paper ?? PaperSize.mm58,
            onChanged: (size) => (config != null && config.hasPrinter)
                ? settings.setPaperSizeForPrinter(config.mac!, size)
                : settings.setPaperSize(size),
            options: [
              PickerOption(value: PaperSize.mm58, label: l.paper58),
              PickerOption(value: PaperSize.mm80, label: l.paper80),
              PickerOption(value: PaperSize.mm80Narrow, label: l.paper80Narrow),
            ],
          ),
          const SizedBox(height: AppTheme.space2),
          Text(
            l.printerPaperHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppTheme.space5),
          AppPickerField<PdfPaperSize>(
            label: l.printerPdfPaperSize,
            value: config?.pdfPaperSize ?? PdfPaperSize.a4,
            onChanged: settings.setPdfPaperSize,
            options: [
              PickerOption(value: PdfPaperSize.a4, label: l.paperA4),
              PickerOption(value: PdfPaperSize.a5, label: l.paperA5),
            ],
          ),
          const SizedBox(height: AppTheme.space2),
          Text(
            l.printerPdfPaperSizeHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (config != null && config.hasPrinter) ...[
            const SizedBox(height: AppTheme.space5),
            AppPickerField<String>(
              label: l.printerModel,
              value: _modelValue(config.modelId),
              onChanged: _pickModel,
              options: [
                for (final preset in kPrinterModels)
                  PickerOption(value: preset.id, label: preset.label),
                PickerOption(
                  value: kPrinterModelCustomId,
                  label: l.printerModelCustom,
                ),
              ],
            ),
            const SizedBox(height: AppTheme.space2),
            Text(
              l.printerModelHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
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
