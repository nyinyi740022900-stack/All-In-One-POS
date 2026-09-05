import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Standard "nothing here yet" view — icon + short copy + an optional
/// primary action. Use instead of a bare `Center(child: Text(...))` for any
/// list/screen that can legitimately be empty (no products, no orders yet,
/// search with no matches, etc.).
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TonalIconPlate(child: Icon(icon, size: 36, color: colors.muted)),
            const SizedBox(height: AppTheme.space4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (message != null) ...[
              const SizedBox(height: AppTheme.space1),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.muted),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppTheme.space4),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Soft square plate behind an empty/error/loading glyph so those states
/// read as designed, not as a bare Material icon floating on the page.
class _TonalIconPlate extends StatelessWidget {
  const _TonalIconPlate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// Centered spinner on the same tonal plate [EmptyStateView] uses, so a
/// loading tab doesn't flash a bare [CircularProgressIndicator] against
/// the page. Optional [message] sits under the plate (no fixed height —
/// Myanmar copy is allowed to wrap).
class AppLoadingView extends StatelessWidget {
  const AppLoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TonalIconPlate(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: scheme.primary,
                ),
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: AppTheme.space4),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.of(context).muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Section label for grouped lists (Settings, similar hubs). Title-weight
/// and brand-green, not a tiny uppercase caption — Myanmar has no case, so
/// the old `toUpperCase()` treatment only made English look louder.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space5,
        AppTheme.space5,
        AppTheme.space4,
        AppTheme.space2,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// White card wrapping a cluster of list tiles on the page surface, so a
/// long Settings (or similar) screen reads as a few short lists instead of
/// one flat wall of rows.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space3),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }
}

/// Leading glyph for auth/onboarding text fields (email, shop name, phone).
/// Do **not** put this on [AuthPasswordField] — that already has a trailing
/// visibility toggle, and a second icon crowds Myanmar labels.
class AuthFieldIcon extends StatelessWidget {
  const AuthFieldIcon(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant);
  }
}

/// What a [StatusPill] is *saying*, not what colour it is — screens pick the
/// meaning and the pill owns the palette. Four tones, because that is how many
/// distinct answers a shopkeeper needs at a glance:
///
/// * [positive] — settled, done, nothing to do (paid, delivered, in stock);
/// * [attention] — open, waiting on someone, needs an action (new order,
///   unpaid, low stock). Deliberately **not** [critical]: most of a shop's
///   day is spent in this state and a red list is a list nobody reads;
/// * [critical] — money or stock is actually wrong (refunded, overdue, out of
///   stock);
/// * [neutral] — real but finished-with (cancelled, archived, inactive).
enum StatusTone { positive, attention, critical, neutral }

extension StatusToneColors on StatusTone {
  /// Resolves to a `(fill, on)` pair from the [AppColors] soft-fill tier.
  /// Pass the palette rather than a [BuildContext] so the fixed-light
  /// document surfaces can hand over [AppColors.onLightDocument].
  ({Color fill, Color on}) colors(AppColors palette) => switch (this) {
    StatusTone.positive => (fill: palette.successSurface, on: palette.success),
    StatusTone.attention => (fill: palette.warningSurface, on: palette.warning),
    StatusTone.critical => (fill: palette.dangerSurface, on: palette.danger),
    StatusTone.neutral => (fill: palette.neutralSurface, on: palette.muted),
  };
}

/// The app's one status pill: a **soft pastel fill with a solid-colour label**
/// (and an optional dot or icon in the same solid colour).
///
/// This is the pattern the whole Orders + Invoices hub converges on. Before
/// it, every screen hand-rolled its own — `Colors.green.withValues(alpha:
/// 0.12)` at radius 10 in the order sheet, `Colors.redAccent` at 0.12/radius
/// 20 on the invoice document, `colorScheme.error` at 0.12/radius 4 in the
/// invoice list — five near-identical widgets with five different fills, three
/// radii, and two of them mixing an alpha wash over a near-black dark surface
/// (which goes muddy, not pastel). The [AppColors] soft-fill tier exists
/// precisely so the fill is a *designed* colour rather than an alpha guess.
///
/// **Pastel fill, saturated label** is the deliberate half of it: a wall of
/// solid-green/solid-red pills fights the one primary CTA on the screen for
/// attention, while the pastel plate stays quiet at list scale and the solid
/// label keeps the text itself at full contrast.
///
/// Myanmar safety: no fixed height and no ellipsis — a status word runs
/// ~20-40% longer in Myanmar and stacks diacritics, so the pill grows with its
/// text (up to two lines) instead of clipping it.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.showDot = false,
    this.palette,
  });

  final String label;
  final StatusTone tone;

  /// Optional leading glyph, drawn in the tone's solid colour. Mutually
  /// exclusive with [showDot] (an icon *is* the marker).
  final IconData? icon;

  /// Draws a small solid dot before the label — the lighter-weight marker for
  /// pills that sit in a dense list row where an icon would be one shape too
  /// many.
  final bool showDot;

  /// Overrides the palette this pill reads. Only for theme-independent
  /// document surfaces — see [AppColors.onLightDocument].
  final AppColors? palette;

  @override
  Widget build(BuildContext context) {
    final tokens = tone.colors(palette ?? AppColors.of(context));
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space2,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: tokens.fill,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tokens.on),
            const SizedBox(width: AppTheme.space1),
          ] else if (showDot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: tokens.on,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppTheme.space1),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: tokens.on),
            ),
          ),
        ],
      ),
    );
  }
}

