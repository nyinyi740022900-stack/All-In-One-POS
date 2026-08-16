import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../features/invoices/receipt_data.dart';
import '../../features/printing/label_data.dart';
import '../local/database.dart';

/// Device-scoped key/value settings (not synced). Backs printer config,
/// shop receipt header/footer, etc.
class SettingsRepository {
  SettingsRepository(
    this._db, {
    AppDatabase? deviceDb,
    FlutterSecureStorage? secureStorage,
  }) : _deviceDb = deviceDb ?? _db,
       _secure = secureStorage ?? const FlutterSecureStorage();

  final AppDatabase _db;
  final AppDatabase _deviceDb;
  final FlutterSecureStorage _secure;

  /// Keys that live on the device sidecar after Priority C cutover.
  static bool isDeviceGlobalKey(String key) {
    if (key == 'device.id' ||
        key == 'license.json' ||
        key == 'license.trial_used' ||
        key == 'onboarding.done' ||
        key == 'operating.mode' ||
        key == 'operating.mode_confirmed' ||
        key == 'app.locale' ||
        key == 'referral.seen_earned' ||
        key == 'branch.switch.state' ||
        key == 'shop.promote.pending' ||
        key == 'vendor.config.json') {
      return true;
    }
    return key.startsWith('printer.') || key.startsWith('label_printer.');
  }

  AppDatabase _dbForKey(String key) =>
      isDeviceGlobalKey(key) ? _deviceDb : _db;

  static const _kPaperSize = 'printer.paper_size';
  static const _kPdfPaperSize = 'printer.pdf_paper_size';
  static const _kPrinterMac = 'printer.mac';
  static const _kPrinterName = 'printer.name';
  static const _kLabelSize = 'label_printer.size';
  static const _kLabelMac = 'label_printer.mac';
  static const _kLabelName = 'label_printer.name';
  static const _kShopName = 'shop.name';
  static const _kShopAddress = 'shop.address';
  static const _kShopPhone = 'shop.phone';
  static const _kShopLogo = 'shop.logo_url';
  static const _kReceiptFooter = 'receipt.footer';
  static const _kTrackStock = 'shop.track_stock';
  static const _kReferralSeenEarned = 'referral.seen_earned';
  static const _kStorefrontSeenOrderMs = 'storefront.seen_order_ms';
  static const _kBranchSwitchState = 'branch.switch.state';
  static const _kShopPromotePending = 'shop.promote.pending';
  static const _kStaffRole = 'staff.role';
  static const _kStaffPinHash = 'staff.pin_hash';
  static const _kStaffPin = 'staff.pin';
  static const _kStaffPinFailedAttempts = 'staff.pin_failed_attempts';
  static const _kStaffPinLockedUntil = 'staff.pin_locked_until';

  Future<String?> _get(String key) async {
    final db = _dbForKey(key);
    final row = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _set(String key, String value) {
    final db = _dbForKey(key);
    return db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion(key: Value(key), value: Value(value)),
        );
  }

  Future<void> _delete(String key) {
    final db = _dbForKey(key);
    return (db.delete(db.appSettings)..where((s) => s.key.equals(key))).go();
  }

  /// Composes a per-shop settings key. An empty [shopId] (the
  /// [shopIdProvider] default before any license/shop has ever been
  /// assigned — e.g. mid-onboarding) maps back to the bare, un-suffixed
  /// legacy key on purpose, so an existing single-shop install's data
  /// (saved before multi-shop/branch support existed) keeps resolving to
  /// the same key with no migration needed.
  String _shopKey(String base, String shopId) =>
      shopId.isEmpty ? base : '$base.$shopId';

  Future<String?> _getShopScoped(
    String baseKey,
    String shopId, {
    bool fallbackToLegacy = true,
  }) async {
    final scoped = await _get(_shopKey(baseKey, shopId));
    if (scoped != null) return scoped;
    if (!fallbackToLegacy || shopId.isEmpty) return null;
    return _get(baseKey);
  }

