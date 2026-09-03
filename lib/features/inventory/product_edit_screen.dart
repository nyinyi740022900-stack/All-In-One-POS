import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/image_util.dart';
import '../../core/input/thousands_formatter.dart';
import '../../core/layout.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/sync/sync_providers.dart';
import '../../domain/product_with_stock.dart';
import '../../l10n/app_localizations.dart';
import '../printing/printing_providers.dart';
import '../sell/barcode_scanner_screen.dart';
import '../sell/hardware_scanner_listener.dart';
import 'inventory_providers.dart';
import 'stock_history_screen.dart';

/// Add or edit a product. Pass [existing] to edit; null to create.
class ProductEditScreen extends ConsumerStatefulWidget {
  const ProductEditScreen({super.key, this.existing});

  final ProductWithStock? existing;

  @override
  ConsumerState<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends ConsumerState<ProductEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _barcode;
  late final TextEditingController _salePrice;
  late final TextEditingController _costPrice;
  late final TextEditingController _wholesalePrice;
  late final TextEditingController _vipPrice;
  late final TextEditingController _onlineStockLimit;
  late final TextEditingController _quantity;
  // The quantity field is seeded once from the stock level at the moment
  // this screen opened. If the owner leaves it untouched while editing
  // something else (price, sellOnline, ...), the field's text goes stale
  // against any stock activity (a sale, a restock, another edit) that
  // happens while the screen is open — submitting it anyway would silently
  // overwrite the real current stock and fabricate a bogus stock movement.
  // Comparing against this snapshot at save time lets us tell "genuinely
  // untouched" apart from "owner typed a new number" and skip the write
  // only in the former case.
  late final String _initialQuantityText;
  late final TextEditingController _reorder;
  String? _categoryId;
  String? _imageUrl;
  late bool _sellOnline;
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final exponent = ref.read(shopCurrencyProvider).exponent;
    _categoryId = e?.product.categoryId;
    _imageUrl = e?.product.imageUrl;
    _sellOnline = e?.product.sellOnline ?? true;
    _name = TextEditingController(text: e?.product.name ?? '');
    _sku = TextEditingController(text: e?.product.sku ?? '');
    _barcode = TextEditingController(text: e?.product.barcode ?? '');
    _salePrice = TextEditingController(
      text: e == null
          ? ''
          : formatDecimalMinorUnits(e.product.salePrice, exponent: exponent),
    );
    _costPrice = TextEditingController(
      text: e == null
          ? ''
          : formatDecimalMinorUnits(e.product.costPrice, exponent: exponent),
    );
    _wholesalePrice = TextEditingController(
      text: e?.product.wholesalePrice == null
          ? ''
          : formatDecimalMinorUnits(e!.product.wholesalePrice!,
              exponent: exponent),
    );
    _vipPrice = TextEditingController(
      text: e?.product.vipPrice == null
          ? ''
          : formatDecimalMinorUnits(e!.product.vipPrice!, exponent: exponent),
    );
    _onlineStockLimit = TextEditingController(
      text: e?.product.onlineStockLimit == null
          ? ''
          : '${e!.product.onlineStockLimit}',
    );
    _quantity = TextEditingController(text: e == null ? '' : '${e.quantity}');
    _initialQuantityText = _quantity.text;
    _reorder = TextEditingController(
      text: e == null ? '' : '${e.reorderLevel}',
    );
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _sku,
      _barcode,
      _salePrice,
      _costPrice,
      _wholesalePrice,
      _vipPrice,
      _onlineStockLimit,
      _quantity,
      _reorder,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int _int(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
  int? _intOrNull(TextEditingController c) =>
      c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());
  int _money(TextEditingController c, int exponent) =>
      parseDecimalMinorUnits(c.text.trim(), exponent: exponent);
  int? _moneyOrNull(TextEditingController c, int exponent) => c.text.trim().isEmpty
      ? null
      : parseDecimalMinorUnits(c.text.trim(), exponent: exponent);

