import 'package:flutter/material.dart';

/// Semantic colors not covered by [ColorScheme] — success/warning/danger
/// states and muted (de-emphasized) text/icons. Read via
/// `AppColors.of(context)`. Every screen that hand-rolls a green/red/orange
/// for a status pill or balance should use these instead of a raw [Color].
///
/// Two tiers, deliberately:
/// * the **solid** tone ([success]/[warning]/[danger]) — for text, icons and
///   thin rules directly on a page surface;
/// * the **soft fill** tone ([successSurface]/[warningSurface]/
///   [dangerSurface]) — a pastel wash meant to be used *as a background* with
///   the matching solid tone as its foreground (every pair below is verified
///   ≥4.5:1 against each other). This is the tier status pills and inline
///   banners should use instead of `someColor.withValues(alpha: 0.12)`, which
///   produces a muddy, unpredictable result over a near-black dark surface.
///
/// **[success] must stay visually distinct from [ColorScheme.primary]**, which
/// is now itself green: primary is a *deep, blue-leaning forest* (hue ~157°),
/// success is a *lighter, yellow-leaning leaf* green (hue ~97-100°). ~60° of
/// hue separation plus a clear luminance step is what keeps a "paid" badge
/// from reading as ordinary brand chrome.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.warning,
    required this.danger,
    required this.muted,
    required this.successSurface,
    required this.warningSurface,
    required this.dangerSurface,
    required this.identityFills,
    required this.identityOnFills,
  });

  final Color success;
  final Color warning;
  final Color danger;
  final Color muted;

  /// Pastel fill paired with [success] as its foreground (≥4.5:1).
  final Color successSurface;

  /// Pastel fill paired with [warning] as its foreground (≥4.5:1).
  final Color warningSurface;

  /// Pastel fill paired with [danger] as its foreground (≥4.5:1).
  final Color dangerSurface;

  /// Tonal fills for **identity tiles** — the initial-letter plate shown
  /// wherever a product has no photo (Sell grid card, checkout/cart rows).
  /// Most shops here will never photograph most of their stock, so the
  /// no-photo case is the *normal* case, not an edge case: it has to look
  /// like a designed element, not a hole where an image failed.
  ///
  /// Deliberate constraints on this set:
  /// * **Cool half of the wheel only** (sage / teal / slate-blue / lilac).
  ///   Warm hues are spoken for — orange is [warning], red is [danger],
  ///   yellow-green is [success] — so a product plate can never be misread as
  ///   a status.
  /// * **No [ColorScheme.primaryContainer].** That fill means "selected /
  ///   primary" in this app (nav indicator, selected chip); a grid full of it
  ///   would compete with the one CTA that matters.
  /// * Muted and light (dark: deep and desaturated) so a screen full of
  ///   plates reads as one calm family, while still giving each product a
  ///   stable color the seller can learn to aim for.
  ///
  /// Paired index-for-index with [identityOnFills]; every pair is ≥8:1. Pick
  /// one with [identityTone] rather than indexing directly.
  final List<Color> identityFills;

  /// Foreground (initials) color for the matching [identityFills] entry.
  final List<Color> identityOnFills;

  /// Stable tonal plate for [seed] (use the product name, so the same product
  /// looks the same in the grid and in the cart). Deliberately hashed by hand
  /// rather than via [String.hashCode], which is not guaranteed stable across
  /// runs — a tile that changes color between launches is worse than no color
  /// at all.
  ({Color fill, Color onFill}) identityTone(String seed) {
    if (identityFills.isEmpty) {
      return (fill: muted, onFill: const Color(0xFFFFFFFF));
    }
    var hash = 0;
    for (final unit in seed.trim().codeUnits) {
      hash = (hash * 31 + unit) & 0x1FFFFFFF;
    }
    final i = hash % identityFills.length;
    return (fill: identityFills[i], onFill: identityOnFills[i]);
  }

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  factory AppColors._forBrightness(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return AppColors(
      // Leaf green — deliberately yellower and lighter than the forest-green
      // brand primary so "success" never reads as plain brand chrome.
      // 5.6:1 on white / 9.6:1 on the dark surface.
      success: dark ? const Color(0xFF84CE5E) : const Color(0xFF3B7518),
      // True orange (hue ~30°), kept clear of the yellow/gold band on
      // purpose — this palette has no gold in it. 5.9:1 / 8.2:1.
      warning: dark ? const Color(0xFFF2A65A) : const Color(0xFF9E4E00),
      danger: dark ? const Color(0xFFFFB4AB) : const Color(0xFFB3261E),
      // Neutral grey with the same faint green cast as the surface ramp, so
      // de-emphasized text sits in the palette rather than next to it.
      muted: dark ? const Color(0xFF95A09B) : const Color(0xFF5E6A65),
      successSurface: dark
          ? const Color(0xFF1F3312)
          : const Color(0xFFE3F3D8),
      warningSurface: dark
          ? const Color(0xFF3A2410)
          : const Color(0xFFFDECD9),
      dangerSurface: dark ? const Color(0xFF3A1A17) : const Color(0xFFFBE3E1),
      // sage · teal · slate-blue · lilac — see [identityFills].
      identityFills: dark
          ? const [
              Color(0xFF2C4A3E),
              Color(0xFF154B55),
              Color(0xFF1E3450),
              Color(0xFF322C52),
            ]
          : const [
              Color(0xFFDCE7E1),
              Color(0xFFCFE8EC),
              Color(0xFFD8E2F0),
              Color(0xFFE2DDF0),
            ],
      identityOnFills: dark
          ? const [
              Color(0xFFC5E8D8),
              Color(0xFFB0E9F5),
              Color(0xFFC4D8F2),
              Color(0xFFDCD5F2),
            ]
          : const [
              Color(0xFF1B2E27),
              Color(0xFF04333B),
              Color(0xFF16324F),
              Color(0xFF2F2A55),
            ],
    );
  }

  @override
  AppColors copyWith({
    Color? success,
    Color? warning,
    Color? danger,
    Color? muted,
    Color? successSurface,
    Color? warningSurface,
    Color? dangerSurface,
    List<Color>? identityFills,
    List<Color>? identityOnFills,
  }) => AppColors(
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    muted: muted ?? this.muted,
    successSurface: successSurface ?? this.successSurface,
    warningSurface: warningSurface ?? this.warningSurface,
    dangerSurface: dangerSurface ?? this.dangerSurface,
    identityFills: identityFills ?? this.identityFills,
    identityOnFills: identityOnFills ?? this.identityOnFills,
  );

  static List<Color> _lerpList(List<Color> a, List<Color> b, double t) => [
    for (var i = 0; i < a.length; i++)
      i < b.length ? Color.lerp(a[i], b[i], t)! : a[i],
  ];

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      identityFills: _lerpList(identityFills, other.identityFills, t),
      identityOnFills: _lerpList(identityOnFills, other.identityOnFills, t),
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      successSurface: Color.lerp(successSurface, other.successSurface, t)!,
      warningSurface: Color.lerp(warningSurface, other.warningSurface, t)!,
      dangerSurface: Color.lerp(dangerSurface, other.dangerSurface, t)!,
    );
  }
}

