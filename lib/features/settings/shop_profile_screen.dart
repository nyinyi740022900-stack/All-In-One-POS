import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/image_util.dart';
import '../../core/phone_validator.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/settings_repository.dart';
import '../../l10n/app_localizations.dart';
import '../printing/printing_providers.dart';

/// Edit the shop's receipt header (logo/name/address/phone) and footer line.
/// Backs [ShopProfile], which the receipt builder (printed + shared invoices)
/// reads.
class ShopProfileScreen extends ConsumerStatefulWidget {
  const ShopProfileScreen({super.key});

  @override
  ConsumerState<ShopProfileScreen> createState() => _ShopProfileScreenState();
}

class _ShopProfileScreenState extends ConsumerState<ShopProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _footer = TextEditingController();
  String? _logoUrl;
  bool _loaded = false;
  bool _saving = false;
  bool _uploadingLogo = false;

  @override
  void initState() {
    super.initState();
    // Live-updates the phone format hint below — a plain helperText, never
    // wired to `validator`, so an unusual (but possibly legitimate, e.g. a
    // landline) number never blocks Save.
    _phone.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _phone, _footer]) {
      c.dispose();
    }
    super.dispose();
  }

  void _hydrate(ShopProfile p) {
    if (_loaded) return;
    _name.text = p.name;
    _address.text = p.address ?? '';
    _phone.text = p.phone ?? '';
    _footer.text = p.footer ?? '';
    _logoUrl = p.logoUrl;
    _loaded = true;
  }

  Future<void> _pickLogo() async {
    final res =
        await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = res?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    setState(() => _uploadingLogo = true);
    try {
      // Downscale before upload — phone photos are often several MB, and this
      // logo also gets embedded directly into the printed receipt.
      final c = compressImage(file.bytes!,
          fallbackExt: (file.extension ?? 'jpg').toLowerCase());
      final path = 'shop-logo-${DateTime.now().millisecondsSinceEpoch}.${c.ext}';
      final storage = Supabase.instance.client.storage.from('product-images');
      await storage.uploadBinary(path, c.bytes,
          fileOptions: const FileOptions(upsert: true));
      final url = storage.getPublicUrl(path);
      // Saved immediately — the logo isn't part of the rest of the form's
      // "Save" step, same as the storefront logo picker.
      await ref.read(settingsRepositoryProvider).setShopLogoUrl(url);
      ref.invalidate(shopProfileProvider);
      if (mounted) setState(() => _logoUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).commonUnexpectedError)));
      }
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    String? orNull(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    try {
      await ref.read(settingsRepositoryProvider).saveShopProfile(ShopProfile(
            name: _name.text.trim(),
            address: orNull(_address),
            phone: orNull(_phone),
            footer: orNull(_footer),
          ));
      // Receipts read this via a FutureProvider — refresh the cache.
      ref.invalidate(shopProfileProvider);
      messenger.showSnackBar(SnackBar(content: Text(l.shopProfileSaved)));
      navigator.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final profile = ref.watch(shopProfileProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.settingsShop)),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.commonUnexpectedError)),
        data: (p) {
          _hydrate(p);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(AppTheme.space4),
              children: [
                Text(l.shopProfileHint,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: AppTheme.space4),
                if (Env.hasBackend) ...[
                  _logoField(l),
                  const SizedBox(height: AppTheme.space4),
                ],
                _field(_name, l.shopName,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? l.validationRequired
                        : null),
                _gap,
                _field(_phone, l.shopPhone, phone: true),
                _gap,
                _field(_address, l.shopAddress, lines: 2),
                _gap,
                _field(_footer, l.receiptFooter, lines: 2),
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
          );
        },
      ),
    );
  }

  Widget _logoField(AppLocalizations l) {
    return Row(
      children: [
        Container(
          width: 72,
          height: 72,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: (_logoUrl ?? '').isEmpty
              ? const Icon(Icons.storefront, size: 32)
              : Image.network(_logoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _uploadingLogo ? null : _pickLogo,
            icon: _uploadingLogo
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add_a_photo_outlined),
            label: Text(l.shopLogo),
          ),
        ),
      ],
    );
  }

  static const _gap = SizedBox(height: AppTheme.space3);

  Widget _field(TextEditingController c, String label,
      {int lines = 1, bool phone = false, String? Function(String?)? validator}) {
    final l = AppLocalizations.of(context);
    return TextFormField(
      controller: c,
      maxLines: lines,
      keyboardType: phone
          ? TextInputType.phone
          : (lines > 1 ? TextInputType.multiline : TextInputType.text),
      decoration: InputDecoration(
        labelText: label,
        // Extra vertical padding so tall Myanmar stacked glyphs aren't clipped.
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.space4, vertical: AppTheme.space4),
        helperText:
            phone && !looksLikeMyanmarPhone(c.text) ? l.phoneFormatHint : null,
        helperMaxLines: 2,
      ),
      validator: validator,
    );
  }
}
