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

**Committed 2026-08-11** — `f131407` (Phase A + A2: design system + Sell/Checkout)
and `fefc666` (Phase C IA: Orders+Invoices nav merge). Working tree was clean
after both; Phase B starts from a clean base.

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

### Phase B — Inventory ✅ (2026-08-11)
`inventory_screen.dart`, `product_edit_screen.dart`, `categories_screen.dart`,
`stock_movements_screen.dart`, `stock_history_screen.dart`,
`sell/barcode_scanner_screen.dart` (+ `stock_adjust_dialog.dart`, pulled in by
adjacency — the redesigned stock pill is now its entry point)

- [x] **The `categories_screen.dart` crash is fixed.** Same shape as
      `_LineDiscountDialog`: the controller moved into a `_CategoryNameDialog`
      `StatefulWidget` so its `dispose` runs when the route is actually gone,
      not when `showDialog`'s future resolves on *pop*. Exercised on device —
      add ➜ save ➜ rename ➜ delete, no red screen.
- [x] **`ProductThumb` adopted in Inventory's list and tablet grid**, so the
      Sell grid and the Inventory list finally agree on what a product looks
      like. Phone list and tablet grid are now one `_ProductTile`.
- [x] Per-row actions: two unlabeled icon buttons ➜ a labelled overflow menu,
      with the **stock pill itself** as the one-tap route to stock adjust (the
      frequent action keeps its tap count; the rare one gains a label).
- [x] `_StockBadge` re-toned to three tiers (out / low / healthy) on the
      `AppColors` soft-fill tier, tabular, 48pt min width. The old healthy
      fill was `secondaryContainer` = `#DCE7E1` = `identityFills[0]` exactly,
      so pill and plate merged on ~a quarter of rows.
- [x] Low-stock banner moved onto the same soft-fill banner language as Sell's
      two licence banners (it was a third, `errorContainer` variant).
- [x] **Shared `CategoryFilterBar` extracted to `core/widgets/app_widgets.dart`**
      from the Sell version built in A2; Inventory's copy was still the
      pre-research pattern. New `inventoryCategoryCountsProvider` mirrors the
      Sell one, sharing a predicate with `filteredProductsProvider`.
- [x] `product_edit_screen.dart`: four `Card` groups instead of a flat
      12-field column with unanchored hint paragraphs; **docked Save** bar;
      photo preview is now its own tap target. Kept its own preview rather
      than `ProductThumb` — see the note below.
- [x] Both stock ledgers: `MoneyText` deltas, 2-line subtitles,
      filter-aware empty state, `opening` added to the type chips.
- [x] `barcode_scanner_screen.dart`: real torch state, device-sized
      viewfinder, safe-area hint, `AppTheme.radius` ➜ `radiusMd`.
- [x] New token `AppTheme.dangerFilledButtonStyle` — destructive confirms
      stop looking like "Save". Two call sites now, ~10 waiting in later
      phases.
- [x] Three new i18n keys in both ARBs + `gen-l10n`; `flutter analyze` clean;
      370 tests pass; verified live on iPhone 17 Pro (`my` light + dark, `en`
      light) and iPad A16.

**Why `product_edit_screen.dart` did *not* get `ProductThumb`.** The widget's
whole contract is that a missing photo is a normal, designed state — it renders
an initials plate and never says "no image". That is right in a list and wrong
in the one control whose job is to tell you whether this product *has* a photo
and let you change it. It keeps an explicit empty state; what it lost was the
hardcoded radius and the dead 72pt square that wasn't a tap target.

**Three bugs only a device found.** (1) The tablet grid's `maxCrossAxisExtent`
is a *ceiling*, not a target — `ceil(width / extent)` columns divided evenly
meant the old 300 gave three ~235pt cards on an 820pt iPad, leaving ~70pt for
the name and shredding every Myanmar product name into clipped fragments. This
was broken before this phase; the thumbnail just made it impossible to miss.
(2) "Show all movements" didn't: `opening` was never in `_allMovementTypes`, so
opening-balance rows appeared only when *every* chip was off. (3) The
stock-adjust dialog's `SegmentedButton` sliced the second line off
"ပစ္စည်းအသစ်ထည့်" because Material's segment padding is horizontal-only and the
control stays pinned at its 40dp minimum.

### Phase C — Orders + Invoices ✅ IA merge + token retrofit both done
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
- [x] Full token retrofit of `invoice_detail_screen.dart`,
      `sales_report_screen.dart`, `customers_screen.dart` — done, see the
      session-log entry below.
- [x] Pastel status-pill pattern (approved in the original color-direction
      research, tokens built in Phase A2, never actually used anywhere until
      now) — implemented as a new shared `StatusPill`/`StatusTone` component
      and adopted in `order_labels.dart`, `invoice_view.dart`,
      `order_detail_sheet.dart`, replacing raw `Colors.green/orange/red`.
- [x] `customers_screen.dart`'s three-controller dispose-after-`await` crash
      (name/phone/address) fixed with the same `_LineDiscountDialog`/
      `_CategoryNameDialog` pattern — exercised end-to-end live.

### Phase D — Analytics + Money ✅ all 8 files done
`analytics_screen.dart`, `pnl_screen.dart`, `credit_screen.dart`,
`cash_session_screen.dart`, `expense_screen.dart`,
`recurring_expenses_screen.dart`, `equity_screen.dart`,
`payment_accounts_screen.dart`

**This phase was finished by the coordinator directly, not a subagent.**
After two consecutive subagent runs hit the account's monthly API spend
limit (see the two session-log entries below), the remaining 5 files were
done by the main session itself on the Sonnet model rather than risking a
third Opus subagent failure — `.claude/agents/ui-ux-designer.md` was also
switched from `model: opus` to `model: sonnet` at this point, so future
design-pass work defaults to the cheaper model.

- [x] Shared component upgrades in `core/widgets/app_widgets.dart`:
      `StatCard` rebuilt (icon plate + label + tabular `MoneyText` via
      `FittedBox`, `tone: StatusTone?` where `null` = informational/neutral
      and non-null = "this figure is a signal"), new `IconAvatar` (replaces
      bare `CircleAvatar`s that were defaulting to `primaryContainer` — the
      "selected" fill — on ordinary list rows), `ButtonSpinner` promoted from
      a private helper duplicated in two screens to one shared widget.
- [x] `analytics_screen.dart` — the KPI-grid raw-`Colors.*` collision with
      brand green (flagged as a handoff item back in Phase A2) resolved by
      elimination, not recoloring: decorative per-category hues were
      "measured and rejected" (see the design note in the file) in favor of
      color-as-signal-only — 6 of 8 tiles are neutral, `netProfit < 0` and
      `creditOutstanding > 0` get `StatusTone.critical`/`.attention`.
