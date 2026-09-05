import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the most expensive bug class this project has shipped: **a licence
/// minted or extended twice for one payment.**
///
/// It has happened, and not through a wrong guard — through an *absent* one,
/// because nobody asked "can this fire twice?":
///
///   * Lemon Squeezy sends both `order_created` **and**
///     `subscription_payment_success` for a single first purchase, and the
///     webhook's dedup was keyed per event *type*, so both independently
///     minted — every new subscriber silently got double the term they paid
///     for (#295-1).
///   * `extend_license` had no idempotency at all: a double-click, an
///     impatient retry, or two open admin tabs each extended (#295-5).
///   * `create_branch`'s trial cap was a check-then-insert race (#296-2).
///
/// There is deliberately **no single "idempotency helper"** to reach for —
/// the four mechanisms below are different because the situations are
/// genuinely different (a row whose status can be claimed vs. no such row;
/// a webhook with an event identity vs. an admin click without one; a
/// cross-table aggregate rule that needs a lock). Forcing one shape onto all
/// of them would make some of them wrong.
///
/// So this guard forces the *question* instead of the shape: every call to a
/// licence-minting or money-moving RPC must be declared here with what stops
/// it from running twice. A new call site fails until it is.
void main() {
  /// What protects each money-moving call from a second delivery.
  ///
  /// Every entry below was read and verified, not assumed — each call site
  /// was followed into the migration that defines its RPC to confirm the
  /// guard its comment claims actually exists there.
  const declared = <String, String>{
    // --- admin console ------------------------------------------------------
    'admin/extend_license/renew_license':
        'time-window dedup: an identical extend logged in license_events '
            'within 10s is treated as the same click landing twice',
    'admin/fulfill_request/renew_license':
        'row claim: license_requests pending->processing is claimed '
            'atomically BEFORE minting; losers get already_fulfilled (409)',
    'admin/fulfill_request/create_license':
        'row claim: same pending->processing claim covers the mint branch',
    'admin/create_license/create_license':
        'existence check: refuses with license_already_exists if the shop '
            'already has a live licence row (the FAB path accepts any typed '
            'shop_id, so it cannot rely on the caller having checked)',
    'admin/set_device_allowance/set_shop_device_allowance':
        'naturally idempotent: upserts an ABSOLUTE slot count (not a '
            'delta), so a repeat delivery converges on the same value',

    // --- Lemon Squeezy webhook ---------------------------------------------
    'lemonsqueezy-webhook/renew_license':
        'event-id insert (unique violation = already handled) PLUS a '
            '10-minute sibling-event window, because one purchase legitimately '
            'fires two different event names',
    'lemonsqueezy-webhook/create_license':
        'event-id insert + sibling-event window (same guard as the renew '
            'branch above)',

    // --- activate (device/app-facing) --------------------------------------
    'activate/request_device_slot/claim_device_slot':
        'idempotent by design: claim_device_slot returns an EXISTING unbound '
            'key when one exists and counts only bound rows toward the cap '
            '(migration 0063), so an interrupted claim never burns a slot',
    'activate/claim_and_bind_extra_device/claim_device_slot':
        'idempotent per device, but the guard is NON-LOCAL: the caller '
            '(handleRefreshAccountLicense) first looks up a licence row '
            'already bound to this device_id and takes the harmless '
            '"touch last_verified_at" branch when it finds one, so this '
            'helper is never reached twice for the same device. Reorder those '
            'branches and the same device starts consuming a second slot — '
            'nothing in the helper or the RPC would stop it.',
    'activate/create_branch/create_trial_branch':
        'SQL advisory lock: pg_advisory_xact_lock per owner makes the '
            'trial-cap count-check and the insert one atomic step '
            '(migration 0089)',
  };

  /// RPCs that mint a licence, extend one, or move money.
  const moneyRpcs = <String>{
    'renew_license',
    'create_license',
    'set_shop_device_allowance',
    'claim_device_slot',
    'create_trial_branch',
  };

  test('every money-moving RPC call declares what stops a double fire', () {
    final found = <String>{};

    for (final file in Directory('supabase/functions')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('index.ts'))) {
      final fn = file.parent.path.split(Platform.pathSeparator).last;
      final source = file.readAsStringSync();

      for (final rpc in moneyRpcs) {
        for (final m in RegExp('\\.rpc\\("$rpc"').allMatches(source)) {
          // Attribute the call to its enclosing handler. The three functions
          // are structured differently — `admin` dispatches with
          // `case "…":` inside one big handler, `activate` with
          // `action === "…"` into separate `handleX()` functions, and the
          // webhook has no action switch at all (one purchase event drives
          // the whole body). So take whichever marker sits CLOSEST above the
          // call, and fall back to the function name alone.
          final before = source.substring(0, m.start);
          final lastCase = RegExp(r'case "([a-z_]+)":').allMatches(before);
          // Any function, not just `handleX` — a money RPC called from a
          // shared helper (`claimAndBindExtraDevice`) must be attributed to
          // that helper, not silently credited to whichever handler happened
          // to be declared above it.
          final lastFn =
              RegExp(r'function ([A-Za-z]+)\s*\(').allMatches(before);
          final caseAt = lastCase.isEmpty ? -1 : lastCase.last.start;
          final fnAt = lastFn.isEmpty ? -1 : lastFn.last.start;

          String? handler;
          if (caseAt > fnAt) {
            handler = lastCase.last.group(1);
          } else if (fnAt >= 0) {
            // handleRequestDeviceSlot -> request_device_slot, so the key
            // reads as the action a caller actually sends.
            handler = lastFn.last
                .group(1)!
                // handleRequestDeviceSlot -> request_device_slot, so the key
                // reads as the action a caller actually sends.
                .replaceFirst(RegExp(r'^handle'), '')
                .replaceAllMapped(
                  RegExp(r'(?<=[a-z])([A-Z])'),
                  (m) => '_${m.group(1)}',
                )
                .toLowerCase();
          }
          found.add(handler == null ? '$fn/$rpc' : '$fn/$handler/$rpc');
        }
      }
    }

    expect(found, isNotEmpty,
        reason: 'no money-moving RPC calls found at all — the Edge Functions '
            'were restructured and this guard is now blind.');

    final undeclared = found.difference(declared.keys.toSet());
    expect(
      undeclared,
      isEmpty,
      reason: 'Undeclared money-moving call site(s):\n'
          '  ${undeclared.join('\n  ')}\n\n'
          'This RPC mints a licence, extends one, or moves money. Before '
          'adding it below, answer: what happens if this runs TWICE for one '
          'payment?\n\n'
          'Webhooks retry. Admins double-click. Networks time out after the '
          'server already committed. Pick the mechanism that fits — an '
          'atomic row claim, an event-id insert, a time window, a SQL '
          'advisory lock, or an absolute (delta-free) write — then record it '
          'here so the next reader knows which one holds.',
    );

    final stale = declared.keys.toSet().difference(found);
    expect(stale, isEmpty,
        reason: 'declared here but no longer present in the Edge Functions:\n'
            '  ${stale.join('\n  ')}\n'
            'Drop the stale entries.');
  });
}
