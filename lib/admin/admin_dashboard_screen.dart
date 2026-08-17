import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/app_widgets.dart';
import 'admin_api.dart';
part 'admin_dashboard_widgets.dart';

enum _ManageByCodeAction { extend, reset, offline }

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
  List<Map<String, dynamic>>? _shops;
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
      // All 7 calls are independent reads (none depends on another's
      // result) — parallelize instead of 7 sequential round-trips, so a
      // slow connection doesn't leave the tab showing stale data for
      // several seconds after an action's success snackbar already fired.
      final results = await Future.wait<dynamic>([
        widget.api.listLicenses(),
        widget.api.listRequests(),
        widget.api.listEvents(),
        widget.api.listReferrals(),
        widget.api.listCommissions(),
        widget.api.listShops(),
        widget.api.getConfig(),
      ]);
      if (!mounted) return;
      setState(() {
        _licenses = results[0] as List<Map<String, dynamic>>;
        _requests = results[1] as List<Map<String, dynamic>>;
        _events = results[2] as List<Map<String, dynamic>>;
        _referrals = results[3] as List<Map<String, dynamic>>;
        _commissions = results[4] as List<Map<String, dynamic>>;
        _shops = results[5] as List<Map<String, dynamic>>;
        _config = results[6] as Map<String, String>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _adminErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingRequests =
        (_requests ?? []).where((r) => r['status'] == 'pending').length;
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('All In One POS Admin'),
          bottom: TabBar(isScrollable: true, tabs: [
            Tab(text: 'Licenses (${_licenses?.length ?? 0})'),
            Tab(text: 'Requests ($pendingRequests)'),
            Tab(text: 'History (${_events?.length ?? 0})'),
            Tab(text: 'Referrals (${_referrals?.length ?? 0})'),
            Tab(text: 'Shops (${_shops?.length ?? 0})'),
            const Tab(text: 'Config'),
          ]),
          actions: [
            // Grouped into one labeled menu rather than three bare icon
            // buttons: none of `more_time`/`phonelink_erase`/`offline_bolt`
            // reads clearly on sight, and tooltips never show on a touch
            // tap — a menu with text labels is legible without guessing,
            // and "Reset device binding" (a real, if reversible, action)
            // no longer sits one misclick away from "Extend."
            PopupMenuButton<_ManageByCodeAction>(
              tooltip: 'Manage by code',
              icon: const Icon(Icons.dialpad),
              onSelected: (action) => switch (action) {
                _ManageByCodeAction.extend => _extendByCode(),
                _ManageByCodeAction.reset => _resetDevice(),
                _ManageByCodeAction.offline => _generateOffline(),
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _ManageByCodeAction.extend,
                  child: Text('Extend by App Reference ID or Email'),
                ),
                PopupMenuItem(
                  value: _ManageByCodeAction.reset,
                  child: Text('Reset device binding'),
                ),
                PopupMenuItem(
                  value: _ManageByCodeAction.offline,
                  child: Text('Generate offline code'),
                ),
              ],
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
                try {
                  await widget.api.signOut();
                  widget.onSignedOut();
                } catch (e) {
                  _snack(_adminErrorMessage(e));
                }
              },
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _generateKey,
          icon: const Icon(Icons.add),
          label: const Text('Generate key'),
        ),
        body: Column(
          children: [
            // Distinct from the initial-load spinner below: shown on top of
            // already-loaded data during a background reload, so a refresh
            // in flight after an action's success snackbar doesn't look
            // like the action silently did nothing.
            if (_loading && _licenses != null)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _error != null
                  ? _ErrorView(message: _error!, onRetry: _reload)
                  : _loading && _licenses == null
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(children: [
                          _LicensesTab(rows: _licenses ?? const []),
                          _RequestsTab(
                            rows: _requests ?? const [],
                            onConfirm: _confirmPayment,
                            onDecline: _declineRequest,
                          ),
                          _HistoryTab(rows: _events ?? const []),
                          _ReferralsTab(
                            commissions: _commissions ?? const [],
                            referrals: _referrals ?? const [],
                            onApplyCredit: _applyCredit,
                          ),
                          _ShopsTab(
                            rows: _shops ?? const [],
                            onGenerateKey: (shopId) =>
                                _generateKey(initialShopId: shopId),
                          ),
                          _ConfigTab(
                            initial: _config ?? const {},
                            onSave: _saveConfig,
                          ),
                        ]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateKey({String? initialShopId}) async {
    final result = await showDialog<_KeyRequest>(
      context: context,
      builder: (_) => _GenerateKeyDialog(initialShopId: initialShopId),
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
    } on LicenseAlreadyExistsException {
      _snack('This shop already has a license — use Extend instead of '
          'Generate key.');
    } catch (e) {
      _snack(_adminErrorMessage(e));
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
      _snack(_adminErrorMessage(e));
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
      _snack(_adminErrorMessage(e));
    }
  }

  Future<void> _extendByCode() async {
    final result = await showDialog<(String?, String?, int)>(
      context: context,
      builder: (_) => const _ExtendByCodeDialog(),
    );
    if (result == null) return;
    try {
      final outcome = await widget.api.extendLicense(
        deviceId: result.$1,
        email: result.$2,
        months: result.$3,
      );
      _snack(outcome.created
          ? 'No license existed — created one, expires ${outcome.expiresAt}'
          : 'Extended to ${outcome.expiresAt}');
      _reload();
    } catch (e) {
      _snack(_adminErrorMessage(e));
    }
  }

  Future<void> _confirmPayment(Map<String, dynamic> request) async {
    try {
      final key = await widget.api.confirmPayment(
        requestId: '${request['id']}',
        months: request['months'] is int ? request['months'] as int : null,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Payment confirmed'),
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
      _snack(_adminErrorMessage(e));
    }
  }

  Future<void> _declineRequest(Map<String, dynamic> request) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _DeclineReasonDialog(),
    );
    if (reason == null) return;
    try {
      await widget.api.rejectRequest(
        requestId: '${request['id']}',
        reason: reason.isEmpty ? null : reason,
      );
      _snack('Request declined.');
      _reload();
    } catch (e) {
      _snack(_adminErrorMessage(e));
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
      _snack(_adminErrorMessage(e));
    }
  }

  Future<void> _saveConfig(Map<String, String> config) async {
    try {
      await widget.api.setConfig(config);
      _snack('Config saved');
      _reload();
    } catch (e) {
      _snack(_adminErrorMessage(e));
    }
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

/// Maps the raw error codes thrown by [AdminApi._throwIfError] (and the
/// backend's `admin` Edge Function — see `supabase/functions/admin/index.ts`)
/// to real sentences, the same way `admin_login_screen.dart`'s `_signIn`
/// already does for sign-in. This console has no l10n pipeline (English
/// only, by design), so these stay literal strings. Falls back to the raw
/// exception text only for a code this function doesn't recognize, so an
/// unmapped backend error is still visible (for support/debugging) rather
/// than silently swallowed.
String _adminErrorMessage(Object e) {
  final raw = e.toString();
  // AdminApi._throwIfError throws Exception('$code') or
  // Exception('$code: $detail') — pull just the leading code token.
  final code = RegExp(r'^Exception: (\w+)').firstMatch(raw)?.group(1);
  switch (code) {
    case 'not_found':
      return 'No shop found matching that email or App Reference ID.';
    case 'forbidden':
      return "You don't have permission for this.";
    case 'not_authenticated':
      return 'Your session expired — sign in again.';
    case 'bad_request':
      return 'That request was missing required information.';
    case 'server_error':
      return 'Something went wrong on the server — try again.';
    case 'unknown_action':
      return "That action isn't supported.";
    case 'method_not_allowed':
      return 'Something went wrong on the server — try again.';
    case 'license_already_exists':
      return 'This shop already has a license.';
  }
  final lower = raw.toLowerCase();
  if (lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('clientexception') ||
      lower.contains('network')) {
    return 'Network error — check your connection and try again.';
  }
  return raw.replaceFirst('Exception: ', '');
}

