import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/image_util.dart';
import '../features/invoices/invoice_capture.dart';
import '../features/invoices/invoice_view.dart';
import '../features/orders/myanmar_townships.dart';
import '../l10n/app_localizations.dart';
import 'storefront_api.dart';
import 'storefront_download.dart';

final _money = NumberFormat('#,##0', 'en_US');
String _ks(AppLocalizations l, int v) => '${_money.format(v)} ${l.currencySymbol}';

/// Slim transparent app bar with just a language toggle — the storefront has
/// no user account/settings to persist a language choice, so it's plain
/// in-memory state on [StorefrontApp], threaded down to whichever screen is
/// showing. Shows the *other* language's own name (matches the main app's
/// `languageEnglish`/`languageMyanmar` convention) so it reads correctly
/// regardless of which language the visitor currently has active.
class StorefrontLocaleBar extends StatelessWidget implements PreferredSizeWidget {
  const StorefrontLocaleBar({super.key, required this.locale, required this.onToggle});
  final Locale locale;
  final VoidCallback onToggle;

  @override
  Size get preferredSize => const Size.fromHeight(40);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 40,
      automaticallyImplyLeading: false,
      actions: [
        TextButton.icon(
          onPressed: onToggle,
          icon: const Icon(Icons.language, size: 16),
          label: Text(locale.languageCode == 'my' ? l.languageEnglish : l.languageMyanmar),
        ),
      ],
    );
  }
}

/// The public storefront for one shop, addressed by [slug]. Shows the catalog,
/// a cart, and a guest-checkout form that submits an order (no account needed).
class StorefrontPage extends StatefulWidget {
  const StorefrontPage({
    super.key,
    required this.slug,
    required this.locale,
    required this.onToggleLocale,
  });
  final String slug;
  final Locale locale;
  final VoidCallback onToggleLocale;

  @override
  State<StorefrontPage> createState() => _StorefrontPageState();
}

class _StorefrontPageState extends State<StorefrontPage> {
  final _api = StorefrontApi();
  late Future<Catalog> _future;
  final Map<String, int> _cart = {}; // productId -> qty
  late Map<String, StoreProduct> _byId = {};

  @override
  void initState() {
    super.initState();
    _future = _api.fetchCatalog(widget.slug);
  }

  int get _total => _cart.entries
      .fold(0, (s, e) => s + (_byId[e.key]?.price ?? 0) * e.value);
  int get _count => _cart.values.fold(0, (s, q) => s + q);

  void _add(StoreProduct p) => setState(() {
        final next = (_cart[p.id] ?? 0) + 1;
        if (p.onlineAvailable != null && next > p.onlineAvailable!) return;
        _cart[p.id] = next;
      });
  void _sub(StoreProduct p) => setState(() {
        final q = (_cart[p.id] ?? 0) - 1;
        if (q <= 0) {
          _cart.remove(p.id);
        } else {
          _cart[p.id] = q;
        }
      });

  Future<void> _checkout(Catalog catalog) async {
    final lines = _cart.entries
        .map((e) => OrderLine(
            e.key, _byId[e.key]!.name, _byId[e.key]!.price, e.value))
        .toList();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CheckoutSheet(
        slug: widget.slug,
        api: _api,
        info: catalog.info,
        lines: lines,
        total: _total,
      ),
    );
    if (result != null && mounted) {
      setState(() => _cart.clear());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: StorefrontLocaleBar(
          locale: widget.locale, onToggle: widget.onToggleLocale),
      body: FutureBuilder<Catalog>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _NotFound(slug: widget.slug);
          }
          final catalog = snap.data!;
          _byId = {for (final p in catalog.products) p.id: p};
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _ShopBanner(info: catalog.info)),
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final p = catalog.products[i];
                      return _ProductCard(
                        product: p,
                        qty: _cart[p.id] ?? 0,
                        onAdd: () => _add(p),
                        onSub: () => _sub(p),
                      );
                    },
                    childCount: catalog.products.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: _count == 0
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: () => _future.then((c) => _checkout(c)),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(l.storefrontCheckoutBar(_count, _ks(l, _total))),
                  ),
                ),
              ),
            ),
    );
  }
}

