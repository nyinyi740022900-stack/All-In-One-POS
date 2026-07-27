import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/money.dart';
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
        finalizedAt: DateTime.parse(m['finalized_at'] as String),
        isRefund: m['refund_of_sale_id'] != null,
      );
}

class InvoiceListScreen extends StatefulWidget {
  const InvoiceListScreen(
      {super.key, required this.locale, required this.onToggleLocale});
  final Locale locale;
  final VoidCallback onToggleLocale;

  @override
  State<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends State<InvoiceListScreen> {
  late Future<List<InvoiceRow>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
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

  Future<void> _signOut() async {
    await InvoicesWebSession.signOut();
    if (mounted) setState(() {});
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
            return Center(child: Text('${snap.error}'));
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
                padding: const EdgeInsets.all(12),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: l.invWebSearchHint,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: all.isEmpty
                    ? Center(child: Text(l.invoicesEmpty))
                    : rows.isEmpty
                        ? Center(child: Text(l.invWebNoResults))
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
                                    Text(Money(r.total).withSymbol(l.currencySymbol)),
                                    if (r.isRefund)
                                      Text(l.invoiceRefunded,
                                          style: const TextStyle(
                                              fontSize: 11, color: Colors.red)),
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
