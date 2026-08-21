part of 'admin_dashboard_screen.dart';

class _ShopHubPage extends StatelessWidget {
  const _ShopHubPage({
    required this.shops,
    required this.licenses,
    required this.requests,
    required this.filter,
    required this.selectedShopId,
    required this.supportViber,
    required this.onFilter,
    required this.onSelectShop,
    required this.onExtendEmail,
    required this.onExtendDevice,
    required this.onResetDevice,
    required this.onOffline,
    required this.onGenerateKey,
    required this.onGrantExtraDevice,
    required this.onViber,
    required this.onResetPassword,
    required this.onUnlink,
    required this.onRestore,
  });

  final List<Map<String, dynamic>> shops;
  final List<Map<String, dynamic>> licenses;
  final List<Map<String, dynamic>> requests;
  final AdminShopFilter filter;
  final String? selectedShopId;
  final String supportViber;
  final ValueChanged<AdminShopFilter> onFilter;
  final ValueChanged<String?> onSelectShop;
  final void Function(Map<String, dynamic> shop) onExtendEmail;
  final void Function(Map<String, dynamic> shop, String? deviceId)
  onExtendDevice;
  final void Function(String deviceId) onResetDevice;
  final void Function(Map<String, dynamic> shop) onOffline;
  final void Function(String shopId) onGenerateKey;
  final void Function(Map<String, dynamic> shop) onGrantExtraDevice;
  final Future<void> Function(String number) onViber;
  final void Function(String email) onResetPassword;
  final void Function(String userId, String email) onUnlink;
  final void Function(String userId, String email) onRestore;

  @override
  Widget build(BuildContext context) {
    return _ShopHubBody(
      shops: shops,
      licenses: licenses,
      requests: requests,
      filter: filter,
      selectedShopId: selectedShopId,
      supportViber: supportViber,
      onFilter: onFilter,
      onSelectShop: onSelectShop,
      onExtendEmail: onExtendEmail,
      onExtendDevice: onExtendDevice,
      onResetDevice: onResetDevice,
      onOffline: onOffline,
      onGenerateKey: onGenerateKey,
      onGrantExtraDevice: onGrantExtraDevice,
      onViber: onViber,
      onResetPassword: onResetPassword,
      onUnlink: onUnlink,
      onRestore: onRestore,
    );
  }
}

class _ShopHubBody extends StatefulWidget {
  const _ShopHubBody({
    required this.shops,
    required this.licenses,
    required this.requests,
    required this.filter,
    required this.selectedShopId,
    required this.supportViber,
    required this.onFilter,
    required this.onSelectShop,
    required this.onExtendEmail,
    required this.onExtendDevice,
    required this.onResetDevice,
    required this.onOffline,
    required this.onGenerateKey,
    required this.onGrantExtraDevice,
    required this.onViber,
    required this.onResetPassword,
    required this.onUnlink,
    required this.onRestore,
  });

  final List<Map<String, dynamic>> shops;
  final List<Map<String, dynamic>> licenses;
  final List<Map<String, dynamic>> requests;
  final AdminShopFilter filter;
  final String? selectedShopId;
  final String supportViber;
  final ValueChanged<AdminShopFilter> onFilter;
  final ValueChanged<String?> onSelectShop;
  final void Function(Map<String, dynamic> shop) onExtendEmail;
  final void Function(Map<String, dynamic> shop, String? deviceId)
  onExtendDevice;
  final void Function(String deviceId) onResetDevice;
  final void Function(Map<String, dynamic> shop) onOffline;
  final void Function(String shopId) onGenerateKey;
  final void Function(Map<String, dynamic> shop) onGrantExtraDevice;
  final Future<void> Function(String number) onViber;
  final void Function(String email) onResetPassword;
  final void Function(String userId, String email) onUnlink;
  final void Function(String userId, String email) onRestore;

  @override
  State<_ShopHubBody> createState() => _ShopHubBodyState();
}