/// Central design-token layer for the whole app — mobile POS tabs, the
/// Flutter Web admin console, and every feature screen. Frontend/UX
/// workstream owns this file.
///
/// This is a **system** file, not a Sell-screen file: every token here has to
/// serve dense data tables (Analytics, P&L), long settings lists, form-heavy
/// editors (product edit, purchase orders) and full-bleed brand/auth surfaces
/// just as well as the Sell/Checkout flow. If a value only makes sense for
/// one screen, it doesn't belong here — style that screen locally instead.
///
/// Brand: **deep forest green on a white / light-neutral surface** — the
/// palette real point-of-sale and accounting products converge on (clean
/// white cards on a barely-tinted grey page, a single saturated accent used
/// only for the one action that matters). Deliberately *not* cream, and
/// deliberately *not* gold: an earlier pass derived the palette from the
/// placeholder app icon and was rejected. Nothing here should be driven by
/// `assets/branding/app_icon_1024.png` — it is a stand-in, not a brand.
///
/// The accent is reserved, not sprayed: [ColorScheme.primary] (`#0F5C3E`,
/// 8.0:1 with white) is for the single primary CTA and the focused/selected
/// state; everything else is neutral. Soft accent surfaces (selected chips,
/// the nav-bar indicator, tint fills) use [ColorScheme.primaryContainer],
/// which is a pale green paired with near-black-green text.
///
/// Typography uses a full custom [TextTheme] (see [_textTheme]) with extra
/// line-height baked in everywhere versus stock Material defaults — Myanmar
/// glyphs (the app's *default* locale, not a fallback case) stack tall
/// diacritics that clip under the tighter stock M3 heights. `NotoSansMyanmar`
/// is registered as a real font family (see `pubspec.yaml`) and wired in
/// per-locale below, with the other script always present as a fallback so
/// mixed-language strings (e.g. a Myanmar customer name while the UI is in
/// English) never render as tofu boxes.
///
/// Depth language: flat cards + a tonal `surfaceContainer*` ladder is the
/// default (cheap Android panels in bad light render drop shadows as muddy
/// smears — tonal elevation reads cleaner). [shadowFloating] is the one
/// deliberate exception, reserved for transient/overlay chrome that should
/// visually lift off the page: dialogs, bottom sheets, snackbars, popup
/// menus, and any custom docked action bar (e.g. Sell's sticky checkout bar).
class AppTheme {
  const AppTheme._();

