/// Last 7 days of Play Integrity verdicts (`integrity_summary`), shown so the
/// owner can tell when `integrity.android_mode` can move from monitor to
/// enforce. See supabase/functions/_shared/play_integrity.ts.
class IntegritySummary {
  const IntegritySummary({
    required this.mode,
    required this.counts,
    required this.recentFailures,
  });

  factory IntegritySummary.fromJson(Map<String, dynamic> j) {
    final counts = <String, int>{};
    final raw = j['counts'];
    if (raw is Map) {
      raw.forEach((k, v) => counts['$k'] = (v as num?)?.toInt() ?? 0);
    }
    return IntegritySummary(
      mode: '${j['mode'] ?? 'monitor'}',
      counts: counts,
      recentFailures: [
        for (final r in (j['recent_failures'] as List?) ?? const [])
          if (r is Map) r.cast<String, dynamic>(),
      ],
    );
  }

  final String mode;
  final Map<String, int> counts;
  final List<Map<String, dynamic>> recentFailures;

  int get total => counts.values.fold(0, (a, b) => a + b);
  int get failures => counts['fail'] ?? 0;
  int get passes => (counts['pass'] ?? 0) + (counts['pass_sideload'] ?? 0);
}