class _ShopHubBodyState extends State<_ShopHubBody> {
  final _filter = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.shops.isEmpty) {
      return const EmptyStateView(
        icon: Icons.storefront_outlined,
        title: 'No shops yet.',
      );
    }
    final now = DateTime.now();
    final filtered = widget.shops.where((s) {
      if (!shopMatchesFilter(s, widget.filter, now)) return false;
      return shopMatchesQuery(s, widget.licenses, _query);
    }).toList();
    Map<String, dynamic>? selected;
    for (final s in filtered) {
      if ('${s['shop_id']}' == widget.selectedShopId) {
        selected = s;
        break;
      }
    }
    final wide = MediaQuery.sizeOf(context).width >= 960;

    final list = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space3,
            AppTheme.space3,
            AppTheme.space3,
            AppTheme.space2,
          ),
          child: TextField(
            controller: _filter,
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Name, email, phone, or App Reference ID',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space3,
            0,
            AppTheme.space3,
            AppTheme.space2,
          ),
          child: Wrap(
            spacing: AppTheme.space1,
            children: [
              for (final f in AdminShopFilter.values)
                FilterChip(
                  label: Text(switch (f) {
                    AdminShopFilter.all => 'All',
                    AdminShopFilter.premium => 'Premium',
                    AdminShopFilter.atRisk => 'At risk',
                    AdminShopFilter.expiring => 'Expiring',
                  }),
                  selected: widget.filter == f,
                  onSelected: (_) => widget.onFilter(f),
                ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const EmptyStateView(
                  icon: Icons.search_off,
                  title: 'No shops match that filter.',
                )
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = filtered[i];
                    final status = '${r['status']}';
                    final selectedRow =
                        '${r['shop_id']}' == widget.selectedShopId;
                    return ListTile(
                      selected: selectedRow,
                      leading: IconAvatar(
                        icon: Icons.storefront,
                        tone: _licenseTone(status) == StatusTone.positive
                            ? null
                            : _licenseTone(status),
                      ),
                      title: Text('${r['shop_name'] ?? r['shop_id']}'),
                      subtitle: Text(
                        '${r['email'] ?? '—'}  ·  ${r['plan'] ?? '—'}',
                      ),
                      trailing: StatusPill(
                        label: _statusLabel(status),
                        tone: _licenseTone(status),
                      ),
                      onTap: () => widget.onSelectShop('${r['shop_id']}'),
                    );
                  },
                ),
        ),
      ],
    );

    if (!wide) {
      if (selected != null) {
        return _ShopDetail(
          shop: selected,
          licenses: widget.licenses,
          requests: widget.requests,
          supportViber: widget.supportViber,
          onBack: () => widget.onSelectShop(null),
          onExtendEmail: widget.onExtendEmail,
          onExtendDevice: widget.onExtendDevice,
          onResetDevice: widget.onResetDevice,
          onOffline: widget.onOffline,
          onGenerateKey: widget.onGenerateKey,
          onGrantExtraDevice: widget.onGrantExtraDevice,
          onViber: widget.onViber,
          onResetPassword: widget.onResetPassword,
          onUnlink: widget.onUnlink,
          onRestore: widget.onRestore,
        );
      }
      return list;
    }

    return Row(
      children: [
        SizedBox(width: 340, child: list),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? const EmptyStateView(
                  icon: Icons.touch_app_outlined,
                  title: 'Select a shop.',
                  message:
                      'Search by name, email, phone, or device, then '
                      'open it to extend, add a device, or fix a login.',
                )
              : _ShopDetail(
                  shop: selected,
                  licenses: widget.licenses,
                  requests: widget.requests,
                  supportViber: widget.supportViber,
                  onExtendEmail: widget.onExtendEmail,
                  onExtendDevice: widget.onExtendDevice,
                  onResetDevice: widget.onResetDevice,
                  onOffline: widget.onOffline,
                  onGenerateKey: widget.onGenerateKey,
                  onGrantExtraDevice: widget.onGrantExtraDevice,
                  onViber: widget.onViber,
                  onResetPassword: widget.onResetPassword,
                  onUnlink: widget.onUnlink,
                  onRestore: widget.onRestore,
                ),
        ),
      ],
    );
  }
}