  // Must track `defaultLocaleCode` in `core/locale_controller.dart`. Kept as
  // a literal (not an import) so this framework-only theme file never
  // depends on the Riverpod-based locale controller.
  static const String _defaultLocaleCode = 'my';
  static const String _fontMyanmar = 'NotoSansMyanmar';

  // ---------------------------------------------------------------------
  // Spacing scale — use these instead of magic numbers for consistency.
  // ---------------------------------------------------------------------
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;
  static const double space6 = 32;

  // ---------------------------------------------------------------------
  // Radius scale, by role — replaces the old single `radius = 12` used for
  // every component regardless of size/purpose.
  // ---------------------------------------------------------------------
  /// Small inline elements: badges, tag pills, inline icon buttons.
  static const double radiusXs = 6;

  /// Form controls: text fields, small/medium buttons.
  static const double radiusSm = 10;

  /// Default container radius: cards, tiles, product grid cells.
  static const double radiusMd = 14;

  /// Large surfaces: bottom sheets, dialogs, modal pages.
  static const double radiusLg = 20;

  /// Fully rounded (stadium) shape: chips, segmented controls, FABs.
  static const double radiusFull = 999;

  /// Deprecated alias for the pre-retrofit single radius token — kept only
  /// so the handful of call sites still using it keep compiling. New code
  /// should pick a role-specific radius above (`radiusMd` is the closest
  /// equivalent).
  static const double radius = radiusMd;

  // ---------------------------------------------------------------------
  // Elevation / depth — flat + tonal surfaces by default; shadow reserved
  // for transient/floating chrome (see class doc).
  // ---------------------------------------------------------------------
  static const double elevationFloating = 6;

  /// Shadow color used behind the [elevationFloating] value above for
  /// standard Material components (dialogs, bottom sheets, snackbars,
  /// popup menus) via `shadowColor:` + `surfaceTintColor: Colors.transparent`
  /// (keeps the brand's crisp white/near-black card color from being washed
  /// out by M3's default tonal-elevation tint).
  static Color shadowColorFor(Brightness brightness) => brightness == Brightness.dark
      ? Colors.black
      : const Color(0xFF0B0F0D);

  /// Explicit [BoxShadow] list for custom (non-Material-elevation) floating
  /// chrome — e.g. Sell's sticky checkout bar docked above the bottom nav,
  /// which is a plain `Container`, not something with a Material `elevation`
  /// knob. Casts upward (negative dy) since these are always bottom-docked.
  static List<BoxShadow> dockedBarShadow(Brightness brightness) => [
    BoxShadow(
      color: shadowColorFor(brightness).withValues(
        alpha: brightness == Brightness.dark ? 0.5 : 0.10,
      ),
      blurRadius: 20,
      offset: const Offset(0, -4),
    ),
  ];

