import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/currency_def.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../credit/credit_screen.dart';
import '../expenses/expense_screen.dart';
import '../inventory/inventory_providers.dart';
import '../license/license_providers.dart';
import '../printing/printing_providers.dart';
import '../staff/staff_providers.dart';
import '../staff/staff_ui.dart';
import '../invoices/cashier_label.dart';
import 'analytics_calculator.dart';
import 'analytics_providers.dart';
import 'pnl_screen.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key, this.embedded = false});

  /// When true, builds only the body — no [Scaffold]/[AppBar] — so
  /// `AnalyticsAccountingHubScreen` can host it under its own chrome as a
  /// sub-tab (same convention as `OrdersScreen`/`InvoicesScreen`'s
  /// `embedded`). The hub owns the "open P&L" app-bar action in that case.
  /// Default (false) keeps the original standalone full-screen behaviour.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);

    // Business analytics are owner-only (or granted-staff) — and FAIL
    // CLOSED while the role stream is still resolving, so a cold-start deep
    // link can't render them in Staff mode (audit QA-M5; the router also
    // bounces /analytics on the same check).
    if (!ref.watch(
      hasResolvedOwnerCapabilityProvider(OwnerCapability.analytics),
    )) {
      const gate = OwnerOnlyGate(
        capability: OwnerCapability.analytics,
        child: SizedBox.shrink(),
      );
      if (embedded) return gate;
      return Scaffold(
        appBar: AppBar(title: Text(l.navAnalytics)),
        body: gate,
      );
    }
    // Every owner can read the core sales totals. Premium gates only the
    // advanced sections, so a lapse never hides the day's takings.
    final premium = ref.watch(isPremiumProvider);

    final range = ref.watch(analyticsRangeProvider);
    final summary = ref.watch(analyticsSummaryProvider);
    final trackStock = ref.watch(trackStockProvider).valueOrNull ?? true;
    final lowStockCount = ref.watch(lowStockCountProvider);

    final body = Column(
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
    );

    if (embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.navAnalytics),
        actions: [
          if (premium) IconButton(
            icon: const Icon(Icons.summarize_outlined),
            tooltip: l.pnlTitle,
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const PnlScreen())),
          ),
        ],
      ),
      body: body,
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

class _Dashboard extends ConsumerWidget {
  const _Dashboard({
    required this.summary,
    required this.trackStock,
    required this.lowStockCount,
  });

  final AnalyticsSummary summary;
  final bool trackStock;
  final int lowStockCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final currency = ref.watch(shopCurrencyProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final premium = ref.watch(isPremiumProvider);
    final previousSummary = premium
        ? ref.watch(analyticsPreviousSummaryProvider).valueOrNull
        : null;
    final revenueChangePercent = previousSummary == null
        ? null
        : periodOverPeriodChange(summary.revenue, previousSummary.revenue);

    final profitTiles = <Widget>[
      StatCard(
        label: l.analyticsProfit,
        value: Money(summary.profit).withCurrency(currency, locale),
        icon: Icons.trending_up,
      ),
      StatCard(
        label: l.analyticsNetProfit,
        value: Money(summary.netProfit).withCurrency(currency, locale),
        icon: Icons.savings_outlined,
        // Losing money is the one thing worth shouting about; breaking even
        // or better is not a badge, so it stays quiet rather than green.
        tone: summary.netProfit < 0 ? StatusTone.critical : null,
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ExpenseScreen())),
      ),
      // Zero expenses / zero stock value is "nothing to report" — the tile is
      // left out rather than shown as a row of zeros.
      if (summary.expenses != 0)
        StatCard(
          label: l.analyticsExpenses,
          value: Money(summary.expenses).withCurrency(currency, locale),
          icon: Icons.receipt_long,
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ExpenseScreen())),
        ),
      if (trackStock && summary.stockValue != 0)
        StatCard(
          label: l.analyticsStockValue,
          value: Money(summary.stockValue).withCurrency(currency, locale),
          icon: Icons.inventory_2,
          onTap: () => context.go('/inventory'),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.all(AppTheme.space3),
      children: [
        // Colour here is a SIGNAL, not a category label: the only accents are
        // an amber Owed (money to chase) and a red net loss inside Profit.
        _GlanceStrip(
          sales: Money(summary.revenue).withCurrency(currency, locale),
          salesChangePercent: revenueChangePercent,
          collected: Money(summary.collected).withCurrency(currency, locale),
          owed: Money(summary.creditOutstanding).withCurrency(currency, locale),
          owedIsZero: summary.creditOutstanding <= 0,
        ),
        if (summary.salesCount > 0 || (trackStock && lowStockCount > 0)) ...[
          const SizedBox(height: AppTheme.space2),
          Wrap(
            spacing: AppTheme.space2,
            runSpacing: AppTheme.space2,
            children: [
              if (summary.salesCount > 0)
                ActionChip(
                  avatar: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: Text(l.analyticsSalesCountChip(summary.salesCount)),
                  onPressed: () => context.go('/invoices'),
                ),
              if (trackStock && lowStockCount > 0)
                ActionChip(
                  avatar: const Icon(Icons.warning_amber_rounded, size: 18),
                  label: Text('${l.inventoryLowStock}: $lowStockCount'),
                  // Arm Inventory's low-stock filter and reset that branch to
                  // its ROOT so the list opens already narrowed to the
                  // problem rows (a bare go() could surface whatever screen
                  // was last pushed on that branch).
                  onPressed: () {
                    ref.read(inventoryLowStockOnlyProvider.notifier).state =
                        true;
                    StatefulNavigationShell.of(
                      context,
                    ).goBranch(1, initialLocation: true);
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: AppTheme.space3),
        // Profit lives behind its own labelled fold: it is the owner's
        // end-of-week question, not the every-visit one.
        if (premium) Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const Icon(Icons.trending_up),
            title: Text(l.analyticsProfitSection),
            subtitle: Text(l.analyticsProfitSectionSubtitle),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppTheme.space3,
              0,
              AppTheme.space3,
              AppTheme.space3,
            ),
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
                children: profitTiles,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.space3),
        if (premium) _RevenueChartCard(daily: summary.daily),
        const SizedBox(height: AppTheme.space3),
        if (premium) _TopProductsCard(top: summary.topProducts),
        const SizedBox(height: AppTheme.space3),
        if (premium) _SalesByEmployeeCard(rows: summary.salesByStaff),
      ],
    );
  }
}

