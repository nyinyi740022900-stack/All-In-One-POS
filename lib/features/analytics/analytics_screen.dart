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
import '../accounting/accounting_screen.dart';
import '../inventory/inventory_providers.dart';
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

    // Business analytics are owner-only — and FAIL CLOSED while the role
    // stream is still resolving, so a cold-start deep link can't render
    // them in Staff mode (audit QA-M5; the router also bounces /analytics).
    if (!ref.watch(isResolvedOwnerProvider)) {
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
          benefits: [l.analyticsBenefit1, l.analyticsBenefit2, l.analyticsBenefit3],
          child: const SizedBox.shrink(),
        ),
      );
    }

    final range = ref.watch(analyticsRangeProvider);
    final summary = ref.watch(analyticsSummaryProvider);
    final trackStock = ref.watch(trackStockProvider).valueOrNull ?? true;
    final lowStockCount = ref.watch(lowStockCountProvider);

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
              loading: () => _DashboardSkeleton(trackStock: trackStock),
              error: (e, _) => EmptyStateView(
                icon: Icons.error_outline,
                title: l.commonUnexpectedError,
                actionLabel: l.commonRetry,
                onAction: () => ref.invalidate(analyticsSummaryProvider),
              ),
              data: (s) => _Dashboard(
                summary: s,
                trackStock: trackStock,
                lowStockCount: lowStockCount,
              ),
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
  const _Dashboard({
    required this.summary,
    required this.trackStock,
    required this.lowStockCount,
  });

  final AnalyticsSummary summary;
  final bool trackStock;
  final int lowStockCount;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cur = l.currencySymbol;

    return ListView(
      padding: const EdgeInsets.all(AppTheme.space3),
      children: [
        _GlanceStrip(
          revenue: Money(summary.revenue).withSymbol(cur),
          salesCount: '${summary.salesCount}',
          lowStockCount: lowStockCount,
          trackStock: trackStock,
        ),
        const SizedBox(height: AppTheme.space3),
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
            // coloured things in the grid. Revenue and sales-count moved up
            // into [_GlanceStrip] so they are not duplicated here.
            // ---------------------------------------------------------------
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
        const SizedBox(height: AppTheme.space4),
        // Accounting, as a CARD on the dashboard rather than only an
        // app-bar glyph inside P&L — the owner asked where the statements
        // went; a visible tile answers that before the question forms.
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(Icons.account_balance_outlined),
            title: Text(l.accountingTitle),
            subtitle: Text(
              l.accountingBalanceSheetSubtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AccountingScreen()),
            ),
          ),
        ),
      ],
    );
  }
}

/// Three equally-weighted glance cells: range revenue, range sales count,
/// and live low-stock (not ranged — stock is "now"). Number on top, label
/// underneath, no icon — a 3-up row on a phone cannot spare StatCard's
/// 32pt plate. Accent is spent only on a non-zero low-stock count.
class _GlanceStrip extends ConsumerWidget {
  const _GlanceStrip({
    required this.revenue,
    required this.salesCount,
    required this.lowStockCount,
    required this.trackStock,
  });

