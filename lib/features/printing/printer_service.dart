import 'dart:ui' as ui;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart' as esc;
import 'package:http/http.dart' as http;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../invoices/receipt_data.dart';
import '../invoices/receipt_formatter.dart';
import 'label_data.dart';
import 'label_raster.dart';
import 'receipt_raster.dart';
import 'tspl.dart';

class BtDevice {
  final String name;
  final String mac;
  const BtDevice(this.name, this.mac);
}

class PrintResult {
  final bool ok;
  final String? error;
  const PrintResult(this.ok, [this.error]);
}

/// Wraps the Bluetooth thermal printer. Discovery/connect/write are all
/// hardware operations and require a real paired printer to fully exercise;
/// the byte generation (raster) is deterministic and reused for a test print.
class PrinterService {
  Future<bool> get bluetoothEnabled => PrintBluetoothThermal.bluetoothEnabled;

  Future<bool> get isConnected => PrintBluetoothThermal.connectionStatus;

  Future<List<BtDevice>> pairedDevices() async {
    final list = await PrintBluetoothThermal.pairedBluetooths;
    return list
        .map((b) => BtDevice(b.name, b.macAdress))
        .toList(growable: false);
  }

  Future<bool> connect(String mac) {
    return PrintBluetoothThermal.connect(macPrinterAddress: mac);
  }

  Future<void> disconnect() => PrintBluetoothThermal.disconnect;

  // Tracks which mac we last connected to — a shop may have both a receipt
  // printer and a separate dedicated label printer, so `isConnected` alone
  // (a bare bool, no mac) isn't enough to tell whether we're already talking
  // to the *right* device before writing bytes to it.
  String? _connectedMac;

  /// Ensures a connection to [mac], (re)connecting if needed.
  Future<bool> _ensureConnected(String mac) async {
    if (_connectedMac == mac && await isConnected) return true;
    final ok = await connect(mac);
    if (ok) _connectedMac = mac;
    return ok;
  }