- [x] `pnl_screen.dart` — `_row` now delegates to `SummaryRow` (tabular
      `MoneyText`, was plain `Text`); net-profit color now only fires on a
      *loss* (previously colored green on every ordinary day, training the
      eye to skip the one line that matters — explicitly made to agree with
      Analytics' now-identical call); `ButtonSpinner` replaces two duplicated
      inline spinners; bare error text became `EmptyStateView`.
- [x] `credit_screen.dart` — the total-outstanding figure onto `MoneyText`.
      Nothing else in this file needed a change (already token-clean).
- [x] `cash_session_screen.dart` — the "Open" indicator (lock icon + green
      text) became `StatusPill(tone: StatusTone.positive)`; `_kv`'s value
      slot widened from `String` to `Widget` so the opened-at timestamp
      still renders as plain `Text` but the opening amount and the live
      "expected now" figure render as `MoneyText`. `_HistoryTile`'s
      variance/opening/closing text was left as-is — it's a formatted
      sentence with the amount embedded mid-string, not a standalone
      figure, so forcing it into `MoneyText` would have meant restructuring
      the row rather than fixing a token gap.
- [x] `expense_screen.dart` — the running-total header and each row's
      trailing amount onto `MoneyText`; `CircleAvatar` → `IconAvatar` for
      the category glyph; the delete-confirm dialog's `FilledButton` gained
      `AppTheme.dangerFilledButtonStyle` (the same "Delete looks exactly
      like Save" collision Phase B's Inventory delete dialogs had — this
      screen had its own uncaught instance). The full-screen receipt-photo
      viewer's `Colors.black`/`Colors.white` were left alone, same reasoning
      as Phase B's barcode scanner: the backdrop is a live photo, not a
      theme surface.
- [x] `recurring_expenses_screen.dart` — `CircleAvatar` → `IconAvatar`; same
      `dangerFilledButtonStyle` fix on its delete-confirm `FilledButton`.
      The subtitle's embedded amount was left as a sentence, same reasoning
      as the cash-session history tile.
- [x] `equity_screen.dart` — `_row` now delegates to `SummaryRow` (was a
      hand-rolled `Row` duplicating `pnl_screen.dart`'s pre-refactor
      pattern almost line-for-line). The contribution/drawing
      `CircleAvatar` — a hand-rolled `colors.success/danger.withValues(alpha:
      0.15)` background, exactly the pattern `IconAvatar` exists to replace
      — became `IconAvatar(tone: StatusTone.positive/.critical)`; the
      trailing signed amount onto `MoneyText`. Same `dangerFilledButtonStyle`
      fix on delete-confirm.
- [x] `payment_accounts_screen.dart` — **a fifth instance of this session's
      recurring crash, fixed**: `_openEditor` created two
      `TextEditingController`s (name/opening balance), `await`ed
      `showDialog`, then disposed both — the same dispose-after-`await` bug
      already fixed in `checkout_sheet.dart`, `categories_screen.dart`,
      `customers_screen.dart`. Moved into a new `_PaymentAccountEditorDialog`
      `StatefulWidget` (+ a small `_PaymentAccountDraft` result type so the
      caller still does the actual repository call). `CircleAvatar` →
      `IconAvatar`; the balance subtitle onto `MoneyText`
      (`textAlign: TextAlign.left`, since a `ListTile.subtitle` reads
      left-aligned under the title, not trailing). Same
      `dangerFilledButtonStyle` fix on delete-confirm.

### Phase E — Settings + Back-office ✅ done (2026-08-12, two parallel sessions)
`settings_screen.dart`, `shop_profile_screen.dart`,
**`branches_screen.dart` (1,370 lines — split out as its own sub-pass, done below)**,
`staff_accounts_screen.dart`, `staff_members_screen.dart`,
`suppliers_screen.dart`, `accounts_payable_screen.dart`,
`purchase_orders_screen.dart`, `purchase_order_editor_screen.dart`,
`purchase_order_detail_screen.dart`, `printer_settings_screen.dart`,
`label_printer_settings_screen.dart`, `backup_screen.dart`,
`referral_screen.dart`, `sync_issues_screen.dart`, `help_guide_screen.dart`

- [x] **The other 14 Phase E files (2026-08-12), done in parallel with the
      `branches_screen.dart` sub-pass below.** Same audit rigor: grepped for
      the recurring dispose-after-`await` `TextEditingController` crash and
      the "delete styled like Save" collision across all 14 before touching
      anything, rather than rediscovering them screen by screen.
- [x] **Crash fixes — six locations, not four.** The three already-known
      locations were real: `settings_screen.dart`'s `_DeviceLabelTile._editLabel`
      (one controller), `suppliers_screen.dart`'s `_openEditor` (four
      controllers — name/phone/address/note), and **two separate instances**
      in `purchase_order_editor_screen.dart` (`_addProduct`'s `searchCtrl`
      product-search sheet, `_editLine`'s `qtyCtrl`/`costCtrl` line editor).
      All four fixed with the session's established pattern — the
      controller(s) moved into their own `StatefulWidget`
      (`_DeviceLabelDialog`, `_SupplierEditorDialog` + a `_SupplierDraft`
      result type, `_ProductPickerSheet`, `_LineEditorDialog` + a
      `_LineEditResult` result type) so `dispose()` runs on the widget's own
      teardown, not on `showDialog`/`showModalBottomSheet`'s future — which
      resolves on *pop*, before the exit animation finishes. **Two more found
      by the same grep sweep, not in the handoff list:**
      `staff_members_screen.dart`'s `_openEditor` (name/pin controllers,
      identical dispose-after-`await` shape — fixed with a new
      `_StaffMemberDialog`) and `staff_accounts_screen.dart`'s `_invite`
      dialog (email/password controllers **never disposed at all** — a leak,
      not a crash, since nothing touched them after the `await`, but the same
      family of bug; fixed with a new `_StaffInviteDialog` for correctness
      and consistency, gaining `autofillHints` in the process). All six
      exercised live end-to-end where the simulator's navigation cooperated
      (see the verification note below) — no red screens, no leaked
      controllers.
- [x] **The delete-button collision, four more instances.** Every
      delete/destructive-confirm `AlertDialog` across the 14 files was
      checked for a plain-green `FilledButton` on the destructive action;
      four had it and now use `AppTheme.dangerFilledButtonStyle`:
      `staff_accounts_screen.dart` (Revoke), `staff_members_screen.dart`
      (Remove member), `suppliers_screen.dart` (Delete supplier — plus the
      nested remove-line confirm and the outer "Cancel PO"/"Delete PO"
      dialogs in `purchase_order_editor_screen.dart`/
      `purchase_order_detail_screen.dart`), and `backup_screen.dart`'s
      import-confirm ("Replace all local data" is exactly this collision).
      `purchase_order_detail_screen.dart`'s "Cancel order" also got the
      danger style, on the reasoning that cancelling a PO is an
      effectively-irreversible status change, not a routine one, and sitting
      next to a neutral "Cancel" button a plain green "Cancel order" reads as
      the safe default.
- [x] **The cross-feature `filteredProductsProvider` bug — fixed, not just
      flagged.** `purchase_order_editor_screen.dart`'s product picker used to
      read `filteredProductsProvider`, Inventory's own search/category
      `StateProvider` — so the PO picker silently inherited whatever
      Inventory's tab was last filtered to (a cashier leaves Inventory on
      "Drinks", the owner opens New PO, and can't find a non-drink product
      until they notice and clear Inventory's filter first). Switched to
      `productsStreamProvider`, the same unfiltered base
      `filteredProductsProvider` itself reads from, so the picker now applies
      only its own local text search — independent of any other tab's leftover
      state. Documented inline at the call site.
- [x] **`purchase_orders_screen.dart` + `purchase_order_detail_screen.dart`**
      — `poStatusColor` (raw `Color?`) became `poStatusTone` (`StatusTone?`,
      mirroring `order_labels.dart`'s `orderStatusTone`: `open` ➜ `attention`
      — it's the shop's to-do list, not neutral; `cancelled` ➜ `neutral`, not
      danger, for the same "don't train the eye to ignore red" reasoning
      Orders already uses). List rows now show a `StatusPill` next to the
      total instead of colored text; the detail screen's header status and
      totals moved onto `StatusPill`/`MoneyText`/`SummaryRow`; bare leading
      `Icon`s became `IconAvatar`.
