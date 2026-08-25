import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/app_widgets.dart';
import '../l10n/app_localizations.dart';
import 'renew_print_web.dart';
import 'storefront_api.dart';

/// The receipt for one renewal request — what a shop gets after paying, and
/// what it can come back to.
///
/// Reached two ways, both landing here: straight after submitting the /renew
/// form (the id is already in hand), or later by opening
/// `/renew?receipt=<id>`. That second path is the point of the whole screen —
/// before it existed a shop that closed the tab had no way to find out
/// whether its payment had been accepted, and the only recourse was to
/// message Support.
class RenewalReceiptView extends StatefulWidget {
  const RenewalReceiptView({
    super.key,
    required this.requestId,
    this.initialInvoiceNo,
  });

  final String requestId;

  /// Known immediately after submitting, so the number can be shown while
  /// the first fetch is still in flight.
  final String? initialInvoiceNo;

  @override
  State<RenewalReceiptView> createState() => _RenewalReceiptViewState();
}

class _RenewalReceiptViewState extends State<RenewalReceiptView> {
  final _api = StorefrontApi();
  static final _money = NumberFormat('#,##0', 'en_US');
  static final _stamp = DateFormat('yyyy-MM-dd HH:mm');

  RenewalReceipt? _receipt;
  bool _loading = true;
  bool _notFound = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _notFound = false;
      _failed = false;
    });
    try {
      final r = await _api.fetchReceipt(widget.requestId);
      if (!mounted) return;
      setState(() {
        _receipt = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // A link that was mistyped or belongs to a deleted request is a
        // different problem from a dropped connection, and only one of them
        // is worth retrying.
        _notFound = '$e'.contains('not_found');
        _failed = !_notFound;
      });
    }
  }

  String get _link {
    final base = Uri.base;
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/renew',
      queryParameters: {'receipt': widget.requestId},
    ).toString();
  }

  Future<void> _copyLink(AppLocalizations l) async {
    await Clipboard.setData(ClipboardData(text: _link));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.receiptLinkCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.space4),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: _body(l),
        ),
      ),
    );
  }

  Widget _body(AppLocalizations l) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppTheme.space6),
        child: AppLoadingView(),
      );
    }
    if (_notFound) {
      return _Message(icon: Icons.search_off, text: l.receiptNotFound);
    }
    if (_failed || _receipt == null) {
      return Column(
        children: [
          _Message(icon: Icons.wifi_off, text: l.receiptLoadFailed),
          const SizedBox(height: AppTheme.space3),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: Text(l.receiptRefresh),
          ),
        ],
      );
    }
    return _receiptCard(l, _receipt!);
  }

  Widget _receiptCard(AppLocalizations l, RenewalReceipt r) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    // Three visual states, but four logical ones: "paid, not yet minted"
    // borrows the success colour because the shop's side of the deal is
    // done — nothing is owed and nothing is wrong, it is our work that is
    // still in flight.
    final (Color tone, IconData icon, String head, String bodyText) =
        switch (r) {
      _ when r.isRejected => (
          colors.danger,
          Icons.cancel_outlined,
          l.receiptStatusRejected,
          r.rejectReason ?? '',
        ),
      _ when r.isFulfilled => (
          colors.success,
          Icons.verified,
          l.receiptStatusFulfilled,
          l.receiptStatusFulfilledBody,
        ),
      _ when r.isPaidNotFulfilled => (
          colors.success,
          Icons.hourglass_top,
          l.receiptStatusPending,
          l.receiptStatusPaidBody,
        ),
      _ => (
          colors.warning,
          Icons.schedule,
          l.receiptStatusPending,
          l.receiptStatusPendingBody,
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.receiptTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppTheme.space1),
        SelectableText(
          r.invoiceNo.isNotEmpty ? r.invoiceNo : (widget.initialInvoiceNo ?? ''),
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontFeatures: AppTheme.tabularFigures),
        ),
        const SizedBox(height: AppTheme.space3),

        // Status banner
        Container(
          padding: const EdgeInsets.all(AppTheme.space3),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(color: tone.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: tone),
              const SizedBox(width: AppTheme.space2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(head,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(color: tone)),
                    if (bodyText.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(bodyText, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        // The key is the payout of the whole flow — give it its own block,
        // selectable, never buried in the detail rows.
        if (r.isFulfilled && (r.issuedKey ?? '').isNotEmpty) ...[
          const SizedBox(height: AppTheme.space3),
          Text(l.receiptYourKey, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppTheme.space1),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppTheme.space3),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: SelectableText(
              r.issuedKey!,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontFeatures: AppTheme.tabularFigures),
            ),
          ),
        ],

        const SizedBox(height: AppTheme.space4),
        const Divider(height: 1),
        _row(l.receiptShop, r.shopName),
        if ((r.deviceIdTail ?? '').isNotEmpty)
          _row(l.receiptDeviceTail, '…${r.deviceIdTail}'),
        _row(l.receiptPlan,
            '${_planLabel(l, r.plan)} · ${l.receiptMonths(r.months)}'),
        _row(l.receiptAmount, '${_money.format(r.amount)} ${l.currencySymbol}'),
        if ((r.method ?? '').isNotEmpty)
          _row(l.receiptMethod, _methodLabel(r.method!)),
        if ((r.refNo ?? '').isNotEmpty) _row(l.receiptRefNo, r.refNo!),
        if (r.createdAt != null)
          _row(l.receiptSubmittedAt, _stamp.format(r.createdAt!)),
        const Divider(height: 1),

        const SizedBox(height: AppTheme.space4),
        Text(l.receiptSaveLink, style: theme.textTheme.bodySmall),
        const SizedBox(height: AppTheme.space2),
        Wrap(
          spacing: AppTheme.space2,
          runSpacing: AppTheme.space2,
          children: [
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(l.receiptRefresh),
            ),
            OutlinedButton.icon(
              onPressed: () => _copyLink(l),
              icon: const Icon(Icons.link),
              label: Text(l.receiptCopyLink),
            ),
            OutlinedButton.icon(
              onPressed: printCurrentPage,
              icon: const Icon(Icons.print_outlined),
              label: Text(l.receiptPrint),
            ),
          ],
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          const SizedBox(width: AppTheme.space2),
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  String _planLabel(AppLocalizations l, String plan) =>
      plan == 'yearly' ? l.licensePlanYearly : l.licensePlanMonthly;

  String _methodLabel(String m) => switch (m) {
        'kbzpay' => 'KBZPay',
        'wavepay' => 'WavePay',
        _ => m,
      };
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space5),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: AppTheme.space2),
          Text(text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
