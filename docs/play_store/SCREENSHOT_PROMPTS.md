# Play Store screenshot prompts (Gemini image generation)

**Design brief:** four DIFFERENT compositions, not one template repeated with
swapped text — that's what Loyverse/Daily Sales Record do (same
headline-over-phone layout, four times) and it reads as repetitive up close.
Instead, each slide below uses its own layout idea. What ties the set
together as one brand is: the locked color palette, the same small logo
badge in the same corner on every slide, and consistent typography — not a
repeated composition.

Attach the matching real device screenshot as the image input, paste the
prompt as text input. Generate one at a time.

Brand tokens (from `marketing-site/styles.css` — keep locked across all 4):

| Token | Value |
|---|---|
| `--brand` | `#0F5C3E` |
| `--brand-dark` | `#0B3D29` |
| `--brand-light` | `#1C7A54` |
| `--brand-tint` | `#E3F3E9` |
| Headline font | Inter Black/Extrabold |
| Logo mark | `docs/play_store/graphics/play_icon_512.png` (use as the small corner badge on every slide) |

Output spec for every image: **1080×1920px portrait, flattened PNG or JPEG,
no alpha channel.**

**Cohesion rule (applies to all 4):** small circular badge of the app's
green icon mark, ~72px, bottom-left corner, sitting on a small white pill
for contrast — the one repeated element across all four designs so the set
still reads as one app despite the different layouts.

---

## 1. "Hero Spotlight" — Sell screen

The loud, confident opener — biggest single visual impact, leads the set.

**Attach:** the Sell screen screenshot (product grid)

**Prompt:**
> Create a Google Play Store marketing screenshot, 1080×1920px portrait, no
> transparency. Background: deep forest green `#0F5C3E` transitioning to
> `#0B3D29` toward the bottom, with a soft circular glow in `#1C7A54` (low
> opacity, soft-edged) centered behind where the phone sits — a spotlight
> effect, not a hard gradient band. In the top ~22%, a massive bold
> centered headline in white, Inter Black, ALL CAPS, tight line-height:
> "SCAN, TAP, SOLD" — with "SOLD" in the mint accent `#E3F3E9`. Below it, a
> large smartphone mockup (white or `#1C7A54` frame, rounded corners, soft
> deep shadow that reads as if floating in the glow) containing the attached
> Sell-screen screenshot faithfully reproduced — tilted 5° clockwise, sized
> to fill ~80% of canvas width, bottom edge bleeding slightly off the canvas
> for scale and energy. Small circular app-icon badge (green mark on a white
> pill) in the bottom-left corner, ~72px. Confident, punchy, high-contrast —
> this is the lead image. Export flattened, no alpha, exactly 1080×1920px.

---

## 2. "Annotated Callouts" — Inventory screen

Infographic-style — teaches a feature instead of just showing it, breaks the
"headline + floating phone" pattern entirely.

**Attach:** the Inventory screen screenshot (stock list with low-stock badge)

**Prompt:**
> Create a Google Play Store marketing screenshot, 1080×1920px portrait, no
> transparency. Background: solid flat `#0B3D29` (darker forest green, no
> gradient) — deliberately moodier/darker than a typical hero slide since
> this one's job is legibility for callouts, not spectacle. Upper-left:
> stacked bold white headline, Inter Black, "NEVER RUN OUT OF STOCK" with
> "STOCK" in mint `#E3F3E9`, left-aligned (not centered). Phone mockup:
> upright, NOT tilted, positioned right-of-center, large but not full-bleed,
> white/`#1C7A54` frame, containing the attached Inventory screenshot
> reproduced faithfully. To the left of the phone, three small horizontal
> pill-shaped callout badges stacked vertically (white text on `#1C7A54`
> pill background, small line-icon per pill): a bell icon + "Low-stock
> alerts", a bar-chart icon + "Live stock counts", a barcode icon + "Scan to
> add". Each pill has a thin 1px mint leader line extending rightward,
> terminating in a small dot pointing toward the corresponding area of the
> phone screenshot (approximate is fine — this is a stylized annotation, not
> precise UI pointing). Small circular app-icon badge (green mark on white
> pill) bottom-left corner, ~72px, positioned so it doesn't collide with the
> callout pills. Export flattened, no alpha, exactly 1080×1920px.

---

## 3. "Ecosystem Orbit" — Settings (Business tools)

The differentiator slide — visually argues "all-in-one" instead of just
saying it. Nothing like this exists in competitor listings.

**Attach:** the Settings screen screenshot showing the Business section
(Shop profile / Cash register / Suppliers / Purchase orders / Storefront)

**Prompt:**
> Create a Google Play Store marketing screenshot, 1080×1920px portrait, no
> transparency. Background: `#0F5C3E` deep green with a large, soft-edged
> circular field of `#1C7A54` centered in the upper two-thirds of the
> canvas, like a glowing hub. In the center of that glow, a MEDIUM-sized
> phone mockup (noticeably smaller than the hero slide's phone — this is a
> deliberate scale contrast within the set), upright, white frame,
> containing the attached Settings screenshot reproduced faithfully. Around
> the phone, arrange 5 small white circular icon badges (simple line icons,
> `#0B3D29` icon color) in an orbit/constellation pattern at varying
> distances — a truck icon (Suppliers), a shopping-cart icon (Purchase
> orders), a storefront icon (Web storefront), a cash-register icon (Cash
> register), a people icon (Customers) — each connected to the phone by a
> thin dotted mint `#E3F3E9` line, like a hub-and-spoke diagram showing
> everything orbiting the central app. Headline positioned in the BOTTOM
> third of the canvas (inverted from a typical top-headline layout), bold
> white Inter Black, centered: "ALL YOUR TOOLS, ONE APP" with "ONE APP" in
> mint `#E3F3E9`, and a smaller subheadline below in `#E3F3E9`: "Suppliers,
> purchase orders, storefront — all connected." Small circular app-icon
> badge bottom-left corner, ~72px, clear of the headline text. Export
> flattened, no alpha, exactly 1080×1920px.

