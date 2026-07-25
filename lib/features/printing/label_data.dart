/// Physical label sizes for dedicated Bluetooth label printers (TSPL
/// gap-detect thermal printers — a different device/protocol than the
/// receipt printer). Dots assume 203dpi (8 dots/mm), the common resolution
/// for these printers.
enum LabelSize {
  mm40x30(widthMm: 40, heightMm: 30),
  mm50x30(widthMm: 50, heightMm: 30),
  mm50x40(widthMm: 50, heightMm: 40);

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
