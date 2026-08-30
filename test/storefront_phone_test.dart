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

  group('normalizeStorefrontIp', () {
    test('keeps a public IPv4 and uses only the last X-Forwarded-For hop', () {
      expect(normalizeStorefrontIp('203.0.113.50'), '203.0.113.50');
      expect(
        normalizeStorefrontIp('198.51.100.1, 203.0.113.50'),
        '203.0.113.50',
      );
      expect(
        normalizeStorefrontIp(' 198.51.100.1, 203.0.113.50:443 '),
        '203.0.113.50',
      );
      // Last hop is the trusted-proxy entry. If it is private, do not walk
      // left into a client-supplied public address.
      expect(normalizeStorefrontIp('203.0.113.50, 10.0.0.1'), '');
      expect(normalizeStorefrontIp('10.0.0.1'), '');
      expect(normalizeStorefrontIp('192.168.1.8'), '');
      expect(normalizeStorefrontIp('172.16.0.1'), '');
    });

    test('normalizes IPv6 and strips brackets/port', () {
      expect(normalizeStorefrontIp('2001:DB8::1'), '2001:db8::1');
      expect(normalizeStorefrontIp('[2001:db8::1]:443'), '2001:db8::1');
    });

    test('canonicalizes equivalent IPv6 notations to one block key', () {
      const canonical = '2001:db8::1';
      expect(
        normalizeStorefrontIp('2001:0db8:0000:0000:0000:0000:0000:0001'),
        canonical,
      );
      expect(normalizeStorefrontIp('2001:db8:0:0:0:0:0:1'), canonical);
      expect(normalizeStorefrontIp('2001:db8::1'), canonical);
    });

    test('folds IPv4-mapped IPv6 onto the same IPv4 block key', () {
      const canonical = '203.0.113.50';
      expect(normalizeStorefrontIp('203.0.113.50'), canonical);
      expect(normalizeStorefrontIp('::ffff:203.0.113.50'), canonical);
      expect(normalizeStorefrontIp('::ffff:cb00:7132'), canonical);
      expect(normalizeStorefrontIp('[::ffff:203.0.113.50]'), canonical);
    });

    test('rejects blank, unknown, loopback, and garbage', () {
      expect(normalizeStorefrontIp(''), '');
      expect(normalizeStorefrontIp('   '), '');
      expect(normalizeStorefrontIp('unknown'), '');
      expect(normalizeStorefrontIp('127.0.0.1'), '');
      expect(normalizeStorefrontIp('0.0.0.0'), '');
      expect(normalizeStorefrontIp('::1'), '');
      expect(normalizeStorefrontIp('0:0:0:0:0:0:0:1'), '');
      expect(normalizeStorefrontIp('::'), '');
      expect(normalizeStorefrontIp('0:0:0:0:0:0:0:0'), '');
      expect(normalizeStorefrontIp('::ffff:127.0.0.1'), '');
      expect(normalizeStorefrontIp('::ffff:0.0.0.0'), '');
      expect(normalizeStorefrontIp('not-an-ip'), '');
      expect(normalizeStorefrontIp('999.1.1.1'), '');
    });

    test('rejects IPv6 with extra empty segments, not a single ::', () {
      expect(normalizeStorefrontIp('1:::2'), '');
      expect(normalizeStorefrontIp('1:2:3:4:5:6:7:'), '');
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
