import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Locks in properties the codebase has already achieved, so they can't be
/// lost by omission in a later change.
///
/// Two shapes of guard here:
///
///  * **Hard bans** — the violation count is already zero, so the rule costs
///    nothing to keep and a new violation fails immediately.
///  * **Ratchets** — real existing debt, listed explicitly. A file NOT on the
///    list may not have the pattern (no new debt), and a file ON the list
///    must still have it (fix one → delete its entry → the ceiling drops and
///    can never rise again). Deliberately not a blanket exemption.
void main() {
  /// Dart sources with `//` comment bodies stripped, so a comment that
  /// *describes* an anti-pattern (`customers_screen.dart` documents the grey
  /// disc it replaced) isn't mistaken for committing it.
  final sources = <String, String>{
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart')))
      f.path: f
          .readAsLinesSync()
          .map((line) {
            final i = line.indexOf('//');
            return i == -1 ? line : line.substring(0, i);
          })
          .join('\n'),
  };

  Iterable<String> filesContaining(String needle, {Set<String> except = const {}}) =>
      sources.entries
          .where((e) => !except.contains(e.key) && e.value.contains(needle))
          .map((e) => e.key);

  group('hard bans (already at zero — keep it there)', () {
    test('every Edge Function call goes through invokeBounded', () {
      // `functions.invoke` has no timeout, so a stalled connection hangs the
      // caller's spinner forever (#298). That was fixed at one call site
      // while 25 others — the whole admin console, the storefront API,
      // branch switching, the sync engine — stayed unbounded. The bound now
      // lives on the transport (`core/net/edge_invoke.dart`); this keeps a
      // new call site from quietly opting out of it again.
      final offenders = filesContaining(
        'functions.invoke(',
        except: {'lib/core/net/edge_invoke.dart'},
      );
      expect(
        offenders,
        isEmpty,
        reason: 'bare functions.invoke( in:\n  ${offenders.join('\n  ')}\n\n'
            'Use `functions.invokeBounded(...)` — a bare invoke can never '
            'time out, which shows the user a spinner that never resolves.',
      );
    });

    test('no identity-less grey avatar disc', () {
      // `CircleAvatar(child: Icon(...))` renders the same grey disc on every
      // row, carrying no information (see customers_screen.dart's own note).
      // `ProductThumb` gives each subject a stable colour + initial instead.
      // A CircleAvatar with a real computed initial (shop_login_screen) is
      // that same idea and is fine — this bans only the empty-icon shape.
      final offenders = filesContaining('CircleAvatar(child: Icon(');
      expect(
        offenders,
        isEmpty,
        reason: 'grey identity-less disc in:\n  ${offenders.join('\n  ')}\n\n'
            'Use ProductThumb(name: …) for a per-subject mark, or IconAvatar '
            'for a category glyph.',
      );
    });
  });

  group('ratchet: page-level loading spinner', () {
    // `Center(child: CircularProgressIndicator())` is the raw form of what
    // `AppLoadingView` does (tonal plate, optional message) — every
    // accounting screen already uses the shared widget, and two screens were
    // converted in #306. These are the ones still to convert.
    const grandfathered = {
      'lib/admin/admin_dashboard_screen.dart',
      'lib/features/account/branches_screen.dart',
      'lib/features/account/staff_accounts_screen.dart',
      'lib/features/customers/customers_screen.dart',
      'lib/features/inventory/categories_screen.dart',
      'lib/features/inventory/stock_history_screen.dart',
      'lib/features/license/premium_gate.dart',
      'lib/features/orders/order_detail_sheet.dart',
      'lib/features/purchasing/purchase_order_detail_screen.dart',
      'lib/features/purchasing/purchase_orders_screen.dart',
      'lib/features/settings/shop_profile_screen.dart',
      'lib/features/staff/staff_members_screen.dart',
      'lib/features/storefront/storefront_screen.dart',
      'lib/features/suppliers/suppliers_screen.dart',
      'lib/invoices_web/invoice_detail_web_screen.dart',
      'lib/invoices_web/invoice_list_screen.dart',
      'lib/storefront/storefront_page.dart',
    };
    const pattern = 'Center(child: CircularProgressIndicator())';

    test('no new screen takes the raw spinner', () {
      final offenders = filesContaining(pattern, except: grandfathered);
      expect(
        offenders,
        isEmpty,
        reason: 'raw page spinner in:\n  ${offenders.join('\n  ')}\n\n'
            'Use `const AppLoadingView()` — it carries the app\'s tonal '
            'plate and an optional message, and keeps every screen\'s '
            'loading state looking like the same app.',
      );
    });

    test('the list only shrinks', () {
      final fixed = grandfathered.where((f) => !sources[f]!.contains(pattern));
      expect(
        fixed,
        isEmpty,
        reason: 'no longer uses the raw spinner:\n  ${fixed.join('\n  ')}\n\n'
            'Thanks — now delete these from `grandfathered` above so the '
            'ceiling drops and they can never regress.',
      );
    });
  });
}
