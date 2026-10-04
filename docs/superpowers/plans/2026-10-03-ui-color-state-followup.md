# UI Color and Interaction State Follow-up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make selection and disabled states predictable in the existing royal-blue design, expose negative profit clearly, and keep the last Social Order accessible above the New order button.

**Architecture:** Update shared Flutter theme state resolvers, then apply the same selection palette to the tablet order card. Keep financial presentation inside AccountingScreen and retain its current providers and calculations. Preserve distinct icon treatments for list navigation, identity, status, and empty/loading states.

**Tech Stack:** Flutter Material 3, Riverpod, flutter_test, existing English/Myanmar localization.

**Spec:** User screenshots and color/state audit, recorded below; existing visual direction in `docs/DESIGN_PASS.md`, project conventions in `AGENTS.md` and `PROJECT_SPEC.md`.

## Global Constraints

- Retain Claude Code's royal blue/white/navy direction and concurrent workspace edits.
- Money is integer kyat; use the existing Money formatter and localized subtitles.
- Two languages everywhere: English + Myanmar. Any added UI text goes into both ARBs followed by `flutter gen-l10n`.
- No new packages, tables, columns, settings keys, or provider dependencies are needed.
- Before any build: `flutter analyze` clean and full `flutter test` passing.
- Every implemented change belongs in `PROJECT_SPEC.md` §12 and `docs/DESIGN_PASS.md`.
- Finish implementation, verification, and installation on the paired iPhone before calling the fix done. Planning does not mean these fixes are already shipped.

## Audit findings and decisions

1. **Confirmed consistency gap:** selected Analytics date segment uses `secondaryContainer`, while category chips/navigation use `primaryContainer`; tablet selected Social Order also uses `secondaryContainer`. Use the shared primaryContainer/onPrimaryContainer pair for filled selections. Sub-tabs retain a blue underline because they are a different navigation control.
2. **Confirmed state resolver defect:** selected switches return the same custom thumb/track for enabled and disabled states. Respect disabled first and let Flutter's disabled defaults resolve.
3. **Confirmed presentation gap:** negative YTD net profit is rendered with the same muted subtitle style as neutral information. Use AppColors.danger for negative profit and retain the minus sign/localized label. Positive and zero values remain neutral; do not classify all outgoing cash flow as a loss.
4. **Confirmed clearance risk:** OrdersScreen's list has only space3 bottom padding, while the containing hub owns the New order FAB. Reserve trailing scroll space and test the actual embedded hub as well as standalone OrdersScreen.
5. **No contrast repair needed:** measured stock edit pencil contrast is 3.61:1 for healthy, 3.05:1 for low, and 3.28:1 for empty in light mode; dark mode is higher. Keep these icons readable without reducing their opacity further.
6. **Correction to previous review:** plain Accounting list icons and an 80dp empty-state icon plate are intentionally different roles, not inherently an inconsistency. Do not add blue backgrounds to every icon. Preserve neutral list icons, neutral identity tiles, and semantic status plates.
7. **Base palette verified:** light/dark body text, muted text, primary button, status badges, and identity pairing checks pass. Pressed/focused widget overlays require checks against the composited fill, not just palette tokens.
8. User screenshots confirm the installed app can open on the iPhone. Earlier automatic-launch denial does not establish that the current app is unusable; update the previous deployment note using this evidence.

## Verification performed during planning

- Four targeted checks passed: light/dark palette tests and real light/dark SegmentedButton interaction probes. Selected/pressed/focused text contrast was 13.08/10.81/10.81:1 in light mode and 10.62/8.17/8.17:1 in dark mode.
- Busy disabled FilledButton spinner contrast measured 4.19:1 light and 5.42:1 dark; no blanket spinner recoloring is justified. Pointer down/up produced no widget exception.
- Disabled selected switch resolver equality was confirmed from theme resolution. Full page physical-phone Light/Dark, hover, and keyboard traversal remain implementation acceptance checks.
- Temporary audit probes were removed; no application code was changed while planning. Results: `/tmp/pos-color-state-audit.log`.

## Task 1: Shared selection and disabled states

**Files:** Modify `lib/core/theme/app_theme.dart`; create `test/ui_color_states_test.dart`; extend `test/theme_contrast_test.dart` only for missing semantic pairs.

**Interfaces:** Consume AppTheme.light()/dark() and ColorScheme; produce the same theme APIs with state-aware SegmentedButton, NavigationBar/Rail, chip text, and Switch styling. No new public helper is required.

- [x] Add a regression assertion for the selected switch resolver in both brightnesses:

```dart
final theme = AppTheme.light();
const disabledSelection = {WidgetState.disabled, WidgetState.selected};
expect(theme.switchTheme.thumbColor!.resolve(disabledSelection), isNull);
expect(theme.switchTheme.trackColor!.resolve(disabledSelection), isNull);
```

