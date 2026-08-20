import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import 'invoice_payment_status.dart';

class InvoiceItemData {
  final String name;
  final int qty;
  final int unitPrice;
  final int lineTotal;
  const InvoiceItemData({
    required this.name,
    required this.qty,
    this.unitPrice = 0,
    required this.lineTotal,
  });
}

/// Everything needed to render a polished, shareable invoice image — distinct
/// from the thermal-printer `ReceiptData` (plain monospace text sized for
/// 58/80mm paper, used only for actual Bluetooth printing). This is a proper
/// visual document meant to be captured as a PNG and shared/downloaded.
class InvoiceData {
  final String shopName;
  final String? shopLogoUrl;
  final String? shopPhone;
  final String? shopAddress;
  final String invoiceNo;
  final DateTime date;
  final String customerName;
  final String? customerPhone;
  final String? deliveryAddress;
  final String? township;
  final List<InvoiceItemData> items;
  final int deliveryFee;
  final int discount;
  final int paid;
  final int changeDue;
  final String paymentStatus; // unpaid | partial | paid
  /// Payment-account / till code (`cash`, `kbzpay`, `transfer`, …).
  final String? paymentMethodCode;
  /// Display name when [paymentMethodCode] is a custom payment-account id.
  final String? paymentMethodCustomName;
  final String? cashier;
  final String currencySymbol;
  final String? footer;

  const InvoiceData({
    required this.shopName,
    this.shopLogoUrl,
    this.shopPhone,
    this.shopAddress,
    required this.invoiceNo,
    required this.date,
    this.customerName = '',
    this.customerPhone,
    this.deliveryAddress,
    this.township,
    required this.items,
    this.deliveryFee = 0,
    this.discount = 0,
    this.paid = 0,
    this.changeDue = 0,
    this.paymentStatus = 'unpaid',
    this.paymentMethodCode,
    this.paymentMethodCustomName,
    this.cashier,
    this.currencySymbol = 'Ks',
    this.footer,
  });

  int get itemsTotal => items.fold(0, (s, i) => s + i.lineTotal);
  int get total => itemsTotal - discount + deliveryFee;
  int get amountDue {
    final due = total - paid;
    return due > 0 ? due : 0;
  }

  bool get hasCustomerDetails {
    bool nonempty(String? s) => (s ?? '').trim().isNotEmpty;
    return nonempty(customerName) ||
        nonempty(customerPhone) ||
        nonempty(deliveryAddress) ||
        nonempty(township);
  }

  /// Delivery street plus township, when either is set.
  String get formattedAddress {
    final parts = <String>[
      if ((deliveryAddress ?? '').trim().isNotEmpty) deliveryAddress!.trim(),
      if ((township ?? '').trim().isNotEmpty) township!.trim(),
    ];
    return parts.join(', ');
  }
}

/// Localized till / wallet name for the invoice document.
String? invoicePaymentMethodLabel(
  AppLocalizations l, {
  String? code,
  String? customName,
}) {
  if (code == null || code.isEmpty) {
    final name = (customName ?? '').trim();
    return name.isEmpty ? null : name;
  }
  if (code == 'transfer') return l.orderPaymentTransfer;
  switch (code) {
    case 'cash':
      return l.paymentCash;
    case 'kbzpay':
      return l.paymentKbzPay;
    case 'wavepay':
      return l.paymentWavePay;
    case 'ayapay':
      return l.paymentAyaPay;
    case 'cbpay':
      return l.paymentCbPay;
    case 'credit':
      return l.paymentCredit;
    case 'cod':
      return l.paymentCod;
  }
  final name = (customName ?? '').trim();
  return name.isEmpty ? code : name;
}

/// A polished, self-contained invoice card. Fixed-width so it captures
/// consistently as an image regardless of the surrounding layout/theme —
/// hardcoded light colors so it reads like a real printed document even on a
/// dark-mode device.
class InvoiceView extends StatelessWidget {
  const InvoiceView({super.key, required this.data, this.width = 380});
  final InvoiceData data;
  final double width;

