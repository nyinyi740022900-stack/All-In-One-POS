# All In One POS — marketing site

Static HTML/CSS/JS marketing/landing page for the app itself (intro, feature
overview, usage guide, download links). Plain vanilla — no build step, no
framework — for the fastest possible load and best SEO on a public landing
page.

This is a **separate** site from `lib/storefront/` (the customer-facing
per-shop storefront + `/renew` license page, deployed at
`shop.allinonepos.app`) and from `lib/admin/` (the owner admin
console). Do not merge them — they serve different audiences and have
different deploy lifecycles.

## Structure

```
marketing-site/
  index.html          home: hero, cinematic showcase, feature hub, how-it-works, download
  styles.css          brand tokens + cinematic photo/parallax/reveal styling
  icons.css           animated custom icon set (entrance + continuous micro-loop per feature)
  feature-page.css    shared layout for the 19 feature tutorial pages
  script.js           scroll-reveal (IntersectionObserver) + parallax (rAF) + phone-shot
                       fallback + language toggle
  features/           one full "how to use" tutorial page per feature area —
                       sell.html, inventory.html, invoices.html, printing.html,
                       analytics.html, credit.html, expenses.html, cash.html,
                       customers.html, orders.html, accounts.html, equity.html,
                       backup.html, license.html, branches.html, storefront.html,
                       purchase-orders.html, payables.html, staff.html — each with
                       numbered steps, real app screenshots, tips, and related links
  assets/
    app_icon.png, app_mark.png   (copied from assets/branding/)
    photos/           hero + showcase photography (Ken-Burns background
                       plates and foreground portrait/product shots), each
                       as .jpg + .webp (picture element serves webp first)
    screenshots/<feature>/NN-name.jpg   real app screenshots per tutorial step
                       (converted to actual JPEG regardless of source format —
                       see "Adding a tutorial screenshot" below)
  vercel.json         static hosting config
```

### Prices on the landing page

The `#plans` cards show real figures, mirrored by hand from production
`app_config`: `price.monthly` 20,000 · `price.yearly` 200,000 ·
`device.free_limit` 3 · `device.extra_fee` 10,000. This page is static and
never reads the backend, so **changing a price in the admin console means
changing it here in the same change-set** — otherwise a shop reads one
number here and is charged another on `/renew`.

The Premium card's primary action goes straight to the renewal form
(`shop.allinonepos.app/renew`), with the Viber number as the second
path. Those are the only two ways a shop can pay; the iOS/Play builds of the
app deliberately carry no purchase UI at all (see `lib/core/build_flags.dart`),
so for those users this page IS the purchase path.

### Feature tutorial pages

Each `features/*.html` follows the same structure (`.fhero` → `.tutorial`
with numbered `.tstep` rows → `.tips-section` → `.related-section` → `.fcta`).
A `.tstep`'s screenshot sits in a `.phone-shot` frame; if the referenced
image 404s, `script.js` adds `.img-missing` and CSS shows a dashed
placeholder ("Screenshot ထည့်ရန် စောင့်နေသည်") instead of a broken-image
icon — so a page stays presentable even before every screenshot exists.
Three slots are still placeholders pending a screenshot: `sell/01-grid.jpg`
(product grid), `expenses/01-add.jpg` (add-expense dialog),
`customers/02-add.jpg` (add-customer dialog).

### Adding a tutorial screenshot

Drop the raw screenshot anywhere and convert it to a real JPEG at a
consistent width (source format doesn't matter — HEIC/WebP/PNG all work;
`sips` reads and converts them):
```bash
sips -Z 700 -s format jpeg -s formatOptions 82 raw-screenshot.png \
  --out assets/screenshots/<feature>/NN-name.jpg
```
The `<img>` in the matching `features/<feature>.html` `.tstep` already
points at that path — no HTML change needed once the file lands there.

### Language toggle (English / Myanmar)

Every page ships bilingual. The Myanmar text is the page's real markup, as
always; an element that needs an English version just gets a
`data-i18n-en="..."` attribute holding the English HTML as a string (so
inline tags like `<strong>` survive — write them HTML-entity-escaped,
e.g. `&lt;strong&gt;`, since the attribute value is parsed once by the
browser and only literal `<`/`>` inside it would break the tag). `script.js`
caches each element's original Myanmar `innerHTML` on load, then swaps
`innerHTML` between the cached Myanmar and the `data-i18n-en` string when
the `.lang-toggle` button (present in every page's nav) is clicked. The
choice is remembered in `localStorage` across pages.

To add a new translatable element: write the Myanmar content normally, then
add `data-i18n-en="English version"` to the same tag. Nothing else to wire
up — no key registry, no per-page dictionary.

### Cinematic photo technique

The hero and download sections use a "photo + motion blend" layering: a
full-bleed background photo (`data-speed` parallax + a slow CSS `kenburns`
zoom, see styles.css) sits behind a separately-shot foreground subject
(`hero-portrait-card`) drifting at its own, different parallax speed —
script.js's generic `[data-speed]` handler already covers both. The feature
section uses the same photography in alternating left/right "showcase" rows
instead of icon cards. Section boundaries fade via a gradient mask
(`.hero::after`, `.download-section::before`) rather than a hard cut.

To swap in new photography, replace files under `assets/photos/` (keep the
same names) and re-run `cwebp` to regenerate the `.webp` sibling:
```bash
cwebp -q 80 assets/photos/hero-bg.jpg -o assets/photos/hero-bg.webp
```

## Local preview

```bash
cd marketing-site
python3 -m http.server 8080
# open http://localhost:8080
```

## Deploy (new Vercel project)

```bash
cd marketing-site
vercel deploy --prod --yes --scope nyi-nyi-s-projects1
```

This deploys to the **`allinonepos-marketing`** project — the host every
page's `canonical`/`og:url` and `sitemap.xml` name. Deploying this folder
anywhere else splits the site across two hosts and de-indexes it (that is
exactly what happened with the retired `allinonepos-site` duplicate), so
if `.vercel/` is ever missing, relink it explicitly:

```bash
vercel link --yes --project allinonepos-marketing --scope nyi-nyi-s-projects1
```

## Updating the Windows download link

The Windows download button points at the rolling GitHub Release
`windows-latest`, published automatically by
`.github/workflows/windows_desktop.yml` on every push to `main` that touches
app code:

```
https://github.com/nyinyi740022900-stack/goldposmm/releases/download/windows-latest/AllInOnePOS-windows.zip
```

This URL never changes — no edits needed here when a new build ships.

## Adding iOS/Android download links

Once published, replace the "မကြာမီ လာမည်" (Coming soon) badge in the
iOS/Android `.download-card` blocks in `index.html` with a real
`<a class="btn btn-primary btn-block" href="...">` to the App Store / Play
Store listing, matching the Windows card's markup.
