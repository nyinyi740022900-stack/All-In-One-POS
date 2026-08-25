/// Physical label sizes for dedicated Bluetooth label printers (TSPL
/// gap-detect thermal printers — a different device/protocol than the
/// receipt printer). Dots assume 203dpi (8 dots/mm), the common resolution
/// for these printers.
///
/// The list covers the sticker rolls actually sold for these printers in
/// Myanmar stationery shops; [tspl.dart] and the raster renderers are fully
/// size-generic, so adding an entry here is all a new roll size needs.
enum LabelSize {
  mm30x20(widthMm: 30, heightMm: 20),
  mm40x30(widthMm: 40, heightMm: 30),
  mm50x30(widthMm: 50, heightMm: 30),
  mm50x40(widthMm: 50, heightMm: 40),
  mm60x40(widthMm: 60, heightMm: 40),
  mm100x50(widthMm: 100, heightMm: 50);

  const LabelSize({required this.widthMm, required this.heightMm});

  final int widthMm;
  final int heightMm;

  static const dotsPerMm = 8;
  int get widthDots => widthMm * dotsPerMm;
  int get heightDots => heightMm * dotsPerMm;
}

/// Everything needed to print one product's label, decoupled from Drift rows.
class LabelData {
  final String name;
  final String priceText;
  final String barcode;

  const LabelData({
    required this.name,
    required this.priceText,
    required this.barcode,
  });
}