  final String revenue;
  final String salesCount;
  final int lowStockCount;
  final bool trackStock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _GlanceCell(
                value: revenue,
                label: l.analyticsRevenue,
                onTap: () => context.go('/invoices'),
              ),
            ),
            VerticalDivider(width: 1, color: scheme.outlineVariant),
            Expanded(
              child: _GlanceCell(
                value: salesCount,
                label: l.analyticsSalesCount,
                onTap: () => context.go('/invoices'),
              ),
            ),
            if (trackStock) ...[
              VerticalDivider(width: 1, color: scheme.outlineVariant),
              Expanded(
                child: _GlanceCell(
                  value: '$lowStockCount',
                  label: l.inventoryLowStock,
                  tone: lowStockCount > 0 ? StatusTone.attention : null,
                  // Two jobs: arm Inventory's low-stock filter so the list
                  // opens ALREADY narrowed to the problem rows, and reset
                  // the Inventory branch to its ROOT — a bare go() could
                  // otherwise surface whatever screen was last pushed on
                  // that branch's navigator (the owner landed on Stock
                  // Movements this way), and initialLocation guarantees
                  // the product list.
                  onTap: () {
                    // Arm the filter only when there IS something to show —
                    // tapping "0" should just open Inventory, not an empty
                    // filtered list.
                    if (lowStockCount > 0) {
                      ref
                          .read(inventoryLowStockOnlyProvider.notifier)
                          .state = true;
                    }
                    StatefulNavigationShell.of(
                      context,
                    ).goBranch(1, initialLocation: true);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GlanceCell extends StatelessWidget {
  const _GlanceCell({
    required this.value,
    required this.label,
    required this.onTap,
    this.tone,
  });

  final String value;
  final String label;
  final VoidCallback onTap;
  final StatusTone? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = tone?.colors(AppColors.of(context)).on;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.space2,
          vertical: AppTheme.space3,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: MoneyText(
                value,
                textAlign: TextAlign.center,
                emphasis: true,
                color: color,
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: AppTheme.space1),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color ?? theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Same geometry as the real dashboard, with the content replaced by tonal
/// blocks — so switching the range doesn't reflow the page. Deliberately
/// static: a shimmer animation on the glance strip plus six cards is
/// per-frame work a cheap Android panel spends on nothing.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton({required this.trackStock});

  final bool trackStock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glanceCells = trackStock ? 3 : 2;
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
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.space2,
                  vertical: AppTheme.space3,
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < glanceCells; i++) ...[
                        if (i > 0)
                          VerticalDivider(
                            width: 1,
                            color: scheme.outlineVariant,
                          ),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              block(72, 18),
                              const SizedBox(height: AppTheme.space1),
                              block(48, 10),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.space3),
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

/// Which x-axis labelling a daily-revenue chart gets, driven by how many
/// bars the range has (see `_RevenueChartCard`).
enum _ChartLabelMode { none, weekday, sparseDay }

/// Short weekday name for a chart axis, from the ARBs.
///
/// intl's `DateFormat.E` was tried first and rejected twice over: bare, it
/// ignores the app locale entirely (English "Mon" under the Myanmar UI);
/// locale-explicit, `E('my')` emits the FULL Burmese names — ကြာသပတေး and
/// သောကြာ collide into one smear at 7-across on a phone. These ARB strings
/// are the calendar-short forms (ကြာသ for ကြာသပတေး) that fit the slot in
/// both languages.
String _weekdayShortLabel(AppLocalizations l, DateTime day) =>
    switch (day.weekday) {
      DateTime.monday => l.weekdayShortMon,
      DateTime.tuesday => l.weekdayShortTue,
      DateTime.wednesday => l.weekdayShortWed,
      DateTime.thursday => l.weekdayShortThu,
      DateTime.friday => l.weekdayShortFri,
      DateTime.saturday => l.weekdayShortSat,
      _ => l.weekdayShortSun,
    };

class _RevenueChartCard extends StatelessWidget {
  const _RevenueChartCard({required this.daily});

  final List<DailyRevenue> daily;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxY = daily.fold<int>(0, (m, d) => d.revenue > m ? d.revenue : m);
    // Today renders one bar — nothing to distinguish. A 7-day week labels
    // every bar with its weekday and fits the card width. A 30-day month
    // can't: its canvas is widened to ~24pt per day inside a horizontal
    // scroller, so EVERY day gets its label and the owner swipes through
    // the month instead of squinting at sparse ticks that reset at the
    // month boundary (26 → 31 → 1 read as nonsense).
    final labelMode = daily.length > 1 && daily.length <= 7
        ? _ChartLabelMode.weekday
        : daily.length > 7
        ? _ChartLabelMode.sparseDay
        : _ChartLabelMode.none;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: l.analyticsDailyRevenue,
              // The peak figure — still useful as a scale reference even
              // now that gridlines carry most of that job.
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
              height: labelMode == _ChartLabelMode.none ? 160 : 180,
              child: maxY == 0
                  ? EmptyStateView(
                      icon: Icons.bar_chart_outlined,
                      title: l.analyticsNoData,
                    )
                  : labelMode == _ChartLabelMode.sparseDay
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: math.max(daily.length * 24.0, 600.0),
                        child: _chart(context, theme, scheme),
                      ),
                    )
                  : _chart(context, theme, scheme),
            ),
            if (labelMode == _ChartLabelMode.sparseDay) ...[
              const SizedBox(height: AppTheme.space1),
              Text(
                l.chartSwipeHint,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The bar chart itself, shared by the fitted (Today/week) and the
  /// horizontally-scrolling (month) layouts.
  Widget _chart(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final l = AppLocalizations.of(context);
    final daily = this.daily;
    final maxY = daily.fold<int>(0, (m, d) => d.revenue > m ? d.revenue : m);
    final df = DateFormat('MM-dd');
    final dayFmt = DateFormat('d');
    final labelMode = daily.length > 1 && daily.length <= 7
        ? _ChartLabelMode.weekday
        : daily.length > 7
        ? _ChartLabelMode.sparseDay
        : _ChartLabelMode.none;
    final gridInterval = maxY == 0 ? 1.0 : math.max(1.0, maxY * 1.15 / 3);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY.toDouble() * 1.15,
        borderData: FlBorderData(show: false),
        // Light horizontal rules so the bars have a scale to read against
        // at a glance, not just the one peak figure above — kept faint
        // enough not to compete with the bars themselves.
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: gridInterval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
            strokeWidth: 1,
          ),
        ),
        // fl_chart's default tooltip is a hardcoded blue-grey plate
        // printing the raw double ("12000.0"). Themed here so tapping a bar
        // answers "which day, how much?" in the app's own surface + money
        // format.
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
        titlesData: FlTitlesData(
          // No y-axis money labels: the wrapped "221.8K" strings crowded
          // the gutter (owner call — the header's peak figure plus the
          // gridlines carry the scale), and the tooltip has exact numbers.
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
              showTitles: labelMode != _ChartLabelMode.none,
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= daily.length) {
                  return const SizedBox.shrink();
                }
                // Every labelled bar: weekday short forms on the fitted
                // week view, day-of-month on the scrolling month canvas —
                // no sparse ticks, so no month-boundary "31 → 1" confusion.
                return Padding(
                  padding: const EdgeInsets.only(top: AppTheme.space1),
                  child: Text(
                    labelMode == _ChartLabelMode.weekday
                        ? _weekdayShortLabel(l, daily[i].day)
                        : dayFmt.format(daily[i].day),
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < daily.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: daily[i].revenue.toDouble(),
                  // Fill intensity tracks the value against the range's
                  // peak (see [barFillAlpha]) — a quiet day and a peak day
                  // stop looking like the same kind of day.
                  color: scheme.primary.withValues(
                    alpha: barFillAlpha(
                      daily[i].revenue.toDouble(),
                      maxY.toDouble(),
                    ),
                  ),
                  width: daily.length > 14 ? 10 : 12,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3),
                  ),
                ),
              ],
            ),
        ],
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
              ...top.asMap().entries.map(
                (e) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  // The badge shows the *rank*, not the quantity. A badge
                  // reading "11" beside another reading "11" looked like a
                  // broken leaderboard — a circled figure in the lead slot
                  // of a list titled "Top products" reads as position, so
                  // the quantity now says so in words underneath instead.
                  leading: IconAvatar(text: '${e.key + 1}', size: 32),
                  // Two lines, not an ellipsis: a Myanmar product name runs
                  // ~20-40% longer and a truncated one is unidentifiable.
                  title: Text(e.value.name, maxLines: 2),
                  subtitle: Text(
                    l.analyticsUnitsSold(e.value.qty),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: MoneyText(Money(e.value.revenue).withSymbol(cur)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