/// The visual anchor for a catalogue or directory row — a product's photo when
/// one exists, and a **designed initial-letter plate** when one doesn't.
///
/// Also used for people (the customer directory), where there is never a photo
/// at all: the plate is then the entire point — a stable colour + initial per
/// customer beats 200 identical grey person-icons in a list you scan by eye.
///
/// Shared on purpose: the Sell grid, the checkout sheet's cart lines and the
/// tablet cart panel all show the same product, so they must show the same
/// mark. Before this existed, product images were loaded ad hoc in two places
/// (`product_edit_screen.dart`, `storefront_page.dart`) and not at all in
/// Sell/checkout, which left the busiest screen in the app rendering products
/// as bare text.
///
/// **The no-photo case is the normal case here**, not an error case: a shop
/// owner keying in 200 items on a cheap Android panel will photograph very few
/// of them. So there is no broken-image glyph and no empty grey box anywhere
/// in this widget — a missing URL, a failed decode, and *no network at all*
/// (the offline-first default) all land on the same tonal plate with the
/// product's initials, from [AppColors.identityTone]. The plate is keyed to
/// the product name, so a given product keeps one stable color everywhere it
/// appears and the seller can aim at "the teal one" without reading.
///
/// Initials are cut on **grapheme clusters**, not code units: Myanmar stacks
/// medials and vowel signs (ကျွ, ဆွေး) and slicing a string by index would
/// strand a combining mark, which renders as a dotted-circle placeholder.
class ProductThumb extends StatelessWidget {
  const ProductThumb({
    super.key,
    required this.name,
    this.imageUrl,
    this.size,
    this.radius = AppTheme.radiusMd,
    this.dimmed = false,
  });

  final String name;

  /// Remote product photo (Supabase public URL). Null/blank falls back to the
  /// initials plate — as does any load failure, including being offline.
  final String? imageUrl;

  /// Square side length. Null means "fill the space my parent gives me" (how
  /// the Sell grid card uses it, as the flexible top band of the tile).
  final double? size;

  final double radius;

  /// Out-of-stock treatment — keeps the mark recognizable while pushing it
  /// behind the badge that explains why the tile is unavailable.
  final bool dimmed;

  static final RegExp _wordStart = RegExp(r'^[\p{L}\p{N}]', unicode: true);

  /// The mark shown when there is no photo.
  ///
  /// **Latin gets two letters, Myanmar gets one**, and that asymmetry is the
  /// whole point. "CC" for Coca Cola reads as an abbreviation; the same rule
  /// applied to Myanmar produced strings like "အုဘီ" — four code points that
  /// look like a misspelled word rather than an initial, which is exactly the
  /// unfinished-looking result this widget exists to avoid. One Myanmar
  /// cluster ("ကို", "ရေ", "ရွှေ") is a whole syllable and reads as a proper
  /// initial.
  ///
  /// Words that start with punctuation are skipped, so a name like
  /// "ရေသန့် (၁ လီတာ)" doesn't take an opening bracket as its second letter.
  static String initialsFor(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => _wordStart.hasMatch(w))
        .toList();
    if (words.isEmpty) return '';
    final first = words.first.characters.first;
    // Myanmar block: one syllable is the initial.
    final code = first.runes.first;
    if (code >= 0x1000 && code <= 0x109F) return first;
    if (words.length >= 2) {
      return (first + words[1].characters.first).toUpperCase();
    }
    return words.first.characters.take(2).toString().toUpperCase();
  }

  /// Decoded-pixel budget for the photo band: rendered side × device pixel
  /// ratio, clamped. Product photos upload at up to 1280 px; without
  /// [Image.cacheWidth] every thumb decoded at FULL source resolution —
  /// ~4–6 MB of RGBA per photo — so scrolling the Sell grid churned tens of
  /// MB through the image cache and janked on mid-range Android (audit H2).
  /// The clamp keeps a huge source from decoding full-res into a 48 pt row
  /// while never asking for an absurdly small decode either.
  static int cacheWidthFor(double renderedSide, double devicePixelRatio) {
    final px = renderedSide * devicePixelRatio;
    return px.round().clamp(96, 1024);
  }

  @override
  Widget build(BuildContext context) {
    final tone = AppColors.of(context).identityTone(name);
    final url = imageUrl?.trim() ?? '';

    final plate = _InitialsPlate(
      initials: initialsFor(name),
      color: tone.onFill,
    );

    Widget content = plate;
    if (url.isNotEmpty) {
      // LayoutBuilder so the decode budget comes from the space the thumb
      // actually occupies (fixed `size`, or the parent-given band on Sell's
      // grid), not from nothing.
      content = LayoutBuilder(
        builder: (context, constraints) {
          final side =
              size ??
              (constraints.maxWidth.isFinite && constraints.maxWidth > 0
                  ? constraints.maxWidth
                  : (constraints.maxHeight.isFinite && constraints.maxHeight > 0
                        ? constraints.maxHeight
                        : 40.0));
          final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
          // Disk-cached load (audit H2): photos now survive app restarts
          // instead of re-downloading on every launch, and `memCacheWidth`
          // carries the #227 decode budget into the cache key. The initials
          // plate is BOTH placeholder and error widget — no spinner, no
          // broken-image glyph — so an offline morning looks identical to an
          // in-flight one.
          return CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            memCacheWidth: cacheWidthFor(side, dpr),
            fadeInDuration: AppTheme.motionMedium,
            placeholder: (_, _) => plate,
            errorWidget: (_, _, _) => plate,
          );
        },
      );
    }

    final tile = DecoratedBox(
      decoration: BoxDecoration(
        color: tone.fill,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(width: size, height: size, child: content),
      ),
    );

    // The product name always sits next to this, so the mark is decorative —
    // announcing it again would just make the row twice as long to hear.
    return ExcludeSemantics(
      child: dimmed ? Opacity(opacity: 0.38, child: tile) : tile,
    );
  }
}

