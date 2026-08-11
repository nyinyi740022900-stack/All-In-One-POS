# App-wide design pass — progress ledger

**Purpose:** this file is the single source of truth for the redesign, so the
work can be **stopped at any point and resumed in a fresh session** without
re-deriving context. Whoever picks this up next: read this file first, then
`git log --oneline -5`, then `git status`.

> **Resume prompt** (paste into a new session):
> `Read docs/DESIGN_PASS.md and continue the design pass from the first phase that isn't ✅.`

---

## ⚠️ IA decision (2026-08-11): bottom nav goes from 6 tabs to 5 — Orders + Invoices merge

**Trigger:** the user shared a 3-tip mobile-UI reference (nav-item-count / hamburger / icon-label best practices). Two of the three tips (hamburger hiding actions, icon-without-label) were already satisfied by this app — no hamburger menu anywhere in the codebase, and the bottom nav already uses `NavigationDestinationLabelBehavior.alwaysShow` with explicit labels. The **third tip — "fewer nav items"** was not: 6 top-level destinations (Sell, Inventory, Orders, Invoices, Analytics, Settings; the tip's own "bad" example showed 7 as cramped, "good" showed 4-5) is genuinely on the crowded side. The user asked for this to actually be fixed, not just diagnosed.

**Analysis before deciding what to merge:** read `orders_screen.dart` and `invoices_screen.dart` directly rather than assuming they're duplicates. They are **not** — `OrdersScreen`'s own doc comment calls it "The Social Orders list," i.e. pre-sale orders arriving from social channels (Facebook/Viber) before being converted to a POS sale; `InvoicesScreen` is the ledger of completed sales/receipts. Different domains, different moments in the sales lifecycle — but adjacent enough (both are "a record of a transaction") that nesting them under one nav destination as two sub-tabs is a defensible merge, unlike e.g. forcing Analytics under Settings (Analytics is a primary, frequent-use owner screen — unlike the occasional-use admin screens already tucked inside Settings like Owner's Equity/Accounts Payable — and stays top-level).

**Decision, approved by the user:** merge Orders + Invoices into one bottom-nav destination with two sub-tabs inside. Nav goes from 6 → 5 (Sell, Inventory, **Orders** [sub-tabs: Orders / Invoices], Analytics, Settings) — lands in the tip's "good" 4-5 range. Analytics stays top-level, not folded into Settings.

**Constraints the implementation must respect** (found by grepping before scoping, not discovered mid-implementation):
- `analytics_screen.dart` has three `context.go('/invoices')` deep links (lines ~131, 162, 177) that must keep working — the `/invoices` URL should keep resolving to the Invoices sub-tab specifically, not just redirect to a bare `/orders`.
- No test file references `OrdersScreen`/`InvoicesScreen`/`'/orders'`/`'/invoices'` directly (checked via grep across `test/`) — low test-breakage risk from the route restructure itself.
- `OrdersScreen` owns a `FloatingActionButton` (new order); `InvoicesScreen` owns an `AppBar` action (sales-report icon) but no FAB. Whatever merges these into one Scaffold needs the chrome (title, actions, FAB) to follow the selected sub-tab, not just the body.
- CLAUDE.md's stack section states "6 tabs" as an architecture fact — must be corrected in the same change-set, not left stale.

See the Phase C section below for implementation status.

---

## ⚠️ Direction history — read this before touching color

**v1 (2026-08-10, superseded same day): cream + gold**, matching
`assets/branding/app_icon_1024.png`. **The user rejected this outright** —
both the color and the screens built on it. The app icon was only a
placeholder and should never have driven the palette; deciding color from an
unfinished logo was the mistake. Don't resurrect `#FBF8F2`/`#B8860B` or
anything cream/gold-adjacent.

**v2 (2026-08-10, current — SHIPPED 2026-08-11): deep green + white/light-neutral surface.**
Final values as built: light `primary #0F5C3E` on a `#F6F8F7` page with white
cards; dark `primary #4FC08D` on a `#101512` page. `AppColors.success` was
re-hued to `#3B7518`/`#84CE5E` (yellow-leaning, ~97-100°) to stay distinct
from primary's ~157°. See the 2026-08-11 session-log entry for the reasoning.
Reached after actually researching Dribbble and real production POS software
(not guessing) — see the reference set in the session that made this call for
the curated images and attribution. Approved anchors:
- Primary/accent: emerald/forest green, roughly the `#0F5C3E` family —
  **one CTA/selected-state per screen**, not a saturated wash. Pick the exact
  contrast-safe value; the ballpark is directional, not final.
- Surface: white / light-neutral grey — **no cream tint**.
- **Primary-brand green and semantic "success" green must stay visually
  distinct** (different hue/saturation) — otherwise a success badge is
  indistinguishable from ordinary primary-brand chrome. This didn't matter in
  v1 (gold primary, green success were already distinct) — it matters now.
- Structure reference: "QuickBill"-style checkout (Dribbble, Naveen —
  cart line = photo/icon + name + qty stepper + right-aligned tabular price;
  subtotal/discount/tax/total summary block; payment method as icon-bearing
  cards, not a dropdown). Also worth carrying forward: pastel (not solid)
  status pills for order/queue states, from a second reference (Suhayel Ahmed
  Nasim, "Restaurant POS System") — mint/peach/lavender rather than solid
  green/orange/red.
- Contrast is the constraint, not the swatch — verify 4.5:1, don't assume it.
  Dark mode must be designed, not auto-derived.

- **Foundation first.** The "beginner look" lives in the thin token layer, not
  the screens (Phases 1–6 already made screens *use* tokens). Fix tokens, then
  screens.
- **Owner:** the `ui-ux-designer` subagent (`.claude/agents/ui-ux-designer.md`,
  Opus). Route UI work through it rather than editing screens ad hoc.

## The audit that started this (2026-08-10)

| # | Finding | Evidence |
|---|---|---|
| 1 | No `textTheme` at all — default Roboto, untuned | `app_theme.dart` had no `textTheme:` |
| 2 | `NotoSansMyanmar-{Regular,Bold}.ttf` bundled under `assets:` but never registered as a `fonts:` family | `pubspec.yaml` |
| 3 | Untouched `ColorScheme.fromSeed(teal)` — brand mismatch | `app_theme.dart:71` |
| 4 | Single `radius = 12` for every component role | `app_theme.dart:81` |
| 5 | No elevation/shadow language — 1 `BoxShadow` in the whole repo | `grep BoxShadow lib` |
| 6 | Money has no `FontFeature.tabularFigures()` — price columns wobble | 0 hits |
| 7 | No motion tokens (duration/curve) | — |
| 8 | 73 raw `Card(`, 31 `TextStyle(fontSize:)` — screens hand-roll their vocabulary | `grep` |

---

## Phases

Legend: ✅ done · 🔄 in progress · 🔜 not started

### Phase A — Foundation + Entry/Auth + Sell ✅ (v2 — deep green, verified live)
Tokens must serve the WHOLE app (dense tables, long settings lists, form-heavy
editors, full-bleed brand surfaces) — not just Sell.

**Status: complete on the v2 (deep green + light-neutral) palette.** The v1
cream+gold `ColorScheme` was rebuilt from scratch; everything structural from
v1 (type scale, radius/elevation/motion, tabular figures, Myanmar font
registration, the shared widgets) carried forward unchanged and was re-verified
on the new palette. Every box below has now been checked **on a device**, in
`en` + `my` × light + dark — the gap v1 left open.

- [x] `lib/core/theme/app_theme.dart` — full custom `TextTheme` (all 15 roles,
      taller line-heights for Myanmar diacritics); hand-picked **deep-green**
      `ColorScheme` for light AND dark, seeded from `#0F5C3E` then pinned to
      contrast-checked overrides (light `primary #0F5C3E` 8.0:1 on white,
      `primaryContainer #C9E9D8`/`onPrimaryContainer #06301F` 11.1:1; dark
      `primary #4FC08D` 8.1:1 on `surface #101512`, `onPrimary #00301E`
      6.4:1). Surfaces are a light-neutral ramp with ~2% green chroma — no
      cream anywhere. `surfaceBright`/`surfaceDim`/`surfaceTint`/
      `inversePrimary` are pinned too, not left to the seed.
      Radius scale (`radiusXs/Sm/Md/Lg/Full`, `radius` kept as a deprecated
      alias = `radiusMd` for 3 old call sites), flat-cards-by-default +
      `surfaceContainerLowest..Highest` tonal ladder + one deliberate
      `dockedBarShadow`/`elevationFloating` token for transient/floating
      chrome (dialogs, bottom sheets, snackbars, popup menus, Sell's sticky
      checkout bar), motion tokens (`motionFast/Medium/Slow`,
      `curveStandard/Emphasized`), `AppTheme.tabularFigures`.
- [x] `AppColors` — `success` re-hued to a yellow-leaning leaf green
      (`#3B7518` light / `#84CE5E` dark, hue ~97-100°) so it stays legible as
      a *different signal* from the blue-leaning forest `primary` (hue ~157°);
      `warning` pushed to a true orange (`#9E4E00` / `#F2A65A`, hue ~30°),
      clear of the gold band; `danger` aligned with `ColorScheme.error`.
      New **soft-fill tier** (`successSurface`/`warningSurface`/
      `dangerSurface`, each ≥4.5:1 against its solid partner) — the pastel
      pill/banner substrate, so nothing hand-rolls `withValues(alpha: 0.12)`
      again. Orders' pastel status pills (a later phase) now have tokens
      waiting for them.
- [x] `pubspec.yaml` — registered `NotoSansMyanmar` (Regular/Bold) as a real
      `fonts:` family; `AppTheme.light/dark(localeCode:)` now takes the
      active locale and sets it as the primary family for `my` (fallback
      `Roboto`) or as a `fontFamilyFallback` for `en` (so a Myanmar customer
      name typed under the English UI still renders, not tofu). `app.dart`
      passes `localeCode` through.
- [x] `lib/core/widgets/app_widgets.dart` — added `MoneyText` (tabular
      figures, right-aligned), `SummaryRow` (label/value row using
      `MoneyText`), `InlineErrorBanner` (soft-danger form error, replaces
      ad-hoc red `Text`), `BrandHero`, and `AuthScaffold` (centered,
      width-capped, keyboard-safe shell for chromeless entry screens).
      **`BrandHero` was rebuilt, not rubber-stamped:** it no longer renders
      `assets/branding/app_icon_1024.png` at all. That placeholder is a gold
      glyph on a cream plate, so painting it would have dropped a
      cream-and-gold rectangle into the middle of every green/white entry
      screen — the loudest possible "unfinished" tell. It now draws a
      `primaryContainer` plate + storefront glyph + `Semantics` label from
      theme tokens: correct in both brightnesses, zero asset weight, and a
      one-widget swap once a real logo exists.
- [x] Entry/Auth done: `onboarding/onboarding_flow.dart` (BrandHero on
      Welcome, `ContentWidth`-capped pages, token spacing, autofillHints),
      `account/shop_login_screen.dart` (replaced a fixed-`SizedBox(height:
      260)` + `TabBarView` — clipped 2-line Myanmar labels — with an
      `AnimatedSize` + manual tab switch; `ContentWidth`-capped),
      `account/reset_password_screen.dart` (now `AuthScaffold`),
      `account/forgot_password_dialog.dart` (autofillHints), 
      `account/auth_password_field.dart` (a11y show/hide label via new
      `accountShowPassword`/`accountHidePassword` keys, `textInputAction`
      chaining, `errorText`). `license/license_screen.dart` reviewed but
      **not touched** — it contains zero color literals (grep-confirmed), so
      it is palette-driven by construction and gets the new theme for free.
      `account/password_strength.dart` moved off raw
      `Colors.orange/amber/green` onto `AppColors` (its amber step sat
      literally in the gold band, and none of the three were ever
      contrast-checked against either surface).
      **Bug found by finally running these screens on a device:**
      `auth_password_field.dart`'s show/hide `IconButton` carried a
      `tooltip:`, and `app.dart` returns `OnboardingFlow` /
      `ResetPasswordScreen` / `ModeMigrateFlow` / `OnlineDailyGate` from
      `MaterialApp.router`'s `builder:` — which sits **above** the Router, so
      those flows have no `Overlay` ancestor and the Tooltip threw
      "No Overlay widget found", painting a red error box over the online
      sign-up form. Tooltip removed; the `Semantics` wrapper already carried
      the a11y label. *Anything added to a builder-hosted flow must avoid
      `Tooltip`/`showDialog`-style Overlay/Navigator dependencies.*
- [x] Sell done: `sell/sell_screen.dart` (`MoneyText` for prices/cart
      totals, `_ProductCard` bump animation on tap via `AnimatedScale` +
      `motionFast`/`curveEmphasized` — the add-to-cart micro-feedback,
      docked-bar shadow on the sticky checkout bar; both licence banners now
      use the `AppColors` soft-fill tier so they share one banner language
      instead of one alpha-wash + one solid `errorContainer`),
      `sell/checkout_sheet.dart`
      (`SummaryRow` replaces the private `_row` helper, `MoneyText` for line
      totals/discounts, customer fields grouped in a `Card`, `SectionHeader`
      for "Payment method", success snackbar gets a check icon; payment
      methods are now **icon-bearing chips** per the approved QuickBill
      reference — new `paymentIcon()` in `payment_labels.dart` maps codes by
      *kind of money movement* so shop-created custom accounts still land
      sensibly, and `showCheckmark: false` because Material paints the
      selected checkmark on top of the avatar and smudged the chosen icon).
      `sell/cart.dart` is pure logic — untouched, as expected.

### Phase A2 — Sell/Checkout structure ✅ (2026-08-11, the reference pattern passes 1–2 skipped)

Passes 1 and 2 recolored and tokenized these two screens but never applied the
**structural** lesson from the seven references that were researched and
approved *before* any of this work started. This pass did that and nothing else
about color.

- [x] **Photo-forward product cards.** `_ProductCard` used to be
      `Expanded(child: Text(name))` + a price — i.e. a large blank flexible
      region shaped exactly like a photo slot, and `itemBuilder` never passed
      `imageUrl` at all even though `Product.imageUrl` and a working upload
      flow (`product_edit_screen.dart`) have existed the whole time. Now:
      full-bleed photo band, then a fixed-height two-line name, then the price.
- [x] **`ProductThumb` (`core/widgets/app_widgets.dart`)** — one shared mark
      for the Sell grid, the checkout cart lines and the tablet cart panel.
      Before this there were two hand-rolled `Image.network` call sites
      (`product_edit_screen.dart:282`, `storefront_page.dart:353`) and none in
      Sell/Checkout; there was no shared helper to reuse, so this is the first
      one. Those two older call sites were **left alone** — they belong to the
      Inventory and Web phases.
- [x] **`AppColors.identityFills`/`identityOnFills` + `identityTone()`** — the
      no-photo plate's tokens. See the design note below.
- [x] Grid geometry retuned for the new content (`childAspectRatio` 1.1 ➜
      0.68, `maxCrossAxisExtent` 180/210 ➜ 132/168 — the delegate counts
      spacing into the extent, so 180 was silently giving **two** columns on a
      402pt phone).
- [x] Out-of-stock: dimmed photo + muted text + soft-fill badge over the
      image, and the tap now reaches the caller's snackbar instead of being
      swallowed into a dead ripple.
- [x] Checkout cart lines: thumbnail + name + unit price / discount action /
      trailing 40dp tonal stepper above a right-aligned tabular line total,
      hairline-separated.
- [x] Checkout: **pinned footer** (scrolling body + docked "Confirm sale" bar
      carrying the total) and a max height so the sheet stays below the status
      bar with its drag handle reachable.
- [x] Category bar: counts per chip, thumb-sized targets, content-sized height.

**The no-photo fallback, and why.** Most products in a shop that typed its
catalogue in by hand will never be photographed, so this is the *normal* state,
not an error state. It renders a tonal plate with the product's initials —
never a broken-image glyph, never an empty grey box, and never a spinner that
reflows the tile mid-sale. A missing URL, a failed decode and *being offline*
all land on the same plate, which is the offline-first requirement stated as a
visual rule. Four plate colors, hashed stably off the product name so one
product keeps one color everywhere: sage, teal, slate-blue, lilac. Constraints
that produced that set — **cool half of the wheel only**, because warm hues are
already spoken for (`warning` orange, `danger` red, `success` leaf), so a plate
can never be misread as a status; and **no `primaryContainer`**, because that
fill means "selected / primary action" in this app and a grid full of it would
compete with the one CTA that matters. **Latin gets two letters, Myanmar gets
one** — the two-letter rule applied to Myanmar produced things like "အုဘီ",
four code points that read as a misspelled word rather than an initial, while
one grapheme cluster ("ကို", "ရေ", "ရွှေ") is a whole syllable. Cutting on
grapheme clusters (not code units) is what stops a stranded combining mark
rendering as a dotted circle; five unit tests pin this
(`test/product_thumb_initials_test.dart`).

**Audited and kept** (traceable to a reference, so not touched): the checkout
summary block (`SummaryRow` + `MoneyText`, tabular and right-aligned — matches
QuickBill's subtotal/discount/total stack), the icon-bearing payment-method
chips from pass 2, the deep-green `ColorScheme`, the type scale, and the
radius/elevation/motion tokens.

**Audited and changed** because it was pre-research default rather than a
reference decision: the category bar (bare `ChoiceChip`s in a fixed
`SizedBox(height: 48)`, no counts — Cirice's carries counts and more weight),
the cart line's flat 6-widget row, and the checkout CTA's position.

**Crash found by running it.** `_editLineDiscount` created a
`TextEditingController`, `await`ed `showDialog`, then disposed it. That future
resolves when the route is *popped*, not when its exit animation finishes, so
the controller was disposed under a still-mounted `TextField` — "A
TextEditingController was used after being disposed", then a cascade of
framework assertions and a red screen. Fixed here by moving the controller into
a `StatefulWidget` dialog. **The identical pattern is still live in
`categories_screen.dart:66-89`** (where it was actually observed crashing, on
Inventory ➜ Categories ➜ add) **and `settings_screen.dart:~642`** — left for
the Inventory and Settings phases rather than widening this diff.

### Phase B — Inventory 🔜
`inventory_screen.dart`, `product_edit_screen.dart`, `categories_screen.dart`,
`stock_movements_screen.dart`, `stock_history_screen.dart`,
`sell/barcode_scanner_screen.dart`

### Phase C — Orders + Invoices 🔄 IA merge ✅ done; token retrofit still pending
`orders_screen.dart`, `invoices_screen.dart`, `invoice_detail_screen.dart`,
`sales_report_screen.dart`, `customers_screen.dart`

- [x] New merged nav destination (5 tabs total): `OrdersScreen`/`InvoicesScreen`
      each gained an `embedded` flag that returns body-only, hosted by the new
      `orders/orders_invoices_hub_screen.dart` under one `Scaffold` whose
      title/actions/FAB follow the selected sub-tab.
- [x] `router.dart`: both branches collapsed into one `StatefulShellBranch`
      carrying two `GoRoute`s (`/orders`, `/invoices`) pointing at the hub with
      different initial sub-tabs — both URLs and Analytics' three
      `context.go('/invoices')` deep links verified working unchanged. `_Dest`
      list in `_ShellScaffold` is now 5 entries.
- [x] `CLAUDE.md` stack section corrected from "6 tabs" to the 5-tab structure.
- [x] Token/visual pass on the new hub screen itself (nav-scoped only).
- [ ] Full Phase C token retrofit of `invoice_detail_screen.dart`,
      `sales_report_screen.dart`, `customers_screen.dart` — **still pending**,
      deliberately out of scope for the IA pass. Also still open from Phase A:
      the raw `Colors.green/orange` status pills in
      `orders/order_detail_sheet.dart`, `invoices/invoice_view.dart` and
      `order_labels.dart` that the `AppColors` soft-fill tier was built for.

### Phase D — Analytics + Money 🔜
`analytics_screen.dart`, `pnl_screen.dart`, `credit_screen.dart`,
`cash_session_screen.dart`, `expense_screen.dart`,
`recurring_expenses_screen.dart`, `equity_screen.dart`,
`payment_accounts_screen.dart`

### Phase E — Settings + Back-office 🔜
`settings_screen.dart`, `shop_profile_screen.dart`,
**`branches_screen.dart` (1,370 lines — likely its own sub-pass)**,
`staff_accounts_screen.dart`, `staff_members_screen.dart`,
`suppliers_screen.dart`, `accounts_payable_screen.dart`,
`purchase_orders_screen.dart`, `purchase_order_editor_screen.dart`,
`purchase_order_detail_screen.dart`, `printer_settings_screen.dart`,
`label_printer_settings_screen.dart`, `backup_screen.dart`,
`referral_screen.dart`, `sync_issues_screen.dart`, `help_guide_screen.dart`

### Phase F — Web surfaces 🔜
`admin/admin_dashboard_screen.dart`, `admin/admin_login_screen.dart`,
`storefront/storefront_screen.dart`, `storefront/storefront_page.dart`,
`invoices_web/*`

---

## Working agreement (applies to every phase)

- **One phase = one commit.** Commit at the end of each phase so an
  interrupted session never loses work and any phase can be `git revert`ed
  independently. Do not batch phases into one commit.
- **Stop cleanly, never mid-file.** If you are running low on budget/context,
  finish the file you are in, run analyze, update this ledger, commit, and
  stop. A half-edited file is the only genuinely bad outcome.
- **Update this ledger in the same change-set** as the code — tick the boxes,
  set the phase status, and add a line under Session log below.
- Definition of done per phase: `flutter analyze` clean · `flutter test` all
  pass · CLAUDE.md ripple-effect check · iOS Simulator screenshots in
  **en + my × light + dark** · new copy in BOTH `.arb` files + `flutter gen-l10n`
  · `PROJECT_SPEC.md` §12 changelog entry.

## Session log

| Date | Phase | What landed | Left for next |
|---|---|---|---|
| 2026-08-10 | — | Audit + `ui-ux-designer` subagent upgraded to Opus (rubric, Dribbble protocol, Simulator verification); direction and phasing agreed; this ledger created | Phase A |
| 2026-08-10 | A | Foundation rebuilt (`app_theme.dart`, `pubspec.yaml` font registration, `app_widgets.dart` new components) + Entry/Auth (onboarding, shop login, reset password, forgot-password dialog, auth password field) + Sell/Checkout (`sell_screen.dart`, `checkout_sheet.dart`) all retro-fitted to the new tokens. `flutter analyze` clean, all 362 tests pass. Two new i18n keys added (`accountShowPassword`/`accountHidePassword`, `inventoryOutOfStock`) in both `.arb` files + `flutter gen-l10n`. `license_screen.dart` reviewed, needed no changes (already Phase-5 token-compliant). | Phase A functionally complete. |
| 2026-08-10 | A | **Coordinator (main session) closed the live-verification gap the subagent flagged**, using `mcp__Claude_Code_iOS_Simulator__control` directly (not available to the subagent's sandbox). `flutter build ios --simulator --debug --dart-define-from-file=env.local.json`, installed on a booted iPhone 17 Pro. Verified live: **Sell screen and Checkout sheet, in both light and dark** (`xcrun simctl ui <udid> appearance dark|light`) — product grid renders Myanmar product names cleanly against the cream surface with gold prices, the docked checkout bar shows the `dockedBarShadow` lift correctly, the Checkout sheet's `SummaryRow`/`MoneyText`/payment-method chips/`Confirm sale` button all read well in both brightnesses with good contrast (light-gold-on-near-black text in dark mode is legible). Also incidentally verified the **Settings screen** (untouched by this pass — ripple-effect spot check) renders correctly. Also code-reviewed every diff by hand (not just re-running `flutter analyze`/`flutter test`, which were re-run and confirmed clean/362-passing independently of the subagent's own report). | Entry/Auth screens (onboarding welcome, Shop login/register) were **not reached live this session** — this test account's Shop-login menu item under Settings › Finance appears gated (tap did not navigate; likely an owner/role or `isOnlineModeProvider` condition not met by this build's local data) and there is no discovered "sign out" path to force the onboarding flow to re-run without deleting local app data. Entry/Auth confidence for this phase rests on code review only (`AuthScaffold`/`BrandHero` reuse the exact patterns just confirmed working on Sell/Checkout), not a screenshot. If a future session wants this closed: either delete-and-reinstall the app in the simulator (`xcrun simctl uninstall`) to force fresh onboarding, or find a role/account that unlocks the Shop-login menu item. |
| 2026-08-10 | A | **v1 rejected outright by the user** — both the cream+gold color and the screens built on it. Root cause: the palette was decided from the app's placeholder logo instead of research. Coordinator did real research this time: browsed Dribbble (searched by problem — "pos-app" tag, "accounting-software" tag, "retail pos mobile" — not vibe), downloaded 6 shots with attribution, plus 1 real production app (Loyverse POS, chosen for Myanmar-market relevance — 1M+ businesses, 170 countries), and showed all 7 to the user before writing any code. User picked: **deep green + white/light-neutral surface** (no cream, no gold), plus two structural patterns to adopt — QuickBill-style checkout line items (Naveen's "Mobile Smart POS System" shot) and pastel status pills for order/queue states (Suhayel Ahmed Nasim's "Restaurant POS System" shot). | **Rebuild not started yet** — this log entry documents the decision; the next entry should document the v2 implementation. See the "Direction history" section at the top of this file for the full palette/structure spec before starting. |
| 2026-08-11 | A | **v2 palette shipped and verified live — Phase A ✅.** Exact values chosen: light `primary #0F5C3E` (the approved anchor, kept literal; 8.0:1 with white), `primaryContainer #C9E9D8` / `onPrimaryContainer #06301F` (11.1:1); dark `primary #4FC08D` (same hue family lifted to read on near-black, 8.1:1) / `onPrimary #00301E` (6.4:1). Surfaces: light `#F6F8F7` page + white cards + `#DCE3DF` hairline; dark `#101512` page + `#0B0F0D` recessed cards. Neutrals carry ~2% green chroma — enough that white cards read as white, not enough to look tinted; no cream. **Success-vs-primary was resolved by hue rotation, not by shade:** primary is blue-leaning forest (~157°), success is yellow-leaning leaf (`#3B7518` light / `#84CE5E` dark, ~97-100°) — ~60° apart plus a luminance step. Verified on the worst-case adjacency in the app (the register form, where the "strong" password bar sits ~3px above the primary CTA): they read as two different greens in both brightnesses, with more separation in dark than light. `warning` moved to a true orange (`#9E4E00`/`#F2A65A`, ~30°) to stay out of the gold band. Added a soft-fill tier (`successSurface`/`warningSurface`/`dangerSurface`) so the future pastel status pills have tokens and nothing hand-rolls alpha washes. **`BrandHero`: stopped rendering the placeholder PNG entirely** — it's a gold glyph on a cream plate and would have re-imported exactly what the user rejected; it now draws a `primaryContainer` plate + storefront glyph from theme tokens, with a `Semantics` label. Also adopted the approved QuickBill payment-method pattern (icon-bearing chips). **Live verification (this session's environment DID have simulator access, unlike the subagent's last time):** iPhone 17 Pro — Sell grid, docked checkout bar, Checkout sheet in en + my × light + dark; Settings as the untouched ripple spot-check. iPad A16, fresh install — onboarding mode-choice, Welcome (`BrandHero` at 64 and 88), the licence page, and the online register form incl. the password-strength meter, in my/en × light/dark. `flutter analyze` clean, 362/362 tests pass. | **Real bug caught by that verification:** `auth_password_field.dart`'s `tooltip:` threw "No Overlay widget found" and painted a red error box across the online sign-up form, because `app.dart` hosts onboarding/reset/migrate/daily-gate from `MaterialApp.router`'s `builder:`, which sits above the Router. Fixed by removing the tooltip. **Two follow-ups for later phases, deliberately not done here** (a recolor shouldn't turn into a repo-wide reskin): (1) `analytics_screen.dart`'s KPI grid is a rainbow of raw `Colors.teal/green/deepOrange/indigo/orange/blueGrey` and its `Colors.green` tile now sits near the brand green — Analytics phase; (2) `orders/order_detail_sheet.dart`, `invoices/invoice_view.dart`, `order_labels.dart` and `admin/admin_dashboard_widgets.dart` still use raw `Colors.green/orange` for status — these are the exact call sites the new pastel soft-fill tier was built for. |

| 2026-08-11 | A | **Coordinator independently re-verified the v2 rebuild** (trust-but-verify, not a rubber stamp of the subagent's report): re-ran `flutter analyze` (clean) and `flutter test` (362/362) myself; grepped `lib/` and `test/` for every v1 gold/cream hex — zero hits; read the `_colorScheme`/`BrandHero` diffs by hand and confirmed the stated contrast pairings look right in the code, not just the docstring. Then did the live verification the subagent *couldn't* finish itself: rebuilt (`flutter build ios --simulator`), confirmed **Sell grid + docked checkout bar + Checkout sheet** on iPhone 17 Pro in `my` locale × light/dark — clean deep-green-on-white, tabular prices, no cream/gold anywhere. Then fresh-installed on iPad A16 (`simctl uninstall` + `install`) specifically to reach the screens gated behind onboarding: **mode-choice page, Welcome (`BrandHero`), and the online register form** (shop name/email/password/confirm, show/hide eye icons, password-strength meter, "ဆိုင် Account ဖန်တီးမည်" CTA) in `my` × light/dark — confirmed the `auth_password_field.dart` Overlay-crash fix actually holds (no red error box, eye icons render fine). This closes the "not verified live" gap the subagent flagged for `shop_login_screen.dart`'s register tab. Still not independently reached: the *sign-in* tab specifically (vs. register) and `forgot_password_dialog.dart` — both need an existing account to test against, lower risk since they share the same `AuthPasswordField`/`AuthScaffold` already confirmed elsewhere. | Ready to show the user before deciding whether to commit Phase A and move to Phase B. The two follow-ups the subagent logged (Analytics KPI rainbow, raw-color status pills in Orders/Invoices) are real and correctly deferred — pick them up when those phases start, not before. |

| 2026-08-11 | A2 | **Sell/Checkout structural rework — the third pass on these screens, and the one that finally applied the reference set.** Full detail in the "Phase A2" section above. Short version: products are now photo-forward cards with a designed initials plate when there's no photo (new shared `ProductThumb` + new `AppColors.identityTone` tokens); cart lines in the checkout sheet carry the same mark, with the stepper and a right-aligned tabular line total on the trailing edge; the checkout CTA moved into a pinned footer carrying the total; the category bar gained counts and lost its fixed 48pt height. Grid geometry retuned (`childAspectRatio` 1.1 ➜ 0.68, tile extent 180/210 ➜ 132/168 — the old value was quietly producing 2 columns, not 3, on a phone). Three new i18n keys (`inventoryOutOfStockBadge`, `sellDecreaseQty`, `sellIncreaseQty`) in both `.arb`s + `flutter gen-l10n`. `flutter analyze` clean, **367 tests pass** (362 + 5 new grapheme/initials tests). **Verified live** on iPhone 17 Pro in en + my × light + dark: grid with real photos and with the plate, out-of-stock tile, category bar with counts, and the whole checkout sheet including the per-line discount dialog; device log clean of Flutter errors after the run. | Two things could not be observed on screen and were reasoned from code instead: the 1s stock-cap snackbar on an out-of-stock tap (fires and clears faster than a screenshot round-trip), and a product photo *failing* to load — every URL in the seed catalogue resolved, so only the missing-URL branch of the fallback was seen live, not the error branch (same code path, one `errorBuilder` line apart). **Handoff:** the `TextEditingController`-disposed-too-early crash documented above is still live in `categories_screen.dart:66-89` and `settings_screen.dart:~642` — fix those when their phases start; it red-screens the app, it is not cosmetic. Also still open from pass 2: the Analytics KPI rainbow and the raw-`Colors` status pills in Orders/Invoices. |

| 2026-08-11 | A2 | **Coordinator independently re-verified the structural rework** (trust-but-verify): re-ran `flutter analyze` (clean) and `flutter test test/product_thumb_initials_test.dart` (5/5) myself; read `ProductThumb`/`initialsFor`/the `_LineDiscountDialog` fix by hand — the controller now lives inside its own `StatefulWidget` tied to the dialog's actual lifecycle, not a `Future` that resolves on pop, which is the correct fix for the dispose-order bug. Rebuilt and live-verified on iPhone 17 Pro, `my` locale, light + dark: Sell grid shows real photos where seed data has an `imageUrl` and the initials plate where it doesn't (one seed product happened to have unrelated stock-photo URLs attached — flowers/waterfall/fashion-card placeholders, pre-existing local seed data, not something this pass introduced or a defect in `ProductThumb`, which correctly renders whatever URL it's given); category chips show live counts ("All 6" / "Drinks 0"); checkout sheet's cart line shows the same thumbnail plus a right-aligned tabular line total; **exercised the exact crash end-to-end** — opened the per-line discount dialog, typed "50", tapped Save, confirmed the sheet updated to the discounted total (700→650 Ks) with no red error screen and no console error, then reopened the discount dialog a second time to confirm the widget survives repeat use, not just first-open. | Did not independently verify the out-of-stock dimmed tile, the "Sold out" badge treatment, or dark-mode contrast on the initials-plate colors specifically (checked general dark-mode legibility on the checkout sheet, not each of the four `identityFills` tones individually) — low risk, but worth a glance next time that data is on screen. The two live `TextEditingController`-dispose bugs the subagent found in `categories_screen.dart`/`settings_screen.dart` are still unfixed — real crashes, not cosmetic, pick up when those phases start. |

| 2026-08-11 | C (IA) | **Bottom nav 6 → 5: Orders + Invoices merged into one destination with two sub-tabs.** New `lib/features/orders/orders_invoices_hub_screen.dart` owns one `Scaffold`; `OrdersScreen`/`InvoicesScreen` each gained `embedded` (default `false`, so standalone use is unchanged) which returns the body only — the split-view `Row`, filters and `_selectedOrderId`/`_selectedSaleId` selection logic were moved into a local variable, not rewritten. **Chrome-follows-sub-tab** is done with a cached-index `TabController` listener: the controller notifies on every frame of a swipe (its `offset` changes), so the listener compares `_tabs.index` against a stored `_index` and only calls `setState` on a real change — an unguarded `setState` there would rebuild the whole Scaffold per frame on a cheap panel. `Scaffold` animates the FAB in/out for free when it becomes null. Merged destination: **`Icons.receipt_long` + `l.navOrders`** — `receipt_long` ("a record of a transaction") covers both halves, and it also removes the old outlier (`dashboard_customize_outlined` was the only outlined icon in an otherwise filled nav set). `router.dart`: one `StatefulShellBranch` with two `GoRoute`s (`/orders` first = branch initial location, `/invoices` second), `_Dest` list down to 5. Title follows the sub-tab: `l.ordersTitle` ("Social Orders") on Orders — more informative than the tab's own label — and `l.navInvoices` on Invoices. **No new i18n keys.** Tab height is computed from the label's own line box (`max(48, scaledFontSize * height + space4)`) instead of Material's fixed 46dp, so Myanmar's stacked diacritics and large text scales can't clip. `flutter analyze` clean, **370 tests pass** (367 + 3 new). | **Three existing tests asserted the old nav structure and the pre-task grep missed them** (they match on `NavigationDestination` counts, not on `OrdersScreen`/`'/orders'`): `app_smoke_test.dart` (6→5) and `role_based_tabs_test.dart` (owner 6→5, staff 5→4). Updated, with the counts explained in comments. Added `test/orders_invoices_hub_test.dart` (3 cases) pinning the two things that would silently rot: the chrome swap in both directions, and `/invoices` still opening the Invoices sub-tab. Note for whoever writes widget tests here: the Invoices sub-tab needs `salesStreamProvider` **plus** `creditSalesProvider`/`repaymentsProvider` overridden with `Stream.value` or the real Drift watches leave a pending close-timer and the test fails at teardown. **Live-verified** on iPhone 17 Pro (en + my × light + dark): 5-tab bar, both sub-tabs, chrome swapping both ways, and the real Analytics → `/invoices` deep link landing on the Invoices sub-tab *even though the live hub had been left on Orders*. iPad A16, fresh onboarding: `NavigationRail` with 5 items and both sub-tabs' master–detail split views intact under the hub's AppBar + TabBar. **One accepted cosmetic tradeoff:** on the Invoices sub-tab the centered AppBar title reads "Invoices" directly above a tab labelled "Invoices". Unavoidable without inventing a new umbrella noun (explicitly rejected — "Sales" already means `salesReportTitle` here); the alternative (a fixed title) puts the same duplication on Orders, the default and more-visited tab, so this is the better half of the trade. |

| 2026-08-11 | C (IA) | **Coordinator independently re-verified the nav merge** (trust-but-verify): re-ran `flutter analyze` (clean) and `flutter test` (370/370, run directly — not piped through `tail`, see the build-pattern note below) myself; read `router.dart` and `orders_invoices_hub_screen.dart` by hand and confirmed the branch/route structure, the `embedded` param on both screens, and the `TabController` listener guard are all correct, not just plausible-sounding. Rebuilt and live-verified on iPhone 17 Pro, `my` locale: **5-tab bottom nav** (ရောင်းချ / ကုန်ပစ္စည်း / အော်ဒါ / စာရင်းအင်း / ဆက်တင်) confirmed by screenshot; tapped into the Orders sub-tab (empty state + "အော်ဒါအသစ်" FAB), then the Invoices sub-tab (FAB gone, sales-report AppBar action appeared, title changed) — chrome-follows-sub-tab confirmed both directions. **Then specifically stress-tested the highest-risk constraint**: left the hub on the Orders sub-tab, navigated to Analytics, tapped a KPI tile wired to `context.go('/invoices')`, and confirmed the hub landed directly on the **Invoices** sub-tab (correct title, correct tab underline, correct chrome) despite having been left on Orders — this is exactly the scenario that would silently break if the branch/route wiring were subtly wrong, and it works. | **Build-pattern correction for future sessions in this file:** `flutter build ... 2>&1 \| tail -N` reports `tail`'s exit code, not `flutter`'s — a failed build can look like exit 0 and get treated as verified. The subagent this session caught this by hitting it directly (a stale `ios/Flutter/ephemeral` build got installed and "verified" for a while before being caught). Use `flutter build ... > logfile 2>&1; echo $?` (or check the log for `✓ Built` explicitly) instead of piping through `tail` when the exit code matters. Did not independently verify `textScaleFactor` behavior on the sub-tab bar or swipe-gesture tab switching (tapped only) — both reasoned-from-code by the subagent, not observed; low risk. |

### Note for next session — coordinate calibration for `mcp__Claude_Code_iOS_Simulator__control`
Tap coordinates for this tool are in **device points** as reported by `attach` (e.g. 402×874 for iPhone 17 Pro), NOT the pixel dimensions the screenshot appears at when viewed. Estimate tap position as a **fraction of the screenshot's visual layout**, then multiply by the point-space width/height — don't eyeball raw pixel numbers from the image. Also: a `swipe`/`touch_path` whose start point lands on the bottom navigation bar (roughly the bottom ~90pt of a compact-width screen) gets consumed by the nav bar and never reaches the scrollable content above it — start swipes well clear of it (e.g. `y=700` on an 874pt-tall screen, not `y=800`).

### Note from the previous session — Simulator verification was partial, read before assuming Phase A is fully closed out visually
- **What was verified live on the iOS Simulator (real build, `flutter run --dart-define-from-file=env.local.json`, device already past onboarding from a prior install):** the Cash Register/Till screen (`my` locale, light) and the **Inventory** screen (untouched by this pass — a ripple-effect check) in **both light and dark** via `xcrun simctl ui <device> appearance dark|light`. All three confirm: warm cream/near-black surfaces render correctly, `NotoSansMyanmar` renders Myanmar product names cleanly with no diacritic clipping, the gold `primaryContainer` tint shows correctly on the FAB and the selected nav-bar pill in both brightnesses, hairline dividers and tonal cards read cleanly. Screenshots are in the session's scratchpad (not committed — ask if you need them re-taken).
- **What could NOT be verified live this session:** the Sell screen and Checkout sheet specifically, and the `en`-locale entry/auth screens — **this environment has no touch-injection into the iOS Simulator** (no computer-use/idb tool available; `osascript`/System Events UI scripting is blocked with error -25204, Accessibility permission not granted to the calling process; `xcrun simctl` has no synthetic-touch command). Getting past the already-onboarded device's daily Cash-Register gate, or driving the onboarding PageView, requires a tap. **Resolved next session — see the entry above; the coordinator's environment did have simulator touch access.**
- **A `flutter test`-based screenshot harness was attempted** (real screens + real Riverpod providers + an in-memory Drift DB + `tester.tap()`, dumping PNGs via `matchesGoldenFile`/`--update-goldens`) as a substitute that doesn't need simulator taps. It hung repeatedly (`pumpAndSettle` never settling) and was **abandoned and deleted** rather than left half-working — do not recreate it without first isolating why it hangs (my working theory, unconfirmed: a `StreamProvider` override using `Stream.empty()` for `categoriesStreamProvider`/`paymentAccountsProvider` never emits, unlike a real Drift watch which emits an initial `[]` immediately — use `Stream.value(const [])` instead next time, not `Stream.empty()`). If you pick this up again, isolate one `testWidgets` case at a time with a short explicit `pumpAndSettle(..., timeout: Duration(seconds: 15))` rather than the 10-minute default, so a hang fails fast instead of burning the session.
- **Recommendation for next session:** either (a) ask the user to grant Accessibility permission to the terminal/agent process so `osascript`/System Events can inject taps, (b) ask the user to manually tap through Sell → Checkout and Onboarding while screenshots are taken between steps, or (c) fix the widget-test harness per the note above. Do not claim Sell/Checkout/en-locale visual verification happened without one of these.
