part of 'admin_dashboard_screen.dart';

/// The semantic weight of a license `status` value (`active | expired |
/// grace`, see `supabase/migrations/0003_licensing.sql`), for [StatusPill] —
/// deliberately mirrors the mobile app's own `LicenseStatusKind` mapping in
/// `settings_screen.dart` (active -> success, grace -> warning, else ->
/// danger) rather than inventing a second convention for the same concept.
StatusTone _licenseTone(String status) => switch (status) {
      'active' => StatusTone.positive,
      'grace' => StatusTone.attention,
      _ => StatusTone.critical,
    };

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// `AppTheme`'s `filledButtonTheme` sets `minimumSize: Size.fromHeight(52)`
/// — a deliberately big, full-bleed tap target for a screen's *one* primary
/// CTA (Sign in, Save, Generate). `Size.fromHeight` sets `minWidth:
/// double.infinity`, which is fine inside a dialog's `OverflowBar` (every
/// `AlertDialog.actions` FilledButton in this app already relies on that)
/// but is a real crash/layout risk for a *compact inline* action sitting in
/// a plain `Row`/`ListTile.trailing` — a non-flex child asked for infinite
/// width inside an otherwise-bounded `Row` fights the row's own finite
/// constraints. Nothing in this app puts a bare `FilledButton` in a `Row`
/// before this file, so this is a real gap, not a copy-paste of a
/// proven-safe shape. Used for the two inline row actions below.
ButtonStyle _compactFilledButtonStyle() => FilledButton.styleFrom(
      minimumSize: const Size(64, 40),
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space3),
    );

