import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/currency_def.dart';
import '../core/image_util.dart';
import '../core/money.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/app_widgets.dart';
import '../features/invoices/invoice_capture.dart';
import '../features/invoices/invoice_view.dart';
import '../features/storefront/storefront_repository.dart';
import '../features/support/viber_launch.dart';
import '../l10n/app_localizations.dart';
import 'storefront_api.dart';
import 'storefront_download.dart';
import 'storefront_seo.dart';

String _ks(CurrencyDef currency, String locale, int v) =>
    Money(v).withCurrency(currency, locale);

/// Last-resort classification for `_submit`'s catch block, for any backend
/// error code (or client-side failure) not already special-cased above —
/// e.g. `bad_request`/`server_error`/`invalid_quantity`/`bad_action` from
/// `supabase/functions/storefront/index.ts`, or a network drop. Without
/// this, an unrecognized code fell through to the raw `Exception: ...`
/// string instead of a real sentence.
String _submitFallbackMessage(AppLocalizations l, String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('failed to fetch') ||
      lower.contains('network')) {
    return l.commonNetworkError;
  }
  return l.commonUnexpectedError;
}

/// Slim transparent app bar with just a language toggle — the storefront has
/// no user account/settings to persist a language choice, so it's plain
/// in-memory state on [StorefrontApp], threaded down to whichever screen is
/// showing. Shows the *other* language's own name (matches the main app's
/// `languageEnglish`/`languageMyanmar` convention) so it reads correctly
/// regardless of which language the visitor currently has active.
class StorefrontLocaleBar extends StatelessWidget
    implements PreferredSizeWidget {
  const StorefrontLocaleBar({
    super.key,
    required this.locale,
    required this.onToggle,
  });
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
          label: Text(
            locale.languageCode == 'my' ? l.languageEnglish : l.languageMyanmar,
          ),
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
  final Map<String, StoreProduct> _byId = {};
  StoreInfo? _info;
  final _searchController = TextEditingController();
  String _search = '';
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    _future = _api.fetchCatalog(widget.slug);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int get _total =>
      _cart.entries.fold(0, (s, e) => s + (_byId[e.key]?.price ?? 0) * e.value);
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

  List<StoreProduct> _visible(Catalog catalog) {
    var list = catalog.products;
    if (_categoryId != null) {
      list = list.where((p) => p.categoryId == _categoryId).toList();
    }
    final query = _search.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list.where((p) => p.name.toLowerCase().contains(query)).toList();
    }
    return list;
  }

  /// Opens the cart → details/payment → confirmation flow, starting on the
  /// cart-review step so a customer always lands somewhere they can adjust
  /// quantities or back out entirely — not straight into a payment form.
  Future<void> _openCheckoutFlow(Catalog catalog) async {
    if (!catalog.info.acceptingOrders) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).storefrontClosed)),
      );
      return;
    }
    await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CheckoutFlowSheet(
        slug: widget.slug,
        api: _api,
        info: catalog.info,
        cart: _cart,
        byId: _byId,
        currency: CurrencyDef.byCode(catalog.info.currencyCode),
        onAdd: _add,
        onSub: _sub,
        // Clears the instant an order actually succeeds, not when the sheet
        // later closes — the confirmation step has no way to force the sheet
        // to stay open, so a customer swiping it away instead of tapping
        // "Done" must not leave the just-ordered items sitting in the cart
        // (that risked a confused re-tap submitting a duplicate order).
        onOrderPlaced: () {
          if (mounted) setState(() => _cart.clear());
        },
        onOrderPlacedUnseen: (orderNo) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 10),
              content: Text('$orderNo ✓'),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: StorefrontLocaleBar(
        locale: widget.locale,
        onToggle: widget.onToggleLocale,
      ),
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
          // Populate ONCE, then leave it alone. `_future` is created a
          // single time in initState, so the only source of fresher data is
          // `_refreshPricesAndCart`, which writes straight into this same
          // map (it is handed to the checkout sheet by reference). Rebuilding
          // it from `catalog` on every rebuild threw that away: after the
          // sheet bounced the customer back with "prices changed", closing
          // the sheet restored the OLD price on the grid and in the checkout
          // bar, and re-opening checkout fired the same bounce again from
          // the same stale state — the exact deception the refresh exists to
          // prevent.
          if (_byId.isEmpty) {
            _byId.addAll({for (final p in catalog.products) p.id: p});
          }
          _info = catalog.info;
          final name = catalog.info.displayName ?? widget.slug;
          final desc = [
            if ((catalog.info.phone ?? '').isNotEmpty) catalog.info.phone,
            if ((catalog.info.address ?? '').isNotEmpty) catalog.info.address,
          ].join(' · ');
          updateStorefrontSeo(
            title: name,
            description: desc.isEmpty ? name : desc,
            imageUrl: catalog.info.logoUrl,
            pageUrl: '$storefrontBaseUrl/${widget.slug}',
          );
          final visible = _visible(catalog);
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _ShopBanner(info: catalog.info)),
              if (!catalog.info.acceptingOrders)
                SliverToBoxAdapter(
                  child: MaterialBanner(
                    content: Text(l.storefrontClosed),
                    actions: const [SizedBox.shrink()],
                  ),
                ),
              if (catalog.products.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.space3,
                      AppTheme.space3,
                      AppTheme.space3,
                      0,
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: l.commonSearch,
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),
                ),
                if (catalog.categories.isNotEmpty)
                  SliverToBoxAdapter(
                    child: CategoryFilterBar(
                      selectedId: _categoryId,
                      onSelected: (id) => setState(() => _categoryId = id),
                      options: [
                        CategoryFilterOption(
                          id: null,
                          label: l.categoryAll,
                          count: catalog.products.length,
                        ),
                        for (final c in catalog.categories)
                          CategoryFilterOption(
                            id: c.id,
                            label: c.name,
                            count: catalog.products
                                .where((p) => p.categoryId == c.id)
                                .length,
                          ),
                      ],
                    ),
                  ),
              ],
              if (catalog.products.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyStateView(
                    icon: Icons.storefront_outlined,
                    title: l.storefrontCatalogEmpty,
                  ),
                )
              else if (visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyStateView(
                    icon: Icons.search_off,
                    title: l.storefrontNoSearchResults,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(AppTheme.space3),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      mainAxisSpacing: AppTheme.space3,
                      crossAxisSpacing: AppTheme.space3,
                      childAspectRatio: 0.72,
                    ),
                    delegate: SliverChildBuilderDelegate((context, i) {
                      final p = visible[i];
                      return _ProductCard(
                        product: p,
                        qty: _cart[p.id] ?? 0,
                        onAdd: () => _add(p),
                        onSub: () => _sub(p),
                        currency: CurrencyDef.byCode(catalog.info.currencyCode),
                      );
                    }, childCount: visible.length),
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
                padding: const EdgeInsets.all(AppTheme.space3),
                child: FilledButton(
                  onPressed: () async {
                    final c = await _future;
                    if (!context.mounted) return;
                    await _openCheckoutFlow(c);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.space2),
                    child: Text(
                      l.storefrontCheckoutBar(
                        _count,
                        _ks(
                          CurrencyDef.byCode(_info?.currencyCode),
                          Localizations.localeOf(context).languageCode,
                          _total,
                        ),
                      ),
                    ),
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
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space5,
        AppTheme.space6,
        AppTheme.space5,
        AppTheme.space5,
      ),
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
              ProductThumb(
                name: info.displayName ?? l.storefrontShopFallbackName,
                imageUrl: info.logoUrl,
                size: 64,
              ),
              const SizedBox(width: AppTheme.space4),
              Expanded(
                child: Text(
                  info.displayName ?? l.storefrontShopFallbackName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          if ((info.phone ?? '').isNotEmpty || (info.address ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.space4),
              child: Wrap(
                spacing: AppTheme.space4,
                runSpacing: AppTheme.space2,
                children: [
                  if ((info.phone ?? '').isNotEmpty)
                    InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: info.phone!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l.storefrontPhoneCopied),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.call_outlined,
                            size: 16,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: AppTheme.space2),
                          Text(info.phone!),
                        ],
                      ),
                    ),
                  if ((info.address ?? '').isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: AppTheme.space2),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: Text(
                            info.address!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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
    required this.currency,
  });
  final StoreProduct product;
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onSub;
  final CurrencyDef currency;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final soldOut = product.onlineAvailable == 0;
    final atCap =
        product.onlineAvailable != null && qty >= product.onlineAvailable!;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ProductThumb(
              name: product.name,
              imageUrl: product.imageUrl,
              radius: 0,
              dimmed: soldOut,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppTheme.space3),
            child: Column(
              // `start` (not `stretch`) made this Column ask its Row child
              // for its *intrinsic* width to size itself — impossible to
              // answer honestly with an Expanded inside that Row (an
              // Expanded's width depends on the space actually available
              // during real layout, not some inherent "ideal" size), which
              // is exactly what threw "BoxConstraints forces an infinite
              // width" at the price/Add-button row below. `stretch` uses
              // the already-bounded width this Padding was given instead of
              // asking children to self-report one — the Text children
              // below don't need `start` specifically, they already render
              // left-anchored via their own default `textAlign`.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (product.onlineAvailable != null) ...[
                  const SizedBox(height: AppTheme.space1),
                  Text(
                    soldOut
                        ? l.storefrontSoldOut
                        : l.storefrontOnlineLeft(product.onlineAvailable!),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: soldOut
                          ? AppColors.of(context).danger
                          : AppColors.of(context).muted,
                    ),
                  ),
                ],
                const SizedBox(height: AppTheme.space2),
                Row(
                  children: [
                    Expanded(
                      child: MoneyText(
                        _ks(currency, locale, product.price),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        textAlign: TextAlign.left,
                      ),
                    ),
                    if (qty == 0)
                      // IntrinsicWidth: this Row sits inside a Column with
                      // mainAxisSize.min, which hands the Row unbounded
                      // height/width along the way a plain FilledButton's
                      // internal Material/Ink layout can't resolve ("Box
                      // Constraints forces an infinite width") — forces a
                      // real two-pass measurement instead of the unbounded
                      // one Flex normally uses to size non-flex children.
                      IntrinsicWidth(
                        child: FilledButton.tonal(
                          onPressed: soldOut ? null : onAdd,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.space2,
                            ),
                            minimumSize: const Size(0, 36),
                            textStyle: Theme.of(context).textTheme.labelMedium,
                          ),
                          child: Text(l.storefrontAdd),
                        ),
                      )
                    else
                      IntrinsicWidth(
                        child: _QtyStepper(qty: qty, onAdd: onAdd, onSub: onSub, atCap: atCap),
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

/// Tonal −/qty/+ control shared by the product grid card and the cart-review
/// step — one place styling this the same way everywhere it appears, with
/// real tooltips on the icon-only buttons (they had none before).
class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.qty,
    required this.onAdd,
    required this.onSub,
    required this.atCap,
  });
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onSub;
  final bool atCap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          tooltip: l.sellDecreaseQty,
          onPressed: onSub,
          icon: const Icon(Icons.remove, size: 18),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.space2),
          child: Text(
            '$qty',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontFeatures: AppTheme.tabularFigures),
          ),
        ),
        IconButton.filledTonal(
          tooltip: l.sellIncreaseQty,
          onPressed: atCap ? null : onAdd,
          icon: const Icon(Icons.add, size: 18),
        ),
      ],
    );
  }
}

