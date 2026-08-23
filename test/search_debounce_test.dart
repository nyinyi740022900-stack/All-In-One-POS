import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/search_debounce.dart';

void main() {
  test('a keystroke burst refilters ONCE with the final value', () async {
    final raw = StateProvider<String>((ref) => '');
    final debounced = debouncedSearchProvider(raw);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    var emissions = 0;
    container.listen<String>(debounced, (_, _) => emissions++);
    expect(container.read(debounced), '');

    for (final v in ['a', 'ap', 'app', 'appl', 'apple']) {
      container.read(raw.notifier).state = v;
    }

    // Still inside the quiet window: the expensive listeners have not run.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(emissions, 0,
        reason: 'typing must not refilter per keystroke (audit H1)');
    expect(container.read(debounced), '');

    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(emissions, 1);
    expect(container.read(debounced), 'apple');
  });

  test('separate pauses settle separately', () async {
    final raw = StateProvider<String>((ref) => '');
    final debounced = debouncedSearchProvider(raw);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    var emissions = 0;
    container.listen<String>(debounced, (_, _) => emissions++);

    container.read(raw.notifier).state = 'co';
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(container.read(debounced), 'co');

    container.read(raw.notifier).state = 'coke';
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(emissions, 2);
    expect(container.read(debounced), 'coke');
  });

  test('initial value mirrors an already-written source immediately', () {
    final raw = StateProvider<String>((ref) => 'carried over');
    final debounced = debouncedSearchProvider(raw);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // The screen can mount long after the user (or a barcode scan) wrote
    // the query — no silent empty first frame.
    expect(container.read(debounced), 'carried over');
  });

  test('identical rewrite does not emit', () async {
    final raw = StateProvider<String>((ref) => '');
    final debounced = debouncedSearchProvider(raw);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    var emissions = 0;
    container.listen<String>(debounced, (_, _) => emissions++);

    container.read(raw.notifier).state = 'same';
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(emissions, 1);

    container.read(raw.notifier).state = 'same';
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(emissions, 1, reason: 'no-op writes must not rebuild filters');
  });
}
