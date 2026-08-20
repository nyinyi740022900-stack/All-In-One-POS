/// Pure admin-console aggregations. Kept free of Flutter so KPI / search /
/// lookup behaviour can be unit-tested the same way Analytics summaries are.
library;

enum AdminShopFilter { all, premium, atRisk, expiring }

class AdminMonthBucket {
  const AdminMonthBucket({
    required this.year,
    required this.month,
    required this.amountKyat,
  });
  final int year;
  final int month;
  final int amountKyat;
}

class AdminPlanMix {
  const AdminPlanMix({
    required this.paid,
    required this.trial,
    required this.free,
    required this.expired,
  });
  final int paid;
  final int trial;
  final int free;
  final int expired;
  int get total => paid + trial + free + expired;
}

class AdminStats {
  const AdminStats({
    required this.shopCount,
    required this.premiumCount,
    required this.atRiskCount,
    required this.accountCount,
    required this.pendingCount,
    required this.revenueThisMonth,
    required this.revenueAllTime,
    required this.expiringIn7Days,
    required this.monthlyRevenue,
    required this.mix,
  });

  final int shopCount;

  /// Active shops that are not on the Free plan (paid monthly/yearly + trial).
  final int premiumCount;

  /// Free, expired, grace, or no license — shops that may need a call.
  final int atRiskCount;

  /// Linked login emails across all shops (owner + staff).
  final int accountCount;
  final int pendingCount;

  /// Sum of *fulfilled* license-request amounts in [now]'s calendar month.
  /// Manual complimentary extends are not included — they never mint a
  /// payment row.
  final int revenueThisMonth;
  final int revenueAllTime;
  final int expiringIn7Days;
  final List<AdminMonthBucket> monthlyRevenue;
  final AdminPlanMix mix;

  factory AdminStats.from({
    required List<Map<String, dynamic>> shops,
    required List<Map<String, dynamic>> requests,
    required DateTime now,
  }) {
    final localNow = now.isUtc ? now.toLocal() : now;
    var premium = 0;
    var atRisk = 0;
    var accounts = 0;
    var expiring = 0;
    var paid = 0;
    var trial = 0;
    var free = 0;
    var expired = 0;

    for (final s in shops) {
      accounts += shopAccountCount(s);
      if (isPremiumShop(s)) premium++;
      if (isAtRiskShop(s)) atRisk++;
      if (isExpiringSoon(s, localNow)) expiring++;
      switch (_planMixBucket(s)) {
        case _MixBucket.paid:
          paid++;
        case _MixBucket.trial:
          trial++;
        case _MixBucket.free:
          free++;
        case _MixBucket.expired:
          expired++;
      }
    }

    var pending = 0;
    var revenueMonth = 0;
    var revenueAll = 0;
    final buckets = <String, int>{};
    for (var i = 11; i >= 0; i--) {
      final dt = DateTime(localNow.year, localNow.month - i, 1);
      buckets[_monthKey(dt.year, dt.month)] = 0;
    }

    for (final r in requests) {
      final status = '${r['status']}';
      if (status == 'pending') pending++;
      if (status != 'fulfilled') continue;
      final amount = (r['amount'] as num?)?.toInt() ?? 0;
      revenueAll += amount;
      final created = _parseLocal(r['created_at']);
      if (created == null) continue;
      if (created.year == localNow.year && created.month == localNow.month) {
        revenueMonth += amount;
      }
      final key = _monthKey(created.year, created.month);
      if (buckets.containsKey(key)) {
        buckets[key] = (buckets[key] ?? 0) + amount;
      }
    }

    final monthly = <AdminMonthBucket>[];
    for (var i = 11; i >= 0; i--) {
      final dt = DateTime(localNow.year, localNow.month - i, 1);
      monthly.add(
        AdminMonthBucket(
          year: dt.year,
          month: dt.month,
          amountKyat: buckets[_monthKey(dt.year, dt.month)] ?? 0,
        ),
      );
    }

    return AdminStats(
      shopCount: shops.length,
      premiumCount: premium,
      atRiskCount: atRisk,
      accountCount: accounts,
      pendingCount: pending,
      revenueThisMonth: revenueMonth,
      revenueAllTime: revenueAll,
      expiringIn7Days: expiring,
      monthlyRevenue: monthly,
      mix: AdminPlanMix(paid: paid, trial: trial, free: free, expired: expired),
    );
  }
}

enum _MixBucket { paid, trial, free, expired }

String _monthKey(int year, int month) =>
    '$year-${month.toString().padLeft(2, '0')}';

String shopPlan(Map<String, dynamic> shop) {
  final raw = shop['plan'];
  if (raw == null) return '';
  final s = '$raw';
  return s == 'null' ? '' : s;
}

String shopStatus(Map<String, dynamic> shop) => '${shop['status']}';

bool isPremiumShop(Map<String, dynamic> shop) {
  final plan = shopPlan(shop);
  return shopStatus(shop) == 'active' && plan.isNotEmpty && plan != 'free';
}

bool isAtRiskShop(Map<String, dynamic> shop) {
  final status = shopStatus(shop);
  final plan = shopPlan(shop);
  return status == 'expired' ||
      status == 'grace' ||
      status == 'no_license' ||
      plan == 'free';
}

