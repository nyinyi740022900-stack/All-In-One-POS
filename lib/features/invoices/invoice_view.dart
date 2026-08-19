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
  final int lineTotal;
  const InvoiceItemData(
      {required this.name, required this.qty, required this.lineTotal});
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
  final String paymentStatus; // unpaid | partial | paid
  final String currencySymbol;
  final String? footer;

  const InvoiceData({
    required this.shopName,
    this.shopLogoUrl,
    this.shopPhone,
    this.shopAddress,
    required this.invoiceNo,
    required this.date,
    required this.customerName,
    this.customerPhone,
    this.deliveryAddress,
    this.township,
    required this.items,
    this.deliveryFee = 0,
    this.paymentStatus = 'unpaid',
    this.currencySymbol = 'Ks',
    this.footer,
  });

  int get itemsTotal => items.fold(0, (s, i) => s + i.lineTotal);
  int get total => itemsTotal + deliveryFee;
}

/// A polished, self-contained invoice card. Fixed-width so it captures
/// consistently as an image regardless of the surrounding layout/theme —
/// hardcoded light colors so it reads like a real printed document even on a
/// dark-mode device.
class InvoiceView extends StatelessWidget {
  const InvoiceView({super.key, required this.data, this.width = 380});
  final InvoiceData data;
  final double width;

  static const _accent = Color(0xFF6C4AB6);
  static const _muted = Color(0xFF8A8398);
  static const _line = Color(0xFFEDEAF3);
  static final _money = NumberFormat('#,##0', 'en_US');
  String _amt(int v) => '${_money.format(v)} ${data.currencySymbol}';

  @override
  Widget build(BuildContext context) {
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
          _titleRow(context),
          const SizedBox(height: 14),
          const Divider(height: 1, color: _line),
          const SizedBox(height: 14),
          _billTo(),
          const SizedBox(height: 14),
          const Divider(height: 1, color: _line),
          const SizedBox(height: 10),
          _itemsTable(),
          const SizedBox(height: 10),
          const Divider(height: 1, color: _line),
          const SizedBox(height: 10),
          _totals(),
          const SizedBox(height: 16),
          _barcode(),
          if ((data.footer ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(data.footer!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: _muted)),
          ],
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(
            color: Color(0xFFF3F0FA),
            shape: BoxShape.circle,
          ),
          child: (data.shopLogoUrl ?? '').isEmpty
              ? const Icon(Icons.storefront, color: _accent)
              : Image.network(data.shopLogoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.storefront, color: _accent)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(data.shopName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black)),
              if ((data.shopPhone ?? '').isNotEmpty ||
                  (data.shopAddress ?? '').isNotEmpty)
                Text(
                  [data.shopPhone, data.shopAddress]
                      .where((s) => (s ?? '').isNotEmpty)
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _titleRow(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('INVOICE',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: _accent)),
            const Spacer(),
            _paymentBadge(context),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data.invoiceNo,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.black)),
            Text(DateFormat('yyyy-MM-dd HH:mm').format(data.date),
                style: const TextStyle(fontSize: 11, color: _muted)),
          ],
        ),
      ],
    );
  }

  Widget _billTo() {
    final lines = [
      data.customerName,
      if ((data.customerPhone ?? '').isNotEmpty) data.customerPhone!,
      if ((data.deliveryAddress ?? '').isNotEmpty) data.deliveryAddress!,
      if ((data.township ?? '').isNotEmpty) data.township!,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('BILL TO',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: _muted)),
        const SizedBox(height: 4),
        for (final l in lines)
          Text(l, style: const TextStyle(fontSize: 13, color: Colors.black)),
      ],
    );
  }

  static const _headStyle =
      TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _muted);
  static const _itemStyle = TextStyle(fontSize: 13, color: Colors.black);

  /// A real ruled grid (outer frame + column/row lines), not just soft
  /// dividers between sections — the standard look a printed business
  /// invoice is expected to have, especially once printed full-size from a
  /// computer rather than viewed as a phone screenshot.
  Widget _itemsTable() {
    const cellPad = EdgeInsets.symmetric(horizontal: 8, vertical: 6);
    return Table(
      border: TableBorder.all(color: _line),
      columnWidths: const {
        0: FlexColumnWidth(5),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(3),
      },
      children: [
        const TableRow(
          decoration: BoxDecoration(color: Color(0xFFF7F5FB)),
          children: [
            Padding(padding: cellPad, child: Text('Item', style: _headStyle)),
            Padding(
                padding: cellPad,
                child: Text('Qty',
                    textAlign: TextAlign.center, style: _headStyle)),
            Padding(
                padding: cellPad,
                child: Text('Total',
                    textAlign: TextAlign.right, style: _headStyle)),
          ],
        ),
        for (final it in data.items)
          TableRow(
            children: [
              Padding(
                  padding: cellPad,
                  child: Text(it.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _itemStyle)),
              Padding(
                  padding: cellPad,
                  child: Text('${it.qty}',
                      textAlign: TextAlign.center, style: _itemStyle)),
              Padding(
                  padding: cellPad,
                  child: Text(_amt(it.lineTotal),
                      textAlign: TextAlign.right, style: _itemStyle)),
            ],
          ),
      ],
    );
  }

  Widget _totals() {
    return Column(
      children: [
        _totalRow('Subtotal', _amt(data.itemsTotal)),
        if (data.deliveryFee > 0)
          _totalRow('Delivery fee', _amt(data.deliveryFee)),
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
              const Text('TOTAL',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
              Text(_amt(data.total),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: _accent)),
            ],
          ),
        ),
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
          Text(value,
              style: const TextStyle(fontSize: 13, color: Colors.black)),
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
  ///
  /// Was `Colors.green` / `Colors.orange` / `Colors.redAccent` at 12% alpha —
  /// three Material defaults that matched nothing else in the product.
  Widget _paymentBadge(BuildContext context) {
    final (label, tone) =
        invoicePaymentStatusDisplay(AppLocalizations.of(context), data.paymentStatus);
    return StatusPill(
      label: label,
      tone: tone,
      palette: AppColors.onLightDocument,
    );
  }
}