- [x] Pump a real SegmentedButton with Today selected and 7 days unselected; resolve its descendant TextButtonTheme merged with its TextButton style. Assert the selected fill equals primaryContainer and text equals onPrimaryContainer. This must fail on the current grey selection.
- [x] Run `flutter test test/ui_color_states_test.dart --no-pub`; confirm failures name the selected fill/disabled resolver, not missing fixtures.
- [x] Implement the selected segment resolver while preserving Material disabled defaults:

```dart
backgroundColor: WidgetStateProperty.resolveWith((states) {
  if (states.contains(WidgetState.disabled)) return null;
  return states.contains(WidgetState.selected) ? scheme.primaryContainer : null;
}),
foregroundColor: WidgetStateProperty.resolveWith((states) {
  if (states.contains(WidgetState.disabled)) return null;
  return states.contains(WidgetState.selected) ? scheme.onPrimaryContainer : null;
}),
```

Keep the existing shape. For switch thumb/track, add `if (states.contains(WidgetState.disabled)) return null;` before selected handling. Explicitly pair selected navigation icon/label and selected chip text with onPrimaryContainer; preserve onSurfaceVariant for unselected navigation and Flutter defaults for disabled chip text. Do not alter unrelated neutral surfaces.

- [ ] Pump ChoiceChip, FilterChip, NavigationBar, NavigationRail, SegmentedButton, and enabled/disabled Switch under both themes. Hold a pointer down and request keyboard focus on enabled controls. Compute foreground contrast against `Color.alphaBlend(overlay, fill)`; enabled text must remain >=4.5:1, meaningful icons >=3:1. Disabled controls must ignore taps and remain visibly distinct; do not apply enabled contrast requirements to intentionally disabled text.
- [x] Check busy FilledButton/OutlinedButton/TextButton states: spinner visibility, duplicate-action prevention, and restored enabled state. Change ButtonSpinner only if actual backgrounds demonstrate a failure; current callers commonly disable the button while busy.
- [x] Run targeted tests; review theme consumers in admin and mobile before retaining the change.

## Task 2: Tablet selected order and FAB clearance

**Files:** Modify `lib/features/orders/orders_screen.dart`; inspect `lib/features/orders/orders_invoices_hub_screen.dart`; extend `test/orders_invoices_hub_test.dart` and add order cases to `test/ui_ux_followup_test.dart`.

**Interfaces:** Keep `OrdersScreen(embedded: bool)` and hub route behavior. The selected tablet card consumes the selection pair from Task 1.

- [x] Add a phone hub fixture containing enough Social Orders to scroll. Scroll to the final row; assert its bottom is above the New order FAB top, then tap the final row and verify its detail opens. Repeat standalone OrdersScreen and tablet at 1x/2x text.
- [x] Add a tablet selection test: tap one order, assert that card uses primaryContainer, and confirm another card stays neutral. Check status and secondary text remain readable on the selected fill.
- [x] Run these cases before changing code; the bottom-clearance assertion should reproduce the present overlap risk.
- [x] Change `_OrderCard` selection from secondaryContainer to primaryContainer. Keep status badge foreground/fill pairs together.
- [x] Increase final list padding from space3 to at least 96dp (56dp FAB + 16dp bottom margin + 24dp gap), then verify geometry at 2x text. If the real FAB exceeds the allowance, derive extra spacing from its rendered/text-scaled height rather than accepting overlap. Keep the hub's single FAB; do not create a second FAB inside the embedded screen.
- [x] Run `flutter test test/orders_invoices_hub_test.dart test/ui_ux_followup_test.dart --no-pub`; preserve invoices, deep links, staff navigation, and filtering behavior.

## Task 3: Negative profit presentation

**Files:** Modify `lib/features/accounting/accounting_screen.dart`; create `test/accounting_color_states_test.dart`. Read `accounting_providers.dart` and the existing tax statement model to build provider fixtures; do not change their calculations.

**Interfaces:** Existing localized subtitle strings and Money.withCurrency remain unchanged. Add a Color? subtitle foreground in the screen's existing tile records; null means default muted style.

- [x] Pump AccountingScreen with premium license and overridden taxStatementProvider values for netProfit -84810, 0, and 84810. Use the same period boundaries as the screen. Assert displayed money/sign and rendered subtitle color in English/Myanmar and light/dark.
- [x] Run the negative case and confirm the present neutral color fails the danger expectation.
- [x] Compute the negative-profit foreground from the underlying integer, not by parsing the formatted subtitle:

```dart
final negativeProfitColor = taxStatement != null && taxStatement.netProfit < 0
    ? AppColors.of(context).danger
    : null;
```

Carry this color only on the tax-summary tile record. Apply it with `Theme.of(context).textTheme.bodySmall?.copyWith(color: subtitleColor)` when non-null; let other subtitles retain the ListTile default. Keep the minus sign visible, including in Myanmar. Loading/static descriptions stay neutral.

