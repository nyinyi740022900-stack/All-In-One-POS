import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../features/invoices/receipt_data.dart';
import '../../features/printing/label_data.dart';
import '../local/database.dart';

/// Device-scoped key/value settings (not synced). Backs printer config,
/// shop receipt header/footer, etc.
class SettingsRepository {
  SettingsRepository(this._db, {FlutterSecureStorage? secureStorage})
      : _secure = secureStorage ?? const FlutterSecureStorage();

  final AppDatabase _db;
  final FlutterSecureStorage _secure;

  static const _kPaperSize = 'printer.paper_size';
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
  static const _kStaffRole = 'staff.role';
  static const _kStaffPin = 'staff.pin';

  Future<String?> _get(String key) async {
    final row = await (_db.select(_db.appSettings)
          ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> _set(String key, String value) {
    return _db.into(_db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion(key: Value(key), value: Value(value)));
  }

  Stream<PrinterConfig> watchPrinterConfig() {
    return _db.select(_db.appSettings).watch().map((rows) {
      final map = {for (final r in rows) r.key: r.value};
      return PrinterConfig(
        paper: map[_kPaperSize] == 'mm80' ? PaperSize.mm80 : PaperSize.mm58,
        mac: map[_kPrinterMac],
        name: map[_kPrinterName],
      );
    });
  }

  Future<PrinterConfig> printerConfig() async {
    return PrinterConfig(
      paper: (await _get(_kPaperSize)) == 'mm80'
          ? PaperSize.mm80
          : PaperSize.mm58,
      mac: await _get(_kPrinterMac),
      name: await _get(_kPrinterName),
    );
  }

  Future<void> setPaperSize(PaperSize size) =>
      _set(_kPaperSize, size == PaperSize.mm80 ? 'mm80' : 'mm58');

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
    return _db.select(_db.appSettings).watch().map((rows) {
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
    } catch (_) {/* not available (tests) */}

    // 2) Migrate a legacy id from the local DB, or mint a new one.
    var id = await _get(_kDeviceId);
    id ??= const Uuid().v4();

    await _set(_kDeviceId, id); // keep a local copy for offline reads
    try {
      await _secure.write(key: _kDeviceId, value: id);
    } catch (_) {/* not available (tests) */}
    return id;
  }

  // ---- Staff role (device-local, not synced) -----------------------------
  // 'owner' (full access) or 'cashier' (restricted). Default owner: the shop
  // owner sets up the device, then hands it to staff in cashier mode.
  Future<String> staffRole() async => (await _get(_kStaffRole)) ?? 'owner';
  Future<void> setStaffRole(String role) => _set(_kStaffRole, role);
  Stream<String> watchStaffRole() {
    return _db.select(_db.appSettings).watch().map((rows) {
      for (final r in rows) {
        if (r.key == _kStaffRole) return r.value;
      }
      return 'owner';
    });
  }

  /// The owner PIN (4–6 digits) required to leave cashier mode. Null = unset.
  Future<String?> staffPin() => _get(_kStaffPin);
  Future<void> setStaffPin(String pin) => _set(_kStaffPin, pin);

  Future<String?> licenseJson() => _get(_kLicense);
  Future<void> setLicenseJson(String json) => _set(_kLicense, json);

  // One free trial per install.
  static const _kTrialUsed = 'license.trial_used';
  Future<bool> trialUsed() async => (await _get(_kTrialUsed)) == 'true';
  Future<void> markTrialUsed() => _set(_kTrialUsed, 'true');

  // First-run onboarding (shop profile / license / owner-staff-mode intro),
  // shown once per install.
  static const _kOnboardingDone = 'onboarding.done';
  Future<bool> onboardingComplete() async =>
      (await _get(_kOnboardingDone)) == 'true';
  Future<void> markOnboardingComplete() => _set(_kOnboardingDone, 'true');

  /// Watermark of the referral commission total (Ks) already seen by the user.
  /// null = never checked, so the first check establishes a baseline silently
  /// (no notification for commissions earned before this feature shipped).
  Future<int?> referralSeenEarned() async {
    final v = await _get(_kReferralSeenEarned);
    return v == null ? null : int.tryParse(v);
  }

  Future<void> setReferralSeenEarned(int value) =>
      _set(_kReferralSeenEarned, '$value');

  // Cached vendor config (payment accounts + support contact), refreshed from
  // the backend `app_config` table so it survives offline.
  static const _kVendorConfig = 'vendor.config.json';
  Future<String?> vendorConfigJson() => _get(_kVendorConfig);
  Future<void> setVendorConfigJson(String json) =>
      _set(_kVendorConfig, json);
  Future<void> clearLicense() {
    return (_db.delete(_db.appSettings)
          ..where((s) => s.key.equals(_kLicense)))
        .go();
  }

  // ---- Sync cursors (per-table high-water mark of pulled updated_at) -------

  Future<DateTime?> syncCursor(String table) async {
    final raw = await _get('sync.cursor.$table');
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setSyncCursor(String table, DateTime value) =>
      _set('sync.cursor.$table', value.toUtc().toIso8601String());

  Future<ShopProfile> shopProfile() async {
    return ShopProfile(
      name: (await _get(_kShopName)) ?? 'My Shop',
      address: await _get(_kShopAddress),
      phone: await _get(_kShopPhone),
      logoUrl: await _get(_kShopLogo),
      footer: await _get(_kReceiptFooter),
    );
  }

  /// A dedicated setter (rather than routing through [saveShopProfile]) since
  /// the logo is uploaded and saved the moment it's picked, independent of
  /// the rest of the profile form.
  Future<void> setShopLogoUrl(String url) => _set(_kShopLogo, url);

  /// Whether the shop tracks inventory. When false the app runs "invoice
  /// only": no stock badges/alerts, no decrement on sale. Defaults to true.
  Future<bool> trackStock() async => (await _get(_kTrackStock)) != 'false';

  Future<void> setTrackStock(bool value) =>
      _set(_kTrackStock, value ? 'true' : 'false');

  Stream<bool> watchTrackStock() => _watchBool(_kTrackStock, true);

  Stream<bool> _watchBool(String key, bool defaultValue) {
    return _db.select(_db.appSettings).watch().map((rows) {
      final row = rows.firstWhere(
        (r) => r.key == key,
        orElse: () =>
            AppSetting(key: key, value: defaultValue ? 'true' : 'false'),
      );
      return row.value != 'false';
    });
  }

  Future<void> saveShopProfile(ShopProfile p) async {
    await _set(_kShopName, p.name);
    if (p.address != null) await _set(_kShopAddress, p.address!);
    if (p.phone != null) await _set(_kShopPhone, p.phone!);
    if (p.footer != null) await _set(_kReceiptFooter, p.footer!);
  }
}

class PrinterConfig {
  final PaperSize paper;
  final String? mac;
  final String? name;
  const PrinterConfig({required this.paper, this.mac, this.name});

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
  const ShopProfile(
      {required this.name,
      this.address,
      this.phone,
      this.logoUrl,
      this.footer});
}
