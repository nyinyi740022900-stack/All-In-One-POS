import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';

/// Forces the question CLAUDE.md's ripple-effect check asks by hand:
/// **does this value belong to the device, or to the currently-active shop?**
///
/// `settings_repository_test.dart` already covers per-shop isolation
/// *behaviourally*, key by key — and thoroughly. What it cannot cover is a
/// key that doesn't exist yet: `referral.seen_earned` shipped as
/// device-global, so switching shops on one device compared the new shop's
/// earnings against a watermark left by a different shop (#295-9). No test
/// was wrong; no test existed, because nobody was prompted to ask.
///
/// So this guard is about completeness, not behaviour. Every key constant in
/// `SettingsRepository` must appear below with an explicit scope, and that
/// declared scope is then checked against what `isDeviceGlobalKey` actually
/// does at runtime. A new key fails here until it is classified, and a key
/// whose classification disagrees with its routing fails too — which is
/// exactly the shape of the bug above.
void main() {
  /// The deliberate scope of every settings key.
  ///
  /// `deviceGlobal` — belongs to the physical device and must SURVIVE a shop
  /// switch (printer hardware, this install's id, the offline licence blob).
  /// Stored in the device sidecar DB.
  ///
  /// `perShop` — belongs to the active shop and must NOT survive a shop
  /// switch (that shop's profile, its staff PINs, its watermarks). Isolated
  /// by living in the per-shop DB file, and additionally `shopId`-suffixed
  /// where a legacy shared DB could still hold both shops' values.
  const scopes = <String, _Scope>{
    // --- device hardware / this install -----------------------------------
    'device.id': _Scope.deviceGlobal,
    'app.locale': _Scope.deviceGlobal,
    'onboarding.done': _Scope.deviceGlobal,
    'operating.mode': _Scope.deviceGlobal,
    'operating.mode_confirmed': _Scope.deviceGlobal,
    'vendor.config.json': _Scope.deviceGlobal,
    // The licence is bound to the DEVICE, so it has to outlive a shop swap —
    // and `branch.switch.state`/`shop.promote.pending` describe a swap in
    // flight, so they cannot live in a DB the swap replaces.
    'license.json': _Scope.deviceGlobal,
    'license.trial_used': _Scope.deviceGlobal,
    'branch.switch.state': _Scope.deviceGlobal,
    'shop.promote.pending': _Scope.deviceGlobal,
    // Printers are physical objects plugged into this device, not shop data.
    'printer.paper_size': _Scope.deviceGlobal,
    'printer.pdf_paper_size': _Scope.deviceGlobal,
    'printer.mac': _Scope.deviceGlobal,
    'printer.name': _Scope.deviceGlobal,
    'printer.model': _Scope.deviceGlobal,
    'printer.connection': _Scope.deviceGlobal,
    'label_printer.size': _Scope.deviceGlobal,
    'label_printer.mac': _Scope.deviceGlobal,
    'label_printer.name': _Scope.deviceGlobal,
    'label_printer.connection': _Scope.deviceGlobal,

    // --- this shop's own data ---------------------------------------------
    'shop.name': _Scope.perShop,
    'shop.address': _Scope.perShop,
    'shop.phone': _Scope.perShop,
    'shop.logo_url': _Scope.perShop,
    'shop.country': _Scope.perShop,
    'shop.currency': _Scope.perShop,
    'shop.payment_methods': _Scope.perShop,
    'shop.track_stock': _Scope.perShop,
    'receipt.footer': _Scope.perShop,
    // Watermarks: a per-shop figure compared against a per-shop threshold.
    // `referral.seen_earned` is the one that shipped device-global by
    // mistake — see this file's header.
    'referral.seen_earned': _Scope.perShop,
    'license.expiry_warned': _Scope.perShop,
    'storefront.seen_order_ms': _Scope.perShop,
    'daily.gate.ymd': _Scope.perShop,
    'daily.gate.skipped_open': _Scope.perShop,
    'inventory.seed_cleanup_done': _Scope.perShop,
    'accounting.books_closed_through': _Scope.perShop,
    // The signed offline token carries a shop_id claim, so it must travel
    // with a promoted shop rather than stay behind on the device.
    'license.offline_fallback': _Scope.perShop,
    // Staff identity and PIN state are the shop's, not the handset's.
    'staff.role': _Scope.perShop,
    'staff.active_id': _Scope.perShop,
    'staff.pin': _Scope.perShop,
    'staff.pin_hash': _Scope.perShop,
    'staff.pin_failed_attempts': _Scope.perShop,
    'staff.pin_locked_until': _Scope.perShop,
  };

  late final Set<String> declaredKeys = RegExp(
    r"static const _k[A-Za-z]+ = '([^']+)';",
  )
      .allMatches(
          File('lib/data/repositories/settings_repository.dart').readAsStringSync())
      .map((m) => m.group(1)!)
      .toSet();

  test('every settings key has a deliberately chosen scope', () {
    expect(declaredKeys, isNotEmpty,
        reason: 'no key constants found — SettingsRepository was '
            'restructured and this guard is now blind.');
    final unclassified = declaredKeys.difference(scopes.keys.toSet());
    expect(
      unclassified,
      isEmpty,
      reason: 'New settings key(s) $unclassified.\n\n'
          'Before adding them here, answer the question this guard exists to '
          'force: does the value belong to the DEVICE (survives a shop '
          'switch — printer hardware, this install\'s licence) or to the '
          'ACTIVE SHOP (must not leak into the next shop — profile, staff '
          'PINs, watermarks)?\n\n'
          'A per-shop value left device-global silently bleeds across shops '
          'on one handset, which is invisible in single-shop testing.',
    );
  });

  test('the classification is not stale', () {
    final vanished = scopes.keys.toSet().difference(declaredKeys);
    expect(vanished, isEmpty,
        reason: 'classified here but no longer declared in '
            'SettingsRepository: $vanished — drop the stale entries.');
  });

  test('each key routes to the store its declared scope requires', () {
    final misrouted = <String>[];
    for (final entry in scopes.entries) {
      final routedToDevice = SettingsRepository.isDeviceGlobalKey(entry.key);
      final shouldBeDevice = entry.value == _Scope.deviceGlobal;
      if (routedToDevice != shouldBeDevice) {
        misrouted.add(
          '${entry.key}: declared ${entry.value.name} but '
          'isDeviceGlobalKey() returns $routedToDevice',
        );
      }
    }
    expect(
      misrouted,
      isEmpty,
      reason: 'Scope declared here disagrees with how the key is actually '
          'stored:\n  ${misrouted.join('\n  ')}\n\n'
          'This is the `referral.seen_earned` bug shape: a value the app '
          'treats as belonging to one shop, kept in the store that outlives '
          'shop switches.',
    );
  });
}

enum _Scope { deviceGlobal, perShop }
