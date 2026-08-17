import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/app_widgets.dart';
import '../features/invoices/invoice_pdf.dart';
import '../features/invoices/invoice_view.dart';
import '../l10n/app_localizations.dart';
import 'invoices_web_download.dart';

/// Fetches one sale + its items directly from Supabase and renders it with
/// the same [InvoiceView] used by the mobile app's Share-invoice and the
/// storefront's order confirmation — then offers a real A4 PDF download
/// ([buildInvoicePdf]) for printing sharp at full size from a computer.
/// Classifies a raw Supabase-fetch failure into a real sentence — same
/// direct-REST-call shape (and same helper) as `invoice_list_screen.dart`'s
/// `_loadErrorMessage`.
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

class InvoiceDetailWebScreen extends StatefulWidget {
  const InvoiceDetailWebScreen({super.key, required this.saleId});
  final String saleId;

  @override
  State<InvoiceDetailWebScreen> createState() => _InvoiceDetailWebScreenState();
}

class _InvoiceDetailWebScreenState extends State<InvoiceDetailWebScreen> {
  late Future<InvoiceData> _future;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<InvoiceData> _load() async {
    final client = Supabase.instance.client;
    final sale = await client.from('sales').select().eq('id', widget.saleId).single();
    final items = await client
        .from('sale_items')
        .select()
        .eq('sale_id', widget.saleId)
        .eq('is_deleted', false) as List;

    // Best-effort shop identity — the storefront row is the only remotely
    // synced source of shop name/logo/phone/address (the mobile app's own
    // Shop profile is a device-local setting, never synced). A shop that
    // hasn't published a storefront just gets a plain, un-branded header.
    final sf = await client.from('storefronts').select().maybeSingle();

    final paid = (sale['paid'] as num?)?.toInt() ?? 0;
    final total = (sale['total'] as num?)?.toInt() ?? 0;
    final paymentStatus = paid >= total ? 'paid' : (paid > 0 ? 'partial' : 'unpaid');

    return InvoiceData(
      shopName: (sf?['display_name'] as String?) ?? '',
      shopLogoUrl: sf?['logo_url'] as String?,
      shopPhone: sf?['phone'] as String?,
      shopAddress: sf?['address'] as String?,
      invoiceNo: sale['invoice_no'] as String,
      date: DateTime.parse(sale['finalized_at'] as String),
      customerName: (sale['customer_name'] as String?) ?? '',
      customerPhone: sale['customer_phone'] as String?,
      items: items
          .map((e) => (e as Map).cast<String, dynamic>())
          .map((m) => InvoiceItemData(
                name: m['name_snapshot'] as String,
                qty: (m['qty'] as num).toInt(),
                lineTotal: (m['line_total'] as num).toInt(),
              ))
          .toList(),
      paymentStatus: paymentStatus,
    );
  }

  Future<void> _downloadPdf(InvoiceData data) async {
    setState(() => _downloading = true);
    try {
      final bytes = await buildInvoicePdf(data);
      downloadBytes(bytes, '${data.invoiceNo}.pdf', 'application/pdf');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.navInvoices)),
      body: FutureBuilder<InvoiceData>(
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
          final data = snap.data!;
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.space5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InvoiceView(data: data, width: 420),
                  const SizedBox(height: AppTheme.space5),
                  FilledButton.icon(
                    onPressed: _downloading ? null : () => _downloadPdf(data),
                    icon: _downloading
                        ? const ButtonSpinner()
                        : const Icon(Icons.picture_as_pdf),
                    label: Text(l.invWebDownloadPdf),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