class _InitialsPlate extends StatelessWidget {
  const _InitialsPlate({required this.initials, required this.color});

  final String initials;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = [
          constraints.hasBoundedWidth ? constraints.maxWidth : 40.0,
          constraints.hasBoundedHeight ? constraints.maxHeight : 40.0,
        ].reduce((a, b) => a < b ? a : b);
        return Padding(
          padding: EdgeInsets.all(side * 0.16),
          child: Center(
            // Myanmar clusters are wider than Latin ones and the user may be
            // at 1.3x text scale — scale down rather than clip or ellipsize.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                initials,
                maxLines: 1,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: color,
                  fontSize: side * 0.42,
                  // Not the 1.0-1.1 a Latin monogram would use: Myanmar
                  // stacks a vowel sign under the base letter and a tight
                  // line box clips it.
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One chip in a [CategoryFilterBar] — a category (or the "All" pseudo-
/// category, which carries a null [id]) plus how many products sit behind it.
class CategoryFilterOption {
  const CategoryFilterOption({
    required this.id,
    required this.label,
    required this.count,
  });

  /// Category id; `null` is the "All" chip.
  final String? id;
  final String label;
  final int count;
}

/// Horizontal category scroller shown above a product grid/list.
///
/// Shared between Sell and Inventory on purpose: they filter the *same*
/// catalogue by the *same* categories, so a chip row that looks and behaves
/// differently between the two tabs is just two half-finished versions of one
/// control. (Sell's was rebuilt in the A2 pass and Inventory's was left as the
/// original bare `ChoiceChip` row in a fixed `SizedBox(height: 48)` — this is
/// that fix, applied once instead of copied.)
///
/// One decision worth keeping: **the bar sizes to its content.** A fixed
/// single-line height is what clips a two-line Myanmar category name at
/// 1.3x text scale.
///
/// Chips deliberately don't show a per-category product count any more — a
/// shop with many categories found the number-per-chip noisy once the list
/// grew, and the count is still available in [showCategoryPickerSheet] via
/// each option's underlying data if ever needed again.
class CategoryFilterBar extends StatelessWidget {
  const CategoryFilterBar({
    super.key,
    required this.options,
    required this.selectedId,
    required this.onSelected,
  });

  final List<CategoryFilterOption> options;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      // Stretch, not the default centre: a horizontal scroller shrink-wraps
      // its content, so a short chip row would sit centred in the bar instead
      // of starting on the same left rule as the grid below it.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space3,
            AppTheme.space2,
            AppTheme.space3,
            AppTheme.space2,
          ),
          child: Row(
            children: [
              for (final option in options)
                Padding(
                  padding: const EdgeInsets.only(right: AppTheme.space2),
                  child: ChoiceChip(
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.space3,
                      vertical: AppTheme.space2,
                    ),
                    label: Text(option.label),
                    selected: option.id == selectedId,
                    onSelected: (_) => onSelected(option.id),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

/// Sentinel returned by [showCategoryPickerSheet]'s "All" row — `null` can't
/// ride through `Navigator.pop` without becoming indistinguishable from a
/// plain dismissal.
const _kCategoryPickerAll = '__all__';

/// Direct-pick category chooser — the counterpart to the scrollable
/// [CategoryFilterBar] chip row. A shop whose category list has grown past
/// a screenful has to hunt through the scroller chip by chip; this sheet
/// lists them all at once (check on the current pick), with a search field
/// once the list is long enough to be worth narrowing, so one tap from the
/// search bar's filter icon lands on the category. Shared by Sell and
/// Inventory, like the chip row.
Future<void> showCategoryPickerSheet(
  BuildContext context, {
  required List<CategoryFilterOption> options,
  required String? selectedId,
  required String title,
  required ValueChanged<String?> onSelected,
}) async {
  final l = AppLocalizations.of(context);
  final picked = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      // Lives outside StatefulBuilder's own builder callback so it survives
      // the setState-triggered rebuilds below instead of resetting to '' on
      // every keystroke.
      var query = '';
      return SafeArea(
        child: StatefulBuilder(
          builder: (context, setState) {
            return _CategoryPickerSheetBody(
              title: title,
              options: options,
              selectedId: selectedId,
              searchHint: l.commonSearch,
              noResultsText: l.categoryPickerNoResults,
              onQueryChanged: (v) => setState(() => query = v),
              query: query,
            );
          },
        ),
      );
    },
  );
  if (picked == null) return; // dismissed
  onSelected(picked == _kCategoryPickerAll ? null : picked);
}

class _CategoryPickerSheetBody extends StatelessWidget {
  const _CategoryPickerSheetBody({
    required this.title,
    required this.options,
    required this.selectedId,
    required this.searchHint,
    required this.noResultsText,
    required this.query,
    required this.onQueryChanged,
  });

  final String title;
  final List<CategoryFilterOption> options;
  final String? selectedId;
  final String searchHint;
  final String noResultsText;
  final String query;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    // "All" always stays visible — it's not a searchable category, it's the
    // reset action.
    final filtered = q.isEmpty
        ? options
        : options
              .where((o) => o.id == null || o.label.toLowerCase().contains(q))
              .toList();
    return ListView(
      shrinkWrap: true,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.space4,
            AppTheme.space3,
            AppTheme.space4,
            AppTheme.space1,
          ),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        // Only worth the extra row once there are enough categories that
        // scanning them all is slower than typing a few letters.
        if (options.length > 6)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space4,
              0,
              AppTheme.space4,
              AppTheme.space2,
            ),
            child: TextField(
              autofocus: false,
              decoration: InputDecoration(
                isDense: true,
                hintText: searchHint,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: onQueryChanged,
            ),
          ),
        for (final option in filtered)
          ListTile(
            leading: Icon(option.id == null ? Icons.apps : Icons.label_outline),
            title: Text(option.label),
            trailing: option.id == selectedId ? const Icon(Icons.check) : null,
            onTap: () =>
                Navigator.pop(context, option.id ?? _kCategoryPickerAll),
          ),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppTheme.space4),
            child: Text(
              noResultsText,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        const SizedBox(height: AppTheme.space2),
      ],
    );
  }
}

/// One selectable chip inside a [showChipFilterSheet] section. [onTap]
/// is expected to both flip the backing provider's state AND call the
/// `refresh` callback the sheet hands to its `sectionsBuilder`, so the chip
/// visibly toggles without the caller needing its own Riverpod plumbing
/// inside the modal.
class FilterChipSpec {
  const FilterChipSpec({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
}

/// A labelled (or unlabelled) group of [FilterChipSpec] chips in a
/// [showChipFilterSheet].
class FilterChipSection {
  const FilterChipSection({this.title, required this.chips});
  final String? title;
  final List<FilterChipSpec> chips;
}

/// Generic "more filters" bottom sheet — the counterpart to
/// [showCategoryPickerSheet] for screens whose filters aren't category-based
/// (Orders' status/channel/payment, Invoices' all/credit/refund). Puts a
/// filter icon beside the search field instead of an always-visible chip row
/// below it, which used to scroll and eat vertical space even when a shop
/// never touched the filters.
///
/// [sectionsBuilder] is re-invoked on every local `refresh()` (via the
/// sheet's own `StatefulBuilder`) rather than wired through Riverpod's
/// `Consumer`, so callers just read current provider values with `ref.read`
/// inside it and call the passed-in `refresh` after mutating state — no
/// separate reactive plumbing needed for the modal to reflect the tap.
Future<void> showChipFilterSheet(
  BuildContext context, {
  required String title,
  required List<FilterChipSection> Function(VoidCallback refresh)
  sectionsBuilder,
  String? clearLabel,
  VoidCallback? onClearAll,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: StatefulBuilder(
        builder: (context, setState) {
          void refresh() => setState(() {});
          final sections = sectionsBuilder(refresh);
          return ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.space4,
                  AppTheme.space3,
                  AppTheme.space2,
                  AppTheme.space1,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (onClearAll != null && clearLabel != null)
                      TextButton(
                        onPressed: () {
                          onClearAll();
                          refresh();
                        },
                        child: Text(clearLabel),
                      ),
                  ],
                ),
              ),
              for (final section in sections) ...[
                if (section.title != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.space4,
                      AppTheme.space2,
                      AppTheme.space4,
                      AppTheme.space1,
                    ),
                    child: Text(
                      section.title!,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.space4,
                  ),
                  child: Wrap(
                    spacing: AppTheme.space2,
                    runSpacing: AppTheme.space2,
                    children: [
                      for (final chip in section.chips)
                        ChoiceChip(
                          label: Text(chip.label),
                          selected: chip.selected,
                          onSelected: (_) => chip.onTap(),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppTheme.space3),
            ],
          );
        },
      ),
    ),
  );
}

