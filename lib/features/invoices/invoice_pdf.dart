import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'invoice_view.dart';

/// Renders the same document as [InvoiceView] onto a real A4 page — used by
/// the Invoices Web companion (and available to the mobile app) wherever a
/// customer/shop wants a document that prints sharp at full size on a
/// computer printer, unlike the fixed-width PNG screenshot [InvoiceView]
/// produces for phone sharing.
Future<Uint8List> buildInvoicePdf(InvoiceData data) async {
  final accent = PdfColor.fromInt(0xFF6C4AB6);
  final muted = PdfColor.fromInt(0xFF8A8398);
  final line = PdfColor.fromInt(0xFFDDD7E8);

  pw.MemoryImage? logo;
  if ((data.shopLogoUrl ?? '').isNotEmpty) {
    try {
      final res = await http.get(Uri.parse(data.shopLogoUrl!));
      if (res.statusCode == 200) logo = pw.MemoryImage(res.bodyBytes);
    } catch (_) {
      // Best-effort — the invoice still prints correctly without a logo.
    }
  }

  String amt(int v) => '${v.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (m) => ',',
      )} ${data.currencySymbol}';

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              children: [
                if (logo != null)
                  pw.ClipOval(
                      child: pw.Image(logo, width: 48, height: 48, fit: pw.BoxFit.cover)),
                if (logo != null) pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(data.shopName,
                          style: pw.TextStyle(
                              fontSize: 20, fontWeight: pw.FontWeight.bold)),
                      if ((data.shopPhone ?? '').isNotEmpty ||
                          (data.shopAddress ?? '').isNotEmpty)
                        pw.Text(
                          [data.shopPhone, data.shopAddress]
                              .where((s) => (s ?? '').isNotEmpty)
                              .join('  ·  '),
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
                pw.Text('INVOICE',
                    style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 1.5,
                        color: accent)),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(data.invoiceNo,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text(
                        '${data.date.year}-${data.date.month.toString().padLeft(2, '0')}-${data.date.day.toString().padLeft(2, '0')} '
                        '${data.date.hour.toString().padLeft(2, '0')}:${data.date.minute.toString().padLeft(2, '0')}',
                        style: pw.TextStyle(fontSize: 10, color: muted)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Divider(color: line, thickness: 1),
            pw.SizedBox(height: 14),
            pw.Text('BILL TO',
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold, color: muted)),
            pw.SizedBox(height: 4),
            pw.Text(data.customerName, style: const pw.TextStyle(fontSize: 12)),
            if ((data.customerPhone ?? '').isNotEmpty)
              pw.Text(data.customerPhone!, style: const pw.TextStyle(fontSize: 12)),
            if ((data.deliveryAddress ?? '').isNotEmpty)
              pw.Text(data.deliveryAddress!, style: const pw.TextStyle(fontSize: 12)),
            if ((data.township ?? '').isNotEmpty)
              pw.Text(data.township!, style: const pw.TextStyle(fontSize: 12)),
            pw.SizedBox(height: 16),
            // Real ruled grid — an outer frame plus column/row lines, matching
            // the standard printed-invoice look this exists to provide.
            pw.Table(
              border: pw.TableBorder.all(color: line),
              columnWidths: const {
                0: pw.FlexColumnWidth(5),
                1: pw.FlexColumnWidth(2),
                2: pw.FlexColumnWidth(3),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF7F5FB)),
                  children: [
                    _cell('Item', bold: true, color: muted),
                    _cell('Qty', bold: true, color: muted, align: pw.TextAlign.center),
                    _cell('Total', bold: true, color: muted, align: pw.TextAlign.right),
                  ],
                ),
                for (final it in data.items)
                  pw.TableRow(children: [
                    _cell(it.name),
                    _cell('${it.qty}', align: pw.TextAlign.center),
                    _cell(amt(it.lineTotal), align: pw.TextAlign.right),
                  ]),
              ],
            ),
            pw.SizedBox(height: 12),
            _totalLine('Subtotal', amt(data.itemsTotal), muted),
            if (data.deliveryFee > 0)
              _totalLine('Delivery fee', amt(data.deliveryFee), muted),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF3EEFA),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text(amt(data.total),
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 14, color: accent)),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(data.paymentStatus.toUpperCase(),
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            ),
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
            if ((data.footer ?? '').isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Center(
                child: pw.Text(data.footer!,
                    style: pw.TextStyle(fontSize: 9, color: muted)),
              ),
            ],
          ],
        );
      },
    ),
  );
  return doc.save();
}

pw.Widget _cell(String text,
    {bool bold = false, PdfColor? color, pw.TextAlign align = pw.TextAlign.left}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: pw.Text(text,
        textAlign: align,
        style: pw.TextStyle(
            fontSize: 10,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color)),
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
