import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/admin/admin_config_keys.dart';

/// `app_config` is world-readable and the admin console is the only UI that
/// writes it, so three lists have to agree and nothing checks that they do:
///
///  1. the keys the console offers to edit (`kAdminConfigKeys`),
///  2. the keys the Edge Function will accept (`PUBLIC_CONFIG_KEYS`),
///  3. the keys the app and web surfaces actually read.
///
/// They had already drifted. The console offered **seven** keys while the
/// product runs on **thirteen** — the four `pay.lemonsqueezy.*` keys and the
/// two `device.*` allowance keys were reachable only through the Supabase SQL
/// editor. #294 is what that costs: the international checkout was broken
/// because `app_config` was mis-wired, and the console could not show, let
/// alone fix, the keys involved.
void main() {
  String fn() =>
      File('supabase/functions/admin/index.ts').readAsStringSync();

  Set<String> serverAllowlist() {
    final src = fn();
    final start = src.indexOf('const PUBLIC_CONFIG_KEYS = new Set([');
    expect(start, isNot(-1),
        reason: 'PUBLIC_CONFIG_KEYS is gone from the Edge Function — '
            'set_config would be writing arbitrary keys into a table the '
            'whole internet can read.');
    final body = src.substring(start, src.indexOf(']);', start));
    return RegExp('"([^"]+)"')
        .allMatches(body)
        .map((m) => m.group(1)!)
        .toSet();
  }

  test('the console and the Edge Function allow exactly the same keys', () {
    expect(serverAllowlist(), kAdminConfigKeys.keys.toSet(),
        reason: 'a key the console can submit but the server rejects fails '
            'silently in the admin\'s face; a key the server accepts but the '
            'console never shows is one only the SQL editor can reach.');
  });

  test('every key the console offers has a human label', () {
    for (final e in kAdminConfigKeys.entries) {
      expect(e.value.trim(), isNotEmpty, reason: '${e.key} has no label');
    }
  });

  test('nothing that reads app_config asks for a key the console cannot set',
      () {
    // The surfaces that actually consume vendor config.
    const readers = [
      'lib/features/support/vendor_config.dart',
      'lib/storefront/storefront_api.dart',
      'lib/storefront/renew_request_page.dart',
    ];
    final read = <String>{};
    for (final path in readers) {
      final src = File(path).readAsStringSync();
      // Config keys are read either as a map subscript — m['pay.kbzpay.name']
      // — or listed in the `.inFilter([...])` the storefront uses to fetch
      // them. Matching those two shapes rather than "any dotted string" keeps
      // Dart import filenames (`storefront_api.dart`) out of the result.
      read.addAll(RegExp(r"\['([a-z_]+(?:\.[a-z_]+)+)'\]")
          .allMatches(src)
          .map((m) => m.group(1)!));
      final inFilter = RegExp(r'inFilter\([^)]*\)', dotAll: true);
      for (final f in inFilter.allMatches(src)) {
        read.addAll(RegExp(r"'([a-z_]+(?:\.[a-z_]+)+)'")
            .allMatches(f.group(0)!)
            .map((m) => m.group(1)!));
      }
    }
    // Keys deliberately excluded, with the reason they are not the console's
    // to set. Anything else that turns up here is a real gap.
    const knownUnsettable = {
      // Dead: VendorConfig still parses these into priceMonthlyOnline /
      // priceYearlyOnline, but nothing reads those fields and priceFor() has
      // no callers, so offering them would invite setting a price that can
      // never be charged. See admin_config_keys.dart.
      'price.monthly.online',
      'price.yearly.online',
    };
    final missing = read
        .where((k) => !kAdminConfigKeys.containsKey(k))
        .where((k) => !knownUnsettable.contains(k))
        .toList()
      ..sort();
    expect(missing, isEmpty,
        reason: 'these app_config keys are read by the product but the admin '
            'console has no field for them, so changing one means opening the '
            'Supabase SQL editor: $missing');
  });

  test('no key that could plausibly hold a secret is settable', () {
    // app_config is `for select to anon ... using (true)`. A key whose name
    // suggests a credential must never be settable through a form whose whole
    // affordance says "admin settings".
    const forbidden = ['secret', 'api_key', 'apikey', 'token', 'password',
      'service_role', 'private'];
    for (final key in kAdminConfigKeys.keys) {
      for (final word in forbidden) {
        expect(key.toLowerCase(), isNot(contains(word)),
            reason: '"$key" reads like a credential, and everything in '
                'app_config is publicly readable without logging in.');
      }
    }
  });

  test('the client month cap matches the server\'s', () {
    final m = RegExp(r'const MAX_LICENCE_MONTHS = (\d+);').firstMatch(fn());
    expect(m, isNotNull,
        reason: 'MAX_LICENCE_MONTHS is gone — sign_offline would again accept '
            'an unbounded, unrevocable term.');
    expect(int.parse(m!.group(1)!), kMaxLicenceMonths,
        reason: 'the form would reject a value the server allows, or wave '
            'through one it rejects.');
  });
}
