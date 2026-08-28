import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/storefront/storefront_repository.dart';
import 'package:mm_pos/storefront/storefront_api.dart';

void main() {
  group('normalizeStorefrontPhone', () {
    test('maps 09 / 9 / +959 / 959 and strips spaces and dashes', () {
      const canonical = '09123456789';
      expect(normalizeStorefrontPhone('09123456789'), canonical);
      expect(normalizeStorefrontPhone('09 123 456 789'), canonical);
      expect(normalizeStorefrontPhone('09-123-456-789'), canonical);
      expect(normalizeStorefrontPhone('9123456789'), canonical);
      expect(normalizeStorefrontPhone('9 123 456 789'), canonical);
      expect(normalizeStorefrontPhone('+959123456789'), canonical);
      expect(normalizeStorefrontPhone('+95 9 123 456 789'), canonical);
      expect(normalizeStorefrontPhone('959123456789'), canonical);
    });

    test('empty after strip stays empty; other numbers keep digits', () {
      expect(normalizeStorefrontPhone('   '), '');
      expect(normalizeStorefrontPhone('0812345678'), '0812345678');
    });
  });

  group('SubmitOrderResult.fromMap', () {
    test('reads server line prices and items_total', () {
      final result = SubmitOrderResult.fromMap({
        'ok': true,
        'order_no': 'WEB-ABCDEF12',
        'items_total': 15000,
        'lines': [
          {
            'product_id': 'p1',
            'name': 'Tea',
            'price': 5000,
            'qty': 2,
            'line_total': 10000,
          },
          {
            'product_id': 'p2',
            'name': 'Snack',
            'price': 5000,
            'qty': 1,
            'line_total': 5000,
          },
        ],
      });
      expect(result.orderNo, 'WEB-ABCDEF12');
      expect(result.itemsTotal, 15000);
      expect(result.lines, hasLength(2));
      expect(result.lines[0].price, 5000);
      expect(result.lines[0].qty, 2);
      expect(result.lines[1].price, 5000);
    });

    test('honeypot-shaped body has order_no and empty lines', () {
      final result = SubmitOrderResult.fromMap({
        'ok': true,
        'order_no': 'WEB-00000000',
      });
      expect(result.orderNo, 'WEB-00000000');
      expect(result.itemsTotal, isNull);
      expect(result.lines, isEmpty);
    });
  });
}
