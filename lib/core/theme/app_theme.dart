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
///   [dangerSurface]/[neutralSurface]) — a pastel wash meant to be used *as a
///   background* with the matching solid tone as its foreground (every pair
///   below is verified ≥4.5:1 against each other). This is the tier status
///   pills and inline banners should use instead of
///   `someColor.withValues(alpha: 0.12)`, which produces a muddy,
///   unpredictable result over a near-black dark surface. `StatusPill` in
///   `core/widgets/app_widgets.dart` is the component built on it — prefer
///   that over reaching for these directly.
///
/// **[success] must stay visually distinct from [ColorScheme.primary]**:
/// primary is a saturated royal blue (hue ~218°), success a fresh emerald/mint
/// green (hue ~155°). ~60° of hue separation is what keeps a "paid" badge
/// from reading as ordinary action-colour chrome.
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
    required this.neutralSurface,
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

  /// Quiet fill paired with [muted] as its foreground (4.6:1 light / 5.3:1
  /// dark) — the *fourth* tier of the soft-fill set, for a status that is
  /// neither good nor bad but **done with**: a cancelled order, a voided
  /// invoice, an inactive account. Without it, a pill component has to fall
  /// back to `ColorScheme.surfaceContainerHigh`, which means the one widget
  /// resolving status colors needs a [ColorScheme] as well as an [AppColors]
  /// — and can then no longer be pointed at a fixed palette for the
  /// theme-independent document surfaces (see [onLightDocument]).
  final Color neutralSurface;

  /// Neutral plate for **identity tiles** — the small initial shown wherever a
  /// product (or a person) has no photo.
  ///
  /// Was a four-colour pastel family (steel / periwinkle / lilac / mist-teal);
  /// as big slabs across the Sell grid those read as washed-out and muddy, so
  /// the family collapsed to ONE neutral grey-navy plate with a muted initial.
  /// The list shape is kept so [identityTone] callers (Sell, Inventory,
  /// customers, the signed-in avatar) keep compiling.
  ///
  /// Light 5.0:1 (`#5B6785` on `#F3F5F8`), dark 6.9:1.
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

  /// The **light** semantic palette, resolved without a [BuildContext].
  ///
  /// Only for the deliberately theme-independent "document" surfaces —
  /// `InvoiceView`, which paints a fixed-width white invoice card that gets
  /// captured as a PNG to share with a customer (and is also rendered by the
  /// web invoice page). That widget lives inside the app's own [Overlay]
  /// during capture, so `AppColors.of(context)` there returns the *dark*
  /// palette whenever the shopkeeper's phone is in dark mode — which would
  /// stamp a near-black pastel and a pale-green label onto a white document.
  /// Everything that actually renders as app chrome must use [of].
  static final AppColors onLightDocument = AppColors._forBrightness(
    Brightness.light,
  );

  factory AppColors._forBrightness(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return AppColors(
      // Fresh emerald (hue ~155°), ~60° away from the royal-blue action
      // colour (hue ~218°) so a "paid" badge never reads as brand chrome.
      // 5.3:1 on white / 9.4:1 on the dark card.
      success: dark ? const Color(0xFF4FD69A) : const Color(0xFF0B7F4E),
      // True orange (hue ~30°), kept clear of the yellow/gold band on
      // purpose — this palette has no gold in it. 6.3:1 / 8.9:1.
      warning: dark ? const Color(0xFFF2A65A) : const Color(0xFF9A4A00),
      danger: dark ? const Color(0xFFFFB4AB) : const Color(0xFFB3261E),
      // Grey-navy secondary text, same cast as the ink. 5.6:1 on white /
      // 7.8:1 on the dark card.
      muted: dark ? const Color(0xFFA3AEC6) : const Color(0xFF5B6785),
      successSurface: dark ? const Color(0xFF12352A) : const Color(0xFFE3F6EC),
      warningSurface: dark ? const Color(0xFF3A2410) : const Color(0xFFFDEBD6),
      dangerSurface: dark ? const Color(0xFF3A1A17) : const Color(0xFFFBE3E1),
      // A neutral grey step (no blue cast) for a "done with" pill.
      neutralSurface: dark ? const Color(0xFF1D2943) : const Color(0xFFEEF1F5),
      // One neutral plate, not a pastel family — see [identityFills].
      identityFills: dark
          ? const [Color(0xFF18233A)]
          : const [Color(0xFFF3F5F8)],
      identityOnFills: dark
          ? const [Color(0xFFA3AEC6)]
          : const [Color(0xFF5B6785)],
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
    Color? neutralSurface,
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
    neutralSurface: neutralSurface ?? this.neutralSurface,
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
      neutralSurface: Color.lerp(neutralSurface, other.neutralSurface, t)!,
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
/// Brand (v3b, 2026-10-02): **navy ink + ONE saturated royal blue on pure
/// white.** Text is deep navy (`onSurface #0B1530`), never black; the single
/// colour is a vivid royal blue ([ColorScheme.primary] `#1F65D6`, 5.4:1 with
/// white) reserved for the one primary action, links and the selected state.
/// Page and cards are both pure white, separated by crisp `#E3E7EE` hairlines
/// rather than tinted blocks; no pastel fills. Shapes are tight (6-8px).
/// Green means exactly one thing: [AppColors.success].
///
/// Soft accent surfaces (selected chips, the nav-bar indicator) use
/// [ColorScheme.primaryContainer], a very pale blue with deep-blue text.
///
/// Typography uses a full custom [TextTheme] (see [_textTheme]) in bundled
/// **Inter** (Latin + numerals, tabular figures via `tnum`) with
/// `NotoSansMyanmar` for Myanmar script, with extra
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
  static const String _defaultLocaleCode = 'en';
  static const String _fontMyanmar = 'NotoSansMyanmar';
  static const String _fontLatin = 'Inter';

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
  static const double radiusXs = 4;

  /// Form controls: text fields, small/medium buttons.
  static const double radiusSm = 6;

  /// Default container radius: cards, tiles, product grid cells.
  static const double radiusMd = 8;

  /// Large surfaces: bottom sheets, dialogs, modal pages.
  static const double radiusLg = 12;

  /// Fully rounded (stadium) shape: ONLY chips/pills/badges and avatars —
  /// never a button.
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
  static Color shadowColorFor(Brightness brightness) =>
      brightness == Brightness.dark ? Colors.black : const Color(0xFF0B1226);

  /// Explicit [BoxShadow] list for custom (non-Material-elevation) floating
  /// chrome — e.g. Sell's sticky checkout bar docked above the bottom nav,
  /// which is a plain `Container`, not something with a Material `elevation`
  /// knob. Casts upward (negative dy) since these are always bottom-docked.
  static List<BoxShadow> dockedBarShadow(Brightness brightness) => [
    BoxShadow(
      color: shadowColorFor(
        brightness,
      ).withValues(alpha: brightness == Brightness.dark ? 0.4 : 0.06),
      blurRadius: 12,
      offset: const Offset(0, -2),
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

  /// Taller (52dp) filled CTA for **auth / onboarding / daily-gate**. Same
  /// [radiusSm] corner as every other button — the stadium pill was retired
  /// with the green identity; only the name is kept so call sites stay put.
  static ButtonStyle authFilledButtonStyle({
    Size minimumSize = const Size.fromHeight(52),
  }) => FilledButton.styleFrom(
    minimumSize: minimumSize,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
  );

  /// Matching outlined — secondary auth actions ("Activate a license
  /// key", "Sign up") sitting under a stadium primary.
  static ButtonStyle authOutlinedButtonStyle() => OutlinedButton.styleFrom(
    minimumSize: const Size.fromHeight(52),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
  );

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
      // Inter leads in English (and for ASCII digits/money in Myanmar via the
      // fallback); NotoSansMyanmar leads when the UI is Myanmar so its
      // vertical metrics, not Inter's, size every Myanmar line box.
      fontFamily: localeCode == 'my' ? _fontMyanmar : _fontLatin,
      // Always keep the *other* script reachable as a fallback so mixed
      // strings (a Myanmar customer name typed while the UI is in English,
      // or vice versa) never render as tofu boxes.
      fontFamilyFallback: localeCode == 'my'
          ? const [_fontLatin]
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
          shape: shapeMd,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: shapeMd,
          side: BorderSide(color: scheme.outline),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: shapeMd,
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
        // Hairline, not a shadow, when content scrolls under the bar.
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
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
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(shape: WidgetStatePropertyAll(shapeSm)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        // The one primary action: solid action blue, not a pale container.
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        highlightElevation: 3,
        shape: shapeMd,
        extendedTextStyle: textTheme.labelLarge,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
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
          (states) =>
              states.contains(WidgetState.selected) ? scheme.primary : null,
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

  /// The single action colour. Saturated royal blue (hue ~218°), 5.4:1
  /// against white — AA for white button labels — and ~60° of hue away from
  /// [AppColors.success] green.
  static const Color _actionBlue = Color(0xFF1F65D6);

  /// Navy ink — body/heading text in light mode. 18.0:1 on white.
  static const Color _inkNavy = Color(0xFF0B1530);

  /// A hand-built, contrast-checked [ColorScheme] for **both** brightnesses.
  /// [ColorScheme.fromSeed] is used only so the roles nobody styles directly
  /// (scrim, shadow, `*Fixed*` variants) land somewhere harmonious; every
  /// role that appears on screen is pinned below.
  ///
  /// Measured pairings (WCAG AA: 4.5:1 text, 3:1 UI edges):
  /// * light `onSurface #0B1530` on white page/card — **18.0:1**
  /// * light `onSurfaceVariant #5B6785` on white — **5.6:1**
  /// * light `onPrimary` white on `primary #1F65D6` — **5.4:1**
  /// * light `primary` on white — **5.4:1**; on `primaryContainer #E8F0FD` 4.8
  /// * light `onPrimaryContainer #0E2F6E` on its container — **11.3:1**
  /// * light `outline #7C879E` on white — **3.6:1** (button edges)
  /// * dark `onSurface #EEF2FA` on page `#0B1220` — **16.7:1**, on card 15.5
  /// * dark `onSurfaceVariant #A3AEC6` on page — **8.4:1**, on card 7.8
  /// * dark `primary #6EA2FF` on page — **7.4:1**, on card 6.8;
  ///   `onPrimary #06183F` on it 6.8
  /// * dark `onPrimaryContainer #DCE8FF` on `#1B3A7A` — **8.8:1**
  static ColorScheme _colorScheme(Brightness brightness) {
    final base = ColorScheme.fromSeed(
      seedColor: _actionBlue,
      brightness: brightness,
    );

    if (brightness == Brightness.light) {
      return base.copyWith(
        primary: _actionBlue,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFE8F0FD),
        onPrimaryContainer: const Color(0xFF0E2F6E),
        secondary: const Color(0xFF3B4A6B), // slate navy
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFFEEF1F5),
        onSecondaryContainer: const Color(0xFF1A2744),
        tertiary: const Color(0xFF4A4F9E), // indigo, for rare 3rd accents
        onTertiary: Colors.white,
        tertiaryContainer: const Color(0xFFE6E8F8),
        onTertiaryContainer: const Color(0xFF25255A),
        error: const Color(0xFFB3261E),
        onError: Colors.white,
        errorContainer: const Color(0xFFFBE3E1),
        onErrorContainer: const Color(0xFF410E0B),
        surface: Colors.white, // pure white page
        onSurface: _inkNavy,
        onSurfaceVariant: const Color(0xFF5B6785),
        outline: const Color(0xFF7C879E),
        outlineVariant: const Color(0xFFE3E7EE), // crisp hairline
        surfaceContainerLowest: Colors.white, // card fill
        surfaceContainerLow: const Color(0xFFF8F9FB),
        surfaceContainer: const Color(0xFFF4F6F8),
        surfaceContainerHigh: const Color(0xFFEFF2F5),
        surfaceContainerHighest: const Color(0xFFE9ECF1),
        surfaceBright: Colors.white,
        surfaceDim: const Color(0xFFE3E7EE),
        surfaceTint: _actionBlue,
        inverseSurface: const Color(0xFF0B1530),
        onInverseSurface: const Color(0xFFF3F5F8),
        inversePrimary: const Color(0xFF6EA2FF),
      );
    }

    return base.copyWith(
      primary: const Color(0xFF6EA2FF),
      onPrimary: const Color(0xFF06183F),
      primaryContainer: const Color(0xFF1B3A7A),
      onPrimaryContainer: const Color(0xFFDCE8FF),
      secondary: const Color(0xFFB4C0DA),
      onSecondary: const Color(0xFF1A2744),
      secondaryContainer: const Color(0xFF1D2943),
      onSecondaryContainer: const Color(0xFFD5DDEE),
      tertiary: const Color(0xFFB4B8F2),
      onTertiary: const Color(0xFF25255A),
      tertiaryContainer: const Color(0xFF2B2D5C),
      onTertiaryContainer: const Color(0xFFD2D3F5),
      error: const Color(0xFFFFB4AB),
      onError: const Color(0xFF690005),
      errorContainer: const Color(0xFF93000A),
      onErrorContainer: const Color(0xFFFFDAD6),
      surface: const Color(0xFF0B1220),
      onSurface: const Color(0xFFEEF2FA),
      onSurfaceVariant: const Color(0xFFA3AEC6),
      outline: const Color(0xFF7B87A2),
      outlineVariant: const Color(0xFF263350), // hairline
      surfaceContainerLowest: const Color(0xFF111A2E), // raised card fill
      surfaceContainerLow: const Color(0xFF141E34),
      surfaceContainer: const Color(0xFF18233C),
      surfaceContainerHigh: const Color(0xFF1D2943),
      surfaceContainerHighest: const Color(0xFF243250),
      surfaceBright: const Color(0xFF2B3A5A),
      surfaceDim: const Color(0xFF0B1220),
      surfaceTint: const Color(0xFF6EA2FF),
      inverseSurface: const Color(0xFFEEF2FA),
      onInverseSurface: const Color(0xFF18233C),
      inversePrimary: _actionBlue,
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

    // Steeper than step 1: headings 700 and large, body 400 in the calmer
    // grey-navy [ColorScheme.onSurfaceVariant] where it is secondary text.
    // Letter-spacing is 0 on body: Inter is already spaced for text sizes.
    return TextTheme(
      displayLarge: s(44, FontWeight.w700, 1.18, letterSpacing: -0.8),
      displayMedium: s(38, FontWeight.w700, 1.20, letterSpacing: -0.6),
      displaySmall: s(32, FontWeight.w700, 1.22, letterSpacing: -0.4),
      headlineLarge: s(28, FontWeight.w700, 1.26, letterSpacing: -0.3),
      headlineMedium: s(24, FontWeight.w700, 1.28, letterSpacing: -0.2),
      headlineSmall: s(21, FontWeight.w700, 1.30, letterSpacing: -0.1),
      titleLarge: s(20, FontWeight.w700, 1.35, letterSpacing: -0.1),
      titleMedium: s(16, FontWeight.w600, 1.42),
      titleSmall: s(14, FontWeight.w600, 1.42),
      bodyLarge: s(16, FontWeight.w400, 1.55),
      bodyMedium: s(14, FontWeight.w400, 1.55),
      bodySmall: s(
        13,
        FontWeight.w400,
        1.55,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: s(14, FontWeight.w600, 1.45, letterSpacing: 0.1),
      labelMedium: s(12, FontWeight.w600, 1.45, letterSpacing: 0.2),
      labelSmall: s(11, FontWeight.w600, 1.50, letterSpacing: 0.2),
    );
  }
}
