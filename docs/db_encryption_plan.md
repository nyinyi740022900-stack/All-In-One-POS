# At-rest database encryption — migration plan

Status 2026-10-16 (later): **implemented** — `lib/data/local/db_encryption.dart`,
recovery screen `lib/features/backup/db_locked_app.dart`, tests
`test/db_encryption_test.dart` + `test/db_locked_screen_test.dart`. Not yet in
any store build (build 7 predates it). The sections below are the original
plan; §8 records where the implementation differs from it.

## 1. Where we are

| Fact | Evidence |
|---|---|
| `sqlite3` 3.x with its native build hook is already the SQLite source | `pubspec.yaml` `sqlite3: ^3.5.2`; `sqlite3_flutter_libs` removed (comment in `lib/main.dart`) |
| Hooks run without a machine-wide flag | Flutter 3.47.4 stable, `flutter config` shows `enable-native-assets: (Not set)` |
| The hook can build an encrypting SQLite | `sqlite3-3.5.2/doc/hook.md`: `hooks.user_defines.sqlite3.source: sqlite3mc` or `sqlcipher` |
| Files to protect | per-shop `mm_pos_<shopId>.sqlite`, device sidecar `mm_pos_device.sqlite`, legacy `mm_pos.sqlite` (+ `.bak`) — all in app Documents (`AppDatabase` §`pathForShop`) |
| Every file opens through one function | `AppDatabase._nativeExecutor` → `NativeDatabase.createInBackground(file)`; the only other opener is `shop_db_migrator.dart` (`NativeDatabase(shopFile)`, two sites) |
| Already mitigated | Android `allowBackup="false"`; OS file encryption (iOS Data Protection, Android FBE on 10+) |
| Not covered by DB encryption | Backup export is **plaintext JSON** (`backup_service.dart::writeBackupFile`) shared via the share sheet; the image cache (sqflite, `cached_network_image`) |

**What encryption actually adds:** protection when someone has the *files*
but not the unlocked app — a rooted/jailbroken phone, a forensic copy, a
desktop (Windows) install where the user profile is readable. On a locked,
stock phone the OS already encrypts the files.

## 2. Recommendation: SQLite3MultipleCiphers, not SQLCipher

- `sqlite3mc` needs **no OpenSSL** (SQLCipher links OpenSSL on Android/Windows);
  smaller build surface, MIT-style licence to review vs. SQLCipher's BSD +
  OpenSSL notices.
- Same `PRAGMA key` API, SQLCipher-compatible cipher scheme available.
- **`PRAGMA rekey` encrypts an existing plaintext file in place** — no
  export-to-new-file dance for the migration.
- The hook docs warn the bundled SQLCipher may lag upstream SQLite; `sqlite3mc`
  tracks it more closely.

## 3. The real risk: key loss = data loss

Today a Free/offline shop's only copy of its books is the local file. Once
encrypted, **losing the key loses the shop** — and a Free shop has no cloud
copy to re-pull. This is the deciding design constraint, more than the code.

Known ways a key can go missing:
- Android Keystore entries invalidated (some OEMs after a lock-screen change,
  or `flutter_secure_storage` decrypt failures after an OS update).
- iOS Keychain item written with an accessibility class the app later can't
  read (e.g. before first unlock after reboot) — must use
  `first_unlock_this_device`, as `saved_login_store.dart` already does.
- An owner moving to a **new** iPhone from an iCloud/encrypted backup gets
  Documents restored, but `…ThisDeviceOnly` keychain items do not migrate to
  a different device → the file arrives without its key.

Mitigations required before shipping:
1. **Never encrypt without a verified key round-trip**: write key → read it
   back → open the DB with it → only then mark the shop as encrypted.
2. **Opening fails with the key → do not delete or recreate the file.** Show a
   recovery screen (restore from JSON backup / re-sync if Premium / contact
   support), keep the file untouched. Treat this like the existing
   pending-outbox guards: no silent wipe.
3. Before the one-time migration, **prompt a JSON backup** (and, for Premium,
   wait for the outbox to drain) so there is a second copy at the riskiest
   moment.
4. Telemetry: Sentry breadcrumb (no key material) on migrate start / done /
   failed, so a pattern of key loss shows up before it is widespread.

## 4. Design

- **One random 256-bit key per device**, generated with `Random.secure()`,
  stored in `flutter_secure_storage` (iOS `first_unlock_this_device`). Every
  file on that device (all shops + device sidecar) uses it — a shop switch
  (`DatabaseSession.reopenForShop`) and shop promotion (copy file) then need
  no re-keying. Not derived from the owner PIN or password (PIN changes and
  staff sign-ins must not re-key the books).
- Key enters SQLite as a raw hex key (`PRAGMA key = "x'…'"`) in the
  `NativeDatabase.createInBackground(file, setup: …)` callback — the setup
  closure runs on the background isolate, so pass the hex string, not the
  storage object.
- Same `setup` for both `shop_db_migrator.dart` openers.
- Per-file state: detect plaintext by reading the first 16 bytes
  (`SQLite format 3\0`) — no settings key needed, so nothing to classify in
  `settings_key_scope_test.dart` and nothing that can disagree with the file.
