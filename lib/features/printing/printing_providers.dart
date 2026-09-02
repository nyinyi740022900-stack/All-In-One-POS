import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/currency_def.dart';
import '../../core/providers.dart';
import '../../data/repositories/settings_repository.dart';
import '../../l10n/app_localizations.dart';
import '../invoices/receipt_formatter.dart';
import 'printer_service.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(
    ref.watch(databaseProvider),
    deviceDb: ref.watch(deviceDatabaseProvider),
  );
});

final printerServiceProvider = Provider<PrinterService>((ref) {
  return PrinterService();
});

final printerConfigProvider = StreamProvider<PrinterConfig>((ref) {
  return ref.watch(settingsRepositoryProvider).watchPrinterConfig();
});

final labelPrinterConfigProvider = StreamProvider<LabelPrinterConfig>((ref) {
  return ref.watch(settingsRepositoryProvider).watchLabelPrinterConfig();
});

final shopProfileProvider = FutureProvider<ShopProfile>((ref) {
  final shopId = ref.watch(shopIdProvider);
  return ref.watch(settingsRepositoryProvider).shopProfile(shopId);
});

/// The shop's current POS currency — the single lookup point every display
/// site formats money against. Fails closed to MMK while the profile is
/// still loading/erroring, same as `CurrencyDef.byCode(null)`.
final shopCurrencyProvider = Provider<CurrencyDef>((ref) {
  final profile = ref.watch(shopProfileProvider).valueOrNull;
  return CurrencyDef.byCode(profile?.currencyCode);
});

/// Whether the Shop Profile currency picker should be enabled — false once
/// the shop has any finalized sale (`SettingsRepository.currencyChangeAllowed`).
final currencyChangeAllowedProvider = FutureProvider<bool>((ref) {
  final shopId = ref.watch(shopIdProvider);
  return ref.watch(settingsRepositoryProvider).currencyChangeAllowed(shopId);
});

/// Whether the shop tracks inventory (true) or runs invoice-only (false).
final trackStockProvider = StreamProvider<bool>((ref) {
  final shopId = ref.watch(shopIdProvider);
  return ref.watch(settingsRepositoryProvider).watchTrackStock(shopId);
});

/// Stable per-install id, doubling as the user-facing App Reference ID / Shop
/// Code (globally unique — a v4 UUID). The admin extends a license by it.
final deviceIdProvider = FutureProvider<String>((ref) {
  return ref.watch(settingsRepositoryProvider).deviceId();
});

/// Builds localized receipt labels from the current localization.
ReceiptLabels receiptLabels(AppLocalizations l) => ReceiptLabels(
      invoice: l.receiptInvoice,
      date: l.receiptDate,
      cashier: l.receiptCashier,
      customer: l.receiptCustomer,
      phone: l.receiptPhone,
      deliveryAddress: l.orderDeliveryAddress,
      subtotal: l.sellSubtotal,
      discount: l.sellDiscount,
      total: l.commonTotal,
      payment: l.sellPaymentMethod,
      paid: l.sellAmountPaid,
      change: l.sellChange,
      amountDue: l.invoiceAmountDue,
    );