/// The three numbers the owner opens this screen for: **Sales** (billed in
/// the range), **Collected** (cash actually in) and **Owed** (still to chase).
/// Number on top, label underneath, no icon. Owed gets the amber accent only
/// when it is non-zero.
class _GlanceStrip extends StatelessWidget {
  const _GlanceStrip({
    required this.sales,
    this.salesChangePercent,
    required this.collected,
    required this.owed,
    required this.owedIsZero,
  });

  final String sales;
  final double? salesChangePercent;
  final String collected;
  final String owed;
  final bool owedIsZero;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // The cell width is measured HERE (outside the IntrinsicHeight, which
    // cannot host a LayoutBuilder) and handed down, so each figure can be
    // sized to fit a known, bounded width — see [_GlanceCell].
    return LayoutBuilder(
      builder: (context, box) {
        final cellWidth = (box.maxWidth - 2) / 3;
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _GlanceCell(
                    value: sales,
                    cellWidth: cellWidth,
                    changePercent: salesChangePercent,
                    label: l.analyticsSalesHeadline,
                    onTap: () => context.go('/invoices'),
                  ),
                ),
                VerticalDivider(width: 1, color: scheme.outlineVariant),
                Expanded(
                  child: _GlanceCell(
                    value: collected,
                    cellWidth: cellWidth,
                    label: l.analyticsCollected,
                    onTap: () => context.go('/invoices'),
                  ),
                ),
                VerticalDivider(width: 1, color: scheme.outlineVariant),
                Expanded(
                  child: _GlanceCell(
                    value: owed,
                    cellWidth: cellWidth,
                    label: l.analyticsOwed,
                    tone: owedIsZero ? null : StatusTone.attention,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CreditScreen()),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GlanceCell extends StatelessWidget {
  const _GlanceCell({
    required this.value,
    required this.label,
    required this.onTap,
    required this.cellWidth,
    this.tone,
    this.changePercent,
  });

  final String value;

  /// Width the strip gave this cell; the figure is sized to fit inside it.
  final double cellWidth;
  final String label;
  final VoidCallback onTap;
  final StatusTone? tone;

  /// vs the immediately-preceding period of the same length (yesterday for
  /// "today", the prior 7 days for "week", etc.) — null when there's no
  /// previous-period figure to compare against yet ([periodOverPeriodChange]
  /// returns null for a zero base), in which case no trend row is shown at
  /// all rather than a misleading "+∞%" or a silently-omitted comparison
  /// that looks the same as "unchanged."
  final double? changePercent;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final color = tone?.colors(colors).on;
    final change = changePercent;
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
            // The figure shrinks to fit its cell instead of truncating (a money
            // figure must never show an ellipsis). Measured with a
            // TextPainter against a BOUNDED width: a FittedBox here laid the
            // text out unbounded, and on iOS that mis-measured the Myanmar
            // currency suffix so it was clipped / ellipsised.
            Builder(
              builder: (context) {
                final base = theme.textTheme.titleLarge!.copyWith(
                  fontFeatures: AppTheme.tabularFigures,
                  fontWeight: FontWeight.w700,
                  color: color ?? theme.textTheme.titleLarge?.color,
                );
                final avail = cellWidth - AppTheme.space2 * 2;
                final painter = TextPainter(
                  text: TextSpan(text: value, style: base),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                  maxLines: 1,
                )..layout();
                final scale = painter.width > avail
                    ? (avail / painter.width).clamp(0.5, 1.0)
                    : 1.0;
                painter.dispose();
                return SizedBox(
                  width: avail,
                  child: Text(
                    value,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: base.copyWith(
                      fontSize: (base.fontSize ?? 19) * scale,
                    ),
                  ),
                );
              },
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
            if (change != null) ...[
              const SizedBox(height: AppTheme.space1),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    change >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 12,
                    color: change >= 0 ? colors.success : colors.warning,
                  ),
                  Text(
                    l.analyticsTrendVsPrevious(
                      change >= 0 ? '+' : '-',
                      change.round().abs(),
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: change >= 0 ? colors.success : colors.warning,
                    ),
                  ),
                ],
              ),
            ],
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
    const glanceCells = 3;
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
            // The collapsed Profit fold.
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.space4),
                child: block(120, 16),
              ),
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

