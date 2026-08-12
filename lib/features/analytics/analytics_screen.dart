import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
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
        body: const OwnerOnlyGate(
          capability: OwnerCapability.analytics,
          child: SizedBox.shrink(),
        ),
      );
    }
    if (ref.watch(licenseControllerProvider).loading ||
        !ref.watch(isPremiumProvider)) {
      return Scaffold(
        appBar: AppBar(title: Text(l.navAnalytics)),
        body: PremiumGate(
          featureName: l.navAnalytics,
          child: const SizedBox.shrink(),
        ),
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
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const PnlScreen())),
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
                  label: Text(l.analyticsRangeToday),
                ),
                ButtonSegment(
                  value: AnalyticsRange.week,
                  label: Text(l.analyticsRangeWeek),
                ),
                ButtonSegment(
                  value: AnalyticsRange.month,
                  label: Text(l.analyticsRangeMonth),
                ),
              ],
              selected: {range},
              onSelectionChanged: (s) =>
                  ref.read(analyticsRangeProvider.notifier).state = s.first,
            ),
          ),
          Expanded(
            child: summary.when(
              // A centred spinner here used to collapse the whole dashboard to
              // a dot and then snap the grid back in — the range segmented
              // button above it is tapped constantly, so that reflow happened
              // on every switch. The skeleton keeps the page's shape.
              loading: () => const _DashboardSkeleton(),
              error: (e, _) => EmptyStateView(
                icon: Icons.error_outline,
                title: l.commonUnexpectedError,
              ),
              data: (s) => _Dashboard(summary: s, trackStock: trackStock),
            ),
          ),
        ],
      ),
    );
  }
}

/// Height one KPI tile needs, derived from the *scaled* type scale rather than
/// a fixed `childAspectRatio`.
///
/// A ratio ties tile height to whatever width the column split happened to
/// produce, so the same tile is a different height on a phone and a tablet
/// while its contents are identical — and at 1.3x text scale, with a Myanmar
/// label running two lines ("ကြွေးကျန်ငွေ"), the old `1.7` clipped the label
/// and fell back to an ellipsis on a *primary* label.
double _kpiTileExtent(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  // labelMedium 12/1.45 (two lines), titleLarge 19/1.35 (one value line).
  final labelBlock = math.max(32.0, scaler.scale(12) * 1.45 * 2);
  final valueLine = scaler.scale(19) * 1.35;
  return AppTheme.space3 * 2 + labelBlock + AppTheme.space2 + valueLine;
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
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: AppTheme.space3,
            crossAxisSpacing: AppTheme.space3,
            mainAxisExtent: _kpiTileExtent(context),
          ),
          children: [
            // ---------------------------------------------------------------
            // Colour in this grid is a SIGNAL, not a category label.
            //
            // These eight tiles used to carry six raw Material hues
            // (teal/green/deepOrange/indigo/orange/blueGrey) as decorative
            // per-category coding, alongside two tiles that used
            // `AppColors.success`/`danger` to mean the figure is actually
            // good or bad. Rendered in the same channel, at the same size,
            // the meaningful red on "credit outstanding" was just the
            // seventh colour in a rainbow — the one thing on the screen that
            // needs to be unmissable was the easiest thing to miss.
            //
            // Four of those six also failed the 3:1 non-text contrast
            // minimum in at least one brightness against this palette
            // (measured, not assumed): `Colors.green` 2.6:1 and
            // `Colors.orange` 2.0:1 and `Colors.deepOrange` 2.9:1 on the
            // light page `#F6F8F7`; `Colors.indigo` 2.7:1 on the dark page
            // `#101512`. And `Colors.green` specifically sat next to the
            // brand green, so one arbitrary category read as "selected".
            //
            // Rebuilding them as a proper categorical token set would have
            // meant inventing and contrast-checking twelve new colours (six
            // per brightness) that all had to stay clear of `primary`,
            // `success`, `warning`, `danger` *and* the four `identityFills`
            // — to re-encode information the icon and the label already
            // carry. So: informational tiles are neutral (`tone: null`), and
            // the accent is spent only where the *sign* of the number is the
            // news. Net profit and credit outstanding are now the only
            // coloured things in the grid.
            // ---------------------------------------------------------------
            StatCard(
              label: l.analyticsRevenue,
              value: Money(summary.revenue).withSymbol(cur),
              icon: Icons.payments,
              onTap: () => context.go('/invoices'),
            ),
            StatCard(
              label: l.analyticsProfit,
              value: Money(summary.profit).withSymbol(cur),
              icon: Icons.trending_up,
            ),
            StatCard(
              label: l.analyticsExpenses,
              value: Money(summary.expenses).withSymbol(cur),
              icon: Icons.receipt_long,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ExpenseScreen())),
            ),
            StatCard(
              label: l.analyticsNetProfit,
              value: Money(summary.netProfit).withSymbol(cur),
              icon: Icons.savings_outlined,
              // Losing money is the one thing on this screen worth shouting
              // about; breaking even or better is not a badge, so it stays
              // quiet rather than turning green.
              tone: summary.netProfit < 0 ? StatusTone.critical : null,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ExpenseScreen())),
            ),
            StatCard(
              label: l.analyticsSalesCount,
              value: '${summary.salesCount}',
              icon: Icons.receipt_long,
              onTap: () => context.go('/invoices'),
            ),
            if (trackStock)
              StatCard(
                label: l.analyticsStockValue,
                value: Money(summary.stockValue).withSymbol(cur),
                icon: Icons.inventory_2,
                onTap: () => context.go('/inventory'),
              ),
            StatCard(
              label: l.analyticsCollected,
              value: Money(summary.collected).withSymbol(cur),
              icon: Icons.account_balance,
              onTap: () => context.go('/invoices'),
            ),
            StatCard(
              label: l.analyticsCreditOutstanding,
              value: Money(summary.creditOutstanding).withSymbol(cur),
              icon: Icons.account_balance_wallet,
              // Money owed to the shop is a to-do, not an emergency — amber,
              // the same tone the Orders list gives an order still waiting on
              // someone. Zero owed needs no colour at all.
              tone: summary.creditOutstanding > 0
                  ? StatusTone.attention
                  : null,
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const CreditScreen())),
            ),
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

