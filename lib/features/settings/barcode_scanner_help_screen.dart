import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';

/// How to use a USB or Bluetooth barcode gun with this app. The gun talks
/// HID keyboard — there is nothing to pair inside the app itself.
class BarcodeScannerHelpScreen extends StatelessWidget {
  const BarcodeScannerHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.scannerSettings)),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.space4),
        children: [
          Text(
            l.scannerSettingsIntro,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppTheme.space4),
          SettingsGroup(
            children: [
              ListTile(
                leading: const IconAvatar(icon: Icons.usb),
                title: Text(l.scannerUsbTitle),
                subtitle: Text(l.scannerUsbBody),
                isThreeLine: true,
              ),
              ListTile(
                leading: const IconAvatar(icon: Icons.bluetooth),
                title: Text(l.scannerBluetoothTitle),
                subtitle: Text(l.scannerBluetoothBody),
                isThreeLine: true,
              ),
              ListTile(
                leading: const IconAvatar(icon: Icons.point_of_sale_outlined),
                title: Text(l.scannerSellTitle),
                subtitle: Text(l.scannerSellBody),
                isThreeLine: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
