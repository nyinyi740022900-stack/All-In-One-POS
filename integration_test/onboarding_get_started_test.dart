import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mm_pos/core/providers.dart';
import 'package:mm_pos/core/theme/app_theme.dart';
import 'package:mm_pos/data/local/database_session.dart';
import 'package:mm_pos/features/license/license_providers.dart';
import 'package:mm_pos/features/onboarding/full_screen_gate.dart';
import 'package:mm_pos/features/onboarding/onboarding_flow.dart';
import 'package:mm_pos/l10n/app_localizations.dart';

/// Reproduces the owner's dead-"Get started" report ON DEVICE: the exact
/// `MaterialApp.builder` layering from `app.dart` (gate over an
/// IgnorePointer'd shell) driven by real hit-tested taps on the simulator —
/// not the synthetic gesture arena of a plain widget test.
class _FakeLicenseController extends LicenseController {
  _FakeLicenseController(super.ref) {
    state = const LicenseState(loading: false);
  }

  @override
  Future<void> load() async {}

  @override
  Future<bool> continueFree() async => true;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Fully live frames: taps are delivered through the real gesture/hit-test
  // pipeline with real vsync pacing — the closest thing to a finger.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('onboarding: Next ×3 → Skip → Get started closes the gate', (
    tester,
  ) async {
    var doneCount = 0;
    // Real per-shop DB on the simulator, exactly as main.dart wires it —
    // the flow's profile/locale/settings reads must behave like production.
    final session = await DatabaseSession.open();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseSessionProvider.overrideWith((ref) {
            ref.onDispose(session.disposeSessions);
            return session;
          }),
          licenseControllerProvider.overrideWith(
            (ref) => _FakeLicenseController(ref),
          ),
        ],
        child: _Harness(onDone: () => doneCount++),
      ),
    );
    await tester.pumpAndSettle();

    // Pages 1→2→3 via the footer Next (welcome → shop → free-plan).
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    // Diagnostic: which page are we actually on?
    for (final title in const [
      'Welcome to All In One POS',
      'Your shop',
      'You start on the Free plan',
      'Email account (optional)',
      'Owner and Staff modes',
    ]) {
      debugPrint('TITLE "$title" visible: ${find.text(title).evaluate().isNotEmpty}');
    }
    // Account page owns its navigation — footer Next is deliberately absent;
    // leave via the page's own skip action. It sits at the bottom of a tall
    // scrollable, so bring it on-screen first (a raw tap on an off-screen
    // finder silently misses).
    final skip = find.text('Skip for now');
    await tester.ensureVisible(skip);
    await tester.pumpAndSettle();
    await tester.tap(skip);
    await tester.pumpAndSettle();

    // Last page: the button under test.
    final getStarted = find.text('Get started');
    expect(getStarted, findsOneWidget);
    expect(tester.widget<FilledButton>(
      find.ancestor(of: getStarted, matching: find.byType(FilledButton)),
    ).onPressed, isNotNull);

    await tester.tap(getStarted);
    await tester.pumpAndSettle();

    expect(doneCount, 1, reason: 'onDone must fire exactly once');
  });
}

/// Mirrors `MmPosApp`'s builder: the gate replaces the tree while active,
/// with the (real, tappable-looking) shell underneath behind IgnorePointer.
/// When [OnboardingFlow.onDone] fires, the shell takes over — exactly what
/// `app.dart` does via its forced-done provider.
class _Harness extends StatefulWidget {
  const _Harness({required this.onDone});
  final VoidCallback onDone;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool _closed = false;

  @override
  Widget build(BuildContext context) {
    final shell = const Scaffold(
      body: Center(key: ValueKey('sell-shell'), child: Text('SELL-SHELL')),
    );
    return MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _closed
          ? shell
          : FullScreenGate(
              underneath: shell,
              page: OnboardingFlow(
                onDone: () {
                  widget.onDone();
                  setState(() => _closed = true);
                },
              ),
            ),
    );
  }
}
