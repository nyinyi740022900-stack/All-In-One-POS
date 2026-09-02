import '../../core/money.dart';
import 'receipt_data.dart';
import 'sales_report_data.dart';

/// Turns a [SalesReport] into fixed-width monospace lines for the thermal
/// printer's paper width — same rationale as [ReceiptFormatter] (pure
/// string logic, unit-testable, shared by the raster renderer). Condensed
/// to what a receipt-width printer can usefully show: invoice number +
/// amount on one line, customer/address wrapped beneath when present, then
/// a Total line.
class SalesReportFormatter {
  SalesReportFormatter({
    required this.paper,
    this.currencySymbol = 'Ks',
    this.exponent = 0,
  });

  final PaperSize paper;
  final String currencySymbol;

  /// Decimal places for money amounts on this report — see
  /// [ReceiptFormatter.exponent]. Defaults to 0 (byte-identical MMK output).
  final int exponent;

  int get _w => paper.chars;

  String _amt(int v) {
    final sign = v < 0 ? '-' : '';
    return '$sign${formatMinorUnits(v.abs(), exponent: exponent)} $currencySymbol';
  }

  List<String> format(
    SalesReport report, {
    required String title,
    required String dateRangeLabel,
    required String totalLabel,
    required String noSalesLabel,
  }) {
    final out = <String>[];
    out.addAll(_center(title));
    out.addAll(_center(dateRangeLabel));
    out.add(_divider());

    if (report.rows.isEmpty) {
      out.addAll(_center(noSalesLabel));
      out.add(_divider());
      return out;
    }

    for (final r in report.rows) {
      out.add(_two(r.invoiceNo, _amt(r.amount)));
      final detail = [
        if (r.customerName.isNotEmpty) r.customerName,
        if (r.address.isNotEmpty) r.address,
      ].join(' - ');
      if (detail.isNotEmpty) out.addAll(_wrap(detail));
    }
    out.add(_divider());
    out.add(_two(totalLabel, _amt(report.total)));

    return out;
  }

  String _divider() => '-' * _w;

  /// Left text and right text on one line, padded apart. Falls back to two
  /// lines if they don't fit together.
  String _two(String left, String right) {
    if (left.length + right.length + 1 > _w) {
      return '$left\n${right.padLeft(_w)}';
    }
    final gap = _w - left.length - right.length;
    return left + (' ' * gap) + right;
  }

  List<String> _center(String text) {
    return _wrap(text).map((line) {
      if (line.length >= _w) return line;
      final pad = (_w - line.length) ~/ 2;
      return (' ' * pad) + line;
    }).toList();
  }

  /// Hard-wraps [text] at the paper width on word boundaries where possible.
  List<String> _wrap(String text) {
    final words = text.split(' ');
    final lines = <String>[];
    var current = '';
    for (final word in words) {
      if (word.length > _w) {
        if (current.isNotEmpty) {
          lines.add(current);
          current = '';
        }
        for (var i = 0; i < word.length; i += _w) {
          lines.add(word.substring(
              i, i + _w > word.length ? word.length : i + _w));
        }
        continue;
      }
      final candidate = current.isEmpty ? word : '$current $word';
      if (candidate.length > _w) {
        lines.add(current);
        current = word;
      } else {
        current = candidate;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines.isEmpty ? [''] : lines;
  }
}
