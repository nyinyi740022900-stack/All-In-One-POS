import 'dart:ui' as ui;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart' as esc;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../invoices/receipt_data.dart';
import '../invoices/receipt_formatter.dart';
import '../invoices/sales_report_data.dart';
import '../invoices/sales_report_formatter.dart';
import 'label_data.dart';
import 'label_raster.dart';
import 'network_transport.dart';
import 'printer_connection.dart';
import 'receipt_raster.dart';
import 'tspl.dart';
import 'usb_transport.dart';

export 'printer_connection.dart' show PrintResult, PrinterConnection;

class BtDevice {
  final String name;
  final String mac;
  const BtDevice(this.name, this.mac);
}

/// ESC/POS monochrome raster packing is a per-pixel Dart loop across the
/// whole receipt/report bitmap — pure CPU work that used to run inline on
/// the UI isolate and janked the till for the duration of a print (audit
/// M6). Runs on a background isolate; the capability profile is loaded on
/// the caller (it fetches an asset) and shipped into the worker.
List<int> _packEscPosRaster(
  (img.Image, esc.CapabilityProfile, esc.PaperSize) args,
) {
  final (image, profile, paperSize) = args;
  return esc.Generator(paperSize, profile).imageRaster(image);
}

/// TSPL packing has the same per-pixel BITMAP loop — see
/// [_packEscPosRaster].
List<int> _packTsplLabel(
  (img.Image, String, String, LabelSize, int) args,
) {
  final (nameImage, priceText, barcodeValue, size, copies) = args;
  return buildTsplLabelBytes(
    nameImage: nameImage,
    priceText: priceText,
    barcodeValue: barcodeValue,
    size: size,
    copies: copies,
  );
}

