import 'printer_connection.dart';

class UsbPrinterInfo {
  final String name;
  const UsbPrinterInfo(this.name);
}

Future<List<UsbPrinterInfo>> listUsbPrinters() async => const [];

Future<PrintResult> sendUsbBytes(List<int> bytes, String printerName) async =>
    const PrintResult(false, 'usb_unsupported');
