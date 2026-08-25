import 'package:flutter/material.dart';

import '../../core/layout.dart';
import '../../core/theme/app_theme.dart';

/// One selectable row of an [AppPickerField].
class PickerOption<T> {
  const PickerOption({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// The ordered "tap the arrow → pick from the list" chooser used across the
/// printer settings screens (connection type, paper size, label size).
/// Bottom sheet on phones, centered dialog on tablets — [showAppModal].
///
/// Returns the chosen value, or null when dismissed without choosing.
Future<T?> showAppPickerSheet<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  required List<PickerOption<T>> options,
  T? selected,
}) {
  return showAppModal<T>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
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
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space4,
                0,
                AppTheme.space4,
                AppTheme.space2,
              ),
              child: Text(
                subtitle,
                style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                  color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final option in options)
            ListTile(
              leading:
                  option.icon != null ? Icon(option.icon) : null,
              title: Text(option.label),
              trailing:
                  option.value == selected
                      ? Icon(
                        Icons.check_circle,
                        color: AppColors.of(sheetContext).success,
                      )
                      : null,
              onTap: () => Navigator.pop(sheetContext, option.value),
            ),
          const SizedBox(height: AppTheme.space2),
        ],
      ),
    ),
  );
}

/// A read-only field styled like an outlined text input whose current value
/// ends in a drop-down arrow; tapping opens the ordered option list
/// ([showAppPickerSheet]) to choose from. Replaces segmented buttons wherever
/// the choice list may grow or the shop just wants the familiar picker flow.
class AppPickerField<T> extends StatelessWidget {
  const AppPickerField({
    super.key,
    required this.label,
    required this.options,
    required this.onChanged,
    this.value,
    this.enabled = true,
  });

  final String label;
  final List<PickerOption<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final bool enabled;

  Future<void> _pick(BuildContext context) async {
    if (!enabled) return;
    final picked = await showAppPickerSheet<T>(
      context: context,
      title: label,
      options: options,
      selected: value,
    );
    if (picked == null || picked == value) return;
    onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    PickerOption<T>? current;
    for (final option in options) {
      if (option.value == value) current = option;
    }

    return Material(
      color: enabled ? scheme.surface : scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        onTap: enabled ? () => _pick(context) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.space3,
            vertical: AppTheme.space2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (current?.icon != null) ...[
                          Icon(current!.icon, size: 18),
                          const SizedBox(width: AppTheme.space2),
                        ],
                        Flexible(
                          child: Text(
                            current?.label ?? '—',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                color: enabled ? scheme.onSurfaceVariant : scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
