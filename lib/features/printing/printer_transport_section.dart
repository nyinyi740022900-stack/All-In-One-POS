import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import 'network_transport.dart';
import 'printer_connection.dart';
import 'printer_service.dart';
import 'printing_providers.dart';
import 'usb_transport.dart';

IconData printerConnectionIcon(PrinterConnection connection) =>
    switch (connection) {
      PrinterConnection.bluetooth => Icons.bluetooth,
      PrinterConnection.network => Icons.wifi,
      PrinterConnection.usb => Icons.usb,
    };

String printerConnectionLabel(
  AppLocalizations l,
  PrinterConnection connection,
) => switch (connection) {
  PrinterConnection.bluetooth => l.printerConnectionBluetooth,
  PrinterConnection.network => l.printerConnectionWifi,
  PrinterConnection.usb => l.printerConnectionUsb,
};

String printerTransportErrorMessage(AppLocalizations l, PrintResult result) {
  if (result.ok) return l.printSuccess;
  if (result.error == 'network_unreachable' ||
      result.error == 'invalid_address') {
    return l.printerNetworkUnreachable;
  }
  return l.printFailed;
}

/// Bluetooth / Wi-Fi / USB picker shared by receipt and label printer
/// settings. Persists nothing — the parent saves via [onSave].
class PrinterTransportSection extends ConsumerStatefulWidget {
  const PrinterTransportSection({
    super.key,
    required this.savedAddress,
    required this.savedName,
    required this.savedConnection,
    required this.hasPrinter,
    required this.onSave,
    this.onTestPrint,
    this.testing = false,
  });

  final String? savedAddress;
  final String? savedName;
  final PrinterConnection savedConnection;
  final bool hasPrinter;
  final Future<void> Function({
    required String address,
    required String name,
    required PrinterConnection connection,
  })
  onSave;
  final VoidCallback? onTestPrint;
  final bool testing;

  @override
  ConsumerState<PrinterTransportSection> createState() =>
      _PrinterTransportSectionState();
}

