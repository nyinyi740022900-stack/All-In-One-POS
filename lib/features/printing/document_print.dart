import 'dart:typed_data';

import 'package:printing/printing.dart';

/// Opens the OS print dialog with a pre-built PDF so the shop can pick any
/// A4/A5 printer the computer or phone already knows (Wi-Fi office printer,
/// USB cable, AirPrint). Returns false if the user cancels. Thermal
/// 58/80mm receipts stay on [PrinterService] — this path is documents.
Future<bool> printPdfDocument({
  required Uint8List bytes,
  required String name,
}) {
  return Printing.layoutPdf(
    name: name,
    onLayout: (_) async => bytes,
  );
}