- [x] Test provider updates from negative to zero/positive without reopening the screen; color must clear. Confirm cash flow, net worth, and year-end close subtitles are unaffected by the profit rule.
- [x] Run `flutter test test/accounting_color_states_test.dart test/theme_contrast_test.dart --no-pub`.

## Task 4: Integration verification, documentation, and device delivery

**Files:** Update `PROJECT_SPEC.md` §12 and `docs/DESIGN_PASS.md`; no native dependency changes intended.

- [ ] Compare Sell, Inventory, Orders/Invoices, Analytics/Accounting, Settings, checkout, and admin controls in English/Myanmar, light/dark, 1x/1.3x/2x text. Cover normal, selected, pressed, focused, disabled, loading, error, and empty states where the control supports them. Capture representative widget renders and clearly label them as test renders.
- [x] Check ripple effects by searching every changed theme/widget consumer. Verify existing provider watches, active-shop behavior, and Money formatting remain unchanged; no settings/table migration is introduced.
- [x] Run `flutter analyze` and full `flutter test`; record actual results. Fix failures before building.
- [x] Add changelog and design-pass evidence with the implemented scope, remaining physical-device verification, and the user's screenshots confirming prior launch. Preserve other authors' current notes.
- [x] Follow the deploy skill. Build with `flutter build ios --no-pub --release --dart-define-from-file=env.local.json --dart-define=COMMERCE_UI=true`, then install on paired iPhone `00008150-001A44C41E08401C`. Do not print env contents. Review incidental Podfile/SwiftPM changes before including any native changes.
- [x] Verify app launch with CoreDevice. If iOS requires owner trust/unlock, report that concrete limitation rather than claiming physical interaction checks passed.
- [ ] On the phone verify Today/category/navigation selections, held-press feedback, negative profit, final order accessibility, and Light/Dark. Physical checks not observed must remain explicitly pending.
- [ ] Report what changed, test evidence, device installation/launch outcome, and a short owner verification list. Do not commit unrelated concurrent edits.

## Completion criteria

- Filled selections use one consistent palette; underlines keep their navigation role.
- Disabled selected switches no longer get the enabled custom colors.
- Negative YTD profit keeps its sign and gets a readable danger foreground.
- The final Social Order is tappable without the FAB covering it.
- Real widget state checks, full analysis/tests, changelog, and device delivery complete.
- Decorative/list/identity/status icon roles remain intentional; no blanket blue icon backgrounds.


## Execution ledger — 2026-10-03

- Implemented Tasks 1–3. User steering approved charcoal `#111827` primary text; blue actions/selection and semantic colors retained.
- Ruling: include existing tablet Invoice and printer selected tiles in the selection ripple fix because they explicitly used secondaryContainer; leave neutral payment-method facts unchanged.
- Ruling: keep chip disabled foreground opaque at the style level, since RawChip applies disabled opacity while painting; a second .38 would fade twice.
- Ruling: fix the narrow tracking field/action overflow revealed by the new final-order detail tests; no routing/data change.
- Shared theme RED reproduced eight state failures; green checks passed before final ripple checks. Accounting RED reproduced four danger-vs-muted failures; eight new accounting checks pass. Orders RED reproduced final row coverage and selected Paid contrast; 22 new checks pass after correction.
- Read-only review completed; no remaining production defect. Current real interaction probes cover selected segment focus/press and disabled control taps. Not every navigation/chip focus/press combination has physical-device evidence.
- Full analysis/tests and phone installation remain in progress. Completion below will record actual outcomes.


### Final automated verification

- `flutter analyze`: clean (4.3 seconds), `/tmp/pos-color-analyze.log`.
- Full `flutter test --no-pub --reporter expanded`: **902/902 pass**, `/tmp/pos-color-full-tests-final.log`. Includes the final Invoice/printer ripple and actual selected-segment focus/held-press assertion.
- Read-only final review: no actionable finding; selected Invoice/printer labels and their semantic foregrounds have adequate contrast in light/dark.
- Database/provider/settings ripple check: presentation-only; no new data dependencies or keys. Shared Material control consumers were searched, selected tiles aligned, neutral order payment-method facts retained.
- Signed release build succeeded (42.7 MB), `/tmp/pos-color-ios-build.log`. CoreDevice installation succeeded, `/tmp/pos-color-install.log`; automatic app launch succeeded, `/tmp/pos-color-launch.log`.
- Generated Podfile.lock was restored to its pre-build contents; earlier Package.resolved deletions were left unchanged.
- Physical navigation/chip interaction matrices and new phone screenshots are not yet observed. Owner verification: Today/category/nav selection, font readability in light/dark, negative-profit color, final Social Order detail access.
