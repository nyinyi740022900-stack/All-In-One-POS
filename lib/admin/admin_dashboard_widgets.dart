part of 'admin_dashboard_screen.dart';

/// The semantic weight of a license `status` value (`active | expired |
/// grace`, see `supabase/migrations/0003_licensing.sql`), for [StatusPill] —
/// deliberately mirrors the mobile app's own `LicenseStatusKind` mapping in
/// `settings_screen.dart` (active -> success, grace -> warning, else ->
/// danger) rather than inventing a second convention for the same concept.
StatusTone _licenseTone(String status) => switch (status) {
  'active' => StatusTone.positive,
  'grace' => StatusTone.attention,
  'no_license' => StatusTone.attention,
  _ => StatusTone.critical,
};

String _statusLabel(String status) =>
    status == 'no_license' ? 'No license' : _capitalize(status);

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

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const EmptyStateView(
        icon: Icons.history,
        title: 'No confirmations, renewals, or declines yet.',
      );
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = rows[i];
        final action = r['action'];
        final isExtend = action == 'extend';
        final isDecline = action == 'reject';
        // Neutral, not color-coded: "Extended" vs "Confirmed" is a category
        // the title text already states, not a state the shop needs a
        // signal for (same reasoning Analytics' KPI grid settled on — color
        // here would be decorative, not information). Decline is the one
        // exception — it's the negative outcome in this feed, so it keeps
        // the critical tone the Requests tab already gives it.
        return ListTile(
          leading: IconAvatar(
            icon: isDecline
                ? Icons.cancel
                : isExtend
                ? Icons.more_time
                : Icons.vpn_key,
            tone: isDecline ? StatusTone.critical : null,
          ),
          title: Text(
            isDecline
                ? 'Declined  ·  ${r['shop_name'] ?? '—'}'
                : '${isExtend ? 'Extended' : 'Confirmed'}  ·  ${r['months']} mo  ·  ${r['shop_name'] ?? '—'}',
          ),
          subtitle: Text(
            isDecline
                ? 'Device: ${r['device_id'] ?? '—'}  ·  ${_date(r['created_at'])}'
                : 'Key: ${r['key']}  ·  Device: ${r['device_id'] ?? '—'}\n'
                      'New expiry: ${_date(r['expires_at'])}  ·  ${_date(r['created_at'])}',
          ),
          isThreeLine: !isDecline,
        );
      },
    );
  }
}

/// The action here is "the admin verified a payment came in," not a generic
/// approve/deny — "Confirm payment" / "Decline" name that directly, instead
/// of the more mechanism-focused "Issue key" wording this replaced (that
/// framing described what the system does internally, not what the admin is
/// deciding).
class _RequestsTab extends StatelessWidget {
  const _RequestsTab({
    required this.rows,
    required this.onConfirm,
    required this.onDecline,
    this.pendingOnly = false,
    this.settledOnly = false,
  });
  final List<Map<String, dynamic>> rows;
  final Future<void> Function(Map<String, dynamic>) onConfirm;
  final Future<void> Function(Map<String, dynamic>) onDecline;
  final bool pendingOnly;
  final bool settledOnly;

