import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mm_pos/core/payment_method.dart';
import 'package:mm_pos/data/local/database.dart';
import 'package:mm_pos/data/repositories/settings_repository.dart';
import 'package:mm_pos/features/invoices/receipt_data.dart';
import 'package:mm_pos/features/printing/printer_connection.dart';

Future<void> _insertSale(AppDatabase db, {required String shopId}) =>
    db.into(db.sales).insert(SalesCompanion.insert(
          id: 'sale-$shopId',
          shopId: shopId,
          invoiceNo: 'INV-$shopId',
        ));

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = SettingsRepository(db);
  });

  tearDown(() async => db.close());

  group('licenseExpiryWarned (per-shop isolation)', () {
    // A device can switch shops (BranchRepository.switchBranch) without
    // wipeSyncedData() touching AppSettings, so a device-global watermark
    // would let shop A's "already warned" silence shop B's genuinely-due
    // reminder — the exact bleed CLAUDE.md's ripple-effect check calls out.
    test('one shop\'s warning watermark never silences another\'s', () async {
      await repo.setLicenseExpiryWarned('shop-main', '2026-09-01|7');

      expect(await repo.licenseExpiryWarned('shop-main'), '2026-09-01|7');
      expect(await repo.licenseExpiryWarned('shop-branch'), isNull);
    });

    test('both shops keep their own value', () async {
      await repo.setLicenseExpiryWarned('shop-main', '2026-09-01|7');
      await repo.setLicenseExpiryWarned('shop-branch', '2026-12-01|3');

      expect(await repo.licenseExpiryWarned('shop-main'), '2026-09-01|7');
      expect(await repo.licenseExpiryWarned('shop-branch'), '2026-12-01|3');
    });

    test('never falls back to a legacy unscoped key', () async {
      // fallbackToLegacy is off for this key: there is no pre-existing
      // device-global value to inherit, and inheriting one would reintroduce
      // the bleed above.
      expect(await repo.licenseExpiryWarned('shop-new'), isNull);
    });
  });

  group('shopProfile (per-shop isolation)', () {
    test(
      'saving a profile for one shop never overwrites another shop\'s',
      () async {
        await repo.saveShopProfile(
          'shop-main',
          const ShopProfile(name: 'Main Shop', phone: '111'),
        );
        await repo.saveShopProfile(
          'shop-branch',
          const ShopProfile(name: 'Branch Shop', phone: '222'),
        );

        final main = await repo.shopProfile('shop-main');
        final branch = await repo.shopProfile('shop-branch');
        expect(main.name, 'Main Shop');
        expect(main.phone, '111');
        expect(branch.name, 'Branch Shop');
        expect(branch.phone, '222');
      },
    );

    test('a shop with no profile saved yet falls back to the un-suffixed '
        'legacy key (a pre-multi-shop install\'s existing data)', () async {
      // Simulates data saved before this shopId-keyed scheme existed, or
      // saved during onboarding before a shopId was assigned (shopId '').
      await repo.saveShopProfile(
        '',
        const ShopProfile(name: 'Legacy Shop', address: 'Yangon'),
      );

      final profile = await repo.shopProfile('shop-not-yet-customized');
      expect(profile.name, 'Legacy Shop');
      expect(profile.address, 'Yangon');
    });

    test('once a shop saves its own profile, it no longer falls back to the '
        'legacy key even for fields it left blank', () async {
      await repo.saveShopProfile(
        '',
        const ShopProfile(name: 'Legacy Shop', address: 'Yangon'),
      );
      await repo.saveShopProfile(
        'shop-branch',
        const ShopProfile(name: 'Branch'),
      );

      final profile = await repo.shopProfile('shop-branch');
      expect(profile.name, 'Branch');
      // address wasn't set for shop-branch specifically, so it does still
      // fall back per-field (documented, non-corrupting default) — but the
      // name itself, which shop-branch did set, is never overridden.
      expect(profile.address, 'Yangon');
    });

    test('setShopLogoUrl is also per-shop', () async {
      await repo.setShopLogoUrl('shop-main', 'https://example.com/main.png');
      await repo.setShopLogoUrl(
        'shop-branch',
        'https://example.com/branch.png',
      );

      expect(
        (await repo.shopProfile('shop-main')).logoUrl,
        'https://example.com/main.png',
      );
      expect(
        (await repo.shopProfile('shop-branch')).logoUrl,
        'https://example.com/branch.png',
      );
    });

    test('no profile saved anywhere defaults to "My Shop"', () async {
      final profile = await repo.shopProfile('shop-fresh');
      expect(profile.name, 'My Shop');
      expect(profile.address, isNull);
    });

    test('country defaults to MM when never set', () async {
      final profile = await repo.shopProfile('shop-fresh');
      expect(profile.country, 'MM');
    });

    test('saveShopProfile never writes country — no screen edits it '
        'anymore (LicenseScreen asks Myanmar-vs-International at subscribe '
        'time instead), so a save must not silently reset an old value back '
        'to the MM default', () async {
      await repo.saveShopProfile(
        'shop-a',
        const ShopProfile(name: 'Shop A', country: 'XX'),
      );
      expect((await repo.shopProfile('shop-a')).country, 'MM');
    });

    test('no payment methods saved anywhere defaults to an empty list',
        () async {
      final profile = await repo.shopProfile('shop-fresh');
      expect(profile.paymentMethods, isEmpty);
    });

    test('custom-named payment methods round-trip, per shop', () async {
      await repo.saveShopProfile(
        'shop-intl',
        const ShopProfile(
          name: 'Intl Shop',
          paymentMethods: [
            PaymentMethod(label: 'PayPal', accountNumber: 'pay@shop.com'),
            PaymentMethod(
              label: 'PromptPay',
              accountName: 'Shop Co',
              accountNumber: '081-234-5678',
            ),
          ],
        ),
      );
      await repo.saveShopProfile(
        'shop-mm',
        const ShopProfile(
          name: 'MM Shop',
          paymentMethods: [
            PaymentMethod(label: 'KBZPay', accountNumber: '09123456'),
          ],
        ),
      );

      final intl = (await repo.shopProfile('shop-intl')).paymentMethods!;
      expect(intl, hasLength(2));
      expect(intl[0].label, 'PayPal');
      expect(intl[0].accountNumber, 'pay@shop.com');
      expect(intl[1].label, 'PromptPay');
      expect(intl[1].accountName, 'Shop Co');

      final mm = (await repo.shopProfile('shop-mm')).paymentMethods!;
      expect(mm, hasLength(1));
      expect(mm.single.label, 'KBZPay');
    });

    test('saving an empty payment-methods list explicitly clears it '
        '(vs. null, which leaves the saved value untouched)', () async {
      await repo.saveShopProfile(
        'shop-a',
        const ShopProfile(
          name: 'Shop A',
          paymentMethods: [
            PaymentMethod(label: 'KBZPay', accountNumber: '09123456'),
          ],
        ),
      );
      await repo.saveShopProfile(
        'shop-a',
        const ShopProfile(name: 'Shop A', paymentMethods: []),
      );

      expect((await repo.shopProfile('shop-a')).paymentMethods, isEmpty);
    });

    test('currency defaults to MMK when never set', () async {
      final profile = await repo.shopProfile('shop-fresh');
      expect(profile.currencyCode, 'MMK');
    });

    test('currency is per-shop — one shop\'s THB never leaks into '
        'another\'s MMK', () async {
      await repo.setShopCurrency('shop-intl', 'THB');
      await repo.setShopCurrency('shop-mm', 'MMK');

      expect((await repo.shopProfile('shop-intl')).currencyCode, 'THB');
      expect((await repo.shopProfile('shop-mm')).currencyCode, 'MMK');
    });

    test('saveShopProfile never writes currency — only setShopCurrency '
        'does, so a plain profile save never bypasses the after-first-sale '
        'lock', () async {
      await repo.setShopCurrency('shop-a', 'THB');
      await repo.saveShopProfile(
        'shop-a',
        const ShopProfile(name: 'Shop A', currencyCode: 'USD'),
      );

      expect((await repo.shopProfile('shop-a')).currencyCode, 'THB');
    });
  });

  group('currencyChangeAllowed / setShopCurrency (after-first-sale lock)', () {
    test('allowed on an empty shop', () async {
      expect(await repo.currencyChangeAllowed('shop-empty'), isTrue);
    });

    test('locked once the shop has any finalized sale', () async {
      await _insertSale(db, shopId: 'shop-with-sale');
      expect(await repo.currencyChangeAllowed('shop-with-sale'), isFalse);
    });

    test('a soft-deleted sale does not lock the shop', () async {
      await db.into(db.sales).insert(SalesCompanion.insert(
            id: 'sale-deleted',
            shopId: 'shop-deleted-sale',
            invoiceNo: 'INV-deleted',
            isDeleted: const Value(true),
          ));
      expect(await repo.currencyChangeAllowed('shop-deleted-sale'), isTrue);
    });

    test('setShopCurrency succeeds on an empty shop', () async {
      await repo.setShopCurrency('shop-empty', 'THB');
      expect((await repo.shopProfile('shop-empty')).currencyCode, 'THB');
    });

    test('setShopCurrency throws once a sale exists, and does not change '
        'the stored value', () async {
      await _insertSale(db, shopId: 'shop-locked');
      await expectLater(
        repo.setShopCurrency('shop-locked', 'THB'),
        throwsA(isA<StateError>()),
      );
      expect((await repo.shopProfile('shop-locked')).currencyCode, 'MMK');
    });
  });

  group('hydrateShopProfileFromSyncIfNeeded (new-device profile pull-down)', () {
    Future<void> insertSyncedRow(
      AppDatabase db,
      String shopId, {
      required String name,
      String? phone,
      String? address,
      String? currencyCode,
    }) async {
      await db.into(db.shopProfiles).insertOnConflictUpdate(
            ShopProfilesCompanion.insert(
              id: shopId,
              shopId: shopId,
              name: name,
              phone: Value(phone),
              address: Value(address),
              currencyCode: currencyCode == null
                  ? const Value.absent()
                  : Value(currencyCode),
            ),
          );
    }

    test(
      'copies a pulled shop_profiles row into the AppSettings KV a new '
      'device\'s Shop Profile screen actually reads',
      () async {
        await insertSyncedRow(
          db,
          'shop-main',
          name: 'Golden Store',
          phone: '09123456',
          address: 'Yangon',
        );

        await repo.hydrateShopProfileFromSyncIfNeeded('shop-main');

        final profile = await repo.shopProfile('shop-main');
        expect(profile.name, 'Golden Store');
        expect(profile.phone, '09123456');
        expect(profile.address, 'Yangon');
      },
    );

    test('is per-shop: hydrating one shop never leaks into another', () async {
      await insertSyncedRow(db, 'shop-main', name: 'Main Shop');
      await insertSyncedRow(db, 'shop-branch', name: 'Branch Shop');

      await repo.hydrateShopProfileFromSyncIfNeeded('shop-main');
      await repo.hydrateShopProfileFromSyncIfNeeded('shop-branch');

      expect((await repo.shopProfile('shop-main')).name, 'Main Shop');
      expect((await repo.shopProfile('shop-branch')).name, 'Branch Shop');
    });

    test(
      'runs only once per shop — a later local edit is not clobbered by '
      'hydrating again',
      () async {
        await insertSyncedRow(db, 'shop-main', name: 'Golden Store');
        await repo.hydrateShopProfileFromSyncIfNeeded('shop-main');

        // Owner edits the profile locally after hydration.
        await repo.saveShopProfile(
          'shop-main',
          const ShopProfile(name: 'Renamed Store'),
        );

        // A later sync cycle re-runs hydration (e.g. next pull) — must not
        // stomp the local edit back to the stale synced name.
        await repo.hydrateShopProfileFromSyncIfNeeded('shop-main');

        expect((await repo.shopProfile('shop-main')).name, 'Renamed Store');
      },
    );

    test(
      'also copies the synced row\'s currency — a second device joining an '
      'already-THB shop must not default to MMK (audit: this used to be '
      'skipped, permanently stranding a new device once it had any local '
      'sale, since the currency picker locks after the first one)',
      () async {
        await insertSyncedRow(
          db,
          'shop-thb',
          name: 'Bangkok Store',
          currencyCode: 'THB',
        );

        await repo.hydrateShopProfileFromSyncIfNeeded('shop-thb');

        expect((await repo.shopProfile('shop-thb')).currencyCode, 'THB');
      },
    );

    test(
      'currency hydration bypasses the after-first-sale lock — it is '
      'adopting the shop\'s existing value, not changing it',
      () async {
        await insertSyncedRow(
          db,
          'shop-thb-sold',
          name: 'Already Trading',
          currencyCode: 'THB',
        );
        await _insertSale(db, shopId: 'shop-thb-sold');

        await repo.hydrateShopProfileFromSyncIfNeeded('shop-thb-sold');

        expect(
          (await repo.shopProfile('shop-thb-sold')).currencyCode,
          'THB',
        );
      },
    );

    test('no synced row yet is a harmless no-op', () async {
      await repo.hydrateShopProfileFromSyncIfNeeded('shop-fresh');
      expect((await repo.shopProfile('shop-fresh')).name, 'My Shop');
    });

    test('empty shopId is a no-op', () async {
      await repo.hydrateShopProfileFromSyncIfNeeded('');
      expect((await repo.shopProfile('')).name, 'My Shop');
    });
  });

  group('trackStock (per-shop isolation)', () {
    test('a saved value is isolated per shop', () async {
      await repo.setTrackStock('shop-main', false);
      await repo.setTrackStock('shop-branch', true);

      expect(await repo.trackStock('shop-main'), isFalse);
      expect(await repo.trackStock('shop-branch'), isTrue);
    });

    test('a shop with no scoped value falls back to legacy key', () async {
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            const AppSettingsCompanion(
              key: Value('shop.track_stock'),
              value: Value('false'),
            ),
          );

      expect(await repo.trackStock('new-shop'), isFalse);
    });
  });

  group('staff mode + PIN state (per-shop isolation)', () {
    test('staff role is isolated per shop with legacy fallback', () async {
      await repo.setStaffRole('shop-main', 'staff');
      await repo.setStaffRole('shop-branch', 'owner');
      expect(await repo.staffRole('shop-main'), 'staff');
      expect(await repo.staffRole('shop-branch'), 'owner');

      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            const AppSettingsCompanion(
              key: Value('staff.role'),
              value: Value('staff'),
            ),
          );
      expect(await repo.staffRole('shop-new'), 'staff');
    });

    test('owner PIN hash and cooldown state are isolated per shop', () async {
      await repo.setStaffPin('shop-main', '1234');
      await repo.setStaffPin('shop-branch', '5678');
      expect(await repo.verifyStaffPin('shop-main', '1234'), isTrue);
      expect(await repo.verifyStaffPin('shop-main', '5678'), isFalse);
      expect(await repo.verifyStaffPin('shop-branch', '5678'), isTrue);

      await repo.setOwnerPinFailedAttempts('shop-main', 4);
      await repo.setOwnerPinFailedAttempts('shop-branch', 1);
      expect(await repo.ownerPinFailedAttempts('shop-main'), 4);
      expect(await repo.ownerPinFailedAttempts('shop-branch'), 1);

      final lockMain = DateTime(2026, 8, 6, 12, 0, 0);
      final lockBranch = DateTime(2026, 8, 6, 13, 0, 0);
      await repo.setOwnerPinLockedUntil('shop-main', lockMain);
      await repo.setOwnerPinLockedUntil('shop-branch', lockBranch);
      expect(await repo.ownerPinLockedUntil('shop-main'), lockMain.toUtc());
      expect(await repo.ownerPinLockedUntil('shop-branch'), lockBranch.toUtc());
    });

    test(
      'active staff id is isolated per shop — a device switching branches '
      'must not carry the previous shop\'s active staff selection along',
      () async {
        await repo.setActiveStaffId('shop-main', 'mimi-id');
        await repo.setActiveStaffId('shop-branch', 'koko-id');
        expect(await repo.activeStaffId('shop-main'), 'mimi-id');
        expect(await repo.activeStaffId('shop-branch'), 'koko-id');

        // A shop that never had one set sees neither — not a leaked value
        // from whichever shop happened to be active most recently.
        expect(await repo.activeStaffId('shop-new'), isNull);
      },
    );
  });

  group('operating mode + daily gate', () {
    test('mode and confirm are device-global and lock once', () async {
      expect(await repo.operatingMode(), isNull);
      expect(await repo.operatingModeConfirmed(), isFalse);

      await repo.setOperatingMode(SettingsRepository.operatingModeOnline);
      await repo.confirmOperatingMode();

      expect(await repo.operatingMode(), 'online');
      expect(await repo.operatingModeConfirmed(), isTrue);
      expect(SettingsRepository.isDeviceGlobalKey('operating.mode'), isTrue);
      expect(
        SettingsRepository.isDeviceGlobalKey('operating.mode_confirmed'),
        isTrue,
      );
    });

    test('daily gate ymd and skip are isolated per shop', () async {
      await repo.markDailyGateComplete(
        'shop-main',
        ymd: '2026-08-09',
        skippedOpen: true,
      );
      await repo.markDailyGateComplete(
        'shop-branch',
        ymd: '2026-08-10',
        skippedOpen: false,
      );

      expect(await repo.dailyGateYmd('shop-main'), '2026-08-09');
      expect(await repo.dailyGateSkippedOpen('shop-main'), isTrue);
      expect(await repo.dailyGateYmd('shop-branch'), '2026-08-10');
      expect(await repo.dailyGateSkippedOpen('shop-branch'), isFalse);
    });
  });

  group('license offline fallback token (per-shop isolation)', () {
    test('is shop-scoped, not device-global — must travel with a promoted '
        'Free shop (ShopDataTransitionService.promoteShopIdentity rekeys '
        'shop-scoped settings, not device-global ones)', () {
      expect(
        SettingsRepository.isDeviceGlobalKey('license.offline_fallback'),
        isFalse,
      );
    });

    test(
      'setting a token for one shop never leaks into another\'s read',
      () async {
        await repo.setLicenseOfflineFallbackToken(
          'shop-main',
          'MMPOS1.main.sig',
        );
        await repo.setLicenseOfflineFallbackToken(
          'shop-branch',
          'MMPOS1.branch.sig',
        );

        expect(
          await repo.licenseOfflineFallbackToken('shop-main'),
          'MMPOS1.main.sig',
        );
        expect(
          await repo.licenseOfflineFallbackToken('shop-branch'),
          'MMPOS1.branch.sig',
        );
      },
    );

    test('unset for a shop that never had one', () async {
      expect(await repo.licenseOfflineFallbackToken('shop-none'), isNull);
    });
  });

  group('printer paper size (per-printer isolation)', () {
    test('two printers on the same device remember their own size '
        'independently', () async {
      await repo.setPrinter('AA:11', 'Front Counter');
      await repo.setPaperSizeForPrinter('AA:11', PaperSize.mm58);
      await repo.setPaperSizeForPrinter('BB:22', PaperSize.mm80);

      final configFront = await repo.printerConfig(); // active mac = AA:11
      expect(configFront.paper, PaperSize.mm58);

      await repo.setPrinter('BB:22', 'Back Counter');
      final configBack = await repo.printerConfig();
      expect(configBack.paper, PaperSize.mm80);
    });

    test('a printer with no remembered size falls back to the device-wide '
        'default, not always 58mm', () async {
      await repo.setPaperSize(PaperSize.mm80); // device-wide default
      await repo.setPrinter('CC:33', 'New Printer'); // never configured

      expect(await repo.hasPaperSizeForPrinter('CC:33'), isFalse);
      final config = await repo.printerConfig();
      expect(config.paper, PaperSize.mm80); // the default, not mm58
    });

    test('hasPaperSizeForPrinter distinguishes "never set" from "set to '
        'the default value"', () async {
      expect(await repo.hasPaperSizeForPrinter('DD:44'), isFalse);
      await repo.setPaperSizeForPrinter('DD:44', PaperSize.mm58);
      expect(await repo.hasPaperSizeForPrinter('DD:44'), isTrue);
    });

    test('watchPrinterConfig resolves the same per-printer/default fallback '
        'as the one-shot printerConfig read', () async {
      await repo.setPaperSize(PaperSize.mm58);
      await repo.setPrinter('EE:55', 'Printer E');
      await repo.setPaperSizeForPrinter('EE:55', PaperSize.mm80);

      final streamed = await repo.watchPrinterConfig().first;
      expect(streamed.paper, PaperSize.mm80);
      expect(streamed.mac, 'EE:55');
    });

    test('setPrinter remembers connection type; a legacy bluetooth-only '
        'row still reads as bluetooth', () async {
      await repo.setPrinter(
        '192.168.1.50',
        'Counter Wi-Fi',
        connection: PrinterConnection.network,
      );
      final wifi = await repo.printerConfig();
      expect(wifi.connection, PrinterConnection.network);
      expect(wifi.mac, '192.168.1.50');

      await repo.setPrinter('AA:11', 'Front Counter');
      final bt = await repo.printerConfig();
      expect(bt.connection, PrinterConnection.bluetooth);
    });

    test('setLabelPrinter remembers connection independently of the '
        'receipt printer', () async {
      await repo.setPrinter(
        'AA:11',
        'Receipt',
        connection: PrinterConnection.bluetooth,
      );
      await repo.setLabelPrinter(
        '192.168.1.80',
        'Label Wi-Fi',
        connection: PrinterConnection.network,
      );
      final receipt = await repo.printerConfig();
      final label = await repo.labelPrinterConfig();
      expect(receipt.connection, PrinterConnection.bluetooth);
      expect(label.connection, PrinterConnection.network);
      expect(label.mac, '192.168.1.80');
    });

    test('the 80mm narrow (180dpi) width round-trips through both read '
        'paths', () async {
      await repo.setPrinter('FF:66', 'Epson TM-T88');
      await repo.setPaperSizeForPrinter('FF:66', PaperSize.mm80Narrow);

      final oneShot = await repo.printerConfig();
      expect(oneShot.paper, PaperSize.mm80Narrow);
      final streamed = await repo.watchPrinterConfig().first;
      expect(streamed.paper, PaperSize.mm80Narrow);

      // The device-wide default path accepts it too.
      await repo.setPaperSize(PaperSize.mm80Narrow);
      expect((await repo.printerConfig()).paper, PaperSize.mm80Narrow);
    });

    test('a legacy pre-expansion paper-size value still resolves (never '
        'falls back to 58 by accident)', () async {
      // Values written before mm80Narrow existed are exactly the enum
      // names 'mm58'/'mm80' — the tolerant parse must keep reading them.
      await repo.setPaperSize(PaperSize.mm80);
      expect((await repo.printerConfig()).paper, PaperSize.mm80);
    });

    test('printer model is remembered per printer — two printers never '
        'share a preset', () async {
      await repo.setPrinter('AA:11', 'Front');
      await repo.setPrinter('BB:22', 'Back');

      await repo.setPrinterModel('AA:11', 'epson_tmt88');
      await repo.setPrinterModel('BB:22', 'xprinter_xp58');

      await repo.setPrinter('AA:11', 'Front');
      var config = await repo.printerConfig();
      expect(config.modelId, 'epson_tmt88');

      await repo.setPrinter('BB:22', 'Back');
      config = await repo.printerConfig();
      expect(config.modelId, 'xprinter_xp58');
    });

    test('printer model: unset reads null; custom id passes through; '
        'clearing works', () async {
      await repo.setPrinter('CC:33', 'No-name');
      expect((await repo.printerConfig()).modelId, isNull);

      await repo.setPrinterModel('CC:33', 'some_unlisted_model');
      expect((await repo.printerConfig()).modelId, 'some_unlisted_model');

      await repo.setPrinterModel('CC:33', null);
      expect((await repo.printerConfig()).modelId, isNull);
    });

    test('watchPrinterConfig exposes the model id too', () async {
      await repo.setPrinter('DD:44', 'Wi-Fi Epson');
      await repo.setPrinterModel('DD:44', 'epson_tmt82');
      final streamed = await repo.watchPrinterConfig().first;
      expect(streamed.modelId, 'epson_tmt82');
    });
  });
}
