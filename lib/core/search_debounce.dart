import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long a search field must stay quiet before its query reaches the
/// list filters.
const Duration kSearchDebounce = Duration(milliseconds: 200);

/// A [StateNotifier] mirroring a search source with [kSearchDebounce] of
/// quiet before each update — see [debouncedSearchProvider].
class DebouncedSearch extends StateNotifier<String> {
  DebouncedSearch(Ref ref, ProviderListenable<String> source)
      : super(ref.read(source)) {
    // Lives as long as the (non-autoDispose) provider — i.e. the whole
    // session, which is exactly what a search mirror needs.
    ref.listen<String>(source, (_, next) {
      _timer?.cancel();
      _timer = Timer(kSearchDebounce, () {
        if (mounted && state != next) state = next;
      });
    });
  }

  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Mirrors [source] but only settles [kSearchDebounce] after it stops
/// changing — typing ten characters refilters the catalogue once, not ten
/// times (audit H1). Writers keep writing to [source] directly, so barcode
/// scans, programmatic clears and text fields all flow through one path.
///
/// Only the EXPENSIVE listeners (list filters, category-count folds) watch
/// the returned provider; instant UI — the text field itself, "filters
/// active" buttons, empty-state labels — keeps watching [source] so it
/// reacts on the same keystroke.
StateNotifierProvider<DebouncedSearch, String> debouncedSearchProvider(
  ProviderListenable<String> source,
) {
  return StateNotifierProvider<DebouncedSearch, String>(
    (ref) => DebouncedSearch(ref, source),
  );
}
