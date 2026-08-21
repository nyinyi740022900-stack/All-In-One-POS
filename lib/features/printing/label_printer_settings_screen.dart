import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import 'label_data.dart';
import 'printer_connection.dart';
import 'printer_transport_section.dart';
import 'printing_providers.dart';

String labelSizeLabel(AppLocalizations l, LabelSize size) => switch (size) {
  LabelSize.mm40x30 => l.labelSize40x30,
  LabelSize.mm50x30 => l.labelSize50x30,
  LabelSize.mm50x40 => l.labelSize50x40,
};

class LabelPrinterSettingsScreen extends ConsumerStatefulWidget {
  const LabelPrinterSettingsScreen({super.key});

  @override
  ConsumerState<LabelPrinterSettingsScreen> createState() =>
      _LabelPrinterSettingsScreenState();
}

class _LabelPrinterSettingsScreenState
    extends ConsumerState<LabelPrinterSettingsScreen> {
  bool _testing = false;

  Future<void> _savePrinter({
    required String address,
    required String name,
    required PrinterConnection connection,
  }) {
    return ref
        .read(settingsRepositoryProvider)
        .setLabelPrinter(address, name, connection: connection);
  }

  Future<void> _testPrint() async {
    final config = ref.read(labelPrinterConfigProvider).valueOrNull;
    if (config == null || !config.hasPrinter) return;
    setState(() => _testing = true);
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      const sample = LabelData(
        name: 'စမ်းသပ် ပစ္စည်း',
        priceText: '1,000 Ks',
        barcode: 'TEST0001',
      );
      final result = await ref
          .read(printerServiceProvider)
          .printTsplLabel(
            sample,
            size: config.size,
            mac: config.mac!,
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
    final config = ref.watch(labelPrinterConfigProvider).valueOrNull;
    final settings = ref.read(settingsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.labelPrinterSettings)),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.space4),
        children: [
          SectionHeader(title: l.labelPrinterSize),
          SegmentedButton<LabelSize>(
            segments: [
              for (final size in LabelSize.values)
                ButtonSegment(
                  value: size,
                  label: Text(labelSizeLabel(l, size)),
                ),
            ],
            selected: {config?.size ?? LabelSize.mm40x30},
            onSelectionChanged: (s) => settings.setLabelSize(s.first),
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
