part of 'admin_dashboard_screen.dart';

class _LicensesTab extends StatelessWidget {
  const _LicensesTab({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Center(child: Text('No licenses yet.'));
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = rows[i];
        final status = '${r['status']}';
        return ListTile(
          leading: Icon(Icons.vpn_key,
              color: status == 'active' ? Colors.green : Colors.orange),
          title: SelectableText('${r['key']}'),
          subtitle: Text(
              'Shop: ${r['shop_id']}  ·  ${r['plan']}  ·  $status\n'
              'Expires: ${_date(r['expires_at'])}  ·  '
              'Device: ${r['device_id'] ?? '—'}'),
          isThreeLine: true,
        );
      },
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(child: Text('No key issues / renewals yet.'));
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = rows[i];
        final isExtend = r['action'] == 'extend';
        return ListTile(
          leading: Icon(isExtend ? Icons.more_time : Icons.vpn_key,
              color: isExtend ? Colors.blue : Colors.green),
          title: Text(
              '${isExtend ? 'Extended' : 'Issued'}  ·  ${r['months']} mo  ·  ${r['shop_name'] ?? '—'}'),
          subtitle: Text(
              'Key: ${r['key']}  ·  Device: ${r['device_id'] ?? '—'}\n'
              'New expiry: ${_date(r['expires_at'])}  ·  ${_date(r['created_at'])}'),
          isThreeLine: true,
        );
      },
    );
  }
}

class _RequestsTab extends StatelessWidget {
  const _RequestsTab({required this.rows, required this.onIssue});
  final List<Map<String, dynamic>> rows;
  final Future<void> Function(Map<String, dynamic>) onIssue;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(child: Text('No subscription requests.'));
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = rows[i];
        final fulfilled = r['status'] == 'fulfilled';
        final proofPath = r['payment_proof_path'] as String?;
        return ListTile(
          leading: Icon(
            fulfilled ? Icons.check_circle : Icons.hourglass_top,
            color: fulfilled ? Colors.green : Colors.orange,
          ),
          title: Text(
              '${r['shop_name']}  ·  ${r['amount']} Ks  ·  ${r['method']}  ·  ${r['months']} mo  ·  ${r['tier'] ?? 'offline'}'),
          subtitle: Text(
              'Phone: ${r['phone'] ?? '—'}  ·  Txn: ${r['ref_no'] ?? '—'}\n'
              'Device: ${r['device_id'] ?? '—'}  ·  ${_date(r['created_at'])}'
              '${fulfilled ? '  ·  Key: ${r['issued_key']}' : ''}'),
          isThreeLine: true,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (proofPath != null && proofPath.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _showProof(context, proofPath),
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('Screenshot'),
                ),
              if (fulfilled)
                const Text('Issued')
              else
                FilledButton(
                  onPressed: () => onIssue(r),
                  child: const Text('Issue key'),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showProof(BuildContext context, String path) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Payment screenshot'),
        content: SizedBox(
          width: 400,
          child: _RequestProofImage(path: path),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _ReferralsTab extends StatelessWidget {
  const _ReferralsTab({
    required this.commissions,
    required this.referrals,
    required this.onApplyCredit,
  });

  final List<Map<String, dynamic>> commissions;
  final List<Map<String, dynamic>> referrals;
  final Future<void> Function(String shopId) onApplyCredit;

  Future<void> _confirmApplyCredit(
      BuildContext context, String shopId, int balance) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apply referral credit?'),
        content: Text(
            'Converts as much of $shopId\'s $balance Ks referral balance as '
            'covers full months into a license extension for that shop, and '
            'deducts it from their balance. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apply')),
        ],
      ),
    );
    if (ok == true) await onApplyCredit(shopId);
  }

  @override
  Widget build(BuildContext context) {
    if (commissions.isEmpty && referrals.isEmpty) {
      return const Center(child: Text('No referrals or commissions yet.'));
    }

    // Aggregate lifetime earned + payment count per referrer.
    final earned = <String, int>{};
    final counts = <String, int>{};
    for (final c in commissions) {
      final sid = '${c['referrer_shop_id']}';
      earned[sid] = (earned[sid] ?? 0) + ((c['amount'] as num?)?.toInt() ?? 0);
      counts[sid] = (counts[sid] ?? 0) + 1;
    }
    final referrers = earned.keys.toList()
      ..sort((a, b) => (earned[b] ?? 0).compareTo(earned[a] ?? 0));

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('Commissions by referrer',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        if (referrers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('No commissions earned yet.'),
          )
        else
          for (final sid in referrers)
            ListTile(
              leading: const Icon(Icons.card_giftcard, color: Colors.green),
              title: SelectableText(sid),
              subtitle: Text(
                  '${counts[sid]} payment(s)  ·  earned ${earned[sid]} Ks'),
              trailing: FilledButton(
                onPressed: () => _confirmApplyCredit(context, sid, earned[sid] ?? 0),
                child: const Text('Apply credit'),
              ),
            ),
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text('Referral links (${referrals.length})',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        if (referrals.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('No referral links yet.'),
          )
        else
          for (final r in referrals)
            ListTile(
              dense: true,
              leading: Icon(
                (r['is_active'] == true) ? Icons.link : Icons.link_off,
                color: (r['is_active'] == true) ? Colors.blue : Colors.grey,
              ),
              title: Text('${r['referral_code']}  ·  ${r['referrer_shop_id']}'),
              subtitle: Text(
                  'referred: ${r['referred_shop_id']}  ·  ${_date(r['created_at'])}'),
            ),
      ],
    );
  }
}