/// A section title with optional trailing action (e.g. "See all"). Keeps
/// list-of-sections screens (Settings, Analytics, Sell cart summary) from
/// each hand-rolling their own heading style.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Resolves the `(fill, on)` pair a toned surface should use, where a **null
/// tone means "no signal"** — a quiet neutral plate from the surface ramp
/// rather than a fifth colour. Shared by [StatCard] and [IconAvatar] so an
/// informational tile and an informational list row look like each other.
({Color fill, Color on}) _plateColors(BuildContext context, StatusTone? tone) {
  if (tone != null) return tone.colors(AppColors.of(context));
  final scheme = Theme.of(context).colorScheme;
  return (fill: scheme.surfaceContainerHigh, on: scheme.onSurfaceVariant);
}

/// One tile in a KPI / summary grid — icon plate, label, and a big **tabular**
/// value. The Analytics dashboard, and any future summary grid, uses this
/// instead of hand-rolling a `Card` + `Column`.
///
/// **Colour here means a signal, never a category.** [tone] is null for the
/// ordinary informational tiles (revenue, expenses, sales count…), which get a
/// neutral plate, and non-null only where the figure's *sign* is telling the
/// shopkeeper something is wrong (net profit below zero, credit outstanding).
/// The alternative — a different decorative hue per KPI — was measured and
/// rejected; see the design note on the Analytics dashboard.
///
/// Myanmar/text-scale safety: the label gets two lines, and the value is
/// scaled down by a [FittedBox] rather than ellipsized, because a truncated
/// money figure is worse than a small one. The tile therefore never needs a
/// fixed aspect ratio to stay intact — give the grid a `mainAxisExtent`
/// derived from the current text scale.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.tone,
    this.onTap,
  });

  final String label;

  /// Pre-formatted figure (money string, count…). Always rendered tabular.
  final String value;
  final IconData? icon;

  /// Null = informational. Non-null = this figure is a *signal*.
  final StatusTone? tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plate = _plateColors(context, tone);
    return Card(
      // Zero, not Card's own default 4dp: this tile lives in a GridView
      // whose delegate already supplies mainAxisSpacing/crossAxisSpacing AND
      // a mainAxisExtent sized to the content computed by _kpiTileExtent().
      // Card's default margin ate into that budget from the outside where
      // the extent math couldn't see it, overflowing every tile by ~8px.
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: plate.fill,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      ),
                      alignment: Alignment.center,
                      child: Icon(icon, size: 18, color: plate.on),
                    ),
                    const SizedBox(width: AppTheme.space2),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.space2),
              // Left-aligned: this is a headline figure in a card, not a
              // column entry, so it hangs off the same left rule as its label.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: MoneyText(
                  value,
                  textAlign: TextAlign.start,
                  emphasis: true,
                  color: tone == null ? null : plate.on,
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The leading mark on a list row whose subject is a **category or an
/// account**, not a person or a product — an expense category, a recurring
/// template, a payment account, an equity entry.
///
/// Exists because those rows all reached for a bare `CircleAvatar`, whose M3
/// default background is [ColorScheme.primaryContainer]: the fill this app
/// reserves for "selected / primary action". A column of pale-green circles
/// down the Expenses list competes with the one FAB that matters, on five
/// screens at once. Neutral by default; [tone] only where the row itself
/// carries a signal (an equity drawing vs. a contribution).
///
/// Rounded square rather than a circle, matching [ProductThumb], so a list of
/// categories and a list of products read as one family.
class IconAvatar extends StatelessWidget {
  const IconAvatar({super.key, this.icon, this.text, this.tone, this.size = 40})
    : assert(icon != null || text != null, 'IconAvatar needs an icon or text');