class _LicensesTab extends StatelessWidget {
  const _LicensesTab({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const EmptyStateView(
        icon: Icons.vpn_key_outlined,
        title: 'No licenses yet.',
        message: 'Generate a key from the button below once a shop is '
            'ready to activate.',
      );
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = rows[i];
        final status = '${r['status']}';
        return ListTile(
          leading: const IconAvatar(icon: Icons.vpn_key),
          title: SelectableText('${r['key']}'),
          subtitle: Text(
              'Shop: ${r['shop_id']}  ·  ${r['plan']}\n'
              'Expires: ${_date(r['expires_at'])}  ·  '
              'Device: ${r['device_id'] ?? '—'}'),
          isThreeLine: true,
          trailing: StatusPill(
            label: _capitalize(status),
            tone: _licenseTone(status),
          ),
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
      return const EmptyStateView(
        icon: Icons.history,
        title: 'No key issues / renewals yet.',
      );
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = rows[i];
        final isExtend = r['action'] == 'extend';
        // Neutral, not color-coded: "Extended" vs "Issued" is a category the
        // title text already states, not a state the shop needs a signal
        // for (same reasoning Analytics' KPI grid settled on — color here
        // would be decorative, not information).
        return ListTile(
          leading: IconAvatar(
              icon: isExtend ? Icons.more_time : Icons.vpn_key),
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
      return const EmptyStateView(
        icon: Icons.hourglass_empty,
        title: 'No subscription requests.',
      );
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = rows[i];
        final fulfilled = r['status'] == 'fulfilled';
        final proofPath = r['payment_proof_path'] as String?;
        final shopId = r['shop_id'] as String?;
        return ListTile(
          // A pending request is the admin's to-do list, so it gets
          // `attention`, not a neutral fill — the same reasoning Orders'
          // `new` status and Purchase Orders' `open` status use.
          leading: IconAvatar(
            icon: fulfilled ? Icons.check_circle : Icons.hourglass_top,
            tone: fulfilled ? StatusTone.positive : StatusTone.attention,
          ),
          title: Text(
              '${r['shop_name']}  ·  ${r['amount']} Ks  ·  ${r['method']}  ·  ${r['months']} mo  ·  ${r['tier'] ?? 'offline'}'),
          subtitle: Text(
              'Phone: ${r['phone'] ?? '—'}  ·  Txn: ${r['ref_no'] ?? '—'}\n'
              'Device: ${r['device_id'] ?? '—'}  ·  ${_date(r['created_at'])}'
              '${fulfilled ? '  ·  Key: ${r['issued_key']}' : ''}'
              // Renewal (an existing shop) vs a brand-new one — see
              // fulfill_request's shop_id-first lookup.
              '${shopId != null && shopId.isNotEmpty ? '\nRenewal for shop: $shopId' : '\n(No shop_id — treated as a new shop)'}'),
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
                const StatusPill(label: 'Issued', tone: StatusTone.positive)
              else
                FilledButton(
                  style: _compactFilledButtonStyle(),
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
      return const EmptyStateView(
        icon: Icons.card_giftcard_outlined,
        title: 'No referrals or commissions yet.',
      );
    }
    final textTheme = Theme.of(context).textTheme;

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
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space2),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTheme.space4, AppTheme.space2, AppTheme.space4, AppTheme.space1),
          child: Text('Commissions by referrer', style: textTheme.titleSmall),
        ),
        if (referrers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.space4, vertical: AppTheme.space2),
            child: Text('No commissions earned yet.',
                style: textTheme.bodyMedium),
          )
        else
          for (final sid in referrers)
            ListTile(
              // Every row here already implies "has earned a commission" —
              // the icon's color would be purely decorative, not a signal
              // (same reasoning as the History tab above), so neutral.
              leading: const IconAvatar(icon: Icons.card_giftcard),
              title: SelectableText(sid),
              subtitle: Text(
                  '${counts[sid]} payment(s)  ·  earned ${earned[sid]} Ks'),
              trailing: FilledButton(
                style: _compactFilledButtonStyle(),
                onPressed: () =>
                    _confirmApplyCredit(context, sid, earned[sid] ?? 0),
                child: const Text('Apply credit'),
              ),
            ),
        const Divider(height: AppTheme.space5),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTheme.space4, AppTheme.space1, AppTheme.space4, AppTheme.space1),
          child: Text('Referral links (${referrals.length})',
              style: textTheme.titleSmall),
        ),
        if (referrals.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.space4, vertical: AppTheme.space2),
            child:
                Text('No referral links yet.', style: textTheme.bodyMedium),
          )
        else
          for (final r in referrals)
            ListTile(
              dense: true,
              // A real binary signal (does this link still work) — active
              // gets `positive`; inactive is a finished-with, non-urgent
              // state (`neutral`, not a warning color), mirroring the
              // printer-connected indicator in `printer_settings_screen.dart`.
              leading: IconAvatar(
                icon: (r['is_active'] == true) ? Icons.link : Icons.link_off,
                tone: (r['is_active'] == true)
                    ? StatusTone.positive
                    : StatusTone.neutral,
                size: 32,
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
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _shopName,
            decoration:
                const InputDecoration(labelText: 'Shop name (display)'),
          ),
          const SizedBox(height: AppTheme.space3),
          DropdownButtonFormField<String>(
            initialValue: _plan,
            decoration: const InputDecoration(labelText: 'Plan'),
            items: const [
              DropdownMenuItem(value: 'monthly', child: Text('monthly')),
              DropdownMenuItem(value: 'yearly', child: Text('yearly')),
            ],
            onChanged: (v) => setState(() => _plan = v ?? 'monthly'),
          ),
          const SizedBox(height: AppTheme.space3),
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
            const SizedBox(height: AppTheme.space2),
            TextField(
                controller: _shopName,
                decoration: const InputDecoration(labelText: 'Shop name')),
            const SizedBox(height: AppTheme.space2),
            DropdownButtonFormField<String>(
              initialValue: _plan,
              decoration: const InputDecoration(labelText: 'Plan'),
              items: const [
                DropdownMenuItem(value: 'monthly', child: Text('monthly')),
                DropdownMenuItem(value: 'yearly', child: Text('yearly')),
              ],
              onChanged: (v) => setState(() => _plan = v ?? 'monthly'),
            ),
            const SizedBox(height: AppTheme.space2),
            TextField(
              controller: _months,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Duration (months)'),
            ),
            const SizedBox(height: AppTheme.space2),
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
            const SizedBox(height: AppTheme.space2),
            Text(
              widget.warning!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.of(context).muted),
            ),
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
          const SizedBox(height: AppTheme.space3),
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
          // A bare `Icon`, not `IconAvatar`: this mirrors `EmptyStateView`'s
          // own big-centered-icon shape (size 48, no plate) rather than the
          // list-row leading-mark shape `IconAvatar` is built for.
          Icon(Icons.error_outline,
              color: AppColors.of(context).danger, size: 40),
          const SizedBox(height: AppTheme.space3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.space5),
            child: Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(height: AppTheme.space3),
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
        const SizedBox(height: AppTheme.space2),
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
