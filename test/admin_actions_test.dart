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
    for (final f in Directory(
      'lib/admin',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      buf.writeln(f.readAsStringSync());
    }
    return buf.toString();
  }

  Set<String> serverActions() => RegExp(
    r'case "(\w+)":',
  ).allMatches(fnSource()).map((m) => m.group(1)!).toSet();

  Set<String> clientActions() {
    final src = dartSource();
    final sent = <String>{};
    // Literal: body: {'action': 'list_shops', ...}
    sent.addAll(
      RegExp(r"'action'\s*:\s*'(\w+)'").allMatches(src).map((m) => m.group(1)!),
    );
    // Indirect: the list endpoints go through `_rows('list_shops')`, which
    // passes the action as a *variable*. A first attempt at this audit read
    // only the literal form and reported five live actions as dead; the
    // helper's own call sites are what make them visible.
    sent.addAll(
      RegExp(r"_rows\(\s*'(\w+)'").allMatches(src).map((m) => m.group(1)!),
    );
    return sent;
  }

  test('every action the console sends exists in the Edge Function', () {
    final unknown = clientActions().difference(serverActions()).toList()
      ..sort();
    expect(
      unknown,
      isEmpty,
      reason:
          'the function would answer `unknown_action` (400) for these, '
          'surfacing as a generic failure on what may be a money action: '
          '$unknown',
    );
  });

  test('every action the Edge Function defines has a caller', () {
    final dead = serverActions().difference(clientActions()).toList()..sort();
    expect(
      dead,
      isEmpty,
      reason:
          'unreachable server code — delete it, or wire it up. This is '
          'how list_carriers/set_carrier/delete_carrier survived unused, '
          'and how #39 found list_payments/renew_license before them: '
          '$dead',
    );
  });

  test('the extraction actually finds things (guards the guard)', () {
    // If either regex silently stops matching, both tests above pass by
    // comparing two empty sets — the failure mode that makes a parity test
    // worthless. Anchor on actions that must exist for the console to work.
    final server = serverActions();
    final client = clientActions();
    expect(server.length, greaterThanOrEqualTo(14));
    expect(client.length, greaterThanOrEqualTo(14));
    for (final a in const ['list_shops', 'extend_license', 'reset_device']) {
      expect(server, contains(a));
      expect(client, contains(a));
    }
    // `list_shops` is the one that only appears via the `_rows` helper, so it
    // specifically proves the indirect path is still being read.
    expect(
      RegExp(r"'action'\s*:\s*'list_shops'").hasMatch(dartSource()),
      isFalse,
      reason:
          'list_shops is expected to be reachable only through _rows(); '
          'if it gained a literal call site, pick another anchor for the '
          'indirect-path check above',
    );
  });

  test('archive uses the locked subscription operation', () {
    final source = fnSource();
    final start = source.indexOf('case "set_shop_archived":');
    final body = source.substring(start, source.indexOf('default:', start));
    expect(body, contains('archive_shop_subscription'));
    expect(body, contains('shop_is_paid'));
    // Behavior including concurrent payment/archive is exercised against
    // real Postgres by supabase/tests/account_billing_test.py.
    expect(RegExp(r'\.from\(\s*"licenses"').hasMatch(body), isFalse);
  });

  test('shop list filters the subscription authority by archive state', () {
    final source = fnSource();
    final start = source.indexOf('case "list_shops":');
    final body = source.substring(
      start,
      source.indexOf('case "reset_password":', start),
    );
    expect(RegExp(r'\.from\(\s*"shop_subscriptions"').hasMatch(body), isTrue);
    expect(body, contains('.eq("is_archived", body.archived === true)'));
    expect(RegExp(r'\.from\(\s*"licenses"').hasMatch(body), isFalse);
  });
}