  final IconData? icon;

  /// Short label used instead of an icon — a quantity or a rank. Rendered
  /// tabular so a column of them lines up.
  final String? text;
  final StatusTone? tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final plate = _plateColors(context, tone);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: plate.fill,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, size: size * 0.5, color: plate.on)
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.space1),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text!,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: plate.on,
                    fontFeatures: AppTheme.tabularFigures,
                  ),
                ),
              ),
            ),
    );
  }
}

/// In-button progress at exactly the size of the icon it replaces, so a
/// button doesn't change width the moment it starts working — and so a row of
/// export/print buttons doesn't reflow while one of them is running.
///
/// Was repeated inline in the sales report, the P&L screen and elsewhere; this
/// is that shape, once.
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: const CircularProgressIndicator(strokeWidth: 2),
  );
}

/// A money or quantity figure with tabular (fixed-width) numerals so digits
/// line up column-to-column as amounts change — plain proportional digits
/// visibly "wobble" in a price list. Use this instead of a bare `Text(...)`
/// for every money/qty figure (see `AppTheme.tabularFigures`).
///
/// Defaults to right-aligned (the normal reading direction for a money
/// column) and the current [TextTheme.bodyMedium] — pass [style] to use a
/// bigger role (e.g. `titleMedium` for a checkout total).
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.value, {
    super.key,
    this.style,
    this.color,
    this.emphasis = false,
    this.textAlign = TextAlign.right,
  });

  final String value;
  final TextStyle? style;
  final Color? color;
  final bool emphasis;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyMedium;
    return Text(
      value,
      textAlign: textAlign,
      // An amount is never meant to wrap. Without this, a narrow container
      // (e.g. the storefront product card's price squeezed by the "Add"
      // button next to it) makes the default multi-line Text wrap character
      // by character instead of just truncating — every digit on its own
      // line, and on the storefront that overflow also pushed the Add
      // button out of its tappable area.
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base?.copyWith(
        fontFeatures: AppTheme.tabularFigures,
        fontWeight: emphasis ? FontWeight.w700 : base.fontWeight,
        color: color ?? base.color,
      ),
    );
  }
}

