import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import 'label_data.dart';
import 'printer_service.dart';
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

  Future<void> _testPrint(LabelSize size, String mac) async {
    setState(() => _testing = true);
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      const sample = LabelData(
        name: 'စမ်းသပ် ပစ္စည်း',
        priceText: '1,000 Ks',
        barcode: 'TEST0001',
      );
      final result = await ref.read(printerServiceProvider).printTsplLabel(
            sample,
            size: size,
            mac: mac,
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
    final config = ref.watch(labelPrinterConfigProvider).valueOrNull;
    final settings = ref.read(settingsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.labelPrinterSettings)),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.space4),
        children: [
          Text(l.labelPrinterSize,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppTheme.space2),
          SegmentedButton<LabelSize>(
            segments: [
              for (final size in LabelSize.values)
                ButtonSegment(value: size, label: Text(labelSizeLabel(l, size))),
            ],
            selected: {config?.size ?? LabelSize.mm40x30},
            onSelectionChanged: (s) => settings.setLabelSize(s.first),
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
                    ? const ButtonSpinner(size: 16)
                    : const Icon(Icons.bluetooth_searching),
                label: Text(l.printerSelectDevice),
              ),
            ],
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
                        onPressed: () => _testPrint(config.size, config.mac!),
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
            ...(_devices!.map((d) => ListTile(
                  leading: const Icon(Icons.bluetooth),
                  title: Text(d.name.isEmpty ? d.mac : d.name),
                  subtitle: Text(d.mac),
                  selected: config?.mac == d.mac,
                  onTap: () => settings.setLabelPrinter(d.mac, d.name),
                ))),
        ],
      ),
    );
  }
}
