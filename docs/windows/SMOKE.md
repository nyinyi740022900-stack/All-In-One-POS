# Windows POS smoke checklist

Run **after** a green GitHub Actions **Windows desktop** build (or a local
`flutter build windows --release`). Not required for the CI gate itself.

## Setup

- [ ] Download CI artifact **or** build locally with `env.local.json`
- [ ] `mm_pos.exe` launches (window paints; not blank)
- [ ] Wide window (≥ 640): NavigationRail visible

## Core

- [ ] Onboarding / license activate (or existing key)
- [ ] Sell: add product → cart (side panel on wide) → checkout → sale
- [ ] Inventory: browse / edit product
- [ ] Orders: list + detail
- [ ] Sync: pending → up to date (with backend defines)
- [ ] Multi-shop A→B→A (if Premium / branches)

## Expected limitations (OK for v1)

- [ ] Camera scan may be unavailable — USB barcode or manual search OK
- [ ] Bluetooth printer may be unavailable — PDF/share OK

## Sign-off

| Build | Date | Tester | Pass? |
|---|---|---|---|
| sha / local | | | |