/// A label/value row — "Subtotal ... 12,000 Ks", "Change ... 500 Ks" — used
/// by any totals/summary block (checkout, invoices, cash register). The
/// value renders with tabular numerals via [MoneyText] since this row exists
/// almost exclusively for money figures; pass [isMoney]=false for a plain
/// text value (e.g. a status word) that shouldn't get tabular spacing.
class SummaryRow extends StatelessWidget {
  const SummaryRow(
    this.label,
    this.value, {
    super.key,
    this.emphasis = false,
    this.color,
    this.isMoney = true,
  });

  final String label;
  final String value;
  final bool emphasis;
  final Color? color;
  final bool isMoney;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasis
        ? theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          )
        : theme.textTheme.bodyMedium?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Flexible, because a Myanmar label runs ~20-40% longer than its
          // English source ("Total balance due" ➜ "စုစုပေါင်း ကျန်ငွေ
          // (ပေးရမည်)") and an unflexed label in a `Row` overflows the page
          // instead of wrapping.
          Flexible(child: Text(label, style: style)),
          const SizedBox(width: AppTheme.space3),
          if (isMoney)
            MoneyText(value, style: style, emphasis: emphasis, color: color)
          else
            // A non-money value can be a whole phrase (a payment-account name,
            // a device label), so it wraps rather than pushing the row wide.
            Flexible(
              child: Text(value, style: style, textAlign: TextAlign.end),
            ),
        ],
      ),
    );
  }
}

/// A load failure with an actual recovery path, not a dead end — icon +
/// message + a "Retry" button that invalidates the failed provider. Use this
/// instead of a bare `Center(child: Text(...))` on an `AsyncValue`/`.when()`
/// error branch.
///
/// Mirrors the shape `storefront_screen.dart`'s `_ErrorRetryView` and
/// `branches_screen.dart`'s inline error view established first, promoted to
/// a shared widget so screens that only had a dead-end error branch (Sell,
/// Inventory, Categories, Stock History, Orders, Invoices, Shop Profile,
/// Equity) don't each hand-roll their own copy.
class ErrorRetryView extends StatelessWidget {
  const ErrorRetryView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TonalIconPlate(
              child: Icon(
                Icons.error_outline,
                size: 36,
                color: AppColors.of(context).muted,
              ),
            ),
            const SizedBox(height: AppTheme.space4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppTheme.space4),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}

/// A short inline validation/error message with an icon on a soft danger
/// tint — the standard treatment for form errors app-wide (was previously a
/// bare red `Text(...)` per screen, with no consistent shape/spacing).
class InlineErrorBanner extends StatelessWidget {
  const InlineErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space3,
        vertical: AppTheme.space2,
      ),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: AppTheme.space2),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Geometric A mark on a brand plate. No l10n — admin web can use this
/// without [AppLocalizations]. Tinted to [ColorScheme.onPrimaryContainer]
/// so one PNG stays readable on the pale plate (light) and the deep plate
/// (dark).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 56});

  static const String asset = 'assets/branding/app_mark.png';

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(size * 0.26),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: EdgeInsets.all(size * 0.18),
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(
            scheme.onPrimaryContainer,
            BlendMode.srcIn,
          ),
          child: Image.asset(
            asset,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}

