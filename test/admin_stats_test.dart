import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/admin/admin_stats.dart';

void main() {
  final now = DateTime(2026, 8, 20, 12);

  final shops = <Map<String, dynamic>>[
    {
      'shop_id': 'shop-a',
      'shop_name': 'Zay Shae',
      'plan': 'monthly',
      'status': 'active',
      'expires_at': '2026-08-25T00:00:00Z',
      'email': 'owner-a@example.com',
      'phone': '091111111',
      'accounts': [
        {'id': 'u1', 'email': 'owner-a@example.com', 'role': 'owner'},
        {'id': 'u2', 'email': 'staff-a@example.com', 'role': 'staff'},
      ],
      'devices': [
        {'device_id': 'dev-a1', 'key': 'KEY-A'},
      ],
    },
    {
      'shop_id': 'shop-b',
      'plan': 'trial',
      'status': 'active',
      'expires_at': '2026-10-01T00:00:00Z',
      'email': 'trial@example.com',
      'accounts': [
        {'id': 'u3', 'email': 'trial@example.com', 'role': 'owner'},
      ],
    },
    {
      'shop_id': 'shop-c',
      'plan': 'free',
      'status': 'active',
      'email': 'free@example.com',
    },
    {
      'shop_id': 'shop-d',
      'plan': 'yearly',
      'status': 'expired',
      'expires_at': '2026-07-01T00:00:00Z',
    },
    {
      'shop_id': 'shop-e',
      'status': 'no_license',
      'email': 'orphan@example.com',
    },
  ];

  final requests = <Map<String, dynamic>>[
    {
      'status': 'fulfilled',
      'amount': 25000,
      'created_at': '2026-08-05T00:00:00Z',
      'shop_id': 'shop-a',
    },
    {
      'status': 'fulfilled',
      'amount': 10000,
      'created_at': '2026-07-05T00:00:00Z',
      'shop_id': 'shop-d',
    },
    {
      'status': 'pending',
      'amount': 5000,
      'created_at': '2026-08-18T00:00:00Z',
      'shop_id': 'shop-b',
    },
    {
      'status': 'rejected',
      'amount': 9000,
      'created_at': '2026-08-01T00:00:00Z',
    },
  ];

  test('KPI cards split premium, at-risk, pending, and paid revenue', () {
    final stats = AdminStats.from(shops: shops, requests: requests, now: now);
    expect(stats.shopCount, 5);
    expect(stats.premiumCount, 2); // monthly + trial, both active
    expect(stats.atRiskCount, 3); // free + expired + no_license
    expect(
      stats.accountCount,
      5,
    ); // a:2 + b:1 + c:1 (email fallback) + d:0 + e:1
    expect(stats.pendingCount, 1);
    expect(stats.revenueThisMonth, 25000);
    expect(stats.revenueAllTime, 35000);
    expect(stats.expiringIn7Days, 1); // shop-a expires Aug 25
    expect(stats.mix.paid, 1);
    expect(stats.mix.trial, 1);
    expect(stats.mix.free, 2); // free plan + no_license
    expect(stats.mix.expired, 1);
  });

  test(
    'monthly revenue is the last 12 calendar months, UTC-shifted to local',
    () {
      final stats = AdminStats.from(shops: shops, requests: requests, now: now);
      expect(stats.monthlyRevenue, hasLength(12));
      expect(stats.monthlyRevenue.last.year, 2026);
      expect(stats.monthlyRevenue.last.month, 8);
      expect(stats.monthlyRevenue.last.amountKyat, 25000);
      final july = stats.monthlyRevenue[stats.monthlyRevenue.length - 2];
      expect(july.month, 7);
      expect(july.amountKyat, 10000);
    },
  );

  test('rejected and pending amounts are never counted as revenue', () {
    final stats = AdminStats.from(shops: shops, requests: requests, now: now);
    expect(stats.revenueAllTime, isNot(35000 + 5000 + 9000));
    expect(stats.revenueAllTime, 35000);
  });

  test('search matches name, email, staff email, phone, and device id', () {
    const licenses = <Map<String, dynamic>>[];
    expect(shopMatchesQuery(shops[0], licenses, 'zay'), isTrue);
    expect(shopMatchesQuery(shops[0], licenses, 'staff-a@'), isTrue);
    expect(shopMatchesQuery(shops[0], licenses, 'dev-a1'), isTrue);
    expect(shopMatchesQuery(shops[0], licenses, '091111111'), isTrue);
    expect(shopMatchesQuery(shops[0], licenses, 'nope'), isFalse);
  });

  test('lookup by email prefers staff emails on the shop payload', () {
    final found = findShopByEmail(shops, 'STAFF-A@example.com');
    expect(found?['shop_id'], 'shop-a');
    expect(findShopByEmail(shops, 'missing@x.com'), isNull);
  });

  test('lookup by device uses the shop devices list', () {
    final found = findShopByDevice(shops, const [], 'dev-a1');
    expect(found?['shop_id'], 'shop-a');
  });

  test('requestsForShop matches shop_id, email, or device', () {
    final forA = requestsForShop(shops[0], requests, const []);
    expect(forA, hasLength(1));
    expect(forA.first['amount'], 25000);
  });

  test('shop filters used by dashboard card taps', () {
    expect(shopMatchesFilter(shops[0], AdminShopFilter.premium, now), isTrue);
    expect(shopMatchesFilter(shops[0], AdminShopFilter.expiring, now), isTrue);
    expect(shopMatchesFilter(shops[2], AdminShopFilter.atRisk, now), isTrue);
    expect(shopMatchesFilter(shops[2], AdminShopFilter.premium, now), isFalse);
  });
}
