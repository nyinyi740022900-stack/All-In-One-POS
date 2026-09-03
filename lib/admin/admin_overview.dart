part of 'admin_dashboard_screen.dart';

double _adminKpiExtent(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  final labelBlock = math.max(32.0, scaler.scale(12) * 1.45 * 2);
  final valueLine = scaler.scale(19) * 1.35;
  return AppTheme.space3 * 2 + labelBlock + AppTheme.space2 + valueLine;
}

class _OverviewPage extends StatelessWidget {
  const _OverviewPage({
    required this.stats,
    required this.pending,
    required this.onOpenInbox,
    required this.onOpenShops,
    required this.onOpenPayments,
  });

  final AdminStats stats;
  final List<Map<String, dynamic>> pending;
  final VoidCallback onOpenInbox;
  final void Function(AdminShopFilter filter) onOpenShops;
  final VoidCallback onOpenPayments;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cols = width >= 1100 ? 3 : 2;
    return ListView(
      padding: const EdgeInsets.all(AppTheme.space4),
      children: [
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: AppTheme.space3,
            crossAxisSpacing: AppTheme.space3,
            mainAxisExtent: _adminKpiExtent(context),
          ),
          children: [
            StatCard(
              label: 'Shops',
              value: '${stats.shopCount}',
              icon: Icons.storefront_outlined,
              onTap: () => onOpenShops(AdminShopFilter.all),
            ),
            StatCard(
              label: 'Premium',
              value: '${stats.premiumCount}',
              icon: Icons.workspace_premium_outlined,
              onTap: () => onOpenShops(AdminShopFilter.premium),
            ),
            StatCard(
              label: 'Free / expired',
              value: '${stats.atRiskCount}',
              icon: Icons.warning_amber_outlined,
              tone: stats.atRiskCount > 0 ? StatusTone.attention : null,
              onTap: () => onOpenShops(AdminShopFilter.atRisk),
            ),
            StatCard(
              label: 'Pending inbox',
              value: '${stats.pendingCount}',
              icon: Icons.inbox_outlined,
              tone: stats.pendingCount > 0 ? StatusTone.attention : null,
              onTap: onOpenInbox,
            ),
            StatCard(
              // Manual (Myanmar) payments only — see AdminStats.
              label: 'Manual payments this month',
              value: _ks(stats.revenueThisMonth),
              icon: Icons.payments_outlined,
              onTap: onOpenPayments,
            ),
            StatCard(
              label: 'Expiring in 7 days',
              value: '${stats.expiringIn7Days}',
              icon: Icons.event_busy_outlined,
              tone: stats.expiringIn7Days > 0 ? StatusTone.critical : null,
              onTap: () => onOpenShops(AdminShopFilter.expiring),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.space2),
        Text(
          '${stats.accountCount} linked login${stats.accountCount == 1 ? '' : 's'}  ·  '
          'All-time manual ${_ks(stats.revenueAllTime)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppTheme.space4),
        _AdminRevenueChart(monthly: stats.monthlyRevenue),
        const SizedBox(height: AppTheme.space3),
        _AdminPlanMixCard(mix: stats.mix),
        if (pending.isNotEmpty) ...[
          const SizedBox(height: AppTheme.space3),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.space3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(
                    title: 'Waiting in inbox',
                    trailing: TextButton(
                      onPressed: onOpenInbox,
                      child: const Text('Open'),
                    ),
                  ),
                  for (final r in pending.take(5))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${r['shop_name'] ?? '—'}'),
                      subtitle: Text(
                        '${r['method'] ?? '—'}  ·  ${r['months'] ?? '—'} mo',
                      ),
                      trailing: Text(_ks((r['amount'] as num?)?.toInt() ?? 0)),
                      onTap: onOpenInbox,
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AdminRevenueChart extends StatelessWidget {
  const _AdminRevenueChart({required this.monthly});
  final List<AdminMonthBucket> monthly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxY = monthly.fold<int>(
      0,
      (m, b) => b.amountKyat > m ? b.amountKyat : m,
    );
    final fmt = DateFormat('MMM');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Paid revenue (12 months)',
              trailing: maxY == 0
                  ? null
                  : Text(
                      _ks(maxY),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
            ),
            SizedBox(
              height: 180,
              child: maxY == 0
                  ? const EmptyStateView(
                      icon: Icons.bar_chart_outlined,
                      title: 'No confirmed payments yet.',
                    )
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: maxY.toDouble() * 1.15,
                        borderData: FlBorderData(show: false),
                        gridData: const FlGridData(show: false),
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (_) => scheme.inverseSurface,
                            tooltipRoundedRadius: AppTheme.radiusSm,
                            getTooltipItem: (group, _, rod, _) {
                              final b = monthly[group.x];
                              return BarTooltipItem(
                                '${fmt.format(DateTime(b.year, b.month))}\n'
                                '${_ks(rod.toY.round())}',
                                theme.textTheme.labelMedium!.copyWith(
                                  color: scheme.onInverseSurface,
                                  fontFeatures: AppTheme.tabularFigures,
                                ),
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 22,
                              getTitlesWidget: (value, _) {
                                final i = value.toInt();
                                if (i < 0 || i >= monthly.length) {
                                  return const SizedBox.shrink();
                                }
                                if (i % 2 == 1) return const SizedBox.shrink();
                                final b = monthly[i];
                                return Text(
                                  fmt.format(DateTime(b.year, b.month)),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        barGroups: [
                          for (var i = 0; i < monthly.length; i++)
                            BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: monthly[i].amountKyat.toDouble(),
                                  color: scheme.primary,
                                  width: 10,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(3),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminPlanMixCard extends StatelessWidget {
  const _AdminPlanMixCard({required this.mix});
  final AdminPlanMix mix;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final slices = <({String label, int value, Color color})>[
      (label: 'Paid', value: mix.paid, color: scheme.onSurface),
      (label: 'Trial', value: mix.trial, color: colors.warning),
      (label: 'Free', value: mix.free, color: colors.muted),
      (label: 'Expired', value: mix.expired, color: colors.danger),
    ].where((s) => s.value > 0).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: 'Plan mix'),
            if (mix.total == 0)
              const EmptyStateView(
                icon: Icons.pie_chart_outline,
                title: 'No shops yet.',
              )
            else
              Row(
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 28,
                        sections: [
                          for (final s in slices)
                            PieChartSectionData(
                              value: s.value.toDouble(),
                              color: s.color,
                              radius: 22,
                              showTitle: false,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.space4),
                  Expanded(
                    child: Column(
                      children: [
                        for (final s in [
                          (
                            label: 'Paid',
                            value: mix.paid,
                            color: scheme.onSurface,
                          ),
                          (
                            label: 'Trial',
                            value: mix.trial,
                            color: colors.warning,
                          ),
                          (label: 'Free', value: mix.free, color: colors.muted),
                          (
                            label: 'Expired',
                            value: mix.expired,
                            color: colors.danger,
                          ),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppTheme.space1,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: s.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: AppTheme.space2),
                                Expanded(child: Text(s.label)),
                                Text(
                                  '${s.value}',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        fontFeatures: AppTheme.tabularFigures,
                                      ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