  /// Per-printer key (`printer.paper_size.<mac>`) — already routes through
  /// the device sidecar via [isDeviceGlobalKey]'s `printer.` prefix check,
  /// no changes needed there. A shop with two receipt printers of different
  /// widths (e.g. swapping a spare in) no longer has to re-pick paper size
  /// by hand every time it reconnects the other one.
  String _paperSizeKeyForMac(String mac) => '$_kPaperSize.$mac';

  PaperSize _resolvePaperSize(Map<String, String> map, String? mac) {
    final scoped = mac == null ? null : map[_paperSizeKeyForMac(mac)];
    final raw = scoped ?? map[_kPaperSize];
    return raw == 'mm80' ? PaperSize.mm80 : PaperSize.mm58;
  }

  Stream<PrinterConfig> watchPrinterConfig() {
    return _deviceDb.select(_deviceDb.appSettings).watch().map((rows) {
      final map = {for (final r in rows) r.key: r.value};
      final mac = map[_kPrinterMac];
      return PrinterConfig(
        paper: _resolvePaperSize(map, mac),
        mac: mac,
        name: map[_kPrinterName],
        pdfPaperSize: map[_kPdfPaperSize] == 'a5'
            ? PdfPaperSize.a5
            : PdfPaperSize.a4,
      );
    });
  }

  Future<PrinterConfig> printerConfig() async {
    final mac = await _get(_kPrinterMac);
    final scoped = mac == null ? null : await _get(_paperSizeKeyForMac(mac));
    final raw = scoped ?? await _get(_kPaperSize);
    return PrinterConfig(
      paper: raw == 'mm80' ? PaperSize.mm80 : PaperSize.mm58,
      mac: mac,
      name: await _get(_kPrinterName),
      pdfPaperSize: (await _get(_kPdfPaperSize)) == 'a5'
          ? PdfPaperSize.a5
          : PdfPaperSize.a4,
    );
  }

  /// Sets the device-wide default paper size — used until a specific
  /// printer has its own remembered size (see [setPaperSizeForPrinter]).
  Future<void> setPaperSize(PaperSize size) =>
      _set(_kPaperSize, size == PaperSize.mm80 ? 'mm80' : 'mm58');

  /// Remembers [size] for this specific printer ([mac]), independent of the
  /// device-wide default — see [_resolvePaperSize].
  Future<void> setPaperSizeForPrinter(String mac, PaperSize size) =>
      _set(_paperSizeKeyForMac(mac), size == PaperSize.mm80 ? 'mm80' : 'mm58');

  /// Whether [mac] already has its own remembered paper size, vs. still
  /// falling back to the device-wide default — the printer settings screen
  /// uses this to decide whether a newly-paired printer needs the
  /// one-time "which paper size?" prompt.
  Future<bool> hasPaperSizeForPrinter(String mac) async =>
      (await _get(_paperSizeKeyForMac(mac))) != null;

  Future<void> setPdfPaperSize(PdfPaperSize size) =>
      _set(_kPdfPaperSize, size == PdfPaperSize.a5 ? 'a5' : 'a4');

  Future<void> setPrinter(String mac, String name) async {
    await _set(_kPrinterMac, mac);
    await _set(_kPrinterName, name);
  }

  // ---- Dedicated label printer (TSPL, separate device from the receipt
  // printer above) --------------------------------------------------------

  LabelSize _labelSizeFromKey(String? key) => LabelSize.values.firstWhere(
    (s) => s.name == key,
    orElse: () => LabelSize.mm40x30,
  );

  Stream<LabelPrinterConfig> watchLabelPrinterConfig() {
    return _deviceDb.select(_deviceDb.appSettings).watch().map((rows) {
      final map = {for (final r in rows) r.key: r.value};
      return LabelPrinterConfig(
        size: _labelSizeFromKey(map[_kLabelSize]),
        mac: map[_kLabelMac],
        name: map[_kLabelName],
      );
    });
  }

