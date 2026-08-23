# All In One POS — marketing site

Static HTML/CSS/JS marketing/landing page for the app itself (intro, feature
overview, usage guide, download links). Plain vanilla — no build step, no
framework — for the fastest possible load and best SEO on a public landing
page.

This is a **separate** site from `lib/storefront/` (the customer-facing
per-shop storefront + `/renew` license page, deployed at
`allinonepos-shop.vercel.app`) and from `lib/admin/` (the owner admin
console). Do not merge them — they serve different audiences and have
different deploy lifecycles.

## Structure

```
marketing-site/
  index.html          all sections (hero, features, how-it-works, download, footer)
  styles.css          brand tokens + cinematic photo/parallax/reveal styling
  script.js           scroll-reveal (IntersectionObserver) + parallax (rAF)
  assets/
    app_icon.png, app_mark.png   (copied from assets/branding/)
    photos/           hero + feature photography (Ken-Burns background
                       plates and foreground portrait/product shots), each
                       as .jpg + .webp (picture element serves webp first)
  vercel.json         static hosting config
```

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

First deploy: when Vercel asks, link it as a **new** project (e.g.
`allinonepos-site`), not the existing `allinonepos-shop`/`allinonepos-admin`
projects.

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
