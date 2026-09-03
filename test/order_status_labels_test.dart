import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/orders/order_labels.dart';
import 'package:mm_pos/features/orders/orders_repository.dart';
import 'package:mm_pos/l10n/app_localizations_en.dart';
import 'package:mm_pos/l10n/app_localizations_my.dart';

/// Guards the "a new status variant renders as the wrong thing" bug class.
///
/// This has bitten Orders twice — `storefront` (a channel only the web
/// storefront writes) crashed the editor's dropdown, and `partial` (a payment
/// status only `convertToSale` writes) silently rendered as "Unpaid" for
/// months, because both label functions end in a `default:` that quietly
/// absorbs anything unregistered. `flutter analyze` cannot see either: a
/// `switch` over `String` is exhaustive by definition once it has a default.
///
/// The Invoices side already had the equivalent coverage
/// (`invoice_payment_status_test.dart`, which is why *its* `partial` and
/// `cod_pending`/`transfer_pending` stages were always right) — this is the
/// missing sibling, made structural rather than case-by-case: it drives off
/// the `…All` sets, so adding a variant without a label fails here instead of
/// on a customer's screen.
void main() {
  final en = AppLocalizationsEn();
  final my = AppLocalizationsMy();

  /// A `default:` fallthrough shows up as two values sharing one label.
  void expectDistinctLabels(
    String field,
    Set<String> values,
    String Function(dynamic l, String v) label,
  ) {
    for (final localizations in [en, my]) {
      final byLabel = <String, List<String>>{};
      for (final v in values) {
        byLabel.putIfAbsent(label(localizations, v), () => []).add(v);
      }
      final collisions = byLabel.entries.where((e) => e.value.length > 1);
      expect(
        collisions,
        isEmpty,
        reason: '[${localizations.localeName}] $field: '
            '${collisions.map((e) => '${e.value} all render as "${e.key}"').join('; ')}'
            ' — one of them is falling through to the switch\'s default. '
            'Give it its own case in $field\'s label function.',
      );
    }
  }

  group('every storable order value has its own label', () {
    test('payment status', () {
      expectDistinctLabels(
        'orderPaymentLabel',
        orderPaymentStatusesAll,
        (l, v) => orderPaymentLabel(l, v),
      );
    });

    test('pipeline status', () {
      expectDistinctLabels(
        'orderStatusLabel',
        orderStatusesAll,
        (l, v) => orderStatusLabel(l, v),
      );
    });

    test('channel', () {
      expectDistinctLabels(
        'orderChannelLabel',
        orderChannelsAll,
        (l, v) => orderChannelLabel(l, v),
      );
    });
  });

  group('pickable values are a subset of storable ones', () {
    test('statuses', () {
      expect(orderStatuses.toSet().difference(orderStatusesAll), isEmpty,
          reason: 'a status the editor offers is not a status an order row '
              'can hold — one of the two lists has a typo.');
    });

    test('channels', () {
      expect(orderChannels.toSet().difference(orderChannelsAll), isEmpty,
          reason: 'a channel the editor offers is not a channel an order row '
              'can hold — one of the two lists has a typo.');
    });
  });

  group('the repository never writes an unregistered value', () {
    // Every literal the repository assigns to one of these fields must be a
    // value the labels/filters know about. Catches the other half of the bug:
    // a new variant written to the DB but never added to its `…All` set (so
    // the distinctness test above would never see it either).
    late final String source =
        File('lib/features/orders/orders_repository.dart').readAsStringSync();

    /// Literals appearing in the argument that follows `field:` — bounded at
    /// the *next* named argument, so a generous window can hold a whole
    /// ternary (`collected >= total ? 'paid' : 'partial'`) without bleeding
    /// into the sibling field that follows it (`status:` sits directly above
    /// `paymentStatus:` in `convertToSale`, and an unbounded window credited
    /// one field with the other's values).
    Set<String> literalsAssignedTo(String field) {
      final found = <String>{};
      final assignment = RegExp('(?<![A-Za-z])$field:');
      final nextArgument = RegExp(r'\b[A-Za-z_]\w*:');
      for (final m in assignment.allMatches(source)) {
        var window = source.substring(
          m.end,
          (m.end + 220).clamp(0, source.length),
        );
        final boundary = nextArgument.firstMatch(window);
        if (boundary != null) window = window.substring(0, boundary.start);
        for (final lit in RegExp(r"'([a-z_]+)'").allMatches(window)) {
          found.add(lit.group(1)!);
        }
      }
      return found;
    }

    test('paymentStatus', () {
      final written = literalsAssignedTo('paymentStatus');
      expect(written, isNotEmpty,
          reason: 'the scan found no paymentStatus writes at all — the '
              'repository was restructured and this guard is now blind.');
      expect(written.difference(orderPaymentStatusesAll), isEmpty,
          reason: 'written to orders.paymentStatus but missing from '
              'orderPaymentStatusesAll (and therefore from every label, '
              'filter and switch driven by it).');
    });

    test('status', () {
      final written = literalsAssignedTo('status');
      expect(written, isNotEmpty,
          reason: 'the scan found no status writes at all — the repository '
              'was restructured and this guard is now blind.');
      expect(written.difference(orderStatusesAll), isEmpty,
          reason: 'written to orders.status but missing from '
              'orderStatusesAll.');
    });
  });
}