class _GenerateKeyDialog extends StatefulWidget {
  const _GenerateKeyDialog();
  @override
  State<_GenerateKeyDialog> createState() => _GenerateKeyDialogState();
}

class _GenerateKeyDialogState extends State<_GenerateKeyDialog> {
  final _shopId = TextEditingController();
  final _shopName = TextEditingController();
  final _months = TextEditingController(text: '1');
  String _plan = 'monthly';

  @override
  void dispose() {
    _shopId.dispose();
    _shopName.dispose();
    _months.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Generate license key'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _shopId,
            decoration: const InputDecoration(
                labelText: 'Shop ID (any stable identifier)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _shopName,
            decoration:
                const InputDecoration(labelText: 'Shop name (display)'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _plan,
            decoration: const InputDecoration(labelText: 'Plan'),
            items: const [
              DropdownMenuItem(value: 'monthly', child: Text('monthly')),
              DropdownMenuItem(value: 'yearly', child: Text('yearly')),
            ],
            onChanged: (v) => setState(() => _plan = v ?? 'monthly'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _months,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Duration (months)'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final shop = _shopId.text.trim();
            if (shop.isEmpty) return;
            Navigator.pop(
              context,
              _KeyRequest(
                shopId: shop,
                shopName: _shopName.text.trim(),
                plan: _plan,
                months: int.tryParse(_months.text.trim()) ?? 1,
              ),
            );
          },
          child: const Text('Generate'),
        ),
      ],
    );
  }
}

class _OfflineRequest {
  final String shopId;
  final String shopName;
  final String plan;
  final int months;
  final String deviceId;
  const _OfflineRequest(
      this.shopId, this.shopName, this.plan, this.months, this.deviceId);
}

class _OfflineCodeDialog extends StatefulWidget {
  const _OfflineCodeDialog();
  @override
  State<_OfflineCodeDialog> createState() => _OfflineCodeDialogState();
}

class _OfflineCodeDialogState extends State<_OfflineCodeDialog> {
  final _shopId = TextEditingController();
  final _shopName = TextEditingController();
  final _months = TextEditingController(text: '1');
  final _device = TextEditingController();
  String _plan = 'monthly';

  @override
  void dispose() {
    for (final c in [_shopId, _shopName, _months, _device]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Generate offline code'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: _shopId,
                decoration: const InputDecoration(labelText: 'Shop ID')),
            const SizedBox(height: 8),
            TextField(
                controller: _shopName,
                decoration: const InputDecoration(labelText: 'Shop name')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _plan,
              decoration: const InputDecoration(labelText: 'Plan'),
              items: const [
                DropdownMenuItem(value: 'monthly', child: Text('monthly')),
                DropdownMenuItem(value: 'yearly', child: Text('yearly')),
              ],
              onChanged: (v) => setState(() => _plan = v ?? 'monthly'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _months,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Duration (months)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _device,
              decoration: const InputDecoration(
                  labelText: 'Bind to App Reference ID (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final shop = _shopId.text.trim();
            if (shop.isEmpty) return;
            Navigator.pop(
              context,
              _OfflineRequest(
                shop,
                _shopName.text.trim(),
                _plan,
                int.tryParse(_months.text.trim()) ?? 1,
                _device.text.trim(),
              ),
            );
          },
          child: const Text('Generate'),
        ),
      ],
    );
  }
}