  // ---------------------------------------------------------------------
  // Motion — durations + curves for the micro-interactions that matter
  // (add-to-cart feedback, checkout success, sheet/tab transitions).
  // ---------------------------------------------------------------------
  /// Instant micro-feedback: icon toggles, chip selection, qty steppers.
  static const Duration motionFast = Duration(milliseconds: 120);

  /// Sheet/dialog open-close, tab and page-body cross-fades.
  static const Duration motionMedium = Duration(milliseconds: 220);

  /// Larger state changes that deserve to be noticed: checkout success,
  /// empty-state illustrations settling in.
  static const Duration motionSlow = Duration(milliseconds: 360);

  static const Curve curveStandard = Curves.easeOutCubic;

  /// A touch of overshoot for positive-feedback moments (add-to-cart bump,
  /// success checkmark) — use sparingly, not for routine navigation.
  static const Curve curveEmphasized = Curves.easeOutBack;

  /// The confirm button in a **destructive** dialog (delete a product, a
  /// category, an expense…). Those dialogs previously used a plain
  /// [FilledButton], i.e. the same brand-green affirmative used for "Save" —
  /// so the button that erases a row looked exactly like the button that
  /// keeps one, and the only thing distinguishing them was the label. Sitting
  /// next to a neutral "Cancel", green also reads as the *safe* choice.
  /// Kept here rather than in each screen so every delete confirm in the app
  /// converges on one treatment as later phases pick it up.
  static ButtonStyle dangerFilledButtonStyle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton.styleFrom(
      backgroundColor: scheme.error,
      foregroundColor: scheme.onError,
    );
  }

  // ---------------------------------------------------------------------
  // Tabular figures — every money/qty column in this app is a POS ledger;
  // proportional digits make price columns visibly wobble as amounts
  // change. Apply via `.copyWith(fontFeatures: AppTheme.tabularFigures)` or
  // (preferred) the `MoneyText`/`QtyText` widgets in `app_widgets.dart`.
  // ---------------------------------------------------------------------
  static const List<FontFeature> tabularFigures = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  static ThemeData light({String localeCode = _defaultLocaleCode}) =>
      _base(Brightness.light, localeCode);
  static ThemeData dark({String localeCode = _defaultLocaleCode}) =>
      _base(Brightness.dark, localeCode);

  static ThemeData _base(Brightness brightness, String localeCode) {
    final scheme = _colorScheme(brightness);
    final textTheme = _textTheme(scheme).apply(
      fontFamily: localeCode == 'my' ? _fontMyanmar : null,
      // Always keep the *other* script reachable as a fallback so mixed
      // strings (a Myanmar customer name typed while the UI is in English,
      // or vice versa) never render as tofu boxes.
      fontFamilyFallback: localeCode == 'my'
          ? const ['Roboto']
          : const [_fontMyanmar],
    );

    final shapeMd = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusMd),
    );
    final shapeSm = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusSm),
    );
    final shapeLg = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusLg),
    );
    final shadowColor = shadowColorFor(brightness);

    return ThemeData(
      colorScheme: scheme,
      textTheme: textTheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      extensions: [AppColors._forBrightness(brightness)],
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52), // big tap targets
          shape: shapeSm,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: shapeSm,
          side: BorderSide(color: scheme.outline),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: shapeSm,
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        shadowColor: shadowColor.withValues(alpha: 0.08),
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge,
      ),
      dialogTheme: DialogThemeData(
        shape: shapeLg,
        elevation: elevationFloating,
        shadowColor: shadowColor.withValues(alpha: 0.25),
        surfaceTintColor: Colors.transparent,
        backgroundColor: scheme.surfaceContainerLowest,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: elevationFloating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: scheme.primary,
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: textTheme.titleSmall,
        unselectedLabelStyle: textTheme.titleSmall,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusFull),
        ),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.primaryContainer,
        labelStyle: textTheme.labelLarge?.copyWith(color: scheme.onSurface),
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(
          color: scheme.onPrimaryContainer,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusFull),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: space4,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        elevation: elevationFloating,
        shadowColor: shadowColor.withValues(alpha: 0.25),
        surfaceTintColor: Colors.transparent,
        backgroundColor: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodySmall,
        iconColor: scheme.onSurfaceVariant,
      ),
      popupMenuTheme: PopupMenuThemeData(
        elevation: elevationFloating,
        shadowColor: shadowColor.withValues(alpha: 0.2),
        surfaceTintColor: Colors.transparent,
        color: scheme.surfaceContainerLowest,
        shape: shapeMd,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primaryContainer
              : null,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHigh,
        circularTrackColor: scheme.surfaceContainerHigh,
      ),
    );
  }

  /// The brand green. Deep forest with a slight blue lean (hue ~157°) so it
  /// stays clearly separated from the yellow-leaning semantic
  /// [AppColors.success] green. 8.0:1 against white, i.e. comfortably AA for
  /// white button labels with headroom left for a cheap panel in daylight.
  static const Color _brandGreen = Color(0xFF0F5C3E);

  /// A hand-built, contrast-checked [ColorScheme] for **both** brightnesses —
  /// not an auto-derived one. [ColorScheme.fromSeed] is used only so the
  /// handful of roles nobody styles directly (scrim, shadow, `*Fixed*`
  /// variants) land somewhere harmonious; every role that actually appears
  /// on screen is pinned below.
  ///
  /// Verified pairings (WCAG AA needs 4.5:1 for text, 3:1 for UI edges):
  /// * light `primary #0F5C3E` on white — **8.0:1**
  /// * light `onPrimaryContainer #06301F` on `primaryContainer #C9E9D8` —
  ///   **11.1:1**
  /// * light `onSurfaceVariant #55605B` on `surface #F6F8F7` — **6.1:1**
  /// * dark `primary #4FC08D` on `surface #101512` — **8.1:1**
  /// * dark `onPrimary #00301E` on `primary #4FC08D` — **6.4:1**
  /// * dark `onSurfaceVariant #AEB9B4` on `surface #101512` — **9.1:1**
  ///
  /// The neutrals carry ~2% green chroma rather than being pure grey — enough
  /// that white cards read as *white* against the page, not enough to look
  /// tinted. This is the "clean white card on a very light neutral page" look
  /// that dense POS/accounting UIs converge on; it is explicitly not cream.
  static ColorScheme _colorScheme(Brightness brightness) {
    final base = ColorScheme.fromSeed(
      seedColor: _brandGreen,
      brightness: brightness,
    );

    if (brightness == Brightness.light) {
      return base.copyWith(
        primary: _brandGreen,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFC9E9D8), // pale green accent fill
        onPrimaryContainer: const Color(0xFF06301F),
        secondary: const Color(0xFF3D5A4E), // desaturated green-slate
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFFDCE7E1),
        onSecondaryContainer: const Color(0xFF1B2E27),
        tertiary: const Color(0xFF15616D), // deep teal, for rare 3rd accents
        onTertiary: Colors.white,
        tertiaryContainer: const Color(0xFFCFE8EC),
        onTertiaryContainer: const Color(0xFF04333B),
        error: const Color(0xFFB3261E),
        onError: Colors.white,
        errorContainer: const Color(0xFFFBE3E1),
        onErrorContainer: const Color(0xFF410E0B),
        surface: const Color(0xFFF6F8F7), // light neutral page
        onSurface: const Color(0xFF121815),
        onSurfaceVariant: const Color(0xFF55605B),
        outline: const Color(0xFF7C8A84),
        outlineVariant: const Color(0xFFDCE3DF), // card hairline
        surfaceContainerLowest: Colors.white, // card fill
        surfaceContainerLow: const Color(0xFFF1F4F2),
        surfaceContainer: const Color(0xFFEBEFED),
        surfaceContainerHigh: const Color(0xFFE5EAE7),
        surfaceContainerHighest: const Color(0xFFDFE5E2),
        surfaceBright: Colors.white,
        surfaceDim: const Color(0xFFDCE3DF),
        surfaceTint: _brandGreen,
        inverseSurface: const Color(0xFF2A312E),
        onInverseSurface: const Color(0xFFEFF3F1),
        inversePrimary: const Color(0xFF4FC08D),
      );
    }

    return base.copyWith(
      // Jade — the same hue family as the light primary, lifted to read on a
      // near-black page rather than lightened arbitrarily.
      primary: const Color(0xFF4FC08D),
      onPrimary: const Color(0xFF00301E),
      primaryContainer: const Color(0xFF14503A),
      onPrimaryContainer: const Color(0xFFB9EBD3),
      secondary: const Color(0xFFA9CCBC),
      onSecondary: const Color(0xFF16352A),
      secondaryContainer: const Color(0xFF2C4A3E),
      onSecondaryContainer: const Color(0xFFC5E8D8),
      tertiary: const Color(0xFF8ECDD9),
      onTertiary: const Color(0xFF00363F),
      tertiaryContainer: const Color(0xFF154B55),
      onTertiaryContainer: const Color(0xFFB0E9F5),
      error: const Color(0xFFFFB4AB),
      onError: const Color(0xFF690005),
      errorContainer: const Color(0xFF93000A),
      onErrorContainer: const Color(0xFFFFDAD6),
      surface: const Color(0xFF101512),
      onSurface: const Color(0xFFE3E8E5),
      onSurfaceVariant: const Color(0xFFAEB9B4),
      outline: const Color(0xFF78837E),
      outlineVariant: const Color(0xFF2C3531),
      surfaceContainerLowest: const Color(0xFF0B0F0D), // recessed card fill
      surfaceContainerLow: const Color(0xFF171D1A),
      surfaceContainer: const Color(0xFF1B2320),
      surfaceContainerHigh: const Color(0xFF242C28),
      surfaceContainerHighest: const Color(0xFF2E3733),
      surfaceBright: const Color(0xFF363E3A),
      surfaceDim: const Color(0xFF0B0F0D),
      surfaceTint: const Color(0xFF4FC08D),
      inverseSurface: const Color(0xFFE3E8E5),
      onInverseSurface: const Color(0xFF1B2320),
      inversePrimary: _brandGreen,
    );
  }

  /// Full type scale. Every role is defined (no gaps to fall back to a
  /// generic Material default) with line-heights biased ~10-20% taller than
  /// stock M3 to give Myanmar diacritics (ျ, ့, ဉ, stacked vowel signs)
  /// headroom — applied uniformly to both locales since Myanmar glyphs can
  /// appear in either (customer names, product names) and the extra
  /// breathing room reads as more considered in Latin too, not just "safe".
  static TextTheme _textTheme(ColorScheme scheme) {
    TextStyle s(
      double size,
      FontWeight weight,
      double height, {
      double letterSpacing = 0,
      Color? color,
    }) => TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: color ?? scheme.onSurface,
    );

    return TextTheme(
      displayLarge: s(40, FontWeight.w700, 1.20, letterSpacing: -0.25),
      displayMedium: s(34, FontWeight.w700, 1.22, letterSpacing: -0.25),
      displaySmall: s(28, FontWeight.w700, 1.25),
      headlineLarge: s(26, FontWeight.w700, 1.28),
      headlineMedium: s(23, FontWeight.w700, 1.30),
      headlineSmall: s(20, FontWeight.w700, 1.32),
      titleLarge: s(19, FontWeight.w600, 1.35),
      titleMedium: s(16, FontWeight.w600, 1.40, letterSpacing: 0.1),
      titleSmall: s(14, FontWeight.w600, 1.40, letterSpacing: 0.1),
      bodyLarge: s(16, FontWeight.w400, 1.55, letterSpacing: 0.15),
      bodyMedium: s(14, FontWeight.w400, 1.55, letterSpacing: 0.15),
      bodySmall: s(
        13,
        FontWeight.w400,
        1.55,
        letterSpacing: 0.15,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: s(14, FontWeight.w600, 1.45, letterSpacing: 0.2),
      labelMedium: s(12, FontWeight.w600, 1.45, letterSpacing: 0.3),
      labelSmall: s(11, FontWeight.w600, 1.50, letterSpacing: 0.3),
    );
  }
}
