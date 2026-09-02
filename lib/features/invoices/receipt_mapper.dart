import '../../data/local/database.dart';
import '../../data/repositories/settings_repository.dart';
import 'invoice_payment_status.dart';
import 'invoice_view.dart';
import 'receipt_data.dart';

/// Assembles a printable [ReceiptData] from persisted rows + shop profile.
///
/// [paymentMethodLabel] must already be display-ready (e.g. via
/// `paymentLabel(l, sale.paymentMethod)`) — this stays free of AppLocalizations
/// so it's plain, testable data mapping. [defaultFooter] is used when the shop
/// hasn't set a custom receipt footer, so a receipt is never printed with no
/// closing line at all.
ReceiptData receiptFromSale(
  Sale sale,
  List<SaleItem> items,
  ShopProfile shop, {
  required String paymentMethodLabel,
  String? defaultFooter,
  String? cashier,
  Map<String, int>? owedBySaleId,
}) {
  // Credit repayments never mutate the sale row — thread the FIFO
  // allocation so a reprinted thermal receipt reflects what's actually
  // still owed (see outstandingForDisplay).
  final outstanding = outstandingForDisplay(
    total: sale.total,
    paid: sale.paid,
    isRefundRow: sale.refundOfSaleId != null,
    owedBySaleId: owedBySaleId,
    saleId: sale.id,
  );
  final effectivePaid = sale.refundOfSaleId != null
      ? sale.paid
      : (sale.total - outstanding < 0 ? 0 : sale.total - outstanding);
  return ReceiptData(
    shopName: shop.name,
    address: shop.address,
    phone: shop.phone,
    logoUrl: shop.logoUrl,
    invoiceNo: sale.invoiceNo,
    dateTime: sale.finalizedAt,
    cashier: cashier,
    customerName: sale.customerName,
    customerPhone: sale.customerPhone,
    deliveryAddress: sale.deliveryAddress,
    items: items
        .map(
          (i) => ReceiptLineItem(
            name: i.nameSnapshot,
            qty: i.qty,
            unitPrice: i.priceSnapshot,
            lineTotal: i.lineTotal,
          ),
        )
        .toList(),
    subtotal: sale.subtotal,
    discount: sale.discount,
    total: sale.total,
    paid: effectivePaid,
    change: sale.changeDue,
    owed: outstanding,
    paymentMethod: paymentMethodLabel,
    footer: (shop.footer != null && shop.footer!.isNotEmpty)
        ? shop.footer
        : defaultFooter,
  );
}

/// Same fields as the thermal receipt, shaped for the shareable / web
/// [InvoiceView] (PNG, A4 PDF, invoices.allinonepos.app, phone invoice detail).
InvoiceData invoiceDataFromSale(
  Sale sale,
  List<SaleItem> items,
  ShopProfile shop, {
  required String currencySymbol,
  int exponent = 0,
  String? cashier,
  String? paymentMethodCustomName,
  String? defaultFooter,
  Map<String, int>? owedBySaleId,
}) {
  // Same credit-allocation awareness as receiptFromSale: the header pill,
  // share PNG and A4 PDF must all agree with the credit book.
  final isRefund = sale.refundOfSaleId != null;
  final outstanding = outstandingForDisplay(
    total: sale.total,
    paid: sale.paid,
    isRefundRow: isRefund,
    owedBySaleId: owedBySaleId,
    saleId: sale.id,
  );
  final effectivePaid = isRefund
      ? sale.paid
      : (sale.total - outstanding < 0 ? 0 : sale.total - outstanding);
  return InvoiceData(
    shopName: shop.name,
    shopLogoUrl: shop.logoUrl,
    shopPhone: shop.phone,
    shopAddress: shop.address,
    invoiceNo: sale.invoiceNo,
    date: sale.finalizedAt,
    customerName: sale.customerName ?? '',
    customerPhone: sale.customerPhone,
    deliveryAddress: sale.deliveryAddress,
    items: [
      for (final i in items)
        InvoiceItemData(
          name: i.nameSnapshot,
          qty: i.qty,
          unitPrice: i.priceSnapshot,
          lineTotal: i.lineTotal,
        ),
    ],
    discount: sale.discount,
    paid: effectivePaid,
    changeDue: sale.changeDue,
    paymentStatus: invoicePaymentStatusCode(
      paid: effectivePaid,
      total: sale.total,
    ),
    paymentMethodCode: sale.paymentMethod,
    paymentMethodCustomName: paymentMethodCustomName,
    cashier: cashier,
    currencySymbol: currencySymbol,
    exponent: exponent,
    footer: (shop.footer != null && shop.footer!.isNotEmpty)
        ? shop.footer
        : defaultFooter,
  );
}

/// Assembles a printable [ReceiptData] for a social/storefront order (not yet
/// a finalized [Sale]) — used by the order detail sheet's Print action.
ReceiptData receiptFromOrder(
  Order order,
  List<OrderItem> items,
  ShopProfile shop, {
  required String paymentMethodLabel,
  required String deliveryFeeLabel,
  String? defaultFooter,
}) {
  final total = order.itemsTotal + order.deliveryFee;
  return ReceiptData(
    shopName: shop.name,
    address: shop.address,
    phone: shop.phone,
    logoUrl: shop.logoUrl,
    invoiceNo: order.orderNo,
    dateTime: order.createdAt,
    customerName: order.customerName,
    customerPhone: order.customerPhone,
    deliveryAddress: _combinedAddress(order),
    items: [
      for (final it in items)
        ReceiptLineItem(
          name: it.nameSnapshot,
          qty: it.qty,
          unitPrice: it.priceSnapshot,
          lineTotal: it.lineTotal,
        ),
      if (order.deliveryFee > 0)
        ReceiptLineItem(
          name: deliveryFeeLabel,
          qty: 1,
          unitPrice: order.deliveryFee,
          lineTotal: order.deliveryFee,
        ),
    ],
    subtotal: total,
    discount: 0,
    total: total,
    paid: order.paymentStatus == 'paid' ? total : 0,
    change: 0,
    paymentMethod: paymentMethodLabel,
    footer: (shop.footer != null && shop.footer!.isNotEmpty)
        ? shop.footer
        : defaultFooter,
  );
}

/// [Order.deliveryAddress] + [Order.township] combined into one line —
/// null if neither is set. Sales.deliveryAddress is already this combined
/// form (set once, at conversion time — see `OrdersRepository.convertToSale`).
String? _combinedAddress(Order order) {
  final address = (order.deliveryAddress ?? '').trim();
  final township = (order.township ?? '').trim();
  if (address.isEmpty && township.isEmpty) return null;
  if (address.isEmpty) return township;
  if (township.isEmpty) return address;
  return '$address, $township';
}
