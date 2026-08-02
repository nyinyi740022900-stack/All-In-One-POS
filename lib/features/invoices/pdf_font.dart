import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

/// Loads the bundled Myanmar-capable font for PDF documents. The `pdf`
/// package's default font has no Myanmar glyphs — Burmese text (a customer
/// name, an address, a localized column label) renders as tofu boxes
/// otherwise, unlike Flutter's own text engine (used by the thermal
/// printer's raster path), which gets Myanmar for free from the OS. Cached
/// module-level since every PDF export needs the same font.
pw.Font? _regular;
pw.Font? _bold;

Future<({pw.Font regular, pw.Font bold})> loadMyanmarPdfFont() async {
  _regular ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansMyanmar-Regular.ttf'));
  _bold ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansMyanmar-Bold.ttf'));
  return (regular: _regular!, bold: _bold!);
}