  @override
  Widget build(BuildContext context) {
    var rows = this.rows;
    if (pendingOnly) {
      rows = rows.where((r) => r['status'] == 'pending').toList();
    } else if (settledOnly) {
      rows = rows.where((r) => r['status'] != 'pending').toList();
    }
    if (rows.isEmpty) {
      return EmptyStateView(
        icon: pendingOnly ? Icons.check_circle_outline : Icons.hourglass_empty,
        title: pendingOnly
            ? "You're caught up."
            : settledOnly
            ? 'No confirmed or declined payments yet.'
            : 'No subscription requests.',
        message: pendingOnly
            ? 'New KBZPay and WavePay requests will land here.'
            : null,
      );
    }
    // Pending requests are the admin's to-do list — surface them above
    // already-settled ones instead of leaving them mixed into one
    // created_at-ordered feed the admin has to scan past.
    final pending = rows.where((r) => r['status'] == 'pending').toList();
    final settled = rows.where((r) => r['status'] != 'pending').toList();
    final sorted = pendingOnly
        ? pending
        : settledOnly
        ? settled
        : [...pending, ...settled];
    final textTheme = Theme.of(context).textTheme;
    return ListView.separated(
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = sorted[i];
        final status = r['status'];
        final fulfilled = status == 'fulfilled';
        final rejected = status == 'rejected';
        final proofPath = r['payment_proof_path'] as String?;
        final shopId = r['shop_id'] as String?;
        final rejectReason = r['reject_reason'] as String?;
        return ListTile(
          leading: (proofPath != null && proofPath.isNotEmpty)
              ? _RequestProofImage(
                  path: proofPath,
                  size: 44,
                  onTap: () => _showProof(context, proofPath),
                )
              : IconAvatar(
                  icon: rejected
                      ? Icons.cancel
                      : fulfilled
                      ? Icons.check_circle
                      : Icons.hourglass_top,
                  tone: rejected
                      ? StatusTone.critical
                      : fulfilled
                      ? StatusTone.positive
                      : StatusTone.attention,
                ),
          title: Row(
            children: [
              Expanded(
                child: Text('${r['shop_name']}', style: textTheme.titleSmall),
              ),
              Text(
                _ks((r['amount'] as num?)?.toInt() ?? 0),
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${r['method']}  ·  ${r['months']} mo  ·  ${r['tier'] ?? 'offline'}'
                '  ·  ${_date(r['created_at'])}',
                style: textTheme.bodySmall,
              ),
              // The values support actually verifies/sends every day get
              // one-tap copy instead of fragile browser text selection.
              Wrap(
                spacing: AppTheme.space3,
                children: [
                  _CopyField('Txn', '${r['ref_no'] ?? ''}'),
                  _CopyField('Phone', '${r['phone'] ?? ''}'),
                  if (fulfilled && '${r['issued_key']}'.isNotEmpty)
                    _CopyField('Key', '${r['issued_key']}'),
                ],
              ),
              Text('Device: ${r['device_id'] ?? '—'}',
                  style: textTheme.bodySmall),
              if (rejected && rejectReason != null && rejectReason.isNotEmpty)
                Text('Reason: $rejectReason', style: textTheme.bodySmall),
              // Renewal (an existing shop) vs a brand-new one — see
              // fulfill_request's shop_id-first lookup.
              Text(
                shopId != null && shopId.isNotEmpty
                    ? 'Renewal for shop: $shopId'
                    : '(No shop_id — treated as a new shop)',
                style: textTheme.bodySmall,
              ),
            ],
          ),
          trailing: fulfilled
              ? const StatusPill(label: 'Confirmed', tone: StatusTone.positive)
              : rejected
              ? const StatusPill(label: 'Declined', tone: StatusTone.critical)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => onDecline(r),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.of(context).danger,
                      ),
                      child: const Text('Decline'),
                    ),
                    const SizedBox(width: AppTheme.space1),
                    FilledButton(
                      style: _compactFilledButtonStyle(),
                      onPressed: () => onConfirm(r),
                      child: const Text('Confirm payment'),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _showProof(BuildContext context, String path) async {
    // Fullscreen pinch-zoom: verifying the transferred amount on a
    // screenshot-of-a-screenshot needs every pixel, not a 400px dialog.
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 5,
                child: _RequestProofImage(path: path),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Optional-reason prompt shown before declining a pending request — same
/// text-entry shape as [_CodePromptDialog], but the field is optional (an
/// empty submit still confirms the decline) since a reason is a courtesy for
/// the shop, not a requirement to act.
class _DeclineReasonDialog extends StatefulWidget {
  const _DeclineReasonDialog();
  @override
  State<_DeclineReasonDialog> createState() => _DeclineReasonDialogState();
}

class _DeclineReasonDialogState extends State<_DeclineReasonDialog> {
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Decline this request?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('The shop will not be charged or issued a key.'),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _reason,
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
            decoration: const InputDecoration(labelText: 'Reason (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _reason.text.trim()),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.of(context).danger,
          ),
          child: const Text('Decline'),
        ),
      ],
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
    BuildContext context,
    String shopId,
    int balance,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apply referral credit?'),
        content: Text(
          'Converts as much of $shopId\'s $balance Ks referral balance as '
          'covers full months into a license extension for that shop, and '
          'deducts it from their balance. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apply'),
          ),
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
            AppTheme.space4,
            AppTheme.space2,
            AppTheme.space4,
            AppTheme.space1,
          ),
          child: Text('Commissions by referrer', style: textTheme.titleSmall),
        ),
        if (referrers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.space4,
              vertical: AppTheme.space2,
            ),
            child: Text(
              'No commissions earned yet.',
              style: textTheme.bodyMedium,
            ),
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
                '${counts[sid]} payment(s)  ·  earned ${earned[sid]} Ks',
              ),
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
            AppTheme.space4,
            AppTheme.space1,
            AppTheme.space4,
            AppTheme.space1,
          ),
          child: Text(
            'Referral links (${referrals.length})',
            style: textTheme.titleSmall,
          ),
        ),
        if (referrals.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.space4,
              vertical: AppTheme.space2,
            ),
            child: Text('No referral links yet.', style: textTheme.bodyMedium),
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
                'referred: ${r['referred_shop_id']}  ·  ${_date(r['created_at'])}',
              ),
            ),
      ],
    );
  }
}

