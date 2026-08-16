# Windows desktop POS (Phase 2)

**Policy:** Computer support targets **Windows only**. macOS desktop is
scaffolded but deferred (blank-window issue; not a product priority).

Phone/tablet remain the primary POS. Windows is the shop-PC path for full
Sell/Inventory/Orders (native Drift SQLite — same offline model as mobile).
Invoices-only on any computer can still use
https://allinonepos-invoices.vercel.app (Phase 1).

## Build gate: GitHub Actions

Workflow: [`.github/workflows/windows_desktop.yml`](../.github/workflows/windows_desktop.yml)

- Runs on `windows-latest` (cannot build Windows from a Mac).
- Triggers: `workflow_dispatch`, and push/PR touching `lib/`, `windows/`,
  `pubspec.*`, l10n, or the workflow file.
- Uploads artifact `AllInOnePOS-windows-<sha>` (Release folder, ~14 days).

### Repo secrets (optional but recommended)

| Secret | Purpose |
|---|---|
| `SUPABASE_URL` | Backend URL |
| `SUPABASE_ANON_KEY` | Anon key (RLS) |
| `SENTRY_DSN` | Crash reporting (optional) |

Without secrets the build still succeeds; the app runs with empty defines
(`Env.hasBackend == false`).

### Download a CI build

1. GitHub → Actions → **Windows desktop** → latest green run.
2. Artifacts → download `AllInOnePOS-windows-…`.
3. Unzip → run `mm_pos.exe`.

## Local build (when you smoke-test on the Windows PC)

Prereqs: Flutter stable, Visual Studio 2022 with **Desktop development with C++**.

```bat
flutter config --enable-windows-desktop
flutter pub get
flutter build windows --release --dart-define-from-file=env.local.json
```

Output: `build\windows\x64\runner\Release\mm_pos.exe`

Copy `env.local.json` from the Mac (or recreate) — never commit it.

## Human smoke (after CI is green — do on the Windows PC)

See [SMOKE.md](SMOKE.md). Defer until the CI artifact boots cleanly.

## Known gaps on Windows

| Feature | Status |
|---|---|
| Sell / Inventory / Orders / sync | Goal — same Dart code as mobile |
| Layout (wide window) | Uses tablet breakpoints (rail + Sell split) |
| Bluetooth thermal print | Weak / may not work — use PDF/share for now |
| Camera barcode (`mobile_scanner`) | No Windows plugin — use USB wedge scanner or type |
| macOS desktop | Deferred |

## Do not

- Expect `flutter build windows` on macOS.
- Treat a green CI build as “Ready” until [SMOKE.md](SMOKE.md) passes on a real PC.
- Commit `env.local.json` or upload keys.