bool isExpiringSoon(Map<String, dynamic> shop, DateTime now, {int days = 7}) {
  if (shopStatus(shop) != 'active') return false;
  if (shopPlan(shop) == 'free') return false;
  final exp = _parseLocal(shop['expires_at']);
  if (exp == null) return false;
  final localNow = now.isUtc ? now.toLocal() : now;
  return exp.isAfter(localNow) &&
      !exp.isAfter(localNow.add(Duration(days: days)));
}

bool shopMatchesFilter(
  Map<String, dynamic> shop,
  AdminShopFilter filter,
  DateTime now,
) {
  return switch (filter) {
    AdminShopFilter.all => true,
    AdminShopFilter.premium => isPremiumShop(shop),
    AdminShopFilter.atRisk => isAtRiskShop(shop),
    AdminShopFilter.expiring => isExpiringSoon(shop, now),
  };
}

/// Device rows stored on the shop payload (`list_shops`) or joined from
/// `list_licenses` as a fallback when the admin function hasn't been
/// redeployed yet.
List<Map<String, dynamic>> shopDevices(
  Map<String, dynamic> shop,
  List<Map<String, dynamic>> licenses,
) {
  final raw = shop['devices'];
  if (raw is List && raw.isNotEmpty) {
    return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }
  final sid = '${shop['shop_id']}';
  return licenses
      .where((l) => '${l['shop_id']}' == sid && l['is_deleted'] != true)
      .toList();
}

List<Map<String, dynamic>> shopAccounts(Map<String, dynamic> shop) {
  final raw = shop['accounts'];
  if (raw is List) {
    return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }
  final email = '${shop['email'] ?? ''}'.trim();
  if (email.isEmpty || email == 'null') return const [];
  return [
    {'email': email, 'role': 'owner'},
  ];
}

int shopAccountCount(Map<String, dynamic> shop) {
  final n = (shop['account_count'] as num?)?.toInt();
  if (n != null) return n;
  return shopAccounts(shop).length;
}

bool shopMatchesQuery(
  Map<String, dynamic> shop,
  List<Map<String, dynamic>> licenses,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final hay = StringBuffer()
    ..write('${shop['shop_name'] ?? ''} ')
    ..write('${shop['shop_id'] ?? ''} ')
    ..write('${shop['email'] ?? ''} ')
    ..write('${shop['phone'] ?? ''} ');
  for (final a in shopAccounts(shop)) {
    hay.write('${a['email'] ?? ''} ');
  }
  for (final d in shopDevices(shop, licenses)) {
    hay.write('${d['device_id'] ?? ''} ');
    hay.write('${d['key'] ?? ''} ');
  }
  return hay.toString().toLowerCase().contains(q);
}

Map<String, dynamic>? findShopByEmail(
  List<Map<String, dynamic>> shops,
  String email,
) {
  final needle = email.trim().toLowerCase();
  if (needle.isEmpty) return null;
  for (final s in shops) {
    if ('${s['email'] ?? ''}'.toLowerCase() == needle) return s;
    for (final a in shopAccounts(s)) {
      if ('${a['email'] ?? ''}'.toLowerCase() == needle) return s;
    }
  }
  return null;
}

Map<String, dynamic>? findShopByDevice(
  List<Map<String, dynamic>> shops,
  List<Map<String, dynamic>> licenses,
  String deviceId,
) {
  final needle = deviceId.trim();
  if (needle.isEmpty) return null;
  for (final s in shops) {
    for (final d in shopDevices(s, licenses)) {
      if ('${d['device_id'] ?? ''}' == needle) return s;
    }
  }
  for (final l in licenses) {
    if ('${l['device_id'] ?? ''}' == needle) {
      final sid = '${l['shop_id']}';
      for (final s in shops) {
        if ('${s['shop_id']}' == sid) return s;
      }
    }
  }
  return null;
}

List<Map<String, dynamic>> requestsForShop(
  Map<String, dynamic> shop,
  List<Map<String, dynamic>> requests,
  List<Map<String, dynamic>> licenses,
) {
  final sid = '${shop['shop_id']}';
  final emails = {
    for (final a in shopAccounts(shop)) '${a['email'] ?? ''}'.toLowerCase(),
  }..removeWhere((e) => e.isEmpty);
  final devices = {
    for (final d in shopDevices(shop, licenses)) '${d['device_id'] ?? ''}',
  }..removeWhere((e) => e.isEmpty);
  return requests.where((r) {
    final rs = '${r['shop_id'] ?? ''}';
    if (rs.isNotEmpty && rs == sid) return true;
    final email = '${r['email'] ?? ''}'.toLowerCase();
    if (email.isNotEmpty && emails.contains(email)) return true;
    final dev = '${r['device_id'] ?? ''}';
    return dev.isNotEmpty && devices.contains(dev);
  }).toList();
}

_MixBucket _planMixBucket(Map<String, dynamic> shop) {
  final status = shopStatus(shop);
  final plan = shopPlan(shop);
  if (status == 'expired' || status == 'grace') return _MixBucket.expired;
  if (status == 'no_license' || plan == 'free' || plan.isEmpty) {
    return _MixBucket.free;
  }
  if (plan == 'trial') return _MixBucket.trial;
  return _MixBucket.paid;
}

DateTime? _parseLocal(dynamic v) {
  if (v == null) return null;
  final parsed = DateTime.tryParse('$v');
  if (parsed == null) return null;
  return parsed.isUtc ? parsed.toLocal() : parsed;
}