/// Same geometry as the real dashboard, with the content replaced by tonal
/// blocks — so switching the range doesn't reflow the page. Deliberately
/// static: a shimmer animation on eight cards is per-frame work a cheap
/// Android panel spends on nothing.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget block(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
      ),
    );

    return IgnorePointer(
      child: ExcludeSemantics(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.space3),
          physics: const NeverScrollableScrollPhysics(),
          children: [
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: AppTheme.space3,
                crossAxisSpacing: AppTheme.space3,
                mainAxisExtent: _kpiTileExtent(context),
              ),
              children: [
                for (var i = 0; i < 6; i++)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.space3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              block(32, 32),
                              const SizedBox(width: AppTheme.space2),
                              Expanded(child: block(double.infinity, 10)),
                            ],
                          ),
                          block(96, 18),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.space3),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.space3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    block(140, 14),
                    const SizedBox(height: AppTheme.space3),
                    block(double.infinity, 160),
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

class _RevenueChartCard extends StatelessWidget {
  const _RevenueChartCard({required this.daily});

  final List<DailyRevenue> daily;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxY = daily.fold<int>(0, (m, d) => d.revenue > m ? d.revenue : m);
    final df = DateFormat('MM-dd');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: l.analyticsDailyRevenue,
              // The bars carry no axis labels (there is no room for 30 of
              // them on a phone), so the peak is the only scale reference the
              // chart can give at a glance without being tapped.
              trailing: maxY == 0
                  ? null
                  : MoneyText(
                      Money(maxY).withSymbol(l.currencySymbol),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
            ),
            SizedBox(
              height: 160,
              child: maxY == 0
                  ? EmptyStateView(
                      icon: Icons.bar_chart_outlined,
                      title: l.analyticsNoData,
                    )
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: maxY.toDouble() * 1.15,
                        borderData: FlBorderData(show: false),
                        gridData: const FlGridData(show: false),
                        // fl_chart's default tooltip is a hardcoded blue-grey
                        // plate printing the raw double ("12000.0"). Themed
                        // here so tapping a bar answers "which day, how
                        // much?" in the app's own surface + money format.
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (_) => scheme.inverseSurface,
                            tooltipRoundedRadius: AppTheme.radiusSm,
                            getTooltipItem: (group, _, rod, _) {
                              final day = daily[group.x].day;
                              return BarTooltipItem(
                                '${df.format(day)}\n'
                                '${Money(rod.toY.round()).withSymbol(l.currencySymbol)}',
                                theme.textTheme.labelMedium!.copyWith(
                                  color: scheme.onInverseSurface,
                                  fontFeatures: AppTheme.tabularFigures,
                                ),
                              );
                            },
                          ),
                        ),
                        titlesData: const FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        barGroups: [
                          for (var i = 0; i < daily.length; i++)
                            BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: daily[i].revenue.toDouble(),
                                  color: scheme.primary,
                                  width: daily.length > 14 ? 6 : 12,
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
            SectionHeader(title: l.analyticsTopProducts),
            if (top.isEmpty)
              EmptyStateView(
                icon: Icons.leaderboard_outlined,
                title: l.analyticsNoData,
              )
            else
              ...top.map(
                (p) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  // The qty was a `CircleAvatar`, whose M3 default fill is
                  // `primaryContainer` — the app's "selected/primary" green.
                  // A stack of them competed with the tiles above.
                  leading: IconAvatar(text: '${p.qty}', size: 32),
                  // Two lines, not an ellipsis: a Myanmar product name runs
                  // ~20-40% longer and a truncated one is unidentifiable.
                  title: Text(p.name, maxLines: 2),
                  trailing: MoneyText(Money(p.revenue).withSymbol(cur)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
