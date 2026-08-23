import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// A big-button numeric pad for money entry at the counter — 1-9, a "00"
/// key (kyat amounts live in round hundreds; typing three zeros one by one
/// is three chances to miss), 0, and backspace.
///
/// Replaces the OS keyboard on amount fields: the system number pad is
/// small-target and its height/viewport jump mid-checkout is exactly the
/// kind of friction a fast sale can't afford. Keys are full-width thirds at
/// [keyHeight] dp — thumb-sized, no precision needed.
///
/// The parent owns the value; this widget only reports taps. Every press
/// gives a selection-click haptic so a noisy shop confirms input by touch,
/// not just sight.
class NumericKeypad extends StatelessWidget {
  const NumericKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.keyHeight = 52,
  });

  /// Receives `'0'`–`'9'` or `'00'`.
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final double keyHeight;

  void _tap(String digit) {
    HapticFeedback.selectionClick();
    onDigit(digit);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    Widget key({
      String? label,
      VoidCallback? onTap,
      String? semanticLabel,
      IconData? icon,
    }) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space1),
          child: Semantics(
            button: true,
            label: semanticLabel ?? label,
            child: Material(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: SizedBox(
                  height: keyHeight,
                  child: Center(
                    child: icon != null
                        ? Icon(icon, size: 22, color: scheme.onSurface)
                        : Text(
                            label!,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontFeatures: AppTheme.tabularFigures),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(children: [for (final d in row) key(label: d, onTap: () => _tap(d))]),
        Row(
          children: [
            key(label: '00', onTap: () => _tap('00')),
            key(label: '0', onTap: () => _tap('0')),
            key(
              icon: Icons.backspace_outlined,
              semanticLabel: l.commonDelete,
              onTap: () {
                HapticFeedback.selectionClick();
                onBackspace();
              },
            ),
          ],
        ),
      ],
    );
  }
}