class _DeviceAllowanceDialog extends StatefulWidget {
  const _DeviceAllowanceDialog({required this.initialExtraSlots});
  final int initialExtraSlots;
  @override
  State<_DeviceAllowanceDialog> createState() => _DeviceAllowanceDialogState();
}

class _DeviceAllowanceDialogState extends State<_DeviceAllowanceDialog> {
  late final _extra = TextEditingController(
    text: '${widget.initialExtraSlots}',
  );
  final _months = TextEditingController(text: '12');
  String? _extraError;
  String? _monthsError;

  @override
  void dispose() {
    _extra.dispose();
    _months.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Allow extra devices'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Free is always the main phone plus 2 extras. This number is paid '
            'extras on top of that. Do not send a key — they sign in on the '
            'new phone or computer and tap Check for renewal.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.of(context).muted,
            ),
          ),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _extra,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Paid extra devices',
              errorText: _extraError,
            ),
            onChanged: (_) {
              if (_extraError != null) setState(() => _extraError = null);
            },
          ),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _months,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Valid for (months)',
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
            final extra = int.tryParse(_extra.text.trim());
            final months = int.tryParse(_months.text.trim());
            var ok = true;
            if (extra == null) {
              setState(() => _extraError = 'Enter 0 or more');
              ok = false;
            }
            if (extra != null && extra > 0 && (months == null || months < 1)) {
              setState(() => _monthsError = 'Enter at least 1 month');
              ok = false;
            }
            if (!ok) return;
            Navigator.pop(context, (
              extraSlots: extra!,
              months: extra == 0 ? 1 : months!,
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _GenerateKeyDialog extends StatefulWidget {
  const _GenerateKeyDialog({this.initialShopId});
  final String? initialShopId;
  @override
  State<_GenerateKeyDialog> createState() => _GenerateKeyDialogState();
}

class _GenerateKeyDialogState extends State<_GenerateKeyDialog> {
  late final _shopId = TextEditingController(text: widget.initialShopId);
  final _shopName = TextEditingController();
  final _months = TextEditingController(text: '1');
  String _plan = 'monthly';
  String? _shopIdError;
  String? _monthsError;

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
          Text(
            'Creates an Offline-tier key (device-key activation, no online '
            'account).',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.of(context).muted),
          ),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _shopId,
            decoration: InputDecoration(
              labelText: 'Shop ID (any stable identifier)',
              errorText: _shopIdError,
            ),
            onChanged: (_) {
              if (_shopIdError != null) setState(() => _shopIdError = null);
            },
          ),
          const SizedBox(height: AppTheme.space3),
          TextField(
            controller: _shopName,
            decoration: const InputDecoration(labelText: 'Shop name (display)'),
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
            decoration: InputDecoration(
              labelText: 'Duration (months)',
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
            final shop = _shopId.text.trim();
            final months = int.tryParse(_months.text.trim());
            setState(() {
              _shopIdError = shop.isEmpty ? 'Shop ID is required.' : null;
              _monthsError = (months == null || months <= 0)
                  ? 'Enter a whole number of months (1 or more).'
                  : null;
            });
            if (_shopIdError != null || _monthsError != null) return;
            Navigator.pop(
              context,
              _KeyRequest(
                shopId: shop,
                shopName: _shopName.text.trim(),
                plan: _plan,
                months: months!,
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
    this.shopId,
    this.shopName,
    this.plan,
    this.months,
    this.deviceId,
  );
}

class _OfflineCodeDialog extends StatefulWidget {
  const _OfflineCodeDialog({this.initialShopId, this.initialShopName});
  final String? initialShopId;
  final String? initialShopName;
  @override
  State<_OfflineCodeDialog> createState() => _OfflineCodeDialogState();
}

class _OfflineCodeDialogState extends State<_OfflineCodeDialog> {
  late final _shopId = TextEditingController(text: widget.initialShopId ?? '');
  late final _shopName = TextEditingController(
    text: widget.initialShopName ?? '',
  );
  final _months = TextEditingController(text: '1');
  final _device = TextEditingController();
  String _plan = 'monthly';
  String? _shopIdError;
  String? _monthsError;

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
              decoration: InputDecoration(
                labelText: 'Shop ID',
                errorText: _shopIdError,
              ),
              onChanged: (_) {
                if (_shopIdError != null) setState(() => _shopIdError = null);
              },
            ),
            const SizedBox(height: AppTheme.space2),
            TextField(
              controller: _shopName,
              decoration: const InputDecoration(labelText: 'Shop name'),
            ),
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
              decoration: InputDecoration(
                labelText: 'Duration (months)',
                errorText: _monthsError,
              ),
              onChanged: (_) {
                if (_monthsError != null) setState(() => _monthsError = null);
              },
            ),
            const SizedBox(height: AppTheme.space2),
            TextField(
              controller: _device,
              decoration: const InputDecoration(
                labelText: 'Bind to App Reference ID (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final shop = _shopId.text.trim();
            final months = int.tryParse(_months.text.trim());
            setState(() {
              _shopIdError = shop.isEmpty ? 'Shop ID is required.' : null;
              _monthsError = (months == null || months <= 0)
                  ? 'Enter a whole number of months (1 or more).'
                  : null;
            });
            if (_shopIdError != null || _monthsError != null) return;
            Navigator.pop(
              context,
              _OfflineRequest(
                shop,
                _shopName.text.trim(),
                _plan,
                months!,
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
  const _CodePromptDialog({
    required this.title,
    required this.label,
    required this.action,
    this.warning,
    this.initial,
  });
  final String title;
  final String label;
  final String action;
  final String? warning;
  final String? initial;
  @override
  State<_CodePromptDialog> createState() => _CodePromptDialogState();
}

class _CodePromptDialogState extends State<_CodePromptDialog> {
  late final _code = TextEditingController(text: widget.initial ?? '');
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
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
            decoration: InputDecoration(labelText: widget.label),
          ),
          if (widget.warning != null) ...[
            const SizedBox(height: AppTheme.space2),
            Text(
              widget.warning!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.of(context).muted,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _code.text.trim()),
          child: Text(widget.action),
        ),
      ],
    );
  }
}

/// One copyable fact on a request row — "Txn: 123456 ⧉". Tap copies to the
/// clipboard with a short confirmation; empty/placeholder values vanish.
class _CopyField extends StatelessWidget {
  const _CopyField(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final v = value.trim();
    if (v.isEmpty || v == '—') return const SizedBox.shrink();
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusXs),
      onTap: () {
        Clipboard.setData(ClipboardData(text: v));
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('$label copied'),
              duration: const Duration(seconds: 1),
            ),
          );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label: $v', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: AppTheme.space1),
            Icon(
              Icons.copy,
              size: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// The irreversible "Confirm payment" gate: at-a-glance verification of
/// shop / amount / plan / txn (with one-tap copy for the txn ref against
/// the bank app), Enter-to-confirm, and an explicit cannot-be-undone line.
class _ConfirmPaymentDialog extends StatelessWidget {
  const _ConfirmPaymentDialog({required this.request});
  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final amount = (r['amount'] as num?)?.toInt() ?? 0;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            Navigator.pop(context, true),
      },
      child: Focus(
        autofocus: true,
        child: AlertDialog(
          title: const Text('Confirm this payment?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${r['shop_name'] ?? '—'}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppTheme.space2),
              SummaryRow(
                'Amount',
                _ks(amount),
                emphasis: true,
              ),
              SummaryRow('Plan',
                  '${r['months']} months · ${r['tier'] ?? 'offline'}',
                  isMoney: false),
              Wrap(
                spacing: AppTheme.space3,
                children: [
                  _CopyField('Txn', '${r['ref_no'] ?? ''}'),
                  _CopyField('Phone', '${r['phone'] ?? ''}'),
                ],
              ),
              if ((r['device_id'] ?? '').toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppTheme.space1),
                  child: Text('Device: ${r['device_id']}',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              const SizedBox(height: AppTheme.space3),
              Text(
                'This issues/extends the license and marks the request '
                'fulfilled — it cannot be undone.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.of(context).danger,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm payment'),
            ),
          ],
        ),
      ),
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
          Icon(
            Icons.error_outline,
            color: AppColors.of(context).danger,
            size: 40,
          ),
          const SizedBox(height: AppTheme.space3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.space5),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
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
  const _KeyRequest({
    required this.shopId,
    required this.shopName,
    required this.plan,
    required this.months,
  });
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
    // No online/offline price split — the app doesn't meaningfully
    // distinguish those plans anymore (see PROJECT_SPEC #144). This one
    // rate applies regardless of a shop's `tier`; `price.monthly.online`/
    // `price.yearly.online` used to exist here but nothing has read them
    // since Store-compliance billing changes removed the only UI that did.
    'price.monthly': 'Monthly price (Ks)',
    'price.yearly': 'Yearly price (Ks)',
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
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
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
  const _RequestProofImage({required this.path, this.size, this.onTap});
  final String path;

  /// When set, renders as a small tappable square thumbnail (for the
  /// Requests tab's row leading) instead of the full-width preview used
  /// inside the "Payment screenshot" dialog.
  final double? size;
  final VoidCallback? onTap;

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
    final size = widget.size;
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return SizedBox(
            height: size ?? 200,
            width: size,
            child: const Center(child: ButtonSpinner(size: 20)),
          );
        }
        if (snap.hasError || snap.data == null) {
          return SizedBox(
            height: size ?? 120,
            width: size,
            child: const Icon(Icons.broken_image_outlined),
          );
        }
        final image = Image.network(
          snap.data!,
          fit: size != null ? BoxFit.cover : BoxFit.contain,
          width: size,
          height: size,
          // Thumbnail case decodes at display size; fullscreen keeps native
          // resolution (capped) so pinch-zoom stays legible.
          cacheWidth: size != null
              ? ProductThumb.cacheWidthFor(
                  size, MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0)
              : 1536,
        );
        if (size == null) return image;
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: InkWell(onTap: widget.onTap, child: image),
        );
      },
    );
  }
}
