import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/analytics/analytics_accounting_hub_screen.dart';
import '../features/inventory/inventory_screen.dart';
import '../features/onboarding/onboarding_flow.dart';
import '../features/onboarding/onboarding_state.dart';
import '../features/orders/orders_invoices_hub_screen.dart';
import '../features/sell/sell_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/staff/owner_permission.dart';
import '../features/staff/staff_providers.dart';
import '../l10n/app_localizations.dart';
import 'layout.dart';

/// The app's routes — shared by the production [appRouterProvider] and by
/// widget tests that need the real shell/chrome without the onboarding
/// redirect.
List<RouteBase> buildAppRoutes() => [

        // Outside the shell — no bottom nav while onboarding.
        GoRoute(
        path: '/onboarding',
        builder: (_, _) => const Scaffold(
          body: SafeArea(child: OnboardingFlow(routed: true)),
        ),
      ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => _ShellScaffold(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/sell', builder: (_, _) => const SellScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/inventory',
              builder: (_, _) => const InventoryScreen(),
            ),
          ],
        ),
        // Orders + Invoices share ONE bottom-nav destination (sub-tabs inside
        // the hub), so they share ONE branch — but keep both URLs, so existing
        // deep links (analytics_screen.dart's `context.go('/invoices')`) still
        // land on the Invoices sub-tab specifically. The first route is the
        // branch's initial location.
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/orders',
              builder: (_, _) => const OrdersInvoicesHubScreen(
                initialTab: OrdersInvoicesHubScreen.ordersTab,
              ),
            ),
            GoRoute(
              path: '/invoices',
              builder: (_, _) => const OrdersInvoicesHubScreen(
                initialTab: OrdersInvoicesHubScreen.invoicesTab,
              ),
            ),
          ],
        ),
        // Analytics + Accounting share ONE bottom-nav destination (sub-tabs
        // inside the hub), so they share ONE branch — but keep both URLs,
        // mirroring the Orders/Invoices hub above. The first route is the
        // branch's initial location.
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/analytics',
              builder: (_, _) => const AnalyticsAccountingHubScreen(
                initialTab: AnalyticsAccountingHubScreen.analyticsTab,
              ),
            ),
            GoRoute(
              path: '/accounting',
              builder: (_, _) => const AnalyticsAccountingHubScreen(
                initialTab: AnalyticsAccountingHubScreen.accountingTab,
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (_, _) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
  ];

/// Built inside a [Provider] so the redirect guard can read the onboarding
/// state; `app.dart` watches this provider for its `routerConfig`.
final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/sell',
    redirect: (context, state) {
      // First-run onboarding owns the whole screen until done. Read (not
      // watch) here: the flow itself drives leaving via context.go, and
      // GoRouter re-runs this guard on every navigation anyway.
      final needed = ref.read(onboardingStillNeededProvider);
      if (needed && state.matchedLocation != '/onboarding') {
        return '/onboarding';
      }
      // Analytics (and Accounting, its peer tab in the same hub — Accounting
      // was previously only reachable by pushing off the already-gated
      // Analytics screen and must stay exactly as protected now that it's a
      // sibling route, not a nested push) is owner-only (or granted-staff)
      // AT THE ROUTER, not just in the tab bar — a deep link straight to
      // either URL must not render it (audit QA-M5). Fail-closed: while the
      // role stream is still resolving, bounce to Sell; an owner (or a
      // staff member granted the `analytics` capability) gets through once
      // resolved.
      if ((state.matchedLocation.startsWith('/analytics') ||
              state.matchedLocation.startsWith('/accounting')) &&
          !ref.read(hasResolvedOwnerCapabilityProvider(OwnerCapability.analytics))) {
        return '/sell';
      }
      return null;
    },
    routes: buildAppRoutes(),
  );
  // Test containers dispose providers eagerly; a live GoRouter keeps
  // internal observers/scheduled work alive past the tree's teardown.
  ref.onDispose(router.dispose);
  return router;
});

