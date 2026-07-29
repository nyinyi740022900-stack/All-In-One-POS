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