class _PrinterTransportSectionState
    extends ConsumerState<PrinterTransportSection> {
  PrinterConnection? _pickedConnection;
  List<BtDevice>? _btDevices;
  List<UsbPrinterInfo>? _usbPrinters;
  List<NetworkPrinterAddress>? _scanned;
  bool _loadingBt = false;
  bool _loadingUsb = false;
  bool _scanning = false;
  late final TextEditingController _ip;
  late final TextEditingController _port;

  @override
  void initState() {
    super.initState();
    _ip = TextEditingController();
    _port = TextEditingController(text: '${NetworkPrinterAddress.defaultPort}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final connection = _connectionFor();
      if (connection == PrinterConnection.network) {
        _fillWifiFromSaved();
        _scanWifi();
      }
      if (connection == PrinterConnection.usb) _loadUsbPrinters();
    });
  }

  @override
  void dispose() {
    _ip.dispose();
    _port.dispose();
    super.dispose();
  }

  PrinterConnection _connectionFor() {
    if (_pickedConnection != null) return _pickedConnection!;
    if (widget.hasPrinter &&
        printerConnectionSupported(widget.savedConnection)) {
      return widget.savedConnection;
    }
    return defaultPrinterConnectionForPlatform();
  }

  void _fillWifiFromSaved() {
    if (!widget.hasPrinter ||
        widget.savedConnection != PrinterConnection.network ||
        widget.savedAddress == null) {
      return;
    }
    final parsed = NetworkPrinterAddress.tryParse(widget.savedAddress!);
    if (parsed == null) return;
    _ip.text = parsed.host;
    _port.text = '${parsed.port}';
  }

  Future<void> _loadBtDevices() async {
    setState(() => _loadingBt = true);
    final svc = ref.read(printerServiceProvider);
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await svc.bluetoothEnabled) {
        messenger.showSnackBar(SnackBar(content: Text(l.bluetoothOff)));
        return;
      }
      final list = await svc.pairedDevices();
      if (mounted) setState(() => _btDevices = list);
    } finally {
      if (mounted) setState(() => _loadingBt = false);
    }
  }

  Future<void> _loadUsbPrinters() async {
    setState(() => _loadingUsb = true);
    try {
      final list = await listUsbPrinters();
      if (mounted) setState(() => _usbPrinters = list);
    } finally {
      if (mounted) setState(() => _loadingUsb = false);
    }
  }

  Future<void> _scanWifi() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final found = await scanNetworkPrinters();
      if (mounted) setState(() => _scanned = found);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _saveWifiPrinter() async {
    final l = AppLocalizations.of(context);
    final fromIp = NetworkPrinterAddress.tryParse(_ip.text);
    final port = int.tryParse(_port.text.trim());
    if (fromIp == null || (port != null && (port < 1 || port > 65535))) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.printerInvalidIp)));
      return;
    }
    final parsed = NetworkPrinterAddress(
      fromIp.host,
      port: port ?? fromIp.port,
    );
    _ip.text = parsed.host;
    _port.text = '${parsed.port}';
    await widget.onSave(
      address: parsed.encoded,
      name: parsed.encoded,
      connection: PrinterConnection.network,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final available = printerConnectionsForPlatform();
    final connection = _connectionFor();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (available.length > 1) ...[
          SectionHeader(title: l.printerConnectionType),
          SegmentedButton<PrinterConnection>(
            segments: [
              for (final c in available)
                ButtonSegment(
                  value: c,
                  icon: Icon(printerConnectionIcon(c), size: 18),
                  label: Text(printerConnectionLabel(l, c)),
                ),
            ],
            selected: {connection},
            onSelectionChanged: (s) {
              final next = s.first;
              setState(() => _pickedConnection = next);
              if (next == PrinterConnection.network) {
                _fillWifiFromSaved();
                if (_scanned == null) _scanWifi();
              }
              if (next == PrinterConnection.usb && _usbPrinters == null) {
                _loadUsbPrinters();
              }
            },
          ),
          const SizedBox(height: AppTheme.space5),
        ],
        if (widget.hasPrinter)
          Card(
            child: ListTile(
              leading: IconAvatar(
                icon: printerConnectionIcon(widget.savedConnection),
                tone: StatusTone.positive,
              ),
              title: Text(widget.savedName ?? widget.savedAddress!),
              subtitle: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '${printerConnectionLabel(l, widget.savedConnection)} · ${widget.savedAddress!}',
                    ),
                  ),
                  const SizedBox(width: AppTheme.space2),
                  StatusPill(
                    label: l.printerConnected,
                    tone: StatusTone.positive,
                  ),
                ],
              ),
              isThreeLine: true,
              trailing: widget.onTestPrint == null
                  ? null
                  : widget.testing
                  ? const ButtonSpinner()
                  : TextButton(
                      onPressed: widget.onTestPrint,
                      child: Text(l.printerTestPrint),
                    ),
            ),
          ),
        if (connection == PrinterConnection.bluetooth) ...[
          const SizedBox(height: AppTheme.space4),
          SectionHeader(
            title: l.printerPaired,
            trailing: TextButton.icon(
              onPressed: _loadingBt ? null : _loadBtDevices,
              icon: _loadingBt
                  ? const ButtonSpinner(size: 16)
                  : const Icon(Icons.bluetooth_searching),
              label: Text(l.printerSelectDevice),
            ),
          ),
          if (_btDevices != null && _btDevices!.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.space4),
              child: EmptyStateView(
                icon: Icons.bluetooth_disabled,
                title: l.printerNoDevicesFound,
              ),
            )
          else if (_btDevices != null)
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < _btDevices!.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _PairedDeviceTile(
                      icon: Icons.bluetooth,
                      title: _btDevices![i].name.isEmpty
                          ? _btDevices![i].mac
                          : _btDevices![i].name,
                      subtitle: _btDevices![i].mac,
                      isSelected:
                          widget.savedAddress == _btDevices![i].mac &&
                          widget.savedConnection == PrinterConnection.bluetooth,
                      onTap: () => widget.onSave(
                        address: _btDevices![i].mac,
                        name: _btDevices![i].name,
                        connection: PrinterConnection.bluetooth,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
        if (connection == PrinterConnection.network) ...[
          const SizedBox(height: AppTheme.space4),
          SectionHeader(
            title: l.printerWifiList,
            trailing: TextButton.icon(
              onPressed: _scanning ? null : _scanWifi,
              icon: _scanning
                  ? const ButtonSpinner(size: 16)
                  : const Icon(Icons.refresh),
              label: Text(
                _scanning ? l.printerWifiScanning : l.printerUsbRefresh,
              ),
            ),
          ),
          Text(l.printerWifiHint, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppTheme.space3),
          if (_scanning && _scanned == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.space4),
              child: Row(
                children: [
                  const ButtonSpinner(),
                  const SizedBox(width: AppTheme.space3),
                  Expanded(child: Text(l.printerWifiScanning)),
                ],
              ),
            )
          else if (_scanned != null && _scanned!.isEmpty)
            EmptyStateView(icon: Icons.wifi_off, title: l.printerWifiNoneFound)
          else if (_scanned != null)
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < _scanned!.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _PairedDeviceTile(
                      icon: Icons.wifi,
                      title: _scanned![i].encoded,
                      subtitle: l.printerConnectionWifi,
                      isSelected:
                          widget.savedAddress == _scanned![i].encoded &&
                          widget.savedConnection == PrinterConnection.network,
                      onTap: () {
                        _ip.text = _scanned![i].host;
                        _port.text = '${_scanned![i].port}';
                        widget.onSave(
                          address: _scanned![i].encoded,
                          name: _scanned![i].encoded,
                          connection: PrinterConnection.network,
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: AppTheme.space5),
          Text(
            l.printerWifiManualHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _ip,
            keyboardType: TextInputType.text,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l.printerWifiIpLabel,
              hintText: '192.168.1.100',
            ),
          ),
          const SizedBox(height: AppTheme.space2),
          TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: l.printerWifiPortLabel),
          ),
          const SizedBox(height: AppTheme.space3),
          FilledButton(
            onPressed: _saveWifiPrinter,
            child: Text(l.printerWifiUse),
          ),
        ],
        if (connection == PrinterConnection.usb) ...[
          const SizedBox(height: AppTheme.space4),
          SectionHeader(
            title: l.printerConnectionUsb,
            trailing: TextButton.icon(
              onPressed: _loadingUsb ? null : _loadUsbPrinters,
              icon: _loadingUsb
                  ? const ButtonSpinner(size: 16)
                  : const Icon(Icons.refresh),
              label: Text(l.printerUsbRefresh),
            ),
          ),
          Text(l.printerUsbHint, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppTheme.space3),
          if (_usbPrinters != null && _usbPrinters!.isEmpty)
            EmptyStateView(icon: Icons.usb, title: l.printerUsbNoneFound)
          else if (_usbPrinters != null)
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < _usbPrinters!.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _PairedDeviceTile(
                      icon: Icons.usb,
                      title: _usbPrinters![i].name,
                      subtitle: l.printerConnectionUsb,
                      isSelected:
                          widget.savedAddress == _usbPrinters![i].name &&
                          widget.savedConnection == PrinterConnection.usb,
                      onTap: () => widget.onSave(
                        address: _usbPrinters![i].name,
                        name: _usbPrinters![i].name,
                        connection: PrinterConnection.usb,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _PairedDeviceTile extends StatelessWidget {
  const _PairedDeviceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: IconAvatar(
        icon: icon,
        tone: isSelected ? StatusTone.positive : null,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      selected: isSelected,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      trailing: isSelected
          ? Icon(Icons.check_circle, color: AppColors.of(context).success)
          : null,
      onTap: onTap,
    );
  }
}
