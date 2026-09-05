import 'dart:async';
import 'dart:math' as math;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/money.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/app_widgets.dart';
import '../features/support/viber_launch.dart';
import 'admin_api.dart';
import 'admin_stats.dart';

part 'admin_dashboard_widgets.dart';
part 'admin_shell.dart';
part 'admin_overview.dart';
part 'admin_shop_hub.dart';
part 'admin_licensing.dart';

enum _AdminSection {
  dashboard,
  inbox,
  shops,
  payments,
  licensing,
  settings,
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    super.key,
    required this.api,
    required this.onSignedOut,
  });
  final AdminApi api;
  final VoidCallback onSignedOut;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  List<Map<String, dynamic>>? _licenses;
  List<Map<String, dynamic>>? _requests;
  List<Map<String, dynamic>>? _events;
  List<Map<String, dynamic>>? _shops;
  Map<String, String>? _config;
  String? _error;
  bool _loading = false;
  bool _didPickLanding = false;

  /// Set while a money-moving action is in flight. Every such action here
  /// runs an `await` that `invokeBounded` may let stand for a full 15s with
  /// nothing on screen saying so — which is precisely what makes an admin
  /// click again. The buttons themselves stay enabled (they live in child
  /// widgets), so this guards at the handler instead: a second tap is
  /// dropped rather than becoming a second extend/mint/credit.
  bool _moneyBusy = false;

  _AdminSection _section = _AdminSection.dashboard;
  AdminShopFilter _shopFilter = AdminShopFilter.all;
  String? _selectedShopId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    // Called from every action handler AFTER an await, so the dashboard can
    // be gone by now (session expiry flipping the auth gate, a sign-out).
    // Every other setState here is guarded; this opening one was not.
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        widget.api.listLicenses(),
        widget.api.listRequests(),
        widget.api.listEvents(),
        widget.api.listShops(),
        widget.api.getConfig(),
      ]);
      if (!mounted) return;
      final requests = results[1] as List<Map<String, dynamic>>;
      final pending = requests.where((r) => r['status'] == 'pending').length;
      setState(() {
        _licenses = results[0] as List<Map<String, dynamic>>;
        _requests = requests;
        _events = results[2] as List<Map<String, dynamic>>;
        _shops = results[3] as List<Map<String, dynamic>>;
        _config = results[4] as Map<String, String>;
        if (!_didPickLanding) {
          _didPickLanding = true;
          if (pending > 0) _section = _AdminSection.inbox;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _adminErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  AdminStats get _stats => AdminStats.from(
    shops: _shops ?? const [],
    requests: _requests ?? const [],
    now: DateTime.now(),
  );

  void _go(
    _AdminSection section, {
    AdminShopFilter? shopFilter,
    String? shopId,
  }) {
    setState(() {
      _section = section;
      if (shopFilter != null) _shopFilter = shopFilter;
      if (section == _AdminSection.shops) {
        if (shopFilter != null) {
          _selectedShopId = shopId;
        } else if (shopId != null) {
          _selectedShopId = shopId;
        }
      } else {
        _selectedShopId = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pending = _stats.pendingCount;
    final loaded = _licenses != null;
    return Scaffold(
      body: Column(
        children: [
          if (_loading && loaded) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _AdminShell(
              section: _section,
              pendingCount: pending,
              onSelect: (s) => _go(
                s,
                shopFilter: s == _AdminSection.shops
                    ? AdminShopFilter.all
                    : null,
              ),
              title: _titleFor(_section, pending),
              onReload: _loading ? null : _reload,
              onSignOut: _signOut,
              body: _error != null
                  ? _ErrorView(message: _error!, onRetry: _reload)
                  : _loading && !loaded
                  ? const Center(child: CircularProgressIndicator())
                  : _page(),
            ),
          ),
        ],
      ),
    );
  }

  String _titleFor(_AdminSection section, int pending) => switch (section) {
    _AdminSection.dashboard => 'Dashboard',
    _AdminSection.inbox => pending == 0 ? 'Inbox' : 'Inbox ($pending)',
    _AdminSection.shops => 'Shops',
    _AdminSection.payments => 'Payments',
    _AdminSection.licensing => 'Licensing',
    _AdminSection.settings => 'Settings',
  };

  Widget _page() {
    final shops = _shops ?? const [];
    final licenses = _licenses ?? const [];
    final requests = _requests ?? const [];
    switch (_section) {
      case _AdminSection.dashboard:
        return _OverviewPage(
          stats: _stats,
          pending: requests.where((r) => r['status'] == 'pending').toList(),
          onOpenInbox: () => _go(_AdminSection.inbox),
          onOpenShops: (filter) => _go(_AdminSection.shops, shopFilter: filter),
          onOpenPayments: () => _go(_AdminSection.payments),
        );
      case _AdminSection.inbox:
        return _RequestsTab(
          rows: requests,
          pendingOnly: true,
          onConfirm: _confirmPayment,
          onDecline: _declineRequest,
        );
      case _AdminSection.shops:
        return _ShopHubPage(
          shops: shops,
          licenses: licenses,
          requests: requests,
          filter: _shopFilter,
          selectedShopId: _selectedShopId,
          supportViber: _config?['support.viber'] ?? '',
          onFilter: (f) => setState(() => _shopFilter = f),
          onSelectShop: (id) => setState(() => _selectedShopId = id),
          onExtendEmail: (shop) =>
              _extend(byEmail: true, initial: '${shop['email'] ?? ''}'),
          onExtendDevice: (_, deviceId) =>
              _extend(byEmail: false, initial: deviceId),
          onResetDevice: _resetDevice,
          onOffline: (shop) => _generateOffline(shop: shop),
          onGenerateKey: (shopId) => _generateKey(initialShopId: shopId),
          onGrantExtraDevice: _grantExtraDevice,
          onViber: _openViber,
          onResetPassword: _resetPassword,
          onUnlink: _unlinkAccount,
          onRestore: _restoreAccount,
        );
      case _AdminSection.payments:
        return _PaymentsPage(
          requests: requests,
          events: _events ?? const [],
          onConfirm: _confirmPayment,
          onDecline: _declineRequest,
        );
      case _AdminSection.licensing:
        return _LicensingPage(
          onExtendEmail: () => _extend(byEmail: true),
          onExtendDevice: () => _extend(byEmail: false),
          onOpenShops: () => _go(_AdminSection.shops),
        );
      case _AdminSection.settings:
        return _ConfigTab(initial: _config ?? const {}, onSave: _saveConfig);
    }
  }

  Future<void> _signOut() async {
    try {
      await widget.api.signOut();
      widget.onSignedOut();
    } catch (e) {
      _snack(_adminErrorMessage(e));
    }
  }

  Future<void> _openViber(String number) async {
    final opened = await launchViberChat(number);
    if (opened) return;
    await Clipboard.setData(ClipboardData(text: number));
    _snack("Viber isn't installed — number copied.");
  }

  Future<void> _extend({required bool byEmail, String? initial}) async {
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (_) =>
          _ExtendIdentifierDialog(byEmail: byEmail, initial: initial),
    );
    if (result == null) return;
    final identifier = result.$1;
    final months = result.$2;
    Map<String, dynamic>? shop = byEmail
        ? findShopByEmail(_shops ?? const [], identifier)
        : findShopByDevice(
            _shops ?? const [],
            _licenses ?? const [],
            identifier,
          );
    try {
      shop ??= await widget.api.lookupShop(
        email: byEmail ? identifier : null,
        deviceId: byEmail ? null : identifier,
      );
    } catch (e) {
      _snack(_adminErrorMessage(e));
      return;
    }
    final preview = Map<String, dynamic>.from(shop);
    if (preview['devices'] is! List) {
      preview['devices'] = shopDevices(shop, _licenses ?? const []);
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ExtendPreviewDialog(
        shop: preview,
        months: months,
        byEmail: byEmail,
        identifier: identifier,
      ),
    );
    if (ok != true) return;
    if (_moneyBusy) return;
    setState(() => _moneyBusy = true);
    try {
      final outcome = await widget.api.extendLicense(
        email: byEmail ? identifier : null,
        deviceId: byEmail ? null : identifier,
        months: months,
      );
      _snack(
        outcome.duplicate
            // The server granted NOTHING — it recognised this as a repeat of
            // a recent identical extend. Saying "Extended to <date>" here
            // would be a lie in the one case where the admin most needs the
            // truth: two separate top-ups bought in quick succession look
            // identical to a double-click, and the shop would be a month
            // short with everyone believing it was applied.
            ? 'Ignored as a repeat of a recent identical extend — nothing '
                'was added. Still expires ${outcome.expiresAt}. If this was '
                'a second, separate payment, wait a minute and try again.'
            : outcome.created
                ? 'No license existed — created one, expires ${outcome.expiresAt}'
                : 'Extended to ${outcome.expiresAt}',
      );
      _reload();
    } catch (e) {
      _snack(_adminErrorMessage(e));
    } finally {
      if (mounted) setState(() => _moneyBusy = false);
    }
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
      await _showCopyDialog('License key created', key);
      _reload();
    } on LicenseAlreadyExistsException {
      _snack(
        'This shop already has a license — use Extend instead of '
        'Generate key.',
      );
    } catch (e) {
      _snack(_adminErrorMessage(e));
    }
  }

  Future<void> _grantExtraDevice(Map<String, dynamic> shop) async {
    final current = (shop['extra_slots'] as num?)?.toInt() ?? 0;
    final result = await showDialog<({int extraSlots, int months})>(
      context: context,
      builder: (_) => _DeviceAllowanceDialog(
        initialExtraSlots: current <= 0 ? 1 : current,
      ),
    );
    if (result == null) return;
    try {
      final saved = await widget.api.setDeviceAllowance(
        shopId: '${shop['shop_id']}',
        extraSlots: result.extraSlots,
        months: result.months,
      );
      if (!mounted) return;
      final until = saved.extrasExpiresAt == null
          ? ''
          : ' until ${_date(saved.extrasExpiresAt)}';
      _snack(
        saved.extraSlots == 0
            ? 'Paid extra devices cleared. Free cap (this phone + 2) still applies.'
            : 'This shop may use ${saved.extraSlots} paid extra device(s)$until. '
                'Tell them to sign in on the new phone and tap Check for renewal — no key.',
      );
      _reload();
    } catch (e) {
      _snack(_adminErrorMessage(e));
    }
  }

  Future<void> _generateOffline({Map<String, dynamic>? shop}) async {
    final req = await showDialog<_OfflineRequest>(
      context: context,
      builder: (_) => _OfflineCodeDialog(
        initialShopId: shop == null ? null : '${shop['shop_id']}',
        initialShopName: shop == null
            ? null
            : '${shop['shop_name'] ?? shop['shop_id']}',
      ),
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
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppTheme.space4),
                BarcodeWidget(
                  barcode: Barcode.qrCode(),
                  data: token,
                  width: 220,
                  height: 220,
                ),
                const SizedBox(height: AppTheme.space4),
                SelectableText(
                  token,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
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

  Future<void> _resetDevice([String? initial]) async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => _CodePromptDialog(
        title: 'Reset device binding',
        label: 'App Reference ID / Shop Code',
        action: 'Reset',
        initial: initial,
        warning:
            'This clears the device bound to this license — any '
            'device can then re-activate it. Use this when a shop lost or '
            'replaced their phone; it does not affect their expiry date.',
      ),
    );
    if (code == null || code.isEmpty) return;
    try {
      final cleared = await widget.api.resetDevice(deviceId: code);
      _snack(
        cleared > 0
            ? 'Device binding cleared — user can re-activate.'
            : 'No license bound to that code.',
      );
      _reload();
    } catch (e) {
      _snack(_adminErrorMessage(e));
    }
  }

  Future<void> _confirmPayment(Map<String, dynamic> request) async {
    if (!mounted) return;
    // One accidental click used to fulfil irreversibly (mint/extend the
    // license, mark fulfilled) — the dialog is both the safety gate and the
    // at-a-glance verification surface for amount/shop/txn before commit.
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmPaymentDialog(request: request),
    );
    if (ok != true || !mounted) return;
    if (_moneyBusy) return;
    setState(() => _moneyBusy = true);
    try {
      final key = await widget.api.confirmPayment(
        requestId: '${request['id']}',
        months: request['months'] is int ? request['months'] as int : null,
      );
      if (!mounted) return;
      await _showCopyDialog('Payment confirmed', key);
      _reload();
    } on RequestNotClosedException catch (e) {
      // The licence IS issued — this is not a failure to retry. Clicking
      // Confirm again would mint a second one for the same payment, so say
      // so in a dialog (not a snackbar that scrolls away) and hand over the
      // key that was already created.
      if (!mounted) return;
      await _showCopyDialog(
        'Licence issued — but the request is still open',
        e.key,
      );
      if (!mounted) return;
      _snack(
        'Do NOT confirm this request again — the licence above was already '
        'issued. Close the request by hand instead.',
      );
      _reload();
    } catch (e) {
      _snack(_adminErrorMessage(e));
    } finally {
      if (mounted) setState(() => _moneyBusy = false);
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

  Future<void> _saveConfig(Map<String, String> config) async {
    try {
      await widget.api.setConfig(config);
      _snack('Config saved');
      _reload();
    } catch (e) {
      _snack(_adminErrorMessage(e));
    }
  }

  Future<void> _resetPassword(String email) async {
    try {
      final link = await widget.api.resetPassword(email: email);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Password reset link'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Send this to $email on Viber. It is not emailed — paste '
                  'it into the chat.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppTheme.space3),
                SelectableText(link, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: link));
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

  Future<void> _unlinkAccount(String userId, String email) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlink this login?'),
        content: Text(
          '$email will no longer belong to this shop. They can still '
          'exist as an Auth user, but they cannot open this shop until '
          'invited again. The last owner of a shop cannot be unlinked.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.of(ctx).danger,
            ),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.unlinkAccount(userId: userId);
      _snack('Unlinked $email.');
      _reload();
    } catch (e) {
      _snack(_adminErrorMessage(e));
    }
  }

  Future<void> _restoreAccount(String userId, String email) async {
    try {
      await widget.api.restoreAccount(userId: userId);
      _snack('Restored access for $email.');
      _reload();
    } catch (e) {
      _snack(_adminErrorMessage(e));
    }
  }

  Future<void> _showCopyDialog(String title, String value) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SelectableText(
          value,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              Navigator.pop(context);
            },
            child: const Text('Copy & close'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

String _adminErrorMessage(Object e) {
  final raw = e.toString();

  // A timeout is NOT a failure you may blindly retry. `invokeBounded` gives
  // up at 15s, but the server keeps going — the licence may already be
  // minted. Retrying is exactly how one payment becomes two licence terms,
  // so say what to do instead of offering the usual "try again".
  if (e is TimeoutException) {
    return 'That took too long to answer. It may still have gone through — '
        'reload and check before trying again.';
  }

  // Every `json({error: ...}, 4xx/5xx)` the Edge Function returns arrives
  // as a thrown FunctionException, NOT as a FunctionResponse — so the
  // error code lives in `details`, and the old `^Exception: (\w+)` pattern
  // (which only matches a plain `Exception('code')`) never matched a single
  // real server error. Every curated message below was unreachable: the
  // admin saw the raw exception string and could not tell "already done,
  // stop" from "failed, retry" — the precise decision that produces a
  // double-fire on a money action.
  String? code;
  if (e is FunctionException) {
    final details = e.details;
    if (details is Map) code = details['error'] as String?;
    code ??= '${e.status}';
  }
  code ??= RegExp(r'^Exception: (\w+)').firstMatch(raw)?.group(1);
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
    case 'already_fulfilled':
      return 'This request was already confirmed — refresh to see it.';
    case 'last_owner':
      return 'Cannot unlink the last owner of this shop.';
    case 'cannot_unlink_admin':
      return 'Admin accounts cannot be unlinked from here.';
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

// Deliberately hardcoded to MMK, not `shopCurrencyProvider` — this admin
// console sums revenue/KPIs *across every shop*, and shops can now run in
// different currencies (THB/USD/JPY). Those integers never numerically add
// together, so a cross-shop total can only ever be presented in one fixed
// unit; MMK stays the reporting currency here regardless of any individual
// shop's own POS currency.
String _ks(int kyat) => Money(kyat).withSymbol('Ks');
