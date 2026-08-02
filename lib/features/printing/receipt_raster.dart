import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

import '../invoices/receipt_data.dart';

/// Renders a receipt to a monochrome-friendly bitmap sized to the paper's dot
/// width: an optional logo, a styled shop-info header (bold name, smaller
/// address/phone, all centered), a divider rule, then the monospace [bodyLines]
/// body (produced by `ReceiptFormatter.format(data, includeHeader: false)` so
/// the shop info isn't printed twice).
///
/// WHY raster at all: most cheap Bluetooth thermal printers ship without a
/// Myanmar font, so ESC/POS text mode prints Burmese as boxes. Rendering with
/// Flutter's text engine (which has Noto/Pyidaungsu fallback) guarantees
/// Burmese renders correctly on any printer, and lets a logo image be embedded
/// directly in the same picture.
Future<img.Image> renderReceiptImage(
  ReceiptData data,
  List<String> bodyLines,
  PaperSize paper, {
  ui.Image? logo,
  double fontSize = 22,
}) async {
  final width = paper.dots;
  final nameFontSize = fontSize * 1.35;
  final smallFontSize = fontSize * 0.9;
  const pad = 10.0;
  const logoDisplaySize = 96.0;

  final namePara = paragraph(data.shopName, width,
      fontSize: nameFontSize, bold: true, align: ui.TextAlign.center);

  final contactLines = [
    if ((data.address ?? '').isNotEmpty) data.address!,
    if ((data.phone ?? '').isNotEmpty) data.phone!,
  ];
  final contactPara = contactLines.isEmpty
      ? null
      : paragraph(contactLines.join('\n'), width,
          fontSize: smallFontSize, align: ui.TextAlign.center);

  final bodyPara = paragraph(bodyLines.join('\n'), width,
      fontSize: fontSize, monospace: true, align: ui.TextAlign.left);

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  // White background so the thermal head only burns the dark glyphs.
  canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);

  var y = pad;
  if (logo != null) {
    final srcW = logo.width.toDouble();
    final srcH = logo.height.toDouble();
    final scale = logoDisplaySize / (srcW > srcH ? srcW : srcH);
    final dstW = srcW * scale;
    final dstH = srcH * scale;
    canvas.drawImageRect(
      logo,
      ui.Rect.fromLTWH(0, 0, srcW, srcH),
      ui.Rect.fromLTWH((width - dstW) / 2, y, dstW, dstH),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    y += logoDisplaySize + pad;
  }

  canvas.drawParagraph(namePara, ui.Offset(0, y));
  y += namePara.height;
  if (contactPara != null) {
    y += 2;
    canvas.drawParagraph(contactPara, ui.Offset(0, y));
    y += contactPara.height;
  }

  y += pad;
  canvas.drawLine(
    ui.Offset(0, y),
    ui.Offset(width.toDouble(), y),
    ui.Paint()
      ..color = const ui.Color(0xFF000000)
      ..strokeWidth = 1.5,
  );
  y += pad;

  canvas.drawParagraph(bodyPara, ui.Offset(0, y));
  y += bodyPara.height + pad;

  final totalHeight = y.ceil();
  final picture = recorder.endRecording();
  final uiImage = await picture.toImage(width, totalHeight);
  final bytes =
      await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
  uiImage.dispose();

  return img.Image.fromBytes(
    width: width,
    height: totalHeight,
    bytes: bytes!.buffer,
    numChannels: 4,
  );
}

/// Renders a sales report to a monochrome-friendly bitmap sized to the
/// paper's dot width: shop name header, a divider, then the monospace
/// [bodyLines] (produced by `SalesReportFormatter.format`). Same Myanmar-safe
/// raster rationale as [renderReceiptImage] — see its doc comment.
Future<img.Image> renderReportImage(
  String shopName,
  List<String> bodyLines,
  PaperSize paper, {
  double fontSize = 22,
}) async {
  final width = paper.dots;
  final nameFontSize = fontSize * 1.35;
  const pad = 10.0;

  final namePara = paragraph(shopName, width,
      fontSize: nameFontSize, bold: true, align: ui.TextAlign.center);
  final bodyPara = paragraph(bodyLines.join('\n'), width,
      fontSize: fontSize, monospace: true, align: ui.TextAlign.left);

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);

  var y = pad;
  canvas.drawParagraph(namePara, ui.Offset(0, y));
  y += namePara.height + pad;
  canvas.drawLine(
    ui.Offset(0, y),
    ui.Offset(width.toDouble(), y),
    ui.Paint()
      ..color = const ui.Color(0xFF000000)
      ..strokeWidth = 1.5,
  );
  y += pad;
  canvas.drawParagraph(bodyPara, ui.Offset(0, y));
  y += bodyPara.height + pad;

  final totalHeight = y.ceil();
  final picture = recorder.endRecording();
  final uiImage = await picture.toImage(width, totalHeight);
  final bytes = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
  uiImage.dispose();

  return img.Image.fromBytes(
    width: width,
    height: totalHeight,
    bytes: bytes!.buffer,
    numChannels: 4,
  );
}

/// Lays out a single block of text at a fixed pixel [width]. Shared by every
/// raster renderer (receipt, label) that needs Myanmar-safe text — see the
/// WHY note above on why raw ESC/POS text mode can't be used for this.
ui.Paragraph paragraph(
  String text,
  int width, {
  required double fontSize,
  bool bold = false,
  bool monospace = false,
  ui.TextAlign align = ui.TextAlign.left,
}) {
  final fontFamily = monospace ? 'monospace' : null;
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
    fontFamily: fontFamily,
    fontSize: fontSize,
    fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
    height: 1.25,
    textAlign: align,
  ))
    ..pushStyle(ui.TextStyle(
      color: const ui.Color(0xFF000000),
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
    ))
    ..addText(text);

  return builder.build()
    ..layout(ui.ParagraphConstraints(width: width.toDouble()));
}

/// Decodes raw image bytes (e.g. a downloaded shop logo) into a [ui.Image]
/// ready for [renderReceiptImage]. Returns null on any decode failure —
/// callers should treat a missing/broken logo as "print without it", never
/// as a reason to fail the whole receipt.
Future<ui.Image?> decodeLogoImage(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  } catch (_) {
    return null;
  }
}
