import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/currency_def.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/app_widgets.dart';
import '../features/invoices/cashier_label.dart';
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
  Future<InvoiceData>? _future;
  bool _started = false;
  bool _downloading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _future = _load(AppLocalizations.of(context));
  }

  Future<InvoiceData> _load(AppLocalizations l) async {
    final client = Supabase.instance.client;
    final sale = await client
        .from('sales')
        .select()
        .eq('id', widget.saleId)
        .single();
    final items =
        await client
                .from('sale_items')
                .select()
                .eq('sale_id', widget.saleId)
                .eq('is_deleted', false)
            as List;

    // Best-effort shop identity — the storefront row is the only remotely
    // synced source of shop name/logo/phone/address (the mobile app's own
    // Shop profile is a device-local setting, never synced). A shop that
    // hasn't published a storefront just gets a plain, un-branded header.
    final sf = await client.from('storefronts').select().maybeSingle();

    final paid = (sale['paid'] as num?)?.toInt() ?? 0;
    final total = (sale['total'] as num?)?.toInt() ?? 0;
    final paymentStatus = paid >= total
        ? 'paid'
        : (paid > 0 ? 'partial' : 'unpaid');
    final methodCode = (sale['payment_method'] as String?) ?? 'cash';

    String? customName;
    const known = {
      'cash',
      'kbzpay',
      'wavepay',
      'ayapay',
      'cbpay',
      'credit',
      'cod',
      'transfer',
    };
    if (!known.contains(methodCode)) {
      try {
        final account = await client
            .from('payment_accounts')
            .select('name')
            .eq('id', methodCode)
            .maybeSingle();
        customName = account?['name'] as String?;
      } catch (_) {}
    }

    String? staffName;
    String? deviceLabel;
    final staffId = (sale['staff_id'] as String?)?.trim();
    final deviceId = (sale['device_id'] as String?)?.trim();
    if (staffId != null && staffId.isNotEmpty) {
      try {
        final staff = await client
            .from('staff_members')
            .select('name')
            .eq('id', staffId)
            .maybeSingle();
        staffName = (staff?['name'] as String?)?.trim();
      } catch (_) {}
    }
    if (deviceId != null && deviceId.isNotEmpty) {
      try {
        final label = await client
            .from('device_labels')
            .select('label')
            .eq('device_id', deviceId)
            .maybeSingle();
        deviceLabel = (label?['label'] as String?)?.trim();
      } catch (_) {}
    }
    final cashier = cashierNameForSale(
      staffId: staffId,
      members: [
        if (staffId != null &&
            staffId.isNotEmpty &&
            staffName != null &&
            staffName.isNotEmpty)
          (id: staffId, name: staffName),
      ],
      ownerLabel: l.staffRoleOwner,
      deviceLabel: deviceLabel,
    );

    return InvoiceData(
      shopName: (sf?['display_name'] as String?) ?? '',
      shopLogoUrl: sf?['logo_url'] as String?,
      shopPhone: sf?['phone'] as String?,
      shopAddress: sf?['address'] as String?,
      invoiceNo: sale['invoice_no'] as String,
      date: DateTime.parse(sale['finalized_at'] as String),
      customerName: (sale['customer_name'] as String?) ?? '',
      customerPhone: sale['customer_phone'] as String?,
      deliveryAddress: sale['delivery_address'] as String?,
      items: items
          .map((e) => (e as Map).cast<String, dynamic>())
          .map(
            (m) => InvoiceItemData(
              name: m['name_snapshot'] as String,
              qty: (m['qty'] as num).toInt(),
              unitPrice: (m['price_snapshot'] as num?)?.toInt() ?? 0,
              lineTotal: (m['line_total'] as num).toInt(),
            ),
          )
          .toList(),
      discount: (sale['discount'] as num?)?.toInt() ?? 0,
      paid: paid,
      changeDue: (sale['change_due'] as num?)?.toInt() ?? 0,
      paymentStatus: paymentStatus,
      paymentMethodCode: methodCode,
      paymentMethodCustomName: customName,
      cashier: cashier,
      currencySymbol: CurrencyDef.byCode(sf?['currency_code'] as String?).symbol,
      exponent: CurrencyDef.byCode(sf?['currency_code'] as String?).exponent,
    );
  }

  Future<void> _downloadPdf(InvoiceData data) async {
    setState(() => _downloading = true);
    try {
      final l = AppLocalizations.of(context);
      final bytes = await buildInvoicePdf(data, l);
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
              onAction: () => setState(() {
                _future = _load(l);
              }),
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