/// Cart review → your details/payment → confirmation, in one modal sheet.
///
/// Three complaints drove this shape (owner feedback on the live storefront,
/// 2026-09-02): the old sheet went straight from "Checkout" to a payment
/// form with no way to see/edit the cart first; it had no visible close/back
/// control other than swipe-to-dismiss; and it read as a plain form, not
/// "an e-commerce checkout". A shared header (back arrow on the details step,
/// a close X on every non-confirmation step) plus a cart-review first step
/// answers all three without a second sheet or a route push.
class _CheckoutFlowSheet extends StatefulWidget {
  const _CheckoutFlowSheet({
    required this.slug,
    required this.api,
    required this.info,
    required this.cart,
    required this.byId,
    required this.currency,
    required this.onAdd,
    required this.onSub,
    required this.onOrderPlaced,
    required this.onOrderPlacedUnseen,
  });
  final String slug;
  final StorefrontApi api;
  final StoreInfo info;

  /// Same `Map` instance the product grid mutates — edits made on the
  /// cart-review step (via [onAdd]/[onSub]) show up on the grid's bottom bar
  /// the moment this sheet closes, with no separate sync step.
  final Map<String, int> cart;
  final Map<String, StoreProduct> byId;
  final CurrencyDef currency;
  final void Function(StoreProduct) onAdd;
  final void Function(StoreProduct) onSub;