class _RevenueChartCard extends ConsumerWidget {
  const _RevenueChartCard({required this.daily});

  final List<DailyRevenue> daily;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = ref.watch(shopCurrencyProvider);
    final locale = Localizations.localeOf(context).languageCode;
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
                      Money(maxY).withCurrency(currency, locale),
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
                        child: _chart(context, theme, scheme, currency, locale),
                      ),
                    )
                  : _chart(context, theme, scheme, currency, locale),
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
    CurrencyDef currency,
    String locale,
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
                '${Money(rod.toY.round()).withCurrency(currency, locale)}',
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

/// Revenue attributed per cashier for the selected range — the data
/// (`Sales.staffId`) has existed since staff accountability shipped, but
/// nothing surfaced it as a report until now. Rows are resolved from raw
/// `staffId`s (see [StaffRevenue]'s doc comment) via the same
/// [cashierNameForSale] rule invoices/receipts use, then re-merged by the
/// resolved label — a deleted roster member's old sales and a genuine
/// owner-mode sale both resolve to the "Owner" label and must combine into
/// one row, not show as two.
class _SalesByEmployeeCard extends ConsumerWidget {
  const _SalesByEmployeeCard({required this.rows});

  final List<StaffRevenue> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final currency = ref.watch(shopCurrencyProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final members = ref.watch(staffMembersProvider).valueOrNull ?? const [];
    final memberPairs = [for (final m in members) (id: m.id, name: m.name)];

    final revenueByLabel = <String, int>{};
    final countByLabel = <String, int>{};
    for (final r in rows) {
      final label = cashierNameForSale(
        staffId: r.staffId,
        members: memberPairs,
        ownerLabel: l.staffRoleOwner,
      );
      revenueByLabel[label] = (revenueByLabel[label] ?? 0) + r.revenue;
      countByLabel[label] = (countByLabel[label] ?? 0) + r.salesCount;
    }
    final merged =
        revenueByLabel.entries
            .map(
              (e) => (
                label: e.key,
                revenue: e.value,
                count: countByLabel[e.key] ?? 0,
              ),
            )
            .toList()
          ..sort((a, b) => b.revenue.compareTo(a.revenue));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: l.analyticsSalesByEmployee),
            if (merged.isEmpty)
              EmptyStateView(
                icon: Icons.people_outline,
                title: l.analyticsNoData,
              )
            else
              ...merged.map(
                (e) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const IconAvatar(icon: Icons.badge_outlined),
                  title: Text(e.label),
                  subtitle: Text(
                    l.salesReportCount(e.count),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: MoneyText(
                    Money(e.revenue).withCurrency(currency, locale),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopProductsCard extends ConsumerWidget {
  const _TopProductsCard({required this.top});

  final List<TopProduct> top;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final currency = ref.watch(shopCurrencyProvider);
    final locale = Localizations.localeOf(context).languageCode;
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
                  trailing: MoneyText(
                    Money(e.value.revenue).withCurrency(currency, locale),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