class _ShellScaffold extends ConsumerWidget {
  const _ShellScaffold({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    // Optimistic (not fail-closed) check for tab CHROME visibility only —
    // the actual route is separately fail-closed-gated by
    // `hasResolvedOwnerCapabilityProvider` above. Owner OR a staff member
    // granted the `analytics` capability sees the tab.
    final canSeeAnalytics =
        ref.watch(hasOwnerCapabilityProvider(OwnerCapability.analytics));
    // Tablet (medium+) → rail; phone → bottom bar.
    final wide = isMediumPlus(context);

    // branchIndex matches the StatefulShellBranch order above (fixed —
    // filtering only changes which of these show, never their identity).
    // Five destinations: Orders is the umbrella for the Orders/Invoices hub
    // (sub-tabs inside), which is why `receipt_long` — "a record of a
    // transaction" — covers both halves better than either list's own icon.
    // Analytics is business-sensitive and owner-only; Settings always stays
    // visible even in Staff mode — it's the only way back to Owner (PIN).
    final allDestinations = <_Dest>[
      _Dest(0, Icons.point_of_sale, l.navSell),
      _Dest(1, Icons.inventory_2, l.navInventory),
      _Dest(2, Icons.receipt_long, l.navOrders),
      _Dest(3, Icons.bar_chart, l.navAnalytics, ownerOnly: true),
      _Dest(4, Icons.settings, l.navSettings),
    ];
    final destinations = allDestinations
        .where((d) => !d.ownerOnly || canSeeAnalytics)
        .toList();

    var selectedIndex = destinations.indexWhere(
      (d) => d.branchIndex == shell.currentIndex,
    );
    if (selectedIndex < 0) {
      // The branch we were on just became hidden (e.g. an owner viewing
      // Analytics switched the device to Staff mode) — bounce to Sell rather
      // than crash the nav widget on an out-of-range selected index.
      selectedIndex = 0;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => shell.goBranch(0, initialLocation: true),
      );
    }

    void go(int filteredIndex) {
      final branchIndex = destinations[filteredIndex].branchIndex;
      shell.goBranch(
        branchIndex,
        initialLocation: branchIndex == shell.currentIndex,
      );
    }

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            // Same label cap as the phone nav bar below — the rail is even
            // narrower than one bottom-bar cell, so it fails the same way.
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: _kNavLabelMaxTextScale,
              child: NavigationRail(
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
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shell),
          ],
        ),
      );
    }

    return Scaffold(
      body: shell,
      // Nav labels stop growing at 1.15x (audit: Play-update UI/UX pass).
      // Myanmar destination labels are long — "ကုန်ပစ္စည်း", "စာရင်းအင်း" —
      // and on a 360dp phone (the cheap Android this app is actually sold
      // for) at the system's "Large" font setting they wrapped MID-SYLLABLE,
      // orphaning the final "း" on a second line and crowding the five
      // destinations into each other. Verified on a 360dp Pixel 7: fine at
      // 1.15, broken at 1.3. Every destination still carries its icon, so
      // capping the label — rather than the whole bar — keeps the meaning
      // while the rest of the app scales for the reader as before.
      bottomNavigationBar: MediaQuery.withClampedTextScaling(
        maxScaleFactor: _kNavLabelMaxTextScale,
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: go,
          destinations: [
            for (final d in destinations)
              NavigationDestination(icon: Icon(d.icon), label: d.label),
          ],
        ),
      ),
    );
  }
}

/// Ceiling on how far a navigation destination's label may scale with the
/// system font size. See the note at the `NavigationBar` above for why the
/// Myanmar labels need one, and `nav_label_scale_test.dart` for the case
/// that locks it in.
const double _kNavLabelMaxTextScale = 1.15;

class _Dest {
  final int branchIndex;
  final IconData icon;
  final String label;
  final bool ownerOnly;
  const _Dest(
    this.branchIndex,
    this.icon,
    this.label, {
    this.ownerOnly = false,
  });
}
