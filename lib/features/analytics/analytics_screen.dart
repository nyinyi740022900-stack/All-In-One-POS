import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../credit/credit_screen.dart';
import '../expenses/expense_screen.dart';
import '../license/license_providers.dart';
import '../license/premium_gate.dart';
import '../printing/printing_providers.dart';
import '../staff/staff_providers.dart';
import '../staff/staff_ui.dart';
import 'analytics_calculator.dart';
import 'analytics_providers.dart';
import 'pnl_screen.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    // Business analytics are owner-only.
    if (!ref.watch(isEffectiveOwnerProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l.navAnalytics)),
        body: const OwnerOnlyGate(child: SizedBox.shrink()),
      );
    }
    if (ref.watch(licenseControllerProvider).loading || !ref.watch(isPremiumProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l.navAnalytics)),
        body: PremiumGate(featureName: l.navAnalytics, child: const SizedBox.shrink()),
      );
    }

    final range = ref.watch(analyticsRangeProvider);
    final summary = ref.watch(analyticsSummaryProvider);
    final trackStock = ref.watch(trackStockProvider).valueOrNull ?? true;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.navAnalytics),
        actions: [
          IconButton(
            icon: const Icon(Icons.summarize_outlined),
            tooltip: l.pnlTitle,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const PnlScreen(),
            )),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppTheme.space3),
            child: SegmentedButton<AnalyticsRange>(
              segments: [
                ButtonSegment(
                    value: AnalyticsRange.today,
                    label: Text(l.analyticsRangeToday)),
                ButtonSegment(
                    value: AnalyticsRange.week,
                    label: Text(l.analyticsRangeWeek)),
                ButtonSegment(
                    value: AnalyticsRange.month,
                    label: Text(l.analyticsRangeMonth)),
              ],
              selected: {range},
              onSelectionChanged: (s) =>
                  ref.read(analyticsRangeProvider.notifier).state = s.first,
            ),
          ),
          Expanded(
            child: summary.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(l.commonUnexpectedError)),
              data: (s) => _Dashboard(summary: s, trackStock: trackStock),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.summary, required this.trackStock});

  final AnalyticsSummary summary;
  final bool trackStock;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cur = l.currencySymbol;

    return ListView(
      padding: const EdgeInsets.all(AppTheme.space3),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppTheme.space3,
          crossAxisSpacing: AppTheme.space3,
          childAspectRatio: 1.7,
          children: [
            _KpiCard(
                label: l.analyticsRevenue,
                value: Money(summary.revenue).withSymbol(cur),
                icon: Icons.payments,
                color: Colors.teal,
                onTap: () => context.go('/invoices')),
            _KpiCard(
                label: l.analyticsProfit,
                value: Money(summary.profit).withSymbol(cur),
                icon: Icons.trending_up,
                color: Colors.green),
            _KpiCard(
                label: l.analyticsExpenses,
                value: Money(summary.expenses).withSymbol(cur),
                icon: Icons.receipt_long,
                color: Colors.deepOrange,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ExpenseScreen()))),
            _KpiCard(
                label: l.analyticsNetProfit,
                value: Money(summary.netProfit).withSymbol(cur),
                icon: Icons.savings_outlined,
                color: summary.netProfit >= 0 ? Colors.green : Colors.red,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ExpenseScreen()))),
            _KpiCard(
                label: l.analyticsSalesCount,
                value: '${summary.salesCount}',
                icon: Icons.receipt_long,
                color: Colors.indigo,
                onTap: () => context.go('/invoices')),
            if (trackStock)
              _KpiCard(
                  label: l.analyticsStockValue,
                  value: Money(summary.stockValue).withSymbol(cur),
                  icon: Icons.inventory_2,
                  color: Colors.orange,
                  onTap: () => context.go('/inventory')),
            _KpiCard(
                label: l.analyticsCollected,
                value: Money(summary.collected).withSymbol(cur),
                icon: Icons.account_balance,
                color: Colors.blueGrey,
                onTap: () => context.go('/invoices')),
            _KpiCard(
                label: l.analyticsCreditOutstanding,
                value: Money(summary.creditOutstanding).withSymbol(cur),
                icon: Icons.account_balance_wallet,
                color: summary.creditOutstanding > 0
                    ? Colors.red
                    : Colors.green,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const CreditScreen()))),
          ],
        ),
        const SizedBox(height: AppTheme.space3),
        _RevenueChartCard(daily: summary.daily),
        const SizedBox(height: AppTheme.space3),
        _TopProductsCard(top: summary.topProducts),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color,
      this.onTap});

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.all(AppTheme.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium),
              ),
            ]),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        ),
      ),
    );
  }
}

class _RevenueChartCard extends StatelessWidget {
  const _RevenueChartCard({required this.daily});

  final List<DailyRevenue> daily;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final maxY = daily.fold<int>(0, (m, d) => d.revenue > m ? d.revenue : m);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.analyticsDailyRevenue,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppTheme.space3),
            SizedBox(
              height: 160,
              child: maxY == 0
                  ? Center(child: Text(l.analyticsNoData))
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: maxY.toDouble() * 1.15,
                        borderData: FlBorderData(show: false),
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(
                          leftTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          topTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                        ),
                        barGroups: [
                          for (var i = 0; i < daily.length; i++)
                            BarChartGroupData(x: i, barRods: [
                              BarChartRodData(
                                toY: daily[i].revenue.toDouble(),
                                color: scheme.primary,
                                width: daily.length > 14 ? 6 : 12,
                                borderRadius:
                                    const BorderRadius.vertical(
                                        top: Radius.circular(3)),
                              ),
                            ]),
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

class _TopProductsCard extends StatelessWidget {
  const _TopProductsCard({required this.top});

  final List<TopProduct> top;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cur = l.currencySymbol;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.analyticsTopProducts,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppTheme.space2),
            if (top.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppTheme.space3),
                child: Text(l.analyticsNoData),
              )
            else
              ...top.map((p) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: CircleAvatar(
                        radius: 14, child: Text('${p.qty}')),
                    title: Text(p.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Text(Money(p.revenue).withSymbol(cur)),
                  )),
          ],
        ),
      ),
    );
  }
}
