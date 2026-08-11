import 'package:flutter/material.dart';

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
            Icon(icon, size: 48, color: colors.muted),
            const SizedBox(height: AppTheme.space3),
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

/// The visual anchor for a product — its photo when one exists, and a
/// **designed initial-letter plate** when one doesn't.
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
      content = Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        // No spinner and no broken-image icon: the plate stands in while the
        // bytes are in flight and stays put if they never arrive, so the tile
        // never changes size or flashes an error glyph mid-sale.
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
            AnimatedSwitcher(
              duration: AppTheme.motionMedium,
              child: wasSynchronouslyLoaded || frame != null ? child : plate,
            ),
        errorBuilder: (_, _, _) => plate,
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
/// Two decisions worth keeping:
/// * **Each chip carries its count**, so an empty category is visible before
///   it is tapped rather than after.
/// * **The bar sizes to its content.** A fixed single-line height is what
///   clips a two-line Myanmar category name at 1.3x text scale.
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
    final scheme = Theme.of(context).colorScheme;
    final muted = AppColors.of(context).muted;

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
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(option.label),
                        const SizedBox(width: AppTheme.space2),
                        Text(
                          '${option.count}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                fontFeatures: AppTheme.tabularFigures,
                                color: option.id == selectedId
                                    ? scheme.onPrimaryContainer
                                    : muted,
                              ),
                        ),
                      ],
                    ),
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

/// A single at-a-glance metric — big value, small label, optional icon and
/// semantic color. Used across Analytics/Equity/Cash Register-style summary
/// grids instead of each screen building its own `Card` + `Column`.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color ?? scheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: tint, size: 20),
              const SizedBox(height: AppTheme.space2),
            ],
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: tint,
              ),
            ),
            const SizedBox(height: AppTheme.space1),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
        children: [
          Text(label, style: style),
          if (isMoney)
            MoneyText(value, style: style, emphasis: emphasis, color: color)
          else
            Text(value, style: style),
        ],
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The brand lockup — mark + wordmark — for first-impression surfaces
/// (onboarding welcome, shop login/register, password reset). Centralized so
/// every entry-flow screen shows the same mark instead of each hand-rolling
/// an `Icon`/`Image` + `Text` pair.
///
/// **The mark is drawn from theme tokens, not from an image asset, on
/// purpose.** `assets/branding/app_icon_1024.png` is a placeholder (a gold
/// glyph on a cream plate) left over from an abandoned palette; painting it
/// into these screens would drop a cream-and-gold rectangle into the middle
/// of an otherwise green-and-white app — a mismatch that reads as unfinished
/// far more loudly than a plain mark does. A soft [ColorScheme.primaryContainer]
/// plate with a storefront glyph recolors correctly in both brightnesses,
/// adds no asset weight to an offline-first build, and keeps the accent
/// subordinate to the screen's actual CTA. When a real logo exists, swapping
/// the [Container] below for an `Image.asset` is a one-widget change and
/// every entry screen picks it up.
class BrandHero extends StatelessWidget {
  const BrandHero({super.key, this.size = 88, this.showName = true});

  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: AppLocalizations.of(context).appTitle,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(size * 0.26),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.storefront_rounded,
              size: size * 0.52,
              color: scheme.onPrimaryContainer,
            ),
          ),
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
