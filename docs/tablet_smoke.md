# Tablet smoke checklist

Breakpoints: **compact** &lt; 640 · **medium** ≥ 640 (NavigationRail + splits) · **expanded** ≥ 1024.

## Devices

| Device | Orientation | Pass? |
|---|---|---|
| iPad Air 11" Simulator | landscape | |
| iPad Air 11" Simulator | portrait | |
| Android Pixel Tablet emulator | landscape | |
| iPhone (any) | portrait | |

## Must pass

### Shell
- [ ] Width ≥ 640 shows **NavigationRail** (not bottom bar)
- [ ] Rotate compact ↔ medium without crash / blank frame

### Sell (P0)
- [ ] Medium+: product grid left, **persistent cart** right
- [ ] Tap product → cart line updates in the side panel
- [ ] Qty ± / Clear / Checkout work from the panel
- [ ] Checkout completes a sale (dialog on tablet, sheet on phone)
- [ ] Compact: bottom cart bar + sheet unchanged

### Orders / Invoices (P1)
- [ ] Medium+: list | detail pane; empty pane shows select hint
- [ ] Selecting a row updates the detail pane (no full-screen push)
- [ ] Compact: list → sheet/push still works

### Inventory / Settings (P2)
- [ ] Medium+: denser product **grid** (edit still pushes)
- [ ] Settings list capped width (not edge-to-edge stretch)

### Regression
- [ ] Phone portrait: Sell / Orders / Invoices / Inventory behave as before

## Notes

Physical iPad QA is nice-to-have. Ready = sim/emu + phone regression.

After Sell split lands, capture iPad screenshots for App Store Connect
(see `docs/app_store/LISTING.md`; keep `TARGETED_DEVICE_FAMILY = 1,2`).