/// The brand lockup — mark + wordmark — for first-impression surfaces
/// (onboarding welcome, shop login/register, password reset). Centralized so
/// every entry-flow screen shows the same mark instead of each hand-rolling
/// an `Icon`/`Image` + `Text` pair.
///
/// The geometric A lives in [BrandMark]. The opaque home-screen icon is a
/// sibling file, `assets/branding/app_icon_1024.png`.
class BrandHero extends StatelessWidget {
  const BrandHero({super.key, this.size = 88, this.showName = true});

  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: AppLocalizations.of(context).appTitle,
          child: BrandMark(size: size),
        ),
        if (showName) ...[
          const SizedBox(height: AppTheme.space3),
          Text(
            AppLocalizations.of(context).appTitle,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ],
    );
  }
}

/// Scales and fades [child] in once on mount — a landed-successfully pop
/// (account created, sync finished) rather than the thing just appearing.
/// Plays once; nothing to dispose since [TweenAnimationBuilder] owns its
/// own ticker for the life of this widget.
/// The brand mark on its plate with pulse rings breathing outward from it,
/// over a caption naming what is happening and a track showing how far along
/// it is.
///
/// For waits the user cannot shorten and did not choose — signing in, mainly.
/// A spinner inside a button says only "something is happening"; the anxious
/// question during a sign-in is *did my password work*, which a caption
/// answers and a spinner cannot. The rings exist to make the wait feel
/// tended rather than stalled.
///
/// Deliberately calm rather than playful: this is a screen a shop owner
/// passes through on a bad connection, possibly several times, and a
/// character animation that charms on the first pass grates by the tenth.
/// Deliberately drawn rather than shipped as an asset, too — it costs no
/// bytes, takes the theme's own colours in light and dark, and starts on
/// the first frame instead of decoding a file while the user waits.
///
/// Honours the platform's reduce-motion setting by standing still.
class BrandPulseProgress extends StatefulWidget {
  const BrandPulseProgress({
    super.key,
    required this.icon,
    required this.caption,
    this.stepCount = 0,
    this.stepIndex = 0,
  });

  final IconData icon;

  /// What is happening right now. Changing it cross-fades, so the change
  /// itself reads as progress.
  final String caption;

  /// Number of segments in the track under the caption. 0 hides it — use it
  /// only when the phases are real; a track that moves on a timer is a lie.
  final int stepCount;

  /// Zero-based index of the running segment.
  final int stepIndex;

  @override
  State<BrandPulseProgress> createState() => _BrandPulseProgressState();
}

