import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../printing/printing_providers.dart';

/// Whether the one-time onboarding has been completed (device DB).
final onboardingCompleteProvider = FutureProvider<bool>((ref) {
  return ref.watch(settingsRepositoryProvider).onboardingComplete();
});

/// Set the moment Get started is tapped, so the flow can leave even if the
/// Drift write of `onboarding.done` stalls behind Free-plan setup writes.
final onboardingForcedDoneProvider = StateProvider<bool>((ref) => false);

/// True while the onboarding route must stay up. Loading reads as *done*
/// so the (instant) first read never flashes onboarding mid-launch.
final onboardingStillNeededProvider = Provider<bool>((ref) {
  if (ref.watch(onboardingForcedDoneProvider)) return false;
  return ref.watch(onboardingCompleteProvider).valueOrNull == false;
});