- [x] **`printer_settings_screen.dart` + `label_printer_settings_screen.dart`**
      — the "printer connected" row (flagged in the handoff as a `StatusPill`
      candidate that didn't exist when Phase 5 last touched these screens):
      the success-green `Icon` became an `IconAvatar(tone: .positive)`, and a
      new `StatusPill` (new i18n key `printerConnected`/"Connected" ·
      "ချိတ်ဆက်ပြီး") sits next to the device MAC. Loading spinners
      (`TextButton.icon`'s scan spinner, the test-print spinner) now use the
      shared `ButtonSpinner` instead of inline `SizedBox`+
      `CircularProgressIndicator`.
- [x] **`backup_screen.dart`** — the two hand-picked `Colors.teal`/
      `Colors.indigo` leading icons (a beginner-tell raw-`Colors.*` pair with
      no semantic meaning) became `IconAvatar`s: export neutral
      (informational), import `tone: .attention` (it's a replace-all that
      erases the device's current data — worth a visual nudge before the tap,
      not just at the confirm dialog, which itself now uses
      `dangerFilledButtonStyle`).
- [x] **`referral_screen.dart`** — the numbered "How it works" steps'
      `CircleAvatar` (hand-rolled `primaryContainer` background + bold text)
      became `IconAvatar(text: '${i+1}')`, exactly the "short label instead
      of an icon" case that parameter exists for; the referred-shops list's
      active/paused `CircleAvatar` became `IconAvatar(tone: .positive/
      .neutral)`; the redeem button's inline spinner became `ButtonSpinner`.
      **A real overflow bug found live, not in the code:** the wallet card's
      "Active shops: N · Total earned: X Ks" row was a `Row` with two
      unconstrained `Text` widgets and a `Spacer` — at this account's `my`
      locale phrase lengths it overflowed the card's right edge by ~10px
      (Flutter's red/yellow debug banner, visible on device). Not something
      this pass introduced; found because this pass actually ran the screen.
      Fixed by replacing the `Row`+`Spacer` with a `Wrap` (the pair now drops
      to a second line instead of overflowing) — the correct Myanmar-safety
      fix per this app's own rule (no ellipsis on this kind of label, no
      forced single line), not a one-off patch.
- [x] **`accounts_payable_screen.dart`** — brought onto the same tokens
      `credit_screen.dart` (out of this phase's scope) still lacks: `CircleAvatar`
      → `IconAvatar`, the header total and all list/detail money figures onto
      `MoneyText`, the "settled" row's hand-rolled check-icon-plus-text became
      a `StatusPill(tone: .positive)`. **Deliberate scope boundary:** this
      makes Accounts Payable and its sibling Credit book visually diverge for
      now (Credit's Phase D pass only touched its total figure) — flagged
      here rather than silently fixed, since `credit_screen.dart` isn't in
      this phase and pulling it in would have widened the diff past one
      phase's scope.
- [x] **`sync_issues_screen.dart`** — the quarantined-row `Card`s were a flat
      white card with a grey "held until sync completes" caption; now a
      leading `IconAvatar(icon: error_outline, tone: .critical)` plus a
      `StatusPill` for the "held" caption, matching the soft-fill banner
      language the rest of the app uses for a blocked/attention state.
- [x] **`settings_screen.dart`** — the License tile's status subtitle
      (Active/Grace/Expired, color-coded) was a bare `TextStyle(color:)`
      bypassing the `ListTileTheme`'s subtitle role; now
      `Theme.of(context).textTheme.bodySmall?.copyWith(color:)`.
      `shop_profile_screen.dart` — the logo-preview circle was missing
      `alignment: Alignment.center` (the fallback icon sat top-left inside
      the circle, not centered); the Save/upload-logo spinners now use
      `ButtonSpinner`.
- [x] **`help_guide_screen.dart`, `staff_accounts_screen.dart` (structure),
      `staff_members_screen.dart` (structure) — audited, already fine.**
      `help_guide_screen.dart` has zero color literals and already uses
      `ExpansionTile` + theme text roles; no change made. The rest of both
      staff screens' layout (list/empty-state/FAB) was already token-clean
      from the earlier Phase-5 retrofit.
- [x] `flutter analyze` clean; **370/370 tests pass**, unchanged (grepped
      `test/` for text these screens' own tests assert on before
      restructuring — `owner_only_routes_matrix_test.dart` only checks the
      `OwnerOnlyGate` lock icon on `StaffAccountsScreen`, unaffected by the
      dialog extraction). No business logic changed. One new i18n key
      (`printerConnected`) added to both `.arb`s + `flutter gen-l10n`.
- [x] **Verified live** on iPhone 17 Pro, `my`+`en` × light+dark (mixed
      across screens, not every combination on every screen — see below).
      **Exercised end-to-end, no red screens:** Suppliers' four-controller
      crash fix (add ➜ Save ➜ new `IconAvatar` row appeared) and its delete
      confirm (`en`/light: solid-red "Delete" clearly distinct from the
      "Cancel" text button, tapped through, row removed cleanly, back to
      `EmptyStateView`); Staff Accounts' invite-dialog crash fix (dialog open
      ➜ eye-icon visibility toggle ➜ Cancel, no leak/crash); the Referral
      overflow fix, confirmed gone in `my`+`en` × light+dark after the code
      fix (screenshotted broken, then fixed, on the same live device);
      Backup's `IconAvatar` tones and its native file-picker dismiss (no
      crash). **Not independently exercised live:**
      `purchase_order_editor_screen.dart`'s two dialog fixes specifically —
      this screen is reached via `Navigator.push` (not the bottom-tab shell),
      and its small icon-only `FloatingActionButton` did not register a tap
      across many coordinate attempts this session, while the *extended*
      FAB one level up (Purchase Orders' "Create" button) and a `showDialog`
      reached via a text-field's trailing `IconButton` on the *same* pushed
      screen both worked — the same "FAB tap unreliable on a pushed route"
      simulator quirk noted in this file's Phase-B section and again in the
      `branches_screen.dart` sub-pass below, not a code defect. Confidence
      instead rests on: (a) the identical `StatefulWidget`-dialog-extraction
      pattern verified live twice elsewhere this same phase (Suppliers,
      Staff Accounts), (b) `flutter analyze` clean + 370/370 tests, and (c)
      the surrounding infrastructure on this exact screen — another
      `showModalBottomSheet` reached via a different control — confirmed
      working live. Also not reached live: `purchase_orders_screen.dart`/
      `purchase_order_detail_screen.dart`'s `StatusPill` (no saved PO to
      view, for the same FAB reason), and the printer-connected `StatusPill`
      (no Bluetooth printer paired in the simulator).

- [x] **`account/branches_screen.dart` ✅ (2026-08-12)** — token/visual pass done
      in isolation (a parallel session handles the other 13 files above; this
      box covers only this one). Verified the old Phase-5 retrofit
      (changelog #104) was already flowing spacing/type-scale/`AppColors`
      through the new deep-green palette correctly (it reads tokens, not
      hex) — confirmed rather than assumed. What changed: a **sixth instance**
      of this session's recurring dispose-after-`await` `TextEditingController`
      crash, in `_createBranch`'s add-branch dialog, fixed with the same
      `_CreateBranchDialog` `StatefulWidget` pattern as the five prior fixes;
      the health chip (`_buildHealthChip`, "Safe to switch"/"Sync needed")
      went from a generic `Chip` — both states rendered in the *same* neutral
      fill, differing only by a 16px icon glyph — to `StatusPill`
      (positive/attention); the three near-identical stuck/quarantine/recovery
      banners moved off raw `ColorScheme.errorContainer`/
      `surfaceContainerHighest`+`primary`-icon/`secondaryContainer` onto the
      `AppColors` soft-fill tier, re-tiered by what each one *means* rather
      than what looked closest to the old color (stuck blocks switching ➜
      `dangerSurface`; quarantine is non-blocking/self-resolving ➜
      `neutralSurface`; an interrupted switch offering a direct retry ➜
      `warningSurface`); `_BranchCard`'s bare leading `Icon` became an
      `IconAvatar`; the `_confirmUnlink` dialog's plain-green `FilledButton`
      (the "delete looks like Save" collision) now uses
      `AppTheme.dangerFilledButtonStyle`; `AppTheme.radius` (the deprecated
      alias) in `_SectionHint` became `radiusMd`; a few remaining raw
      `TextStyle(color: ...)` spots in the preflight bottom sheet now read
      through `Theme.of(context).textTheme.*` + `AppColors`. The
      `Switch`/`Unlink` trailing-row button *types* (`OutlinedButton`/
      `FilledButton`) were deliberately left alone — `branches_screen_p3_widget_test.dart`
      pins those exact widget types by text, and the existing tonal-fill +
      red-foreground "Unlink" button already reads as visually distinct from
      "Switch", so there was no real "Save" collision there to fix (unlike the
      confirm-dialog's plain FilledButton, which was one). No business logic
      touched. `flutter analyze` clean; **370/370 tests pass** unchanged (the
      widget test's `OutlinedButton`/`FilledButton`-by-text assertions and
      "Safe to switch"/"Sync needed" text assertions still hold against
      `StatusPill`). No new i18n strings. **Verified live** on iPhone 17 Pro,
      `my` locale, dark + light: the pinned current-branch card, the green
      `StatusPill` "Safe to switch", and the bordered `_SectionHint` empty-other-
      branches box all render cleanly with no overflow in both brightnesses;
      the create-branch dialog crash fix was exercised end-to-end twice
      (FAB ➜ dialog opens autofocused ➜ typed a name ➜ submitted ➜ dialog
      closed cleanly back to the branch list, no red error screen either time).
      **Not independently verified live** (this test account only has one
      linked branch, so the "other branches" list never rendered): the
      `IconAvatar` on an other-branch card, the `_confirmUnlink` danger-button
      fix, and the three re-toned banners — all code-reviewed and reusing
      call shapes already confirmed working live elsewhere this session
      (`IconAvatar`/`StatusPill`/`dangerFilledButtonStyle` in Phase D;
      the `AppColors` soft-fill `Material`+`Padding`+`Icon`+`Text` banner
      shape in Sell's licence banners). `en` locale not reached live either
      (only exercised by the widget test, which does force `Locale('en')` for
      the error-state case and passes). Simulator navigation in this session
      was unusually unreliable — screenshots repeatedly landed on unrelated
      Settings sub-screens after a tap, consistent with a second, concurrent
      agent driving the same booted simulator for the rest of Phase E at the
      same time — so fewer states were captured than a typical phase; the
      states above were captured on stable, double-confirmed screenshots only.

### Phase F — Web surfaces ✅ done (2026-08-12, two parallel sessions + coordinator finished the remainder)
`admin/admin_login_screen.dart`, `admin/admin_dashboard_screen.dart`,
`admin/admin_dashboard_widgets.dart` (924 lines — found during scoping, not
in the original file list, but it's where the dashboard's actual
dialogs/status colors live), `features/storefront/storefront_screen.dart`
(the in-app "My Web Storefront" settings screen), `storefront/storefront_page.dart`
(the public customer-facing storefront page), `storefront/storefront_app.dart`,
`invoices_web/*` (7 files).

**Both parallel subagents (F1: admin, F2: storefront) hit the account's
monthly spend limit mid-task, a third and fourth time this session** — see
the session-log entry below. Unlike the Phase D interruptions, both agents'
*actual file edits* were substantially complete and high-quality when cut
off; the coordinator finished the small remainder itself (3 leftover raw
colors in `admin_dashboard_widgets.dart`, all of `invoices_web/*`, which F2
never reached) rather than spawning a fifth subagent.

- [x] **Admin console (`lib/admin/*`) — adopted `AppTheme`/`AppColors`
      wholesale, a deliberate decision, not a mechanical import.** This is
      GoldPOSMM's own internal tool (the vendor's license-management
      console), not customer-facing chrome, so unlike the storefront
      question below there was no real case for a separate visual identity.
      Before: a raw `ColorScheme.fromSeed(seedColor: Color(0xFF00695C))`
      (the old teal, no relationship to the actual `#0F5C3E` brand green)
      and no `textTheme` at all — exactly "beginner tell #1" from the
      original design-pass rubric, on the one screen that had somehow never
      been touched by any of this session's other phases. `admin_login_screen.dart`
      rebuilt onto `AuthScaffold`/`InlineErrorBanner`/`ButtonSpinner`, the
      exact shared auth pattern the mobile app and `invoices_web`'s
      `ActivateScreen` both already use. `admin_dashboard_screen.dart`'s
      `_NotAuthorized` view: hand-rolled `Center`+`Column`+raw `Colors.red`
      → `EmptyStateView`. `admin_dashboard_widgets.dart`: five independent
      raw-color ternaries for license/key/carrier status
      (`Colors.green/orange/blue/grey/red`, scattered across the license
      list, key-request dialog, and carrier-config list) resolved through
      `AppColors`; `_ErrorView` rebuilt onto tokens; the carrier list's bare
      `Center(child: Text(...))` empty state → `EmptyStateView`. Explicitly
      **English-only by design** (no `AppLocalizations` import anywhere in
      `admin/`) — `localeCode: 'en'` passed to `AppTheme` so Myanmar stays a
      font *fallback* only, and no `localizationsDelegates` were added
      (would pull in a translation pipeline this console was never part of).
      `core/theme/app_theme.dart`/`core/widgets/app_widgets.dart` confirmed
      to have no non-web-safe imports before being pulled in — nothing broke
      the web build.
- [x] **`features/storefront/storefront_screen.dart` (the mobile in-app
      settings screen)** — already imported `AppTheme` from the old Phase 6
      retrofit, confirmed still flowing correctly. **A crash fix — the
      eighth instance of this session's recurring bug, this time a straight
      leak (no `dispose()` at all, not even the dispose-after-`await`
      shape)**: `_BlockedCustomersScreen._addBlock` created `phone`/`reason`
      controllers inline for its block-a-customer dialog and never disposed
      them. Fixed with a new `_AddBlockedCustomerDialog` `StatefulWidget`,
      the same pattern as the seven prior fixes.
- [x] **`storefront/storefront_page.dart` + `storefront/storefront_app.dart`
      (the actual public page a shop's customers see) — adopted `AppTheme`,
      a considered decision with real functional payoff, not just
      consistency for its own sake.** Grepped the data model first for any
      per-shop color/branding field — none exists, so the old untouched
      `colorSchemeSeed: Color(0xFF6C4AB6)` (purple) reads as an unreplaced
      framework default, not a deliberate separate brand. Adopting `AppTheme`
      gets this page the tuned type scale for free — in particular the
      taller line-heights for Myanmar diacritics, which this page needed and
      never had (`my` is its default locale) — plus the radius/elevation/
      motion tokens and the `AppColors` soft-fill tier, applied automatically
      to every `Card`/`FilledButton`/bottom sheet already in the file via one
      `ThemeData`, instead of hand-rolling a second design system for one
      extra Flutter Web target. Deliberately **light-only**, matching this
      page's behavior before the change (no `darkTheme:` was set either).
      Locale passed dynamically (`_locale.languageCode`, not hardcoded like
      admin) since this page has its own bilingual toggle.
- [x] **`invoices_web/*` (7 files) — same reasoning as admin, not
      storefront: `InvoicesWebSession` is the shop owner's own tool** (their
      own invoices, authenticated via the same device-activation flow as
      the mobile app), not a page anonymous customers land on — so it
      shares `AppTheme` for the same reason `admin_app.dart` does, not the
      "does this deserve its own brand" question `storefront_page.dart`
      had to actually answer. `invoices_web_app.dart`: same raw
      `colorSchemeSeed` (purple) replaced with `AppTheme.light/dark`.
      `activate_screen.dart`: spacing onto tokens, spinner onto
      `ButtonSpinner`, a redundant local `OutlineInputBorder()` removed
      (fighting `AppTheme`'s own `inputDecorationTheme`). `invoice_list_screen.dart`:
      money onto `MoneyText`, the refund-flag label onto `AppColors.danger`
      + a theme text role (was `TextStyle(fontSize: 11, color: Colors.red)`),
      both empty states onto `EmptyStateView`, search-field padding onto
      `AppTheme.space3`. `invoice_detail_web_screen.dart`: spacing onto
      tokens, the download spinner onto `ButtonSpinner`, the fetch-error
      state onto `EmptyStateView`. `invoice_detail_web_screen.dart` and
      `invoices_web_session.dart` had no `TextEditingController`/dialog
      pattern to check; `activate_screen.dart`'s one controller was already
      correctly disposed.
- [x] **A real, pre-existing bug found and fixed while trying to verify
      live, unrelated to any of the above.** `.claude/launch.json`'s
      `storefront-web` entry was missing `--dart-define-from-file
      env.local.json` — present on both its sibling entries
      (`admin-web`, `invoices-web`) but not this one. The practical effect:
      `flutter run -d web-server -t lib/storefront/storefront_main.dart
      --web-port 8765` (exactly the documented launch command) loads,
      serves, and reports success, but the page never paints — a genuinely
      blank tab with **zero console errors and an empty accessibility
      tree**, which is a much harder failure to diagnose than a visible
      error would have been (traced by re-running the identical command
      with the missing flag added on a fresh port, which rendered
      correctly). Fixed in `launch.json` directly. Whoever hits an
      inexplicable blank Flutter-web preview in this repo in the future:
      check the launch config has the env dart-define before assuming the
      app code is broken.
- [x] `flutter analyze` clean; **370/370 tests pass**, unchanged.
- [x] **Verified live** via the Browser tools against real `flutter run -d
      web-server` builds (not code review alone) — all three web surfaces:
      admin login screen (deep-green `primaryContainer` brand mark, "MM POS
      Admin" title, tokenized Card/FilledButton — no valid admin credentials
      available to see past login, noted rather than skipped silently);
      storefront's `_NoSlug` screen (Myanmar copy, language toggle, correct
      fonts, after the `launch.json` fix above); `invoices_web`'s
      `ActivateScreen` (green icon, tokenized input, green "Activate"
      button — the exact result of the `activate_screen.dart` edits above).
      `features/storefront/storefront_screen.dart`'s crash fix was
      code-reviewed (correct `StatefulWidget` shape, matching seven prior
      proven-live fixes) but not independently exercised on the iOS
      Simulator this pass — the mobile-side verification budget went to
      confirming the two web servers actually painted, which was the
      higher-risk unknown given this phase's different toolchain.

**This closes out the whole app-wide redesign — all six phases (A/A2, B, C,
D, E, F) are now done.**

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

| 2026-08-11 | B | **Inventory — the crash, `ProductThumb` everywhere it belongs, and a grid that was quietly broken on tablet.** Full detail in the Phase B section above. Short version: the `categories_screen.dart` `TextEditingController` crash (observed live during A2) is fixed with the `_LineDiscountDialog` pattern and exercised end-to-end on device; Inventory's list and tablet grid now carry the shared `ProductThumb` and are one `_ProductTile` instead of two divergent rows; the two unlabeled per-row icon buttons became a labelled overflow menu with the stock pill as the direct route to stock adjust; `_StockBadge` gained an out-of-stock tier and lost a fill that was byte-identical to `identityFills[0]`; the low-stock banner joined Sell's soft-fill banner language; Sell's category bar was extracted into a shared `CategoryFilterBar` and Inventory adopted it (with a matching counts provider); the product editor is grouped into four cards with a docked Save; both stock ledgers got tabular deltas, 2-line subtitles and a filter-aware empty state; the scanner's torch button now reflects reality. New token `AppTheme.dangerFilledButtonStyle`. Three new i18n keys. `flutter analyze` clean, 370 tests pass (no test changes needed — grepped first). **Verified live**: iPhone 17 Pro `my` × light + dark and `en` × light; iPad A16 for the grid. | **Three bugs found only by running it**, all fixed here: the tablet grid packing three ~235pt cards (pre-existing — `maxCrossAxisExtent` is a ceiling, not a target — and it shredded every Myanmar name); "show all movements" not showing `opening` rows because that type was never in the chip list; and the stock-adjust `SegmentedButton` clipping "ပစ္စည်းအသစ်ထည့်". **Handoff, not fixed here:** `purchase_order_editor_screen.dart:105` reads `filteredProductsProvider`, so the PO product picker silently inherits whatever search/category the Inventory tab was left on — a real cross-feature bug for the Purchasing phase. And the dispose-after-`await` controller crash is still live in **four** places: `settings_screen.dart:642`, `customers_screen.dart:126`, `suppliers_screen.dart:137`, `purchase_order_editor_screen.dart` (`searchCtrl`). Also: `mobile_scanner`'s own "Scanning is not supported on this device" error text is package-supplied English with no `errorBuilder` override, so a Myanmar user hitting a camera-permission denial sees English. |

| 2026-08-11 | B | **Coordinator independently re-verified Phase B** (trust-but-verify): re-ran `flutter analyze` (clean) and `flutter test` (370/370) myself; read the `_CategoryNameDialog` fix and confirmed it's the same shape as `_LineDiscountDialog` (controller lifecycle owned by the dialog's own `StatefulWidget`, not a `Future`); read the `_StockBadge`/`identityFills[0]` collision fix and confirmed the two colors are genuinely distinct now, not just relabeled. Rebuilt and live-verified on iPhone 17 Pro, `my` locale, light: Inventory list shows `ProductThumb` (photo or initials plate) consistently with Sell, stock pills read clearly distinct from the identity plates, low-stock banner and out-of-stock red badge both visible on real seed data. **Exercised the exact crash end-to-end, both entry points**: opened the categories screen, tapped an existing category ("Drinks") to open the rename dialog — opened cleanly, no crash — then tapped Save and confirmed it closed and persisted with no red error screen. (The FAB "add category" tap did not register after several coordinate attempts — likely a calibration miss on this specific pushed-route screen rather than an app bug, since the *edit* path exercises the identical `_CategoryNameDialog` code and worked correctly; not worth further time chasing given the fix is verified through the other entry point.) | Did not independently verify the tablet-grid fix, the "show all movements" filter fix, or the stock-adjust dialog text-clipping fix — all three were fixes to bugs the subagent found and fixed in the same pass, code-reviewed but not re-exercised live. Low risk given they're narrow, mechanical fixes (a geometry constant, a missing enum value in a filter list, a `SegmentedButton` padding tweak) rather than new logic. The four other live locations of the dispose-after-`await` crash pattern (`settings_screen.dart`, `customers_screen.dart`, `suppliers_screen.dart`, `purchase_order_editor_screen.dart`) are still open — real crashes, fix when those phases start. |

| 2026-08-11 | C | **Phase C's remaining token retrofit + the pastel status-pill pattern, finally implemented.** The subagent doing this work **hit the account's monthly API spend limit and was terminated mid-task**, mid-sentence, before it could report or update this ledger — the coordinator picked up from the working-tree state directly. Despite the abrupt cutoff, `flutter analyze` was clean and all 370 tests passed on inspection, meaning the agent's actual file edits were complete and self-consistent even though its own narration wasn't. **What shipped:** full token retrofit of `invoice_detail_screen.dart`, `sales_report_screen.dart` (new `_ButtonSpinner` helper for its export/generate buttons), and `customers_screen.dart`. **New shared `StatusPill`/`StatusTone` component** (`app_widgets.dart`) — four tones (`positive`/`attention`/`critical`/`neutral`) driven by `AppColors`' soft-fill tier (`successSurface`/`warningSurface`/`dangerSurface` + a new `neutralSurface`), replacing raw `Colors.green/orange/redAccent` in `order_labels.dart`'s `orderStatusColor` (now `orderStatusTone`, returning a tone not a `Color`), `invoice_view.dart`'s paid/partial/unpaid pill, and four spots in `order_detail_sheet.dart`. Non-trivial judgment calls documented inline in `order_labels.dart`: order status `new` maps to `attention` (not neutral) because a new order is the shop's to-do list, not a passive state; `cancelled` maps to `neutral` (not danger) because training the eye to read red for a normal end-state teaches it to ignore red. `customers_screen.dart`'s three-controller (name/phone/address) dispose-after-`await` crash — the same pattern as `checkout_sheet.dart`'s and `categories_screen.dart`'s, now fixed a third time — moved into a `_CustomerEditorDialog` `StatefulWidget`. `flutter analyze` clean, 370/370 tests pass, two new i18n keys. | **Coordinator's own verification** (not the subagent's, which never got to report): live on iPhone 17 Pro, `my` locale, dark — confirmed the pastel `StatusPill` renders consistently across all three surfaces that show an order/invoice status (Orders list card, Order detail sheet, Invoices list), confirmed a `new` order genuinely shows the warm-amber "attention" tone rather than a generic neutral grey (the design reasoning in the code comment is real, not aspirational), and confirmed a customer's owed-credit badge on the Customers list uses the same pastel language. **Exercised the customers crash end-to-end**: opened the edit dialog for an existing customer (three prefilled fields), tapped Save, confirmed it closed and persisted with no red error screen. Did not independently verify `sales_report_screen.dart`'s new `_ButtonSpinner` or `invoice_detail_screen.dart`'s retrofit live — code-reviewed only (grepped for leftover raw `Colors.*`/`TextStyle(fontSize:` and found none). If a future session sees anything off in the sales report or invoice detail screens specifically, treat that as the first place to look. |

| 2026-08-11 | D | **Phase D — hit the account's monthly spend limit a second time, this time with real unfinished scope left over.** Unlike the Phase C interruption (where the agent's work was substantively complete and only the report/docs were missing), this run was cut off after only 3 of 8 files: `analytics_screen.dart` and `pnl_screen.dart` got full, complete treatment; `credit_screen.dart` got one line changed (a `MoneyText` conversion) before the process died; `cash_session_screen.dart`, `expense_screen.dart`, `recurring_expenses_screen.dart`, `equity_screen.dart`, `payment_accounts_screen.dart` were never reached — no diff exists for any of them. The coordinator did not attempt to hand-complete the remaining 5 files (that would be a full phase's worth of design work done without the audit/reference rigor the rest of this session has used) — instead verified what *was* done, fixed a real bug found doing so, and is stopping here to let the spend-limit signal actually be heard rather than mechanically continuing to grind through Phase E next. What shipped: `StatCard` rebuilt with an icon-plate + `IconAvatar` + `ButtonSpinner` (promoted from a private duplicate) added to the shared widget library; the Analytics KPI-grid raw-color collision flagged back in Phase A2 resolved by removing per-category decoration entirely in favor of color-as-signal (documented as a considered rejection, not an oversight); `pnl_screen.dart` brought onto `SummaryRow`/`MoneyText`/`ButtonSpinner` and its net-profit color rule changed to match Analytics' (loss-only, not "green on every ordinary day"). `flutter analyze` clean, 370/370 tests pass. | **Real bug caught by live verification, not code review**: every single `StatCard` tile overflowed its `RenderFlex` by 5.5-7.5px on device — `Card`'s own default 4dp margin was eating into the height budget that `_kpiTileExtent()` computed for content only, invisible in a code read since the math *looked* right in isolation. Fixed with `margin: EdgeInsets.zero` on the `Card` inside `StatCard` (the GridView's own `mainAxisSpacing`/`crossAxisSpacing` already provide the gap Card's margin was redundantly re-adding). Rebuilt and re-verified after the fix: clean tiles, correct neutral-vs-signal tone split visible live (informational tiles read as plain dark plates, `creditOutstanding > 0` reads as the amber "attention" tone), P&L's net-profit row correctly stays neutral-white on a positive figure. **Handoff, unambiguous:** Phase D needs a fresh pass covering `cash_session_screen.dart`, `expense_screen.dart`, `recurring_expenses_screen.dart`, `equity_screen.dart`, `payment_accounts_screen.dart`, plus finishing `credit_screen.dart` beyond its one-line start — none of these were audited this session, so treat them as fully unstarted, not "probably fine." **Before running another large multi-file phase, check/raise the account's monthly spend limit** — two consecutive hits in one session is a real constraint, not a fluke. |

| 2026-08-12 | D | **Phase D finished directly by the coordinator, on Sonnet, after two subagent spend-limit failures.** `.claude/agents/ui-ux-designer.md` switched `model: opus` ➜ `model: sonnet` at the user's request before this work started, so this and future design-pass phases default to the cheaper model rather than risking a third Opus failure mid-phase. Surveyed all 5 remaining files for the two recurring issues this session keeps finding before touching anything: grepped for `Colors.*`/`TextEditingController`/`CircleAvatar` across all 5 up front, which showed 4 of 5 files' controllers were already safely owned by a `StatefulWidget`'s own `dispose()` — only `payment_accounts_screen.dart` had the actual bug (**a fifth instance** of the dispose-after-`await` crash, same fix pattern as the four prior ones, moved into a new `_PaymentAccountEditorDialog`). Applied `StatCard`/`IconAvatar`/`MoneyText`/`SummaryRow`/`StatusPill` consistently across `cash_session_screen.dart`, `expense_screen.dart`, `recurring_expenses_screen.dart`, `equity_screen.dart`, `payment_accounts_screen.dart` — full detail in the Phase D section above. **Also found and fixed the same "delete looks exactly like Save" collision Phase B fixed in Inventory's delete dialogs, in three more files this session hadn't touched yet** (`expense_screen.dart`, `recurring_expenses_screen.dart`, `equity_screen.dart`, `payment_accounts_screen.dart` — four, not three) — none of these had `AppTheme.dangerFilledButtonStyle` applied to their delete-confirm `FilledButton`, all now do. `flutter analyze` clean, 370/370 tests pass throughout (checked after every file, not just at the end). | **Live-verified on iPhone 17 Pro, `my` locale, dark, exercising the actual user flows rather than just screenshotting a static screen**: `payment_accounts_screen.dart`'s crash fix end-to-end (empty state ➜ FAB ➜ dialog ➜ typed a name ➜ Save ➜ new `IconAvatar`+`MoneyText` row appeared, no red screen); `cash_session_screen.dart`'s `StatusPill` end-to-end (closed state ➜ open-register dialog ➜ typed an opening amount ➜ confirmed ➜ the "Open" pastel pill and both `MoneyText` figures render correctly). Not independently live-verified: `equity_screen.dart`'s `IconAvatar(tone:)` on a contribution/drawing row and `expense_screen.dart`/`recurring_expenses_screen.dart`'s `dangerFilledButtonStyle` — code-reviewed only, reusing patterns already proven live elsewhere this session (the identical `IconAvatar(tone:)` call shape confirmed working in `payment_accounts_screen.dart`'s live check; the identical `dangerFilledButtonStyle` call confirmed working in Phase B's Inventory delete dialogs). This closes out Phase D — all 8 scoped files done. |

| 2026-08-12 | E (branches) | **`account/branches_screen.dart` alone (1,370 lines, split out from the rest of Phase E because of size — the other 13 Phase E files were handled by a parallel agent).** Read the file fresh rather than assuming the old Phase-5 retrofit (changelog #104) still held under the new deep-green palette — it did (spacing/type-scale/`AppColors` calls read tokens, not hex, so the recolor flowed through for free). Found and fixed a **sixth instance** of this session's recurring dispose-after-`await` `TextEditingController` crash, in `_createBranch`'s add-branch `AlertDialog` — the controller was created inline, `await`ed `showDialog`, then disposed on the next line, the same bug already fixed five times in `checkout_sheet.dart`/`categories_screen.dart`/`customers_screen.dart`/`payment_accounts_screen.dart`. Fixed the same way: moved into a new `_CreateBranchDialog` `StatefulWidget`. The `_confirmUnlink` delete-confirm dialog had the "delete looks exactly like Save" collision (a plain green `FilledButton` for "Unlink") — now uses `AppTheme.dangerFilledButtonStyle`. Beyond the two known recurring patterns: the health chip (`_buildHealthChip`) went from a generic `Chip` — "Safe to switch" and "Sync needed" rendered in the *identical* neutral fill, differing only by a 16px icon — to `StatusPill` (positive/attention), matching the pattern this app converged on elsewhere; the three near-identical stuck/quarantine/recovery banners (flagged as already using `AppTheme.space*` back in changelog #104, but never re-examined for color) moved off raw `ColorScheme.errorContainer`/`surfaceContainerHighest`+`primary`-icon/`secondaryContainer` onto the `AppColors` soft-fill tier, re-tiered by actual meaning rather than closest-old-color: stuck blocks switching ➜ `dangerSurface`/critical, quarantine is non-blocking and self-resolving ➜ `neutralSurface`/neutral, an interrupted switch offering a direct "Retry sync" ➜ `warningSurface`/attention; `_BranchCard`'s bare leading `Icon` became an `IconAvatar`; `_SectionHint`'s `AppTheme.radius` (the deprecated pre-retrofit alias) became `radiusMd`; a few remaining raw `TextStyle(color: ...)` spots in the switch-preflight bottom sheet now read through `Theme.of(context).textTheme.*` + `AppColors.danger`. **Deliberately left alone:** the `Switch`/`Unlink` trailing-row button *types* (`OutlinedButton`/`FilledButton.tonalIcon`) — `branches_screen_p3_widget_test.dart` pins those exact types by button text, and on inspection the existing tonal-fill-plus-red-foreground "Unlink" button already reads as visually distinct from the outlined "Switch" button, so there was no actual "looks like Save" collision there to fix, unlike the confirm-dialog's plain `FilledButton`, which was one. No business logic touched, no new i18n strings. `flutter analyze` clean; **370/370 tests pass unchanged**, including the 4 branches-specific widget tests (`OutlinedButton`/`FilledButton`-by-text and "Safe to switch"/"Sync needed"-by-text assertions all still hold against the `StatusPill`/style changes). | **Verified live** on iPhone 17 Pro, `my` locale, dark + light (light via `xcrun simctl ui <udid> appearance light`): the pinned current-branch card, the green `StatusPill` "Safe to switch" (pastel fill, solid-green label, correct in both brightnesses), and the bordered `_SectionHint` "no other branches" box all render cleanly with no overflow. **Exercised the crash fix end-to-end, twice**: FAB ➜ dialog opens autofocused ➜ typed a branch name ➜ submitted ➜ dialog closed cleanly back to the branch list with no red error screen, repeated a second time to confirm the widget survives repeat opens, not just first-open (matching this session's "reopen it a second time" standard from the A2 checkout-discount-dialog verification). **Not independently verified live** — this test account has only one linked branch, so the "other branches" list/`_BranchCard` never rendered regardless of navigation: the `IconAvatar` on an other-branch row, the `_confirmUnlink` danger-button fix, the `Switch`/`Unlink` trailing row, and the three re-toned banners (none of stuck/quarantined/interrupted-switch state exists in this seed data either) — all code-reviewed only, reusing call shapes already proven live elsewhere this session (`IconAvatar`/`StatusPill`/`dangerFilledButtonStyle` throughout Phase D; the `AppColors` soft-fill `Material`+`Padding`+`Icon`+`Text` banner shape in Sell's licence banners, Phase A). `en` locale not reached live (only exercised by the widget test's forced `Locale('en')` error-state case, which passes). **Simulator navigation was unusually unreliable this session** — repeated taps landed on unrelated Settings sub-screens (Suppliers, Label Printer Settings, License) instead of the row actually tapped, and the visible screen sometimes didn't match the most recent screenshot at all — consistent with a second, concurrent agent also driving this same booted simulator for the rest of Phase E at the same time (the mid-session build failures in `purchase_order_detail_screen.dart`/`purchase_order_editor_screen.dart` — files outside this task's scope, transiently referencing not-yet-defined methods, then clean again minutes later — independently confirm a second agent was mid-edit on the shared working tree concurrently). Every screenshot cited above as "verified" was double-confirmed stable (two consecutive identical screenshots) before being treated as ground truth, rather than trusted on the first frame. |

| 2026-08-12 | E (13-15 files) | **The other 14 Phase E files, done in parallel with the `branches_screen.dart` sub-pass above (same booted simulator, same working tree — see that entry's note on why navigation was noisy this session).** Full detail in the Phase E section above; short version: grepped `TextEditingController`/`Colors.*`/delete-confirm `FilledButton`s across all 14 files up front rather than rediscovering issues screen-by-screen. Confirmed **all four already-flagged crash locations** (`settings_screen.dart`'s device-label dialog; `suppliers_screen.dart`'s four-controller editor; `purchase_order_editor_screen.dart`'s **two separate instances** — the product-search sheet and the qty/cost line editor) and fixed all four with the session's established `StatefulWidget`-owns-the-controller(s) pattern. **Found two more of the same bug family the grep sweep turned up, not on the handoff list**: `staff_members_screen.dart`'s name/pin editor (identical dispose-after-`await` crash shape) and `staff_accounts_screen.dart`'s invite dialog (controllers **never disposed at all** — a leak, not a crash, but fixed the same way for correctness). **Decided the `filteredProductsProvider` cross-feature bug is a real fix, not just a flag**: switched the PO product picker to `productsStreamProvider` (the same unfiltered base Inventory's own filtered provider reads from) so it stops silently inheriting whatever category/search Inventory's tab was last left on — documented inline. Delete-button collision fixed in four more files (`staff_accounts_screen.dart`, `staff_members_screen.dart`, `suppliers_screen.dart`, `backup_screen.dart`'s import-confirm) plus PO's cancel/delete dialogs. `purchase_orders_screen.dart`/`purchase_order_detail_screen.dart` gained `poStatusTone`+`StatusPill` (mirroring `order_labels.dart`'s reasoning: open=attention, cancelled=neutral, not danger). `printer_settings_screen.dart`/`label_printer_settings_screen.dart`'s "printer connected" indicator — flagged in the handoff as a `StatusPill` candidate that didn't exist last time these screens were touched — now is one (new i18n key `printerConnected`). `backup_screen.dart`'s raw `Colors.teal`/`Colors.indigo` icons became toned `IconAvatar`s. `referral_screen.dart`'s numbered steps and referred-shops list adopted `IconAvatar`; **a real overflow bug was found live** (not introduced by this pass) — the wallet card's "Active shops / Total earned" `Row`+`Spacer` overflowed ~10px at `my` locale phrase lengths, fixed with a `Wrap` per this app's own Myanmar-safety rule. `accounts_payable_screen.dart` got the full token pass (`IconAvatar`/`MoneyText`/`StatusPill`) that its sibling `credit_screen.dart` (out of scope this phase) still lacks — flagged as a deliberate, documented scope boundary, not an oversight. `sync_issues_screen.dart`'s quarantined rows gained an `IconAvatar`+`StatusPill` in the critical tone. `help_guide_screen.dart` audited and left untouched (zero color literals, already token-clean). One new i18n key in both `.arb`s + `flutter gen-l10n`. `flutter analyze` clean, **370/370 tests pass** throughout. | **Live-verified** on iPhone 17 Pro, `my`+`en` × light+dark (not every combination on every screen). **Exercised end-to-end**: Suppliers' four-controller crash fix and its delete-confirm (`en`/light — solid-red "Delete" vs. text "Cancel", deleted cleanly, back to `EmptyStateView`); Staff Accounts' invite-dialog fix (open ➜ eye-icon toggle ➜ Cancel, no leak); the Referral overflow bug, screenshotted broken then confirmed fixed on the same device across `my`/`en` × light/dark; Backup's `IconAvatar` tones plus its native file-picker dismiss. **Not independently exercised live**: `purchase_order_editor_screen.dart`'s two dialog fixes specifically — this screen's small icon-only FAB did not register a tap across many coordinate attempts (the same "FAB unreliable on a pushed route" quirk the note below and the `branches_screen.dart` entry above both hit), while an *extended* FAB one level up and a `showDialog` reached via a different control on the *same* pushed screen both worked fine — confidence rests on the identical extraction pattern proven live twice elsewhere in this same phase, plus `flutter analyze`/tests. Also not reached live: Purchase Orders' `StatusPill` (no saved PO to view, same FAB reason) and the printer-connected `StatusPill` (no Bluetooth printer paired in the simulator). |

| 2026-08-12 | E | **Coordinator independently re-verified both Phase E halves** (trust-but-verify): re-ran `flutter analyze` (clean) and `flutter test` (370/370) myself; confirmed `docs/DESIGN_PASS.md` and `PROJECT_SPEC.md` merged coherently from the two concurrent subagent sessions (no duplicated headers, no corrupted table rows — both wrote to genuinely disjoint sections). Read the crash-fix structure directly in `branches_screen.dart` (`_CreateBranchDialog`) and `purchase_order_editor_screen.dart` (`_ProductPickerSheet`, `_LineEditorDialog`) — both correctly shaped `StatefulWidget`s with `dispose()` on real teardown, matching the five prior fixes. Rebuilt and live-verified on iPhone 17 Pro: Settings list navigation, Printer settings (confirmed the "printer connected" `StatusPill` genuinely can't be seen without a paired Bluetooth device, matching both subagents' own caveat — not a gap in verification effort), and reached the Purchase Order editor screen (supplier/note fields, items list, Save button all render correctly on the new tokens). | **Could not get past the same wall both subagents hit**: `purchase_order_editor_screen.dart`'s small icon-only "add product" `FloatingActionButton` did not register a tap across 4 separate attempts with carefully recalculated coordinates, on the *same* screen where the extended "Create purchase order" FAB one level up worked correctly (confirming the coordinate math itself is right) and where the code (`floatingActionButton: FloatingActionButton(onPressed: _addProduct, ...)`) is unremarkable — no `heroTag` collision, no disabled condition, no `IgnorePointer`. Three independent sessions now hitting the identical wall on the identical control is enough to call this a real characteristic of `mcp__Claude_Code_iOS_Simulator__control` (or this specific `FloatingActionButton` shape) worth flagging plainly rather than a coincidence — see the coordinate-calibration note below, and if a future session needs to actually exercise this dialog live, try `mcp__Claude_Code_iOS_Simulator__control`'s `touch_path` action (a slower, eased tap-and-hold) instead of a bare `tap`, which hasn't been tried against this specific button yet. Confidence in the fix itself rests on code review + the identical extraction pattern proven live 6 times elsewhere this session, not on exercising this exact button. |

| 2026-08-12 | F | **Phase F — both parallel subagents (F1 admin, F2 storefront/invoices-web) hit the account's monthly spend limit mid-task, the third and fourth occurrences this session.** Unlike Phase D's second interruption (real scope left untouched), both agents here left genuinely complete, high-quality work behind — the coordinator's job was finishing a small remainder and documenting, not redoing anything. F1 (admin) was essentially done: `admin_login_screen.dart` fully rebuilt onto shared auth components, `admin_app.dart`'s theme + `_NotAuthorized` view converted, `admin_dashboard_widgets.dart` mostly converted with a well-reasoned doc comment on *why* admin adopts `AppTheme` (it's GoldPOSMM's own tool) — only 3 raw colors near the end of that 924-line file were unreached, fixed directly by the coordinator (`enabled ? Colors.green : Colors.grey` → `AppColors`, a `Colors.red` delete icon → `AppColors.danger`, a `Colors.black54` caption → a theme text role + `AppColors.muted`, plus one bare empty state → `EmptyStateView`). F2 (storefront) had fully converted `storefront_screen.dart` (including an eighth crash-pattern instance — a straight leak this time, `_BlockedCustomersScreen._addBlock`'s controllers never disposed at all) and `storefront_page.dart`/`storefront_app.dart` (with a genuinely well-reasoned branding decision documented inline — grepped the data model for per-shop color fields, found none, concluded the old purple seed was an unreplaced default not an intentional brand boundary) — but never reached `invoices_web/*` at all, which the coordinator did from scratch: `invoices_web_app.dart` onto `AppTheme` (same reasoning as admin — this is the shop owner's own tool, not a customer-facing page, so the storefront branding question doesn't apply), `activate_screen.dart`/`invoice_list_screen.dart`/`invoice_detail_web_screen.dart` onto `MoneyText`/`ButtonSpinner`/`EmptyStateView`/spacing tokens. `flutter analyze` clean, 370/370 tests pass throughout. | **A real, pre-existing bug found live, not introduced by this phase**: `.claude/launch.json`'s `storefront-web` entry was missing `--dart-define-from-file env.local.json` (present on its two sibling entries) — the practical symptom was a completely blank page with zero console errors and an empty accessibility tree, diagnosed by re-running the identical `flutter run` command with the flag added on a fresh port, which then rendered correctly. Fixed in `launch.json`. **Verified live via the Browser tools** (this phase's first time using them instead of the iOS Simulator, since it's Flutter Web) against real `flutter run -d web-server` builds for all three surfaces: admin login screen, storefront's `_NoSlug` screen (after the launch-config fix), and `invoices_web`'s `ActivateScreen` — all three render correctly on the new deep-green tokens with no visual defects. Not verified: what's past admin login (no valid credentials available — noted rather than silently skipped) and `storefront_screen.dart`'s crash fix on the actual iOS Simulator (code-reviewed only, matching seven prior proven-live fixes of the identical shape). **All six phases of the app-wide design pass are now complete.** |

### Note for next session — coordinate calibration for `mcp__Claude_Code_iOS_Simulator__control`
Tap coordinates for this tool are in **device points** as reported by `attach` (e.g. 402×874 for iPhone 17 Pro), NOT the pixel dimensions the screenshot appears at when viewed. Estimate tap position as a **fraction of the screenshot's visual layout**, then multiply by the point-space width/height — don't eyeball raw pixel numbers from the image. Also: a `swipe`/`touch_path` whose start point lands on the bottom navigation bar (roughly the bottom ~90pt of a compact-width screen) gets consumed by the nav bar and never reaches the scrollable content above it — start swipes well clear of it (e.g. `y=700` on an 874pt-tall screen, not `y=800`). **New this session:** on at least one pushed (non-tab-shell) route, a `FloatingActionButton`'s tap target did not register across several plausible coordinate estimates while other elements on the same screen (list rows) worked fine at the same calibration — if a tap silently fails to do anything on a screen reached via `Navigator.push` rather than the bottom-tab shell, try a nearby alternate entry point to the same code path before concluding the app itself is broken.

### Note from the previous session — Simulator verification was partial, read before assuming Phase A is fully closed out visually
- **What was verified live on the iOS Simulator (real build, `flutter run --dart-define-from-file=env.local.json`, device already past onboarding from a prior install):** the Cash Register/Till screen (`my` locale, light) and the **Inventory** screen (untouched by this pass — a ripple-effect check) in **both light and dark** via `xcrun simctl ui <device> appearance dark|light`. All three confirm: warm cream/near-black surfaces render correctly, `NotoSansMyanmar` renders Myanmar product names cleanly with no diacritic clipping, the gold `primaryContainer` tint shows correctly on the FAB and the selected nav-bar pill in both brightnesses, hairline dividers and tonal cards read cleanly. Screenshots are in the session's scratchpad (not committed — ask if you need them re-taken).
- **What could NOT be verified live this session:** the Sell screen and Checkout sheet specifically, and the `en`-locale entry/auth screens — **this environment has no touch-injection into the iOS Simulator** (no computer-use/idb tool available; `osascript`/System Events UI scripting is blocked with error -25204, Accessibility permission not granted to the calling process; `xcrun simctl` has no synthetic-touch command). Getting past the already-onboarded device's daily Cash-Register gate, or driving the onboarding PageView, requires a tap. **Resolved next session — see the entry above; the coordinator's environment did have simulator touch access.**
- **A `flutter test`-based screenshot harness was attempted** (real screens + real Riverpod providers + an in-memory Drift DB + `tester.tap()`, dumping PNGs via `matchesGoldenFile`/`--update-goldens`) as a substitute that doesn't need simulator taps. It hung repeatedly (`pumpAndSettle` never settling) and was **abandoned and deleted** rather than left half-working — do not recreate it without first isolating why it hangs (my working theory, unconfirmed: a `StreamProvider` override using `Stream.empty()` for `categoriesStreamProvider`/`paymentAccountsProvider` never emits, unlike a real Drift watch which emits an initial `[]` immediately — use `Stream.value(const [])` instead next time, not `Stream.empty()`). If you pick this up again, isolate one `testWidgets` case at a time with a short explicit `pumpAndSettle(..., timeout: Duration(seconds: 15))` rather than the 10-minute default, so a hang fails fast instead of burning the session.
- **Recommendation for next session:** either (a) ask the user to grant Accessibility permission to the terminal/agent process so `osascript`/System Events can inject taps, (b) ask the user to manually tap through Sell → Checkout and Onboarding while screenshots are taken between steps, or (c) fix the widget-test harness per the note above. Do not claim Sell/Checkout/en-locale visual verification happened without one of these.

| 2026-08-16 | E (follow-up) | **`printer_settings_screen.dart` — owner reviewed a screenshot of PROJECT_SPEC.md #123's per-printer paper-size feature and asked for a focused visual/UX pass, no behavior changes.** Full detail in PROJECT_SPEC.md §12 #124. Short version: the "pick a different printer" list's bare `Icons.bluetooth` `ListTile`s became a new `_PairedDeviceTile` using `IconAvatar`, wrapped in one `Card` with hairline `Divider`s to harmonize with the active-printer `Card` already above it (that one already used `IconAvatar`/`StatusPill` from the original Phase E pass — this closes the gap on the list below it, which Phase E's original pass left as plain `ListTile`s); the selected row gets `selectedTileColor: colorScheme.secondaryContainer` (reusing `invoices_screen.dart`'s established selected-row pattern) plus a positive-toned `IconAvatar` and a trailing check icon; the three inline `titleMedium` section headers became `SectionHeader` (the established sub-section pattern, see `storefront_screen.dart`); the new paper-size-choice dialog's `MaterialLocalizations...okButtonLabel` ("OK", the only such call site in the app) became `l.commonSave` and gained the `l.commonCancel` button every other choice-dialog in the app has (`stock_adjust_dialog.dart` etc.) — no icon-framed dialog convention exists anywhere in the codebase (grepped all `AlertDialog(` call sites), so none was invented here. No new i18n keys — reused `commonSave`/`commonCancel`. `flutter analyze` clean, 399/399 tests pass unchanged. | **Coordinate-calibration note confirmed again this session** (see the note above): a stale, non-rebuilt app on the simulator can look deceptively similar to a fresh build when the diff is subtle styling (titleMedium bold-black vs. SectionHeader's titleSmall+onSurfaceVariant look similar at a glance) — did a real `flutter run --dart-define-from-file=env.local.json` rebuild specifically to be sure the installed binary reflected the change, rather than trusting a `simctl launch` of a possibly-stale install. **Verified live** on iPhone 17 Pro, `en`+`my` × light+dark, no-printer-paired state: section headers and the Myanmar "ချိတ်ဆက်ထားသော စက်များ" header + trailing button don't collide, no overflow in any of the four combinations. **Not reachable live** (no real Bluetooth peripherals in the Simulator, same limitation every prior Phase E entry already hit on this exact screen): the active-printer `Card`, the paired-list's populated/selected-row state, and the new dialog — all code-reviewed only. |
