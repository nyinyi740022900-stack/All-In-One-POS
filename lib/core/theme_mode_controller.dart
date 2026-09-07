import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/printing/printing_providers.dart';

/// The three choices offered in Settings, in the order they are shown.
const supportedThemeModes = {'system', 'light', 'dark'};

/// Follow the phone until the owner says otherwise — the behaviour every
/// build before this one had, so nobody's app changes appearance on upgrade.
const defaultThemeModeCode = 'system';

ThemeMode themeModeFromCode(String code) => switch (code) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

/// Holds the light/dark preference and persists it, so it is stable across
/// launches. Mirrors [LocaleController] deliberately — both are device-global
/// display settings that `MaterialApp` reads on every build.
///
/// `AppTheme` has had a full hand-pinned dark palette since the design pass,
/// and `app.dart` has always passed both `theme:` and `darkTheme:` — but no
/// `themeMode:`, so Flutter defaulted to [ThemeMode.system] and the phone's
/// setting was the only input. That left a shopkeeper whose phone lives in
/// dark mode unable to put the POS in light for a sunlit stall (or to match
/// the paper receipt they are reading beside it). This adds the missing third
/// input without changing what an existing install does.
class ThemeModeController extends StateNotifier<String> {
  ThemeModeController(this._ref) : super(defaultThemeModeCode) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    final saved = await _ref.read(settingsRepositoryProvider).savedThemeMode();
    if (saved != null && supportedThemeModes.contains(saved)) {
      state = saved;
    }
  }

  Future<void> set(String code) async {
    if (!supportedThemeModes.contains(code)) return;
    state = code;
    await _ref.read(settingsRepositoryProvider).saveThemeMode(code);
  }
}

final themeModeControllerProvider =
    StateNotifierProvider<ThemeModeController, String>((ref) {
  return ThemeModeController(ref);
});
