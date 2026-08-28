import 'package:intl/intl.dart';

import '../invoices/receipt_data.dart';
import 'cash_session_repository.dart';

/// Turns a [CashSessionReport] into fixed-width monospace lines for the
/// thermal printer's paper width — same shape/helpers as
/// `SalesReportFormatter`, reused as-is by `renderReportImage` (shop name is
/// drawn separately by that renderer, so it isn't part of this body).
class CashSessionReportFormatter {
  CashSessionReportFormatter({required this.paper, this.currencySymbol = 'Ks'});

  final PaperSize paper;
  final String currencySymbol;

  int get _w => paper.chars;

  final _money = NumberFormat('#,##0', 'en_US');
  String _amt(int v) {
    final sign = v < 0 ? '-' : '';
    return '$sign${_money.format(v.abs())} $currencySymbol';
  }

  List<String> format(
    CashSessionReport report, {
    required String title,
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
  }) {
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final out = <String>[];
    out.addAll(_center(title));
    out.add(_divider());
    out.add(_two(openedLabel, df.format(openedAt)));
    if (closedAt != null) out.add(_two(closedLabel, df.format(closedAt)));
    out.add(_divider());

    out.add(_two(openingFloatLabel, _amt(report.openingAmount)));
    out.add(_two(cashSalesLabel, _amt(report.cashSalesTotal)));
    out.add(_two(cashRepaymentsLabel, _amt(report.cashRepaymentsTotal)));
    out.add(_two(topUpsLabel, _amt(report.topUpsTotal)));
    out.add(_two(expensesLabel, '-${_amt(report.expensesTotal)}'));
    out.add(_two(supplierPaymentsLabel,
        '-${_amt(report.supplierPaymentsTotal)}'));
    out.add(_divider());
    out.add(_two(expectedCashLabel, _amt(report.expectedCash)));

    if (report.closingAmount != null) {
      out.add(_two(countedCashLabel, _amt(report.closingAmount!)));
      if (varianceLabel != null && varianceText != null) {
        out.add(_two(varianceLabel, varianceText));
      }
    }

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