  Future<LabelPrinterConfig> labelPrinterConfig() async {
    return LabelPrinterConfig(
      size: _labelSizeFromKey(await _get(_kLabelSize)),
      mac: await _get(_kLabelMac),
      name: await _get(_kLabelName),
    );
  }

  Future<void> setLabelSize(LabelSize size) => _set(_kLabelSize, size.name);

  Future<void> setLabelPrinter(String mac, String name) async {
    await _set(_kLabelMac, mac);
    await _set(_kLabelName, name);
  }

  // ---- License cache + device identity ------------------------------------

  static const _kLicense = 'license.json';
  static const _kDeviceId = 'device.id';
  static const _kLocale = 'app.locale';
  /// Shop-scoped (via [_shopKey]) — unlike [_kLicense] itself, which is
  /// device-global, this must travel with a Free-plan shop's data if it's
  /// later promoted to a real one (`ShopDataTransitionService
  /// .promoteShopIdentity` rekeys every shop-scoped setting, not
  /// device-global ones).
  static const _kLicenseOfflineFallback = 'license.offline_fallback';

  /// Persisted UI language ('en' | 'my'); null until the user has chosen.
  Future<String?> savedLocale() => _get(_kLocale);
  Future<void> saveLocale(String code) => _set(_kLocale, code);

  /// Stable per-install device id (used for license binding + App Reference
  /// ID). Kept in the OS secure store (iOS Keychain / Android Keystore) so it
  /// **survives an app reinstall** — otherwise reinstalling would orphan the
  /// user's license behind the device binding. Falls back to the local DB when
  /// secure storage is unavailable (e.g. unit tests).
  Future<String> deviceId() async {
    // 1) Prefer the secure store.
    try {
      final secure = await _secure.read(key: _kDeviceId);
      if (secure != null && secure.isNotEmpty) return secure;
    } catch (_) {
      /* not available (tests) */
    }

    // 2) Migrate a legacy id from the local DB, or mint a new one.
    var id = await _get(_kDeviceId);
    id ??= const Uuid().v4();

    await _set(_kDeviceId, id); // keep a local copy for offline reads
    try {
      await _secure.write(key: _kDeviceId, value: id);
    } catch (_) {
      /* not available (tests) */
    }
    return id;
  }

  // ---- Staff role (device-local, not synced) -----------------------------
  // 'owner' (full access) or 'cashier' (restricted). Default owner: the shop
  // owner sets up the device, then hands it to staff in cashier mode.
  Future<String> staffRole(String shopId) async =>
      (await _getShopScoped(_kStaffRole, shopId)) ?? 'owner';
  Future<void> setStaffRole(String shopId, String role) =>
      _set(_shopKey(_kStaffRole, shopId), role);
  Stream<String> watchStaffRole(String shopId) {
    return _db.select(_db.appSettings).watch().map((rows) {
      final scopedKey = _shopKey(_kStaffRole, shopId);
      String? scoped;
      String? legacy;
      for (final r in rows) {
        if (r.key == scopedKey) scoped = r.value;
        if (r.key == _kStaffRole) legacy = r.value;
      }
      return scoped ?? legacy ?? 'owner';
    });
  }

  String _hashStaffPin(String pin) {
    final digest = sha256.convert(utf8.encode('owner-pin:$pin'));
    return 'v1:$digest';
  }

  /// The owner PIN hash (v1:sha256) required to leave staff mode.
  ///
  /// Legacy plaintext rows under [_kStaffPin] are auto-migrated on first read.
  Future<String?> staffPinHash(String shopId) async {
    final scopedHashKey = _shopKey(_kStaffPinHash, shopId);
    final scopedLegacyKey = _shopKey(_kStaffPin, shopId);
    final hashed = await _getShopScoped(_kStaffPinHash, shopId);
    if (hashed != null && hashed.isNotEmpty) return hashed;

    final legacyPlain = await _getShopScoped(_kStaffPin, shopId);
    if (legacyPlain == null || legacyPlain.isEmpty) return null;
    final migrated = _hashStaffPin(legacyPlain);
    await _set(scopedHashKey, migrated);
    await _delete(scopedLegacyKey);
    if (shopId.isNotEmpty) {
      await _delete(_kStaffPin);
    }
    return migrated;
  }

