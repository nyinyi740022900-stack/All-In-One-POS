part of 'admin_dashboard_screen.dart';

class _AdminShell extends StatelessWidget {
  const _AdminShell({
    required this.section,
    required this.pendingCount,
    required this.onSelect,
    required this.title,
    required this.onReload,
    required this.onSignOut,
    required this.body,
  });

  final _AdminSection section;
  final int pendingCount;
  final ValueChanged<_AdminSection> onSelect;
  final String title;
  final VoidCallback? onReload;
  final VoidCallback onSignOut;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 880;
    final rail = _AdminRail(
      section: section,
      pendingCount: pendingCount,
      onSelect: onSelect,
    );
    return Row(
      children: [
        if (wide) rail,
        if (wide) const VerticalDivider(width: 1),
        Expanded(
          child: Scaffold(
            appBar: AppBar(
              title: Text(title),
              leading: wide
                  ? null
                  : Builder(
                      builder: (ctx) => IconButton(
                        tooltip: 'Menu',
                        icon: const Icon(Icons.menu),
                        onPressed: () => Scaffold.of(ctx).openDrawer(),
                      ),
                    ),
              actions: [
                IconButton(
                  tooltip: 'Reload',
                  icon: const Icon(Icons.refresh),
                  onPressed: onReload,
                ),
                IconButton(
                  tooltip: 'Sign out',
                  icon: const Icon(Icons.logout),
                  onPressed: onSignOut,
                ),
              ],
            ),
            drawer: wide ? null : Drawer(child: SafeArea(child: rail)),
            body: body,
          ),
        ),
      ],
    );
  }
}

class _AdminRail extends StatelessWidget {
  const _AdminRail({
    required this.section,
    required this.pendingCount,
    required this.onSelect,
  });

  final _AdminSection section;
  final int pendingCount;
  final ValueChanged<_AdminSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: SizedBox(
        width: 232,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppTheme.space3),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space4,
                AppTheme.space2,
                AppTheme.space4,
                AppTheme.space4,
              ),
              child: Row(
                children: [
                  const BrandMark(size: 36),
                  const SizedBox(width: AppTheme.space2),
                  Expanded(
                    child: Text(
                      'Admin',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _navLabel(context, 'Overview'),
            _item(
              context,
              _AdminSection.dashboard,
              Icons.space_dashboard_outlined,
              'Dashboard',
            ),
            _navLabel(context, 'Daily work'),
            _item(
              context,
              _AdminSection.inbox,
              Icons.inbox_outlined,
              'Inbox',
              badge: pendingCount,
            ),
            _navLabel(context, 'Customers'),
            _item(
              context,
              _AdminSection.shops,
              Icons.storefront_outlined,
              'Shops',
            ),
            _navLabel(context, 'Billing'),
            _item(
              context,
              _AdminSection.payments,
              Icons.payments_outlined,
              'Payments',
            ),
            _navLabel(context, 'Licensing'),
            _item(
              context,
              _AdminSection.licensing,
              Icons.vpn_key_outlined,
              'Licensing',
            ),
            _navLabel(context, 'Growth'),
            _item(
              context,
              _AdminSection.referrals,
              Icons.card_giftcard_outlined,
              'Referrals',
            ),
            _navLabel(context, 'System'),
            _item(context, _AdminSection.settings, Icons.tune, 'Settings'),
          ],
        ),
      ),
    );
  }

  Widget _navLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space4,
        AppTheme.space3,
        AppTheme.space4,
        AppTheme.space1,
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    _AdminSection value,
    IconData icon,
    String label, {
    int badge = 0,
  }) {
    final selected = section == value;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space2),
      child: ListTile(
        selected: selected,
        selectedTileColor: scheme.primaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        leading: Icon(icon, size: 20),
        title: Text(label),
        trailing: badge > 0
            ? StatusPill(label: '$badge', tone: StatusTone.attention)
            : null,
        dense: true,
        onTap: () {
          onSelect(value);
          final scaffold = Scaffold.maybeOf(context);
          if (scaffold?.isDrawerOpen == true) Navigator.pop(context);
        },
      ),
    );
  }
}
