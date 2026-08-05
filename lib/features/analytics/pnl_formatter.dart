import 'package:intl/intl.dart';

import '../invoices/receipt_data.dart';
import 'pnl_data.dart';

/// Turns a [PnlStatement] into fixed-width monospace lines for the thermal
/// printer's paper width — same shape/helpers as `CashSessionReportFormatter`
/// (a key-value body, not a row table), reused as-is by `renderReportImage`.
class PnlFormatter {
  PnlFormatter({required this.paper, this.currencySymbol = 'Ks'});

  final PaperSize paper;
  final String currencySymbol;

  int get _w => paper.chars;

  final _money = NumberFormat('#,##0', 'en_US');
  String _amt(int v) {
    final sign = v < 0 ? '-' : '';
    return '$sign${_money.format(v.abs())} $currencySymbol';
  }

  List<String> format(
    PnlStatement p, {
    required String title,
    required String dateRangeLabel,
    required String revenueLabel,
    required String cogsLabel,
    required String grossProfitLabel,
    required String totalExpensesLabel,
    required String netProfitLabel,
    required String Function(String category) categoryLabel,
  }) {
    final df = DateFormat('yyyy-MM-dd');
    final inclusiveEnd = p.end.subtract(const Duration(days: 1));
    final out = <String>[];
    out.addAll(_center(title));
    out.add(_divider());
    out.add(_two(dateRangeLabel, '${df.format(p.start)} ~ ${df.format(inclusiveEnd)}'));
    out.add(_divider());

    out.add(_two(revenueLabel, _amt(p.revenue)));
    out.add(_two(cogsLabel, _amt(-p.cogs)));
    out.add(_two(grossProfitLabel, _amt(p.grossProfit)));
    out.add(_divider());

    for (final entry in p.expensesByCategory.entries) {
      if (entry.value == 0) continue;
      out.add(_two('  ${categoryLabel(entry.key)}', _amt(-entry.value)));
    }
    out.add(_two(totalExpensesLabel, _amt(-p.totalExpenses)));
    out.add(_divider());
    out.add(_two(netProfitLabel, _amt(p.netProfit)));

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