/// Builds ESC/POS (or TSPL) bytes, then hands them to whichever transport
/// this device is using: Bluetooth (phones), Wi-Fi TCP 9100 (phones + PCs),
/// or USB RAW via the Windows spooler (shop PCs).
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

  /// Writes already-built bytes over the configured transport. Byte
  /// generation stays transport-agnostic so a Wi-Fi printer gets the same
  /// Myanmar-safe raster a Bluetooth printer always did.
  Future<PrintResult> _send(
    List<int> bytes, {
    required String address,
    required PrinterConnection connection,
  }) async {
    switch (connection) {
      case PrinterConnection.bluetooth:
        if (!await _ensureConnected(address)) {
          return const PrintResult(false, 'connect_failed');
        }
        final ok = await PrintBluetoothThermal.writeBytes(bytes);
        return PrintResult(ok, ok ? null : 'write_failed');
      case PrinterConnection.network:
        return sendNetworkBytes(bytes, address);
      case PrinterConnection.usb:
        return sendUsbBytes(bytes, address);
    }
  }

  /// Best-effort: downloads and decodes the shop's logo for the receipt
  /// header. Never throws — a network failure or bad image just means the
  /// receipt prints without a logo, not that printing fails.
  Future<ui.Image?> _fetchLogo(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
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
    bytes.addAll(await compute(
        _packEscPosRaster,
        (
          image,
          profile,
          paper == PaperSize.mm80 ? esc.PaperSize.mm80 : esc.PaperSize.mm58,
        )));
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
    PrinterConnection connection = PrinterConnection.bluetooth,
  }) async {
    try {
      final bytes = await buildBytes(data, paper: paper, labels: labels);
      return _send(bytes, address: mac, connection: connection);
    } catch (e) {
      return PrintResult(false, e.toString());
    }
  }

  /// Builds the ESC/POS byte stream for a date-range sales report (raster
  /// image + cut, no barcode — a report isn't a single scannable document).
  Future<List<int>> buildReportBytes(
    SalesReport report,
    String shopName, {
    required PaperSize paper,
    required String title,
    required String dateRangeLabel,
    required String totalLabel,
    required String noSalesLabel,
  }) async {
    final bodyLines = SalesReportFormatter(paper: paper).format(
      report,
      title: title,
      dateRangeLabel: dateRangeLabel,
      totalLabel: totalLabel,
      noSalesLabel: noSalesLabel,
    );
    final image = await renderReportImage(shopName, bodyLines, paper);

    final profile = await esc.CapabilityProfile.load();
    final generator = esc.Generator(
      paper == PaperSize.mm80 ? esc.PaperSize.mm80 : esc.PaperSize.mm58,
      profile,
    );

    final bytes = <int>[];
    bytes.addAll(await compute(
        _packEscPosRaster,
        (
          image,
          profile,
          paper == PaperSize.mm80 ? esc.PaperSize.mm80 : esc.PaperSize.mm58,
        )));
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());
    return bytes;
  }

  Future<PrintResult> printReport(
    SalesReport report,
    String shopName, {
    required PaperSize paper,
    required String mac,
    required String title,
    required String dateRangeLabel,
    required String totalLabel,
    required String noSalesLabel,
    PrinterConnection connection = PrinterConnection.bluetooth,
  }) async {
    try {
      final bytes = await buildReportBytes(
        report,
        shopName,
        paper: paper,
        title: title,
        dateRangeLabel: dateRangeLabel,
        totalLabel: totalLabel,
        noSalesLabel: noSalesLabel,
      );
      return _send(bytes, address: mac, connection: connection);
    } catch (e) {
      return PrintResult(false, e.toString());
    }
  }

  // ---- End-of-day (Z-report) summaries ---------------------------------
  //
  // Takes already-formatted lines (e.g. from `CashSessionReportFormatter`)
  // rather than a specific report type — `renderReportImage` only needs a
  // shop name + body lines, so this stays generic instead of coupling the
  // printing layer to the cash-session feature.

  Future<List<int>> buildZReportBytes(
    List<String> bodyLines,
    String shopName, {
    required PaperSize paper,
  }) async {
    final image = await renderReportImage(shopName, bodyLines, paper);

    final profile = await esc.CapabilityProfile.load();
    final generator = esc.Generator(
      paper == PaperSize.mm80 ? esc.PaperSize.mm80 : esc.PaperSize.mm58,
      profile,
    );

    final bytes = <int>[];
    bytes.addAll(await compute(
        _packEscPosRaster,
        (
          image,
          profile,
          paper == PaperSize.mm80 ? esc.PaperSize.mm80 : esc.PaperSize.mm58,
        )));
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());
    return bytes;
  }

  Future<PrintResult> printZReport(
    List<String> bodyLines,
    String shopName, {
    required PaperSize paper,
    required String mac,
    PrinterConnection connection = PrinterConnection.bluetooth,
  }) async {
    try {
      final bytes = await buildZReportBytes(bodyLines, shopName, paper: paper);
      return _send(bytes, address: mac, connection: connection);
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
  //    printer (different protocol than ESC/POS). Same Bluetooth / Wi-Fi /
  //    USB transports as the receipt printer.

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

    // Pack the name raster ONCE off-isolate; the copies loop just repeats
    // the already-packed bytes (audit M6).
    final packedName = await compute(
        _packEscPosRaster,
        (
          nameImage,
          profile,
          paper == PaperSize.mm80 ? esc.PaperSize.mm80 : esc.PaperSize.mm58,
        ));

    final chars = data.barcode.split('');
    final bytes = <int>[];
    for (var i = 0; i < copies; i++) {
      bytes.addAll(packedName);
      bytes.addAll(
        generator.text(
          data.priceText,
          styles: const esc.PosStyles(
            align: esc.PosAlign.center,
            bold: true,
            height: esc.PosTextSize.size2,
            width: esc.PosTextSize.size2,
          ),
        ),
      );
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
    PrinterConnection connection = PrinterConnection.bluetooth,
  }) async {
    try {
      final bytes = await buildLabelBytes(data, paper: paper, copies: copies);
      return _send(bytes, address: mac, connection: connection);
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
    return compute(_packTsplLabel,
        (nameImage, data.priceText, data.barcode, size, copies));
  }

  Future<PrintResult> printTsplLabel(
    LabelData data, {
    required LabelSize size,
    required String mac,
    int copies = 1,
    PrinterConnection connection = PrinterConnection.bluetooth,
  }) async {
    try {
      final bytes = await buildTsplBytes(data, size: size, copies: copies);
      return _send(bytes, address: mac, connection: connection);
    } catch (e) {
      return PrintResult(false, e.toString());
    }
  }
}
