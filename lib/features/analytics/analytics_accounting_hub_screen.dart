import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../accounting/accounting_screen.dart';
import 'analytics_screen.dart';
import 'pnl_screen.dart';

/// One bottom-nav destination hosting the dashboard and the statements it
/// links out to, as sub-tabs: **Analytics** (the KPI dashboard) and
/// **Accounting** (Balance Sheet / Cash Flow / Tax Summary / Year-end
/// Close) — the owner asked for the two placed next to each other rather
/// than Accounting living one tap deep inside Analytics.
///
/// Same navigation-only merge as `OrdersInvoicesHubScreen`: both remain two
/// separate screens with separate data; this only shares their chrome. Both
/// [AnalyticsScreen] and [AccountingScreen] are rendered with
/// `embedded: true`, i.e. body-only — this screen owns the single
/// [Scaffold] and swaps its app-bar action to whichever sub-tab is
/// selected (the "open P&L" shortcut only makes sense on the Analytics
/// tab).
///
/// The shell routes `/analytics` and `/accounting` both land here with a
/// different [initialTab] — mirrors the Orders/Invoices hub's dual-route
/// convention so either URL still resolves to the tab it always implied.
/// Both routes stay behind the SAME router-level owner/capability guard
/// (`core/router.dart`), since Accounting was previously only reachable
/// from inside the already-gated Analytics screen and must stay exactly as
/// protected now that it's a peer tab instead of a nested push.
class AnalyticsAccountingHubScreen extends StatefulWidget {
  const AnalyticsAccountingHubScreen({super.key, this.initialTab = analyticsTab});

  /// Sub-tab shown on first build. Use the named constants, not literals.
  final int initialTab;

  static const int analyticsTab = 0;
  static const int accountingTab = 1;

  @override
  State<AnalyticsAccountingHubScreen> createState() =>
      _AnalyticsAccountingHubScreenState();
}

class _AnalyticsAccountingHubScreenState
    extends State<AnalyticsAccountingHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late int _index = widget.initialTab.clamp(
    AnalyticsAccountingHubScreen.analyticsTab,
    AnalyticsAccountingHubScreen.accountingTab,
  );

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, initialIndex: _index, vsync: this);
    _tabs.addListener(_onTabChanged);
  }

  /// [TabController] is a [ChangeNotifier] that also fires on every frame of
  /// a swipe (its `offset` changes), so rebuilding unconditionally here
  /// would rebuild the whole Scaffold per frame on a cheap panel. Only the
  /// settled `index` matters for the chrome, so compare before calling
  /// `setState`.
  void _onTabChanged() {
    if (!mounted || _tabs.index == _index) return;
    setState(() => _index = _tabs.index);
  }

  @override
  void didUpdateWidget(covariant AnalyticsAccountingHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // go_router normally builds a fresh page (and State) per route, but if
    // it ever reuses this element across `/analytics` <-> `/accounting`,
    // honour the new deep link. Guarded on a *change* so a plain rebuild
    // never yanks the user off a tab they picked by hand.
    if (widget.initialTab != oldWidget.initialTab) {
      _tabs.index = widget.initialTab.clamp(
        AnalyticsAccountingHubScreen.analyticsTab,
        AnalyticsAccountingHubScreen.accountingTab,
      );
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final onAnalytics = _index == AnalyticsAccountingHubScreen.analyticsTab;
    final tabHeight = _subTabHeight(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(onAnalytics ? l.navAnalytics : l.accountingTitle),
        actions: [
          if (onAnalytics)
            IconButton(
              icon: const Icon(Icons.summarize_outlined),
              tooltip: l.pnlTitle,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PnlScreen()),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            _subTab(l.navAnalytics, tabHeight),
            _subTab(l.accountingTitle, tabHeight),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          AnalyticsScreen(embedded: true),
          AccountingScreen(embedded: true),
        ],
      ),
    );
  }
}

/// Tab height derived from the label's own line box instead of Material's
/// fixed 46dp, so a Myanmar label with stacked diacritics is never clipped
/// and the target stays >= 48dp at any text scale. `TabBar` reads this back
/// off each [Tab]'s `preferredSize`, so the app bar's `bottom` grows with
/// it rather than clipping.
double _subTabHeight(BuildContext context) {
  final theme = Theme.of(context);
  final style = theme.tabBarTheme.labelStyle ?? theme.textTheme.titleSmall;
  final line =
      MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 14) *
      (style?.height ?? 1.4);
  return math.max(48, line + AppTheme.space4);
}

Widget _subTab(String label, double height) => Tab(
  height: height,
  child: Text(label, textAlign: TextAlign.center),
);
