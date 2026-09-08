import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The console and its Edge Function agree on a set of action strings that
/// nothing type-checks — `invokeBounded('admin', body: {'action': '...'})` is
/// just a map — so the two drift silently and in both directions.
///
/// Both directions have already happened. `list_carriers`/`set_carrier`/
/// `delete_carrier` sat in the function with no caller anywhere for months,
/// and #39 removed an earlier pair (`list_payments`, `renew_license`) the same
/// way: by hand, by grepping every case against every call site. This is that
/// audit, kept.
///
/// A wrong action string in the other direction is worse than dead code: the
/// function answers `unknown_action` 400, which the console surfaces as a
/// generic failure on what may be a money action.
void main() {
  String fnSource() =>
      File('supabase/functions/admin/index.ts').readAsStringSync();

  String dartSource() {
    final buf = StringBuffer();
    for (final f in Directory('lib/admin')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      buf.writeln(f.readAsStringSync());
    }
    return buf.toString();
  }

  Set<String> serverActions() => RegExp(r'case "(\w+)":')
      .allMatches(fnSource())
      .map((m) => m.group(1)!)
      .toSet();

  Set<String> clientActions() {
    final src = dartSource();
    final sent = <String>{};
    // Literal: body: {'action': 'list_shops', ...}
    sent.addAll(RegExp(r"'action'\s*:\s*'(\w+)'")
        .allMatches(src)
        .map((m) => m.group(1)!));
    // Indirect: the list endpoints go through `_rows('list_shops')`, which
    // passes the action as a *variable*. A first attempt at this audit read
    // only the literal form and reported five live actions as dead; the
    // helper's own call sites are what make them visible.
    sent.addAll(
        RegExp(r"_rows\(\s*'(\w+)'").allMatches(src).map((m) => m.group(1)!));
    return sent;
  }

  test('every action the console sends exists in the Edge Function', () {
    final unknown = clientActions().difference(serverActions()).toList()..sort();
    expect(unknown, isEmpty,
        reason: 'the function would answer `unknown_action` (400) for these, '
            'surfacing as a generic failure on what may be a money action: '
            '$unknown');
  });

  test('every action the Edge Function defines has a caller', () {
    final dead = serverActions().difference(clientActions()).toList()..sort();
    expect(dead, isEmpty,
        reason: 'unreachable server code — delete it, or wire it up. This is '
            'how list_carriers/set_carrier/delete_carrier survived unused, '
            'and how #39 found list_payments/renew_license before them: '
            '$dead');
  });

  test('the extraction actually finds things (guards the guard)', () {
    // If either regex silently stops matching, both tests above pass by
    // comparing two empty sets — the failure mode that makes a parity test
    // worthless. Anchor on actions that must exist for the console to work.
    final server = serverActions();
    final client = clientActions();
    expect(server.length, greaterThanOrEqualTo(15));
    expect(client.length, greaterThanOrEqualTo(15));
    for (final a in const ['list_shops', 'extend_license', 'sign_offline']) {
      expect(server, contains(a));
      expect(client, contains(a));
    }
    // `list_shops` is the one that only appears via the `_rows` helper, so it
    // specifically proves the indirect path is still being read.
    expect(
        RegExp(r"'action'\s*:\s*'list_shops'").hasMatch(dartSource()), isFalse,
        reason: 'list_shops is expected to be reachable only through _rows(); '
            'if it gained a literal call site, pick another anchor for the '
            'indirect-path check above');
  });

  test('archiving a shop is guarded server-side, not only in the dialog', () {
    // The console asks the admin to type the shop name, but a typed
    // confirmation is UI and UI is bypassable. What actually protects a
    // paying customer from losing their licence is the refusal below.
    final src = fnSource();
    final start = src.indexOf('case "set_shop_archived":');
    expect(start, isNot(-1), reason: 'set_shop_archived is gone');
    final body = src.substring(start, src.indexOf('default:', start));
    expect(body, contains('shop_is_paid'),
        reason: 'the active-paid refusal is what stops an archive from '
            'silently revoking a paying shop\'s licence');
    expect(body, contains('"trial"'),
        reason: 'trial must stay archivable — it is most of what needs '
            'cleaning up');
  });

  test('the shop list respects the archived flag past the licence query', () {
    // The licence query filtering on `archived` is not enough. list_shops
    // also backfills shops that have an auth account but no licence row, and
    // that backfill predates archiving — left unconditional it broke BOTH
    // lists at once: the live one re-added every archived shop as
    // `no_license` (so archiving looked like it had done nothing), and the
    // archived one filled up with every account-only shop in the system.
    // Caught on production, not by a test, which is why this one exists.
    final src = fnSource();
    final start = src.indexOf('case "list_shops":');
    expect(start, isNot(-1));
    final body = src.substring(start, src.indexOf('case "lookup_shop":'));
    expect(body, contains('wantArchived'),
        reason: 'list_shops no longer reads the archived flag at all');
    expect(body, contains('archivedShopIds'),
        reason: 'the no_license backfill must exclude archived shops, or an '
            'archived shop reappears in the live list as if nothing happened');
    expect(body, contains('if (!wantArchived) {'),
        reason: 'the backfill must not run at all for the archived view, or '
            'that view lists every account-only shop in the system');
  });
}
