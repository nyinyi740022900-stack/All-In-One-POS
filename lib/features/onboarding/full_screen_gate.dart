import 'package:flutter/material.dart';

/// Full-screen overlay for first-run / daily-gate / password-recovery.
///
/// These pages are shown from [MaterialApp.builder], which *replaces*
/// go_router's Navigator. A bare [Navigator] (even inside
/// [SizedBox.expand]) can paint full-screen while its hit-test box stays
/// empty or narrower than the phone — Get started / Continue look enabled
/// but taps fall through to the router underneath (sometimes visible as a
/// grey chevron on the right edge).
///
/// Pin the overlay to [MediaQuery] size and keep the router child in the
/// tree behind [IgnorePointer] so hits cannot leak through.
class FullScreenGate extends StatelessWidget {
  const FullScreenGate({super.key, required this.page, this.underneath});

  final Widget page;
  final Widget? underneath;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (underneath != null)
          IgnorePointer(
            child: TickerMode(enabled: false, child: underneath!),
          ),
        SizedBox(
          width: size.width,
          height: size.height,
          child: HeroControllerScope.none(
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => page,
                fullscreenDialog: true,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
