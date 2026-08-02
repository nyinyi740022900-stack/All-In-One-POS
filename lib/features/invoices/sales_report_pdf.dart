import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_font.dart';
import 'receipt_data.dart';
import 'sales_report_data.dart';

/// Renders a date-range [SalesReport] onto a real A4/A5 page — for a
/// WiFi/AirPrint printer or a computer's own print dialog, the two cases a
/// Bluetooth thermal printer can't reach. Visually matches [buildInvoicePdf]
/// (same accent/header layout) so an invoice and this report read as the
/// same shop's documents.
Future<Uint8List> buildSalesReportPdf({
  required String shopName,
  String? shopLogoUrl,
  String? shopPhone,
  String? shopAddress,
  required String title,
  required String dateRangeLabel,
  required SalesReport report,
  required String currencySymbol,
  required String invoiceColumnLabel,
  required String dateColumnLabel,
  required String customerColumnLabel,
  required String addressColumnLabel,
  required String amountColumnLabel,
  required String totalLabel,
  required String noSalesLabel,
  PdfPaperSize pageFormat = PdfPaperSize.a4,
}) async {
  final accent = PdfColor.fromInt(0xFF6C4AB6);
  final muted = PdfColor.fromInt(0xFF8A8398);
  final line = PdfColor.fromInt(0xFFDDD7E8);

  pw.MemoryImage? logo;
  if ((shopLogoUrl ?? '').isNotEmpty) {
    try {
      final res = await http.get(Uri.parse(shopLogoUrl!));
      if (res.statusCode == 200) logo = pw.MemoryImage(res.bodyBytes);
    } catch (_) {
      // Best-effort — the report still prints correctly without a logo.
    }
  }

  String amt(int v) {
    final sign = v < 0 ? '-' : '';
    return '$sign${v.abs().toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (m) => ',',
        )} $currencySymbol';
  }

  String dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
    pw.MultiPage(
      pageFormat:
          pageFormat == PdfPaperSize.a5 ? PdfPageFormat.a5 : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      header: (context) {
        if (context.pageNumber > 1) return pw.SizedBox();
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              children: [
                if (logo != null)
                  pw.ClipOval(
                      child: pw.Image(logo,
                          width: 40, height: 40, fit: pw.BoxFit.cover)),
                if (logo != null) pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(shopName,
                          style: pw.TextStyle(
                              fontSize: 18, fontWeight: pw.FontWeight.bold)),
                      if ((shopPhone ?? '').isNotEmpty ||
                          (shopAddress ?? '').isNotEmpty)
                        pw.Text(
                          [shopPhone, shopAddress]
                              .where((s) => (s ?? '').isNotEmpty)
                              .join('  ·  '),
                          style: pw.TextStyle(fontSize: 9, color: muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Divider(color: line, thickness: 1),
            pw.SizedBox(height: 10),
            pw.Text(title,
                style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.2,
                    color: accent)),
            // "→" (as shown on-screen, where Flutter's own text engine
            // renders it fine) has no glyph in either the bundled Myanmar
            // font or the Unicode-less Helvetica fallback — swap it for a
            // plain hyphen here rather than a tofu box.
            pw.Text(dateRangeLabel.replaceAll('→', '-'),
                style: pw.TextStyle(fontSize: 10, color: muted)),
            pw.SizedBox(height: 12),
          ],
        );
      },
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text('${context.pageNumber} / ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: muted)),
      ),
      build: (context) {
        if (report.rows.isEmpty) {
          return [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 24),
              child: pw.Center(
                child: pw.Text(noSalesLabel,
                    style: pw.TextStyle(fontSize: 11, color: muted)),
              ),
            ),
          ];
        }
        return [
          pw.Table(
            border: pw.TableBorder.all(color: line),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(3),
              3: pw.FlexColumnWidth(4),
              4: pw.FlexColumnWidth(3),
            },
            children: [
              pw.TableRow(
                decoration:
                    const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF7F5FB)),
                children: [
                  _cell(invoiceColumnLabel, bold: true, color: muted),
                  _cell(dateColumnLabel, bold: true, color: muted),
                  _cell(customerColumnLabel, bold: true, color: muted),
                  _cell(addressColumnLabel, bold: true, color: muted),
                  _cell(amountColumnLabel,
                      bold: true, color: muted, align: pw.TextAlign.right),
                ],
              ),
              for (final r in report.rows)
                pw.TableRow(children: [
                  _cell(r.invoiceNo),
                  _cell(dateStr(r.date)),
                  _cell(r.customerName),
                  _cell(r.address),
                  _cell(amt(r.amount), align: pw.TextAlign.right),
                ]),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF3EEFA),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(totalLabel.toUpperCase(),
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text(amt(report.total),
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 14,
                        color: accent)),
              ],
            ),
          ),
        ];
      },
    ),
  );
  return doc.save();
}

pw.Widget _cell(String text,
    {bool bold = false, PdfColor? color, pw.TextAlign align = pw.TextAlign.left}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    child: pw.Text(text,
        textAlign: align,
        style: pw.TextStyle(
            fontSize: 9,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color)),
  );
}
