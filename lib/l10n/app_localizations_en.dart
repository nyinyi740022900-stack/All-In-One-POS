// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'MM POS';

  @override
  String get navSell => 'Sell';

  @override
  String get navInventory => 'Inventory';

  @override
  String get navInvoices => 'Invoices';

  @override
  String get navAnalytics => 'Analytics';

  @override
  String get navSettings => 'Settings';

  @override
  String get commonSave => 'Save';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonOk => 'OK';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonYes => 'Yes';

  @override
  String get commonNo => 'No';

  @override
  String get commonTotal => 'Total';

  @override
  String get commonCopy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get sellTitle => 'Sell';

  @override
  String sellStockCap(int count) {
    return 'Only $count in stock';
  }

  @override
  String get sellCart => 'Cart';

  @override
  String get sellEmptyCart => 'No items yet. Tap a product to add.';

  @override
  String get sellCheckout => 'Checkout';

  @override
  String get sellSubtotal => 'Subtotal';

  @override
  String get sellDiscount => 'Discount';

  @override
  String get sellPaymentMethod => 'Payment method';

  @override
  String get sellAmountPaid => 'Amount paid';

  @override
  String get sellChange => 'Change';

  @override
  String get sellConfirm => 'Confirm sale';

  @override
  String get sellClear => 'Clear';

  @override
  String get scanBarcode => 'Scan barcode';

  @override
  String get scanTorch => 'Flash';

  @override
  String get scanFlip => 'Flip camera';

  @override
  String get scanHint => 'Point the camera at a barcode';

  @override
  String scanAdded(String name) {
    return 'Added $name';
  }

  @override
  String scanNotFound(String code) {
    return 'No product for barcode $code';
  }

  @override
  String get sellCompleted => 'Sale completed';

  @override
  String get sellInsufficientPaid => 'Amount paid is less than total.';

  @override
  String get paymentCash => 'Cash';

  @override
  String get paymentKbzPay => 'KBZPay';

  @override
  String get paymentWavePay => 'WavePay';

  @override
  String get paymentAyaPay => 'AYAPay';

  @override
  String get paymentCbPay => 'CBPay';

  @override
  String get paymentCredit => 'Credit';

  @override
  String get creditTitle => 'Credit book';

  @override
  String get creditCustomerName => 'Customer name';

  @override
  String get customerPhone => 'Phone (optional)';

  @override
  String get checkoutAddCustomer => 'Add customer';

  @override
  String checkoutTierPricingApplied(String tier) {
    return '$tier pricing applied to this sale';
  }

  @override
  String get creditCustomerRequired =>
      'Enter a customer name for a credit sale.';

  @override
  String get creditPaidNow => 'Paid now (optional)';

  @override
  String get creditOwed => 'Owed';

  @override
  String get creditTotalOutstanding => 'Total outstanding';

  @override
  String creditTotalDue(String amount) {
    return '$amount outstanding';
  }

  @override
  String get creditNoneDue => 'No outstanding credit';

  @override
  String get creditEmpty => 'No one owes you right now.';

  @override
  String creditOpenInvoices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'invoices',
      one: 'invoice',
    );
    return '$count open $_temp0';
  }

  @override
  String get creditOutstanding => 'Outstanding';

  @override
  String get creditInvoices => 'Credit invoices';

  @override
  String get creditSettled => 'Settled';

  @override
  String get creditRepayments => 'Repayments';

  @override
  String get creditRecordRepayment => 'Record repayment';

  @override
  String get creditAmount => 'Amount';

  @override
  String get creditRepaymentSaved => 'Repayment recorded';

  @override
  String get customersTitle => 'Customers';

  @override
  String get customersEmpty => 'No customers yet. Add your first customer.';

  @override
  String get customersSearchHint => 'Search name or phone';

  @override
  String get customerAdd => 'Add customer';

  @override
  String get customerEdit => 'Edit customer';

  @override
  String get customerNameLabel => 'Name';

  @override
  String get customerAddress => 'Address';

  @override
  String get customerTierLabel => 'Pricing tier';

  @override
  String get customerTierRetail => 'Retail';

  @override
  String get customerTierWholesale => 'Wholesale';

  @override
  String get customerTierVip => 'VIP';

  @override
  String get customerSaved => 'Customer saved';

  @override
  String get customerDeleteConfirmTitle => 'Remove this customer?';

  @override
  String customerDeleteConfirmBody(String name) {
    return '$name will no longer appear as a suggestion at checkout. Past invoices still show their name.';
  }

  @override
  String get customerDeleted => 'Customer removed';

  @override
  String get inventoryTitle => 'Inventory';

  @override
  String get inventoryEmpty => 'No products yet. Add your first product.';

  @override
  String get inventoryLowStock => 'Low stock';

  @override
  String get inventoryAddProduct => 'Add product';

  @override
  String get inventoryEditProduct => 'Edit product';

  @override
  String get inventoryNoResults => 'No products match your search.';

  @override
  String get productName => 'Product name';

  @override
  String get productPhoto => 'Product photo';

  @override
  String get productPrice => 'Sale price';

  @override
  String get productCost => 'Cost price';

  @override
  String get productTierPricesHint =>
      'Optional — leave blank to use the sale price for that tier.';

  @override
  String get productWholesalePrice => 'Wholesale price';

  @override
  String get productVipPrice => 'VIP price';

  @override
  String get productBarcode => 'Barcode';

  @override
  String get productSku => 'SKU';

  @override
  String get productStock => 'Stock';

  @override
  String get productQuantity => 'Quantity';

  @override
  String get productReorderLevel => 'Reorder level';

  @override
  String get productUnit => 'Unit';

  @override
  String get inventoryUpdateStock => 'Update stock';

  @override
  String get stockAdjustTitle => 'Update stock';

  @override
  String get stockAdjustModeRestock => 'Restock';

  @override
  String get stockAdjustModeAdjust => 'Adjust';

  @override
  String get stockAdjustQuantity => 'Quantity';

  @override
  String get stockAdjustQuantityHintRestock => 'Units received';

  @override
  String get stockAdjustQuantityHintAdjust => '+ to increase, − to decrease';

  @override
  String get stockAdjustReason => 'Reason';

  @override
  String get stockAdjustNote => 'Note (optional)';

  @override
  String get stockAdjustSave => 'Save';

  @override
  String get stockAdjustInvalid => 'Enter a valid quantity';

  @override
  String stockAdjustCurrentStock(int quantity) {
    return 'Current stock: $quantity';
  }

  @override
  String get stockReasonDamaged => 'Damaged';

  @override
  String get stockReasonLost => 'Lost / stolen';

  @override
  String get stockReasonCount => 'Stock count correction';

  @override
  String get stockReasonOther => 'Other';

  @override
  String get stockHistoryTitle => 'Stock history';

  @override
  String get stockHistoryEmpty => 'No stock movements yet.';

  @override
  String get stockMovementOpening => 'Opening balance';

  @override
  String get stockMovementSale => 'Sale';

  @override
  String get stockMovementReturn => 'Refund return';

  @override
  String get stockMovementPurchase => 'Restock';

  @override
  String get stockMovementAdjustment => 'Adjustment';

  @override
  String get productViewStockHistory => 'View stock history';

  @override
  String get validationRequired => 'Required';

  @override
  String get deleteConfirmTitle => 'Delete?';

  @override
  String get deleteConfirmBody => 'This item will be removed.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionBusiness => 'Business';

  @override
  String get settingsSectionFinance => 'Finance';

  @override
  String get settingsSectionDevice => 'Device & Staff';

  @override
  String get settingsSectionHelp => 'Help';

  @override
  String get settingsSectionOwnerTools => 'Owner Tools';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsPrinter => 'Printer';

  @override
  String get settingsShop => 'Shop profile';

  @override
  String get settingsLicense => 'License';

  @override
  String get settingsSupport => 'Support';

  @override
  String get settingsTrackStock => 'Track stock';

  @override
  String get settingsTrackStockHint =>
      'Off = invoice only (no stock counts or alerts).';

  @override
  String get settingsAskCustomer => 'Ask for customer';

  @override
  String get settingsAskCustomerHint =>
      'Show optional customer name + phone at checkout.';

  @override
  String get shopProfileHint => 'Shown on printed receipts.';

  @override
  String get shopLogo => 'Shop logo';

  @override
  String get shopName => 'Shop name';

  @override
  String get shopAddress => 'Address';

  @override
  String get shopPhone => 'Phone';

  @override
  String get receiptFooter => 'Receipt footer';

  @override
  String get shopProfileSaved => 'Shop profile saved';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageMyanmar => 'Myanmar';

  @override
  String get invoicesEmpty => 'No sales yet.';

  @override
  String get invoiceFilterAll => 'All';

  @override
  String get invoiceFilterCredit => 'Credit';

  @override
  String invoiceOwed(String amount) {
    return 'Owed $amount';
  }

  @override
  String get invoicePrint => 'Print';

  @override
  String get invoiceReprint => 'Reprint';

  @override
  String get invoiceDetail => 'Invoice';

  @override
  String get invoiceSearchHint => 'Search invoice #, customer, phone';

  @override
  String get invoiceScanToSearch => 'Scan barcode';

  @override
  String get invoiceRefund => 'Refund';

  @override
  String get invoiceRefunded => 'Refunded';

  @override
  String get invoiceRefundConfirmTitle => 'Refund this invoice?';

  @override
  String get invoiceRefundConfirmBody =>
      'This reverses the sale, restores stock, and cannot be undone.';

  @override
  String invoiceRefundOf(String invoiceNo) {
    return 'Refund of $invoiceNo';
  }

  @override
  String invoiceRefundSuccess(String refundNo) {
    return 'Refunded ($refundNo).';
  }

  @override
  String get invoiceAlreadyRefunded => 'This invoice was already refunded.';

  @override
  String get printerSettings => 'Printer settings';

  @override
  String get printerSelectDevice => 'Select printer';

  @override
  String get printerPaperSize => 'Paper size';

  @override
  String get printerTestPrint => 'Test print';

  @override
  String get printerNone => 'No printer selected';

  @override
  String get printerPaired => 'Paired devices';

  @override
  String get printSuccess => 'Printed successfully';

  @override
  String get printFailed => 'Print failed';

  @override
  String get bluetoothOff =>
      'Bluetooth is off. Turn it on and pair your printer.';

  @override
  String get receiptInvoice => 'Invoice';

  @override
  String get receiptDate => 'Date';

  @override
  String get receiptCashier => 'Cashier';

  @override
  String get receiptCustomer => 'Customer';

  @override
  String get receiptPhone => 'Phone';

  @override
  String get receiptThankYou => 'Thank you for your patronage!';

  @override
  String get paper58 => '58 mm';

  @override
  String get paper80 => '80 mm';

  @override
  String get settingsLabelPrinter => 'Label printer';

  @override
  String get labelPrinterSettings => 'Label printer settings';

  @override
  String get labelPrinterSize => 'Label size';

  @override
  String get labelSize40x30 => '40 x 30 mm';

  @override
  String get labelSize50x30 => '50 x 30 mm';

  @override
  String get labelSize50x40 => '50 x 40 mm';

  @override
  String get inventoryPrintLabel => 'Print label';

  @override
  String get labelPrintDialogTitle => 'Print label';

  @override
  String get labelCopies => 'Copies';

  @override
  String get labelPrintTargetStrip =>
      'Prints as a strip on the receipt printer';

  @override
  String get labelPrintTargetDedicated => 'Prints on the label printer';

  @override
  String get labelPrintNoTarget =>
      'No printer connected. Set one up in Settings.';

  @override
  String get categoriesTitle => 'Categories';

  @override
  String get manageCategories => 'Manage categories';

  @override
  String get categoryAdd => 'Add category';

  @override
  String get categoryEdit => 'Edit category';

  @override
  String get categoryName => 'Category name';

  @override
  String get categoryNone => 'Uncategorized';

  @override
  String get categoryAll => 'All';

  @override
  String get categoriesEmpty => 'No categories yet.';

  @override
  String get productCategory => 'Category';

  @override
  String get analyticsRevenue => 'Revenue';

  @override
  String get analyticsProfit => 'Profit';

  @override
  String get analyticsSalesCount => 'Sales';

  @override
  String get analyticsStockValue => 'Stock value';

  @override
  String get analyticsDiscountGiven => 'Discounts';

  @override
  String get analyticsTopProducts => 'Top products';

  @override
  String get analyticsRangeToday => 'Today';

  @override
  String get analyticsRangeWeek => '7 days';

  @override
  String get analyticsRangeMonth => '30 days';

  @override
  String get analyticsNoData => 'No sales in this period.';

  @override
  String get analyticsDailyRevenue => 'Daily revenue';

  @override
  String get analyticsCollected => 'Collected';

  @override
  String get analyticsCreditOutstanding => 'Credit outstanding';

  @override
  String get licenseActivateTitle => 'Activate license';

  @override
  String get licenseKeyLabel => 'License key';

  @override
  String get licenseActivateBtn => 'Activate';

  @override
  String get licenseStatusActive => 'Active';

  @override
  String get licenseStatusGrace => 'Grace period';

  @override
  String get licenseStatusExpired => 'Expired';

  @override
  String get licenseStatusNone => 'Not activated';

  @override
  String licenseExpires(String date) {
    return 'Expires: $date';
  }

  @override
  String licenseGraceLeft(int days) {
    return '$days days of grace left';
  }

  @override
  String get licenseReadOnly =>
      'License expired — read-only. Renew to keep selling.';

  @override
  String get licenseInvalidKey => 'Invalid or unknown license key.';

  @override
  String get licenseActivateFailed =>
      'Activation failed. Check your connection.';

  @override
  String get licenseActivated => 'License activated';

  @override
  String get licenseRenewTitle => 'Record renewal payment';

  @override
  String get licenseRecordPayment => 'Record payment';

  @override
  String get licensePaymentSaved => 'Renewal payment recorded';

  @override
  String get licenseAmount => 'Amount';

  @override
  String get licenseRefNo => 'Reference no.';

  @override
  String get licensePayTo => 'Transfer license fee to:';

  @override
  String get licenseTxnId => 'Transaction ID (last 6 digits)';

  @override
  String get licenseDeactivate => 'Remove license';

  @override
  String get licenseDeactivateConfirm =>
      'Remove the license from this device? Your expiry date is kept — re-activating the same key later won\'t lose any days or restart it.';

  @override
  String get licensePlanLabel => 'Plan';

  @override
  String get licensePlanMonthly => 'Monthly';

  @override
  String get licensePlanYearly => 'Yearly';

  @override
  String get licenseDuration => 'Duration';

  @override
  String get unitMonths => 'months';

  @override
  String get unitYears => 'years';

  @override
  String get licenseGetKey => 'Enter the key you received when you subscribed.';

  @override
  String get licenseNoKeyTitle => 'Don\'t have a key?';

  @override
  String get licenseNoKeyHint =>
      'Subscribe online: pay via KBZPay/WavePay and we\'ll send your key.';

  @override
  String get licenseSubscribe => 'Subscribe / Get license';

  @override
  String get licenseRenew => 'Renew / Extend';

  @override
  String licenseExpiringSoon(int days) {
    return 'License expires in $days days — tap to renew.';
  }

  @override
  String get licenseThankYouTitle => 'Thank you!';

  @override
  String get licenseThankYou24h =>
      'We\'ll verify your payment and your access will begin within 24 hours.';

  @override
  String get licenseFreeTrial => 'Start free 2-month trial';

  @override
  String get licenseTrialStarted => 'Free 2-month trial started';

  @override
  String get licenseTrialUsed => 'Free trial already used on this device.';

  @override
  String get licenseRefId => 'App Reference ID';

  @override
  String get licenseRequestSent =>
      'Request sent. We\'ll review your payment and send your key.';

  @override
  String licenseRequestSentViber(String viber) {
    return 'Request sent. We\'ll send your key via Viber $viber.';
  }

  @override
  String get licenseCheckRenewal => 'Check for renewal';

  @override
  String get licenseRefreshed => 'License status updated';

  @override
  String get licenseRenewHint =>
      'After paying (KPay/WavePay) and recording it, ask the admin to approve, then tap Check for renewal.';

  @override
  String get deviceSectionTitle => 'Devices';

  @override
  String deviceCount(int used, int free) {
    return '$used/$free free devices used';
  }

  @override
  String get deviceThisDevice => 'This device';

  @override
  String deviceLastActive(String when) {
    return 'Last active $when';
  }

  @override
  String get deviceNeverVerified => 'Not yet activated';

  @override
  String get deviceAdd => 'Add a device';

  @override
  String get deviceRelease => 'Release';

  @override
  String get deviceReleaseConfirmTitle => 'Release this device?';

  @override
  String get deviceReleaseConfirmBody =>
      'The device will lose access to this shop next time it checks its license. You can add a new device in its place afterward.';

  @override
  String get deviceReleased => 'Device released';

  @override
  String get deviceKeyReadyTitle => 'New device is ready';

  @override
  String get deviceKeyReadyHint =>
      'Scan this QR code on the new device\'s activation screen, or type the key below.';

  @override
  String get deviceKeyCopied => 'Key copied';

  @override
  String get devicePaymentRequiredTitle => 'Device fee required';

  @override
  String devicePaymentRequiredBody(int free, String fee) {
    return 'This shop already uses its $free free devices. Adding another costs $fee (one-time) — after paying, contact support with your App Reference ID to get your new device\'s key.';
  }

  @override
  String get deviceOnlyOnPaidPlan =>
      'Add a device once you have an active subscription (not available during the free trial).';

  @override
  String get deviceRequestFailed => 'Couldn\'t add a device — try again.';

  @override
  String get deviceRoleTitle => 'Who is this device for?';

  @override
  String get deviceRoleHint =>
      'Picked now, so the new phone is already set up correctly the moment it activates — no separate step needed on it.';

  @override
  String get deviceRoleStaffMember => 'Staff member (optional)';

  @override
  String get deviceRoleAppliesOnScan =>
      'Staff mode will be applied automatically when this QR is scanned to activate.';

  @override
  String get referralTitle => 'Refer & earn';

  @override
  String get referralSubtitle =>
      'Share your code. Every month a shop you referred pays, you earn — added straight to your license.';

  @override
  String get referralMyCode => 'My referral code';

  @override
  String get referralShare => 'Share code';

  @override
  String get referralCopied => 'Code copied';

  @override
  String referralShareText(String code, String shop) {
    return 'Use MM POS for your shop! Enter my referral code $code when you subscribe. — $shop';
  }

  @override
  String get referralBalance => 'Your earnings';

  @override
  String get referralEarnedTotal => 'Total earned';

  @override
  String get referralActiveShops => 'Shops you referred';

  @override
  String get referralRedeem => 'Redeem for license days';

  @override
  String referralRedeemDone(int months) {
    return 'Added $months month(s) to your license!';
  }

  @override
  String get referralRedeemNotEnough =>
      'Not enough balance yet — refer one more shop!';

  @override
  String referralNextGoal(String amount) {
    return '$amount more until your next free month';
  }

  @override
  String get referralCodeOptional => 'Referral code (optional)';

  @override
  String get referralCodeHint =>
      'Got a friend\'s code? Enter it — they earn when your payment is approved.';

  @override
  String get referralEmpty =>
      'No referrals yet. Share your code to start earning every month.';

  @override
  String get referralNotifTitle => '🎉 Commission earned!';

  @override
  String referralNotifBody(String amount) {
    return '$amount was added to your referral wallet. Open the app to redeem it for free license days.';
  }

  @override
  String get referralHowTitle => 'How Refer & earn works';

  @override
  String get referralStep1 => 'Share your code with other shop owners.';

  @override
  String get referralStep2 =>
      'They type your code when they subscribe and pay.';

  @override
  String get referralStep3 =>
      'You earn a commission every month they keep paying.';

  @override
  String get referralStep4 =>
      'Turn your balance into free license days anytime.';

  @override
  String get referralHaveCode => 'Have a referral code?';

  @override
  String get referralHaveCodeHint =>
      'A friend gave you one? Enter it below — they earn when your payment is approved. Leave blank if you don\'t have one.';

  @override
  String get referralRedeemConfirmTitle => 'Redeem now?';

  @override
  String referralRedeemConfirmBody(int months, String amount) {
    return 'Add $months month(s) to your license and use $amount from your balance?';
  }

  @override
  String get referralRedeemAction => 'Redeem';

  @override
  String get backupTitle => 'Backup & restore';

  @override
  String get backupHint =>
      'Your data is stored on this device. Export a backup file and keep it safe (e.g. send it to Viber → My Notes).';

  @override
  String get backupExport => 'Export backup';

  @override
  String get backupExportHint => 'Save all data to a file and share it.';

  @override
  String get backupImport => 'Import backup';

  @override
  String get backupImportHint => 'Restore data from a backup file.';

  @override
  String get backupShareSubject => 'MM POS backup';

  @override
  String get backupShareText =>
      'MM POS data backup. Keep this file to restore later.';

  @override
  String get backupImportConfirmTitle => 'Replace all data?';

  @override
  String get backupImportConfirmBody =>
      'This will erase the current products, sales and credit data and replace them with the backup. This cannot be undone.';

  @override
  String get backupImportConfirmAction => 'Replace';

  @override
  String backupImportDone(int count) {
    return 'Restored $count rows';
  }

  @override
  String backupFailed(String error) {
    return 'Backup failed: $error';
  }

  @override
  String get settingsSync => 'Cloud sync';

  @override
  String get syncNow => 'Sync now';

  @override
  String get syncIdle => 'Up to date';

  @override
  String get syncSyncing => 'Syncing…';

  @override
  String get syncOffline => 'Offline';

  @override
  String get syncError => 'Sync error';

  @override
  String get syncDisabled => 'Cloud sync not configured';

  @override
  String get syncNever => 'Never synced';

  @override
  String syncLastSynced(String time) {
    return 'Last synced: $time';
  }

  @override
  String get syncRealtimeOn => 'Live updates on';

  @override
  String get navOrders => 'Orders';

  @override
  String get ordersTitle => 'Social Orders';

  @override
  String get ordersEmpty => 'No orders yet. Tap + to add one.';

  @override
  String get orderNew => 'New order';

  @override
  String get orderEditTitle => 'Edit order';

  @override
  String get orderStatusNew => 'New';

  @override
  String get orderStatusConfirmed => 'Confirmed';

  @override
  String get orderStatusPacked => 'Packed';

  @override
  String get orderStatusShipped => 'Shipped';

  @override
  String get orderStatusDelivered => 'Delivered';

  @override
  String get orderStatusCancelled => 'Cancelled';

  @override
  String get orderChannelFacebook => 'Facebook';

  @override
  String get orderChannelViber => 'Viber';

  @override
  String get orderChannelTiktok => 'TikTok';

  @override
  String get orderChannelInstagram => 'Instagram';

  @override
  String get orderChannelPhone => 'Phone';

  @override
  String get orderChannelStorefront => 'Web';

  @override
  String get orderChannelOther => 'Other';

  @override
  String get orderCustomerName => 'Customer name';

  @override
  String get orderCustomerPhone => 'Phone (optional)';

  @override
  String get orderChannel => 'Channel';

  @override
  String get orderDeliveryAddress => 'Delivery address';

  @override
  String get orderDeliveryFee => 'Delivery fee';

  @override
  String get orderNote => 'Note';

  @override
  String get orderMoreDetails =>
      'More details (phone, address, delivery fee, note)';

  @override
  String get orderItems => 'Items';

  @override
  String get orderAddItem => 'Add item';

  @override
  String get orderItemName => 'Item name';

  @override
  String get orderItemPrice => 'Price';

  @override
  String get orderItemQty => 'Qty';

  @override
  String get orderItemsTotal => 'Items subtotal';

  @override
  String get orderTotal => 'Total';

  @override
  String get orderPayment => 'Payment';

  @override
  String get orderPayUnpaid => 'Unpaid';

  @override
  String get orderPaymentTransfer => 'Bank transfer';

  @override
  String get orderPaymentCod => 'Cash on delivery';

  @override
  String get orderPaymentCodNote =>
      'Cash on delivery — collected when the order arrives';

  @override
  String get orderPayPartial => 'Partial';

  @override
  String get orderPayPaid => 'Paid';

  @override
  String get orderAwaitingPayment => 'Awaiting payment';

  @override
  String get orderMarkAsPaid => 'Mark as paid';

  @override
  String get orderMarkAsUnpaid => 'Mark as unpaid';

  @override
  String get orderSave => 'Save order';

  @override
  String get orderEdit => 'Edit';

  @override
  String get orderDelete => 'Delete order';

  @override
  String get orderDeleteConfirm => 'Delete this order? This cannot be undone.';

  @override
  String get orderMoveTo => 'Move to';

  @override
  String get orderConvertToSale => 'Convert to sale';

  @override
  String get orderConvertHint =>
      'Creates an invoice and deducts stock for catalog items.';

  @override
  String orderConverted(String invoice) {
    return 'Order converted to a sale ($invoice).';
  }

  @override
  String get orderAlreadySale => 'Already recorded as a sale.';

  @override
  String get orderCancel => 'Cancel order';

  @override
  String get orderRestore => 'Restore to New';

  @override
  String get orderNeedsName => 'Enter a customer name.';

  @override
  String get orderNeedsItem => 'Add at least one item.';

  @override
  String get orderSaved => 'Order saved.';

  @override
  String orderItemsCount(int count) {
    return '$count items';
  }

  @override
  String get orderPickPaymentMethod => 'Payment method';

  @override
  String get orderPaymentProof => 'Payment screenshot';

  @override
  String get orderInvoice => 'Share invoice';

  @override
  String get orderPrint => 'Print';

  @override
  String get deliverySection => 'Delivery';

  @override
  String get deliveryTownship => 'Township';

  @override
  String get deliveryTownshipNone => 'No township set';

  @override
  String get deliveryCarrier => 'Carrier';

  @override
  String get deliveryCarrierNinjaVan => 'Ninja Van';

  @override
  String get deliveryCarrierRoyalExpress => 'Royal Express';

  @override
  String get deliveryCarrierOther => 'Other';

  @override
  String get deliveryCarrierNone => 'Not assigned';

  @override
  String get deliveryTrackingNumber => 'Tracking / waybill number';

  @override
  String get deliveryTrackingHint =>
      'Enter after booking on the carrier\'s own app';

  @override
  String get deliveryStatusLabel => 'Delivery status';

  @override
  String get deliveryStatusPending => 'Pending';

  @override
  String get deliveryStatusBooked => 'Booked';

  @override
  String get deliveryStatusOutForDelivery => 'Out for delivery';

  @override
  String get deliveryStatusDelivered => 'Delivered';

  @override
  String get deliveryStatusFailed => 'Failed';

  @override
  String get deliveryStatusReturned => 'Returned';

  @override
  String get deliverySave => 'Save delivery info';

  @override
  String get deliverySaved => 'Delivery info saved';

  @override
  String get deliveryManualNote =>
      'No live carrier API yet — book the waybill in the carrier\'s own app, then record the tracking number here.';

  @override
  String get ordersSearchHint => 'Search name, phone, order #';

  @override
  String get ordersNoMatch => 'No orders match your filters.';

  @override
  String get ordersClearFilters => 'Clear filters';

  @override
  String get orderFilterChannel => 'Channel';

  @override
  String get orderFilterPayment => 'Payment';

  @override
  String get staffMode => 'Staff mode';

  @override
  String get staffRoleOwner => 'Owner';

  @override
  String get staffRoleStaff => 'Staff';

  @override
  String staffCurrentRole(String role) {
    return 'Current: $role';
  }

  @override
  String staffSwitchTo(String role) {
    return 'Switch to $role';
  }

  @override
  String get staffUnlockOwner => 'Unlock Owner';

  @override
  String get staffSetPin => 'Set owner PIN';

  @override
  String get staffChangePin => 'Change owner PIN';

  @override
  String get staffEnterPin => 'Enter owner PIN';

  @override
  String get staffWrongPin => 'Wrong PIN';

  @override
  String get staffPinHint => '4–6 digits';

  @override
  String get staffPinSaved => 'PIN saved';

  @override
  String get staffOwnerOnly => 'Owner only';

  @override
  String get staffOwnerOnlyDesc =>
      'Switch to Owner mode (Settings) to view this.';

  @override
  String get staffBadge => 'Staff mode';

  @override
  String get staffManageMembers => 'Manage staff';

  @override
  String get staffMembersTitle => 'Staff members';

  @override
  String get staffMembersEmpty =>
      'No staff members yet. Add one so sales can be attributed to whoever rang them up.';

  @override
  String get staffAddMember => 'Add staff';

  @override
  String get staffEditMember => 'Edit staff';

  @override
  String get staffMemberName => 'Name';

  @override
  String get staffMemberPin => 'PIN (4–6 digits)';

  @override
  String get staffMemberSaved => 'Staff member saved';

  @override
  String get staffRemoveMember => 'Remove';

  @override
  String get staffRemoveConfirmTitle => 'Remove this staff member?';

  @override
  String staffRemoveConfirmBody(String name) {
    return '$name will no longer appear when switching to Staff mode. Past sales still show their name.';
  }

  @override
  String get staffMemberRemoved => 'Staff member removed';

  @override
  String get staffWhoAreYou => 'Who\'s using this device?';

  @override
  String get staffNoNamedStaff => 'No name — just Staff mode';

  @override
  String get storefrontTitle => 'My web storefront';

  @override
  String get storefrontDesc =>
      'Publish a public catalog your customers can order from — no app needed.';

  @override
  String get storefrontPublish => 'Publish storefront';

  @override
  String get storefrontDisplayName => 'Storefront name';

  @override
  String get storefrontYourLink => 'Your shop link';

  @override
  String get storefrontEnabled => 'Storefront enabled';

  @override
  String get storefrontCopied => 'Link copied';

  @override
  String get storefrontNeedsName => 'Enter a storefront name';

  @override
  String get storefrontShare =>
      'Share this link with customers on Facebook, Viber, etc.';

  @override
  String get storefrontPaymentInfoTitle => 'Payment accounts';

  @override
  String get storefrontPaymentInfoHint =>
      'Shown to customers at checkout so they know who to transfer to.';

  @override
  String get storefrontPayKpayName => 'KBZPay account name';

  @override
  String get storefrontPayKpayNumber => 'KBZPay number';

  @override
  String get storefrontPayWaveName => 'WavePay account name';

  @override
  String get storefrontPayWaveNumber => 'WavePay number';

  @override
  String get storefrontNumberCopied => 'Number copied';

  @override
  String get onboardWelcomeTitle => 'Welcome to GoldPOSMM';

  @override
  String get onboardWelcomeBody =>
      'Offline-first point of sale for Myanmar shops. Let\'s get your shop set up — it only takes a minute.';

  @override
  String get onboardNext => 'Next';

  @override
  String get onboardSkip => 'Skip';

  @override
  String get onboardGetStarted => 'Get started';

  @override
  String get onboardShopTitle => 'Your shop';

  @override
  String get onboardShopBody => 'This appears on your printed receipts.';

  @override
  String get onboardLicenseTitle => 'Free trial or license key';

  @override
  String get onboardLicenseBody =>
      'You get a 2-month free trial automatically — no card, no signup. Already have a license key from an agent? Activate it now, or add it later from Settings.';

  @override
  String get onboardActivateNow => 'Activate a license key';

  @override
  String get onboardStaffTitle => 'Owner and Staff modes';

  @override
  String get onboardStaffBody =>
      'You\'re in Owner mode — full access. Handing the phone to an employee? Go to Settings → Owner Tools → Switch to Staff. Staff mode only shows Sell and Orders; a PIN is needed to switch back to Owner.';

  @override
  String get currencySymbol => 'Ks';
}
