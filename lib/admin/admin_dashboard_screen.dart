import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/app_widgets.dart';
import 'admin_api.dart';
part 'admin_dashboard_widgets.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen(
      {super.key, required this.api, required this.onSignedOut});
  final AdminApi api;
  final VoidCallback onSignedOut;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  List<Map<String, dynamic>>? _licenses;
  List<Map<String, dynamic>>? _requests;
  List<Map<String, dynamic>>? _events;
  List<Map<String, dynamic>>? _referrals;
  List<Map<String, dynamic>>? _commissions;
  Map<String, String>? _config;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final licenses = await widget.api.listLicenses();
      final requests = await widget.api.listRequests();
      final events = await widget.api.listEvents();
      final referrals = await widget.api.listReferrals();
      final commissions = await widget.api.listCommissions();
      final config = await widget.api.getConfig();
      setState(() {
        _licenses = licenses;
        _requests = requests;
        _events = events;
        _referrals = referrals;
        _commissions = commissions;
        _config = config;
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingRequests =
        (_requests ?? []).where((r) => r['status'] == 'pending').length;
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('MM POS Admin'),
          bottom: TabBar(isScrollable: true, tabs: [
            Tab(text: 'Licenses (${_licenses?.length ?? 0})'),
            Tab(text: 'Requests ($pendingRequests)'),
            Tab(text: 'History (${_events?.length ?? 0})'),
            Tab(text: 'Referrals (${_referrals?.length ?? 0})'),
            const Tab(text: 'Config'),
          ]),
          actions: [
            IconButton(
              tooltip: 'Extend by App Reference ID',
              icon: const Icon(Icons.more_time),
              onPressed: _extendByCode,
            ),
            IconButton(
              tooltip: 'Reset device binding',
              icon: const Icon(Icons.phonelink_erase),
              onPressed: _resetDevice,
            ),
            IconButton(
              tooltip: 'Generate offline code',
              icon: const Icon(Icons.offline_bolt),
              onPressed: _generateOffline,
            ),
            IconButton(
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _reload,
            ),
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await widget.api.signOut();
                widget.onSignedOut();
              },
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _generateKey,
          icon: const Icon(Icons.add),
          label: const Text('Generate key'),
        ),
        body: _error != null
            ? _ErrorView(message: _error!, onRetry: _reload)
            : _loading && _licenses == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(children: [
                    _LicensesTab(rows: _licenses ?? const []),
                    _RequestsTab(
                      rows: _requests ?? const [],
                      onIssue: _issueKey,
                    ),
                    _HistoryTab(rows: _events ?? const []),
                    _ReferralsTab(
                      commissions: _commissions ?? const [],
                      referrals: _referrals ?? const [],
                      onApplyCredit: _applyCredit,
                    ),
                    _ConfigTab(
                      initial: _config ?? const {},
                      onSave: _saveConfig,
                    ),
                  ]),
      ),
    );
  }

  Future<void> _generateKey() async {
    final result = await showDialog<_KeyRequest>(
      context: context,
      builder: (_) => const _GenerateKeyDialog(),
    );
    if (result == null) return;
    try {
      final key = await widget.api.createLicense(
        shopId: result.shopId,
        shopName: result.shopName,
        plan: result.plan,
        months: result.months,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('License key created'),
          content: SelectableText(key,
              style: const TextStyle(
                  fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: key));
                Navigator.pop(context);
              },
              child: const Text('Copy & close'),
            ),
          ],
        ),
      );
      _reload();
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _generateOffline() async {
    final req = await showDialog<_OfflineRequest>(
      context: context,
      builder: (_) => const _OfflineCodeDialog(),
    );
    if (req == null) return;
    try {
      final token = await widget.api.signOffline(
        shopId: req.shopId,
        shopName: req.shopName,
        plan: req.plan,
        months: req.months,
        deviceId: req.deviceId,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Offline license code'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    'Scan on the customer\'s phone (License screen > License key '
                    'field > scan icon) instead of retyping the code below.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: AppTheme.space4),
                BarcodeWidget(
                  barcode: Barcode.qrCode(),
                  data: token,
                  width: 220,
                  height: 220,
                ),
                const SizedBox(height: AppTheme.space4),
                SelectableText(token,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: token));
                Navigator.pop(context);
              },
              child: const Text('Copy & close'),
            ),
          ],
        ),
      );
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _resetDevice() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _CodePromptDialog(
        title: 'Reset device binding',
        label: 'App Reference ID / Shop Code',
        action: 'Reset',
        warning: 'This clears the device bound to this license — any '
            'device can then re-activate it. Use this when a shop lost or '
            'replaced their phone; it does not affect their expiry date.',
      ),
    );
    if (code == null || code.isEmpty) return;
    try {
      final cleared = await widget.api.resetDevice(deviceId: code);
      _snack(cleared > 0
          ? 'Device binding cleared — user can re-activate.'
          : 'No license bound to that code.');
      _reload();
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _extendByCode() async {
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (_) => const _ExtendByCodeDialog(),
    );
    if (result == null) return;
    try {
      final expiry = await widget.api
          .extendByDevice(deviceId: result.$1, months: result.$2);
      _snack('Extended to $expiry');
      _reload();
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _issueKey(Map<String, dynamic> request) async {
    try {
      final key = await widget.api.fulfillRequest(
        requestId: '${request['id']}',
        months: request['months'] is int ? request['months'] as int : null,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Key issued'),
          content: SelectableText(key,
              style: const TextStyle(
                  fontFamily: 'monospace', fontWeight: FontWeight.bold)),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: key));
                Navigator.pop(context);
              },
              child: const Text('Copy & close'),
            ),
          ],
        ),
      );
      _reload();
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _applyCredit(String shopId) async {
    try {
      final res = await widget.api.applyReferralCredit(shopId: shopId);
      final months = (res['months'] as num?)?.toInt() ?? 0;
      if (months <= 0) {
        final balance = (res['balance'] as num?)?.toInt() ?? 0;
        _snack('Not enough balance to credit a full month ($balance Ks).');
      } else {
        final amount = (res['amount'] as num?)?.toInt() ?? 0;
        _snack('Credited $months month(s) = $amount Ks to $shopId.');
      }
      _reload();
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _saveConfig(Map<String, String> config) async {
    try {
      await widget.api.setConfig(config);
      _snack('Config saved');
      _reload();
    } catch (e) {
      _snack('$e');
    }
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

