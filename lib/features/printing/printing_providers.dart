import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/repositories/settings_repository.dart';
import '../../l10n/app_localizations.dart';
import '../invoices/receipt_formatter.dart';
import 'printer_service.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(databaseProvider));
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

/// Whether the shop tracks inventory (true) or runs invoice-only (false).
final trackStockProvider = StreamProvider<bool>((ref) {
  return ref.watch(settingsRepositoryProvider).watchTrackStock();
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
    );
