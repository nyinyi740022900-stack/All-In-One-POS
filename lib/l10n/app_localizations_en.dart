// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'All In One POS';

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
  String get commonUnexpectedError => 'Something went wrong. Please try again.';

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
  String get commonMore => 'More actions';

  @override
  String get commonClear => 'Clear';

  @override
  String get commonNetworkError =>
      'No internet connection. Check your connection and try again.';

  @override
  String get commonRetry => 'Retry';

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
  String get ordersSelectHint => 'Select an order';

  @override
  String get invoicesSelectHint => 'Select an invoice';

  @override
  String get sellCheckout => 'Checkout';

  @override
  String get sellSubtotal => 'Subtotal';

  @override
  String get sellDiscount => 'Discount';

  @override
  String sellItemDiscountTitle(String item) {
    return 'Discount for $item';
  }

  @override
  String get sellPaymentMethod => 'Payment method';

  @override
  String get sellAmountPaid => 'Amount paid';

  @override
  String get sellTenderExact => 'Exact';

  @override
  String get sellChange => 'Change';

  @override
  String get sellConfirm => 'Confirm sale';

  @override
  String get sellDecreaseQty => 'Decrease quantity';

  @override
  String get sellIncreaseQty => 'Increase quantity';

  @override
  String get sellClear => 'Clear';

  @override
  String get sellClearConfirmTitle => 'Clear the cart?';

  @override
  String get sellClearConfirmBody =>
      'Every item already added will be removed. This cannot be undone.';

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
  String get sellCheckoutFailed =>
      'Sale wasn\'t saved — nothing was charged. Please try again.';

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
  String get paymentCod => 'COD (Cash on Delivery)';

  @override
  String get cashRegisterTitle => 'Cash register';

  @override
  String get cashRegisterOpen => 'Open';

  @override
  String get cashRegisterClosed => 'Closed';

  @override
  String get cashOpeningAmount => 'Opening cash amount';

  @override
  String get cashOpenRegister => 'Open register';

  @override
  String get cashCloseRegister => 'Close register';

  @override
  String get cashExpectedNow => 'Expected cash now';

  @override
  String get cashOpenedAt => 'Opened';

  @override
  String get cashClosingAmount => 'Counted cash';

  @override
  String get cashCloseWarning =>
      'Once closed, this count is final — the session and its variance can\'t be edited afterward.';

  @override
  String get cashVariance => 'Variance';

  @override
  String cashVarianceShort(String amount) {
    return 'Short by $amount';
  }

  @override
  String cashVarianceOver(String amount) {
    return 'Over by $amount';
  }

  @override
  String get cashVarianceExact => 'Matches exactly';

  @override
  String get cashNote => 'Note (optional)';

  @override
  String get cashHistory => 'History';

  @override
  String get cashNoSession => 'The register isn\'t open yet.';

  @override
  String get cashNoHistory => 'No past sessions yet.';

  @override
  String get cashRegisterOpenedMsg => 'Register opened';

  @override
  String get cashRegisterClosedMsg => 'Register closed';

  @override
  String get cashReportTitle => 'Cash Session Report';

  @override
  String get cashClosedAt => 'Closed';

  @override
  String get cashReportPrintBluetooth => 'Print (Bluetooth)';

  @override
  String get cashReportSharePdf => 'Share PDF';

  @override
  String get cashReportCashSales => 'Cash sales';

  @override
  String get cashReportCashRepayments => 'Cash repayments';

  @override
  String get creditTitle => 'Credit book';

  @override
  String get creditCustomerName => 'Customer name';

  @override
  String get customerPhone => 'Phone (optional)';

  @override
  String get phoneFormatHint =>
      'Doesn\'t look like a Myanmar phone number (e.g. 09xxxxxxxxx) — you can still save it.';

  @override
  String get checkoutAddCustomer => 'Add customer';

  @override
  String get checkoutSaveToDirectory => 'Save to customer list';

  @override
  String get checkoutPickCustomer => 'Pick from customers';

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
  String get creditDeposit => 'Deposit';

  @override
  String get creditBalanceDue => 'Balance due';

  @override
  String get creditPreviousBalance => 'Previous balance';

  @override
  String get creditTotalBalanceDue => 'Total balance due';

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
  String get creditFilterOutstanding => 'Outstanding';

  @override
  String get creditFilterAll => 'All';

  @override
  String get creditRepayments => 'Repayments';

  @override
  String get creditRecordRepayment => 'Record repayment';

  @override
  String get creditAmount => 'Amount';

  @override
  String creditRepaymentExceedsOutstanding(String outstanding) {
    return 'This is more than the amount owed ($outstanding).';
  }

  @override
  String get accountsPayableTitle => 'Accounts payable';

  @override
  String get apNoneDue => 'Nothing owed to suppliers';

  @override
  String get apOutstanding => 'Outstanding';

  @override
  String get apEmpty => 'You don\'t owe any supplier right now.';

  @override
  String get apRecordPayment => 'Record payment';

  @override
  String get apReceivedPOs => 'Received purchase orders';

  @override
  String get apPayments => 'Payments';

  @override
  String get apPaymentSaved => 'Payment recorded';

  @override
  String get equityTitle => 'Owner\'s equity';

  @override
  String get equityPaidInCapital => 'Paid-in capital';

  @override
  String get equityRetainedEarnings => 'Retained earnings';

  @override
  String get equityTotal => 'Total equity';

  @override
  String get equityContribution => 'Contribution';

  @override
  String get equityDrawing => 'Drawing';

  @override
  String get equityAdd => 'Add entry';

  @override
  String get equityAmount => 'Amount';

  @override
  String get equityEmpty => 'No contributions or drawings recorded yet.';

  @override
  String get equitySaved => 'Saved';

  @override
  String get equityDeleteConfirmTitle => 'Remove this entry?';

  @override
  String get equityDeleteConfirmBody => 'This cannot be undone.';

  @override
  String get equityDeleted => 'Entry removed';

  @override
  String get creditRepaymentSaved => 'Repayment recorded';

  @override
  String get customersTitle => 'Customers';

  @override
  String get customersEmpty => 'No customers yet. Add your first customer.';

  @override
  String get customersNoMatch => 'No customers match that search.';

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
  String get suppliersTitle => 'Suppliers';

  @override
  String get suppliersEmpty => 'No suppliers yet. Add your first supplier.';

  @override
  String get supplierAdd => 'Add supplier';

  @override
  String get supplierEdit => 'Edit supplier';

  @override
  String get supplierNameLabel => 'Supplier name';

  @override
  String get supplierSaved => 'Supplier saved';

  @override
  String get supplierDeleteConfirmTitle => 'Remove this supplier?';

  @override
  String supplierDeleteConfirmBody(String name) {
    return '$name will no longer appear as a suggestion on new purchase orders. Past purchase orders still show their name.';
  }

  @override
  String supplierDeleteConfirmApWarning(String name, String amount) {
    return '$name still owes $amount in Accounts Payable. Deleting the supplier won\'t cancel that debt — it stays visible in Accounts Payable under their saved name.';
  }

  @override
  String get supplierDeleted => 'Supplier removed';

  @override
  String get paymentAccountsTitle => 'Payment accounts';

  @override
  String get paymentAccountsEmpty =>
      'No payment accounts yet. Add your first account.';

  @override
  String get paymentAccountAdd => 'Add account';

  @override
  String get paymentAccountEdit => 'Edit account';

  @override
  String get paymentAccountNameLabel => 'Account name';

  @override
  String get paymentAccountOpeningBalanceLabel => 'Opening balance';

  @override
  String get paymentAccountSaved => 'Account saved';

  @override
  String get paymentAccountDeleteConfirmTitle => 'Remove this account?';

  @override
  String paymentAccountDeleteConfirmBody(String name) {
    return '$name will no longer appear as a payment option at checkout. Past sales still show its name.';
  }

  @override
  String get paymentAccountDeleted => 'Account removed';

  @override
  String get expensePaidFrom => 'Paid from';

  @override
  String get purchaseOrdersTitle => 'Purchase orders';

  @override
  String get purchaseOrdersEmpty => 'No purchase orders yet.';

  @override
  String get poCreate => 'Create purchase order';

  @override
  String get poItems => 'Items';

  @override
  String get poNoItems => 'No items added yet — tap + to add a product.';

  @override
  String get poRemoveLineConfirmTitle => 'Remove this item from the draft?';

  @override
  String get poUnitCost => 'Unit cost';

  @override
  String get poSaveDraft => 'Save';

  @override
  String get poSaved => 'Purchase order saved.';

  @override
  String get poNeedsSupplier => 'Enter a supplier name.';

  @override
  String get poNeedsItems => 'Add at least one item before saving.';

  @override
  String get poNoProductsFound => 'No products found.';

  @override
  String get poStatusOpen => 'Open';

  @override
  String get poStatusReceived => 'Received';

  @override
  String get poStatusCancelled => 'Cancelled';

  @override
  String get poMarkReceived => 'Mark as received';

  @override
  String get poReceiveConfirmTitle => 'Mark this purchase order as received?';

  @override
  String get poReceiveConfirmBody =>
      'This adds every item\'s ordered quantity to stock at its ordered cost. This can\'t be undone.';

  @override
  String get poReceived => 'Purchase order received — stock updated.';

  @override
  String get poReceiveFailed =>
      'Couldn\'t mark as received — stock wasn\'t updated. Please try again.';

  @override
  String get poCancelOrder => 'Cancel purchase order';

  @override
  String get poCancelConfirmTitle =>
      'Cancel this purchase order? Stock will not be affected.';

  @override
  String get poCancelConfirmBody =>
      'This marks the order as cancelled and it can no longer be received. Your stock is not touched. This can\'t be undone.';

  @override
  String get poDeleteConfirmTitle => 'Delete this purchase order?';

  @override
  String get poDeleteConfirmBody =>
      'This permanently removes the draft and its line items. This cannot be undone.';

  @override
  String get poDeleteFailedReceived =>
      'Can\'t delete a purchase order that\'s already been received.';

  @override
  String get inventoryTitle => 'Inventory';

  @override
  String get inventoryExportCsv => 'Export CSV';

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
  String inventoryFilteredCount(int count) {
    return '$count products';
  }

  @override
  String get inventoryOutOfStock => 'Out of stock';

  @override
  String get inventoryOutOfStockBadge => 'Sold out';

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
  String get productOnlineStockLimitHint =>
      'Recommended for online sales: set how many units this product may sell on your web storefront (keeps walk-in stock safe). Leave blank for no online cap.';

  @override
  String get productOnlineStockLimit => 'Online stock limit';

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
  String get stockAdjustUnitCost => 'Unit cost (optional)';

  @override
  String get stockAdjustUnitCostHint =>
      'Leave blank to use the product\'s cost price';

  @override
  String get stockAdjustReason => 'Reason';

  @override
  String get stockAdjustNote => 'Note (optional)';

  @override
  String get stockAdjustSave => 'Save';

  @override
  String get stockAdjustInvalid => 'Enter a valid quantity';

  @override
  String stockAdjustBelowZero(int quantity) {
    return 'This would take stock below zero (currently $quantity).';
  }

  @override
  String get stockAdjustRace =>
      'Stock changed on another device — refresh and try again.';

  @override
  String stockAdjustCurrentStock(int quantity) {
    return 'Current stock: $quantity';
  }

  @override
  String get stockAdjustConfirmTitle => 'Confirm stock change';

  @override
  String stockAdjustConfirmBody(String name, int before, int after) {
    return '$name: stock changes from $before to $after. This is recorded in stock history but not automatically reversible.';
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
  String get stockHistoryEmptyFiltered =>
      'Some movements may be hidden by the type or date filters.';

  @override
  String get stockHistoryShowAll => 'Show all movements';

  @override
  String get stockHistoryPickDateRange => 'Pick date range';

  @override
  String get stockHistoryClearDateRange => 'Clear date range';

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
  String get productDeleteConfirmBody =>
      'It will be hidden from Sell and Inventory, but stays visible on past sales, invoices, and stock history.';

  @override
  String get categoryDeleteConfirmBody =>
      'Products in this category keep their prices and stock, but show as uncategorized.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionBusiness => 'Business';

  @override
  String get settingsSectionFinance => 'Finance';

  @override
  String get settingsSectionAccountTeam => 'Account & Team';

  @override
  String get settingsSectionDevice => 'Device';

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
  String get settingsAppGuide => 'App Guide';

  @override
  String get helpGuideTitle => 'App Guide';

  @override
  String get helpGuideIntro =>
      'A quick tour of what each screen does. Tap a section to expand it.';

  @override
  String get helpGuideSellTitle => 'Sell';

  @override
  String get helpGuideSellBody =>
      '1. Tap a product tile to add it to the cart, or use the scan icon to add it by barcode.\n2. Tap a line in the cart to change its quantity, or remove it.\n3. If this customer has a Wholesale/VIP pricing tier, pick them in the customer field — prices update automatically.\n4. Tap \"Checkout\" to open the payment sheet.\n5. Add a discount if needed, then choose a payment method (Cash, KBZPay, WavePay, AYAPay, CBPay, or Credit).\n6. For a Credit sale, enter the customer\'s name (required) and any amount paid now.\n7. Confirm the sale — stock updates automatically, a receipt prints if a printer is connected, and the sale is recorded for Analytics.';

  @override
  String get helpGuideInventoryTitle => 'Inventory';

  @override
  String get helpGuideInventoryBody =>
      '1. Tap \"Add product\" to create one: name, photo, sale price, cost price, barcode/SKU, starting stock, and reorder level.\n2. Optionally set Wholesale/VIP prices — leave them blank to use the sale price for those tiers.\n3. Tap any product to edit its details later.\n4. Tap the stock icon to open Restock/Adjust: \"Restock\" adds purchased stock (with an optional unit cost); \"Adjust\" corrects a count with a reason (damaged, lost, count correction).\n5. Tap \"View stock history\" to see every past stock movement for that product.\n6. Products below their reorder level show a \"Low stock\" badge automatically.\n7. Tap the print icon to print a barcode label, on your receipt printer or a dedicated label printer.';

  @override
  String get helpGuideOrdersTitle => 'Orders';

  @override
  String get helpGuideOrdersBody =>
      '1. Orders show as cards on a board — New, Confirmed, Packed, Shipped, Delivered.\n2. Tap \"+\" to add one manually: customer, channel (Facebook, Web, etc.), items, and payment method (cash-on-delivery or transfer).\n3. Drag a card to a new column, or use its \"⋮\" menu to jump straight to any status.\n4. Tap a card to see full details: items, delivery info, and the payment-proof photo for transfer orders.\n5. Use \"Mark as paid\"/\"Mark as unpaid\" to track payment separately from delivery progress.\n6. Once fulfilled, tap \"Convert to sale\" to move it into your sales ledger and stock.\n7. Orders placed by customers on your online storefront appear here automatically — nothing to type in yourself.';

  @override
  String get helpGuideInvoicesTitle => 'Invoices';

  @override
  String get helpGuideInvoicesBody =>
      '1. Every completed sale appears here as an invoice, newest first.\n2. Tap an invoice to see its full details: items, customer, payment method, and status.\n3. For a Credit sale, record a partial or full repayment right from the invoice detail screen.\n4. Overdue credit invoices are highlighted so you know who to follow up with.\n5. Tap \"Refund\" to reverse a sale — stock and the customer\'s credit balance are restored automatically.\n6. Use the search bar, or the scan icon, to find an invoice by number, customer name, or phone.\n7. Every invoice carries a barcode for a quick lookup later.';

  @override
  String get helpGuideAnalyticsTitle => 'Analytics';

  @override
  String get helpGuideAnalyticsBody =>
      'Analytics is a Premium feature — a Free-plan shop sees an upgrade prompt here instead of this screen.\n1. Pick a date range at the top — today, this week, this month, or a custom range.\n2. View total sales, profit, and transaction count for that period.\n3. Scroll down to see your best-selling products, ranked by revenue or quantity.\n4. Profit figures use each sale\'s actual recorded cost, not just today\'s cost price — so past sales stay accurate even after you change a product\'s cost.\n5. Compare two periods side by side to spot trends before deciding what to restock or re-price.';

  @override
  String get helpGuideSettingsTitle => 'Settings';

  @override
  String get helpGuideSettingsBody =>
      '1. \"Shop profile\" — your shop name, logo, address, and contact info, shown on receipts and your storefront.\n2. \"Printer\"/\"Label printer\" — pair your Bluetooth receipt or label printer.\n3. \"License\" — the Free plan works forever, no key or account needed (Sell, Inventory, Cash Register, Expenses, Suppliers, Credit book, and more). Tap \"Upgrade\" to unlock Premium features (Analytics, Staff accounts, and more) — contact Support with your App Reference ID for a license key (no payment inside the app).\n4. \"Account\" — sign in with email + password, or create a shop login. Staff and owners both sign out here. Delete account is available when signed in as owner. Forgot your password? Tap \"Forgot password?\" on the sign-in screen.\n5. \"My web storefront\" — turn on your online shop and set your KBZPay/WavePay payment details.\n6. \"Owner Tools\" — hand this device to a staff member, or switch back to Owner with your PIN. Works with or without an email login.\n7. \"Sync\" — check your connection to the cloud, or force an immediate sync.\n8. Switch the app\'s language between English and Myanmar any time, from the dropdown at the top of this screen.';

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
  String get invoiceDevice => 'Device';

  @override
  String get invoiceDeviceUnnamed => 'Unnamed device';

  @override
  String get invoiceRefunded => 'Refunded';

  @override
  String get invoiceStatusPaid => 'Paid';

  @override
  String get invoiceStatusPartial => 'Partial';

  @override
  String get invoiceStatusUnpaid => 'Unpaid';

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
  String get salesReportTitle => 'Sales report';

  @override
  String get salesReportAllDates => 'All dates';

  @override
  String get salesReportEmpty => 'No sales in this range.';

  @override
  String get salesReportTotal => 'Total';

  @override
  String get salesReportColumnInvoice => 'Invoice #';

  @override
  String get salesReportColumnDate => 'Date';

  @override
  String get salesReportColumnCustomer => 'Customer';

  @override
  String get salesReportColumnAddress => 'Address';

  @override
  String get salesReportColumnAmount => 'Amount';

  @override
  String get salesReportPrintBluetooth => 'Print (Bluetooth)';

  @override
  String get salesReportExportPdf => 'Export PDF';

  @override
  String get salesReportExportCsv => 'Export CSV';

  @override
  String get salesReportNoPrinter =>
      'No Bluetooth printer set up — see Printer settings.';

  @override
  String salesReportCount(int count) {
    return '$count sales';
  }

  @override
  String get pnlTitle => 'Profit & Loss';

  @override
  String get pnlDateRange => 'Date range';

  @override
  String get pnlRevenue => 'Revenue';

  @override
  String get pnlCogs => 'Cost of goods sold';

  @override
  String get pnlGrossProfit => 'Gross profit';

  @override
  String get pnlTotalExpenses => 'Total expenses';

  @override
  String get pnlNetProfit => 'Net profit';

  @override
  String get pnlLine => 'Line';

  @override
  String get pnlAmount => 'Amount';

  @override
  String get pnlExportCsv => 'Export CSV';

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
  String get printerConnected => 'Connected';

  @override
  String get printerPaired => 'Paired devices';

  @override
  String get printerNoDevicesFound => 'No paired Bluetooth devices found.';

  @override
  String get printerChoosePaperSizeTitle =>
      'What paper size does this printer use?';

  @override
  String get printerChoosePaperSizeHint =>
      'Each printer remembers its own size — you can change it anytime from here.';

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
  String get printerPdfPaperSize => 'Document paper size';

  @override
  String get printerPdfPaperSizeHint =>
      'For invoices/reports printed via AirPrint or a computer, not the thermal printer above.';

  @override
  String get paperA4 => 'A4';

  @override
  String get paperA5 => 'A5';

  @override
  String get settingsLabelPrinter => 'Label printer';

  @override
  String get settingsDeviceName => 'Device name';

  @override
  String get settingsDeviceNameUnset => 'Not set — tap to name this device';

  @override
  String get settingsDeviceNameHint => 'e.g. Counter A, Owner\'s phone';

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
  String get analyticsProfit => 'Gross profit';

  @override
  String get analyticsExpenses => 'Total expenses';

  @override
  String get analyticsNetProfit => 'Net profit';

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
  String get expensesTitle => 'Expenses';

  @override
  String get expensesEmpty => 'No expenses logged for this period.';

  @override
  String get expensesTotal => 'Total expenses';

  @override
  String get expenseAdd => 'Add expense';

  @override
  String get expenseEdit => 'Edit expense';

  @override
  String get expenseAmount => 'Amount';

  @override
  String get expenseNote => 'Note (optional)';

  @override
  String get expenseCategoryRent => 'Rent';

  @override
  String get expenseCategoryUtilities => 'Utilities';

  @override
  String get expenseCategoryWages => 'Staff wages';

  @override
  String get expenseCategoryTransport => 'Transport';

  @override
  String get expenseCategoryPackaging => 'Packaging';

  @override
  String get expenseCategoryOther => 'Other';

  @override
  String get expenseReceiptPhotoAdd => 'Attach receipt photo';

  @override
  String get expenseReceiptPhotoReplace => 'Replace photo';

  @override
  String get expenseReceiptPhotoView => 'View photo';

  @override
  String get expenseReceiptPhotoSave => 'Save a copy';

  @override
  String get expenseReceiptPhotoHint =>
      'Kept on this device only, not backed up. Before switching phones, share a copy of it to yourself first.';

  @override
  String get expenseReceiptPhotoMissing =>
      'This receipt photo isn\'t on this device.';

  @override
  String get expenseSaved => 'Expense saved';

  @override
  String get expenseDeleteConfirmTitle => 'Delete this expense?';

  @override
  String get expenseDeleteConfirmBody =>
      'This permanently removes the expense record. This cannot be undone.';

  @override
  String get expenseDeleted => 'Expense deleted';

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
      'This shop isn\'t set up yet, so you can\'t complete a sale.';

  @override
  String get licenseInvalidKey => 'Invalid or unknown license key.';

  @override
  String get licenseActivateFailed =>
      'Activation failed. Check your connection.';

  @override
  String get licenseRateLimited =>
      'Too many attempts — please wait a few minutes and try again.';

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
  String get licenseFixConnection => 'Fix connection issue';

  @override
  String get licenseFixConnectionHint =>
      'If Publish/Register keeps saying your session needs refreshing even after reopening the app, try this — it reconnects your device without losing any data.';

  @override
  String get licenseFixConnectionSuccess =>
      'Connection fixed — please try again.';

  @override
  String get licenseDeactivate => 'Remove license';

  @override
  String get licenseDeactivateConfirm =>
      'Remove the license from this device? Your expiry date is kept — re-activating the same key later won\'t lose any days or restart it. This device switches to the Free plan meanwhile, so Sell and Inventory keep working.';

  @override
  String get licensePlanLabel => 'Plan';

  @override
  String get licensePlanMonthly => 'Monthly';

  @override
  String get licensePlanFree => 'Free plan';

  @override
  String premiumFeatureTitle(String featureName) {
    return '$featureName is a Premium feature';
  }

  @override
  String get premiumFeatureBody =>
      'You\'re on the Free plan — Sell, Inventory, Cash Register, Expenses, Suppliers, and Credit book keep working, but this feature needs an active Premium subscription or license key.';

  @override
  String get premiumUpgradeCta => 'Upgrade';

  @override
  String get analyticsBenefit1 => 'See your best-selling products at a glance';

  @override
  String get analyticsBenefit2 => 'Daily profit trends, not just totals';

  @override
  String get analyticsBenefit3 => 'Compare this month vs last month';

  @override
  String get pnlBenefit1 => 'Real profit — income minus expenses';

  @override
  String get pnlBenefit2 => 'Calculated automatically every month';

  @override
  String get equityBenefit1 => 'See exactly what the business owes you';

  @override
  String get equityBenefit2 => 'Track capital you\'ve put in vs. profit kept';

  @override
  String get purchaseOrdersBenefit1 =>
      'Track what you\'ve ordered from suppliers';

  @override
  String get purchaseOrdersBenefit2 => 'See what\'s arrived vs. still pending';

  @override
  String get accountsPayableBenefit1 =>
      'See exactly what you owe each supplier';

  @override
  String get accountsPayableBenefit2 => 'Never lose track of an unpaid bill';

  @override
  String get paymentAccountsBenefit1 =>
      'Track balances across KBZPay, WavePay, and more';

  @override
  String get paymentAccountsBenefit2 => 'Know exactly where your money is';

  @override
  String get salesReportBenefit1 =>
      'Printable, shareable reports for any period';

  @override
  String get salesReportBenefit2 => 'Hand a clean report to your accountant';

  @override
  String get storefrontBenefit1 => 'A free online ordering page for your shop';

  @override
  String get storefrontBenefit2 => 'Customers browse and order without calling';

  @override
  String get branchesBenefit1 =>
      'Manage multiple shop locations from one account';

  @override
  String get branchesBenefit2 =>
      'See stock and sales for each branch separately';

  @override
  String get staffAccountsBenefit1 => 'Give each staff member their own login';

  @override
  String get staffAccountsBenefit2 => 'No more sharing one PIN for everyone';

  @override
  String get inventoryCsvBenefit =>
      'Export your full product list to a spreadsheet';

  @override
  String get settingsSignInRequired =>
      'Sign in to a shop account first (Account above) to use this.';

  @override
  String get settingsSignIn => 'Sign In';

  @override
  String get settingsOwnerModeRequired =>
      'This phone is in Staff mode. Switch to Owner in Owner Tools (below) to use this.';

  @override
  String get onboardingContinueFree => 'Continue Free';

  @override
  String get accountSignOutPremiumConfirmBody =>
      'You\'ll lose Premium features on this device and it will drop to the Free plan (Sell and Inventory keep working). You\'ll need your email and password again to sign back in and restore Premium.';

  @override
  String get licenseDowngradedToFreeNotice =>
      'Your subscription/key expired — this device is now on the Free plan. Sell and Inventory still work; renew to unlock Premium features again.';

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
  String get licenseHaveKeyTitle => 'Already have a license key?';

  @override
  String get licensePaymentProofLabel => 'Payment screenshot (optional)';

  @override
  String get licensePaymentProofAttach => 'Attach screenshot';

  @override
  String get licensePaymentProofAttached => 'Screenshot attached';

  @override
  String get licenseNoKeyTitle => 'Don\'t have a key?';

  @override
  String get licenseNoKeyHint =>
      'Contact Support on Viber with your App Reference ID — they will send a license key. Then activate it below.';

  @override
  String get licenseContactSupportTitle => 'Contact Support';

  @override
  String get licensePremiumContactHint =>
      'Premium is unlocked by Support outside the app (license key or Online account). Copy the Viber number, send your App Reference ID, and ask to upgrade or renew. No payment is collected inside this app.';

  @override
  String get licensePremiumContactHintOnline =>
      'Premium for Online shops is unlocked on your shop account by Support (no license key to type). Copy the Viber number, send the email you use to sign in, and ask to upgrade or renew. No payment is collected inside this app.';

  @override
  String get licenseSubscribe => 'Subscribe';

  @override
  String get licenseGetKeyTitle => 'Get license key';

  @override
  String get licenseOnlineApplyHint =>
      'Once approved, this is applied to your account automatically — no key to enter.';

  @override
  String get licenseRenew => 'Renew / Extend';

  @override
  String get licenseBuyOrRenewTitle => 'Buy or renew Premium';

  @override
  String get licenseBuyOrRenewIntro =>
      'Two ways — our website, or Viber. Payment is not collected in this app.';

  @override
  String get licensePayOnline => 'Pay online';

  @override
  String get licensePayOnlineHint =>
      'Send a payment request on our website. Works for a new Premium purchase and for renewal — no account needed.';

  @override
  String get licenseContactViber => 'Message on Viber';

  @override
  String get licenseContactViberHint =>
      'Opens Viber. Send your App Reference ID (above) and ask to buy or renew Premium.';

  @override
  String get licenseContactViberHintOnline =>
      'Opens Viber. Send the email you use to sign in and ask to buy or renew Premium.';

  @override
  String get supportViberOpenFailed =>
      'Couldn\'t open Viber. The number was copied — paste it in Viber.';

  @override
  String get licenseAfterPaymentTitle => 'Already paid or asked Support?';

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
  String get licenseFreeTrial => 'Try Premium';

  @override
  String get licensePlanTrial => 'Free trial';

  @override
  String get licenseTrialStartConfirm =>
      'Start your 2-month Premium trial on this device now? Every Premium feature unlocks immediately, no payment needed. One trial per device — needs an internet connection to start.';

  @override
  String get licenseTrialSelfServeHint =>
      '2 months, every Premium feature, no payment — one trial per device.';

  @override
  String get licenseTrialContactHint =>
      'Premium trials are issued by support only (not in-app), no charge. Copy the Viber number, send your App Reference ID, and ask for a trial key.';

  @override
  String get licenseTrialContactHintOnline =>
      'Premium trials for Online shops are issued by Support only, no charge. Copy the Viber number, send your shop account email, and ask for a trial on that account — no key to enter.';

  @override
  String get licenseTrialViberMissing =>
      'Support Viber is not configured yet. Use Settings → Support once it is available, or contact us another way with your App Reference ID.';

  @override
  String get licenseTrialStarted => 'Free 2-month trial started';

  @override
  String get licenseTrialUsed => 'Free trial already used on this device.';

  @override
  String get licenseRefId => 'App Reference ID';

  @override
  String get licenseAccountEmail => 'Shop account email';

  @override
  String get licenseAccountEmailMissing =>
      'Sign in under Account so Support can find your account.';

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
      'After Support extends your license, tap Check for renewal (or activate a new key).';

  @override
  String get licenseRenewHintOnline =>
      'After Support extends your Online subscription, tap Check for renewal — Premium applies to your account automatically (no key).';

  @override
  String get licenseRenewNotFound =>
      'No subscription found for this account yet. After Support extends it, try Check for renewal again.';

  @override
  String get deviceSectionTitle => 'Devices';

  @override
  String get deviceAddOnlineHint =>
      'To use another phone, sign in with the same shop email and password (Settings → Account). No license-key QR is used in Online mode.';

  @override
  String get premiumFeatureBodyOnline =>
      'You\'re on the Free plan — Sell, Inventory, Cash Register, Expenses, Suppliers, and Credit book keep working, but this feature needs an active Online Premium subscription on your shop account.';

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
  String get invWebActivateTitle => 'Activate this computer';

  @override
  String get invWebActivateHint =>
      'On your phone: Settings → License → Add device, then paste the key here.';

  @override
  String get invWebKeyLabel => 'Device key';

  @override
  String get invWebActivateButton => 'Activate';

  @override
  String get invWebErrorEmptyKey => 'Enter a device key';

  @override
  String get invWebErrorInvalidKey => 'That key isn\'t valid or has expired';

  @override
  String get invWebErrorDeviceMismatch =>
      'This key is already bound to a different device';

  @override
  String get invWebErrorPaymentRequired =>
      'Adding this computer needs an extra-device fee — contact support to pay, then try again';

  @override
  String get invWebErrorActivationFailed =>
      'Couldn\'t activate — check the key and try again';

  @override
  String get invWebErrorNetwork =>
      'Network error — check your connection and try again';

  @override
  String get invWebErrorRefreshPending =>
      'Activated — reload this page to continue';

  @override
  String get invWebSignOut => 'Sign out this computer';

  @override
  String get invWebDownloadPdf => 'Download PDF';

  @override
  String get invWebSearchHint => 'Search invoice #, customer, or phone';

  @override
  String get invWebNoResults => 'No invoices match your search.';

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
    return 'Use All In One POS for your shop! Enter my referral code $code when you subscribe. — $shop';
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
  String get backupShareSubject => 'All In One POS backup';

  @override
  String get backupShareText =>
      'All In One POS data backup. Keep this file to restore later.';

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
  String get backupInvalidFile =>
      'This doesn\'t look like a valid backup file.';

  @override
  String get settingsSync => 'Cloud sync';

  @override
  String get syncNow => 'Sync now';

  @override
  String get syncIdle => 'Up to date';

  @override
  String get syncPendingUploads => 'Pending uploads';

  @override
  String get syncHasIssues => 'Sync retrying — open Branches if needed';

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
  String syncIssuesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sync status',
      one: 'Sync status',
    );
    return '$_temp0';
  }

  @override
  String get syncIssuesEmpty => 'Nothing waiting — sync is clear.';

  @override
  String get syncIssuesBackgroundHint =>
      'Background sync finishes any held uploads automatically. If you were offline, they complete when you are back online. Tap Sync now to retry now.';

  @override
  String syncIssuesPendingHint(int count) {
    return '$count upload(s) still retrying — tap Sync now.';
  }

  @override
  String syncIssuesQuarantinedRow(String table) {
    return 'Finishing: $table';
  }

  @override
  String get syncIssuesQuarantinedHeld =>
      'Kept on this device until cloud sync completes automatically.';

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
  String get orderStatusDelivered => 'Delivered';

  @override
  String get orderStatusCancelled => 'Return';

  @override
  String get orderChannelFacebook => 'Facebook';

  @override
  String get orderChannelViber => 'Viber';

  @override
  String get orderChannelTiktok => 'TikTok';

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
  String get orderBlockCustomer => 'Block this customer';

  @override
  String orderBlockCustomerConfirm(String phone) {
    return 'Block $phone from placing new orders on your storefront?';
  }

  @override
  String get orderCustomerBlocked => 'Customer blocked';

  @override
  String get orderLowStockAtOrder =>
      'Requested more than the recorded stock at the time of this order';

  @override
  String get orderCarrierHint => 'Type or pick a carrier';

  @override
  String get orderHandOffButton => 'Handed off to carrier';

  @override
  String orderHandedOffTo(String carrier) {
    return 'Handed off to $carrier';
  }

  @override
  String get orderChangeCarrier => 'Change';

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
  String get orderConvertFailed =>
      'Couldn\'t convert this order to a sale. Please try again.';

  @override
  String get orderAlreadySale => 'Already recorded as a sale.';

  @override
  String get orderCancel => 'Mark as return';

  @override
  String get orderRestore => 'Undo return';

  @override
  String get orderReturnConfirmTitle => 'Return this order?';

  @override
  String orderReturnConfirmBody(String amount) {
    return 'This refunds $amount, reverses the sale, and restores stock. This cannot be undone.';
  }

  @override
  String get orderReturnFailed =>
      'Couldn\'t process the return. Please check Invoices before trying again.';

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
  String get deliveryTownship => 'Township';

  @override
  String get deliveryTownshipNone => 'No township set';

  @override
  String get deliveryCarrier => 'Carrier';

  @override
  String get deliveryCarrierNone => 'Not assigned';

  @override
  String get deliveryTrackingNumber => 'Tracking / waybill number';

  @override
  String get deliveryTrackingHint =>
      'Enter after booking on the carrier\'s own app';

  @override
  String get deliverySave => 'Save delivery info';

  @override
  String get deliverySaved => 'Delivery info saved';

  @override
  String get deliveryManualNote =>
      'No live carrier API yet — book the waybill in the carrier\'s own app, then record the tracking number here.';

  @override
  String get ordersSearchHint => 'Search name, phone, order #, invoice #';

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
  String staffPinTryAgainIn(int seconds) {
    return 'Too many attempts. Try again in ${seconds}s';
  }

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
  String get staffMemberPinKeepHint => 'Leave blank to keep the current PIN';

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
  String get storefrontOrderNeedsName =>
      'Please enter your name to place the order.';

  @override
  String get storefrontSessionStale =>
      'Your session needs refreshing. Please close and reopen the app, then try again.';

  @override
  String get storefrontPhoneShown => 'Phone (shown to customers)';

  @override
  String get storefrontAddressShown => 'Address (shown to customers)';

  @override
  String get storefrontLogoLabel => 'Shop logo';

  @override
  String get storefrontProfileSaved => 'Saved';

  @override
  String get storefrontShare =>
      'Share this link with customers on Facebook, Viber, etc.';

  @override
  String get storefrontShareAction => 'Share link';

  @override
  String storefrontShareText(String name, String url) {
    return '$name\nOrder here: $url';
  }

  @override
  String get storefrontClosed =>
      'This shop is closed for online orders right now. Please try again during opening hours.';

  @override
  String get storefrontProofRequired =>
      'Please attach your transfer screenshot before placing the order.';

  @override
  String get storefrontAttachProofRequired => 'Attach payment screenshot *';

  @override
  String get storefrontHoursTitle => 'Opening hours (Yangon time)';

  @override
  String get storefrontHoursEnabled => 'Only accept orders during hours';

  @override
  String get storefrontHoursOpen => 'Opens';

  @override
  String get storefrontHoursClose => 'Closes';

  @override
  String get storefrontRequireProof => 'Require transfer screenshot';

  @override
  String get storefrontRequireProofHint =>
      'When on, bank-transfer checkouts must upload a payment proof.';

  @override
  String get storefrontOrderNotifTitle => 'New web order';

  @override
  String storefrontOrderNotifBody(int count) {
    return '$count new storefront order(s) — open Orders to review.';
  }

  @override
  String get storefrontBlockedCustomers => 'Blocked customers';

  @override
  String get storefrontNoBlockedCustomers => 'No one is blocked.';

  @override
  String get storefrontUnblock => 'Unblock';

  @override
  String get storefrontAddBlocked => 'Block a phone number';

  @override
  String get storefrontBlockReasonOptional => 'Reason (optional)';

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
  String get storefrontRateLimited =>
      'Too many orders submitted recently — please wait a few minutes and try again.';

  @override
  String get storefrontBlocked =>
      'This shop isn\'t able to accept orders from this phone number. Please contact the shop directly.';

  @override
  String get storefrontOutOfStock =>
      'Sorry, one of your items just sold out online. Please adjust your cart and try again.';

  @override
  String get storefrontInvalidProduct =>
      'One of the items in your cart is no longer available. Please remove it and try again.';

  @override
  String storefrontOnlineLeft(int count) {
    return '$count left online';
  }

  @override
  String get storefrontSoldOut => 'Sold out online';

  @override
  String storefrontCheckoutBar(int count, String total) {
    return 'Checkout · $count item(s) · $total';
  }

  @override
  String get storefrontShopFallbackName => 'Shop';

  @override
  String get storefrontPhoneCopied => 'Phone number copied';

  @override
  String get storefrontAdd => 'Add';

  @override
  String get storefrontYourDetails => 'Your details';

  @override
  String get storefrontNameRequired => 'Name *';

  @override
  String get storefrontPayment => 'Payment';

  @override
  String get storefrontBankTransfer => 'Bank transfer';

  @override
  String get storefrontCashOnDelivery => 'Cash on delivery';

  @override
  String get storefrontPayTo => 'Pay to:';

  @override
  String get storefrontAttachProof => 'Attach payment screenshot';

  @override
  String storefrontProofAttached(String name) {
    return 'Screenshot: $name';
  }

  @override
  String get storefrontCodNoticeBeforeOrder =>
      'You\'ll pay cash to the courier when your order arrives.';

  @override
  String storefrontTotal(String amount) {
    return 'Total: $amount';
  }

  @override
  String get storefrontPlaceOrder => 'Place order';

  @override
  String get storefrontOrderPlaced => 'Order placed!';

  @override
  String storefrontOrderNo(String orderNo) {
    return 'Order no: $orderNo';
  }

  @override
  String get storefrontTransferInstructions =>
      'Transfer and send the screenshot to the shop:';

  @override
  String get storefrontCodNoticeAfterOrder =>
      'You\'ll pay cash to the courier on delivery.';

  @override
  String get storefrontSaveToPhotos => 'Save to Photos';

  @override
  String get storefrontDone => 'Done';

  @override
  String get storefrontCopyNumber => 'Copy number';

  @override
  String storefrontNotFound(String slug) {
    return 'Shop \"$slug\" not found or not published.';
  }

  @override
  String get storefrontOpenShopLink => 'Open a shop link, e.g. /your-shop-slug';

  @override
  String get storefrontRenewTitle => 'Renew subscription';

  @override
  String get storefrontRenewHint =>
      'Submit your payment details below and we\'ll review it to extend your subscription.';

  @override
  String get storefrontRenewShopName => 'Shop name *';

  @override
  String get storefrontRenewDeviceIdHint =>
      'Find this on your phone: Settings → License → App Reference ID. Signed in with an account instead? Skip this and fill in your email below.';

  @override
  String get storefrontRenewEmail => 'Email (if you have an account)';

  @override
  String get storefrontRenewEmailHint =>
      'Have this? You don\'t need the App Reference ID above — either one is enough.';

  @override
  String get storefrontRenewPlan => 'Plan';

  @override
  String storefrontRenewPricePerMonth(String price) {
    return '$price / month';
  }

  @override
  String storefrontRenewPricePerYear(String price) {
    return '$price / year';
  }

  @override
  String get storefrontRenewMonths => 'Months';

  @override
  String get storefrontRenewAmountLockedHint =>
      'This is the fixed amount for your plan — please transfer exactly this much.';

  @override
  String get storefrontRenewAmountPaid => 'Amount to pay (Ks) *';

  @override
  String get storefrontRenewRefNo =>
      'Last 6 digits of the transaction number *';

  @override
  String get storefrontRenewRefNoHint =>
      'Find this at the end of the transaction ID in your KBZPay/WavePay confirmation.';

  @override
  String get storefrontRenewSubmit => 'Submit request';

  @override
  String get storefrontRenewSubmitted =>
      'Request submitted! We\'ll review your payment and extend your subscription soon.';

  @override
  String storefrontRenewRequestId(String requestId) {
    return 'Reference: $requestId';
  }

  @override
  String get storefrontRenewFailed =>
      'Something went wrong. Please try again or contact support.';

  @override
  String get storefrontRenewRateLimited =>
      'Too many requests submitted recently — please wait a few minutes and try again.';

  @override
  String get storefrontRenewMissingFields =>
      'Please fill in shop name, App Reference ID (or email), months, amount, and the last 6 digits of the transaction number.';

  @override
  String get storefrontRenewMonthsTooHigh =>
      'Months can\'t be more than 60 (5 years). Please enter a smaller number.';

  @override
  String get onboardWelcomeTitle => 'Welcome to All In One POS';

  @override
  String get onboardWelcomeBody =>
      'Offline-first point of sale for Myanmar shops. Let\'s get your shop set up — it only takes a minute.';

  @override
  String get onboardNext => 'Next';

  @override
  String get onboardBack => 'Back';

  @override
  String get onboardSkip => 'Skip';

  @override
  String get onboardGetStarted => 'Get started';

  @override
  String get onboardShopTitle => 'Your shop';

  @override
  String get onboardShopBody => 'This appears on your printed receipts.';

  @override
  String get onboardLicenseTitle => 'Free plan or license key';

  @override
  String get onboardLicenseBody =>
      'Continue on the Free plan — Sell and Inventory work forever, no card, no signup, no key needed. Already have a license key from an agent? Activate it now to unlock Premium, or add one later from Settings.';

  @override
  String get onboardActivateNow => 'Activate a license key';

  @override
  String get onboardAccountTitle => 'Sign in (optional)';

  @override
  String get onboardAccountBody =>
      'Already run this shop on another device? Sign in to sync across devices, get cloud backup, and manage staff by email. Skip this and it still works — you can sign in anytime later from Settings.';

  @override
  String get onboardAccountSkip => 'Skip for now';

  @override
  String get onboardAccountSignedInTitle => 'Signed in';

  @override
  String get onboardStaffTitle => 'Owner and Staff modes';

  @override
  String get onboardStaffBody =>
      'You\'re in Owner mode — full access. Handing the phone to an employee? Go to Settings → Owner Tools → Switch to Staff. Staff mode only shows Sell and Orders; a PIN is needed to switch back to Owner. This same PIN also confirms who\'s opening the shop each day.';

  @override
  String get accountShopLoginTitle => 'Account';

  @override
  String get accountShopLoginHint =>
      'Optional: sign in with an email and password to reach this shop from another device. Your existing license key and PIN quick-switch keep working as before.';

  @override
  String get accountProfileSubtitleSignedOut =>
      'Sign in or create a shop login';

  @override
  String get accountCreatedSignedIn => 'Account created. You\'re signed in.';

  @override
  String get accountReadyNoEmailWait =>
      'No confirmation email to wait for — this email and password work on any device right away.';

  @override
  String get accountEmail => 'Email';

  @override
  String get accountPassword => 'Password';

  @override
  String get accountPasswordRememberedHint =>
      'Remembered on this phone after you sign in.';

  @override
  String get accountConfirmPassword => 'Confirm password';

  @override
  String get accountShowPassword => 'Show password';

  @override
  String get accountHidePassword => 'Hide password';

  @override
  String get accountPasswordMismatch => 'Passwords don\'t match';

  @override
  String get passwordStrengthWeak => 'Weak';

  @override
  String get passwordStrengthFair => 'Fair';

  @override
  String get passwordStrengthGood => 'Good';

  @override
  String get passwordStrengthStrong => 'Strong';

  @override
  String get accountForgotPassword => 'Forgot password?';

  @override
  String get accountResetPasswordTitle => 'Reset password';

  @override
  String get accountResetPasswordHint =>
      'Enter the email for your shop account. We\'ll send a link to reset your password.';

  @override
  String get accountResetPasswordSend => 'Send reset link';

  @override
  String get accountResetPasswordSent => 'Check your email for a reset link.';

  @override
  String get accountResetPasswordNewLabel => 'New password';

  @override
  String get accountResetPasswordSave => 'Save new password';

  @override
  String get accountResetPasswordSuccess =>
      'Password updated. You\'re signed in.';

  @override
  String get accountCreateShopLogin => 'Create shop login';

  @override
  String get accountSignIn => 'Sign in';

  @override
  String get accountSignOut => 'Sign out';

  @override
  String get accountDeleteAccount => 'Delete account';

  @override
  String get accountDeleteConfirmTitle => 'Delete your account?';

  @override
  String get accountDeleteConfirmBody =>
      'This permanently deletes your online shop account, staff logins for this shop, and cloud data for shops you own. This device will return to the Free plan. This cannot be undone.';

  @override
  String get accountDeletePasswordLabel => 'Confirm with your password';

  @override
  String get accountDeleteSuccess =>
      'Account deleted. You\'re on the Free plan.';

  @override
  String get accountDeleteFailed =>
      'Could not delete account. Check your password and connection.';

  @override
  String get accountDeleteWrongPassword => 'Wrong password.';

  @override
  String get accountDeleteOwnerOnly =>
      'Only the shop owner can delete the account.';

  @override
  String get accountSignedIn => 'Signed in.';

  @override
  String get accountSignedOut => 'Signed out.';

  @override
  String get accountSignOutConfirmTitle => 'Sign out?';

  @override
  String get accountSignOutConfirmBody =>
      'You\'ll need your email and password again to sign back in. Device-key activation and the local PIN quick-switch are unaffected.';

  @override
  String get accountSignOutConfirmBodyStaff =>
      'You\'ll need your email and password again to sign back in.';

  @override
  String get accountSignInWipeConfirmTitle =>
      'This account belongs to a different shop';

  @override
  String get accountSignInWipeConfirmBody =>
      'This device currently has another shop\'s data. Continuing replaces all local data on this device with this account\'s shop data. Make sure everything is already synced first — this cannot be undone.';

  @override
  String get accountLoginCreated => 'Login created.';

  @override
  String get accountEmailTaken => 'That email is already in use.';

  @override
  String get accountTrialAlreadyUsed =>
      'This device or account has already used its free trial. Contact support to continue.';

  @override
  String get accountNotActivated => 'Activate this device first.';

  @override
  String get accountNoBackend => 'No internet connection.';

  @override
  String get accountPendingSync =>
      'This device still has unsynced changes. Wait for sync to finish, then try again.';

  @override
  String get accountActionFailed => 'Something went wrong. Please try again.';

  @override
  String get staffAccountsTitle => 'Staff accounts (email login)';

  @override
  String get staffAccountsSubtitle =>
      'Online: each staff signs in with their own email and password.';

  @override
  String get staffModeSubtitle =>
      'This phone only: lock the device with an owner PIN (works offline too).';

  @override
  String get staffPinEmailOwnerHint =>
      'Set or change the owner PIN here. Switch this phone to Staff when handing it to a cashier — email login is not required. The same PIN unlocks Owner and confirms who opens the shop each day.';

  @override
  String get staffAccountsInvite => 'Invite staff';

  @override
  String get staffAccountsEmpty =>
      'No staff accounts yet. Invite one with an email and password so they can sign in on their own device.';

  @override
  String get staffAccountsActive => 'Active';

  @override
  String get staffAccountsRevoked => 'Revoked';

  @override
  String get staffAccountsRevoke => 'Revoke';

  @override
  String get staffAccountsRevokeConfirmTitle => 'Revoke this account?';

  @override
  String staffAccountsRevokeConfirmBody(String email) {
    return '$email will no longer be able to sign in.';
  }

  @override
  String get branchesTitle => 'Branches';

  @override
  String get branchesCreate => 'Create a new branch';

  @override
  String get branchesCreated => 'Branch created.';

  @override
  String get branchesEmpty => 'No branches yet.';

  @override
  String get branchesSectionCurrent => 'Current branch';

  @override
  String get branchesSectionOther => 'Other branches';

  @override
  String get branchesNoOther => 'No other branches linked yet.';

  @override
  String get branchesPinnedCurrentTitle => 'Pinned current branch';

  @override
  String get branchesPinnedCurrentHint =>
      'This device is currently scoped to this branch.';

  @override
  String get branchesHealthSafeSwitch => 'Safe to switch';

  @override
  String get branchesHealthSyncNeeded => 'Sync needed';

  @override
  String branchesRowPending(int count) {
    return 'This device — pending uploads: $count';
  }

  @override
  String branchesRowLastSync(String time) {
    return 'Last synced: $time';
  }

  @override
  String get branchesCurrent => 'Current';

  @override
  String get branchesSwitch => 'Switch';

  @override
  String get branchesSwitched => 'Switched branch.';

  @override
  String get branchesSwitchSyncing =>
      'Syncing this shop\'s data — this may take a moment on a slow connection.';

  @override
  String get branchesSwitchConfirmTitle => 'Switch to this branch?';

  @override
  String branchesSwitchConfirmBody(String label) {
    return 'This replaces all local data on this device with \"$label\"\'s data. Make sure everything is already synced first — this cannot be undone.';
  }

  @override
  String get branchesSwitchBlockedTitle => 'Fix sync issues first';

  @override
  String get branchesSwitchBlockedStuckOutbox =>
      'Some uploads are still retrying. Tap Sync now, wait a moment, then try switching again.';

  @override
  String get branchesSwitchFixSyncIssues => 'View sync status';

  @override
  String get branchesPendingSync =>
      'This device still has unsynced changes. Wait for sync to finish, then try again.';

  @override
  String branchesPreflightTitle(String label) {
    return 'Ready to switch to \"$label\"?';
  }

  @override
  String get branchesPreflightTarget => 'Target branch';

  @override
  String branchesPreflightPending(int count) {
    return 'Pending local changes: $count';
  }

  @override
  String branchesPreflightStuck(int count) {
    return 'Uploads still retrying: $count';
  }

  @override
  String branchesPreflightNetwork(String status) {
    return 'Network: $status';
  }

  @override
  String branchesPreflightLastSync(String time) {
    return 'Last synced: $time';
  }

  @override
  String get branchesPreflightNeedSync =>
      'Sync first before switching so no local changes are lost.';

  @override
  String branchesSwitchUploadFailed(int count) {
    return 'Could not upload $count local change(s) yet. Tap Sync now and try switching again. Held items finish automatically in the background and do not block switching.';
  }

  @override
  String get branchesPreflightNeedOnline =>
      'You are offline. Connect to the internet before switching.';

  @override
  String get branchesPreflightSyncAndSwitch => 'Sync and switch';

  @override
  String get branchesPreflightSyncFirst => 'Sync first';

  @override
  String get branchesPreflightSwitchNow => 'Switch now';

  @override
  String get branchesPreflightDetails => 'Details';

  @override
  String get branchesPreflightSummaryReady =>
      'Online — ready to sync and switch.';

  @override
  String get branchesStuckBannerTitle =>
      'Finish syncing before switching branches';

  @override
  String get branchesStuckBannerBody =>
      'Tap Sync now to retry uploads. Held items finish automatically and do not block switching branches.';

  @override
  String get branchesStuckBannerSyncNow => 'Sync now';

  @override
  String get branchesStuckBannerReview => 'View sync status';

  @override
  String get branchesQuarantineBannerTitle =>
      'Some uploads are finishing in the background';

  @override
  String get branchesQuarantineBannerBody =>
      'They stay on this device and do not block switching branches. Sync will complete them automatically.';

  @override
  String get branchesQuarantineBannerOpen => 'View sync status';

  @override
  String get branchesSwitchInProgressTitle => 'Switching branch';

  @override
  String get branchesSwitchStepCheckingDataSafety => 'Checking data safety';

  @override
  String get branchesSwitchStepSwitchingAccountClaim =>
      'Switching account claim';

  @override
  String get branchesSwitchStepRefreshingSession => 'Refreshing session';

  @override
  String get branchesSwitchStepClearingOldData => 'Opening this shop\'s data';

  @override
  String get branchesSwitchStepSyncingNewData => 'Syncing new branch data';

  @override
  String branchesRecoveryBody(String shopId) {
    return 'Branch switch to $shopId was interrupted before setup completed. You can retry sync now.';
  }

  @override
  String branchesRecoveryBodyWithError(String shopId, String error) {
    return 'Branch switch to $shopId is still incomplete: $error.';
  }

  @override
  String get branchesRecoveryRetrySync => 'Retry sync';

  @override
  String get branchesRecoveryDismiss => 'Dismiss';

  @override
  String get branchesRecoveryResolved => 'Branch setup completed.';

  @override
  String get branchesRecoveryStillPending =>
      'Branch setup is still incomplete. You can retry from the banner.';

  @override
  String get branchesVerifyTitle => 'Finishing branch setup';

  @override
  String get branchesVerifyBody =>
      'Some branch data still looks incomplete. Retry sync now, or finish in background and keep using the app.';

  @override
  String get branchesVerifyRetryNow => 'Retry now';

  @override
  String get branchesVerifyFinishBackground => 'Finish in background';

  @override
  String get branchesNetworkOnline => 'Online';

  @override
  String get branchesNetworkOffline => 'Offline';

  @override
  String get branchesNetworkRetry =>
      'Internet connection looks unstable. Please retry.';

  @override
  String get branchesAuthExpired =>
      'Your session expired. Please sign in again.';

  @override
  String get branchesInvalidState =>
      'This branch is no longer linked or allowed for this account.';

  @override
  String get branchesUnlink => 'Unlink';

  @override
  String get branchesUnlinkConfirmTitle => 'Unlink this branch?';

  @override
  String branchesUnlinkConfirmBody(String label) {
    return '\"$label\" will be removed from your branch list. You can re-link it later with its key.';
  }

  @override
  String get recurringExpenseTitle => 'Recurring expenses';

  @override
  String get recurringExpenseManage => 'Manage recurring expenses';

  @override
  String get recurringExpenseAddFromTemplate => 'Add from template';

  @override
  String get recurringExpenseEmpty =>
      'No recurring expenses set up yet. Add one for a cost you pay every month, like rent or wages.';

  @override
  String get recurringExpenseAdd => 'Add recurring expense';

  @override
  String get recurringExpenseEdit => 'Edit recurring expense';

  @override
  String get recurringExpenseSaved => 'Saved.';

  @override
  String get recurringExpenseDeleted => 'Deleted.';

  @override
  String get recurringExpenseDeleteConfirmTitle =>
      'Delete this recurring expense?';

  @override
  String get recurringExpenseDeleteConfirmBody =>
      'This only removes the template — auto-generation stops, but expenses it already created stay untouched.';

  @override
  String get recurringExpenseAutoGenerate => 'Auto-add every month';

  @override
  String get recurringExpenseAutoGenerateHint =>
      'Adds this automatically instead of needing \"Add from template\" — you\'ll still see it in the list right away.';

  @override
  String get recurringExpenseTimingStart => 'Day 1';

  @override
  String get recurringExpenseTimingEnd => 'Last day';

  @override
  String recurringExpenseAutoAdded(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recurring expenses added automatically',
      one: '1 recurring expense added automatically',
    );
    return '$_temp0: $names';
  }

  @override
  String get onboardModeTitle => 'How will you use All In One POS?';

  @override
  String get onboardModeOfflineTitle => 'Offline';

  @override
  String get onboardModeOfflineBody =>
      'Start free with Sell + Inventory, no account needed. Add a license key anytime to unlock Premium.';

  @override
  String get onboardModeOnlineTitle => 'Online';

  @override
  String get onboardModeOnlineBody =>
      'Create a shop account with your email. Get a 2-month free trial, and manage staff and branches from Settings.';

  @override
  String get onboardModeCompareTitle =>
      'Online vs Offline — read before choosing';

  @override
  String get onboardModeAckLabel => 'I have read the differences';

  @override
  String get onboardModeChooseHint =>
      'This choice is permanent on this device. You cannot switch later in Settings.';

  @override
  String get onboardModeOnlineBullets =>
      '• Sign in with email on any device\n• Staff accounts, branches, and cloud sync\n• Free plan available; Premium unlocks more online features';

  @override
  String get onboardModeOfflineBullets =>
      '• Sell without an account or internet\n• License key lives on this device\n• Free plan available; Premium via a key — no multi-device account features';

  @override
  String get onboardOnlineTitle => 'Create your shop account';

  @override
  String get onboardOnlineBody =>
      'Your shop name, email, and a password — that\'s all you need to get started with a 2-month free trial.';

  @override
  String get onboardOnlineDone =>
      'Account created. Your free trial has started.';

  @override
  String get onboardOnlineCreateAccount => 'Create shop account';

  @override
  String get onboardOnlineSignInTitle => 'Sign in to your shop';

  @override
  String get onboardOnlineSignInBody =>
      'Use the email and password for an existing shop account.';

  @override
  String get onboardOnlineTabRegister => 'Register';

  @override
  String get onboardOnlineTabSignIn => 'Sign in';

  @override
  String get onboardOnlineSignedIn => 'Signed in. You can continue.';

  @override
  String get modeMigrateTitle => 'Confirm how this shop works';

  @override
  String get modeMigrateBody =>
      'All In One POS now uses a permanent Online or Offline mode. Confirm once — you cannot change it later in the app.';

  @override
  String get modeMigrateSuggestOnline =>
      'Suggested: Online (account / cloud features)';

  @override
  String get modeMigrateSuggestOffline =>
      'Suggested: Offline (this device + license key)';

  @override
  String get modeMigrateConfirm => 'Confirm and continue';

  @override
  String get dailyGateTitle => 'Start today\'s shop';

  @override
  String get dailyGateAccountStep => 'Account';

  @override
  String get dailyGateRoleStep => 'Who is using this device';

  @override
  String get dailyGateBranchStep => 'Branch';

  @override
  String get dailyGateOpeningStep => 'Opening amount';

  @override
  String get dailyGateContinue => 'Continue';

  @override
  String get dailyGateSkipOpening => 'Skip opening amount';

  @override
  String get dailyGateRoleOwner => 'Owner';

  @override
  String get dailyGateRoleStaff => 'Staff';

  @override
  String get dailyGateOpeningHint =>
      'Enter the cash in the drawer, or skip if you are not tracking the till today.';

  @override
  String get dailyGateContinueAsOwner => 'Continue as Owner';

  @override
  String get dailyGateContinueAsStaff => 'Continue as Staff';

  @override
  String get dailyGateOrSignIn => 'or sign in with an account';

  @override
  String get operatingModeLabel => 'Shop mode';

  @override
  String get licenseAccountLinked => 'Cloud account linked';

  @override
  String get operatingModeOnline => 'Online';

  @override
  String get operatingModeOffline => 'Offline';

  @override
  String get currencySymbol => 'Ks';
}
