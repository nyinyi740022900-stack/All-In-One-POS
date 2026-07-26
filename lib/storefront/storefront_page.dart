import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/image_util.dart';
import '../features/invoices/invoice_capture.dart';
import '../features/invoices/invoice_view.dart';
import '../features/orders/myanmar_townships.dart';
import 'storefront_api.dart';
import 'storefront_download.dart';

final _money = NumberFormat('#,##0', 'en_US');
String _ks(int v) => '${_money.format(v)} Ks';

/// The public storefront for one shop, addressed by [slug]. Shows the catalog,
/// a cart, and a guest-checkout form that submits an order (no account needed).
class StorefrontPage extends StatefulWidget {
  const StorefrontPage({super.key, required this.slug});
  final String slug;

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

  void _add(StoreProduct p) => setState(() => _cart[p.id] = (_cart[p.id] ?? 0) + 1);
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
    return Scaffold(
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
                    child: Text('Checkout · $_count item(s) · ${_ks(_total)}'),
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
                  info.displayName ?? 'Shop',
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
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Phone number copied'),
                                duration: Duration(seconds: 1)));
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
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(_ks(product.price),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (qty == 0)
                      FilledButton.tonal(
                        onPressed: onAdd,
                        child: const Text('Add'),
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
                              onPressed: onAdd,
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
      );
      if (mounted) setState(() => _orderNo = no);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    if (_orderNo != null) return _confirmation(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Your details',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name *')),
            const SizedBox(height: 8),
            TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone')),
            const SizedBox(height: 8),
            TextField(
                controller: _address,
                maxLines: 2,
                decoration:
                    const InputDecoration(labelText: 'Delivery address')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _township,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Township'),
              items: [
                for (final t in myanmarTownships)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) => setState(() => _township = v),
            ),
            const SizedBox(height: 8),
            TextField(
                controller: _note,
                decoration: const InputDecoration(labelText: 'Note')),
            const SizedBox(height: 16),
            const Text('Payment', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'transfer',
                    label: Text('Bank transfer'),
                    icon: Icon(Icons.account_balance_outlined)),
                ButtonSegment(
                    value: 'cod',
                    label: Text('Cash on delivery'),
                    icon: Icon(Icons.local_shipping_outlined)),
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
                        const Text('Pay to:',
                            style: TextStyle(fontWeight: FontWeight.bold)),
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
                    ? 'Attach payment screenshot'
                    : 'Screenshot: $_proofName'),
              ),
            ] else
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              "You'll pay cash to the courier when your order arrives.")),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text('Total: ${_ks(widget.total)}',
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
                    : const Text('Place order'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InvoiceData get _invoiceData => InvoiceData(
        shopName: widget.info.displayName ?? 'Shop',
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
          for (final l in widget.lines)
            InvoiceItemData(
                name: l.name, qty: l.qty, lineTotal: l.price * l.qty),
        ],
      );

  Future<void> _saveInvoiceToPhotos(BuildContext context) async {
    setState(() => _downloading = true);
    try {
      final invoice = _invoiceData;
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

  Widget _confirmation(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 8),
            Text('Order placed!',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Order no: $_orderNo'),
            const SizedBox(height: 16),
            InvoiceView(data: _invoiceData),
            const SizedBox(height: 12),
            if (_paymentMethod == 'transfer' &&
                ((widget.info.payKpay ?? '').isNotEmpty ||
                    (widget.info.payWave ?? '').isNotEmpty)) ...[
              const Text('Transfer and send the screenshot to the shop:'),
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
              const Text("You'll pay cash to the courier on delivery."),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _downloading ? null : () => _saveInvoiceToPhotos(context),
                    icon: _downloading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.photo_library_outlined),
                    label: const Text('Save to Photos'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop('done'),
                    child: const Text('Done'),
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
    final label = (name ?? '').isEmpty ? number : '$name · $number';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text('$method: $label')),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            tooltip: 'Copy number',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: number));
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Number copied')));
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.storefront_outlined, size: 56),
          const SizedBox(height: 12),
          Text('Shop "$slug" not found or not published.'),
        ],
      ),
    );
  }
}
