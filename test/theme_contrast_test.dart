import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/theme/app_theme.dart';

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return (math.max(a, b) + .05) / (math.min(a, b) + .05);
}

void main() {
  for (final dark in [false, true]) {
    test(
      '${dark ? 'dark' : 'light'} palette keeps labels and status text readable',
      () {
        final theme = dark ? AppTheme.dark() : AppTheme.light();
        final s = theme.colorScheme;
        final c = theme.extension<AppColors>()!;
        final pairs = <String, (Color, Color)>{
          'body on page': (s.onSurface, s.surface),
          'secondary on page': (s.onSurfaceVariant, s.surface),
          'body on card': (s.onSurface, s.surfaceContainerLowest),
          'secondary on card': (s.onSurfaceVariant, s.surfaceContainerLowest),
          'primary button': (s.onPrimary, s.primary),
          'selected navigation': (s.onPrimaryContainer, s.primaryContainer),
          'success badge': (c.success, c.successSurface),
          'warning badge': (c.warning, c.warningSurface),
          'danger badge': (c.danger, c.dangerSurface),
          'neutral badge': (c.muted, c.neutralSurface),
          'product initial': (c.identityOnFills.first, c.identityFills.first),
        };
        for (final entry in pairs.entries) {
          expect(
            _contrast(entry.value.$1, entry.value.$2),
            greaterThanOrEqualTo(4.5),
            reason: entry.key,
          );
        }
      },
    );
  }
}
