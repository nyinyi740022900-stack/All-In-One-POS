import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'label_data.dart';

/// Builds TSPL command bytes for a dedicated Bluetooth label printer (a
/// different protocol than the ESC/POS receipt printer — most cheap 40x30/
/// 50x30mm gap-detect label printers speak TSPL, not ESC/POS). TSPL is a
/// plain-ASCII command language with one binary payload (BITMAP); everything
/// else is sent as CRLF-terminated text lines.
///
/// The product name is rasterized (same Myanmar-safe reasoning as the
/// receipt/ESC/POS label — see receipt_raster.dart) and sent via BITMAP;
/// price and barcode value are always ASCII, so they use TSPL's native TEXT
/// and BARCODE commands instead of being rasterized.
List<int> buildTsplLabelBytes({
  required img.Image nameImage,
  required String priceText,
  required String barcodeValue,
  required LabelSize size,
  int copies = 1,
}) {
  final bytes = <int>[];
  void line(String s) => bytes.addAll(ascii.encode('$s\r\n'));

  // Small rolls (30x20mm is only 240x160 dots at 8 dots/mm) can't afford
  // the gaps a 50x40 label has, and a Code128 bar module of 2 dots makes an
  // average barcode WIDER than a 240-dot printable area (122+ modules x 2).
  final small = size.heightDots <= 200;
  final gapAfterName = small ? 4 : 12;
  // TSPL font "3" renders ~24 dots tall.
  const priceHeight = 24;
  final gapBeforeBarcode = small ? 4 : 16;
  final narrowBarDots = size.widthDots >= 360 ? 2 : 1;

  line('SIZE ${size.widthMm} mm,${size.heightMm} mm');
  line('GAP 2 mm,0 mm');
  line('DIRECTION 1');
  line('CLS');

  final widthBytes = (nameImage.width + 7) ~/ 8;
  bytes.addAll(ascii
      .encode('BITMAP 0,4,$widthBytes,${nameImage.height},0,'));
  bytes.addAll(_packMonochrome(nameImage, widthBytes));
  bytes.addAll(ascii.encode('\r\n'));

  final priceY = nameImage.height + 4 + gapAfterName;
  line('TEXT 10,$priceY,"3",0,1,1,"$priceText"');

  final barcodeY = priceY + priceHeight + gapBeforeBarcode;
  final barHeight = size.heightDots - barcodeY - 4;
  if (barcodeValue.length >= 2 && barHeight > 20) {
    line(
      'BARCODE 10,$barcodeY,"128",$barHeight,1,0,$narrowBarDots,'
      '$narrowBarDots,"$barcodeValue"',
    );
  }

  line('PRINT 1,$copies');
  return bytes;
}

/// Packs an [image] into 1-bit-per-pixel rows (MSB first, 1 = black/print),
/// each row padded to a whole number of bytes — the format TSPL's BITMAP
/// command expects.
Uint8List _packMonochrome(img.Image image, int widthBytes) {
  final out = Uint8List(widthBytes * image.height);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final px = image.getPixel(x, y);
      if (px.luminance < 128) {
        final byteIndex = y * widthBytes + (x >> 3);
        out[byteIndex] |= 0x80 >> (x & 7);
      }
    }
  }
  return out;
}