/// Shop banner: logo, name, phone (tap to copy), address.
class _ShopBanner extends StatelessWidget {
  const _ShopBanner({required this.info});
  final StoreInfo info;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.surface],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: scheme.surface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: (info.logoUrl ?? '').isEmpty
                    ? Icon(Icons.storefront, color: scheme.primary, size: 30)
                    : Image.network(
                        info.logoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            Icon(Icons.storefront, color: scheme.primary),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  info.displayName ?? l.storefrontShopFallbackName,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if ((info.phone ?? '').isNotEmpty || (info.address ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  if ((info.phone ?? '').isNotEmpty)
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: info.phone!));
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(l.storefrontPhoneCopied),
                            duration: const Duration(seconds: 1)));
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.call_outlined,
                              size: 16, color: scheme.primary),
                          const SizedBox(width: 6),
                          Text(info.phone!),
                        ],
                      ),
                    ),
                  if ((info.address ?? '').isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_on_outlined,
                            size: 16, color: scheme.primary),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: Text(info.address!,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.qty,
    required this.onAdd,
    required this.onSub,
  });
  final StoreProduct product;
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onSub;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final soldOut = product.onlineAvailable == 0;
    final atCap =
        product.onlineAvailable != null && qty >= product.onlineAvailable!;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: (product.imageUrl ?? '').isEmpty
                  ? Icon(Icons.image_outlined,
                      color: Theme.of(context).colorScheme.outlineVariant)
                  : Image.network(
                      product.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (product.onlineAvailable != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    soldOut
                        ? l.storefrontSoldOut
                        : l.storefrontOnlineLeft(product.onlineAvailable!),
                    style: TextStyle(
                        fontSize: 11,
                        color: soldOut
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.outline),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(_ks(l, product.price),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (qty == 0)
                      FilledButton.tonal(
                        onPressed: soldOut ? null : onAdd,
                        child: Text(l.storefrontAdd),
                      )
                    else
                      Row(
                        children: [
                          IconButton.filledTonal(
                              onPressed: onSub,
                              icon: const Icon(Icons.remove, size: 18)),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 6),
                            child: Text('$qty',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ),
                          IconButton.filledTonal(
                              onPressed: atCap ? null : onAdd,
                              icon: const Icon(Icons.add, size: 18)),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet({
    required this.slug,
    required this.api,
    required this.info,
    required this.lines,
    required this.total,
  });
  final String slug;
  final StorefrontApi api;
  final StoreInfo info;
  final List<OrderLine> lines;
  final int total;

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _note = TextEditingController();
  // Honeypot: real customers never see or fill this field; a scripted bot
  // that blindly fills every input on the form will. Checked server-side.
  final _hp = TextEditingController();
  String? _township;
  String _paymentMethod = 'transfer';
  bool _submitting = false;
  String? _orderNo;
  bool _downloading = false;
  List<int>? _proofBytes;
  String? _proofExt;
  String? _proofName;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _note.dispose();
    _hp.dispose();
    super.dispose();
  }

  Future<void> _pickProof() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = res?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    // Shrink before upload — phone screenshots are often several MB.
    final c = compressImage(Uint8List.fromList(file.bytes!),
        fallbackExt: (file.extension ?? 'jpg').toLowerCase());
    setState(() {
      _proofBytes = c.bytes;
      _proofExt = c.ext;
      _proofName = file.name;
    });
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      String? proofPath;
      if (_paymentMethod == 'transfer' && _proofBytes != null) {
        proofPath = await widget.api
            .uploadPaymentProof(_proofBytes!, _proofExt ?? 'jpg');
      }
      final no = await widget.api.submitOrder(
        slug: widget.slug,
        customerName: _name.text.trim(),
        phone: _phone.text.trim(),
        address: _address.text.trim(),
        township: _township,
        note: _note.text.trim(),
        paymentMethod: _paymentMethod,
        paymentProofPath: _paymentMethod == 'transfer' ? proofPath : null,
        lines: widget.lines,
        hp: _hp.text,
      );
      if (mounted) setState(() => _orderNo = no);
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        final message = '$e'.contains('rate_limited')
            ? l.storefrontRateLimited
            : '$e'.contains('blocked')
                ? l.storefrontBlocked
                : '$e'.contains('out_of_stock')
                    ? l.storefrontOutOfStock
                    : '$e';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    if (_orderNo != null) return _confirmation(context, l);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.storefrontYourDetails,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            // Honeypot — kept out of the visible layout entirely (zero size,
            // not just hidden) so no real customer can tab/scroll into it.
            Offstage(
              child: TextField(controller: _hp, autofocus: false),
            ),
            TextField(
                controller: _name,
                decoration:
                    InputDecoration(labelText: l.storefrontNameRequired)),
            const SizedBox(height: 8),
            TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: l.shopPhone)),
            const SizedBox(height: 8),
            TextField(
                controller: _address,
                maxLines: 2,
                decoration:
                    InputDecoration(labelText: l.orderDeliveryAddress)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _township,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.deliveryTownship),
              items: [
                for (final t in myanmarTownships)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) => setState(() => _township = v),
            ),
            const SizedBox(height: 8),
            TextField(
                controller: _note,
                decoration: InputDecoration(labelText: l.orderNote)),
            const SizedBox(height: 16),
            Text(l.storefrontPayment,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                    value: 'transfer',
                    label: Text(l.storefrontBankTransfer),
                    icon: const Icon(Icons.account_balance_outlined)),
                ButtonSegment(
                    value: 'cod',
                    label: Text(l.storefrontCashOnDelivery),
                    icon: const Icon(Icons.local_shipping_outlined)),
              ],
              selected: {_paymentMethod},
              onSelectionChanged: (s) =>
                  setState(() => _paymentMethod = s.first),
            ),
            const SizedBox(height: 12),
            if (_paymentMethod == 'transfer') ...[
              if ((widget.info.payKpay ?? '').isNotEmpty ||
                  (widget.info.payWave ?? '').isNotEmpty) ...[
                Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.storefrontPayTo,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        if ((widget.info.payKpay ?? '').isNotEmpty)
                          _PayAccountRow(
                            method: 'KBZPay',
                            name: widget.info.payKpayName,
                            number: widget.info.payKpay!,
                          ),
                        if ((widget.info.payWave ?? '').isNotEmpty)
                          _PayAccountRow(
                            method: 'WavePay',
                            name: widget.info.payWaveName,
                            number: widget.info.payWave!,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: _pickProof,
                icon: const Icon(Icons.upload_file),
                label: Text(_proofName == null
                    ? l.storefrontAttachProof
                    : l.storefrontProofAttached(_proofName!)),
              ),
            ] else
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(l.storefrontCodNoticeBeforeOrder)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(l.storefrontTotal(_ks(l, widget.total)),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l.storefrontPlaceOrder),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InvoiceData _invoiceData(AppLocalizations l) => InvoiceData(
        shopName: widget.info.displayName ?? l.storefrontShopFallbackName,
        shopLogoUrl: widget.info.logoUrl,
        shopPhone: widget.info.phone,
        shopAddress: widget.info.address,
        invoiceNo: _orderNo ?? '',
        date: DateTime.now(),
        customerName: _name.text.trim(),
        customerPhone:
            _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        deliveryAddress:
            _address.text.trim().isEmpty ? null : _address.text.trim(),
        township: _township,
        items: [
          for (final line in widget.lines)
            InvoiceItemData(
                name: line.name, qty: line.qty, lineTotal: line.price * line.qty),
        ],
      );

  Future<void> _saveInvoiceToPhotos(BuildContext context, AppLocalizations l) async {
    setState(() => _downloading = true);
    try {
      final invoice = _invoiceData(l);
      if ((invoice.shopLogoUrl ?? '').isNotEmpty) {
        try {
          await precacheImage(NetworkImage(invoice.shopLogoUrl!), context);
        } catch (_) {}
      }
      if (!context.mounted) return;
      final bytes =
          await captureWidgetAsPng(context, InvoiceView(data: invoice));
      await saveImageToPhotos(bytes, 'invoice-${invoice.invoiceNo}.png');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Widget _confirmation(BuildContext context, AppLocalizations l) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 8),
            Text(l.storefrontOrderPlaced,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(l.storefrontOrderNo(_orderNo!)),
            const SizedBox(height: 16),
            InvoiceView(data: _invoiceData(l)),
            const SizedBox(height: 12),
            if (_paymentMethod == 'transfer' &&
                ((widget.info.payKpay ?? '').isNotEmpty ||
                    (widget.info.payWave ?? '').isNotEmpty)) ...[
              Text(l.storefrontTransferInstructions),
              const SizedBox(height: 8),
              if ((widget.info.payKpay ?? '').isNotEmpty)
                _PayAccountRow(
                  method: 'KBZPay',
                  name: widget.info.payKpayName,
                  number: widget.info.payKpay!,
                ),
              if ((widget.info.payWave ?? '').isNotEmpty)
                _PayAccountRow(
                  method: 'WavePay',
                  name: widget.info.payWaveName,
                  number: widget.info.payWave!,
                ),
              const SizedBox(height: 16),
            ] else if (_paymentMethod == 'cod') ...[
              Text(l.storefrontCodNoticeAfterOrder),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _downloading
                        ? null
                        : () => _saveInvoiceToPhotos(context, l),
                    icon: _downloading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.photo_library_outlined),
                    label: Text(l.storefrontSaveToPhotos),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop('done'),
                    child: Text(l.storefrontDone),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One payment account line ("KBZPay: Name · 09xxxxxxxx") with a copy button
/// for the number, so the customer doesn't have to retype it by hand into
/// their banking app.
class _PayAccountRow extends StatelessWidget {
  const _PayAccountRow({required this.method, this.name, required this.number});
  final String method;
  final String? name;
  final String number;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final label = (name ?? '').isEmpty ? number : '$name · $number';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text('$method: $label')),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            tooltip: l.storefrontCopyNumber,
            visualDensity: VisualDensity.compact,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: number));
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l.storefrontNumberCopied)));
            },
          ),
        ],
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.storefront_outlined, size: 56),
          const SizedBox(height: 12),
          Text(l.storefrontNotFound(slug)),
        ],
      ),
    );
  }
}
