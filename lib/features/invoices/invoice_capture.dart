import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Renders [child] off-screen (inside an [Overlay] entry positioned well
/// outside the viewport, so it still lays out and paints normally) and
/// captures it as PNG bytes. Used to turn an on-screen widget (like
/// `InvoiceView`) into a shareable/downloadable image without ever showing
/// the capture surface itself.
Future<Uint8List> captureWidgetAsPng(
  BuildContext context,
  Widget child, {
  double pixelRatio = 2.0,
}) async {
  final key = GlobalKey();
  final overlay = Overlay.of(context, rootOverlay: true);
  // InvoiceView now looks up AppLocalizations. The overlay is usually under
  // MaterialApp already, but Localizations.override copies delegates from
  // the capturing screen so a missing ancestor cannot crash share/download.
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -10000,
      top: 0,
      child: Localizations.override(
        context: context,
        child: Material(
          color: Colors.transparent,
          child: RepaintBoundary(key: key, child: child),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  try {
    // Let the overlay lay out and paint at least one frame before capturing.
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    entry.remove();
  }
}