class _BrandPulseProgressState extends State<BrandPulseProgress>
    with SingleTickerProviderStateMixin {
  static const _plate = 88.0;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Started here, not at construction, because whether it should run at
    // all depends on MediaQuery. A controller left repeating under
    // reduce-motion burns a ticker for a frame nobody sees — and any
    // `pumpAndSettle` on a screen holding one never settles.
    final still = MediaQuery.disableAnimationsOf(context);
    if (still && _c.isAnimating) {
      _c.stop();
    } else if (!still && !_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final still = MediaQuery.disableAnimationsOf(context);

    final plate = Container(
      width: _plate,
      height: _plate,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      alignment: Alignment.center,
      child: Icon(widget.icon, size: 40, color: scheme.onPrimary),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          // Room for the outermost ring at full spread, so the rings are
          // never clipped by a tight parent.
          width: _plate * 2.6,
          height: _plate * 2.6,
          child: still
              ? Center(child: plate)
              : AnimatedBuilder(
                  animation: _c,
                  builder: (context, child) => CustomPaint(
                    painter: _PulseRingPainter(
                      t: _c.value,
                      color: scheme.primary,
                      plate: _plate,
                    ),
                    child: Center(
                      child: Transform.scale(
                        // A shallow breath on the same clock as the rings,
                        // so the mark and its rings read as one movement.
                        scale: 1 + 0.03 * math.sin(_c.value * 2 * math.pi),
                        child: child,
                      ),
                    ),
                  ),
                  child: plate,
                ),
        ),
        const SizedBox(height: AppTheme.space4),
        AnimatedSwitcher(
          duration: AppTheme.motionMedium,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.35),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: Text(
            widget.caption,
            key: ValueKey(widget.caption),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (widget.stepCount > 0) ...[
          const SizedBox(height: AppTheme.space4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.stepCount; i++) ...[
                if (i > 0) const SizedBox(width: AppTheme.space2),
                AnimatedContainer(
                  duration: AppTheme.motionMedium,
                  curve: AppTheme.curveStandard,
                  width: i == widget.stepIndex ? 28 : 16,
                  height: 5,
                  decoration: BoxDecoration(
                    color: i <= widget.stepIndex
                        ? scheme.primary
                        : scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _PulseRingPainter extends CustomPainter {
  const _PulseRingPainter({
    required this.t,
    required this.color,
    required this.plate,
  });

  /// Cycle position, 0→1, shared by every ring.
  final double t;
  final Color color;
  final double plate;

  static const _rings = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final start = plate * 0.62;
    final end = size.width / 2;

    for (var i = 0; i < _rings; i++) {
      // Evenly staggered around the cycle, so one ring is always leaving as
      // another arrives and the movement never has a visible seam.
      final p = (t + i / _rings) % 1.0;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        // Fades out as it spreads; `1 - p` alone left a hard edge at the
        // wrap, so it is squared to land softly on zero.
        ..color = color.withValues(alpha: 0.30 * (1 - p) * (1 - p));
      canvas.drawCircle(centre, start + (end - start) * p, paint);
    }
  }

  @override
  bool shouldRepaint(_PulseRingPainter old) =>
      old.t != t || old.color != color || old.plate != plate;
}

class SuccessPopIn extends StatelessWidget {
  const SuccessPopIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppTheme.motionSlow,
      curve: AppTheme.curveEmphasized,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: t, child: child),
      ),
      child: child,
    );
  }
}

/// Full-bleed brand panel with a soft wave into the page below.
/// **Auth / onboarding / daily-gate only** — never on Sell, Inventory,
/// Orders, Analytics, or Settings. Light mode paints [ColorScheme.primary]
/// (deep forest); dark mode paints [ColorScheme.primaryContainer] so the
/// panel stays a dark green instead of the jade used for on-page accents.
class BrandHeroPanel extends StatelessWidget {
  const BrandHeroPanel({
    super.key,
    required this.icon,
    this.imageUrl,
    this.height = 120,
    this.waveAmplitude = 20,
    this.celebrate = false,
  });

  final IconData icon;

  /// Shop logo URL. When set, the rounded plate shows the photo instead of
  /// [icon]. Failed or in-flight loads keep the icon so an offline morning
  /// open never flashes a broken-image glyph.
  final String? imageUrl;

  /// Content band below the status-bar inset, not counting the wave.
  final double height;

  /// How far the wave dips below [height]. Onboarding uses 20; the daily
  /// gate uses 16 so a screen the owner sees every morning is a touch less
  /// ceremonial.
  final double waveAmplitude;

  /// Pops the icon/logo plate in with [SuccessPopIn] instead of showing it
  /// statically — for a "you're done" moment (e.g. onboarding's signed-in
  /// page), not the default.
  final bool celebrate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final fill = dark ? scheme.primaryContainer : scheme.primary;
    final onFill = dark ? scheme.onPrimaryContainer : scheme.onPrimary;
    final topInset = MediaQuery.paddingOf(context).top;
    final totalHeight = topInset + height + waveAmplitude;
    final url = imageUrl?.trim() ?? '';
    final fallback = Icon(icon, size: 36, color: onFill);
    Widget mark = fallback;
    if (url.isNotEmpty) {
      mark = Image.network(
        url,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        cacheWidth: ProductThumb.cacheWidthFor(
          72,
          MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0,
        ),
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
            wasSynchronouslyLoaded || frame != null ? child : fallback,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    if (celebrate) mark = SuccessPopIn(child: mark);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: ClipPath(
        clipper: _HeroWaveClipper(amplitude: waveAmplitude),
        child: ColoredBox(
          color: fill,
          child: SizedBox(
            width: double.infinity,
            height: totalHeight,
            child: Padding(
              padding: EdgeInsets.only(top: topInset, bottom: waveAmplitude),
              child: Center(
                child: Semantics(
                  label: AppLocalizations.of(context).appTitle,
                  child: Container(
                    width: 72,
                    height: 72,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: onFill.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    ),
                    alignment: Alignment.center,
                    child: mark,
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

class _HeroWaveClipper extends CustomClipper<Path> {
  const _HeroWaveClipper({required this.amplitude});

  final double amplitude;

  @override
  Path getClip(Size size) {
    final trough = size.height - amplitude;
    return Path()
      ..lineTo(0, trough)
      ..quadraticBezierTo(size.width / 2, size.height, size.width, trough)
      ..lineTo(size.width, 0)
      ..close();
  }

  @override
  bool shouldReclip(_HeroWaveClipper old) => old.amplitude != amplitude;
}

/// Centered, width-capped scaffold for auth/entry screens (welcome,
/// login/register, reset password, license activation) — full-bleed page
/// background but content pinned to a comfortable reading width on tablet
/// instead of stretching a login form across a 1024px pane. Scrolls so a
/// long Myanmar form (labels run ~20-40% longer than English) or an open
/// keyboard never overflows.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.child,
    this.appBar,
    this.maxWidth = 440,
  });

  final Widget child;
  final PreferredSizeWidget? appBar;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.space5,
              vertical: AppTheme.space6,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
