import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../invoices/pdf_font.dart';
import '../invoices/receipt_data.dart';

/// A generic "table of strings" PDF shell — same header/footer/font scaffold
/// as `buildSalesReportPdf`/`buildPnlPdf`/`buildEquityPdf`, parameterized on
/// columns instead of re-implementing the shell per screen. Shared by every
/// Accounting-family export whose data is really just rows of pre-formatted
/// cells (Balance Sheet, Cash Flow, Accounts Payable/Receivable, Expenses,
/// Inventory, Stock Movements) — the caller formats money/dates into
/// strings itself, this only lays them out.
Future<Uint8List> buildLabeledTablePdf({
  required String shopName,
  String? shopLogoUrl,
  String? shopPhone,
  String? shopAddress,
  required String title,
  String? subtitle,
  required List<String> columnLabels,
  required List<int> columnFlex,
  required List<List<String>> rows,
  Set<int> rightAlignColumns = const {},
  Set<int> boldRowIndices = const {},
  String? emptyLabel,
  PdfPaperSize pageFormat = PdfPaperSize.a4,
}) async {
  assert(columnLabels.length == columnFlex.length);
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

  final font = await loadMyanmarPdfFont();
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(
      base: font.regular,
      bold: font.bold,
      // Noto Sans Myanmar doesn't cover every symbol (e.g. an arrow) — fall
      // back to the bundled Helvetica for anything it's missing rather than
      // a tofu box.
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
            if ((subtitle ?? '').isNotEmpty)
              pw.Text(subtitle!.replaceAll('→', '-'),
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
        if (rows.isEmpty && (emptyLabel ?? '').isNotEmpty) {
          return [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 24),
              child: pw.Center(
                child: pw.Text(emptyLabel!,
                    style: pw.TextStyle(fontSize: 11, color: muted)),
              ),
            ),
          ];
        }
        return [
          pw.Table(
            border: pw.TableBorder.all(color: line),
            columnWidths: {
              for (var i = 0; i < columnFlex.length; i++)
                i: pw.FlexColumnWidth(columnFlex[i].toDouble()),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFF7F5FB)),
                children: [
                  for (var c = 0; c < columnLabels.length; c++)
                    _cell(columnLabels[c],
                        bold: true,
                        color: muted,
                        align: rightAlignColumns.contains(c)
                            ? pw.TextAlign.right
                            : pw.TextAlign.left),
                ],
              ),
              for (var r = 0; r < rows.length; r++)
                pw.TableRow(children: [
                  for (var c = 0; c < rows[r].length; c++)
                    _cell(rows[r][c],
                        bold: boldRowIndices.contains(r),
                        align: rightAlignColumns.contains(c)
                            ? pw.TextAlign.right
                            : pw.TextAlign.left),
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