  /// Same forest green as [AppTheme] light primary (`#0F5C3E`).
  static const _accent = Color(0xFF0F5C3E);
  static const _muted = Color(0xFF5C6B64);
  static const _line = Color(0xFFDCE6E0);
  static final _money = NumberFormat('#,##0', 'en_US');
  String _amt(int v) => '${_money.format(v)} ${data.currencySymbol}';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final method = invoicePaymentMethodLabel(
      l,
      code: data.paymentMethodCode,
      customName: data.paymentMethodCustomName,
    );
    final footer = (data.footer ?? '').trim().isNotEmpty
        ? data.footer!.trim()
        : l.receiptThankYou;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: 16),
          const Divider(height: 1, color: _line),
          const SizedBox(height: 14),
          _titleRow(context, l),
          const SizedBox(height: 14),
          const Divider(height: 1, color: _line),
          if (data.hasCustomerDetails) ...[
            const SizedBox(height: 14),
            _customerBlock(l),
            const SizedBox(height: 14),
            const Divider(height: 1, color: _line),
          ],
          const SizedBox(height: 10),
          _itemsTable(l),
          const SizedBox(height: 10),
          const Divider(height: 1, color: _line),
          const SizedBox(height: 10),
          _totals(l, method),
          const SizedBox(height: 16),
          _barcode(),
          const SizedBox(height: 16),
          Text(
            footer,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(
            color: Color(0xFFEEF5F1),
            shape: BoxShape.circle,
          ),
          child: (data.shopLogoUrl ?? '').isEmpty
              ? const Icon(Icons.storefront, color: _accent)
              : Image.network(
                  data.shopLogoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.storefront, color: _accent),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.shopName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              if ((data.shopPhone ?? '').isNotEmpty)
                Text(
                  data.shopPhone!,
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
              if ((data.shopAddress ?? '').isNotEmpty)
                Text(
                  data.shopAddress!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _titleRow(BuildContext context, AppLocalizations l) {
    final cashier = (data.cashier ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.receiptInvoice.toUpperCase(),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: _accent,
              ),
            ),
            const Spacer(),
            _paymentBadge(context),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.invoiceNo,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            Text(
              DateFormat('yyyy-MM-dd HH:mm').format(data.date),
              style: const TextStyle(fontSize: 11, color: _muted),
            ),
          ],
        ),
        if (cashier.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '${l.receiptCashier}: $cashier',
            style: const TextStyle(fontSize: 11, color: _muted),
          ),
        ],
      ],
    );
  }

  Widget _customerBlock(AppLocalizations l) {
    final name = data.customerName.trim();
    final phone = (data.customerPhone ?? '').trim();
    final address = data.formattedAddress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (name.isNotEmpty) _labeled(l.invoiceCustomerName, name),
        if (phone.isNotEmpty) _labeled(l.invoicePhoneNumber, phone),
        if (address.isNotEmpty) _labeled(l.invoiceAddress, address),
      ],
    );
  }

  Widget _labeled(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label - ',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _muted,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontSize: 13, color: Colors.black),
            ),
          ],
        ),
      ),
    );
  }

  static const _headStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.bold,
    color: _muted,
  );
  static const _itemStyle = TextStyle(fontSize: 13, color: Colors.black);

  Widget _itemsTable(AppLocalizations l) {
    const cellPad = EdgeInsets.symmetric(horizontal: 6, vertical: 6);
    return Table(
      border: TableBorder.all(color: _line),
      columnWidths: const {
        0: FlexColumnWidth(4.2),
        1: FlexColumnWidth(1.4),
        2: FlexColumnWidth(2.2),
        3: FlexColumnWidth(2.4),
      },
      children: [
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFF3F7F5)),
          children: [
            Padding(
              padding: cellPad,
              child: Text(l.invoiceColItem, style: _headStyle),
            ),
            Padding(
              padding: cellPad,
              child: Text(
                l.invoiceColQty,
                textAlign: TextAlign.center,
                style: _headStyle,
              ),
            ),
            Padding(
              padding: cellPad,
              child: Text(
                l.invoiceColPrice,
                textAlign: TextAlign.right,
                style: _headStyle,
              ),
            ),
            Padding(
              padding: cellPad,
              child: Text(
                l.commonTotal,
                textAlign: TextAlign.right,
                style: _headStyle,
              ),
            ),
          ],
        ),
        for (final it in data.items)
          TableRow(
            children: [
              Padding(
                padding: cellPad,
                child: Text(
                  it.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _itemStyle,
                ),
              ),
              Padding(
                padding: cellPad,
                child: Text(
                  '${it.qty}',
                  textAlign: TextAlign.center,
                  style: _itemStyle,
                ),
              ),
              Padding(
                padding: cellPad,
                child: Text(
                  _amt(_unitPrice(it)),
                  textAlign: TextAlign.right,
                  style: _itemStyle,
                ),
              ),
              Padding(
                padding: cellPad,
                child: Text(
                  _amt(it.lineTotal),
                  textAlign: TextAlign.right,
                  style: _itemStyle,
                ),
              ),
            ],
          ),
      ],
    );
  }

  int _unitPrice(InvoiceItemData it) {
    if (it.unitPrice != 0) return it.unitPrice;
    if (it.qty == 0) return 0;
    return it.lineTotal ~/ it.qty;
  }

  Widget _totals(AppLocalizations l, String? method) {
    return Column(
      children: [
        _totalRow(l.invoiceItemsAmount, _amt(data.itemsTotal)),
        if (data.discount > 0)
          _totalRow(l.sellDiscount, '-${_amt(data.discount)}'),
        if (data.deliveryFee > 0)
          _totalRow(l.orderDeliveryFee, _amt(data.deliveryFee)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l.commonTotal.toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              Text(
                _amt(data.total),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: _accent,
                ),
              ),
            ],
          ),
        ),
        if (method != null) ...[
          const SizedBox(height: 8),
          _totalRow(l.sellPaymentMethod, method),
        ],
        if (data.paid > 0) _totalRow(l.sellAmountPaid, _amt(data.paid)),
        if (data.changeDue > 0) _totalRow(l.sellChange, _amt(data.changeDue)),
        if (data.amountDue > 0)
          _totalRow(l.invoiceAmountDue, _amt(data.amountDue)),
      ],
    );
  }

  Widget _totalRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: _muted)),
          Text(
            value,
            style: const TextStyle(fontSize: 13, color: Colors.black),
          ),
        ],
      ),
    );
  }

  /// Matches the same Code128-of-the-invoice-number convention already used
  /// on the in-app invoice detail screen and the thermal-printer receipt —
  /// so a paper/screenshot copy of this document can be scanned straight
  /// back to its record in Invoices, not just read by eye.
  Widget _barcode() {
    return Center(
      child: BarcodeWidget(
        barcode: Barcode.code128(),
        data: data.invoiceNo,
        width: 200,
        height: 56,
        drawText: true,
        style: const TextStyle(fontSize: 11, color: Colors.black),
      ),
    );
  }

  /// The one place this document reads the app's palette — and it reads the
  /// **light** one explicitly ([AppColors.onLightDocument]), not
  /// `AppColors.of(context)`. This card is captured to PNG from inside the
  /// live app's Overlay, so a shopkeeper on a dark-mode phone would otherwise
  /// send the customer a white invoice carrying a near-black badge with a
  /// pale-green label on it.
  Widget _paymentBadge(BuildContext context) {
    final (label, tone) = invoicePaymentStatusDisplay(
      AppLocalizations.of(context),
      data.paymentStatus,
    );
    return StatusPill(
      label: label,
      tone: tone,
      palette: AppColors.onLightDocument,
    );
  }
}
