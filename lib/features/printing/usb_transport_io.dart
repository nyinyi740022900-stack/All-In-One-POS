import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:windows_printer/windows_printer.dart';

import 'printer_connection.dart';

class UsbPrinterInfo {
  final String name;
  const UsbPrinterInfo(this.name);
}

Future<List<UsbPrinterInfo>> listUsbPrinters() async {
  if (kIsWeb || !Platform.isWindows) return const [];
  try {
    final names = await WindowsPrinter.getAvailablePrinters();
    return [
      for (final name in names)
        if (name.toString().trim().isNotEmpty)
          UsbPrinterInfo(name.toString().trim()),
    ];
  } catch (_) {
    return const [];
  }
}

Future<PrintResult> sendUsbBytes(List<int> bytes, String printerName) async {
  if (kIsWeb || !Platform.isWindows) {
    return const PrintResult(false, 'usb_unsupported');
  }
  if (printerName.trim().isEmpty) {
    return const PrintResult(false, 'invalid_address');
  }
  try {
    await WindowsPrinter.printRawData(
      printerName: printerName,
      data: Uint8List.fromList(bytes),
      useRawDatatype: true,
    );
    return const PrintResult(true);
  } catch (e) {
    return PrintResult(false, e.toString());
  }
}
