import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

/// How strong a candidate password looks, judged by simple, explainable
/// heuristics (length + character variety) — not a full entropy estimate,
/// just enough to nudge a shop owner away from a 4-digit PIN-style password
/// when creating a real login. Never blocks submission on its own; a weak
/// password can still be saved.
enum PasswordStrength { empty, weak, fair, good, strong }

/// Pure, so it's directly testable without a widget: length crosses two
/// thresholds (8, 12) and character variety crosses three (digit,
/// lower+upper mix, symbol) — capped at 4 points, mapped to the 5 levels.
PasswordStrength computePasswordStrength(String password) {
  if (password.isEmpty) return PasswordStrength.empty;
  var score = 0;
  if (password.length >= 8) score++;
  if (password.length >= 12) score++;
  if (RegExp(r'\d').hasMatch(password)) score++;
  if (RegExp(r'[a-z]').hasMatch(password) &&
      RegExp(r'[A-Z]').hasMatch(password)) {
    score++;
  }
  if (RegExp(r'[^a-zA-Z0-9]').hasMatch(password)) score++;
  return switch (score.clamp(0, 4)) {
    0 => PasswordStrength.weak,
    1 => PasswordStrength.weak,
    2 => PasswordStrength.fair,
    3 => PasswordStrength.good,
    _ => PasswordStrength.strong,
  };
}

/// A 4-segment strength bar + label, live-updating as the user types — the
/// standard "growing colored line" pattern for a new-password field. Reads
/// [controller] directly (no external state needed) via [AnimatedBuilder];
/// callers just drop this under a password [TextField] that shares the same
/// controller. Renders nothing (zero height) while the field is empty, so it
/// doesn't shift layout for a screen that never touches the field.
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final strength = computePasswordStrength(controller.text);
        if (strength == PasswordStrength.empty) {
          return const SizedBox.shrink();
        }
        final l = AppLocalizations.of(context);
        final scheme = Theme.of(context).colorScheme;
        final colors = AppColors.of(context);
        // Semantic tokens, not raw `Colors.orange/amber/green`: the raw
        // palette wasn't contrast-checked against either surface, and its
        // amber step sat in the gold band this brand deliberately avoids.
        // "good" reuses the warning tone at a wider fill rather than adding a
        // fourth hue nobody else in the app uses.
        final (filled, color, label) = switch (strength) {
          PasswordStrength.empty => (0, scheme.outlineVariant, ''),
          PasswordStrength.weak => (1, colors.danger, l.passwordStrengthWeak),
          PasswordStrength.fair => (2, colors.warning, l.passwordStrengthFair),
          PasswordStrength.good => (3, colors.warning, l.passwordStrengthGood),
          PasswordStrength.strong => (
            4,
            colors.success,
            l.passwordStrengthStrong,
          ),
        };
        return Padding(
          padding: const EdgeInsets.only(top: AppTheme.space2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: List.generate(4, (i) {
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                      decoration: BoxDecoration(
                        color: i < filled ? color : scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: AppTheme.space1),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: color),
              ),
            ],
          ),
        );
      },
    );
  }
}