  /// Best-effort: downloads and decodes the shop's logo for the receipt
  /// header. Never throws — a network failure or bad image just means the
  /// receipt prints without a logo, not that printing fails.
  Future<ui.Image?> _fetchLogo(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final res = await http.get(Uri.parse(url)).timeout(
            const Duration(seconds: 5),
          );
      if (res.statusCode != 200) return null;
      return decodeLogoImage(res.bodyBytes);
    } catch (_) {
      return null;
    }
  }

  /// Builds the ESC/POS byte stream for a receipt (raster image + cut).
  Future<List<int>> buildBytes(
    ReceiptData data, {
    required PaperSize paper,
    required ReceiptLabels labels,
  }) async {
    final bodyLines = ReceiptFormatter(
      paper: paper,
      labels: labels,
      // Always the ASCII 'Ks' on receipts so money columns stay aligned even
      // when the UI language is Burmese.
      currencySymbol: 'Ks',
    ).format(data, includeHeader: false);

    final logo = await _fetchLogo(data.logoUrl);
    final image = await renderReceiptImage(data, bodyLines, paper, logo: logo);

    final profile = await esc.CapabilityProfile.load();
    final generator = esc.Generator(
      paper == PaperSize.mm80 ? esc.PaperSize.mm80 : esc.PaperSize.mm58,
      profile,
    );

    final bytes = <int>[];
    bytes.addAll(generator.imageRaster(image));
    bytes.addAll(generator.feed(1));
    // Code128 handles the hyphenated alphanumeric invoice/refund numbers
    // (e.g. INV-20260722-001) that CODE39/EAN/ITF can't cleanly encode.
    final chars = data.invoiceNo.split('');
    if (chars.length >= 2) {
      bytes.addAll(generator.barcode(esc.Barcode.code128(chars)));
    }
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());
    return bytes;
  }

  Future<PrintResult> printReceipt(
    ReceiptData data, {
    required PaperSize paper,
    required String mac,
    required ReceiptLabels labels,
  }) async {
    try {
      if (!await _ensureConnected(mac)) {
        return const PrintResult(false, 'connect_failed');
      }
      final bytes = await buildBytes(data, paper: paper, labels: labels);
      final ok = await PrintBluetoothThermal.writeBytes(bytes);
      return PrintResult(ok, ok ? null : 'write_failed');
    } catch (e) {
      return PrintResult(false, e.toString());
    }
  }

  // ---- Product labels -------------------------------------------------
  //
  // Two ways to print a product's barcode label, both reusing the
  // Myanmar-safe raster trick above for the name only (price/barcode are
  // always ASCII, so they use each protocol's native text/barcode commands):
  //  - buildLabelBytes / printLabel: a strip on the existing ESC/POS receipt
  //    printer — no new hardware, but not a real adhesive sticker.
  //  - buildTsplBytes / printTsplLabel: a dedicated TSPL gap-detect label
  //    printer (a different protocol/device than the receipt printer).

  /// Builds ESC/POS bytes for [copies] repeats of one product label, printed
  /// as a strip on the existing receipt printer.
  Future<List<int>> buildLabelBytes(
    LabelData data, {
    required PaperSize paper,
    int copies = 1,
  }) async {
    final nameImage = await renderLabelNameImage(data.name, paper.dots);

    final profile = await esc.CapabilityProfile.load();
    final generator = esc.Generator(
      paper == PaperSize.mm80 ? esc.PaperSize.mm80 : esc.PaperSize.mm58,
      profile,
    );

    final chars = data.barcode.split('');
    final bytes = <int>[];
    for (var i = 0; i < copies; i++) {
      bytes.addAll(generator.imageRaster(nameImage));
      bytes.addAll(generator.text(
        data.priceText,
        styles: const esc.PosStyles(
          align: esc.PosAlign.center,
          bold: true,
          height: esc.PosTextSize.size2,
          width: esc.PosTextSize.size2,
        ),
      ));
      if (chars.length >= 2) {
        bytes.addAll(generator.barcode(esc.Barcode.code128(chars)));
      }
      bytes.addAll(generator.feed(2));
      bytes.addAll(generator.cut());
    }
    return bytes;
  }

  Future<PrintResult> printLabel(
    LabelData data, {
    required PaperSize paper,
    required String mac,
    int copies = 1,
  }) async {
    try {
      if (!await _ensureConnected(mac)) {
        return const PrintResult(false, 'connect_failed');
      }
      final bytes = await buildLabelBytes(data, paper: paper, copies: copies);
      final ok = await PrintBluetoothThermal.writeBytes(bytes);
      return PrintResult(ok, ok ? null : 'write_failed');
    } catch (e) {
      return PrintResult(false, e.toString());
    }
  }

  /// Builds TSPL bytes for [copies] of one product label on a dedicated
  /// label printer of physical [size].
  Future<List<int>> buildTsplBytes(
    LabelData data, {
    required LabelSize size,
    int copies = 1,
  }) async {
    final nameImage = await renderLabelNameImage(
      data.name,
      size.widthDots,
      fontSize: 20,
    );
    return buildTsplLabelBytes(
      nameImage: nameImage,
      priceText: data.priceText,
      barcodeValue: data.barcode,
      size: size,
      copies: copies,
    );
  }

  Future<PrintResult> printTsplLabel(
    LabelData data, {
    required LabelSize size,
    required String mac,
    int copies = 1,
  }) async {
    try {
      if (!await _ensureConnected(mac)) {
        return const PrintResult(false, 'connect_failed');
      }
      final bytes = await buildTsplBytes(data, size: size, copies: copies);
      final ok = await PrintBluetoothThermal.writeBytes(bytes);
      return PrintResult(ok, ok ? null : 'write_failed');
    } catch (e) {
      return PrintResult(false, e.toString());
    }
  }
}
