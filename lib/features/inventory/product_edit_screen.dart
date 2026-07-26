import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/image_util.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/product_with_stock.dart';
import '../../l10n/app_localizations.dart';
import '../printing/printing_providers.dart';
import '../sell/barcode_scanner_screen.dart';
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
  late final TextEditingController _quantity;
  late final TextEditingController _reorder;
  String? _categoryId;
  String? _imageUrl;
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _categoryId = e?.product.categoryId;
    _imageUrl = e?.product.imageUrl;
    _name = TextEditingController(text: e?.product.name ?? '');
    _sku = TextEditingController(text: e?.product.sku ?? '');
    _barcode = TextEditingController(text: e?.product.barcode ?? '');
    _salePrice =
        TextEditingController(text: e == null ? '' : '${e.product.salePrice}');
    _costPrice =
        TextEditingController(text: e == null ? '' : '${e.product.costPrice}');
    _wholesalePrice = TextEditingController(
        text: e?.product.wholesalePrice == null
            ? ''
            : '${e!.product.wholesalePrice}');
    _vipPrice = TextEditingController(
        text: e?.product.vipPrice == null ? '' : '${e!.product.vipPrice}');
    _quantity = TextEditingController(text: e == null ? '' : '${e.quantity}');
    _reorder = TextEditingController(text: e == null ? '' : '${e.reorderLevel}');
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
      _quantity,
      _reorder
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int _int(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
  int? _intOrNull(TextEditingController c) =>
      c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());

  Future<void> _pickImage() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = res?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    setState(() => _uploading = true);
    try {
      final c = compressImage(Uint8List.fromList(file.bytes!),
          fallbackExt: (file.extension ?? 'jpg').toLowerCase());
      final path = 'p-${DateTime.now().millisecondsSinceEpoch}.${c.ext}';
      final storage = Supabase.instance.client.storage.from('product-images');
      await storage.uploadBinary(path, c.bytes,
          fileOptions: const FileOptions(upsert: true));
      final url = storage.getPublicUrl(path);
      if (mounted) setState(() => _imageUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(inventoryRepositoryProvider).upsertProduct(
            id: widget.existing?.product.id,
            name: _name.text.trim(),
            sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
            barcode:
                _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
            categoryId: _categoryId,
            salePrice: _int(_salePrice),
            costPrice: _int(_costPrice),
            wholesalePrice: _intOrNull(_wholesalePrice),
            vipPrice: _intOrNull(_vipPrice),
            quantity: _int(_quantity),
            reorderLevel: _int(_reorder),
            imageUrl: _imageUrl,
          );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isEdit = widget.existing != null;
    final trackStock = ref.watch(trackStockProvider).valueOrNull ?? true;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? l.inventoryEditProduct : l.inventoryAddProduct),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.space4),
          children: [
            if (Env.hasBackend) ...[
              _photoField(l),
              _gap,
            ],
            _field(_name, l.productName,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l.validationRequired : null),
            _gap,
            _field(_salePrice, l.productPrice, number: true),
            _gap,
            _field(_costPrice, l.productCost, number: true),
            _gap,
            Text(l.productTierPricesHint,
                style: Theme.of(context).textTheme.bodySmall),
            _gap,
            _field(_wholesalePrice, l.productWholesalePrice, number: true),
            _gap,
            _field(_vipPrice, l.productVipPrice, number: true),
            _gap,
            if (trackStock) ...[
              _field(_quantity, l.productQuantity, number: true),
              _gap,
              _field(_reorder, l.productReorderLevel, number: true),
              _gap,
              if (isEdit) ...[
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => StockHistoryScreen(
                      productId: widget.existing!.product.id,
                      productName: widget.existing!.product.name,
                    ),
                  )),
                  icon: const Icon(Icons.history),
                  label: Text(l.productViewStockHistory),
                ),
                _gap,
              ],
            ],
            _field(_barcode, l.productBarcode,
                number: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: l.scanBarcode,
                  onPressed: _scanBarcode,
                )),
            _gap,
            _field(_sku, l.productSku),
            _gap,
            _categoryDropdown(l),
            const SizedBox(height: AppTheme.space5),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(l.commonSave),
            ),
          ],
        ),
      ),
    );
  }

  static const _gap = SizedBox(height: AppTheme.space3);

  Widget _photoField(AppLocalizations l) {
    return Row(
      children: [
        Container(
          width: 72,
          height: 72,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: (_imageUrl ?? '').isEmpty
              ? const Icon(Icons.image_outlined)
              : Image.network(_imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _uploading ? null : _pickImage,
            icon: _uploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add_a_photo_outlined),
            label: Text(l.productPhoto),
          ),
        ),
      ],
    );
  }

  Widget _categoryDropdown(AppLocalizations l) {
    final categories = ref.watch(categoriesStreamProvider).valueOrNull ?? const [];
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

  Widget _field(TextEditingController c, String label,
      {bool number = false,
      Widget? suffixIcon,
      String? Function(String?)? validator}) {
    return TextFormField(
      controller: c,
      // Extra vertical padding so tall Myanmar stacked glyphs aren't clipped.
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.space4, vertical: AppTheme.space4),
      ),
      keyboardType: number ? TextInputType.number : TextInputType.text,
      inputFormatters:
          number ? [FilteringTextInputFormatter.digitsOnly] : null,
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