---

## 4. "Duotone Split" — Settings (Finance & Team)

The premium/editorial close — most visually distinct of the four, reads as
confident rather than crowded even though it covers the most features.

**Attach:** the Settings screen screenshot showing Finance / Account & Team
(Credit book / Expenses / Owner's equity / License / Staff accounts /
Branches)

**Prompt:**
> Create a Google Play Store marketing screenshot, 1080×1920px portrait, no
> transparency. Background: a hard-edge vertical split straight down the
> center — left half solid `#0F5C3E` deep green, right half solid
> `#E3F3E9` mint/off-white. No gradient, no blending at the seam, a crisp
> vertical line. A smartphone mockup sits centered, straddling the seam
> exactly, tilted 4°, white frame with soft shadow, containing the attached
> Settings screenshot reproduced faithfully — sized so it visually bridges
> both halves. Headline split across the two halves at the top ~20%, same
> baseline, reading as one continuous phrase: on the green (left) half, in
> white Inter Black, "BEYOND"; on the mint (right) half, in `#0B3D29` dark
> green Inter Black, "JUST SELLING" — same type size and weight on both
> sides so it reads as one confident headline despite the color switch.
> Below the phone, a single thin horizontal pill/tag row, centered, straddling
> the seam, white text on a `#0B3D29` pill background: "Credit book ·
> Expenses · Multi-branch · Staff logins". Small circular app-icon badge in
> the bottom-left corner sitting on whichever half's contrast reads best
> (white mark if on the green side, `#0F5C3E` mark if on the mint side),
> ~72px. This slide should feel editorial and premium, not busy — the
> duotone split does the visual work, not clutter. Export flattened, no
> alpha, exactly 1080×1920px.

---

## 5. "Value Stack" — closer, no screenshot needed

Every other slide is built around a phone mockup — this one deliberately
drops it entirely, which is itself the visual break that signals "closing
card" (a common pattern: the last screenshot in a set often has no UI at
all, just the pitch). No device to attach here.

**Prompt:**
> Create a Google Play Store marketing screenshot, 1080×1920px portrait, no
> transparency. Background: solid flat `#0B3D29` (darkest of the set's
> greens, for a confident close). No phone mockup anywhere in this one —
> pure typography and iconography. Top ~18%: the app name as a bold
> wordmark, Inter Black, white, centered: "ALL IN ONE POS" — modest size,
> this is a signature, not the headline. Below it, a thin horizontal mint
> `#E3F3E9` rule, short (~120px wide), centered. Middle ~60% of the canvas:
> four stacked rows, each a small white circular icon-badge on the left (line
> icon, `#0B3D29` icon color) paired with a short bold line of white text to
> its right, generously spaced vertically, left-aligned as a block but
> centered as a group on the canvas: a Wi-Fi-off icon + "Works fully
> offline", a globe/translate icon + "English + Myanmar", an infinity icon +
> "Free to sell, forever", a shield icon + "Your data stays yours". Each row
> plain, no pills or boxes — just icon + text, generous whitespace between
> rows so it doesn't feel like a form. Bottom ~15%: small circular app-icon
> badge (green mark on white pill, ~72px) centered — this one time, centered
> rather than bottom-left, since it's acting as a closing signature rather
> than a corner watermark. Calm, confident, uncluttered — this slide's job is
> to feel like a clean exhale after four busy feature slides, not to compete
> with them for attention. Export flattened, no alpha, exactly 1080×1920px.

---

## Why this beats a repeated template

Loyverse and Daily Sales Record use the exact same "headline block + phone"
composition on every single screenshot — only the copy changes. Up close (as
a listing page, not a search thumbnail), that reads as low-effort. This set
instead varies: composition (centered hero → left-aligned annotation →
radial hub → split duotone → icon-stack closer), phone scale (large →
medium → medium → medium → none), headline position (top → top-left →
bottom → split → top-signature), and background treatment (glow → flat dark
→ radial → hard split → flat darkest) — while the locked palette + repeated
logo badge keep it unmistakably one app. That's the same technique premium
App Store listings (Notion, Linear, Superhuman) use: vary the layout, lock
the brand system.

---

## After generating

1. Save the five outputs into `docs/play_store/screenshots/final/` (create
   the folder — gitignored like the rest of `docs/play_store/screenshots/`).
2. Order in Play Console: **Hero Spotlight → Annotated Callouts → Ecosystem
   Orbit → Duotone Split → Value Stack** (biggest-impact image first, per
   Play SEO
   convention — the first 1-2 screenshots are what show in search results).
3. Check each at Play Console's small thumbnail size before finalizing —
   the accent word / split headline needs to stay legible that small.
