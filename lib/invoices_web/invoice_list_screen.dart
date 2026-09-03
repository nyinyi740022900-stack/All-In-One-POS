import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/currency_def.dart';
import '../core/money.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/app_widgets.dart';
import '../l10n/app_localizations.dart';
import 'invoice_detail_web_screen.dart';
import 'invoices_web_session.dart';

class _LocaleBar extends StatelessWidget implements PreferredSizeWidget {
  const _LocaleBar(
      {required this.locale, required this.onToggle, required this.onSignOut});
  final Locale locale;
  final VoidCallback onToggle;
  final VoidCallback onSignOut;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppBar(
      title: Text(l.navInvoices),
      actions: [
        TextButton.icon(
          onPressed: onToggle,
          icon: const Icon(Icons.language, size: 16),
          label: Text(
              locale.languageCode == 'my' ? l.languageEnglish : l.languageMyanmar),
        ),
        IconButton(
          tooltip: l.invWebSignOut,
          icon: const Icon(Icons.logout),
          onPressed: onSignOut,
        ),
      ],
    );
  }
}

/// One row of the shop's own sales ledger, fetched directly from Supabase
/// (RLS `shop_isolation` scopes every read to this browser's activated
/// shop) — read-only, no local cache/sync, since this is a print companion
/// not a full offline POS surface.
class InvoiceRow {
  final String id;
  final String invoiceNo;
  final String customerName;
  final String? customerPhone;
  final String paymentMethod;
  final int total;
  final DateTime finalizedAt;
  final bool isRefund;
  const InvoiceRow({
    required this.id,
    required this.invoiceNo,
    required this.customerName,
    this.customerPhone,
    required this.paymentMethod,
    required this.total,
    required this.finalizedAt,
    required this.isRefund,
  });

  factory InvoiceRow.fromRow(Map<String, dynamic> m) => InvoiceRow(
        id: m['id'] as String,
        invoiceNo: m['invoice_no'] as String,
        customerName: (m['customer_name'] as String?) ?? '',
        customerPhone: m['customer_phone'] as String?,
        paymentMethod: (m['payment_method'] as String?) ?? 'cash',
        total: (m['total'] as num?)?.toInt() ?? 0,
        // Stored UTC — see invoice_detail_web_screen.
        finalizedAt: DateTime.parse(m['finalized_at'] as String).toLocal(),
        isRefund: m['refund_of_sale_id'] != null,
      );
}

/// Classifies a raw Supabase-fetch failure into a real sentence — this
/// screen makes a direct `.from('sales').select()` REST call (no local
/// cache/sync layer to fall back on), so any offline/network hiccup here
/// surfaces straight from the client. Reuses the same shared keys
/// `activate_screen.dart`'s `_errorMessage` reaches for on this web target.
String _loadErrorMessage(AppLocalizations l, Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('socketexception') ||
      text.contains('clientexception') ||
      text.contains('failed host lookup') ||
      text.contains('failed to fetch') ||
      text.contains('network')) {
    return l.commonNetworkError;
  }
  return l.commonUnexpectedError;
}

class InvoiceListScreen extends StatefulWidget {
  const InvoiceListScreen({
    super.key,
    required this.locale,
    required this.onToggleLocale,
    required this.onSignedOut,
  });
  final Locale locale;
  final VoidCallback onToggleLocale;

  /// Rebuilds the ROOT so its `activated` gate re-evaluates. Without it,
  /// `setState` here only rebuilt this list — leaving the previous shop's
  /// ledger (customer names, phone numbers, totals) on screen after Sign
  /// Out, on the shared counter computer this tool is for. The odd tell was
  /// that toggling the language *did* snap back to the activate screen,
  /// because that rebuilds the root.
  final VoidCallback onSignedOut;

  @override
  State<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends State<InvoiceListScreen> {
  late Future<List<InvoiceRow>> _future;
  String _query = '';
  // This web target has no local Drift DB / Riverpod `shopCurrencyProvider`
  // (a separate, DB-less entry point — see `printing_providers.dart`'s
  // provider chain), so the shop's currency is fetched directly from
  // Supabase instead, same as `_load()` reads `sales` directly. Fails
  // closed to MMK (`CurrencyDef.byCode(null)`) until the fetch resolves,
  // matching `shopCurrencyProvider`'s own fail-closed default.
  CurrencyDef _currency = CurrencyDef.byCode(null);

  @override
  void initState() {
    super.initState();
    _future = _load();
    _loadCurrency();
  }

  Future<List<InvoiceRow>> _load() async {
    final rows = await Supabase.instance.client
        .from('sales')
        .select()
        .eq('is_deleted', false)
        .order('finalized_at', ascending: false)
        .limit(300) as List;
    return rows
        .map((e) => InvoiceRow.fromRow((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> _loadCurrency() async {
    try {
      final row = await Supabase.instance.client
          .from('shop_profiles')
          .select('currency_code')
          .limit(1)
          .maybeSingle();
      final code = row?['currency_code'] as String?;
      if (mounted) setState(() => _currency = CurrencyDef.byCode(code));
    } catch (_) {
      // Best-effort — stays MMK on failure, same as the mobile default.
    }
  }

  Future<void> _signOut() async {
    await InvoicesWebSession.signOut();
    if (mounted) widget.onSignedOut();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: _LocaleBar(
          locale: widget.locale,
          onToggle: widget.onToggleLocale,
          onSignOut: _signOut),
      body: FutureBuilder<List<InvoiceRow>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return EmptyStateView(
              icon: Icons.error_outline,
              title: _loadErrorMessage(l, snap.error!),
              actionLabel: l.commonRetry,
              onAction: () => setState(() => _future = _load()),
            );
          }
          final all = snap.data ?? const <InvoiceRow>[];
          final q = _query.trim().toLowerCase();
          final rows = q.isEmpty
              ? all
              : all
                  .where((r) =>
                      r.invoiceNo.toLowerCase().contains(q) ||
                      r.customerName.toLowerCase().contains(q) ||
                      (r.customerPhone ?? '').toLowerCase().contains(q))
                  .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppTheme.space3),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: l.invWebSearchHint,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: all.isEmpty
                    ? EmptyStateView(
                        icon: Icons.receipt_long_outlined,
                        title: l.invoicesEmpty,
                      )
                    : rows.isEmpty
                        ? EmptyStateView(
                            icon: Icons.search_off,
                            title: l.invWebNoResults,
                          )
                        : ListView.separated(
                            itemCount: rows.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final r = rows[i];
                              return ListTile(
                                leading: Icon(r.isRefund
                                    ? Icons.undo
                                    : Icons.receipt_long),
                                title: Text(r.invoiceNo),
                                subtitle: Text([
                                  if (r.customerName.isNotEmpty) r.customerName,
                                  if ((r.customerPhone ?? '').isNotEmpty)
                                    r.customerPhone!,
                                ].join(' · ')),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    MoneyText(Money(r.total).withCurrency(
                                        _currency, widget.locale.languageCode)),
                                    if (r.isRefund)
                                      Text(l.invoiceRefunded,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                  color: AppColors.of(context)
                                                      .danger)),
                                  ],
                                ),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => InvoiceDetailWebScreen(saleId: r.id),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}
