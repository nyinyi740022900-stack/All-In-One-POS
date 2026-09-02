import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/money.dart';
import '../invoices/pdf_font.dart';
import '../invoices/receipt_data.dart';
import 'cash_session_repository.dart';

/// Renders a [CashSessionReport] onto a real A4/A5 page — same
/// header/footer/font/page-format scaffold as `buildSalesReportPdf`, with a
/// key-value body instead of a row table (a single session's summary, not a
/// multi-row dataset).
Future<Uint8List> buildCashSessionReportPdf({
  required String shopName,
  String? shopLogoUrl,
  String? shopPhone,
  String? shopAddress,
  required String title,
  required CashSessionReport report,
  required String currencySymbol,
  int exponent = 0,
  required String openedLabel,
  required String closedLabel,
  required String openingFloatLabel,
  required String cashSalesLabel,
  required String cashRepaymentsLabel,
  required String topUpsLabel,
  required String expensesLabel,
  required String supplierPaymentsLabel,
  required String expectedCashLabel,
  required String countedCashLabel,
  required DateTime openedAt,
  DateTime? closedAt,
  String? varianceLabel,
  String? varianceText,
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
    return '$sign${formatMinorUnits(v.abs(), exponent: exponent)} $currencySymbol';
  }

  String dateTimeStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  final font = await loadMyanmarPdfFont();
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(
      base: font.regular,
      bold: font.bold,
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
                    color: accent)),
            pw.Text(
              closedAt == null
                  ? '$openedLabel: ${dateTimeStr(openedAt)}'
                  : '$openedLabel: ${dateTimeStr(openedAt)}   $closedLabel: ${dateTimeStr(closedAt)}',
              style: pw.TextStyle(fontSize: 10, color: muted),
            ),
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
        final rows = <(String, String, bool)>[
          (openingFloatLabel, amt(report.openingAmount), false),
          (cashSalesLabel, amt(report.cashSalesTotal), false),
          (cashRepaymentsLabel, amt(report.cashRepaymentsTotal), false),
          (topUpsLabel, amt(report.topUpsTotal), false),
          (expensesLabel, '-${amt(report.expensesTotal)}', false),
          (supplierPaymentsLabel, '-${amt(report.supplierPaymentsTotal)}', false),
          (expectedCashLabel, amt(report.expectedCash), true),
          if (report.closingAmount != null)
            (countedCashLabel, amt(report.closingAmount!), false),
          if (report.closingAmount != null &&
              varianceLabel != null &&
              varianceText != null)
            (varianceLabel, varianceText, true),
        ];
        return [
          pw.Table(
            border: pw.TableBorder.all(color: line),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(2),
            },
            children: [
              for (final r in rows)
                pw.TableRow(children: [
                  _cell(r.$1, bold: r.$3),
                  _cell(r.$2, bold: r.$3, align: pw.TextAlign.right),
                ]),
            ],
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
