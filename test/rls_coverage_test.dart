import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Forces step 5 of CLAUDE.md's "Adding a synced table" checklist, which until
/// now was the one step nothing enforced:
///
/// > create the table **with RLS**: `enable row level security` + a
/// > `shop_isolation` policy (`shop_id = auth_shop_id()`). NOT dev-open.
///
/// This is the checklist's highest-stakes item and its easiest to forget: a
/// synced table shipped without `shop_isolation` is not a broken feature that
/// someone notices, it is one shop reading another shop's books, silently, for
/// as long as it takes anyone to look. Nothing in `flutter analyze` or the
/// rest of the suite can see a `.sql` file.
///
/// The check replays every migration **in source order** and asks what policy
/// each synced table is left holding at the end. Order is the whole point:
/// `0002_dev_open_policies.sql` deliberately dropped `shop_isolation` on the 7
/// core tables to install a permissive `dev_open` for pre-launch testing, and
/// `0012_drop_dev_policies.sql` put it back — a checker that just greps for
/// "does the string shop_isolation appear near this table" would call both
/// states fine. Only the final state matters.
void main() {
  /// Table names the sync engine actually pushes rows to — the registry, not
  /// a list maintained by hand here, so a new `SyncTableDef` is covered the
  /// moment it is registered.
  List<String> syncedTables() {
    final src = File('lib/data/sync/sync_mappers.dart').readAsStringSync();
    final registry = src.substring(src.indexOf('final syncTables'));
    final registered = RegExp(r'^\s*_(\w+),', multiLine: true)
        .allMatches(registry.substring(0, registry.indexOf('];')))
        .map((m) => m.group(1)!)
        .toSet();
    // Map each registered `_foo` back to the `name:` its SyncTableDef declares.
    final names = <String>[];
    for (final v in registered) {
      final def = RegExp("final _$v = SyncTableDef\\(\\s*name: '([a-z_]+)'")
          .firstMatch(src);
      expect(def, isNotNull, reason: 'no SyncTableDef found for _$v');
      names.add(def!.group(1)!);
    }
    return names..sort();
  }

  /// Every synced table's policy set after all migrations have been applied.
  Map<String, Set<String>> finalPolicyState() {
    final stmt = RegExp(
      r'(create|drop)\s+policy\s+(?:if\s+exists\s+)?"?(\w+)"?\s+on\s+(?:public\.)?(%I|\w+)',
      caseSensitive: false,
    );
    // `do $$ ... foreach t in array array[...] ... execute format(..., t)` —
    // the 7 core tables are only ever touched through one of these loops, so
    // a `%I` target resolves to the member list of the nearest loop above it.
    final loop = RegExp(
      r'foreach\s+t\s+in\s+array\s+array\[(.*?)\]',
      caseSensitive: false,
      dotAll: true,
    );

    final state = <String, Set<String>>{};
    final files = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final f in files) {
      final src = f.readAsStringSync();
      final loops = loop.allMatches(src).map((m) => (
            at: m.start,
            members: RegExp("'([a-z_]+)'")
                .allMatches(m.group(1)!)
                .map((x) => x.group(1)!)
                .toList(),
          ));
      for (final m in stmt.allMatches(src)) {
        final target = m.group(3)!;
        final targets = target == '%I'
            ? (loops.where((l) => l.at < m.start).lastOrNull?.members ??
                const <String>[])
            : [target];
        for (final t in targets) {
          final set = state.putIfAbsent(t, () => <String>{});
          if (m.group(1)!.toLowerCase() == 'create') {
            set.add(m.group(2)!);
          } else {
            set.remove(m.group(2)!);
          }
        }
      }
    }
    return state;
  }

  test('every synced table ends up isolated by shop', () {
    final state = finalPolicyState();
    final missing = <String>[];
    for (final t in syncedTables()) {
      if (!(state[t] ?? const <String>{}).contains('shop_isolation')) {
        missing.add('$t (has: ${(state[t] ?? {}).join(', ')})');
      }
    }
    expect(missing, isEmpty,
        reason: 'these synced tables would let one shop read another:\n'
            '  ${missing.join('\n  ')}\n'
            'Add `enable row level security` + a shop_isolation policy '
            '(shop_id = auth_shop_id()) in a new migration.');
  });

  test('no table is left dev-open', () {
    final state = finalPolicyState();
    final open = state.entries
        .where((e) => e.value.contains('dev_open'))
        .map((e) => e.key)
        .toList();
    expect(open, isEmpty,
        reason: '`dev_open` is `using (true)` — it lets any authenticated '
            'session read every shop. It was pre-launch scaffolding and '
            '0012 removed it; these tables still carry one: $open');
  });

  test('the replay actually sees the loop-driven core tables', () {
    // Guards the guard: the 7 tables from 0001 are only ever touched through
    // a `format()` loop, so if the `%I` handling above regresses they would
    // silently read as "no policy at all" — which, being *stricter* than the
    // truth, would fail loudly rather than pass. The real risk is the
    // opposite: this file quietly checking nothing. So assert we resolved
    // them, not merely that they passed.
    final state = finalPolicyState();
    for (final t in const [
      'categories',
      'products',
      'stock_levels',
      'stock_movements',
      'sales',
      'sale_items',
      'payments',
    ]) {
      expect(state[t], isNotNull,
          reason: '$t resolved to no policy statements at all — the loop '
              'expansion in this test has stopped working');
      expect(state[t], contains('shop_isolation'));
    }
  });

  test('the registry is what is being checked, and it is not empty', () {
    final tables = syncedTables();
    expect(tables.length, greaterThanOrEqualTo(20));
    expect(tables, contains('sales'));
    expect(tables, contains('payments'));
  });
}
