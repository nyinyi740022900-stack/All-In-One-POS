/// Paper width for thermal printers.
enum PaperSize {
  mm58(chars: 32, dots: 384),
  mm80(chars: 48, dots: 576);

  const PaperSize({required this.chars, required this.dots});

  /// Characters per line in monospace text mode.
  final int chars;

  /// Horizontal dots (pixels) for raster/image printing.
  final int dots;
}

/// Page size for a real (A4/A5) document export — a real printer or a
/// browser's print dialog, unlike [PaperSize]'s narrow thermal rolls. Some
/// shops print invoices/reports on a WiFi/AirPrint or computer-attached
/// printer loaded with A5 rather than the more common A4.
enum PdfPaperSize { a4, a5 }

/// Best-effort guess at a newly-paired Bluetooth printer's paper width from
/// its OS-reported device name — the Bluetooth pairing API this app uses
/// exposes no real capability/model descriptor (no vendor id, no paper-width
/// field), only that name string, so this is a heuristic suggestion to
/// pre-select in the UI, never a substitute for the owner's own confirm.
/// Returns null when the name gives no signal either way, so the caller can
/// fall back to its own existing default rather than guessing wrong with
/// false confidence.
PaperSize? suggestPaperSizeFromDeviceName(String name) {
  final n = name.toLowerCase();
  if (n.contains('80')) return PaperSize.mm80;
  if (n.contains('58') || n.contains('57') || n.contains('56')) {
    return PaperSize.mm58;
  }
  return null;
}

/// A line item's own discount, recovered from what's already stored rather
/// than needing its own column — `SaleItems.lineTotal` is written as
/// `unitPrice * qty - lineDiscount` at sale time (see
/// `CartState.lineTotalFor`), so the difference is exactly the discount.
/// Never negative (a line total can't exceed unitPrice * qty).
int lineDiscountOf({required int unitPrice, required int qty, required int lineTotal}) {
  final d = unitPrice * qty - lineTotal;
  return d > 0 ? d : 0;
}

class ReceiptLineItem {
  final String name;
  final int qty;
  final int unitPrice;
  final int lineTotal;

  const ReceiptLineItem({
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.lineTotal,
  });
}

/// Everything needed to render a receipt, decoupled from DB rows so the
/// formatter and printer never touch Drift types directly.
class ReceiptData {
  final String shopName;
  final String? address;
  final String? phone;
  final String? logoUrl;
  final String invoiceNo;
  final DateTime dateTime;
  final String? cashier;
  final String? customerName;
  final String? customerPhone;
  final String? deliveryAddress;
  final List<ReceiptLineItem> items;
  final int subtotal;
  final int discount;
  final int total;
  final int paid;
  final int change;
  final String paymentMethod;
  final String? footer;

  const ReceiptData({
    required this.shopName,
    this.address,
    this.phone,
    this.logoUrl,
    required this.invoiceNo,
    required this.dateTime,
    this.cashier,
    this.customerName,
    this.customerPhone,
    this.deliveryAddress,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.paid,
    required this.change,
    required this.paymentMethod,
    this.footer,
  });
}