  /// Called once, right when an order submission actually succeeds — not
  /// tied to how (or whether) the sheet is later dismissed.
  final VoidCallback onOrderPlaced;

  /// Called instead of showing the confirmation when the sheet was closed
  /// while the submit was still in flight — the order is real, so the page
  /// must surface its number rather than silently emptying the cart.
  final void Function(String orderNo) onOrderPlacedUnseen;

  @override
  State<_CheckoutFlowSheet> createState() => _CheckoutFlowSheetState();
}

class _CheckoutFlowSheetState extends State<_CheckoutFlowSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _note = TextEditingController();
  // Honeypot: real customers never see or fill this field; a scripted bot
  // that blindly fills every input on the form will. Checked server-side.
  final _hp = TextEditingController();
  String _paymentMethod = 'transfer';
  bool _submitting = false;

  /// The order id this checkout will use, generated once and REUSED across
  /// retries so the server can recognise a repeat and return the order it
  /// already made rather than creating a second one. Cleared only after a
  /// confirmed success, so every "it failed, try again" tap in one checkout
  /// carries the same id. See StorefrontApi.submitOrder.
  String? _clientOrderId;

  /// The uploaded proof's storage path, kept so a retry reuses the file
  /// already uploaded rather than orphaning a new copy per attempt.
  String? _uploadedProofPath;

  /// When the order was actually placed. `_invoiceData` used to call
  /// `DateTime.now()`, and it is invoked fresh from both the confirmation's
  /// build and the save handler — so the date on screen changed on every
  /// rebuild and the saved PNG carried the moment the customer tapped Save
  /// rather than when they ordered.
  DateTime? _placedAt;
  SubmitOrderResult? _submitted;
  bool _downloading = false;
  List<int>? _proofBytes;
  String? _proofExt;
  String? _proofName;

  /// true = showing the cart-review step, false = the details/payment step.
  /// Confirmation is a separate check (`_submitted != null`), not a third
  /// value here — once an order is placed there's no "back" into either.
  bool _reviewingCart = true;

  /// Computed live from [widget.cart] on every build, not a snapshot taken
  /// when the sheet opened — the cart-review step lets the customer keep
  /// editing quantities, so a fixed list would go stale the moment they did.
  List<OrderLine> get _lines => [
    for (final e in widget.cart.entries)
      if (e.value > 0)
        OrderLine(e.key, widget.byId[e.key]!.name, widget.byId[e.key]!.price, e.value),
  ];
  int get _total => _lines.fold(0, (s, l) => s + l.price * l.qty);

  void _bumpAdd(StoreProduct p) => setState(() => widget.onAdd(p));
  void _bumpSub(StoreProduct p) => setState(() => widget.onSub(p));

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _note.dispose();
    _hp.dispose();
    super.dispose();
  }

  /// The `payment-proofs` bucket accepts only jpeg/png/webp under 5 MiB
  /// (migration 0032), and nothing enforced either here. `compressImage`
  /// returns the ORIGINAL bytes with the original extension whenever it
  /// cannot decode the input — which is exactly what happens to HEIC, the
  /// default iPhone photo format that `FileType.image` (accept="image/*")
  /// happily offers on iOS Safari. The upload then went out as
  /// `proof-….heic`, the storage client derived `image/heic` from the path,
  /// and the bucket refused it — surfacing as a generic error that no amount
  /// of retrying could clear, with no way to detach the proof. Reject it
  /// here instead, in words the customer can act on.
  Future<void> _pickProof() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = res?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    // Shrink before upload — phone screenshots are often several MB.
    final c = await compressImage(
      Uint8List.fromList(file.bytes!),
      fallbackExt: (file.extension ?? 'jpg').toLowerCase(),
    );
    const uploadable = {'jpg', 'jpeg', 'png', 'webp'};
    const maxProofBytes = 5 * 1024 * 1024;
    if (!uploadable.contains(c.ext) || c.bytes.length > maxProofBytes) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(uploadable.contains(c.ext)
            ? l.storefrontProofTooLarge
            : l.storefrontProofUnsupported),
      ));
      return;
    }
    if (!mounted) return;
    setState(() {
      _proofBytes = c.bytes;
      _proofExt = c.ext;
      _proofName = file.name;
    });
  }

  /// Re-fetches the catalog right before submitting and reconciles it against
  /// the cart — a product's price (or availability) can change while the
  /// customer is mid-checkout, since the whole catalog was only fetched once
  /// when the page loaded. `submit_order` always re-reads prices server-side
  /// regardless, so the *charge* is never wrong — but without this check, a
  /// "transfer" customer could still manually wire a stale total before ever
  /// seeing the real one (only the confirmation screen would show the
  /// mismatch, after the money already moved). A cart item that disappeared
  /// entirely (hidden/deleted) is dropped from the cart here rather than left
  /// to null-crash `_lines` on the next rebuild. Returns true if anything
  /// changed, so the caller can send the customer back to review it instead
  /// of submitting against stale numbers. Best-effort: a network hiccup here
  /// must not block an otherwise-valid submission, so it fails open (false).
  Future<bool> _refreshPricesAndCart() async {
    try {
      final fresh = await widget.api.fetchCatalog(widget.slug);
      final freshById = {for (final p in fresh.products) p.id: p};
      var changed = false;
      for (final id in widget.cart.keys.toList()) {
        final freshProduct = freshById[id];
        if (freshProduct == null) {
          widget.cart.remove(id);
          changed = true;
        } else if (widget.byId[id]?.price != freshProduct.price) {
          changed = true;
        }
      }
      widget.byId
        ..clear()
        ..addAll(freshById);
      return changed;
    } catch (_) {
      return false;
    }
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).storefrontOrderNeedsName),
        ),
      );
      return;
    }
    if (_paymentMethod == 'transfer' &&
        widget.info.requireTransferProof &&
        _proofBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).storefrontProofRequired),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    if (await _refreshPricesAndCart()) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _reviewingCart = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context).storefrontPricesChanged),
          ),
        );
      }
      return;
    }
    try {
      // Uploaded ONCE per checkout and remembered. It used to sit inside the
      // retried block, so every failure after a successful upload (including
      // a timeout) left a ~5 MiB file in the shop's folder that no row
      // references, and the next attempt uploaded another copy under a fresh
      // timestamped path.
      if (_paymentMethod == 'transfer' &&
          _proofBytes != null &&
          _uploadedProofPath == null) {
        _uploadedProofPath = await widget.api.uploadPaymentProof(
          _proofBytes!,
          _proofExt ?? 'jpg',
          folder: widget.info.shopId,
        );
      }
      final proofPath = _uploadedProofPath;
      _clientOrderId ??= const Uuid().v4();
      final submitted = await widget.api.submitOrder(
        slug: widget.slug,
        clientOrderId: _clientOrderId!,
        customerName: _name.text.trim(),
        phone: _phone.text.trim(),
        address: _address.text.trim(),
        // Township is no longer collected as a separate field — the free-text
        // delivery address above already asks for the full address, and a
        // second structured field for the same information read as duplicate
        // data entry (owner feedback, 2026-09-02). The column stays nullable
        // server-side and still displays on the shop's order detail view for
        // orders entered manually in-app, which still collect it.
        township: null,
        note: _note.text.trim(),
        paymentMethod: _paymentMethod,
        paymentProofPath: _paymentMethod == 'transfer' ? proofPath : null,
        lines: _lines,
        hp: _hp.text,
      );
      _placedAt ??= DateTime.now();
      if (mounted) {
        setState(() => _submitted = submitted);
      } else {
        // The customer swiped the sheet away while this was in flight. The
        // order is real and has an order number, but this State can no
        // longer show the confirmation — hand it to the page so they are
        // not left with an emptied cart, no order number, and every reason
        // to order again.
        widget.onOrderPlacedUnseen(submitted.orderNo);
      }
      widget.onOrderPlaced();
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        final raw = '$e';
        final blockedOrRateLimited =
            raw.contains('rate_limited') || raw.contains('blocked');
        final message = raw.contains('rate_limited')
            ? l.storefrontRateLimited
            : raw.contains('blocked')
            ? l.storefrontBlocked
            : raw.contains('out_of_stock')
            ? l.storefrontOutOfStock
            : raw.contains('proof_required') || raw.contains('proof_missing')
            ? l.storefrontProofRequired
            : raw.contains('closed')
            ? l.storefrontClosed
            : raw.contains('invalid_product')
            ? l.storefrontInvalidProduct
            : _submitFallbackMessage(l, raw);
        // These two codes mean the order genuinely cannot go through this
        // form (shared-IP false positive on the block-list, or the 10-min
        // rate window) — a SnackBar that vanishes in a few seconds leaves a
        // real customer stuck with no path to actually buy. Offer the
        // shop's own phone/Viber directly instead of a dead end.
        if (blockedOrRateLimited && (widget.info.phone ?? '').isNotEmpty) {
          await _showContactShopDialog(context, l, message);
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showContactShopDialog(
    BuildContext context,
    AppLocalizations l,
    String message,
  ) {
    final phone = widget.info.phone!;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.storefrontContactShopTitle),
        content: Text(message),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.call_outlined, size: 18),
            label: Text(l.storefrontCallShop),
            onPressed: () async {
              final ok = await launchUrl(
                Uri(scheme: 'tel', path: phone),
                mode: LaunchMode.externalApplication,
              );
              if (!ok && dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text(l.commonUnexpectedError)),
                );
              }
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: Text(l.storefrontChatViber),
            onPressed: () => openSupportViber(dialogContext, number: phone),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l.commonOk),
          ),
        ],
      ),
    );
  }

  /// Shared step header: a title, a back arrow when [onBack] is given (the
  /// details step returns to cart review), and an always-present close X
  /// (`Navigator.pop` with no result — the parent only clears the mini-cart
  /// when the sheet resolves with a non-null result, so backing out this way
  /// never discards a submitted order). This is the fix for "no way to
  /// cancel or go back" — a swipe-to-dismiss gesture existed before, but
  /// nothing on screen told a customer it was there.
  Widget _header(
    BuildContext context, {
    required String title,
    VoidCallback? onBack,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: onBack == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  visualDensity: VisualDensity.compact,
                  onPressed: onBack,
                ),
        ),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          visualDensity: VisualDensity.compact,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _cartStep(BuildContext context, AppLocalizations l) {
    final lines = _lines;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, title: l.storefrontYourCart),
        const SizedBox(height: AppTheme.space2),
        if (lines.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.space5),
            child: EmptyStateView(
              icon: Icons.shopping_cart_outlined,
              title: l.storefrontCartEmptyTitle,
              message: l.storefrontCartEmptyBody,
              actionLabel: l.storefrontContinueShopping,
              onAction: () => Navigator.of(context).pop(),
            ),
          )
        else ...[
          for (final line in lines)
            _CartLineRow(
              line: line,
              product: widget.byId[line.productId]!,
              currency: widget.currency,
              onAdd: () => _bumpAdd(widget.byId[line.productId]!),
              onSub: () => _bumpSub(widget.byId[line.productId]!),
            ),
          const Divider(),
          Row(
            children: [
              Expanded(
                child: Text(
                  l.commonTotal,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              MoneyText(
                _ks(
                  widget.currency,
                  Localizations.localeOf(context).languageCode,
                  _total,
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space3),
          FilledButton(
            onPressed: () => setState(() => _reviewingCart = false),
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.space2),
              child: Text(l.storefrontProceedToCheckout),
            ),
          ),
        ],
      ],
    );
  }

  Widget _detailsStep(BuildContext context, AppLocalizations l) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          context,
          title: l.storefrontYourDetails,
          onBack: () => setState(() => _reviewingCart = true),
        ),
        const SizedBox(height: AppTheme.space3),
        // Honeypot — kept out of the visible layout entirely (zero size,
        // not just hidden) so no real customer can tab/scroll into it.
        Offstage(child: TextField(controller: _hp, autofocus: false)),
        TextField(
          controller: _name,
          decoration: InputDecoration(labelText: l.storefrontNameRequired),
        ),
        const SizedBox(height: AppTheme.space2),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: l.shopPhone),
        ),
        const SizedBox(height: AppTheme.space2),
        TextField(
          controller: _address,
          maxLines: 2,
          decoration: InputDecoration(labelText: l.orderDeliveryAddress),
        ),
        const SizedBox(height: AppTheme.space2),
        TextField(
          controller: _note,
          decoration: InputDecoration(labelText: l.orderNote),
        ),
        const SizedBox(height: AppTheme.space4),
        SectionHeader(title: l.storefrontPayment),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: 'transfer',
              label: Text(l.storefrontBankTransfer),
              icon: const Icon(Icons.account_balance_outlined),
            ),
            ButtonSegment(
              value: 'cod',
              label: Text(l.storefrontCashOnDelivery),
              icon: const Icon(Icons.local_shipping_outlined),
            ),
          ],
          selected: {_paymentMethod},
          onSelectionChanged: (s) => setState(() => _paymentMethod = s.first),
        ),
        const SizedBox(height: AppTheme.space3),
        if (_paymentMethod == 'transfer') ...[
          if (widget.info.paymentMethods.isNotEmpty) ...[
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.space3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.storefrontPayTo,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppTheme.space1),
                    for (final m in widget.info.paymentMethods)
                      _PayAccountRow(
                        method: m.label,
                        name: m.accountName,
                        number: m.accountNumber,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTheme.space2),
          ],
          OutlinedButton.icon(
            onPressed: _pickProof,
            icon: const Icon(Icons.upload_file),
            label: Text(
              _proofName == null
                  ? (widget.info.requireTransferProof
                        ? l.storefrontAttachProofRequired
                        : l.storefrontAttachProof)
                  : l.storefrontProofAttached(_proofName!),
            ),
          ),
        ] else
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.space3),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: AppTheme.space2),
                  Expanded(child: Text(l.storefrontCodNoticeBeforeOrder)),
                ],
              ),
            ),
          ),
        const SizedBox(height: AppTheme.space4),
        Text(
          l.storefrontTotal(
            _ks(
              widget.currency,
              Localizations.localeOf(context).languageCode,
              _total,
            ),
          ),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppTheme.space3),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.space2),
            child: _submitting
                ? const ButtonSpinner()
                : Text(l.storefrontPlaceOrder),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    if (_submitted != null) return _confirmation(context, l);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppTheme.space4,
        AppTheme.space4,
        AppTheme.space4,
        bottom + AppTheme.space4,
      ),
      child: SingleChildScrollView(
        child: _reviewingCart
            ? _cartStep(context, l)
            : _detailsStep(context, l),
      ),
    );
  }

  /// Prices the server actually charged — not the client-computed [_lines],
  /// which can go stale between submit and this confirmation view if the
  /// owner edits a product mid-checkout.
  List<OrderLine> get _chargedLines {
    final server = _submitted?.lines;
    if (server != null && server.isNotEmpty) return server;
    return _lines;
  }

  InvoiceData _invoiceData(AppLocalizations l) => InvoiceData(
    shopName: widget.info.displayName ?? l.storefrontShopFallbackName,
    shopLogoUrl: widget.info.logoUrl,
    shopPhone: widget.info.phone,
    shopAddress: widget.info.address,
    invoiceNo: _submitted?.orderNo ?? '',
    date: DateTime.now(),
    customerName: _name.text.trim(),
    customerPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
    deliveryAddress: _address.text.trim().isEmpty ? null : _address.text.trim(),
    items: [
      for (final line in _chargedLines)
        InvoiceItemData(
          name: line.name,
          qty: line.qty,
          unitPrice: line.price,
          lineTotal: line.price * line.qty,
        ),
    ],
    paymentMethodCode: _paymentMethod,
    // The order confirmation is a pre-sale document: COD is paid at the
    // door by design, a transfer is awaiting the shop's verification of
    // the screenshot — neither is the red "unpaid/credit" state the
    // default stamped on it (see [invoicePaymentStatusDisplay]).
    paymentStatus: _paymentMethod == 'cod' ? 'cod_pending' : 'transfer_pending',
    footer: l.receiptThankYou,
    currencySymbol: widget.currency.symbol,
    exponent: widget.currency.exponent,
  );

  Future<void> _saveInvoiceToPhotos(
    BuildContext context,
    AppLocalizations l,
  ) async {
    setState(() => _downloading = true);
    try {
      final invoice = _invoiceData(l);
      if ((invoice.shopLogoUrl ?? '').isNotEmpty) {
        try {
          await precacheImage(NetworkImage(invoice.shopLogoUrl!), context);
        } catch (_) {}
      }
      if (!context.mounted) return;
      final bytes = await captureWidgetAsPng(
        context,
        InvoiceView(data: invoice),
      );
      await saveImageToPhotos(bytes, 'invoice-${invoice.invoiceNo}.png');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Widget _confirmation(BuildContext context, AppLocalizations l) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle,
              color: AppColors.of(context).success,
              size: 48,
            ),
            const SizedBox(height: AppTheme.space2),
            Text(
              l.storefrontOrderPlaced,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppTheme.space1),
            Text(l.storefrontOrderNo(_submitted!.orderNo)),
            const SizedBox(height: AppTheme.space4),
            InvoiceView(data: _invoiceData(l)),
            const SizedBox(height: AppTheme.space3),
            if (_paymentMethod == 'transfer' &&
                widget.info.paymentMethods.isNotEmpty) ...[
              Text(l.storefrontTransferInstructions),
              const SizedBox(height: AppTheme.space2),
              for (final m in widget.info.paymentMethods)
                _PayAccountRow(
                  method: m.label,
                  name: m.accountName,
                  number: m.accountNumber,
                ),
              const SizedBox(height: AppTheme.space4),
            ] else if (_paymentMethod == 'cod') ...[
              Text(l.storefrontCodNoticeAfterOrder),
              const SizedBox(height: AppTheme.space4),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _downloading
                        ? null
                        : () => _saveInvoiceToPhotos(context, l),
                    icon: _downloading
                        ? const ButtonSpinner(size: 16)
                        : const Icon(Icons.photo_library_outlined),
                    label: Text(l.storefrontSaveToPhotos),
                  ),
                ),
                const SizedBox(width: AppTheme.space2),
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

