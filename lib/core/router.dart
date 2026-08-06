import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/analytics/analytics_screen.dart';
import '../features/inventory/inventory_screen.dart';
import '../features/invoices/invoices_screen.dart';
import '../features/orders/orders_screen.dart';
import '../features/sell/sell_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/staff/staff_providers.dart';
import '../l10n/app_localizations.dart';

final appRouter = GoRouter(
  initialLocation: '/sell',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => _ShellScaffold(shell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/sell', builder: (_, _) => const SellScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/inventory',
              builder: (_, _) => const InventoryScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/orders', builder: (_, _) => const OrdersScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/invoices', builder: (_, _) => const InvoicesScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/analytics',
              builder: (_, _) => const AnalyticsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/settings', builder: (_, _) => const SettingsScreen()),
        ]),
      ],
    ),
  ],
);

class _ShellScaffold extends ConsumerWidget {
  const _ShellScaffold({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final isOwner = ref.watch(isEffectiveOwnerProvider);
    // Tablet (wide) → rail; phone → bottom bar.
    final isWide = MediaQuery.sizeOf(context).width >= 640;

    // branchIndex matches the StatefulShellBranch order above (fixed —
    // filtering only changes which of these show, never their identity).
    // Analytics is business-sensitive and owner-only; Settings always stays
    // visible so account/session controls remain reachable for all roles.
    final allDestinations = <_Dest>[
      _Dest(0, Icons.point_of_sale, l.navSell),
      _Dest(1, Icons.inventory_2, l.navInventory),
      _Dest(2, Icons.dashboard_customize_outlined, l.navOrders),
      _Dest(3, Icons.receipt_long, l.navInvoices),
      _Dest(4, Icons.bar_chart, l.navAnalytics, ownerOnly: true),
      _Dest(5, Icons.settings, l.navSettings),
    ];
    final destinations =
        allDestinations.where((d) => !d.ownerOnly || isOwner).toList();

    var selectedIndex =
        destinations.indexWhere((d) => d.branchIndex == shell.currentIndex);
    if (selectedIndex < 0) {
      // The branch we were on just became hidden (e.g. role changed from owner
      // to staff after auth refresh) — bounce to Sell rather than crash the
      // nav widget on an out-of-range selected index.
      selectedIndex = 0;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => shell.goBranch(0, initialLocation: true));
    }

    void go(int filteredIndex) {
      final branchIndex = destinations[filteredIndex].branchIndex;
      shell.goBranch(branchIndex,
          initialLocation: branchIndex == shell.currentIndex);
    }

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: go,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shell),
          ],
        ),
      );
    }

    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: go,
        destinations: [
          for (final d in destinations)
            NavigationDestination(icon: Icon(d.icon), label: d.label),
        ],
      ),
    );
  }
}

class _Dest {
  final int branchIndex;
  final IconData icon;
  final String label;
  final bool ownerOnly;
  const _Dest(this.branchIndex, this.icon, this.label, {this.ownerOnly = false});
}
