import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/money.dart';
import '../../l10n/app_localizations.dart';
import 'invoice_payment_status.dart';
import 'invoice_view.dart';
import 'pdf_font.dart';

/// Renders the same document as [InvoiceView] onto a real A4 page — used by
/// the Invoices Web companion (and available to the mobile app) wherever a
/// customer/shop wants a document that prints sharp at full size on a
/// computer printer, unlike the fixed-width PNG screenshot [InvoiceView]
/// produces for phone sharing.
Future<Uint8List> buildInvoicePdf(
  InvoiceData data,
  AppLocalizations l,
) async {
  final accent = PdfColor.fromInt(0xFF0F5C3E);
  final muted = PdfColor.fromInt(0xFF5C6B64);
  final line = PdfColor.fromInt(0xFFDCE6E0);

  pw.MemoryImage? logo;
  if ((data.shopLogoUrl ?? '').isNotEmpty) {
    try {
      final res = await http.get(Uri.parse(data.shopLogoUrl!));
      if (res.statusCode == 200) logo = pw.MemoryImage(res.bodyBytes);
    } catch (_) {
      // Best-effort — the invoice still prints correctly without a logo.
    }
  }

  String amt(int v) =>
      '${formatMinorUnits(v, exponent: data.exponent)} ${data.currencySymbol}';

  int unitPrice(InvoiceItemData it) {
    if (it.unitPrice != 0) return it.unitPrice;
    if (it.qty == 0) return 0;
    return it.lineTotal ~/ it.qty;
  }

  final method = invoicePaymentMethodLabel(
    l,
    code: data.paymentMethodCode,
    customName: data.paymentMethodCustomName,
  );
  final footer = (data.footer ?? '').trim().isNotEmpty
      ? data.footer!.trim()
      : l.receiptThankYou;
  final (statusLabel, _) = invoicePaymentStatusDisplay(l, data.paymentStatus);
  final cashier = (data.cashier ?? '').trim();

  // Bundled font so a Myanmar customer name/address/item name renders
  // correctly instead of as tofu boxes — the `pdf` package's default font
  // has no Myanmar glyphs.
  final font = await loadMyanmarPdfFont();
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(
      base: font.regular,
      bold: font.bold,
      // Noto Sans Myanmar doesn't cover every symbol (e.g. the date-range
      // arrow "→") — fall back to the bundled Helvetica for anything it's
      // missing rather than a tofu box.
      fontFallback: [pw.Font.helvetica(), pw.Font.helveticaBold()],
    ),
  );
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logo != null)
                  pw.ClipOval(
                    child: pw.Image(
                      logo,
                      width: 48,
                      height: 48,
                      fit: pw.BoxFit.cover,
                    ),
                  ),
                if (logo != null) pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        data.shopName,
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      if ((data.shopPhone ?? '').isNotEmpty)
                        pw.Text(
                          data.shopPhone!,
                          style: pw.TextStyle(fontSize: 10, color: muted),
                        ),
                      if ((data.shopAddress ?? '').isNotEmpty)
                        pw.Text(
                          data.shopAddress!,
                          style: pw.TextStyle(fontSize: 10, color: muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Divider(color: line, thickness: 1),
            pw.SizedBox(height: 14),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      l.receiptInvoice.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: accent,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      statusLabel,
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                        color: accent,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      data.invoiceNo,
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      '${data.date.year}-${data.date.month.toString().padLeft(2, '0')}-${data.date.day.toString().padLeft(2, '0')} '
                      '${data.date.hour.toString().padLeft(2, '0')}:${data.date.minute.toString().padLeft(2, '0')}',
                      style: pw.TextStyle(fontSize: 10, color: muted),
                    ),
                    if (cashier.isNotEmpty)
                      pw.Text(
                        '${l.receiptCashier}: $cashier',
                        style: pw.TextStyle(fontSize: 10, color: muted),
                      ),
                  ],
                ),
              ],
            ),
            if (data.hasCustomerDetails) ...[
              pw.SizedBox(height: 14),
              pw.Divider(color: line, thickness: 1),
              pw.SizedBox(height: 14),
              if (data.customerName.trim().isNotEmpty)
                _labeledLine(
                  l.invoiceCustomerName,
                  data.customerName.trim(),
                  muted,
                ),
              if ((data.customerPhone ?? '').trim().isNotEmpty)
                _labeledLine(
                  l.invoicePhoneNumber,
                  data.customerPhone!.trim(),
                  muted,
                ),
              if (data.formattedAddress.isNotEmpty)
                _labeledLine(l.invoiceAddress, data.formattedAddress, muted),
            ],
            pw.SizedBox(height: 16),
            pw.Table(
              border: pw.TableBorder.all(color: line),
              columnWidths: const {
                0: pw.FlexColumnWidth(4.2),
                1: pw.FlexColumnWidth(1.4),
                2: pw.FlexColumnWidth(2.2),
                3: pw.FlexColumnWidth(2.4),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFF3F7F5),
                  ),
                  children: [
                    _cell(l.invoiceColItem, bold: true, color: muted),
                    _cell(
                      l.invoiceColQty,
                      bold: true,
                      color: muted,
                      align: pw.TextAlign.center,
                    ),
                    _cell(
                      l.invoiceColPrice,
                      bold: true,
                      color: muted,
                      align: pw.TextAlign.right,
                    ),
                    _cell(
                      l.commonTotal,
                      bold: true,
                      color: muted,
                      align: pw.TextAlign.right,
                    ),
                  ],
                ),
                for (final it in data.items)
                  pw.TableRow(
                    children: [
                      _cell(it.name),
                      _cell('${it.qty}', align: pw.TextAlign.center),
                      _cell(amt(unitPrice(it)), align: pw.TextAlign.right),
                      _cell(amt(it.lineTotal), align: pw.TextAlign.right),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 12),
            _totalLine(l.invoiceItemsAmount, amt(data.itemsTotal), muted),
            if (data.discount > 0)
              _totalLine(l.sellDiscount, '-${amt(data.discount)}', muted),
            if (data.deliveryFee > 0)
              _totalLine(l.orderDeliveryFee, amt(data.deliveryFee), muted),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFE8F2EC),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    l.commonTotal.toUpperCase(),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    amt(data.total),
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 14,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
            if (method != null) _totalLine(l.sellPaymentMethod, method, muted),
            if (data.paid > 0) _totalLine(l.sellAmountPaid, amt(data.paid), muted),
            if (data.changeDue > 0)
              _totalLine(l.sellChange, amt(data.changeDue), muted),
            if (data.amountDue > 0)
              _totalLine(l.invoiceAmountDue, amt(data.amountDue), muted),
            pw.SizedBox(height: 20),
            pw.Center(
              child: pw.BarcodeWidget(
                barcode: Barcode.code128(),
                data: data.invoiceNo,
                width: 220,
                height: 60,
                drawText: true,
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Center(
              child: pw.Text(
                footer,
                style: pw.TextStyle(fontSize: 9, color: muted),
              ),
            ),
          ],
        );
      },
    ),
  );
  return doc.save();
}

pw.Widget _cell(
  String text, {
  bool bold = false,
  PdfColor? color,
  pw.TextAlign align = pw.TextAlign.left,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 10,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: color,
      ),
    ),
  );
}

pw.Widget _labeledLine(String label, String value, PdfColor muted) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label - ',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: muted,
            ),
          ),
          pw.TextSpan(
            text: value,
            style: const pw.TextStyle(fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

pw.Widget _totalLine(String label, String value, PdfColor muted) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 10, color: muted)),
        pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
      ],
    ),
  );
}
