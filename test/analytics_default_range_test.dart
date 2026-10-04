import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/features/analytics/analytics_providers.dart';

void main() {
  test('Analytics opens on Today, not the 7-day range', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(analyticsRangeProvider), AnalyticsRange.today);
  });
}
