import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/widgets/app_widgets.dart';

/// [BrandPulseProgress] is the sign-in wait: a `CustomPainter` on a
/// forever-repeating controller, sized generously so the outermost pulse ring
/// is not clipped. Two things about that can break without any analyzer or
/// pure-logic test noticing — it can overflow a short screen, and its ticker
/// can keep running when the platform has asked for stillness.
void main() {
  Widget host(
    Widget child, {
    Size size = const Size(360, 640),
    bool disableAnimations = false,
  }) => MediaQuery(
    data: MediaQueryData(
      size: size,
      disableAnimations: disableAnimations,
    ),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    ),
  );

  testWidgets('paints through a full cycle without overflowing', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const BrandPulseProgress(
          icon: Icons.storefront_rounded,
          caption: 'Checking your password',
          stepCount: 2,
        ),
      ),
    );

    // Walk a whole 2.4s cycle. `pumpAndSettle` would hang here by design —
    // the animation never ends — so step it by hand.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('survives the shortest screen it can land on', (tester) async {
    // A small phone in landscape with the keyboard up is the worst case; the
    // rings alone are ~229 logical pixels before the caption and the track.
    await tester.pumpWidget(
      host(
        const BrandPulseProgress(
          icon: Icons.storefront_rounded,
          caption: 'Opening your shop',
          stepCount: 3,
          stepIndex: 2,
        ),
        size: const Size(640, 320),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('holds still — and stops its ticker — under reduce motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const BrandPulseProgress(
          icon: Icons.storefront_rounded,
          caption: 'Checking your password',
        ),
        disableAnimations: true,
      ),
    );

    // The real assertion: this returns instead of timing out. A controller
    // left repeating would make it hang, which is also what it would do to
    // any future widget test that walks the sign-in screen.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
  });

  testWidgets('the caption is what changes, so it must survive a swap', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const BrandPulseProgress(
          icon: Icons.storefront_rounded,
          caption: 'Checking your password',
          stepCount: 2,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pumpWidget(
      host(
        const BrandPulseProgress(
          icon: Icons.storefront_rounded,
          caption: 'Opening your shop',
          stepCount: 2,
          stepIndex: 1,
        ),
      ),
    );
    // Mid-cross-fade both captions are on screen; that is the transition
    // working, not a duplicate.
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.text('Opening your shop'), findsOneWidget);
  });
}
