import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../invoices/invoices_screen.dart';
import '../invoices/sales_report_screen.dart';
import 'order_editor_sheet.dart';
import 'orders_screen.dart';

/// One bottom-nav destination hosting the two transaction-record lists as
/// sub-tabs: pre-sale **Social Orders** (Facebook/Viber) and the completed-sale
/// **Invoices** ledger.
///
/// They remain two separate screens with separate data, filters and
/// master–detail state — this merges only their *navigation*, taking the bottom
/// bar from 6 destinations to 5. Both [OrdersScreen] and [InvoicesScreen] are
/// rendered with `embedded: true`, i.e. body-only; this screen owns the single
/// [Scaffold] and swaps its chrome (title / actions / FAB) to whichever sub-tab
/// is selected, because the two lists have genuinely different affordances:
/// Orders has a "new order" FAB and no app-bar action, Invoices has a
/// sales-report action and no FAB.
///
/// The shell routes `/orders` and `/invoices` both land here with a different
/// [initialTab], so every existing deep link (notably Analytics'
/// `context.go('/invoices')`) still resolves to the list it always did.
class OrdersInvoicesHubScreen extends StatefulWidget {
  const OrdersInvoicesHubScreen({super.key, this.initialTab = ordersTab});

  /// Sub-tab shown on first build. Use the named constants, not literals.
  final int initialTab;

  static const int ordersTab = 0;
  static const int invoicesTab = 1;

  @override
  State<OrdersInvoicesHubScreen> createState() =>
      _OrdersInvoicesHubScreenState();
}

class _OrdersInvoicesHubScreenState extends State<OrdersInvoicesHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late int _index = widget.initialTab.clamp(
    OrdersInvoicesHubScreen.ordersTab,
    OrdersInvoicesHubScreen.invoicesTab,
  );

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, initialIndex: _index, vsync: this);
    _tabs.addListener(_onTabChanged);
  }

  /// [TabController] is a [ChangeNotifier] that also fires on every frame of a
  /// swipe (its `offset` changes), so rebuilding unconditionally here would
  /// rebuild the whole Scaffold per frame on a cheap panel. Only the settled
  /// `index` matters for the chrome, so compare before calling `setState`.
  void _onTabChanged() {
    if (!mounted || _tabs.index == _index) return;
    setState(() => _index = _tabs.index);
  }

  @override
  void didUpdateWidget(covariant OrdersInvoicesHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // go_router normally builds a fresh page (and State) per route, but if it
    // ever reuses this element across `/orders` <-> `/invoices`, honour the
    // new deep link. Guarded on a *change* so a plain rebuild never yanks the
    // user off a tab they picked by hand.
    if (widget.initialTab != oldWidget.initialTab) {
      _tabs.index = widget.initialTab.clamp(
        OrdersInvoicesHubScreen.ordersTab,
        OrdersInvoicesHubScreen.invoicesTab,
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
    final onOrders = _index == OrdersInvoicesHubScreen.ordersTab;
    final tabHeight = _subTabHeight(context);

    return Scaffold(
      appBar: AppBar(
        // "Social Orders" is more specific than the tab's "Orders" label, so
        // the title still earns its row rather than echoing the tab.
        title: Text(onOrders ? l.ordersTitle : l.navInvoices),
        actions: [
          if (!onOrders)
            IconButton(
              tooltip: l.salesReportTitle,
              icon: const Icon(Icons.summarize_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SalesReportScreen()),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            _subTab(l.navOrders, tabHeight),
            _subTab(l.navInvoices, tabHeight),
          ],
        ),
      ),
      floatingActionButton: onOrders
          ? FloatingActionButton.extended(
              onPressed: () => OrderEditorSheet.show(context),
              icon: const Icon(Icons.add),
              label: Text(l.orderNew),
            )
          : null,
      body: TabBarView(
        controller: _tabs,
        children: const [
          OrdersScreen(embedded: true),
          InvoicesScreen(embedded: true),
        ],
      ),
    );
  }
}

/// Tab height derived from the label's own line box instead of Material's
/// fixed 46dp, so a Myanmar label with stacked diacritics ("ပြေစာများ") is
/// never clipped and the target stays >= 48dp at any text scale. `TabBar`
/// reads this back off each [Tab]'s `preferredSize`, so the app bar's `bottom`
/// grows with it rather than clipping.
double _subTabHeight(BuildContext context) {
  final theme = Theme.of(context);
  final style = theme.tabBarTheme.labelStyle ?? theme.textTheme.titleSmall;
  final line =
      MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 14) *
      (style?.height ?? 1.4);
  return math.max(48, line + AppTheme.space4);
}

Widget _subTab(String label, double height) =>
    Tab(height: height, child: Text(label, textAlign: TextAlign.center));
