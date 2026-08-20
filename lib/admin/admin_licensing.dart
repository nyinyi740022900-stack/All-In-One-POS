part of 'admin_dashboard_screen.dart';

/// Viber-paste extend: email or App Reference ID — nothing else.
/// Reset / offline code / generate key live on Shops, next to the shop they
/// apply to.
class _LicensingPage extends StatelessWidget {
  const _LicensingPage({
    required this.onExtendEmail,
    required this.onExtendDevice,
    required this.onOpenShops,
  });

  final VoidCallback onExtendEmail;
  final VoidCallback onExtendDevice;
  final VoidCallback onOpenShops;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.of(context).muted;
    return ListView(
      padding: const EdgeInsets.all(AppTheme.space4),
      children: [
        Text(
          'Add months to a shop. Email and App Reference ID are only how you '
          'find them — both extend every phone on that shop.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: AppTheme.space4),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoUp = constraints.maxWidth >= 720;
            final cards = [
              _LicensingActionCard(
                icon: Icons.mail_outline,
                title: 'They sent an email',
                body:
                    'Owner or staff login. Finds the shop, then adds months '
                    'to all of its devices.',
                action: 'Extend by email',
                onPressed: onExtendEmail,
              ),
              _LicensingActionCard(
                icon: Icons.phonelink,
                title: 'They sent an App Reference ID',
                body:
                    'From that phone’s License screen. Finds the same shop — '
                    'still adds months to every device, not only that phone.',
                action: 'Extend by device',
                onPressed: onExtendDevice,
              ),
            ];
            if (twoUp) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: AppTheme.space3),
                  Expanded(child: cards[1]),
                ],
              );
            }
            return Column(
              children: [
                cards[0],
                const SizedBox(height: AppTheme.space3),
                cards[1],
              ],
            );
          },
        ),
        const SizedBox(height: AppTheme.space5),
        Text(
          'Need to reset a phone, mint a key, or send an offline code?',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: AppTheme.space2),
        OutlinedButton.icon(
          onPressed: onOpenShops,
          icon: const Icon(Icons.storefront_outlined),
          label: const Text('Open Shops'),
        ),
      ],
    );
  }
}

class _LicensingActionCard extends StatelessWidget {
  const _LicensingActionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconAvatar(icon: icon),
            const SizedBox(height: AppTheme.space3),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTheme.space2),
            Text(body, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: AppTheme.space3),
            FilledButton(onPressed: onPressed, child: Text(action)),
          ],
        ),
      ),
    );
  }
}

class _ExtendIdentifierDialog extends StatefulWidget {
  const _ExtendIdentifierDialog({required this.byEmail, this.initial});
  final bool byEmail;
  final String? initial;
  @override
  State<_ExtendIdentifierDialog> createState() =>
      _ExtendIdentifierDialogState();
}

class _ExtendIdentifierDialogState extends State<_ExtendIdentifierDialog> {
  late final _id = TextEditingController(text: widget.initial ?? '');
  final _months = TextEditingController(text: '1');
  String? _idError;
  String? _monthsError;

  @override
  void dispose() {
    _id.dispose();
    _months.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final byEmail = widget.byEmail;
    return AlertDialog(
      title: Text(byEmail ? 'Extend by email' : 'Extend by device'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            byEmail
                ? 'Finds the shop by account email, then adds months to every '
                      'device on that shop. If they have an account but no '
                      'license yet, this creates one instead.'
                : 'Finds the shop by App Reference ID, then adds months to '
                      'every device on that shop — not only that phone.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.of(context).muted),
          ),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _id,
            autofocus: (widget.initial ?? '').isEmpty,
            keyboardType: byEmail
                ? TextInputType.emailAddress
                : TextInputType.text,
            decoration: InputDecoration(
              labelText: byEmail ? 'Shop account email' : 'App Reference ID',
              errorText: _idError,
            ),
            onChanged: (_) {
              if (_idError != null) setState(() => _idError = null);
            },
          ),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _months,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Extend by (months)',
              errorText: _monthsError,
            ),
            onChanged: (_) {
              if (_monthsError != null) setState(() => _monthsError = null);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final id = _id.text.trim();
            final months = int.tryParse(_months.text.trim());
            setState(() {
              _idError = id.isEmpty
                  ? (byEmail
                        ? 'Enter the shop account email.'
                        : 'Enter the App Reference ID.')
                  : null;
              _monthsError = (months == null || months <= 0)
                  ? 'Enter a whole number of months (1 or more).'
                  : null;
            });
            if (_idError != null || _monthsError != null) return;
            Navigator.pop(context, (id, months!));
          },
          child: const Text('Review'),
        ),
      ],
    );
  }
}

class _ExtendPreviewDialog extends StatelessWidget {
  const _ExtendPreviewDialog({
    required this.shop,
    required this.months,
    required this.byEmail,
    required this.identifier,
  });

  final Map<String, dynamic> shop;
  final int months;
  final bool byEmail;
  final String identifier;

  @override
  Widget build(BuildContext context) {
    final status = '${shop['status']}';
    final willCreate = status == 'no_license';
    final devices = shopDevices(shop, const []);
    return AlertDialog(
      title: Text(willCreate ? 'Create license?' : 'Extend this shop?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${shop['shop_name'] ?? shop['shop_id']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppTheme.space1),
            SelectableText('${shop['shop_id']}'),
            const SizedBox(height: AppTheme.space2),
            Text('Looked up by ${byEmail ? 'email' : 'device'}: $identifier'),
            Text('Email: ${shop['email'] ?? '—'}'),
            Text(
              'Status: ${_statusLabel(status)}  ·  '
              'plan ${shop['plan'] ?? '—'}  ·  '
              'expires ${_date(shop['expires_at'])}',
            ),
            Text('Devices: ${devices.isEmpty ? '—' : devices.length}'),
            const SizedBox(height: AppTheme.space3),
            Text(
              willCreate
                  ? 'No license exists. Confirming creates a paid '
                        'plan for $months month(s).'
                  : 'Will add $months month(s) to every device on this shop.'
                        '${_trialPromoteHint(shop['plan'], months)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(willCreate ? 'Create' : 'Extend'),
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

/// Empty when the shop is already on a paid plan. Admin extend used to
/// leave `plan = 'trial'` in the DB, which the app then showed as
/// "Free trial" even after Support added paid months (#180).
String _trialPromoteHint(Object? plan, int months) {
  final p = '$plan';
  if (p != 'trial' && p != 'free') return '';
  return ' This shop is still labelled $p — extending marks it as '
      '${months >= 12 ? 'Yearly' : 'Monthly'}.';
}