- **Web** (admin/invoices web) is unaffected — no local Drift file there.
- **Windows desktop**: same code path; CI job `windows_desktop.yml` must build
  with the new hook source.

## 5. Migration (one time, at startup, before `DatabaseSession.open` returns)

For each existing file (device sidecar first, then legacy, then every
`mm_pos_*.sqlite`):
1. Header says plaintext → open with no key, `PRAGMA integrity_check` must be
   `ok`, else skip this file and report (never encrypt a damaged file).
2. Copy to `<file>.pre-encrypt` (same directory, same Data Protection).
3. `PRAGMA rekey = "x'…'"` on the open plaintext connection; close.
4. Reopen **with** the key, `PRAGMA integrity_check` + `select count(*) from
   sales` equals the pre-copy count.
5. Success → delete `.pre-encrypt`. Failure → restore `.pre-encrypt` over the
   file, keep running plaintext, report; retry next launch.
Crash mid-step: on next launch a `.pre-encrypt` beside a file that won't open
with the key is restored first.

`-wal`/`-shm` files: checkpoint (`PRAGMA wal_checkpoint(TRUNCATE)`) before
step 2 so the copy is complete.

## 6. Tests to add with the change

- Unit (in-memory can't test files — use a temp dir): plaintext → encrypted
  round trip; wrong key fails to open and the file is untouched; crash between
  steps 3 and 4 restores from `.pre-encrypt`; two-shop device (both files
  migrated, switch still works); shop promotion copy opens with the key.
- `wipe_synced_data_test.dart`, `shop_db_migrator_test.dart`,
  `app_database_shop_path_test.dart` updated for keyed opens.
- Integration (`integration_test/`): app on simulator with a plaintext DB from
  build 7 → launch new build → sale history intact.
- Manual: upgrade install on a real Android and iPhone that already hold a
  shop with sales; reboot and open before first unlock (iOS) — must show the
  normal locked behaviour, not the recovery screen.

## 7. Order of work

1. Backup export encryption decision (separate, smaller: password-protected
   JSON) — it is the bigger leak today, since it leaves the device.
   **Still open.**
2. ~~Key store + keyed open behind a build flag~~ — done; flag is
   `DB_ENCRYPTION` (default **off**; beta builds pass `=true`).
3. ~~Migration of existing files + recovery screen~~ — done.
4. Beta to the closed track; watch Sentry migrate breadcrumbs for a week.
5. Changelog + Play Data safety ("data is encrypted" can then be claimed for
   on-device storage too).

## 8. As built (differences from the plan above)

- **iOS keychain class is `first_unlock`, not `first_unlock_this_device`.**
  A ThisDeviceOnly key does not travel to a new iPhone, while the Documents
  files it opens do (iCloud / encrypted Finder backup) — every phone upgrade
  would land on the recovery screen. With `first_unlock` the key moves with an
  encrypted backup. Threat model unchanged: the backup is protected by the
  owner's Apple account / backup password.
- **No backup prompt before migration.** Migration runs before the first
  frame, so there is no UI to prompt from. Instead each file is
  integrity-checked, copied to `.pre-encrypt`, rekeyed, re-verified (same
  tables, same row counts) and only then is the copy deleted; any failure
  restores the copy and the file stays plaintext until the next launch.
- **Opt-in, not on by default** (owner call, 2026-10-17, before merging to
  `main`): `main` publishes the Windows and Android downloads, so encryption
  only runs in a build made with `--dart-define=DB_ENCRYPTION=true`. Without
  it, *new* encryption is off; already-encrypted files still open (state is
  read from the header), so turning it off never locks a shop.
  `db_encryption_test.dart` fails if the default is flipped.
- **Key loss** → `DbKeyUnavailableException` before `runApp` → `DbLockedApp`
  (Try again / Viber support when the number can be fetched / Start with an
  empty shop). "Start empty" moves every `mm_pos*` file into
  `Documents/locked_<timestamp>/` — nothing is deleted — and clears the
  unreadable key entry.
- **A keystore that fails while nothing is encrypted yet** is not a lock: the
  launch stays plaintext and encryption is retried next launch.
- **Verified on the iOS Simulator (iPhone 17 Pro, iOS 26.4):** a pre-encryption
  build seeded a Free shop and a 700 Ks sale; installing the new build over it
  encrypted all three files (`sqlite3` CLI: "file is not a database"), the app
  opened straight to Sell with the sale, products and settings intact, a new
  300 Ks sale was written, and after a cold restart Today's sales read 1,000 Ks.
- **Verified on the Android emulator (Pixel 7):** same upgrade path — a
  pre-encryption APK seeded a Free shop and a 500 Ks sale; `adb install -r` of
  the new APK encrypted all three files (~170 ms each), the sale and products
  survived, and a cold restart reopened them with the Keystore-held key. The
  APK ships `libsqlite3mc.so` for arm64-v8a, armeabi-v7a and x86_64.
  Not exercised on a device: the recovery screen itself (widget-tested only —
  forcing it would mean wiping a keychain), a physical phone, Windows.