class _ShopDetail extends StatelessWidget {
  const _ShopDetail({
    required this.shop,
    required this.licenses,
    required this.requests,
    required this.supportViber,
    this.onBack,
    required this.onExtendEmail,
    required this.onExtendDevice,
    required this.onResetDevice,
    required this.onOffline,
    required this.onGenerateKey,
    required this.onGrantExtraDevice,
    required this.onViber,
    required this.onResetPassword,
    required this.onUnlink,
    required this.onRestore,
  });

  final Map<String, dynamic> shop;
  final List<Map<String, dynamic>> licenses;
  final List<Map<String, dynamic>> requests;
  final String supportViber;
  final VoidCallback? onBack;
  final void Function(Map<String, dynamic> shop) onExtendEmail;
  final void Function(Map<String, dynamic> shop, String? deviceId)
  onExtendDevice;
  final void Function(String deviceId) onResetDevice;
  final void Function(Map<String, dynamic> shop) onOffline;
  final void Function(String shopId) onGenerateKey;
  final void Function(Map<String, dynamic> shop) onGrantExtraDevice;
  final Future<void> Function(String number) onViber;
  final void Function(String email) onResetPassword;
  final void Function(String userId, String email) onUnlink;
  final void Function(String userId, String email) onRestore;

  @override
  Widget build(BuildContext context) {
    final status = '${shop['status']}';
    final hasNoLicense = status == 'no_license';
    final devices = shopDevices(shop, licenses);
    final accounts = shopAccounts(shop);
    final payments = requestsForShop(shop, requests, licenses);
    final phone = '${shop['phone'] ?? ''}'.trim();
    final viberTarget = phone.isNotEmpty ? phone : supportViber;
    final textTheme = Theme.of(context).textTheme;
    final muted = AppColors.of(context).muted;

    return ListView(
      padding: const EdgeInsets.all(AppTheme.space4),
      children: [
        if (onBack != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('All shops'),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${shop['shop_name'] ?? shop['shop_id']}',
                    style: textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppTheme.space1),
                  SelectableText(
                    '${shop['shop_id']}',
                    style: textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  const SizedBox(height: AppTheme.space1),
                  Text(
                    '${shop['email'] ?? '—'}  ·  ${shop['phone'] ?? '—'}',
                    style: textTheme.bodyMedium,
                  ),
                  if ('${shop['address'] ?? ''}'.trim().isNotEmpty)
                    Text('${shop['address']}', style: textTheme.bodySmall),
                ],
              ),
            ),
            StatusPill(label: _statusLabel(status), tone: _licenseTone(status)),
          ],
        ),
        const SizedBox(height: AppTheme.space2),
        Text(
          hasNoLicense
              ? 'Has an account, but no license — nothing to extend, only to create.'
              : '${shop['plan'] ?? '—'}  ·  ${shop['tier'] ?? 'offline'}  ·  '
                    'Expires ${_date(shop['expires_at'])}',
          style: textTheme.bodyMedium,
        ),
        if (!hasNoLicense) ...[
          const SizedBox(height: AppTheme.space1),
          Text(
            _deviceAllowanceLabel(shop),
            style: textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
        const SizedBox(height: AppTheme.space4),
        Wrap(
          spacing: AppTheme.space2,
          runSpacing: AppTheme.space2,
          children: [
            if (hasNoLicense)
              FilledButton.icon(
                onPressed: () => onGenerateKey('${shop['shop_id']}'),
                icon: const Icon(Icons.add),
                label: const Text('Generate key'),
              )
            else ...[
              FilledButton.icon(
                onPressed: () => onExtendEmail(shop),
                icon: const Icon(Icons.mail_outline),
                label: const Text('Extend by email'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  String? deviceId;
                  for (final d in devices) {
                    if (deviceIsBound(d)) {
                      deviceId = '${d['device_id']}'.trim();
                      break;
                    }
                  }
                  onExtendDevice(shop, deviceId);
                },
                icon: const Icon(Icons.phonelink),
                label: const Text('Extend by device'),
              ),
              OutlinedButton.icon(
                onPressed: () => onGrantExtraDevice(shop),
                icon: const Icon(Icons.phonelink_setup),
                label: const Text('Allow extra devices'),
              ),
            ],
            OutlinedButton.icon(
              onPressed: () => onOffline(shop),
              icon: const Icon(Icons.qr_code),
              label: const Text('Offline code'),
            ),
            if (viberTarget.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => onViber(viberTarget),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('Message on Viber'),
              ),
          ],
        ),
        const SizedBox(height: AppTheme.space5),
        const SectionHeader(title: 'Devices'),
        if (devices.isEmpty)
          Text(
            'No devices yet.',
            style: textTheme.bodyMedium?.copyWith(color: muted),
          )
        else
          for (final d in devices)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: IconAvatar(
                icon: deviceIsBound(d)
                    ? Icons.smartphone
                    : Icons.phonelink_setup,
              ),
              title: SelectableText(
                deviceIsBound(d)
                    ? '${d['device_id']}'
                    : 'Waiting for new phone / computer',
              ),
              subtitle: Text('Expires ${_date(d['expires_at'])}'),
              trailing: deviceIsBound(d)
                  ? TextButton(
                      onPressed: () => onResetDevice('${d['device_id']}'),
                      child: const Text('Reset'),
                    )
                  : null,
            ),
        const SizedBox(height: AppTheme.space4),
        const SectionHeader(title: 'Accounts'),
        if (accounts.isEmpty)
          Text(
            'No linked logins.',
            style: textTheme.bodyMedium?.copyWith(color: muted),
          )
        else
          for (final a in accounts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: IconAvatar(
                icon: a['banned'] == true
                    ? Icons.person_off_outlined
                    : Icons.person_outline,
                tone: a['banned'] == true ? StatusTone.critical : null,
              ),
              title: Text('${a['email'] ?? '—'}'),
              subtitle: Text(
                '${a['role'] ?? '—'}'
                '${a['banned'] == true ? '  ·  banned' : ''}',
              ),
              trailing: a['id'] == null && '${a['email'] ?? ''}'.isEmpty
                  ? null
                  : PopupMenuButton<String>(
                      onSelected: (v) {
                        switch (v) {
                          case 'reset':
                            onResetPassword('${a['email']}');
                          case 'restore':
                            onRestore('${a['id']}', '${a['email'] ?? ''}');
                          case 'unlink':
                            onUnlink('${a['id']}', '${a['email'] ?? ''}');
                        }
                      },
                      itemBuilder: (context) => [
                        if ('${a['email'] ?? ''}'.isNotEmpty)
                          const PopupMenuItem(
                            value: 'reset',
                            child: Text('Reset password'),
                          ),
                        if (a['banned'] == true && a['id'] != null)
                          const PopupMenuItem(
                            value: 'restore',
                            child: Text('Restore access'),
                          )
                        else if (a['id'] != null)
                          const PopupMenuItem(
                            value: 'unlink',
                            child: Text('Unlink'),
                          ),
                      ],
                    ),
            ),
        const SizedBox(height: AppTheme.space4),
        const SectionHeader(title: 'Payments'),
        if (payments.isEmpty)
          Text(
            'No payment requests for this shop.',
            style: textTheme.bodyMedium?.copyWith(color: muted),
          )
        else
          for (final r in payments.take(12))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${_capitalize('${r['status']}')}  ·  ${_ks((r['amount'] as num?)?.toInt() ?? 0)}',
              ),
              subtitle: Text(
                '${r['method'] ?? '—'}  ·  ${r['months'] ?? '—'} mo  ·  ${_date(r['created_at'])}',
              ),
            ),
      ],
    );
  }
}

String _deviceAllowanceLabel(Map<String, dynamic> shop) {
  final extra = (shop['extra_slots'] as num?)?.toInt() ?? 0;
  if (extra <= 0) {
    return 'Free cap: this phone + 2 extras. After they pay, allow more — they sign in on the new device and tap Check for renewal (no key).';
  }
  final until = shop['extras_expires_at'];
  final untilText = until == null || '$until'.trim().isEmpty
      ? 'no end date'
      : _date(until);
  return 'Paid extras: $extra (until $untilText). New phone: sign in + Check for renewal — do not send a key.';
}
