import 'package:flutter/material.dart';

/// Width buckets for phone vs tablet layouts.
///
/// - [compact]: &lt; 640 — bottom nav, single-column features
/// - [medium]: 640–1023 — NavigationRail + split panes
/// - [expanded]: ≥ 1024 — wider pane ratios
enum AppWidthClass { compact, medium, expanded }

const double kAppCompactMaxWidth = 640;
const double kAppExpandedMinWidth = 1024;

/// Pure helper (unit-testable without a [BuildContext]).
AppWidthClass widthClassFor(double width) {
  if (width < kAppCompactMaxWidth) return AppWidthClass.compact;
  if (width < kAppExpandedMinWidth) return AppWidthClass.medium;
  return AppWidthClass.expanded;
}

AppWidthClass widthClassOf(BuildContext context) =>
    widthClassFor(MediaQuery.sizeOf(context).width);

bool isCompact(BuildContext context) =>
    widthClassOf(context) == AppWidthClass.compact;

bool isMediumPlus(BuildContext context) => !isCompact(context);

/// Fraction of the row given to the trailing pane (cart / detail).
double trailingPaneFlex(BuildContext context) =>
    widthClassOf(context) == AppWidthClass.expanded ? 0.38 : 0.42;

/// Modal that is a bottom sheet on phones and a constrained dialog on tablets.
Future<T?> showAppModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool showDragHandle = true,
}) {
  if (isMediumPlus(context)) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
          child: Material(
            type: MaterialType.card,
            child: builder(ctx),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    showDragHandle: showDragHandle,
    builder: builder,
  );
}

/// Caps content width on very wide screens (Settings-style lists).
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 720});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (isCompact(context)) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