  Future<void> setStaffPin(String shopId, String pin) async {
    await _set(_shopKey(_kStaffPinHash, shopId), _hashStaffPin(pin));
    await _delete(_shopKey(_kStaffPin, shopId));
    if (shopId.isNotEmpty) {
      await _delete(_kStaffPin);
    }
  }

  Future<bool> verifyStaffPin(String shopId, String pin) async {
    final saved = await staffPinHash(shopId);
    if (saved == null || saved.isEmpty) return true;
    return saved == _hashStaffPin(pin);
  }

  Future<int> ownerPinFailedAttempts(String shopId) async {
    final raw = await _getShopScoped(_kStaffPinFailedAttempts, shopId);
    return int.tryParse(raw ?? '') ?? 0;
  }

  Future<void> setOwnerPinFailedAttempts(String shopId, int attempts) =>
      _set(_shopKey(_kStaffPinFailedAttempts, shopId), '$attempts');
  Future<void> clearOwnerPinFailedAttempts(String shopId) =>
      _delete(_shopKey(_kStaffPinFailedAttempts, shopId));

  Future<DateTime?> ownerPinLockedUntil(String shopId) async {
    final raw = await _getShopScoped(_kStaffPinLockedUntil, shopId);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setOwnerPinLockedUntil(String shopId, DateTime until) => _set(
    _shopKey(_kStaffPinLockedUntil, shopId),
    until.toUtc().toIso8601String(),
  );
  Future<void> clearOwnerPinLockedUntil(String shopId) =>
      _delete(_shopKey(_kStaffPinLockedUntil, shopId));

  /// Which staff-roster member (see `StaffMembers`) is currently "using" this
  /// device — device-local, not synced (the roster itself is shared across
  /// devices; who's holding this particular phone right now is per-device).
  /// Empty/null = no named staff selected (plain staff mode, pre-roster).
  static const _kActiveStaffId = 'staff.active_id';
  Future<String?> activeStaffId() async {
    final v = await _get(_kActiveStaffId);
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setActiveStaffId(String id) => _set(_kActiveStaffId, id);
  Stream<String?> watchActiveStaffId() {
    return _db.select(_db.appSettings).watch().map((rows) {
      for (final r in rows) {
        if (r.key == _kActiveStaffId) return r.value.isEmpty ? null : r.value;
      }
      return null;
    });
  }

  Future<String?> licenseJson() => _get(_kLicense);
  Future<void> setLicenseJson(String json) => _set(_kLicense, json);

  /// Cryptographically offline-verifiable fallback token (`MMPOS1.` format,
  /// see `OfflineLicense`) issued automatically alongside a normal online
  /// activation/signup — gives a Premium shop a safety net that outlives the
  /// 7-day online grace window if it loses connectivity, not just shops an
  /// admin happened to hand-fulfill one for. Refreshed on every successful
  /// online re-verify; read by `LicenseController._silentReverify`'s
  /// network-failure fallback path.
  Future<String?> licenseOfflineFallbackToken(String shopId) =>
      _get(_shopKey(_kLicenseOfflineFallback, shopId));
  Future<void> setLicenseOfflineFallbackToken(String shopId, String token) =>
      _set(_shopKey(_kLicenseOfflineFallback, shopId), token);

  // One free trial per install.
  static const _kTrialUsed = 'license.trial_used';
  Future<bool> trialUsed() async => (await _get(_kTrialUsed)) == 'true';
  Future<void> markTrialUsed() => _set(_kTrialUsed, 'true');

  // Whether the default Payment Accounts (KBZPay/WavePay/AYAPay/CBPay) have
  // already been seeded once **for this shop** — set-and-forget, so a shop
  // that later deletes all of them never has them silently reappear.
  // Keyed by shopId (not a single global flag): this device's AppSettings
  // rows survive a branch switch (`wipeSyncedData` only clears synced
  // *data*, never settings), so a bare global flag would permanently skip
  // seeding for every shop after the first one this device ever opened.
  Future<bool> paymentAccountsSeeded(String shopId) async =>
      (await _get('payment_accounts.seeded.$shopId')) == 'true';
  Future<void> setPaymentAccountsSeeded(String shopId) =>
      _set('payment_accounts.seeded.$shopId', 'true');

  // First-run onboarding (shop profile / license / owner-staff-mode intro),
  // shown once per install.
  static const _kOnboardingDone = 'onboarding.done';
  Future<bool> onboardingComplete() async =>
      (await _get(_kOnboardingDone)) == 'true';
  Future<void> markOnboardingComplete() => _set(_kOnboardingDone, 'true');

  /// Permanent Online vs Offline shell for this install. Chosen once at
  /// onboarding (or the one-time migrate screen) and never switched in-app.
  static const _kOperatingMode = 'operating.mode';
  static const _kOperatingModeConfirmed = 'operating.mode_confirmed';
  static const operatingModeOnline = 'online';
  static const operatingModeOffline = 'offline';

  Future<String?> operatingMode() => _get(_kOperatingMode);

  Future<void> setOperatingMode(String mode) {
    assert(
      mode == operatingModeOnline || mode == operatingModeOffline,
      'operating mode must be online|offline',
    );
    return _set(_kOperatingMode, mode);
  }

  Future<bool> operatingModeConfirmed() async =>
      (await _get(_kOperatingModeConfirmed)) == 'true';

  Future<void> confirmOperatingMode() =>
      _set(_kOperatingModeConfirmed, 'true');

  /// Online daily shop-entry gate: calendar day (local yyyy-MM-dd) when the
  /// account → role → branch → open/Skip flow last finished for [shopId].
  static const _kDailyGateYmd = 'daily.gate.ymd';
  static const _kDailyGateSkippedOpen = 'daily.gate.skipped_open';

  Future<String?> dailyGateYmd(String shopId) =>
      _get(_shopKey(_kDailyGateYmd, shopId));

  Future<void> setDailyGateYmd(String shopId, String ymd) =>
      _set(_shopKey(_kDailyGateYmd, shopId), ymd);

  Future<bool> dailyGateSkippedOpen(String shopId) async =>
      (await _get(_shopKey(_kDailyGateSkippedOpen, shopId))) == 'true';

  Future<void> setDailyGateSkippedOpen(String shopId, bool skipped) {
    final key = _shopKey(_kDailyGateSkippedOpen, shopId);
    return skipped ? _set(key, 'true') : _delete(key);
  }

  Future<void> markDailyGateComplete(
    String shopId, {
    required String ymd,
    required bool skippedOpen,
  }) async {
    await setDailyGateYmd(shopId, ymd);
    await setDailyGateSkippedOpen(shopId, skippedOpen);
  }

  /// Watermark of the referral commission total (Ks) already seen by the user.
  /// null = never checked, so the first check establishes a baseline silently
  /// (no notification for commissions earned before this feature shipped).
  Future<int?> referralSeenEarned() async {
    final v = await _get(_kReferralSeenEarned);
    return v == null ? null : int.tryParse(v);
  }

  Future<void> setReferralSeenEarned(int value) =>
      _set(_kReferralSeenEarned, '$value');

  /// Watermark of the newest storefront-channel order `createdAt` already
  /// notified for [shopId]. null = never checked (baseline silently).
  Future<int?> storefrontSeenOrderCreatedMs(String shopId) async {
    final v = await _get(_shopKey(_kStorefrontSeenOrderMs, shopId));
    return v == null ? null : int.tryParse(v);
  }

  Future<void> setStorefrontSeenOrderCreatedMs(String shopId, int ms) =>
      _set(_shopKey(_kStorefrontSeenOrderMs, shopId), '$ms');

  /// Persisted branch-switch recovery marker (feature/account scoped JSON).
  Future<String?> branchSwitchStateJson() => _get(_kBranchSwitchState);
  Future<void> setBranchSwitchStateJson(String json) =>
      _set(_kBranchSwitchState, json);
  Future<void> clearBranchSwitchState() => _delete(_kBranchSwitchState);

  /// Recovery marker for a Free-plan shop-identity promotion in progress,
  /// stored as `"<fromShopId>|<toShopId>"`. Written before
  /// `ShopDataTransitionService.promoteShopIdentity` starts, cleared only
  /// after the subsequent file rename succeeds — if still set on the next
  /// app launch, `resolvePendingShopPromotion` finishes the job (both steps
  /// are safe to blindly re-run; see `promoteShopIdentity`'s doc comment).
  Future<String?> pendingShopPromotion() => _get(_kShopPromotePending);
  Future<void> setPendingShopPromotion(String fromShopId, String toShopId) =>
      _set(_kShopPromotePending, '$fromShopId|$toShopId');
  Future<void> clearPendingShopPromotion() =>
      _delete(_kShopPromotePending);
  Stream<String?> watchBranchSwitchStateJson() {
    return _db.select(_db.appSettings).watch().map((rows) {
      for (final r in rows) {
        if (r.key == _kBranchSwitchState) return r.value;
      }
      return null;
    });
  }

  // Cached vendor config (payment accounts + support contact), refreshed from
  // the backend `app_config` table so it survives offline.
  static const _kVendorConfig = 'vendor.config.json';
  Future<String?> vendorConfigJson() => _get(_kVendorConfig);
  Future<void> setVendorConfigJson(String json) => _set(_kVendorConfig, json);
  Future<void> clearLicense() {
    return (_db.delete(
      _db.appSettings,
    )..where((s) => s.key.equals(_kLicense))).go();
  }

  // ---- Sync cursors (per-table high-water mark of pulled updated_at) -------

  Future<DateTime?> syncCursor(String table) async {
    final raw = await _get('sync.cursor.$table');
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setSyncCursor(String table, DateTime value) =>
      _set('sync.cursor.$table', value.toUtc().toIso8601String());

  /// Row ids already applied at the exact `updated_at` timestamp the cursor
  /// sits on. The pull filter is inclusive (`gte`, not `gt`) — because
  /// Drift's second-precision `DateTimeColumn` storage means two changes
  /// within the same second collide on `updated_at` — so the same
  /// boundary row can be re-fetched on the next pull. This set lets
  /// [SyncEngine] tell "already applied, skip" apart from "a new tie-partner
  /// landed at this same timestamp after the fact, apply it" instead of
  /// either silently dropping the latter (a strict `gt` would) or
  /// re-applying the former forever.
  Future<Set<String>> syncCursorTieIds(String table) async {
    final raw = await _get('sync.cursor.ids.$table');
    if (raw == null || raw.isEmpty) return {};
    return raw.split(',').toSet();
  }

  Future<void> setSyncCursorTieIds(String table, Set<String> ids) =>
      _set('sync.cursor.ids.$table', ids.join(','));

  /// Resets a table's pull cursor entirely, so the next sync re-fetches its
  /// FULL remote history from scratch (every mapper's own LWW / idempotent
  /// upsert logic makes this safe, if wasteful, to do broadly). Used after a
  /// backup restore: the restored snapshot may be older than the shop's
  /// current cloud state, and the cursor from before the restore would
  /// otherwise make the next pull skip any remote row not present in the
  /// backup file, permanently losing it locally.
  Future<void> clearSyncCursor(String table) async {
    await _delete('sync.cursor.$table');
    await _delete('sync.cursor.ids.$table');
  }

  /// The shop's profile (name/address/phone/logo/footer) for [shopId] —
  /// keyed per shop so a device that switches between a main shop and a
  /// branch (`BranchRepository.switchBranch`) never bleeds one shop's
  /// profile into the other. Falls back to the un-suffixed legacy key for
  /// any field this shop hasn't set yet (see [_shopKey]) — for the very
  /// first shop a device ever configures this transparently picks up its
  /// pre-multi-shop data; for a later-added shop it's a sensible shared
  /// default until that shop sets its own.
  Future<ShopProfile> shopProfile(String shopId) async {
    Future<String?> get(String base) async {
      final scoped = await _get(_shopKey(base, shopId));
      if (scoped != null) return scoped;
      if (shopId.isEmpty) return null; // already the legacy key itself
      return _get(base);
    }

    return ShopProfile(
      name: (await get(_kShopName)) ?? 'My Shop',
      address: await get(_kShopAddress),
      phone: await get(_kShopPhone),
      logoUrl: await get(_kShopLogo),
      footer: await get(_kReceiptFooter),
    );
  }

  /// A dedicated setter (rather than routing through [saveShopProfile]) since
  /// the logo is uploaded and saved the moment it's picked, independent of
  /// the rest of the profile form.
  Future<void> setShopLogoUrl(String shopId, String url) =>
      _set(_shopKey(_kShopLogo, shopId), url);

  /// Whether the shop tracks inventory. When false the app runs "invoice
  /// only": no stock badges/alerts, no decrement on sale. Defaults to true.
  Future<bool> trackStock(String shopId) async {
    final scoped = await _get(_shopKey(_kTrackStock, shopId));
    if (scoped != null) return scoped != 'false';
    if (shopId.isEmpty) return true;
    final legacy = await _get(_kTrackStock);
    return legacy != 'false';
  }

  Future<void> setTrackStock(String shopId, bool value) =>
      _set(_shopKey(_kTrackStock, shopId), value ? 'true' : 'false');

  Stream<bool> watchTrackStock(String shopId) {
    final scopedKey = _shopKey(_kTrackStock, shopId);
    return _db.select(_db.appSettings).watch().map((rows) {
      for (final r in rows) {
        if (r.key == scopedKey) return r.value != 'false';
      }
      if (shopId.isNotEmpty) {
        for (final r in rows) {
          if (r.key == _kTrackStock) return r.value != 'false';
        }
      }
      return true;
    });
  }

  Future<void> saveShopProfile(String shopId, ShopProfile p) async {
    await _set(_shopKey(_kShopName, shopId), p.name);
    if (p.address != null) {
      await _set(_shopKey(_kShopAddress, shopId), p.address!);
    }
    if (p.phone != null) await _set(_shopKey(_kShopPhone, shopId), p.phone!);
    if (p.footer != null) {
      await _set(_shopKey(_kReceiptFooter, shopId), p.footer!);
    }
  }
}

class PrinterConfig {
  final PaperSize paper;
  final String? mac;
  final String? name;
  final PdfPaperSize pdfPaperSize;
  const PrinterConfig({
    required this.paper,
    this.mac,
    this.name,
    this.pdfPaperSize = PdfPaperSize.a4,
  });

  bool get hasPrinter => mac != null && mac!.isNotEmpty;
}

class LabelPrinterConfig {
  final LabelSize size;
  final String? mac;
  final String? name;
  const LabelPrinterConfig({required this.size, this.mac, this.name});

  bool get hasPrinter => mac != null && mac!.isNotEmpty;
}

class ShopProfile {
  final String name;
  final String? address;
  final String? phone;
  final String? logoUrl;
  final String? footer;
  const ShopProfile({
    required this.name,
    this.address,
    this.phone,
    this.logoUrl,
    this.footer,
  });
}