class _CodePromptDialog extends StatefulWidget {
  const _CodePromptDialog(
      {required this.title,
      required this.label,
      required this.action,
      this.warning});
  final String title;
  final String label;
  final String action;
  final String? warning;
  @override
  State<_CodePromptDialog> createState() => _CodePromptDialogState();
}

class _CodePromptDialogState extends State<_CodePromptDialog> {
  final _code = TextEditingController();
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _code,
            autofocus: true,
            decoration: InputDecoration(labelText: widget.label),
          ),
          if (widget.warning != null) ...[
            const SizedBox(height: 8),
            Text(widget.warning!,
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _code.text.trim()),
          child: Text(widget.action),
        ),
      ],
    );
  }
}

class _ExtendByCodeDialog extends StatefulWidget {
  const _ExtendByCodeDialog();
  @override
  State<_ExtendByCodeDialog> createState() => _ExtendByCodeDialogState();
}

class _ExtendByCodeDialogState extends State<_ExtendByCodeDialog> {
  final _code = TextEditingController();
  final _months = TextEditingController(text: '1');
  @override
  void dispose() {
    _code.dispose();
    _months.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Extend by App Reference ID'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _code,
            decoration: const InputDecoration(
                labelText: 'App Reference ID / Shop Code'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _months,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Extend by (months)'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final code = _code.text.trim();
            if (code.isEmpty) return;
            Navigator.pop(
                context, (code, int.tryParse(_months.text.trim()) ?? 1));
          },
          child: const Text('Extend'),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 40),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(message, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _KeyRequest {
  final String shopId;
  final String shopName;
  final String plan;
  final int months;
  const _KeyRequest(
      {required this.shopId,
      required this.shopName,
      required this.plan,
      required this.months});
}

/// Editable vendor config (payment accounts, support, renewal prices).
class _ConfigTab extends StatefulWidget {
  const _ConfigTab({required this.initial, required this.onSave});
  final Map<String, String> initial;
  final Future<void> Function(Map<String, String>) onSave;

  @override
  State<_ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<_ConfigTab> {
  static const _fields = <String, String>{
    'pay.kbzpay.name': 'KBZPay account name',
    'pay.kbzpay.number': 'KBZPay number',
    'pay.wavepay.name': 'WavePay account name',
    'pay.wavepay.number': 'WavePay number',
    'support.viber': 'Support Viber number',
    'price.monthly': 'Monthly price, offline (Ks)',
    'price.yearly': 'Yearly price, offline (Ks)',
    'price.monthly.online': 'Monthly price, online (Ks, defaults to offline)',
    'price.yearly.online': 'Yearly price, online (Ks, defaults to offline)',
    'referral.enabled': 'Referral program on (true/false)',
    'referral.rate': 'Referral commission rate (e.g. 0.15 = 15%)',
  };
  late final Map<String, TextEditingController> _controllers = {
    for (final k in _fields.keys)
      k: TextEditingController(text: widget.initial[k] ?? ''),
  };
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final values = {
      for (final e in _controllers.entries) e.key: e.value.text.trim(),
    };
    await widget.onSave(values);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final e in _fields.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _controllers[e.key],
              keyboardType: e.key.startsWith('price')
                  ? TextInputType.number
                  : TextInputType.text,
              decoration: InputDecoration(
                labelText: e.value,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save),
          label: const Text('Save config'),
        ),
      ],
    );
  }
}

String _date(dynamic v) {
  if (v == null) return '—';
  final s = '$v';
  return s.length >= 10 ? s.substring(0, 10) : s;
}

// ---------------------------------------------------------------------------
// Delivery carriers tab: manage Ninja Van / Royal Express credentials. The
// API key is a secret held server-side — this UI only shows whether one is set
// (and its last 4 chars) and lets an admin set/replace it.
// ---------------------------------------------------------------------------

const _carrierLabels = <String, String>{
  'ninja_van': 'Ninja Van',
  'royal_express': 'Royal Express',
  'other': 'Other',
};

String _carrierLabel(String? code) => _carrierLabels[code] ?? (code ?? '—');

class _DeliveryTab extends StatelessWidget {
  const _DeliveryTab({
    required this.rows,
    required this.onSave,
    required this.onDelete,
  });

  final List<Map<String, dynamic>> rows;
  final Future<void> Function(Map<String, dynamic>) onSave;
  final Future<void> Function(String) onDelete;

