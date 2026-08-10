import 'package:flutter/material.dart';

/// Semantic colors not covered by [ColorScheme] — success/warning/danger
/// states and muted (de-emphasized) text/icons. Read via
/// `AppColors.of(context)`. Every screen that hand-rolls a green/red/orange
/// for a status pill or balance should use these instead of a raw [Color].
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.warning,
    required this.danger,
    required this.muted,
  });

  final Color success;
  final Color warning;
  final Color danger;
  final Color muted;

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  factory AppColors._forBrightness(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return AppColors(
      success: dark ? const Color(0xFF7BC67E) : const Color(0xFF2E7D32),
      warning: dark ? const Color(0xFFFFB74D) : const Color(0xFFB25E00),
      danger: dark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828),
      muted: dark ? const Color(0xFFAAAAAA) : const Color(0xFF6B6B6B),
    );
  }

  @override
  AppColors copyWith({
    Color? success,
    Color? warning,
    Color? danger,
    Color? muted,
  }) => AppColors(
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    muted: muted ?? this.muted,
  );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
    );
  }
}

/// Central theme tokens for the app. Frontend/UX workstream owns this file.
///
/// Uses Material 3 with a seed color tuned for retail (calm teal/green,
/// readable on cheap panels). Typography falls back to the platform's
/// Myanmar-capable font (Noto Sans Myanmar / Pyidaungsu) when locale is `my`.
///
/// Component themes below (app bar, dialog, snack bar, tabs, nav bar, chip,
/// divider, bottom sheet) exist so screens get a consistent look for free —
/// prefer adding/adjusting a token here over a per-screen style override.
class AppTheme {
  const AppTheme._();

  static const Color _seed = Color(0xFF00695C); // teal 800

  // Spacing scale — use these instead of magic numbers for consistency.
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;
  static const double space6 = 32;

  static const double radius = 12;

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      extensions: [AppColors._forBrightness(brightness)],
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52), // big tap targets
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: shape,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        filled: true,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: true,
      ),
      dialogTheme: DialogThemeData(shape: shape),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(space2),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: scheme.primary,
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(space5),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: space4,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
        ),
      ),
    );
  }
}
