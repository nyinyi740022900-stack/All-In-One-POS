import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/theme/app_theme.dart';
import 'package:mm_pos/core/widgets/app_widgets.dart';

double _contrast(Color a, Color b) =>
    (math.max(a.computeLuminance(), b.computeLuminance()) + .05) /
    (math.min(a.computeLuminance(), b.computeLuminance()) + .05);

void main() {
  for (final dark in [false, true]) {
    final theme = dark ? AppTheme.dark() : AppTheme.light();
    final s = theme.colorScheme;
    final prefix = dark ? 'dark' : 'light';
    test('$prefix disabled selection uses switch defaults', () {
      const disabled = {WidgetState.disabled, WidgetState.selected};
      expect(theme.switchTheme.thumbColor!.resolve(disabled), isNull);
      expect(theme.switchTheme.trackColor!.resolve(disabled), isNull);
      expect(
        theme.switchTheme.thumbColor!.resolve({WidgetState.selected}),
        s.primary,
      );
    });

    testWidgets('$prefix selected segment palette and interaction contrast', (
      tester,
    ) async {
      var selected = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('Today')),
                  ButtonSegment(value: 2, label: Text('7 days')),
                ],
                selected: {selected},
                onSelectionChanged: (v) => setState(() => selected = v.first),
              ),
            ),
          ),
        ),
      );
      final finder = find
          .descendant(
            of: find.byType(SegmentedButton<int>),
            matching: find.byType(TextButton),
          )
          .first;
      final button = tester.widget<TextButton>(finder);
      final style = TextButtonTheme.of(
        tester.element(finder),
      ).style!.merge(button.style);
      for (final state in [
        WidgetState.selected,
        WidgetState.pressed,
        WidgetState.focused,
        WidgetState.hovered,
      ]) {
        final states = {WidgetState.selected, state};
        final bg = style.backgroundColor!.resolve(states)!;
        final fg = style.foregroundColor!.resolve(states)!;
        final overlay = style.overlayColor!.resolve(states);
        expect(bg, s.primaryContainer);
        expect(fg, s.onPrimaryContainer);
        expect(
          _contrast(fg, Color.alphaBlend(overlay ?? Colors.transparent, bg)),
          greaterThanOrEqualTo(4.5),
        );
      }
      Focus.of(tester.element(find.text('Today'))).requestFocus();
      await tester.pump();
      final selectedPress = await tester.startGesture(tester.getCenter(find.text('Today')));
      await tester.pump(const Duration(milliseconds: 100));
      final selectedText = tester.widget<RichText>(find.descendant(of: find.text('Today'), matching: find.byType(RichText)));
      expect(selectedText.text.style?.color, s.onPrimaryContainer);
      await selectedPress.up();
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('7 days')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(selected, 1);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selected, 2);
    });

    testWidgets('$prefix chips and navigation use selected foreground', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                ChoiceChip(
                  label: const Text('Category'),
                  selected: true,
                  onSelected: (_) {},
                ),
                FilterChip(
                  label: const Text('Filter'),
                  selected: true,
                  onSelected: (_) {},
                ),
                NavigationBar(
                  selectedIndex: 0,
                  onDestinationSelected: (_) {},
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.store),
                      label: 'Sell',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.inventory),
                      label: 'Inventory',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      for (final label in ['Category', 'Filter', 'Sell']) {
        final rendered = tester.widget<RichText>(
          find.descendant(
            of: find.text(label),
            matching: find.byType(RichText),
          ),
        );
        expect(rendered.text.style?.color, s.onPrimaryContainer, reason: label);
      }
      final icon = find.byIcon(Icons.store);
      expect(IconTheme.of(tester.element(icon)).color, s.onPrimaryContainer);
      expect(
        _contrast(s.onPrimaryContainer, s.primaryContainer),
        greaterThanOrEqualTo(4.5),
      );
    });

    testWidgets('$prefix rail selection and disabled taps', (tester) async {
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: 0,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (_) {},
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.store),
                      label: Text('Sell'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.inventory),
                      label: Text('Inventory'),
                    ),
                  ],
                ),
                Expanded(
                  child: Column(
                    children: [
                      const Switch(value: true, onChanged: null),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 1, label: Text('Disabled')),
                          ButtonSegment(value: 2, label: Text('Other')),
                        ],
                        selected: const {1},
                      ),
                      ChoiceChip(
                        label: const Text('Disabled chip'),
                        selected: true,
                        onSelected: null,
                      ),
                      Switch(value: true, onChanged: (_) => changes++),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        DefaultTextStyle.of(tester.element(find.text('Sell'))).style.color,
        s.onPrimaryContainer,
      );
      expect(
        IconTheme.of(tester.element(find.byIcon(Icons.store))).color,
        s.onPrimaryContainer,
      );
      final disabledChipLabel = tester.widget<RichText>(
        find.descendant(
          of: find.text('Disabled chip'),
          matching: find.byType(RichText),
        ),
      );
      expect(disabledChipLabel.text.style?.color, s.onSurface);
      expect(disabledChipLabel.text.style?.color, isNot(s.onPrimaryContainer));
      await tester.tap(find.byType(Switch).first);
      await tester.tap(find.text('Disabled'));
      await tester.tap(find.text('Disabled chip'));
      await tester.pump();
      expect(changes, 0);
      await tester.tap(find.byType(Switch).last);
      await tester.pump();
      expect(changes, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$prefix busy buttons keep visible spinner and reject taps', (
      tester,
    ) async {
      for (final kind in ['filled', 'outlined', 'text']) {
        var calls = 0;
        var busy = true;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  final VoidCallback? action = busy ? null : () => calls++;
                  final child = busy
                      ? const ButtonSpinner()
                      : const Text('Ready');
                  final button = switch (kind) {
                    'filled' => FilledButton(onPressed: action, child: child),
                    'outlined' => OutlinedButton(
                      onPressed: action,
                      child: child,
                    ),
                    _ => TextButton(onPressed: action, child: child),
                  };
                  return Column(
                    children: [
                      button,
                      TextButton(
                        onPressed: () => setState(() => busy = false),
                        child: const Text('Finish'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
        final spinner = find.byType(ButtonSpinner);
        final painted = find
            .ancestor(of: spinner, matching: find.byType(Material))
            .first;
        final bg = tester.widget<Material>(painted).color ?? s.surface;
        expect(
          _contrast(
            theme.progressIndicatorTheme.color!,
            Color.alphaBlend(bg, s.surface),
          ),
          greaterThanOrEqualTo(3),
          reason: kind,
        );
        await tester.tap(spinner);
        await tester.pump();
        expect(calls, 0);
        await tester.tap(find.text('Finish'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Ready'));
        expect(calls, 1);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