  Future<void> _edit(BuildContext context, [Map<String, dynamic>? row]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CarrierDialog(initial: row),
    );
    if (result != null) await onSave(result);
  }

  Future<void> _confirmDelete(
      BuildContext context, Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${_carrierLabel(row['carrier'] as String?)}?'),
        content: const Text(
            'This removes the stored API credentials for this carrier. '
            'Any storefront order already using it is unaffected, but new '
            'orders can no longer be handed off to it until reconfigured. '
            'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await onDelete(row['id'] as String);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Delivery carrier API credentials (stored securely, '
                  'server-side only).',
                ),
              ),
              FilledButton.icon(
                onPressed: () => _edit(context),
                icon: const Icon(Icons.add),
                label: const Text('Add carrier'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('No carriers configured yet.'))
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    final enabled = r['enabled'] == true;
                    final keySet = r['api_key_set'] == true;
                    final last4 = r['api_key_last4'];
                    return ListTile(
                      leading: Icon(
                        Icons.local_shipping,
                        color: enabled ? Colors.green : Colors.grey,
                      ),
                      title: Text(_carrierLabel(r['carrier'] as String?)),
                      subtitle: Text([
                        if ((r['account_id'] ?? '').toString().isNotEmpty)
                          'Account: ${r['account_id']}',
                        keySet ? 'API key: ••••$last4' : 'API key: not set',
                        enabled ? 'Enabled' : 'Disabled',
                      ].join('  ·  ')),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _edit(context, r),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            onPressed: () => _confirmDelete(context, r),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CarrierDialog extends StatefulWidget {
  const _CarrierDialog({this.initial});
  final Map<String, dynamic>? initial;

  @override
  State<_CarrierDialog> createState() => _CarrierDialogState();
}

class _CarrierDialogState extends State<_CarrierDialog> {
  late String _carrier;
  late final TextEditingController _account;
  late final TextEditingController _baseUrl;
  final _apiKey = TextEditingController();
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _carrier = (i?['carrier'] as String?) ?? 'ninja_van';
    _account = TextEditingController(text: (i?['account_id'] as String?) ?? '');
    _baseUrl = TextEditingController(text: (i?['base_url'] as String?) ?? '');
    _enabled = i?['enabled'] == true;
  }

  @override
  void dispose() {
    _account.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    final keySet = widget.initial?['api_key_set'] == true;
    return AlertDialog(
      title: Text(editing ? 'Edit carrier' : 'Add carrier'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _carrier,
              decoration: const InputDecoration(labelText: 'Carrier'),
              items: [
                for (final e in _carrierLabels.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _carrier = v ?? 'ninja_van'),
            ),
            TextField(
              controller: _account,
              decoration: const InputDecoration(
                  labelText: 'Account / client id'),
            ),
            TextField(
              controller: _apiKey,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'API key',
                hintText: keySet ? 'Leave blank to keep current key' : null,
              ),
            ),
            TextField(
              controller: _baseUrl,
              decoration: const InputDecoration(
                  labelText: 'Base URL (optional)'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enabled'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(<String, dynamic>{
            if (widget.initial?['id'] != null) 'id': widget.initial!['id'],
            'carrier': _carrier,
            'account_id': _account.text.trim(),
            'base_url': _baseUrl.text.trim(),
            'api_key': _apiKey.text.trim(),
            'enabled': _enabled,
          }),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Renders a license-request payment screenshot from the private
/// `payment-proofs` bucket via a signed URL — same call
/// `order_detail_sheet.dart`'s `_PaymentProof` makes on the mobile app side;
/// the admin's own session is `authenticated`, already covered by the
/// existing bucket-wide SELECT policy (migration 0022).
class _RequestProofImage extends StatefulWidget {
  const _RequestProofImage({required this.path});
  final String path;

  @override
  State<_RequestProofImage> createState() => _RequestProofImageState();
}

class _RequestProofImageState extends State<_RequestProofImage> {
  late final Future<String> _url;

  @override
  void initState() {
    super.initState();
    _url = Supabase.instance.client.storage
        .from('payment-proofs')
        .createSignedUrl(widget.path, 3600);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
              height: 200, child: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError || snap.data == null) {
          return const SizedBox(
              height: 120, child: Icon(Icons.broken_image_outlined));
        }
        return Image.network(snap.data!, fit: BoxFit.contain);
      },
    );
  }
}
