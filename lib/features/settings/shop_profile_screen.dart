import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/currency_def.dart';
import '../../core/env.dart';
import '../../core/image_util.dart';
import '../../core/locale_controller.dart';
import '../../core/payment_method.dart';
import '../../core/phone_validator.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/repositories/settings_repository.dart';
import '../../l10n/app_localizations.dart';
import '../printing/printing_providers.dart';
import '../storefront/storefront_providers.dart'
    show storefrontRepositoryProvider, myStorefrontProvider;
import 'shop_profile_sync_repository.dart';

/// One editable payment-method row's controllers — a `List` of these backs
/// the dynamic add/remove UI, replacing the old fixed KBZPay/WavePay slots
/// so a shop outside Myanmar can name whatever it actually uses (PayPal,
/// PromptPay, bank transfer, ...).
class _PaymentMethodDraft {
  final label = TextEditingController();
  final accountName = TextEditingController();
  final accountNumber = TextEditingController();

  void dispose() {
    label.dispose();
    accountName.dispose();
    accountNumber.dispose();
  }
}

/// Edit the shop's receipt header (logo/name/address/phone/payment accounts)
/// and footer line. Backs [ShopProfile], which the receipt builder (printed +
/// shared invoices) reads — and is also the single edit point for the shared
/// fields on the shop's web Storefront (name/phone/address/logo/payment
/// accounts), best-effort mirrored on save via [storefrontRepositoryProvider]
/// so the owner never has to type the same thing twice. `StorefrontScreen`
/// only shows those fields read-only now, with its own settings (hours,
/// require-proof, enabled, share link, blocked customers) untouched.
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
  final List<_PaymentMethodDraft> _paymentMethods = [];
  String? _logoUrl;
  String _currencyCode = 'MMK';
  String? _loadedCurrencyCode;
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
    for (final d in _paymentMethods) {
      d.dispose();
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
    _currencyCode = p.currencyCode ?? 'MMK';
    _loadedCurrencyCode = _currencyCode;
    for (final m in p.paymentMethods ?? const <PaymentMethod>[]) {
      final d = _PaymentMethodDraft();
      d.label.text = m.label;
      d.accountName.text = m.accountName;
      d.accountNumber.text = m.accountNumber;
      _paymentMethods.add(d);
    }
    _loaded = true;
  }

  void _addPaymentMethod() =>
      setState(() => _paymentMethods.add(_PaymentMethodDraft()));

  void _removePaymentMethod(int i) =>
      setState(() => _paymentMethods.removeAt(i).dispose());

  List<PaymentMethod> _collectPaymentMethods() => _paymentMethods
      .map((d) => PaymentMethod(
            label: d.label.text.trim(),
            accountName: d.accountName.text.trim(),
            accountNumber: d.accountNumber.text.trim(),
          ))
      .where((m) => m.label.isNotEmpty || m.accountNumber.isNotEmpty)
      .toList();

  Future<void> _pickLogo() async {
    final res =
        await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = res?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    setState(() => _uploadingLogo = true);
    try {
      // Downscale before upload — phone photos are often several MB, and this
      // logo also gets embedded directly into the printed receipt.
      final c = await compressImage(file.bytes!,
          fallbackExt: (file.extension ?? 'jpg').toLowerCase());
      // Folder-scoped by the caller's own shop_id — see the matching
      // comment in product_edit_screen.dart's upload path.
      final shopId = ref.read(shopIdProvider);
      final path =
          '$shopId/shop-logo-${DateTime.now().millisecondsSinceEpoch}.${c.ext}';
      final storage = Supabase.instance.client.storage.from('product-images');
      await storage.uploadBinary(path, c.bytes,
          fileOptions: const FileOptions(upsert: true));
      final url = storage.getPublicUrl(path);
      // Saved immediately — the logo isn't part of the rest of the form's
      // "Save" step, same as the storefront logo picker.
      await ref
          .read(settingsRepositoryProvider)
          .setShopLogoUrl(ref.read(shopIdProvider), url);
      if (mounted) ref.invalidate(shopProfileProvider);
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
    final methods = _collectPaymentMethods();
    try {
      final shopId = ref.read(shopIdProvider);
      await ref.read(settingsRepositoryProvider).saveShopProfile(
            shopId,
            ShopProfile(
              name: _name.text.trim(),
              address: orNull(_address),
              phone: orNull(_phone),
              footer: orNull(_footer),
              paymentMethods: methods,
            ),
          );
      // Currency has its own setter (enforces the after-first-sale lock) —
      // only called when it actually changed, and its own try/catch so a
      // lock rejection surfaces its own message instead of the generic one
      // without blocking the rest of the profile, which already saved.
      final currencyChanged = _currencyCode != _loadedCurrencyCode;
      // Starts false, not "!currencyChanged" — this must only flip true when
      // a real currency change actually saved below, so the never-clobber
      // mirrors just past it stay null (untouched) on every ordinary
      // name/phone/address-only save, exactly as their own doc comments say.
      var currencySaved = false;
      if (currencyChanged) {
        try {
          await ref
              .read(settingsRepositoryProvider)
              .setShopCurrency(shopId, _currencyCode);
          currencySaved = true;
          _loadedCurrencyCode = _currencyCode;
        } catch (_) {
          // Locked (a sale exists) — revert the picker to what's actually
          // saved and let the shop know why, without failing the rest of
          // the profile save that already succeeded above.
          if (mounted) setState(() => _currencyCode = _loadedCurrencyCode!);
          messenger.showSnackBar(
              SnackBar(content: Text(l.shopCurrencyLockedHint)));
        }
      }
      // Mirrors name/phone/address into the synced ShopProfiles table so
      // the admin console can show them without a published Storefront —
      // best-effort: a sync failure here shouldn't block saving the
      // profile itself, which already succeeded locally above.
      try {
        await ref.read(shopProfileSyncRepositoryProvider).sync(
              shopId: shopId,
              name: _name.text.trim(),
              phone: orNull(_phone),
              address: orNull(_address),
              currencyCode: currencySaved ? _currencyCode : null,
            );
      } catch (_) {}
      // Same best-effort mirror, but into the web Storefront's own row —
      // only when one already exists (Premium + already published); if the
      // shop hasn't published yet, `StorefrontScreen`'s Publish button reads
      // straight from `shopProfileProvider` at that moment instead, so
      // there's nothing to push here yet.
      try {
        final storefront = await ref.read(storefrontRepositoryProvider).mine();
        if (storefront != null) {
          await ref.read(storefrontRepositoryProvider).updateProfile(
                displayName: _name.text.trim(),
                phone: orNull(_phone) ?? '',
                address: orNull(_address) ?? '',
                logoUrl: _logoUrl ?? '',
                paymentMethods: methods,
                currencyCode: currencySaved ? _currencyCode : null,
              );
        }
      } catch (_) {}
      // Receipts read this via a FutureProvider — refresh the cache.
      ref.invalidate(shopProfileProvider);
      ref.invalidate(myStorefrontProvider);
      messenger.showSnackBar(SnackBar(content: Text(l.shopProfileSaved)));
      navigator.pop();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text(l.commonUnexpectedError)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final profile = ref.watch(shopProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.settingsShop),
        actions: [_languageMenu(l)],
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetryView(
          message: l.commonUnexpectedError,
          onRetry: () => ref.invalidate(shopProfileProvider),
        ),
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
                _currencyField(l),
                _gap,
                _field(_footer, l.receiptFooter, lines: 2),
                const Divider(height: AppTheme.space6),
                SectionHeader(title: l.storefrontPaymentInfoTitle),
                Text(l.storefrontPaymentInfoHint,
                    style: Theme.of(context).textTheme.bodySmall),
                _gap,
                for (var i = 0; i < _paymentMethods.length; i++) ...[
                  _paymentMethodRow(l, i),
                  _gap,
                ],
                OutlinedButton.icon(
                  onPressed: _addPaymentMethod,
                  icon: const Icon(Icons.add),
                  label: Text(l.paymentMethodAdd),
                ),
                const SizedBox(height: AppTheme.space5),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving ? const ButtonSpinner() : const Icon(Icons.check),
                  label: Text(l.commonSave),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _currencyField(AppLocalizations l) {
    final allowedAsync = ref.watch(currencyChangeAllowedProvider);
    final allowed = allowedAsync.valueOrNull ?? true;
    return DropdownButtonFormField<String>(
      initialValue: _currencyCode,
      decoration: InputDecoration(
        labelText: l.shopCurrency,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.space4, vertical: AppTheme.space4),
        helperText: allowed ? null : l.shopCurrencyLockedHint,
        helperMaxLines: 2,
      ),
      items: [
        for (final c in CurrencyDef.all)
          DropdownMenuItem(value: c.code, child: Text('${c.code} (${c.symbol})')),
      ],
      onChanged: allowed
          ? (v) => setState(() => _currencyCode = v ?? _currencyCode)
          : null,
    );
  }

  Widget _paymentMethodRow(AppLocalizations l, int i) {
    final d = _paymentMethods[i];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: d.label,
                    decoration:
                        InputDecoration(labelText: l.paymentMethodLabel),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: l.paymentMethodRemove,
                  onPressed: () => _removePaymentMethod(i),
                ),
              ],
            ),
            _gap,
            TextFormField(
              controller: d.accountName,
              decoration:
                  InputDecoration(labelText: l.paymentMethodAccountName),
            ),
            _gap,
            TextFormField(
              controller: d.accountNumber,
              keyboardType: TextInputType.phone,
              decoration:
                  InputDecoration(labelText: l.paymentMethodAccountNumber),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logoField(AppLocalizations l) {
    return Center(
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: (_logoUrl ?? '').isEmpty
                ? const Icon(Icons.storefront, size: 40)
                : Image.network(_logoUrl!,
                    fit: BoxFit.cover,
                    cacheWidth: ProductThumb.cacheWidthFor(
                        96, MediaQuery.devicePixelRatioOf(context)),
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined)),
          ),
          const SizedBox(height: AppTheme.space2),
          TextButton.icon(
            onPressed: _uploadingLogo ? null : _pickLogo,
            icon: _uploadingLogo
                ? const ButtonSpinner(size: 14)
                : const Icon(Icons.add_a_photo_outlined, size: 18),
            label: Text(l.shopLogo),
          ),
        ],
      ),
    );
  }

  /// Top-right app bar language switcher — the owner asked for this to be
  /// the one place the language lives (Settings → Device's copy of the same
  /// control was removed). Device-global via [localeControllerProvider],
  /// applied immediately on selection — not part of the form's Save step.
  Widget _languageMenu(AppLocalizations l) {
    final locale = ref.watch(localeControllerProvider);
    final flag = locale == 'my' ? '🇲🇲' : '🇬🇧';
    final name = locale == 'my' ? l.languageMyanmar : l.languageEnglish;
    return PopupMenuButton<String>(
      initialValue: locale,
      tooltip: l.settingsLanguage,
      onSelected: (v) => ref.read(localeControllerProvider.notifier).set(v),
      itemBuilder: (context) => [
        PopupMenuItem(value: 'my', child: Text('🇲🇲  ${l.languageMyanmar}')),
        PopupMenuItem(value: 'en', child: Text('🇬🇧  ${l.languageEnglish}')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.space3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(flag, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: AppTheme.space1),
            Text(name, style: Theme.of(context).textTheme.labelLarge),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
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