/// One line in the cart-review step: thumbnail, name + unit price, and a
/// trailing qty stepper stacked over the tabular line total — the pattern
/// convergent across small-shop ordering apps (stepper on the trailing
/// edge, total right-aligned under it) rather than a bare quantity number.
/// No separate "remove" control: dragging the stepper to 0 removes the line,
/// same gesture the product grid already teaches on the way in.
class _CartLineRow extends StatelessWidget {
  const _CartLineRow({
    required this.line,
    required this.product,
    required this.currency,
    required this.onAdd,
    required this.onSub,
  });
  final OrderLine line;
  final StoreProduct product;
  final CurrencyDef currency;
  final VoidCallback onAdd;
  final VoidCallback onSub;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final atCap =
        product.onlineAvailable != null && line.qty >= product.onlineAvailable!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProductThumb(name: line.name, imageUrl: product.imageUrl, size: 48),
          const SizedBox(width: AppTheme.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // No `maxLines`/`overflow: ellipsis` here on purpose — a
                // Myanmar product name can run 20-40% longer than its
                // English counterpart and stack diacritics, so this wraps to
                // as many lines as it needs instead of clipping the one
                // thing that tells the customer what they're buying.
                Text(line.name, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppTheme.space1),
                Text(
                  _ks(currency, locale, line.price),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.of(context).muted,
                    fontFeatures: AppTheme.tabularFigures,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.space2),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              _QtyStepper(qty: line.qty, onAdd: onAdd, onSub: onSub, atCap: atCap),
              const SizedBox(height: AppTheme.space1),
              MoneyText(
                _ks(currency, locale, line.price * line.qty),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ],
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
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space1),
      child: Row(
        children: [
          Expanded(child: Text('$method: $label')),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            tooltip: l.storefrontCopyNumber,
            visualDensity: VisualDensity.compact,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: number));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(l.storefrontNumberCopied)));
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
    return EmptyStateView(
      icon: Icons.storefront_outlined,
      title: l.storefrontNotFound(slug),
    );
  }
}
