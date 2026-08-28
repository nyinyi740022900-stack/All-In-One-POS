import 'package:intl/intl.dart';

import 'receipt_data.dart';

/// Turns a [ReceiptData] into an ordered list of plain-text lines laid out for
/// a fixed-width thermal paper. Pure string logic — no Flutter, no I/O — so it
/// is fully unit-testable and is also what the raster renderer draws.
///
/// Labels are passed in (already localized) so this stays UI-framework-free.
class ReceiptFormatter {
  ReceiptFormatter({
    required this.paper,
    required this.labels,
    this.currencySymbol = 'Ks',
  });

  final PaperSize paper;
  final ReceiptLabels labels;
  final String currencySymbol;

  int get _w => paper.chars;

  final _money = NumberFormat('#,##0', 'en_US');
  String _amt(int v) => '${_money.format(v)} $currencySymbol';

  /// [includeHeader] controls whether the shop name/address/phone block is
  /// included as plain centered text. The raster renderer draws that block
  /// itself (logo + styled shop name) and asks for `includeHeader: false` so
  /// it isn't printed twice.
  List<String> format(ReceiptData r, {bool includeHeader = true}) {
    final out = <String>[];

    if (includeHeader) {
      out.addAll(_center(r.shopName));
      if (r.address != null && r.address!.isNotEmpty) {
        out.addAll(_center(r.address!));
      }
      if (r.phone != null && r.phone!.isNotEmpty) {
        out.addAll(_center(r.phone!));
      }
      out.add(_divider());
    }

    out.add(_two(labels.invoice, r.invoiceNo));
    out.add(_two(labels.date,
        DateFormat('yyyy-MM-dd HH:mm').format(r.dateTime)));
    if (r.cashier != null && r.cashier!.isNotEmpty) {
      out.add(_two(labels.cashier, r.cashier!));
    }
    if (r.customerName != null && r.customerName!.isNotEmpty) {
      out.add(_two(labels.customer, r.customerName!));
    }
    if (r.customerPhone != null && r.customerPhone!.isNotEmpty) {
      out.add(_two(labels.phone, r.customerPhone!));
    }
    if (r.deliveryAddress != null && r.deliveryAddress!.isNotEmpty) {
      out.addAll(_wrap('${labels.deliveryAddress}: ${r.deliveryAddress}'));
    }
    out.add(_divider());

    // Items: name on its own line, then "qty x price ....... lineTotal".
    for (final it in r.items) {
      out.addAll(_wrap(it.name));
      out.add(_two('  ${it.qty} x ${_money.format(it.unitPrice)}',
          _amt(it.lineTotal)));
      final itemDiscount = lineDiscountOf(
          unitPrice: it.unitPrice, qty: it.qty, lineTotal: it.lineTotal);
      if (itemDiscount > 0) {
        out.add(_two('  ${labels.discount}', '-${_amt(itemDiscount)}'));
      }
    }
    out.add(_divider());

    out.add(_two(labels.subtotal, _amt(r.subtotal)));
    if (r.discount > 0) {
      out.add(_two(labels.discount, '-${_amt(r.discount)}'));
    }
    out.add(_two(labels.total, _amt(r.total)));
    out.add(_two(labels.payment, r.paymentMethod));
    if (r.paid > 0 || r.owed > 0) {
      out.add(_two(labels.paid, _amt(r.paid)));
    }
    if (r.change > 0) {
      out.add(_two(labels.change, _amt(r.change)));
    }
    if (r.owed > 0) {
      out.add(_two(labels.amountDue, _amt(r.owed)));
    }
    out.add(_divider());

    if (r.footer != null && r.footer!.isNotEmpty) {
      out.addAll(_center(r.footer!));
    }

    return out;
  }

  String _divider() => '-' * _w;

  /// Left text and right text on one line, padded apart. Falls back to two
  /// lines if they don't fit together.
  String _two(String left, String right) {
    if (left.length + right.length + 1 > _w) {
      // Not enough room: right-align the value under the label.
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
        // A single over-long token: chunk it.
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

/// Localized labels for the receipt, supplied by the caller.
class ReceiptLabels {
  final String invoice;
  final String date;
  final String cashier;
  final String customer;
  final String phone;
  final String deliveryAddress;
  final String subtotal;
  final String discount;
  final String total;
  final String payment;
  final String paid;
  final String change;
  final String amountDue;

  const ReceiptLabels({
    required this.invoice,
    required this.date,
    required this.cashier,
    required this.customer,
    required this.phone,
    required this.deliveryAddress,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.payment,
    required this.paid,
    required this.change,
    required this.amountDue,
  });
}
