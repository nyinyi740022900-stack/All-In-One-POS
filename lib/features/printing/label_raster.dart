import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

import 'receipt_raster.dart' show paragraph;

/// Renders just the product name to a monochrome-friendly bitmap sized to
/// [widthDots]. Price and barcode are ASCII-only (money is always formatted
/// with the Latin 'Ks' symbol, and barcode values are alphanumeric), so they
/// print fine as native printer commands — only the name may contain Myanmar
/// text and needs the same raster workaround as the receipt header.
Future<img.Image> renderLabelNameImage(
  String name,
  int widthDots, {
  double fontSize = 26,
}) async {
  final para = paragraph(name, widthDots,
      fontSize: fontSize, bold: true, align: ui.TextAlign.center);

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
  canvas.drawParagraph(para, const ui.Offset(0, 4));

  final height = (para.height + 8).ceil();
  final picture = recorder.endRecording();
  final uiImage = await picture.toImage(widthDots, height);
  final bytes = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
  uiImage.dispose();

  return img.Image.fromBytes(
    width: widthDots,
    height: height,
    bytes: bytes!.buffer,
    numChannels: 4,
  );
}
