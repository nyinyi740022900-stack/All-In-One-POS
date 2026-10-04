part of 'admin_dashboard_screen.dart';

class _SubscriptionDialog extends StatelessWidget {
  const _SubscriptionDialog({required this.shop});
  final Map<String, dynamic> shop;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.licenseRenewTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${shop['shop_name'] ?? shop['shop_id']}'),
          const SizedBox(height: AppTheme.space3),
          FilledButton(
            onPressed: () => Navigator.pop(context, 1),
            child: Text(l.licensePlanMonthly),
          ),
          const SizedBox(height: AppTheme.space2),
          FilledButton(
            onPressed: () => Navigator.pop(context, 12),
            child: Text(l.licensePlanYearly),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
      ],
    );
  }
}

class _PaymentsPage extends StatelessWidget {
  const _PaymentsPage({
    required this.requests,
    required this.events,
    required this.onConfirm,
    required this.onDecline,
  });

  final List<Map<String, dynamic>> requests;
  final List<Map<String, dynamic>> events;
  final Future<void> Function(Map<String, dynamic>) onConfirm;
  final Future<void> Function(Map<String, dynamic>) onDecline;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Payments'),
              Tab(text: 'Activity'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _RequestsTab(
                  rows: requests,
                  settledOnly: true,
                  onConfirm: onConfirm,
                  onDecline: onDecline,
                ),
                _HistoryTab(rows: events),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