  Future<void> _pickImage() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = res?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    setState(() => _uploading = true);
    try {
      final c = await compressImage(
        Uint8List.fromList(file.bytes!),
        fallbackExt: (file.extension ?? 'jpg').toLowerCase(),
      );
      // Folder-scoped by the caller's own shop_id — the bucket's write
      // policy requires it, so a shop can only ever create/overwrite
      // objects under its own folder, never another shop's.
      final shopId = ref.read(shopIdProvider);
      final path = '$shopId/p-${DateTime.now().millisecondsSinceEpoch}.${c.ext}';
      final storage = Supabase.instance.client.storage.from('product-images');
      await storage.uploadBinary(
        path,
        c.bytes,
        fileOptions: const FileOptions(upsert: true),
      );
      final url = storage.getPublicUrl(path);
      if (mounted) setState(() => _imageUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).commonUnexpectedError),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _confirmDelete() async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.deleteConfirmTitle),
        content: Text(
          '${widget.existing!.product.name}\n\n${l.productDeleteConfirmBody}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            style: AppTheme.dangerFilledButtonStyle(ctx),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref
          .read(inventoryRepositoryProvider)
          .deleteProduct(widget.existing!.product.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).commonUnexpectedError),
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final exponent = ref.read(shopCurrencyProvider).exponent;
      // Only resubmit quantity as a stock-level write when it's a brand-new
      // product (setting opening stock, no prior state to conflict with) or
      // the owner actually changed the field — see _initialQuantityText.
      // Otherwise pass null so upsertProduct leaves the current stock alone,
      // however it's changed since this screen opened.
      final quantityTouched = widget.existing == null ||
          _quantity.text.trim() != _initialQuantityText.trim();
      await ref
          .read(inventoryRepositoryProvider)
          .upsertProduct(
            id: widget.existing?.product.id,
            name: _name.text.trim(),
            sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
            barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
            categoryId: _categoryId,
            salePrice: _money(_salePrice, exponent),
            costPrice: _money(_costPrice, exponent),
            wholesalePrice: _moneyOrNull(_wholesalePrice, exponent),
            vipPrice: _moneyOrNull(_vipPrice, exponent),
            onlineStockLimit: _intOrNull(_onlineStockLimit),
            sellOnline: _sellOnline,
            quantity: quantityTouched ? _int(_quantity) : null,
            reorderLevel: _int(_reorder),
            imageUrl: _imageUrl,
          );
      // Best-effort, not awaited: a product edit can change what the public
      // web storefront shows (price, sellOnline, stock cap) and the owner
      // reasonably expects that to reach it promptly rather than sit in the
      // outbox until the next periodic sync (up to 5 minutes) — a failure
      // here doesn't block the save, which already succeeded locally above.
      unawaited(ref.read(syncControllerProvider.notifier).sync());
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).commonUnexpectedError),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isEdit = widget.existing != null;
    final trackStock = ref.watch(trackStockProvider).valueOrNull ?? true;
    final currencyExponent = ref.watch(shopCurrencyProvider).exponent;
    return HardwareScannerListener(
      onScan: (code) => setState(() => _barcode.text = code.trim()),
      child: Scaffold(
        appBar: AppBar(
          title: Text(isEdit ? l.inventoryEditProduct : l.inventoryAddProduct),
          actions: [
            if (isEdit)
              IconButton(
                tooltip: l.commonDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: _confirmDelete,
              ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ContentWidth(
            child: ListView(
              padding: const EdgeInsets.all(AppTheme.space4),
              children: [
                // Grouped, not one flat 12-field column. The old form ran
                // photo ➜ name ➜ prices ➜ an unanchored hint paragraph ➜ more
                // prices ➜ another hint ➜ stock ➜ barcode ➜ SKU ➜ category as
                // a single undifferentiated stack, so the two explanatory
                // paragraphs floated between fields with nothing to attach
                // themselves to. Each card is now one idea, and each hint sits
                // inside the card it explains.
                _group([
                  if (Env.hasBackend) _photoField(l),
                  _field(
                    _name,
                    l.productName,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l.validationRequired
                        : null,
                  ),
                  _categoryDropdown(l),
                ]),
                _group([
                  _field(
                    _salePrice,
                    l.productPrice,
                    money: true,
                    moneyExponent: currencyExponent,
                  ),
                  _field(
                    _costPrice,
                    l.productCost,
                    money: true,
                    moneyExponent: currencyExponent,
                  ),
                  Text(
                    l.productTierPricesHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  _field(
                    _wholesalePrice,
                    l.productWholesalePrice,
                    money: true,
                    moneyExponent: currencyExponent,
                  ),
                  _field(
                    _vipPrice,
                    l.productVipPrice,
                    money: true,
                    moneyExponent: currencyExponent,
                  ),
                ]),
                _group([
                  if (trackStock) ...[
                    _field(
                      _quantity,
                      l.productQuantity,
                      number: true,
                      // Only for an existing product — a new one's quantity
                      // IS the starting stock, no ambiguity to flag. Editing
                      // an existing product's count here silently overwrites
                      // it with no audit trail, unlike Adjust Stock.
                      helperText: isEdit ? l.productQuantityEditHint : null,
                    ),
                    _field(_reorder, l.productReorderLevel, number: true),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.productSellOnline),
                    subtitle: Text(l.productSellOnlineHint),
                    value: _sellOnline,
                    onChanged: (v) => setState(() => _sellOnline = v),
                  ),
                  Text(
                    l.productOnlineStockLimitHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  _field(
                    _onlineStockLimit,
                    l.productOnlineStockLimit,
                    number: true,
                  ),
                  if (trackStock && isEdit)
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => StockHistoryScreen(
                            productId: widget.existing!.product.id,
                            productName: widget.existing!.product.name,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.history),
                      label: Text(l.productViewStockHistory),
                    ),
                ]),
                _group([
                  _field(
                    _barcode,
                    l.productBarcode,
                    number: true,
                    // A real EAN-13 barcode is 13 digits; the shared 9-digit
                    // cap below exists for *money* fields and was silently
                    // truncating anything typed in by hand here.
                    maxLength: 20,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: l.scanBarcode,
                      onPressed: _scanBarcode,
                    ),
                  ),
                  _field(_sku, l.productSku),
                ]),
              ],
            ),
          ),
        ),
        // Docked, like the checkout sheet's confirm bar: this form is a dozen
        // fields long in English and longer in Myanmar, and the primary action
        // used to sit at the bottom of that scroll — reachable only after
        // scrolling past everything, including on the tall tablet layout where
        // the whole form fits and the button still hid below the fold.
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: AppTheme.dockedBarShadow(Theme.of(context).brightness),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.space3),
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(l.commonSave),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _gap = SizedBox(height: AppTheme.space3);

  /// One card = one group of related fields, evenly spaced.
  Widget _group(List<Widget> fields) {
    if (fields.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.space3),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < fields.length; i++) ...[
              if (i > 0) _gap,
              fields[i],
            ],
          ],
        ),
      ),
    );
  }

  /// The editable photo slot.
  ///
  /// Deliberately **not** [ProductThumb]: that widget's whole contract is
  /// that a missing photo is a normal, designed state (it renders an initials
  /// plate and never says "no image"), which is right in a list and wrong in
  /// the one place whose job is to tell you whether this product has a photo
  /// and let you change it. So it keeps an explicit empty state — but the
  /// preview is now the tap target too, instead of a dead 72pt square next to
  /// the only button that did anything.
  Widget _photoField(AppLocalizations l) {
    final scheme = Theme.of(context).colorScheme;
    final hasImage = (_imageUrl ?? '').isEmpty == false;
    return Row(
      children: [
        InkWell(
          onTap: _uploading ? null : _pickImage,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: Container(
            width: 72,
            height: 72,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: !hasImage
                ? Icon(Icons.image_outlined, color: scheme.onSurfaceVariant)
                : Image.network(
                    _imageUrl!,
                    fit: BoxFit.cover,
                    cacheWidth: ProductThumb.cacheWidthFor(
                        72, MediaQuery.devicePixelRatioOf(context)),
                    errorBuilder: (_, _, _) => Icon(
                      Icons.broken_image_outlined,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: AppTheme.space3),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _uploading ? null : _pickImage,
            icon: _uploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_a_photo_outlined),
            label: Text(l.productPhoto),
          ),
        ),
      ],
    );
  }

  Widget _categoryDropdown(AppLocalizations l) {
    final categories =
        ref.watch(categoriesStreamProvider).valueOrNull ?? const [];
    final ids = categories.map((c) => c.id).toSet();
    // Guard against a value pointing at a deleted category.
    final value = (_categoryId != null && ids.contains(_categoryId))
        ? _categoryId
        : null;
    return DropdownButtonFormField<String?>(
      initialValue: value,
      decoration: InputDecoration(labelText: l.productCategory),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(l.categoryNone)),
        for (final c in categories)
          DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
      ],
      onChanged: (v) => setState(() => _categoryId = v),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool number = false,
    bool money = false,
    int moneyExponent = 0,
    Widget? suffixIcon,
    int? maxLength,
    String? Function(String?)? validator,
    String? helperText,
  }) {
    return TextFormField(
      controller: c,
      // Extra vertical padding so tall Myanmar stacked glyphs aren't clipped.
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: suffixIcon,
        helperText: helperText,
        helperMaxLines: 3,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTheme.space4,
          vertical: AppTheme.space4,
        ),
      ),
      keyboardType: money
          ? TextInputType.numberWithOptions(decimal: moneyExponent > 0)
          : (number ? TextInputType.number : TextInputType.text),
      // Every field here is followed by another one — hand the keyboard a
      // "next" key instead of a newline it can't use.
      textInputAction: TextInputAction.next,
      // 9 digits comfortably covers any real kyat price/quantity while
      // guarding against a fat-fingered huge number losing precision on the
      // admin web (dart2js) build, where numbers are JS doubles. Fields that
      // are numeric but aren't money (barcodes) pass their own [maxLength].
      // A money field uses the exponent-aware formatter so a THB/USD shop
      // can type a decimal point; for exponent 0 (MMK/JPY) it behaves
      // exactly like the plain digits-only formatter below.
      inputFormatters: money
          ? [
              DecimalMoneyInputFormatter(exponent: moneyExponent),
              LengthLimitingTextInputFormatter(maxLength ?? 12),
            ]
          : (number
                ? [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(maxLength ?? 9),
                  ]
                : null),
      validator: validator,
    );
  }

  Future<void> _scanBarcode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (code == null || !mounted) return;
    setState(() => _barcode.text = code);
  }
}
