import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_my.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('my'),
  ];

  /// Application title
  ///
  /// In en, this message translates to:
  /// **'MM POS'**
  String get appTitle;

  /// No description provided for @navSell.
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get navSell;

  /// No description provided for @navInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get navInventory;

  /// No description provided for @navInvoices.
  ///
  /// In en, this message translates to:
  /// **'Invoices'**
  String get navInvoices;

  /// No description provided for @navAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get navAnalytics;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @commonUnexpectedError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get commonUnexpectedError;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// No description provided for @commonYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get commonYes;

  /// No description provided for @commonNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get commonNo;

  /// No description provided for @commonTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get commonTotal;

  /// No description provided for @commonCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get commonCopy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @sellTitle.
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get sellTitle;

  /// No description provided for @sellStockCap.
  ///
  /// In en, this message translates to:
  /// **'Only {count} in stock'**
  String sellStockCap(int count);

  /// No description provided for @sellCart.
  ///
  /// In en, this message translates to:
  /// **'Cart'**
  String get sellCart;

  /// No description provided for @sellEmptyCart.
  ///
  /// In en, this message translates to:
  /// **'No items yet. Tap a product to add.'**
  String get sellEmptyCart;

  /// No description provided for @sellCheckout.
  ///
  /// In en, this message translates to:
  /// **'Checkout'**
  String get sellCheckout;

  /// No description provided for @sellSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get sellSubtotal;

  /// No description provided for @sellDiscount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get sellDiscount;

  /// No description provided for @sellItemDiscountTitle.
  ///
  /// In en, this message translates to:
  /// **'Discount for {item}'**
  String sellItemDiscountTitle(String item);

  /// No description provided for @sellPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get sellPaymentMethod;

  /// No description provided for @sellAmountPaid.
  ///
  /// In en, this message translates to:
  /// **'Amount paid'**
  String get sellAmountPaid;

  /// No description provided for @sellChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get sellChange;

  /// No description provided for @sellConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm sale'**
  String get sellConfirm;

  /// No description provided for @sellClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get sellClear;

  /// No description provided for @sellClearConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear the cart?'**
  String get sellClearConfirmTitle;

  /// No description provided for @sellClearConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Every item already added will be removed. This cannot be undone.'**
  String get sellClearConfirmBody;

  /// No description provided for @scanBarcode.
  ///
  /// In en, this message translates to:
  /// **'Scan barcode'**
  String get scanBarcode;

  /// No description provided for @scanTorch.
  ///
  /// In en, this message translates to:
  /// **'Flash'**
  String get scanTorch;

  /// No description provided for @scanFlip.
  ///
  /// In en, this message translates to:
  /// **'Flip camera'**
  String get scanFlip;

  /// No description provided for @scanHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at a barcode'**
  String get scanHint;

  /// No description provided for @scanAdded.
  ///
  /// In en, this message translates to:
  /// **'Added {name}'**
  String scanAdded(String name);

  /// No description provided for @scanNotFound.
  ///
  /// In en, this message translates to:
  /// **'No product for barcode {code}'**
  String scanNotFound(String code);

  /// No description provided for @sellCompleted.
  ///
  /// In en, this message translates to:
  /// **'Sale completed'**
  String get sellCompleted;

  /// No description provided for @sellInsufficientPaid.
  ///
  /// In en, this message translates to:
  /// **'Amount paid is less than total.'**
  String get sellInsufficientPaid;

  /// No description provided for @paymentCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get paymentCash;

  /// No description provided for @paymentKbzPay.
  ///
  /// In en, this message translates to:
  /// **'KBZPay'**
  String get paymentKbzPay;

  /// No description provided for @paymentWavePay.
  ///
  /// In en, this message translates to:
  /// **'WavePay'**
  String get paymentWavePay;

  /// No description provided for @paymentAyaPay.
  ///
  /// In en, this message translates to:
  /// **'AYAPay'**
  String get paymentAyaPay;

  /// No description provided for @paymentCbPay.
  ///
  /// In en, this message translates to:
  /// **'CBPay'**
  String get paymentCbPay;

  /// No description provided for @paymentCredit.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get paymentCredit;

  /// No description provided for @paymentCod.
  ///
  /// In en, this message translates to:
  /// **'COD (Cash on Delivery)'**
  String get paymentCod;

  /// No description provided for @cashRegisterTitle.
  ///
  /// In en, this message translates to:
  /// **'Cash register'**
  String get cashRegisterTitle;

  /// No description provided for @cashRegisterOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get cashRegisterOpen;

  /// No description provided for @cashRegisterClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get cashRegisterClosed;

  /// No description provided for @cashOpeningAmount.
  ///
  /// In en, this message translates to:
  /// **'Opening cash amount'**
  String get cashOpeningAmount;

  /// No description provided for @cashOpenRegister.
  ///
  /// In en, this message translates to:
  /// **'Open register'**
  String get cashOpenRegister;

  /// No description provided for @cashCloseRegister.
  ///
  /// In en, this message translates to:
  /// **'Close register'**
  String get cashCloseRegister;

  /// No description provided for @cashExpectedNow.
  ///
  /// In en, this message translates to:
  /// **'Expected cash now'**
  String get cashExpectedNow;

  /// No description provided for @cashOpenedAt.
  ///
  /// In en, this message translates to:
  /// **'Opened'**
  String get cashOpenedAt;

  /// No description provided for @cashClosingAmount.
  ///
  /// In en, this message translates to:
  /// **'Counted cash'**
  String get cashClosingAmount;

  /// No description provided for @cashCloseWarning.
  ///
  /// In en, this message translates to:
  /// **'Once closed, this count is final — the session and its variance can\'t be edited afterward.'**
  String get cashCloseWarning;

  /// No description provided for @cashVariance.
  ///
  /// In en, this message translates to:
  /// **'Variance'**
  String get cashVariance;

  /// No description provided for @cashVarianceShort.
  ///
  /// In en, this message translates to:
  /// **'Short by {amount}'**
  String cashVarianceShort(String amount);

  /// No description provided for @cashVarianceOver.
  ///
  /// In en, this message translates to:
  /// **'Over by {amount}'**
  String cashVarianceOver(String amount);

  /// No description provided for @cashVarianceExact.
  ///
  /// In en, this message translates to:
  /// **'Matches exactly'**
  String get cashVarianceExact;

  /// No description provided for @cashNote.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get cashNote;

  /// No description provided for @cashHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get cashHistory;

  /// No description provided for @cashNoSession.
  ///
  /// In en, this message translates to:
  /// **'The register isn\'t open yet.'**
  String get cashNoSession;

  /// No description provided for @cashNoHistory.
  ///
  /// In en, this message translates to:
  /// **'No past sessions yet.'**
  String get cashNoHistory;

  /// No description provided for @cashRegisterOpenedMsg.
  ///
  /// In en, this message translates to:
  /// **'Register opened'**
  String get cashRegisterOpenedMsg;

  /// No description provided for @cashRegisterClosedMsg.
  ///
  /// In en, this message translates to:
  /// **'Register closed'**
  String get cashRegisterClosedMsg;

  /// No description provided for @cashReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Cash Session Report'**
  String get cashReportTitle;

  /// No description provided for @cashClosedAt.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get cashClosedAt;

  /// No description provided for @cashReportPrintBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Print (Bluetooth)'**
  String get cashReportPrintBluetooth;

  /// No description provided for @cashReportSharePdf.
  ///
  /// In en, this message translates to:
  /// **'Share PDF'**
  String get cashReportSharePdf;

  /// No description provided for @cashReportCashSales.
  ///
  /// In en, this message translates to:
  /// **'Cash sales'**
  String get cashReportCashSales;

  /// No description provided for @cashReportCashRepayments.
  ///
  /// In en, this message translates to:
  /// **'Cash repayments'**
  String get cashReportCashRepayments;

  /// No description provided for @creditTitle.
  ///
  /// In en, this message translates to:
  /// **'Credit book'**
  String get creditTitle;

  /// No description provided for @creditCustomerName.
  ///
  /// In en, this message translates to:
  /// **'Customer name'**
  String get creditCustomerName;

  /// No description provided for @customerPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone (optional)'**
  String get customerPhone;

  /// No description provided for @phoneFormatHint.
  ///
  /// In en, this message translates to:
  /// **'Doesn\'t look like a Myanmar phone number (e.g. 09xxxxxxxxx) — you can still save it.'**
  String get phoneFormatHint;

  /// No description provided for @checkoutAddCustomer.
  ///
  /// In en, this message translates to:
  /// **'Add customer'**
  String get checkoutAddCustomer;

  /// No description provided for @checkoutSaveToDirectory.
  ///
  /// In en, this message translates to:
  /// **'Save to customer list'**
  String get checkoutSaveToDirectory;

  /// No description provided for @checkoutPickCustomer.
  ///
  /// In en, this message translates to:
  /// **'Pick from customers'**
  String get checkoutPickCustomer;

  /// No description provided for @checkoutTierPricingApplied.
  ///
  /// In en, this message translates to:
  /// **'{tier} pricing applied to this sale'**
  String checkoutTierPricingApplied(String tier);

  /// No description provided for @creditCustomerRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a customer name for a credit sale.'**
  String get creditCustomerRequired;

  /// No description provided for @creditPaidNow.
  ///
  /// In en, this message translates to:
  /// **'Paid now (optional)'**
  String get creditPaidNow;

  /// No description provided for @creditOwed.
  ///
  /// In en, this message translates to:
  /// **'Owed'**
  String get creditOwed;

  /// No description provided for @creditDeposit.
  ///
  /// In en, this message translates to:
  /// **'Deposit'**
  String get creditDeposit;

  /// No description provided for @creditBalanceDue.
  ///
  /// In en, this message translates to:
  /// **'Balance due'**
  String get creditBalanceDue;

  /// No description provided for @creditPreviousBalance.
  ///
  /// In en, this message translates to:
  /// **'Previous balance'**
  String get creditPreviousBalance;

  /// No description provided for @creditTotalBalanceDue.
  ///
  /// In en, this message translates to:
  /// **'Total balance due'**
  String get creditTotalBalanceDue;

  /// No description provided for @creditTotalOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Total outstanding'**
  String get creditTotalOutstanding;

  /// No description provided for @creditTotalDue.
  ///
  /// In en, this message translates to:
  /// **'{amount} outstanding'**
  String creditTotalDue(String amount);

  /// No description provided for @creditNoneDue.
  ///
  /// In en, this message translates to:
  /// **'No outstanding credit'**
  String get creditNoneDue;

  /// No description provided for @creditEmpty.
  ///
  /// In en, this message translates to:
  /// **'No one owes you right now.'**
  String get creditEmpty;

  /// No description provided for @creditOpenInvoices.
  ///
  /// In en, this message translates to:
  /// **'{count} open {count, plural, one{invoice} other{invoices}}'**
  String creditOpenInvoices(int count);

  /// No description provided for @creditOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Outstanding'**
  String get creditOutstanding;

  /// No description provided for @creditInvoices.
  ///
  /// In en, this message translates to:
  /// **'Credit invoices'**
  String get creditInvoices;

  /// No description provided for @creditSettled.
  ///
  /// In en, this message translates to:
  /// **'Settled'**
  String get creditSettled;

  /// No description provided for @creditFilterOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Outstanding'**
  String get creditFilterOutstanding;

  /// No description provided for @creditFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get creditFilterAll;

  /// No description provided for @creditRepayments.
  ///
  /// In en, this message translates to:
  /// **'Repayments'**
  String get creditRepayments;

  /// No description provided for @creditRecordRepayment.
  ///
  /// In en, this message translates to:
  /// **'Record repayment'**
  String get creditRecordRepayment;

  /// No description provided for @creditAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get creditAmount;

  /// No description provided for @creditRepaymentExceedsOutstanding.
  ///
  /// In en, this message translates to:
  /// **'This is more than the amount owed ({outstanding}).'**
  String creditRepaymentExceedsOutstanding(String outstanding);

  /// No description provided for @creditRepaymentSaved.
  ///
  /// In en, this message translates to:
  /// **'Repayment recorded'**
  String get creditRepaymentSaved;

  /// No description provided for @customersTitle.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get customersTitle;

  /// No description provided for @customersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No customers yet. Add your first customer.'**
  String get customersEmpty;

  /// No description provided for @customersSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search name or phone'**
  String get customersSearchHint;

  /// No description provided for @customerAdd.
  ///
  /// In en, this message translates to:
  /// **'Add customer'**
  String get customerAdd;

  /// No description provided for @customerEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit customer'**
  String get customerEdit;

  /// No description provided for @customerNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get customerNameLabel;

  /// No description provided for @customerAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get customerAddress;

  /// No description provided for @customerTierLabel.
  ///
  /// In en, this message translates to:
  /// **'Pricing tier'**
  String get customerTierLabel;

  /// No description provided for @customerTierRetail.
  ///
  /// In en, this message translates to:
  /// **'Retail'**
  String get customerTierRetail;

  /// No description provided for @customerTierWholesale.
  ///
  /// In en, this message translates to:
  /// **'Wholesale'**
  String get customerTierWholesale;

  /// No description provided for @customerTierVip.
  ///
  /// In en, this message translates to:
  /// **'VIP'**
  String get customerTierVip;

  /// No description provided for @customerSaved.
  ///
  /// In en, this message translates to:
  /// **'Customer saved'**
  String get customerSaved;

  /// No description provided for @customerDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove this customer?'**
  String get customerDeleteConfirmTitle;

  /// No description provided for @customerDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{name} will no longer appear as a suggestion at checkout. Past invoices still show their name.'**
  String customerDeleteConfirmBody(String name);

  /// No description provided for @customerDeleted.
  ///
  /// In en, this message translates to:
  /// **'Customer removed'**
  String get customerDeleted;

  /// No description provided for @suppliersTitle.
  ///
  /// In en, this message translates to:
  /// **'Suppliers'**
  String get suppliersTitle;

  /// No description provided for @suppliersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No suppliers yet. Add your first supplier.'**
  String get suppliersEmpty;

  /// No description provided for @supplierAdd.
  ///
  /// In en, this message translates to:
  /// **'Add supplier'**
  String get supplierAdd;

  /// No description provided for @supplierEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit supplier'**
  String get supplierEdit;

  /// No description provided for @supplierNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Supplier name'**
  String get supplierNameLabel;

  /// No description provided for @supplierSaved.
  ///
  /// In en, this message translates to:
  /// **'Supplier saved'**
  String get supplierSaved;

  /// No description provided for @supplierDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove this supplier?'**
  String get supplierDeleteConfirmTitle;

  /// No description provided for @supplierDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{name} will no longer appear as a suggestion on new purchase orders. Past purchase orders still show their name.'**
  String supplierDeleteConfirmBody(String name);

  /// No description provided for @supplierDeleted.
  ///
  /// In en, this message translates to:
  /// **'Supplier removed'**
  String get supplierDeleted;

  /// No description provided for @purchaseOrdersTitle.
  ///
  /// In en, this message translates to:
  /// **'Purchase orders'**
  String get purchaseOrdersTitle;

  /// No description provided for @purchaseOrdersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No purchase orders yet.'**
  String get purchaseOrdersEmpty;

  /// No description provided for @poCreate.
  ///
  /// In en, this message translates to:
  /// **'Create purchase order'**
  String get poCreate;

  /// No description provided for @poItems.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get poItems;

  /// No description provided for @poNoItems.
  ///
  /// In en, this message translates to:
  /// **'No items added yet — tap + to add a product.'**
  String get poNoItems;

  /// No description provided for @poRemoveLineConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove this item from the draft?'**
  String get poRemoveLineConfirmTitle;

  /// No description provided for @poUnitCost.
  ///
  /// In en, this message translates to:
  /// **'Unit cost'**
  String get poUnitCost;

  /// No description provided for @poSaveDraft.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get poSaveDraft;

  /// No description provided for @poSaved.
  ///
  /// In en, this message translates to:
  /// **'Purchase order saved.'**
  String get poSaved;

  /// No description provided for @poNeedsSupplier.
  ///
  /// In en, this message translates to:
  /// **'Enter a supplier name.'**
  String get poNeedsSupplier;

  /// No description provided for @poNeedsItems.
  ///
  /// In en, this message translates to:
  /// **'Add at least one item before saving.'**
  String get poNeedsItems;

  /// No description provided for @poNoProductsFound.
  ///
  /// In en, this message translates to:
  /// **'No products found.'**
  String get poNoProductsFound;

  /// No description provided for @poStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get poStatusOpen;

  /// No description provided for @poStatusReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get poStatusReceived;

  /// No description provided for @poStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get poStatusCancelled;

  /// No description provided for @poMarkReceived.
  ///
  /// In en, this message translates to:
  /// **'Mark as received'**
  String get poMarkReceived;

  /// No description provided for @poReceiveConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Mark this purchase order as received?'**
  String get poReceiveConfirmTitle;

  /// No description provided for @poReceiveConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This adds every item\'s ordered quantity to stock at its ordered cost. This can\'t be undone.'**
  String get poReceiveConfirmBody;

  /// No description provided for @poReceived.
  ///
  /// In en, this message translates to:
  /// **'Purchase order received — stock updated.'**
  String get poReceived;

  /// No description provided for @poCancelOrder.
  ///
  /// In en, this message translates to:
  /// **'Cancel purchase order'**
  String get poCancelOrder;

  /// No description provided for @poCancelConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this purchase order? Stock will not be affected.'**
  String get poCancelConfirmTitle;

  /// No description provided for @poDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this purchase order?'**
  String get poDeleteConfirmTitle;

  /// No description provided for @poDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes the draft and its line items. This cannot be undone.'**
  String get poDeleteConfirmBody;

  /// No description provided for @inventoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get inventoryTitle;

  /// No description provided for @inventoryExportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get inventoryExportCsv;

  /// No description provided for @inventoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No products yet. Add your first product.'**
  String get inventoryEmpty;

  /// No description provided for @inventoryLowStock.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get inventoryLowStock;

  /// No description provided for @inventoryAddProduct.
  ///
  /// In en, this message translates to:
  /// **'Add product'**
  String get inventoryAddProduct;

  /// No description provided for @inventoryEditProduct.
  ///
  /// In en, this message translates to:
  /// **'Edit product'**
  String get inventoryEditProduct;

  /// No description provided for @inventoryNoResults.
  ///
  /// In en, this message translates to:
  /// **'No products match your search.'**
  String get inventoryNoResults;

  /// No description provided for @productName.
  ///
  /// In en, this message translates to:
  /// **'Product name'**
  String get productName;

  /// No description provided for @productPhoto.
  ///
  /// In en, this message translates to:
  /// **'Product photo'**
  String get productPhoto;

  /// No description provided for @productPrice.
  ///
  /// In en, this message translates to:
  /// **'Sale price'**
  String get productPrice;

  /// No description provided for @productCost.
  ///
  /// In en, this message translates to:
  /// **'Cost price'**
  String get productCost;

  /// No description provided for @productTierPricesHint.
  ///
  /// In en, this message translates to:
  /// **'Optional — leave blank to use the sale price for that tier.'**
  String get productTierPricesHint;

  /// No description provided for @productWholesalePrice.
  ///
  /// In en, this message translates to:
  /// **'Wholesale price'**
  String get productWholesalePrice;

  /// No description provided for @productVipPrice.
  ///
  /// In en, this message translates to:
  /// **'VIP price'**
  String get productVipPrice;

  /// No description provided for @productOnlineStockLimitHint.
  ///
  /// In en, this message translates to:
  /// **'Optional — cap how many of this product your web storefront may sell, separate from your real in-store stock. Leave blank for no cap.'**
  String get productOnlineStockLimitHint;

  /// No description provided for @productOnlineStockLimit.
  ///
  /// In en, this message translates to:
  /// **'Online stock limit'**
  String get productOnlineStockLimit;

  /// No description provided for @productBarcode.
  ///
  /// In en, this message translates to:
  /// **'Barcode'**
  String get productBarcode;

  /// No description provided for @productSku.
  ///
  /// In en, this message translates to:
  /// **'SKU'**
  String get productSku;

  /// No description provided for @productStock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get productStock;

  /// No description provided for @productQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get productQuantity;

  /// No description provided for @productReorderLevel.
  ///
  /// In en, this message translates to:
  /// **'Reorder level'**
  String get productReorderLevel;

  /// No description provided for @productUnit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get productUnit;

  /// No description provided for @inventoryUpdateStock.
  ///
  /// In en, this message translates to:
  /// **'Update stock'**
  String get inventoryUpdateStock;

  /// No description provided for @stockAdjustTitle.
  ///
  /// In en, this message translates to:
  /// **'Update stock'**
  String get stockAdjustTitle;

  /// No description provided for @stockAdjustModeRestock.
  ///
  /// In en, this message translates to:
  /// **'Restock'**
  String get stockAdjustModeRestock;

  /// No description provided for @stockAdjustModeAdjust.
  ///
  /// In en, this message translates to:
  /// **'Adjust'**
  String get stockAdjustModeAdjust;

  /// No description provided for @stockAdjustQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get stockAdjustQuantity;

  /// No description provided for @stockAdjustQuantityHintRestock.
  ///
  /// In en, this message translates to:
  /// **'Units received'**
  String get stockAdjustQuantityHintRestock;

  /// No description provided for @stockAdjustQuantityHintAdjust.
  ///
  /// In en, this message translates to:
  /// **'+ to increase, − to decrease'**
  String get stockAdjustQuantityHintAdjust;

  /// No description provided for @stockAdjustUnitCost.
  ///
  /// In en, this message translates to:
  /// **'Unit cost (optional)'**
  String get stockAdjustUnitCost;

  /// No description provided for @stockAdjustUnitCostHint.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to use the product\'s cost price'**
  String get stockAdjustUnitCostHint;

  /// No description provided for @stockAdjustReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get stockAdjustReason;

  /// No description provided for @stockAdjustNote.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get stockAdjustNote;

  /// No description provided for @stockAdjustSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get stockAdjustSave;

  /// No description provided for @stockAdjustInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid quantity'**
  String get stockAdjustInvalid;

  /// No description provided for @stockAdjustBelowZero.
  ///
  /// In en, this message translates to:
  /// **'This would take stock below zero (currently {quantity}).'**
  String stockAdjustBelowZero(int quantity);

  /// No description provided for @stockAdjustCurrentStock.
  ///
  /// In en, this message translates to:
  /// **'Current stock: {quantity}'**
  String stockAdjustCurrentStock(int quantity);

  /// No description provided for @stockAdjustConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm stock change'**
  String get stockAdjustConfirmTitle;

  /// No description provided for @stockAdjustConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{name}: stock changes from {before} to {after}. This is recorded in stock history but not automatically reversible.'**
  String stockAdjustConfirmBody(String name, int before, int after);

  /// No description provided for @stockReasonDamaged.
  ///
  /// In en, this message translates to:
  /// **'Damaged'**
  String get stockReasonDamaged;

  /// No description provided for @stockReasonLost.
  ///
  /// In en, this message translates to:
  /// **'Lost / stolen'**
  String get stockReasonLost;

  /// No description provided for @stockReasonCount.
  ///
  /// In en, this message translates to:
  /// **'Stock count correction'**
  String get stockReasonCount;

  /// No description provided for @stockReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get stockReasonOther;

  /// No description provided for @stockHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Stock history'**
  String get stockHistoryTitle;

  /// No description provided for @stockHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No stock movements yet.'**
  String get stockHistoryEmpty;

  /// No description provided for @stockHistoryPickDateRange.
  ///
  /// In en, this message translates to:
  /// **'Pick date range'**
  String get stockHistoryPickDateRange;

  /// No description provided for @stockHistoryClearDateRange.
  ///
  /// In en, this message translates to:
  /// **'Clear date range'**
  String get stockHistoryClearDateRange;

  /// No description provided for @stockMovementOpening.
  ///
  /// In en, this message translates to:
  /// **'Opening balance'**
  String get stockMovementOpening;

  /// No description provided for @stockMovementSale.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get stockMovementSale;

  /// No description provided for @stockMovementReturn.
  ///
  /// In en, this message translates to:
  /// **'Refund return'**
  String get stockMovementReturn;

  /// No description provided for @stockMovementPurchase.
  ///
  /// In en, this message translates to:
  /// **'Restock'**
  String get stockMovementPurchase;

  /// No description provided for @stockMovementAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Adjustment'**
  String get stockMovementAdjustment;

  /// No description provided for @productViewStockHistory.
  ///
  /// In en, this message translates to:
  /// **'View stock history'**
  String get productViewStockHistory;

  /// No description provided for @validationRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get validationRequired;

  /// No description provided for @deleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete?'**
  String get deleteConfirmTitle;

  /// No description provided for @deleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This item will be removed.'**
  String get deleteConfirmBody;

  /// No description provided for @productDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'It will be hidden from Sell and Inventory, but stays visible on past sales, invoices, and stock history.'**
  String get productDeleteConfirmBody;

  /// No description provided for @categoryDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Products in this category keep their prices and stock, but show as uncategorized.'**
  String get categoryDeleteConfirmBody;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSectionBusiness.
  ///
  /// In en, this message translates to:
  /// **'Business'**
  String get settingsSectionBusiness;

  /// No description provided for @settingsSectionFinance.
  ///
  /// In en, this message translates to:
  /// **'Finance'**
  String get settingsSectionFinance;

  /// No description provided for @settingsSectionDevice.
  ///
  /// In en, this message translates to:
  /// **'Device & Staff'**
  String get settingsSectionDevice;

  /// No description provided for @settingsSectionHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get settingsSectionHelp;

  /// No description provided for @settingsSectionOwnerTools.
  ///
  /// In en, this message translates to:
  /// **'Owner Tools'**
  String get settingsSectionOwnerTools;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsPrinter.
  ///
  /// In en, this message translates to:
  /// **'Printer'**
  String get settingsPrinter;

  /// No description provided for @settingsShop.
  ///
  /// In en, this message translates to:
  /// **'Shop profile'**
  String get settingsShop;

  /// No description provided for @settingsLicense.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get settingsLicense;

  /// No description provided for @settingsSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get settingsSupport;

  /// No description provided for @settingsAppGuide.
  ///
  /// In en, this message translates to:
  /// **'App Guide'**
  String get settingsAppGuide;

  /// No description provided for @helpGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'App Guide'**
  String get helpGuideTitle;

  /// No description provided for @helpGuideIntro.
  ///
  /// In en, this message translates to:
  /// **'A quick tour of what each screen does. Tap a section to expand it.'**
  String get helpGuideIntro;

  /// No description provided for @helpGuideSellTitle.
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get helpGuideSellTitle;

  /// No description provided for @helpGuideSellBody.
  ///
  /// In en, this message translates to:
  /// **'1. Tap a product tile to add it to the cart, or use the scan icon to add it by barcode.\n2. Tap a line in the cart to change its quantity, or remove it.\n3. If this customer has a Wholesale/VIP pricing tier, pick them in the customer field — prices update automatically.\n4. Tap \"Checkout\" to open the payment sheet.\n5. Add a discount if needed, then choose a payment method (Cash, KBZPay, WavePay, AYAPay, CBPay, or Credit).\n6. For a Credit sale, enter the customer\'s name (required) and any amount paid now.\n7. Confirm the sale — stock updates automatically, a receipt prints if a printer is connected, and the sale is recorded for Analytics.'**
  String get helpGuideSellBody;

  /// No description provided for @helpGuideInventoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get helpGuideInventoryTitle;

  /// No description provided for @helpGuideInventoryBody.
  ///
  /// In en, this message translates to:
  /// **'1. Tap \"Add product\" to create one: name, photo, sale price, cost price, barcode/SKU, starting stock, and reorder level.\n2. Optionally set Wholesale/VIP prices — leave them blank to use the sale price for those tiers.\n3. Tap any product to edit its details later.\n4. Tap the stock icon to open Restock/Adjust: \"Restock\" adds purchased stock (with an optional unit cost); \"Adjust\" corrects a count with a reason (damaged, lost, count correction).\n5. Tap \"View stock history\" to see every past stock movement for that product.\n6. Products below their reorder level show a \"Low stock\" badge automatically.\n7. Tap the print icon to print a barcode label, on your receipt printer or a dedicated label printer.'**
  String get helpGuideInventoryBody;

  /// No description provided for @helpGuideOrdersTitle.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get helpGuideOrdersTitle;

  /// No description provided for @helpGuideOrdersBody.
  ///
  /// In en, this message translates to:
  /// **'1. Orders show as cards on a board — New, Confirmed, Packed, Shipped, Delivered.\n2. Tap \"+\" to add one manually: customer, channel (Facebook, Web, etc.), items, and payment method (cash-on-delivery or transfer).\n3. Drag a card to a new column, or use its \"⋮\" menu to jump straight to any status.\n4. Tap a card to see full details: items, delivery info, and the payment-proof photo for transfer orders.\n5. Use \"Mark as paid\"/\"Mark as unpaid\" to track payment separately from delivery progress.\n6. Once fulfilled, tap \"Convert to sale\" to move it into your sales ledger and stock.\n7. Orders placed by customers on your online storefront appear here automatically — nothing to type in yourself.'**
  String get helpGuideOrdersBody;

  /// No description provided for @helpGuideInvoicesTitle.
  ///
  /// In en, this message translates to:
  /// **'Invoices'**
  String get helpGuideInvoicesTitle;

  /// No description provided for @helpGuideInvoicesBody.
  ///
  /// In en, this message translates to:
  /// **'1. Every completed sale appears here as an invoice, newest first.\n2. Tap an invoice to see its full details: items, customer, payment method, and status.\n3. For a Credit sale, record a partial or full repayment right from the invoice detail screen.\n4. Overdue credit invoices are highlighted so you know who to follow up with.\n5. Tap \"Refund\" to reverse a sale — stock and the customer\'s credit balance are restored automatically.\n6. Use the search bar, or the scan icon, to find an invoice by number, customer name, or phone.\n7. Every invoice carries a barcode for a quick lookup later.'**
  String get helpGuideInvoicesBody;

  /// No description provided for @helpGuideAnalyticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get helpGuideAnalyticsTitle;

  /// No description provided for @helpGuideAnalyticsBody.
  ///
  /// In en, this message translates to:
  /// **'Analytics is a Premium feature — a Free-plan shop sees an upgrade prompt here instead of this screen.\n1. Pick a date range at the top — today, this week, this month, or a custom range.\n2. View total sales, profit, and transaction count for that period.\n3. Scroll down to see your best-selling products, ranked by revenue or quantity.\n4. Profit figures use each sale\'s actual recorded cost, not just today\'s cost price — so past sales stay accurate even after you change a product\'s cost.\n5. Compare two periods side by side to spot trends before deciding what to restock or re-price.'**
  String get helpGuideAnalyticsBody;

  /// No description provided for @helpGuideSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get helpGuideSettingsTitle;

  /// No description provided for @helpGuideSettingsBody.
  ///
  /// In en, this message translates to:
  /// **'1. \"Shop profile\" — your shop name, logo, address, and contact info, shown on receipts and your storefront.\n2. \"Printer\"/\"Label printer\" — pair your Bluetooth receipt or label printer.\n3. \"License\" — the Free plan works forever, no key or account needed (Sell, Inventory, and more). Tap \"Upgrade\" to unlock Premium features (Analytics, Suppliers, Staff accounts, and more) — pay via KBZPay/WavePay for a license key, or subscribe under your Shop Login account.\n4. \"Shop Login\" (optional) — sign in with email + password to reach this shop from another device, and to subscribe online instead of using a key. Forgot your password? Tap \"Forgot password?\" on the sign-in screen.\n5. \"Pricing tier\" — tap the ⓘ icon to see what\'s different between the Online (account) and Offline (key) plans.\n6. \"My web storefront\" — turn on your online shop and set your KBZPay/WavePay payment details.\n7. \"Owner Tools\" (once you have 2+ devices) — hand this device to a staff member, or switch back to Owner with your PIN.\n8. \"Sync\" — check your connection to the cloud, or force an immediate sync.\n9. Switch the app\'s language between English and Myanmar any time, from the dropdown at the top of this screen.'**
  String get helpGuideSettingsBody;

  /// No description provided for @settingsTrackStock.
  ///
  /// In en, this message translates to:
  /// **'Track stock'**
  String get settingsTrackStock;

  /// No description provided for @settingsTrackStockHint.
  ///
  /// In en, this message translates to:
  /// **'Off = invoice only (no stock counts or alerts).'**
  String get settingsTrackStockHint;

  /// No description provided for @settingsAskCustomer.
  ///
  /// In en, this message translates to:
  /// **'Ask for customer'**
  String get settingsAskCustomer;

  /// No description provided for @settingsAskCustomerHint.
  ///
  /// In en, this message translates to:
  /// **'Show optional customer name + phone at checkout.'**
  String get settingsAskCustomerHint;

  /// No description provided for @shopProfileHint.
  ///
  /// In en, this message translates to:
  /// **'Shown on printed receipts.'**
  String get shopProfileHint;

  /// No description provided for @shopLogo.
  ///
  /// In en, this message translates to:
  /// **'Shop logo'**
  String get shopLogo;

  /// No description provided for @shopName.
  ///
  /// In en, this message translates to:
  /// **'Shop name'**
  String get shopName;

  /// No description provided for @shopAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get shopAddress;

  /// No description provided for @shopPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get shopPhone;

  /// No description provided for @receiptFooter.
  ///
  /// In en, this message translates to:
  /// **'Receipt footer'**
  String get receiptFooter;

  /// No description provided for @shopProfileSaved.
  ///
  /// In en, this message translates to:
  /// **'Shop profile saved'**
  String get shopProfileSaved;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageMyanmar.
  ///
  /// In en, this message translates to:
  /// **'Myanmar'**
  String get languageMyanmar;

  /// No description provided for @invoicesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No sales yet.'**
  String get invoicesEmpty;

  /// No description provided for @invoiceFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get invoiceFilterAll;

  /// No description provided for @invoiceFilterCredit.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get invoiceFilterCredit;

  /// No description provided for @invoiceOwed.
  ///
  /// In en, this message translates to:
  /// **'Owed {amount}'**
  String invoiceOwed(String amount);

  /// No description provided for @invoicePrint.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get invoicePrint;

  /// No description provided for @invoiceReprint.
  ///
  /// In en, this message translates to:
  /// **'Reprint'**
  String get invoiceReprint;

  /// No description provided for @invoiceDetail.
  ///
  /// In en, this message translates to:
  /// **'Invoice'**
  String get invoiceDetail;

  /// No description provided for @invoiceSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search invoice #, customer, phone'**
  String get invoiceSearchHint;

  /// No description provided for @invoiceScanToSearch.
  ///
  /// In en, this message translates to:
  /// **'Scan barcode'**
  String get invoiceScanToSearch;

  /// No description provided for @invoiceRefund.
  ///
  /// In en, this message translates to:
  /// **'Refund'**
  String get invoiceRefund;

  /// No description provided for @invoiceDevice.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get invoiceDevice;

  /// No description provided for @invoiceDeviceUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Unnamed device'**
  String get invoiceDeviceUnnamed;

  /// No description provided for @invoiceRefunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get invoiceRefunded;

  /// No description provided for @invoiceRefundConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Refund this invoice?'**
  String get invoiceRefundConfirmTitle;

  /// No description provided for @invoiceRefundConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This reverses the sale, restores stock, and cannot be undone.'**
  String get invoiceRefundConfirmBody;

  /// No description provided for @invoiceRefundOf.
  ///
  /// In en, this message translates to:
  /// **'Refund of {invoiceNo}'**
  String invoiceRefundOf(String invoiceNo);

  /// No description provided for @invoiceRefundSuccess.
  ///
  /// In en, this message translates to:
  /// **'Refunded ({refundNo}).'**
  String invoiceRefundSuccess(String refundNo);

  /// No description provided for @invoiceAlreadyRefunded.
  ///
  /// In en, this message translates to:
  /// **'This invoice was already refunded.'**
  String get invoiceAlreadyRefunded;

  /// No description provided for @salesReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Sales report'**
  String get salesReportTitle;

  /// No description provided for @salesReportAllDates.
  ///
  /// In en, this message translates to:
  /// **'All dates'**
  String get salesReportAllDates;

  /// No description provided for @salesReportEmpty.
  ///
  /// In en, this message translates to:
  /// **'No sales in this range.'**
  String get salesReportEmpty;

  /// No description provided for @salesReportTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get salesReportTotal;

  /// No description provided for @salesReportColumnInvoice.
  ///
  /// In en, this message translates to:
  /// **'Invoice #'**
  String get salesReportColumnInvoice;

  /// No description provided for @salesReportColumnDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get salesReportColumnDate;

  /// No description provided for @salesReportColumnCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get salesReportColumnCustomer;

  /// No description provided for @salesReportColumnAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get salesReportColumnAddress;

  /// No description provided for @salesReportColumnAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get salesReportColumnAmount;

  /// No description provided for @salesReportPrintBluetooth.
  ///
  /// In en, this message translates to:
  /// **'Print (Bluetooth)'**
  String get salesReportPrintBluetooth;

  /// No description provided for @salesReportExportPdf.
  ///
  /// In en, this message translates to:
  /// **'Export PDF'**
  String get salesReportExportPdf;

  /// No description provided for @salesReportExportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get salesReportExportCsv;

  /// No description provided for @salesReportNoPrinter.
  ///
  /// In en, this message translates to:
  /// **'No Bluetooth printer set up — see Printer settings.'**
  String get salesReportNoPrinter;

  /// No description provided for @salesReportCount.
  ///
  /// In en, this message translates to:
  /// **'{count} sales'**
  String salesReportCount(int count);

  /// No description provided for @printerSettings.
  ///
  /// In en, this message translates to:
  /// **'Printer settings'**
  String get printerSettings;

  /// No description provided for @printerSelectDevice.
  ///
  /// In en, this message translates to:
  /// **'Select printer'**
  String get printerSelectDevice;

  /// No description provided for @printerPaperSize.
  ///
  /// In en, this message translates to:
  /// **'Paper size'**
  String get printerPaperSize;

  /// No description provided for @printerTestPrint.
  ///
  /// In en, this message translates to:
  /// **'Test print'**
  String get printerTestPrint;

  /// No description provided for @printerNone.
  ///
  /// In en, this message translates to:
  /// **'No printer selected'**
  String get printerNone;

  /// No description provided for @printerPaired.
  ///
  /// In en, this message translates to:
  /// **'Paired devices'**
  String get printerPaired;

  /// No description provided for @printSuccess.
  ///
  /// In en, this message translates to:
  /// **'Printed successfully'**
  String get printSuccess;

  /// No description provided for @printFailed.
  ///
  /// In en, this message translates to:
  /// **'Print failed'**
  String get printFailed;

  /// No description provided for @bluetoothOff.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is off. Turn it on and pair your printer.'**
  String get bluetoothOff;

  /// No description provided for @receiptInvoice.
  ///
  /// In en, this message translates to:
  /// **'Invoice'**
  String get receiptInvoice;

  /// No description provided for @receiptDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get receiptDate;

  /// No description provided for @receiptCashier.
  ///
  /// In en, this message translates to:
  /// **'Cashier'**
  String get receiptCashier;

  /// No description provided for @receiptCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get receiptCustomer;

  /// No description provided for @receiptPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get receiptPhone;

  /// No description provided for @receiptThankYou.
  ///
  /// In en, this message translates to:
  /// **'Thank you for your patronage!'**
  String get receiptThankYou;

  /// No description provided for @paper58.
  ///
  /// In en, this message translates to:
  /// **'58 mm'**
  String get paper58;

  /// No description provided for @paper80.
  ///
  /// In en, this message translates to:
  /// **'80 mm'**
  String get paper80;

  /// No description provided for @printerPdfPaperSize.
  ///
  /// In en, this message translates to:
  /// **'Document paper size'**
  String get printerPdfPaperSize;

  /// No description provided for @printerPdfPaperSizeHint.
  ///
  /// In en, this message translates to:
  /// **'For invoices/reports printed via AirPrint or a computer, not the thermal printer above.'**
  String get printerPdfPaperSizeHint;

  /// No description provided for @paperA4.
  ///
  /// In en, this message translates to:
  /// **'A4'**
  String get paperA4;

  /// No description provided for @paperA5.
  ///
  /// In en, this message translates to:
  /// **'A5'**
  String get paperA5;

  /// No description provided for @settingsLabelPrinter.
  ///
  /// In en, this message translates to:
  /// **'Label printer'**
  String get settingsLabelPrinter;

  /// No description provided for @settingsDeviceName.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get settingsDeviceName;

  /// No description provided for @settingsDeviceNameUnset.
  ///
  /// In en, this message translates to:
  /// **'Not set — tap to name this device'**
  String get settingsDeviceNameUnset;

  /// No description provided for @settingsDeviceNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Counter A, Owner\'s phone'**
  String get settingsDeviceNameHint;

  /// No description provided for @labelPrinterSettings.
  ///
  /// In en, this message translates to:
  /// **'Label printer settings'**
  String get labelPrinterSettings;

  /// No description provided for @labelPrinterSize.
  ///
  /// In en, this message translates to:
  /// **'Label size'**
  String get labelPrinterSize;

  /// No description provided for @labelSize40x30.
  ///
  /// In en, this message translates to:
  /// **'40 x 30 mm'**
  String get labelSize40x30;

  /// No description provided for @labelSize50x30.
  ///
  /// In en, this message translates to:
  /// **'50 x 30 mm'**
  String get labelSize50x30;

  /// No description provided for @labelSize50x40.
  ///
  /// In en, this message translates to:
  /// **'50 x 40 mm'**
  String get labelSize50x40;

  /// No description provided for @inventoryPrintLabel.
  ///
  /// In en, this message translates to:
  /// **'Print label'**
  String get inventoryPrintLabel;

  /// No description provided for @labelPrintDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Print label'**
  String get labelPrintDialogTitle;

  /// No description provided for @labelCopies.
  ///
  /// In en, this message translates to:
  /// **'Copies'**
  String get labelCopies;

  /// No description provided for @labelPrintTargetStrip.
  ///
  /// In en, this message translates to:
  /// **'Prints as a strip on the receipt printer'**
  String get labelPrintTargetStrip;

  /// No description provided for @labelPrintTargetDedicated.
  ///
  /// In en, this message translates to:
  /// **'Prints on the label printer'**
  String get labelPrintTargetDedicated;

  /// No description provided for @labelPrintNoTarget.
  ///
  /// In en, this message translates to:
  /// **'No printer connected. Set one up in Settings.'**
  String get labelPrintNoTarget;

  /// No description provided for @categoriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categoriesTitle;

  /// No description provided for @manageCategories.
  ///
  /// In en, this message translates to:
  /// **'Manage categories'**
  String get manageCategories;

  /// No description provided for @categoryAdd.
  ///
  /// In en, this message translates to:
  /// **'Add category'**
  String get categoryAdd;

  /// No description provided for @categoryEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit category'**
  String get categoryEdit;

  /// No description provided for @categoryName.
  ///
  /// In en, this message translates to:
  /// **'Category name'**
  String get categoryName;

  /// No description provided for @categoryNone.
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get categoryNone;

  /// No description provided for @categoryAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get categoryAll;

  /// No description provided for @categoriesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No categories yet.'**
  String get categoriesEmpty;

  /// No description provided for @productCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get productCategory;

  /// No description provided for @analyticsRevenue.
  ///
  /// In en, this message translates to:
  /// **'Revenue'**
  String get analyticsRevenue;

  /// No description provided for @analyticsProfit.
  ///
  /// In en, this message translates to:
  /// **'Gross profit'**
  String get analyticsProfit;

  /// No description provided for @analyticsExpenses.
  ///
  /// In en, this message translates to:
  /// **'Total expenses'**
  String get analyticsExpenses;

  /// No description provided for @analyticsNetProfit.
  ///
  /// In en, this message translates to:
  /// **'Net profit'**
  String get analyticsNetProfit;

  /// No description provided for @analyticsSalesCount.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get analyticsSalesCount;

  /// No description provided for @analyticsStockValue.
  ///
  /// In en, this message translates to:
  /// **'Stock value'**
  String get analyticsStockValue;

  /// No description provided for @analyticsDiscountGiven.
  ///
  /// In en, this message translates to:
  /// **'Discounts'**
  String get analyticsDiscountGiven;

  /// No description provided for @analyticsTopProducts.
  ///
  /// In en, this message translates to:
  /// **'Top products'**
  String get analyticsTopProducts;

  /// No description provided for @analyticsRangeToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get analyticsRangeToday;

  /// No description provided for @analyticsRangeWeek.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get analyticsRangeWeek;

  /// No description provided for @analyticsRangeMonth.
  ///
  /// In en, this message translates to:
  /// **'30 days'**
  String get analyticsRangeMonth;

  /// No description provided for @analyticsNoData.
  ///
  /// In en, this message translates to:
  /// **'No sales in this period.'**
  String get analyticsNoData;

  /// No description provided for @analyticsDailyRevenue.
  ///
  /// In en, this message translates to:
  /// **'Daily revenue'**
  String get analyticsDailyRevenue;

  /// No description provided for @analyticsCollected.
  ///
  /// In en, this message translates to:
  /// **'Collected'**
  String get analyticsCollected;

  /// No description provided for @analyticsCreditOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Credit outstanding'**
  String get analyticsCreditOutstanding;

  /// No description provided for @expensesTitle.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expensesTitle;

  /// No description provided for @expensesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No expenses logged for this period.'**
  String get expensesEmpty;

  /// No description provided for @expensesTotal.
  ///
  /// In en, this message translates to:
  /// **'Total expenses'**
  String get expensesTotal;

  /// No description provided for @expenseAdd.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get expenseAdd;

  /// No description provided for @expenseEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit expense'**
  String get expenseEdit;

  /// No description provided for @expenseAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get expenseAmount;

  /// No description provided for @expenseNote.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get expenseNote;

  /// No description provided for @expenseCategoryRent.
  ///
  /// In en, this message translates to:
  /// **'Rent'**
  String get expenseCategoryRent;

  /// No description provided for @expenseCategoryUtilities.
  ///
  /// In en, this message translates to:
  /// **'Utilities'**
  String get expenseCategoryUtilities;

  /// No description provided for @expenseCategoryWages.
  ///
  /// In en, this message translates to:
  /// **'Staff wages'**
  String get expenseCategoryWages;

  /// No description provided for @expenseCategoryTransport.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get expenseCategoryTransport;

  /// No description provided for @expenseCategoryPackaging.
  ///
  /// In en, this message translates to:
  /// **'Packaging'**
  String get expenseCategoryPackaging;

  /// No description provided for @expenseCategoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get expenseCategoryOther;

  /// No description provided for @expenseReceiptPhotoAdd.
  ///
  /// In en, this message translates to:
  /// **'Attach receipt photo'**
  String get expenseReceiptPhotoAdd;

  /// No description provided for @expenseReceiptPhotoReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace photo'**
  String get expenseReceiptPhotoReplace;

  /// No description provided for @expenseReceiptPhotoView.
  ///
  /// In en, this message translates to:
  /// **'View photo'**
  String get expenseReceiptPhotoView;

  /// No description provided for @expenseReceiptPhotoSave.
  ///
  /// In en, this message translates to:
  /// **'Save a copy'**
  String get expenseReceiptPhotoSave;

  /// No description provided for @expenseReceiptPhotoHint.
  ///
  /// In en, this message translates to:
  /// **'Kept on this device only, not backed up. Before switching phones, share a copy of it to yourself first.'**
  String get expenseReceiptPhotoHint;

  /// No description provided for @expenseReceiptPhotoMissing.
  ///
  /// In en, this message translates to:
  /// **'This receipt photo isn\'t on this device.'**
  String get expenseReceiptPhotoMissing;

  /// No description provided for @expenseSaved.
  ///
  /// In en, this message translates to:
  /// **'Expense saved'**
  String get expenseSaved;

  /// No description provided for @expenseDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this expense?'**
  String get expenseDeleteConfirmTitle;

  /// No description provided for @expenseDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes the expense record. This cannot be undone.'**
  String get expenseDeleteConfirmBody;

  /// No description provided for @expenseDeleted.
  ///
  /// In en, this message translates to:
  /// **'Expense deleted'**
  String get expenseDeleted;

  /// No description provided for @licenseActivateTitle.
  ///
  /// In en, this message translates to:
  /// **'Activate license'**
  String get licenseActivateTitle;

  /// No description provided for @licenseKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'License key'**
  String get licenseKeyLabel;

  /// No description provided for @licenseActivateBtn.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get licenseActivateBtn;

  /// No description provided for @licenseStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get licenseStatusActive;

  /// No description provided for @licenseStatusGrace.
  ///
  /// In en, this message translates to:
  /// **'Grace period'**
  String get licenseStatusGrace;

  /// No description provided for @licenseStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get licenseStatusExpired;

  /// No description provided for @licenseStatusNone.
  ///
  /// In en, this message translates to:
  /// **'Not activated'**
  String get licenseStatusNone;

  /// No description provided for @licenseExpires.
  ///
  /// In en, this message translates to:
  /// **'Expires: {date}'**
  String licenseExpires(String date);

  /// No description provided for @licenseGraceLeft.
  ///
  /// In en, this message translates to:
  /// **'{days} days of grace left'**
  String licenseGraceLeft(int days);

  /// No description provided for @licenseReadOnly.
  ///
  /// In en, this message translates to:
  /// **'License expired — read-only. Renew to keep selling.'**
  String get licenseReadOnly;

  /// No description provided for @licenseInvalidKey.
  ///
  /// In en, this message translates to:
  /// **'Invalid or unknown license key.'**
  String get licenseInvalidKey;

  /// No description provided for @licenseActivateFailed.
  ///
  /// In en, this message translates to:
  /// **'Activation failed. Check your connection.'**
  String get licenseActivateFailed;

  /// No description provided for @licenseRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts — please wait a few minutes and try again.'**
  String get licenseRateLimited;

  /// No description provided for @licenseActivated.
  ///
  /// In en, this message translates to:
  /// **'License activated'**
  String get licenseActivated;

  /// No description provided for @licenseRenewTitle.
  ///
  /// In en, this message translates to:
  /// **'Record renewal payment'**
  String get licenseRenewTitle;

  /// No description provided for @licenseRecordPayment.
  ///
  /// In en, this message translates to:
  /// **'Record payment'**
  String get licenseRecordPayment;

  /// No description provided for @licensePaymentSaved.
  ///
  /// In en, this message translates to:
  /// **'Renewal payment recorded'**
  String get licensePaymentSaved;

  /// No description provided for @licenseAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get licenseAmount;

  /// No description provided for @licenseRefNo.
  ///
  /// In en, this message translates to:
  /// **'Reference no.'**
  String get licenseRefNo;

  /// No description provided for @licensePayTo.
  ///
  /// In en, this message translates to:
  /// **'Transfer license fee to:'**
  String get licensePayTo;

  /// No description provided for @licenseTxnId.
  ///
  /// In en, this message translates to:
  /// **'Transaction ID (last 6 digits)'**
  String get licenseTxnId;

  /// No description provided for @licenseDeactivate.
  ///
  /// In en, this message translates to:
  /// **'Remove license'**
  String get licenseDeactivate;

  /// No description provided for @licenseDeactivateConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove the license from this device? Your expiry date is kept — re-activating the same key later won\'t lose any days or restart it. This device switches to the Free plan meanwhile, so Sell and Inventory keep working.'**
  String get licenseDeactivateConfirm;

  /// No description provided for @licensePlanLabel.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get licensePlanLabel;

  /// No description provided for @licensePlanMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get licensePlanMonthly;

  /// No description provided for @licensePlanFree.
  ///
  /// In en, this message translates to:
  /// **'Free plan'**
  String get licensePlanFree;

  /// No description provided for @premiumFeatureTitle.
  ///
  /// In en, this message translates to:
  /// **'{featureName} is a Premium feature'**
  String premiumFeatureTitle(String featureName);

  /// No description provided for @premiumFeatureBody.
  ///
  /// In en, this message translates to:
  /// **'You\'re on the Free plan — Sell and Inventory keep working, but this feature needs an active Premium subscription or license key.'**
  String get premiumFeatureBody;

  /// No description provided for @premiumUpgradeCta.
  ///
  /// In en, this message translates to:
  /// **'Upgrade'**
  String get premiumUpgradeCta;

  /// No description provided for @onboardingContinueFree.
  ///
  /// In en, this message translates to:
  /// **'Continue Free'**
  String get onboardingContinueFree;

  /// No description provided for @accountSignOutPremiumConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'You\'ll lose Premium features on this device and it will drop to the Free plan (Sell and Inventory keep working). You\'ll need your email and password again to sign back in and restore Premium.'**
  String get accountSignOutPremiumConfirmBody;

  /// No description provided for @licenseDowngradedToFreeNotice.
  ///
  /// In en, this message translates to:
  /// **'Your subscription/key expired — this device is now on the Free plan. Sell and Inventory still work; renew to unlock Premium features again.'**
  String get licenseDowngradedToFreeNotice;

  /// No description provided for @licensePlanYearly.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get licensePlanYearly;

  /// No description provided for @licenseDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get licenseDuration;

  /// No description provided for @unitMonths.
  ///
  /// In en, this message translates to:
  /// **'months'**
  String get unitMonths;

  /// No description provided for @unitYears.
  ///
  /// In en, this message translates to:
  /// **'years'**
  String get unitYears;

  /// No description provided for @licenseGetKey.
  ///
  /// In en, this message translates to:
  /// **'Enter the key you received when you subscribed.'**
  String get licenseGetKey;

  /// No description provided for @licenseHaveKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Already have a license key?'**
  String get licenseHaveKeyTitle;

  /// No description provided for @licensePaymentProofLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment screenshot (optional)'**
  String get licensePaymentProofLabel;

  /// No description provided for @licensePaymentProofAttach.
  ///
  /// In en, this message translates to:
  /// **'Attach screenshot'**
  String get licensePaymentProofAttach;

  /// No description provided for @licensePaymentProofAttached.
  ///
  /// In en, this message translates to:
  /// **'Screenshot attached'**
  String get licensePaymentProofAttached;

  /// No description provided for @licenseNoKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have a key?'**
  String get licenseNoKeyTitle;

  /// No description provided for @licenseNoKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Pay via KBZPay/WavePay and we\'ll send your license key.'**
  String get licenseNoKeyHint;

  /// No description provided for @licenseSubscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get licenseSubscribe;

  /// No description provided for @licenseGetKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Get license key'**
  String get licenseGetKeyTitle;

  /// No description provided for @licenseOnlineApplyHint.
  ///
  /// In en, this message translates to:
  /// **'Once approved, this is applied to your account automatically — no key to enter.'**
  String get licenseOnlineApplyHint;

  /// No description provided for @licenseRenew.
  ///
  /// In en, this message translates to:
  /// **'Renew / Extend'**
  String get licenseRenew;

  /// No description provided for @licenseExpiringSoon.
  ///
  /// In en, this message translates to:
  /// **'License expires in {days} days — tap to renew.'**
  String licenseExpiringSoon(int days);

  /// No description provided for @licenseThankYouTitle.
  ///
  /// In en, this message translates to:
  /// **'Thank you!'**
  String get licenseThankYouTitle;

  /// No description provided for @licenseThankYou24h.
  ///
  /// In en, this message translates to:
  /// **'We\'ll verify your payment and your access will begin within 24 hours.'**
  String get licenseThankYou24h;

  /// No description provided for @licenseFreeTrial.
  ///
  /// In en, this message translates to:
  /// **'Start free 2-month trial'**
  String get licenseFreeTrial;

  /// No description provided for @licenseTrialStarted.
  ///
  /// In en, this message translates to:
  /// **'Free 2-month trial started'**
  String get licenseTrialStarted;

  /// No description provided for @licenseTrialUsed.
  ///
  /// In en, this message translates to:
  /// **'Free trial already used on this device.'**
  String get licenseTrialUsed;

  /// No description provided for @licenseRefId.
  ///
  /// In en, this message translates to:
  /// **'App Reference ID'**
  String get licenseRefId;

  /// No description provided for @licenseRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Request sent. We\'ll review your payment and send your key.'**
  String get licenseRequestSent;

  /// No description provided for @licenseRequestSentViber.
  ///
  /// In en, this message translates to:
  /// **'Request sent. We\'ll send your key via Viber {viber}.'**
  String licenseRequestSentViber(String viber);

  /// No description provided for @licenseCheckRenewal.
  ///
  /// In en, this message translates to:
  /// **'Check for renewal'**
  String get licenseCheckRenewal;

  /// No description provided for @licenseRefreshed.
  ///
  /// In en, this message translates to:
  /// **'License status updated'**
  String get licenseRefreshed;

  /// No description provided for @licenseRenewHint.
  ///
  /// In en, this message translates to:
  /// **'After paying (KPay/WavePay) and recording it, ask the admin to approve, then tap Check for renewal.'**
  String get licenseRenewHint;

  /// No description provided for @deviceSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get deviceSectionTitle;

  /// No description provided for @deviceCount.
  ///
  /// In en, this message translates to:
  /// **'{used}/{free} free devices used'**
  String deviceCount(int used, int free);

  /// No description provided for @deviceThisDevice.
  ///
  /// In en, this message translates to:
  /// **'This device'**
  String get deviceThisDevice;

  /// No description provided for @deviceLastActive.
  ///
  /// In en, this message translates to:
  /// **'Last active {when}'**
  String deviceLastActive(String when);

  /// No description provided for @deviceNeverVerified.
  ///
  /// In en, this message translates to:
  /// **'Not yet activated'**
  String get deviceNeverVerified;

  /// No description provided for @deviceAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a device'**
  String get deviceAdd;

  /// No description provided for @deviceRelease.
  ///
  /// In en, this message translates to:
  /// **'Release'**
  String get deviceRelease;

  /// No description provided for @deviceReleaseConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Release this device?'**
  String get deviceReleaseConfirmTitle;

  /// No description provided for @deviceReleaseConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The device will lose access to this shop next time it checks its license. You can add a new device in its place afterward.'**
  String get deviceReleaseConfirmBody;

  /// No description provided for @deviceReleased.
  ///
  /// In en, this message translates to:
  /// **'Device released'**
  String get deviceReleased;

  /// No description provided for @deviceKeyReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'New device is ready'**
  String get deviceKeyReadyTitle;

  /// No description provided for @deviceKeyReadyHint.
  ///
  /// In en, this message translates to:
  /// **'Scan this QR code on the new device\'s activation screen, or type the key below.'**
  String get deviceKeyReadyHint;

  /// No description provided for @deviceKeyCopied.
  ///
  /// In en, this message translates to:
  /// **'Key copied'**
  String get deviceKeyCopied;

  /// No description provided for @devicePaymentRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Device fee required'**
  String get devicePaymentRequiredTitle;

  /// No description provided for @devicePaymentRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'This shop already uses its {free} free devices. Adding another costs {fee} (one-time) — after paying, contact support with your App Reference ID to get your new device\'s key.'**
  String devicePaymentRequiredBody(int free, String fee);

  /// No description provided for @deviceOnlyOnPaidPlan.
  ///
  /// In en, this message translates to:
  /// **'Add a device once you have an active subscription (not available during the free trial).'**
  String get deviceOnlyOnPaidPlan;

  /// No description provided for @deviceRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add a device — try again.'**
  String get deviceRequestFailed;

  /// No description provided for @deviceRoleTitle.
  ///
  /// In en, this message translates to:
  /// **'Who is this device for?'**
  String get deviceRoleTitle;

  /// No description provided for @deviceRoleHint.
  ///
  /// In en, this message translates to:
  /// **'Picked now, so the new phone is already set up correctly the moment it activates — no separate step needed on it.'**
  String get deviceRoleHint;

  /// No description provided for @deviceRoleStaffMember.
  ///
  /// In en, this message translates to:
  /// **'Staff member (optional)'**
  String get deviceRoleStaffMember;

  /// No description provided for @deviceRoleAppliesOnScan.
  ///
  /// In en, this message translates to:
  /// **'Staff mode will be applied automatically when this QR is scanned to activate.'**
  String get deviceRoleAppliesOnScan;

  /// No description provided for @invWebActivateTitle.
  ///
  /// In en, this message translates to:
  /// **'Activate this computer'**
  String get invWebActivateTitle;

  /// No description provided for @invWebActivateHint.
  ///
  /// In en, this message translates to:
  /// **'On your phone: Settings → License → Add device, then paste the key here.'**
  String get invWebActivateHint;

  /// No description provided for @invWebKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Device key'**
  String get invWebKeyLabel;

  /// No description provided for @invWebActivateButton.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get invWebActivateButton;

  /// No description provided for @invWebErrorEmptyKey.
  ///
  /// In en, this message translates to:
  /// **'Enter a device key'**
  String get invWebErrorEmptyKey;

  /// No description provided for @invWebErrorInvalidKey.
  ///
  /// In en, this message translates to:
  /// **'That key isn\'t valid or has expired'**
  String get invWebErrorInvalidKey;

  /// No description provided for @invWebErrorDeviceMismatch.
  ///
  /// In en, this message translates to:
  /// **'This key is already bound to a different device'**
  String get invWebErrorDeviceMismatch;

  /// No description provided for @invWebErrorPaymentRequired.
  ///
  /// In en, this message translates to:
  /// **'Adding this computer needs an extra-device fee — contact support to pay, then try again'**
  String get invWebErrorPaymentRequired;

  /// No description provided for @invWebErrorActivationFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t activate — check the key and try again'**
  String get invWebErrorActivationFailed;

  /// No description provided for @invWebErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error — check your connection and try again'**
  String get invWebErrorNetwork;

  /// No description provided for @invWebSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out this computer'**
  String get invWebSignOut;

  /// No description provided for @invWebDownloadPdf.
  ///
  /// In en, this message translates to:
  /// **'Download PDF'**
  String get invWebDownloadPdf;

  /// No description provided for @invWebSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search invoice #, customer, or phone'**
  String get invWebSearchHint;

  /// No description provided for @invWebNoResults.
  ///
  /// In en, this message translates to:
  /// **'No invoices match your search.'**
  String get invWebNoResults;

  /// No description provided for @referralTitle.
  ///
  /// In en, this message translates to:
  /// **'Refer & earn'**
  String get referralTitle;

  /// No description provided for @referralSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Share your code. Every month a shop you referred pays, you earn — added straight to your license.'**
  String get referralSubtitle;

  /// No description provided for @referralMyCode.
  ///
  /// In en, this message translates to:
  /// **'My referral code'**
  String get referralMyCode;

  /// No description provided for @referralShare.
  ///
  /// In en, this message translates to:
  /// **'Share code'**
  String get referralShare;

  /// No description provided for @referralCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get referralCopied;

  /// No description provided for @referralShareText.
  ///
  /// In en, this message translates to:
  /// **'Use MM POS for your shop! Enter my referral code {code} when you subscribe. — {shop}'**
  String referralShareText(String code, String shop);

  /// No description provided for @referralBalance.
  ///
  /// In en, this message translates to:
  /// **'Your earnings'**
  String get referralBalance;

  /// No description provided for @referralEarnedTotal.
  ///
  /// In en, this message translates to:
  /// **'Total earned'**
  String get referralEarnedTotal;

  /// No description provided for @referralActiveShops.
  ///
  /// In en, this message translates to:
  /// **'Shops you referred'**
  String get referralActiveShops;

  /// No description provided for @referralRedeem.
  ///
  /// In en, this message translates to:
  /// **'Redeem for license days'**
  String get referralRedeem;

  /// No description provided for @referralRedeemDone.
  ///
  /// In en, this message translates to:
  /// **'Added {months} month(s) to your license!'**
  String referralRedeemDone(int months);

  /// No description provided for @referralRedeemNotEnough.
  ///
  /// In en, this message translates to:
  /// **'Not enough balance yet — refer one more shop!'**
  String get referralRedeemNotEnough;

  /// No description provided for @referralNextGoal.
  ///
  /// In en, this message translates to:
  /// **'{amount} more until your next free month'**
  String referralNextGoal(String amount);

  /// No description provided for @referralCodeOptional.
  ///
  /// In en, this message translates to:
  /// **'Referral code (optional)'**
  String get referralCodeOptional;

  /// No description provided for @referralCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Got a friend\'s code? Enter it — they earn when your payment is approved.'**
  String get referralCodeHint;

  /// No description provided for @referralEmpty.
  ///
  /// In en, this message translates to:
  /// **'No referrals yet. Share your code to start earning every month.'**
  String get referralEmpty;

  /// No description provided for @referralNotifTitle.
  ///
  /// In en, this message translates to:
  /// **'🎉 Commission earned!'**
  String get referralNotifTitle;

  /// No description provided for @referralNotifBody.
  ///
  /// In en, this message translates to:
  /// **'{amount} was added to your referral wallet. Open the app to redeem it for free license days.'**
  String referralNotifBody(String amount);

  /// No description provided for @referralHowTitle.
  ///
  /// In en, this message translates to:
  /// **'How Refer & earn works'**
  String get referralHowTitle;

  /// No description provided for @referralStep1.
  ///
  /// In en, this message translates to:
  /// **'Share your code with other shop owners.'**
  String get referralStep1;

  /// No description provided for @referralStep2.
  ///
  /// In en, this message translates to:
  /// **'They type your code when they subscribe and pay.'**
  String get referralStep2;

  /// No description provided for @referralStep3.
  ///
  /// In en, this message translates to:
  /// **'You earn a commission every month they keep paying.'**
  String get referralStep3;

  /// No description provided for @referralStep4.
  ///
  /// In en, this message translates to:
  /// **'Turn your balance into free license days anytime.'**
  String get referralStep4;

  /// No description provided for @referralHaveCode.
  ///
  /// In en, this message translates to:
  /// **'Have a referral code?'**
  String get referralHaveCode;

  /// No description provided for @referralHaveCodeHint.
  ///
  /// In en, this message translates to:
  /// **'A friend gave you one? Enter it below — they earn when your payment is approved. Leave blank if you don\'t have one.'**
  String get referralHaveCodeHint;

  /// No description provided for @referralRedeemConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Redeem now?'**
  String get referralRedeemConfirmTitle;

  /// No description provided for @referralRedeemConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Add {months} month(s) to your license and use {amount} from your balance?'**
  String referralRedeemConfirmBody(int months, String amount);

  /// No description provided for @referralRedeemAction.
  ///
  /// In en, this message translates to:
  /// **'Redeem'**
  String get referralRedeemAction;

  /// No description provided for @backupTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup & restore'**
  String get backupTitle;

  /// No description provided for @backupHint.
  ///
  /// In en, this message translates to:
  /// **'Your data is stored on this device. Export a backup file and keep it safe (e.g. send it to Viber → My Notes).'**
  String get backupHint;

  /// No description provided for @backupExport.
  ///
  /// In en, this message translates to:
  /// **'Export backup'**
  String get backupExport;

  /// No description provided for @backupExportHint.
  ///
  /// In en, this message translates to:
  /// **'Save all data to a file and share it.'**
  String get backupExportHint;

  /// No description provided for @backupImport.
  ///
  /// In en, this message translates to:
  /// **'Import backup'**
  String get backupImport;

  /// No description provided for @backupImportHint.
  ///
  /// In en, this message translates to:
  /// **'Restore data from a backup file.'**
  String get backupImportHint;

  /// No description provided for @backupShareSubject.
  ///
  /// In en, this message translates to:
  /// **'MM POS backup'**
  String get backupShareSubject;

  /// No description provided for @backupShareText.
  ///
  /// In en, this message translates to:
  /// **'MM POS data backup. Keep this file to restore later.'**
  String get backupShareText;

  /// No description provided for @backupImportConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace all data?'**
  String get backupImportConfirmTitle;

  /// No description provided for @backupImportConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This will erase the current products, sales and credit data and replace them with the backup. This cannot be undone.'**
  String get backupImportConfirmBody;

  /// No description provided for @backupImportConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get backupImportConfirmAction;

  /// No description provided for @backupImportDone.
  ///
  /// In en, this message translates to:
  /// **'Restored {count} rows'**
  String backupImportDone(int count);

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'Backup failed: {error}'**
  String backupFailed(String error);

  /// No description provided for @settingsSync.
  ///
  /// In en, this message translates to:
  /// **'Cloud sync'**
  String get settingsSync;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @syncIdle.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get syncIdle;

  /// No description provided for @syncSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get syncSyncing;

  /// No description provided for @syncOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get syncOffline;

  /// No description provided for @syncError.
  ///
  /// In en, this message translates to:
  /// **'Sync error'**
  String get syncError;

  /// No description provided for @syncDisabled.
  ///
  /// In en, this message translates to:
  /// **'Cloud sync not configured'**
  String get syncDisabled;

  /// No description provided for @syncNever.
  ///
  /// In en, this message translates to:
  /// **'Never synced'**
  String get syncNever;

  /// No description provided for @syncLastSynced.
  ///
  /// In en, this message translates to:
  /// **'Last synced: {time}'**
  String syncLastSynced(String time);

  /// No description provided for @syncRealtimeOn.
  ///
  /// In en, this message translates to:
  /// **'Live updates on'**
  String get syncRealtimeOn;

  /// No description provided for @navOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get navOrders;

  /// No description provided for @ordersTitle.
  ///
  /// In en, this message translates to:
  /// **'Social Orders'**
  String get ordersTitle;

  /// No description provided for @ordersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No orders yet. Tap + to add one.'**
  String get ordersEmpty;

  /// No description provided for @orderNew.
  ///
  /// In en, this message translates to:
  /// **'New order'**
  String get orderNew;

  /// No description provided for @orderEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit order'**
  String get orderEditTitle;

  /// No description provided for @orderStatusNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get orderStatusNew;

  /// No description provided for @orderStatusDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get orderStatusDelivered;

  /// No description provided for @orderStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Return'**
  String get orderStatusCancelled;

  /// No description provided for @orderChannelFacebook.
  ///
  /// In en, this message translates to:
  /// **'Facebook'**
  String get orderChannelFacebook;

  /// No description provided for @orderChannelViber.
  ///
  /// In en, this message translates to:
  /// **'Viber'**
  String get orderChannelViber;

  /// No description provided for @orderChannelTiktok.
  ///
  /// In en, this message translates to:
  /// **'TikTok'**
  String get orderChannelTiktok;

  /// No description provided for @orderChannelPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get orderChannelPhone;

  /// No description provided for @orderChannelStorefront.
  ///
  /// In en, this message translates to:
  /// **'Web'**
  String get orderChannelStorefront;

  /// No description provided for @orderChannelOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get orderChannelOther;

  /// No description provided for @orderCustomerName.
  ///
  /// In en, this message translates to:
  /// **'Customer name'**
  String get orderCustomerName;

  /// No description provided for @orderCustomerPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone (optional)'**
  String get orderCustomerPhone;

  /// No description provided for @orderChannel.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get orderChannel;

  /// No description provided for @orderDeliveryAddress.
  ///
  /// In en, this message translates to:
  /// **'Delivery address'**
  String get orderDeliveryAddress;

  /// No description provided for @orderDeliveryFee.
  ///
  /// In en, this message translates to:
  /// **'Delivery fee'**
  String get orderDeliveryFee;

  /// No description provided for @orderNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get orderNote;

  /// No description provided for @orderMoreDetails.
  ///
  /// In en, this message translates to:
  /// **'More details (phone, address, delivery fee, note)'**
  String get orderMoreDetails;

  /// No description provided for @orderItems.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get orderItems;

  /// No description provided for @orderAddItem.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get orderAddItem;

  /// No description provided for @orderItemName.
  ///
  /// In en, this message translates to:
  /// **'Item name'**
  String get orderItemName;

  /// No description provided for @orderItemPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get orderItemPrice;

  /// No description provided for @orderItemQty.
  ///
  /// In en, this message translates to:
  /// **'Qty'**
  String get orderItemQty;

  /// No description provided for @orderItemsTotal.
  ///
  /// In en, this message translates to:
  /// **'Items subtotal'**
  String get orderItemsTotal;

  /// No description provided for @orderTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get orderTotal;

  /// No description provided for @orderPayment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get orderPayment;

  /// No description provided for @orderPayUnpaid.
  ///
  /// In en, this message translates to:
  /// **'Unpaid'**
  String get orderPayUnpaid;

  /// No description provided for @orderPaymentTransfer.
  ///
  /// In en, this message translates to:
  /// **'Bank transfer'**
  String get orderPaymentTransfer;

  /// No description provided for @orderPaymentCod.
  ///
  /// In en, this message translates to:
  /// **'Cash on delivery'**
  String get orderPaymentCod;

  /// No description provided for @orderPaymentCodNote.
  ///
  /// In en, this message translates to:
  /// **'Cash on delivery — collected when the order arrives'**
  String get orderPaymentCodNote;

  /// No description provided for @orderPayPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get orderPayPaid;

  /// No description provided for @orderAwaitingPayment.
  ///
  /// In en, this message translates to:
  /// **'Awaiting payment'**
  String get orderAwaitingPayment;

  /// No description provided for @orderMarkAsPaid.
  ///
  /// In en, this message translates to:
  /// **'Mark as paid'**
  String get orderMarkAsPaid;

  /// No description provided for @orderMarkAsUnpaid.
  ///
  /// In en, this message translates to:
  /// **'Mark as unpaid'**
  String get orderMarkAsUnpaid;

  /// No description provided for @orderSave.
  ///
  /// In en, this message translates to:
  /// **'Save order'**
  String get orderSave;

  /// No description provided for @orderEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get orderEdit;

  /// No description provided for @orderDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete order'**
  String get orderDelete;

  /// No description provided for @orderDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this order? This cannot be undone.'**
  String get orderDeleteConfirm;

  /// No description provided for @orderBlockCustomer.
  ///
  /// In en, this message translates to:
  /// **'Block this customer'**
  String get orderBlockCustomer;

  /// No description provided for @orderBlockCustomerConfirm.
  ///
  /// In en, this message translates to:
  /// **'Block {phone} from placing new orders on your storefront?'**
  String orderBlockCustomerConfirm(String phone);

  /// No description provided for @orderCustomerBlocked.
  ///
  /// In en, this message translates to:
  /// **'Customer blocked'**
  String get orderCustomerBlocked;

  /// No description provided for @orderLowStockAtOrder.
  ///
  /// In en, this message translates to:
  /// **'Requested more than the recorded stock at the time of this order'**
  String get orderLowStockAtOrder;

  /// No description provided for @orderCarrierHint.
  ///
  /// In en, this message translates to:
  /// **'Type or pick a carrier'**
  String get orderCarrierHint;

  /// No description provided for @orderHandOffButton.
  ///
  /// In en, this message translates to:
  /// **'Handed off to carrier'**
  String get orderHandOffButton;

  /// No description provided for @orderHandedOffTo.
  ///
  /// In en, this message translates to:
  /// **'Handed off to {carrier}'**
  String orderHandedOffTo(String carrier);

  /// No description provided for @orderChangeCarrier.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get orderChangeCarrier;

  /// No description provided for @orderConvertToSale.
  ///
  /// In en, this message translates to:
  /// **'Convert to sale'**
  String get orderConvertToSale;

  /// No description provided for @orderConvertHint.
  ///
  /// In en, this message translates to:
  /// **'Creates an invoice and deducts stock for catalog items.'**
  String get orderConvertHint;

  /// No description provided for @orderConverted.
  ///
  /// In en, this message translates to:
  /// **'Order converted to a sale ({invoice}).'**
  String orderConverted(String invoice);

  /// No description provided for @orderAlreadySale.
  ///
  /// In en, this message translates to:
  /// **'Already recorded as a sale.'**
  String get orderAlreadySale;

  /// No description provided for @orderCancel.
  ///
  /// In en, this message translates to:
  /// **'Mark as return'**
  String get orderCancel;

  /// No description provided for @orderRestore.
  ///
  /// In en, this message translates to:
  /// **'Undo return'**
  String get orderRestore;

  /// No description provided for @orderReturnConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Return this order?'**
  String get orderReturnConfirmTitle;

  /// No description provided for @orderReturnConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This refunds {amount}, reverses the sale, and restores stock. This cannot be undone.'**
  String orderReturnConfirmBody(String amount);

  /// No description provided for @orderNeedsName.
  ///
  /// In en, this message translates to:
  /// **'Enter a customer name.'**
  String get orderNeedsName;

  /// No description provided for @orderNeedsItem.
  ///
  /// In en, this message translates to:
  /// **'Add at least one item.'**
  String get orderNeedsItem;

  /// No description provided for @orderSaved.
  ///
  /// In en, this message translates to:
  /// **'Order saved.'**
  String get orderSaved;

  /// No description provided for @orderItemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String orderItemsCount(int count);

  /// No description provided for @orderPickPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get orderPickPaymentMethod;

  /// No description provided for @orderPaymentProof.
  ///
  /// In en, this message translates to:
  /// **'Payment screenshot'**
  String get orderPaymentProof;

  /// No description provided for @orderInvoice.
  ///
  /// In en, this message translates to:
  /// **'Share invoice'**
  String get orderInvoice;

  /// No description provided for @orderPrint.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get orderPrint;

  /// No description provided for @deliveryTownship.
  ///
  /// In en, this message translates to:
  /// **'Township'**
  String get deliveryTownship;

  /// No description provided for @deliveryTownshipNone.
  ///
  /// In en, this message translates to:
  /// **'No township set'**
  String get deliveryTownshipNone;

  /// No description provided for @deliveryCarrier.
  ///
  /// In en, this message translates to:
  /// **'Carrier'**
  String get deliveryCarrier;

  /// No description provided for @deliveryCarrierNone.
  ///
  /// In en, this message translates to:
  /// **'Not assigned'**
  String get deliveryCarrierNone;

  /// No description provided for @deliveryTrackingNumber.
  ///
  /// In en, this message translates to:
  /// **'Tracking / waybill number'**
  String get deliveryTrackingNumber;

  /// No description provided for @deliveryTrackingHint.
  ///
  /// In en, this message translates to:
  /// **'Enter after booking on the carrier\'s own app'**
  String get deliveryTrackingHint;

  /// No description provided for @deliverySave.
  ///
  /// In en, this message translates to:
  /// **'Save delivery info'**
  String get deliverySave;

  /// No description provided for @deliverySaved.
  ///
  /// In en, this message translates to:
  /// **'Delivery info saved'**
  String get deliverySaved;

  /// No description provided for @deliveryManualNote.
  ///
  /// In en, this message translates to:
  /// **'No live carrier API yet — book the waybill in the carrier\'s own app, then record the tracking number here.'**
  String get deliveryManualNote;

  /// No description provided for @ordersSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search name, phone, order #, invoice #'**
  String get ordersSearchHint;

  /// No description provided for @ordersNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No orders match your filters.'**
  String get ordersNoMatch;

  /// No description provided for @ordersClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get ordersClearFilters;

  /// No description provided for @orderFilterChannel.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get orderFilterChannel;

  /// No description provided for @orderFilterPayment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get orderFilterPayment;

  /// No description provided for @staffMode.
  ///
  /// In en, this message translates to:
  /// **'Staff mode'**
  String get staffMode;

  /// No description provided for @staffRoleOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get staffRoleOwner;

  /// No description provided for @staffRoleStaff.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get staffRoleStaff;

  /// No description provided for @staffCurrentRole.
  ///
  /// In en, this message translates to:
  /// **'Current: {role}'**
  String staffCurrentRole(String role);

  /// No description provided for @staffSwitchTo.
  ///
  /// In en, this message translates to:
  /// **'Switch to {role}'**
  String staffSwitchTo(String role);

  /// No description provided for @staffUnlockOwner.
  ///
  /// In en, this message translates to:
  /// **'Unlock Owner'**
  String get staffUnlockOwner;

  /// No description provided for @staffSetPin.
  ///
  /// In en, this message translates to:
  /// **'Set owner PIN'**
  String get staffSetPin;

  /// No description provided for @staffChangePin.
  ///
  /// In en, this message translates to:
  /// **'Change owner PIN'**
  String get staffChangePin;

  /// No description provided for @staffEnterPin.
  ///
  /// In en, this message translates to:
  /// **'Enter owner PIN'**
  String get staffEnterPin;

  /// No description provided for @staffWrongPin.
  ///
  /// In en, this message translates to:
  /// **'Wrong PIN'**
  String get staffWrongPin;

  /// No description provided for @staffPinHint.
  ///
  /// In en, this message translates to:
  /// **'4–6 digits'**
  String get staffPinHint;

  /// No description provided for @staffPinSaved.
  ///
  /// In en, this message translates to:
  /// **'PIN saved'**
  String get staffPinSaved;

  /// No description provided for @staffOwnerOnly.
  ///
  /// In en, this message translates to:
  /// **'Owner only'**
  String get staffOwnerOnly;

  /// No description provided for @staffOwnerOnlyDesc.
  ///
  /// In en, this message translates to:
  /// **'Switch to Owner mode (Settings) to view this.'**
  String get staffOwnerOnlyDesc;

  /// No description provided for @staffBadge.
  ///
  /// In en, this message translates to:
  /// **'Staff mode'**
  String get staffBadge;

  /// No description provided for @staffManageMembers.
  ///
  /// In en, this message translates to:
  /// **'Manage staff'**
  String get staffManageMembers;

  /// No description provided for @staffMembersTitle.
  ///
  /// In en, this message translates to:
  /// **'Staff members'**
  String get staffMembersTitle;

  /// No description provided for @staffMembersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No staff members yet. Add one so sales can be attributed to whoever rang them up.'**
  String get staffMembersEmpty;

  /// No description provided for @staffAddMember.
  ///
  /// In en, this message translates to:
  /// **'Add staff'**
  String get staffAddMember;

  /// No description provided for @staffEditMember.
  ///
  /// In en, this message translates to:
  /// **'Edit staff'**
  String get staffEditMember;

  /// No description provided for @staffMemberName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get staffMemberName;

  /// No description provided for @staffMemberPin.
  ///
  /// In en, this message translates to:
  /// **'PIN (4–6 digits)'**
  String get staffMemberPin;

  /// No description provided for @staffMemberPinKeepHint.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to keep the current PIN'**
  String get staffMemberPinKeepHint;

  /// No description provided for @staffMemberSaved.
  ///
  /// In en, this message translates to:
  /// **'Staff member saved'**
  String get staffMemberSaved;

  /// No description provided for @staffRemoveMember.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get staffRemoveMember;

  /// No description provided for @staffRemoveConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove this staff member?'**
  String get staffRemoveConfirmTitle;

  /// No description provided for @staffRemoveConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{name} will no longer appear when switching to Staff mode. Past sales still show their name.'**
  String staffRemoveConfirmBody(String name);

  /// No description provided for @staffMemberRemoved.
  ///
  /// In en, this message translates to:
  /// **'Staff member removed'**
  String get staffMemberRemoved;

  /// No description provided for @staffWhoAreYou.
  ///
  /// In en, this message translates to:
  /// **'Who\'s using this device?'**
  String get staffWhoAreYou;

  /// No description provided for @staffNoNamedStaff.
  ///
  /// In en, this message translates to:
  /// **'No name — just Staff mode'**
  String get staffNoNamedStaff;

  /// No description provided for @storefrontTitle.
  ///
  /// In en, this message translates to:
  /// **'My web storefront'**
  String get storefrontTitle;

  /// No description provided for @storefrontDesc.
  ///
  /// In en, this message translates to:
  /// **'Publish a public catalog your customers can order from — no app needed.'**
  String get storefrontDesc;

  /// No description provided for @storefrontPublish.
  ///
  /// In en, this message translates to:
  /// **'Publish storefront'**
  String get storefrontPublish;

  /// No description provided for @storefrontDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Storefront name'**
  String get storefrontDisplayName;

  /// No description provided for @storefrontYourLink.
  ///
  /// In en, this message translates to:
  /// **'Your shop link'**
  String get storefrontYourLink;

  /// No description provided for @storefrontEnabled.
  ///
  /// In en, this message translates to:
  /// **'Storefront enabled'**
  String get storefrontEnabled;

  /// No description provided for @storefrontCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get storefrontCopied;

  /// No description provided for @storefrontNeedsName.
  ///
  /// In en, this message translates to:
  /// **'Enter a storefront name'**
  String get storefrontNeedsName;

  /// No description provided for @storefrontPhoneShown.
  ///
  /// In en, this message translates to:
  /// **'Phone (shown to customers)'**
  String get storefrontPhoneShown;

  /// No description provided for @storefrontAddressShown.
  ///
  /// In en, this message translates to:
  /// **'Address (shown to customers)'**
  String get storefrontAddressShown;

  /// No description provided for @storefrontLogoLabel.
  ///
  /// In en, this message translates to:
  /// **'Shop logo'**
  String get storefrontLogoLabel;

  /// No description provided for @storefrontProfileSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get storefrontProfileSaved;

  /// No description provided for @storefrontShare.
  ///
  /// In en, this message translates to:
  /// **'Share this link with customers on Facebook, Viber, etc.'**
  String get storefrontShare;

  /// No description provided for @storefrontBlockedCustomers.
  ///
  /// In en, this message translates to:
  /// **'Blocked customers'**
  String get storefrontBlockedCustomers;

  /// No description provided for @storefrontNoBlockedCustomers.
  ///
  /// In en, this message translates to:
  /// **'No one is blocked.'**
  String get storefrontNoBlockedCustomers;

  /// No description provided for @storefrontUnblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get storefrontUnblock;

  /// No description provided for @storefrontAddBlocked.
  ///
  /// In en, this message translates to:
  /// **'Block a phone number'**
  String get storefrontAddBlocked;

  /// No description provided for @storefrontBlockReasonOptional.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get storefrontBlockReasonOptional;

  /// No description provided for @storefrontPaymentInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment accounts'**
  String get storefrontPaymentInfoTitle;

  /// No description provided for @storefrontPaymentInfoHint.
  ///
  /// In en, this message translates to:
  /// **'Shown to customers at checkout so they know who to transfer to.'**
  String get storefrontPaymentInfoHint;

  /// No description provided for @storefrontPayKpayName.
  ///
  /// In en, this message translates to:
  /// **'KBZPay account name'**
  String get storefrontPayKpayName;

  /// No description provided for @storefrontPayKpayNumber.
  ///
  /// In en, this message translates to:
  /// **'KBZPay number'**
  String get storefrontPayKpayNumber;

  /// No description provided for @storefrontPayWaveName.
  ///
  /// In en, this message translates to:
  /// **'WavePay account name'**
  String get storefrontPayWaveName;

  /// No description provided for @storefrontPayWaveNumber.
  ///
  /// In en, this message translates to:
  /// **'WavePay number'**
  String get storefrontPayWaveNumber;

  /// No description provided for @storefrontNumberCopied.
  ///
  /// In en, this message translates to:
  /// **'Number copied'**
  String get storefrontNumberCopied;

  /// No description provided for @storefrontRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many orders submitted recently — please wait a few minutes and try again.'**
  String get storefrontRateLimited;

  /// No description provided for @storefrontBlocked.
  ///
  /// In en, this message translates to:
  /// **'This shop isn\'t able to accept orders from this phone number. Please contact the shop directly.'**
  String get storefrontBlocked;

  /// No description provided for @storefrontOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'Sorry, one of your items just sold out online. Please adjust your cart and try again.'**
  String get storefrontOutOfStock;

  /// No description provided for @storefrontOnlineLeft.
  ///
  /// In en, this message translates to:
  /// **'{count} left online'**
  String storefrontOnlineLeft(int count);

  /// No description provided for @storefrontSoldOut.
  ///
  /// In en, this message translates to:
  /// **'Sold out online'**
  String get storefrontSoldOut;

  /// No description provided for @storefrontCheckoutBar.
  ///
  /// In en, this message translates to:
  /// **'Checkout · {count} item(s) · {total}'**
  String storefrontCheckoutBar(int count, String total);

  /// No description provided for @storefrontShopFallbackName.
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get storefrontShopFallbackName;

  /// No description provided for @storefrontPhoneCopied.
  ///
  /// In en, this message translates to:
  /// **'Phone number copied'**
  String get storefrontPhoneCopied;

  /// No description provided for @storefrontAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get storefrontAdd;

  /// No description provided for @storefrontYourDetails.
  ///
  /// In en, this message translates to:
  /// **'Your details'**
  String get storefrontYourDetails;

  /// No description provided for @storefrontNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name *'**
  String get storefrontNameRequired;

  /// No description provided for @storefrontPayment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get storefrontPayment;

  /// No description provided for @storefrontBankTransfer.
  ///
  /// In en, this message translates to:
  /// **'Bank transfer'**
  String get storefrontBankTransfer;

  /// No description provided for @storefrontCashOnDelivery.
  ///
  /// In en, this message translates to:
  /// **'Cash on delivery'**
  String get storefrontCashOnDelivery;

  /// No description provided for @storefrontPayTo.
  ///
  /// In en, this message translates to:
  /// **'Pay to:'**
  String get storefrontPayTo;

  /// No description provided for @storefrontAttachProof.
  ///
  /// In en, this message translates to:
  /// **'Attach payment screenshot'**
  String get storefrontAttachProof;

  /// No description provided for @storefrontProofAttached.
  ///
  /// In en, this message translates to:
  /// **'Screenshot: {name}'**
  String storefrontProofAttached(String name);

  /// No description provided for @storefrontCodNoticeBeforeOrder.
  ///
  /// In en, this message translates to:
  /// **'You\'ll pay cash to the courier when your order arrives.'**
  String get storefrontCodNoticeBeforeOrder;

  /// No description provided for @storefrontTotal.
  ///
  /// In en, this message translates to:
  /// **'Total: {amount}'**
  String storefrontTotal(String amount);

  /// No description provided for @storefrontPlaceOrder.
  ///
  /// In en, this message translates to:
  /// **'Place order'**
  String get storefrontPlaceOrder;

  /// No description provided for @storefrontOrderPlaced.
  ///
  /// In en, this message translates to:
  /// **'Order placed!'**
  String get storefrontOrderPlaced;

  /// No description provided for @storefrontOrderNo.
  ///
  /// In en, this message translates to:
  /// **'Order no: {orderNo}'**
  String storefrontOrderNo(String orderNo);

  /// No description provided for @storefrontTransferInstructions.
  ///
  /// In en, this message translates to:
  /// **'Transfer and send the screenshot to the shop:'**
  String get storefrontTransferInstructions;

  /// No description provided for @storefrontCodNoticeAfterOrder.
  ///
  /// In en, this message translates to:
  /// **'You\'ll pay cash to the courier on delivery.'**
  String get storefrontCodNoticeAfterOrder;

  /// No description provided for @storefrontSaveToPhotos.
  ///
  /// In en, this message translates to:
  /// **'Save to Photos'**
  String get storefrontSaveToPhotos;

  /// No description provided for @storefrontDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get storefrontDone;

  /// No description provided for @storefrontCopyNumber.
  ///
  /// In en, this message translates to:
  /// **'Copy number'**
  String get storefrontCopyNumber;

  /// No description provided for @storefrontNotFound.
  ///
  /// In en, this message translates to:
  /// **'Shop \"{slug}\" not found or not published.'**
  String storefrontNotFound(String slug);

  /// No description provided for @storefrontOpenShopLink.
  ///
  /// In en, this message translates to:
  /// **'Open a shop link, e.g. /your-shop-slug'**
  String get storefrontOpenShopLink;

  /// No description provided for @onboardWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to GoldPOSMM'**
  String get onboardWelcomeTitle;

  /// No description provided for @onboardWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Offline-first point of sale for Myanmar shops. Let\'s get your shop set up — it only takes a minute.'**
  String get onboardWelcomeBody;

  /// No description provided for @onboardNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardNext;

  /// No description provided for @onboardSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardSkip;

  /// No description provided for @onboardGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onboardGetStarted;

  /// No description provided for @onboardShopTitle.
  ///
  /// In en, this message translates to:
  /// **'Your shop'**
  String get onboardShopTitle;

  /// No description provided for @onboardShopBody.
  ///
  /// In en, this message translates to:
  /// **'This appears on your printed receipts.'**
  String get onboardShopBody;

  /// No description provided for @onboardLicenseTitle.
  ///
  /// In en, this message translates to:
  /// **'Free plan or license key'**
  String get onboardLicenseTitle;

  /// No description provided for @onboardLicenseBody.
  ///
  /// In en, this message translates to:
  /// **'Continue on the Free plan — Sell and Inventory work forever, no card, no signup, no key needed. Already have a license key from an agent? Activate it now to unlock Premium, or add one later from Settings.'**
  String get onboardLicenseBody;

  /// No description provided for @onboardActivateNow.
  ///
  /// In en, this message translates to:
  /// **'Activate a license key'**
  String get onboardActivateNow;

  /// No description provided for @onboardStaffTitle.
  ///
  /// In en, this message translates to:
  /// **'Owner and Staff modes'**
  String get onboardStaffTitle;

  /// No description provided for @onboardStaffBody.
  ///
  /// In en, this message translates to:
  /// **'You\'re in Owner mode — full access. Handing the phone to an employee? Go to Settings → Owner Tools → Switch to Staff. Staff mode only shows Sell and Orders; a PIN is needed to switch back to Owner.'**
  String get onboardStaffBody;

  /// No description provided for @accountShopLoginTitle.
  ///
  /// In en, this message translates to:
  /// **'Shop login'**
  String get accountShopLoginTitle;

  /// No description provided for @accountShopLoginHint.
  ///
  /// In en, this message translates to:
  /// **'Optional: sign in with an email and password to reach this shop from another device. Your existing license key and PIN quick-switch keep working as before.'**
  String get accountShopLoginHint;

  /// No description provided for @accountEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get accountEmail;

  /// No description provided for @accountPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get accountPassword;

  /// No description provided for @accountConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get accountConfirmPassword;

  /// No description provided for @accountPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords don\'t match'**
  String get accountPasswordMismatch;

  /// No description provided for @accountForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get accountForgotPassword;

  /// No description provided for @accountResetPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get accountResetPasswordTitle;

  /// No description provided for @accountResetPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the email for your shop account. We\'ll send a link to reset your password.'**
  String get accountResetPasswordHint;

  /// No description provided for @accountResetPasswordSend.
  ///
  /// In en, this message translates to:
  /// **'Send reset link'**
  String get accountResetPasswordSend;

  /// No description provided for @accountResetPasswordSent.
  ///
  /// In en, this message translates to:
  /// **'Check your email for a reset link.'**
  String get accountResetPasswordSent;

  /// No description provided for @accountResetPasswordNewLabel.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get accountResetPasswordNewLabel;

  /// No description provided for @accountResetPasswordSave.
  ///
  /// In en, this message translates to:
  /// **'Save new password'**
  String get accountResetPasswordSave;

  /// No description provided for @accountResetPasswordSuccess.
  ///
  /// In en, this message translates to:
  /// **'Password updated. You\'re signed in.'**
  String get accountResetPasswordSuccess;

  /// No description provided for @accountCreateShopLogin.
  ///
  /// In en, this message translates to:
  /// **'Create shop login'**
  String get accountCreateShopLogin;

  /// No description provided for @accountSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get accountSignIn;

  /// No description provided for @accountSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get accountSignOut;

  /// No description provided for @accountSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in.'**
  String get accountSignedIn;

  /// No description provided for @accountSignedOut.
  ///
  /// In en, this message translates to:
  /// **'Signed out.'**
  String get accountSignedOut;

  /// No description provided for @accountSignOutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out?'**
  String get accountSignOutConfirmTitle;

  /// No description provided for @accountSignOutConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'You\'ll need your email and password again to sign back in. Device-key activation and the local PIN quick-switch are unaffected.'**
  String get accountSignOutConfirmBody;

  /// No description provided for @accountSignInWipeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'This account belongs to a different shop'**
  String get accountSignInWipeConfirmTitle;

  /// No description provided for @accountSignInWipeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This device currently has another shop\'s data. Continuing replaces all local data on this device with this account\'s shop data. Make sure everything is already synced first — this cannot be undone.'**
  String get accountSignInWipeConfirmBody;

  /// No description provided for @accountLoginCreated.
  ///
  /// In en, this message translates to:
  /// **'Login created.'**
  String get accountLoginCreated;

  /// No description provided for @accountEmailTaken.
  ///
  /// In en, this message translates to:
  /// **'That email is already in use.'**
  String get accountEmailTaken;

  /// No description provided for @accountNotActivated.
  ///
  /// In en, this message translates to:
  /// **'Activate this device first.'**
  String get accountNotActivated;

  /// No description provided for @accountNoBackend.
  ///
  /// In en, this message translates to:
  /// **'No internet connection.'**
  String get accountNoBackend;

  /// No description provided for @accountPendingSync.
  ///
  /// In en, this message translates to:
  /// **'This device still has unsynced changes. Wait for sync to finish, then try again.'**
  String get accountPendingSync;

  /// No description provided for @accountActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get accountActionFailed;

  /// No description provided for @staffAccountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Staff accounts (login)'**
  String get staffAccountsTitle;

  /// No description provided for @staffAccountsInvite.
  ///
  /// In en, this message translates to:
  /// **'Invite staff'**
  String get staffAccountsInvite;

  /// No description provided for @staffAccountsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No staff accounts yet. Invite one with an email and password so they can sign in on their own device.'**
  String get staffAccountsEmpty;

  /// No description provided for @staffAccountsActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get staffAccountsActive;

  /// No description provided for @staffAccountsRevoked.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get staffAccountsRevoked;

  /// No description provided for @staffAccountsRevoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get staffAccountsRevoke;

  /// No description provided for @staffAccountsRevokeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Revoke this account?'**
  String get staffAccountsRevokeConfirmTitle;

  /// No description provided for @staffAccountsRevokeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{email} will no longer be able to sign in.'**
  String staffAccountsRevokeConfirmBody(String email);

  /// No description provided for @branchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Branches'**
  String get branchesTitle;

  /// No description provided for @branchesCreate.
  ///
  /// In en, this message translates to:
  /// **'Create a new branch'**
  String get branchesCreate;

  /// No description provided for @branchesCreated.
  ///
  /// In en, this message translates to:
  /// **'Branch created.'**
  String get branchesCreated;

  /// No description provided for @branchesLink.
  ///
  /// In en, this message translates to:
  /// **'Link with a key'**
  String get branchesLink;

  /// No description provided for @branchesLinkHint.
  ///
  /// In en, this message translates to:
  /// **'For a shop that already exists separately (e.g. bought its own license key elsewhere). To start a fresh branch, use \"Create a new branch\" instead.'**
  String get branchesLinkHint;

  /// No description provided for @branchesKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'License key'**
  String get branchesKeyLabel;

  /// No description provided for @branchesLabelField.
  ///
  /// In en, this message translates to:
  /// **'Branch name'**
  String get branchesLabelField;

  /// No description provided for @branchesLinked.
  ///
  /// In en, this message translates to:
  /// **'Branch linked.'**
  String get branchesLinked;

  /// No description provided for @branchesInvalidKey.
  ///
  /// In en, this message translates to:
  /// **'That license key wasn\'t found.'**
  String get branchesInvalidKey;

  /// No description provided for @branchesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No branches linked yet.'**
  String get branchesEmpty;

  /// No description provided for @branchesCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get branchesCurrent;

  /// No description provided for @branchesSwitch.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get branchesSwitch;

  /// No description provided for @branchesSwitched.
  ///
  /// In en, this message translates to:
  /// **'Switched branch.'**
  String get branchesSwitched;

  /// No description provided for @branchesSwitchConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch to this branch?'**
  String get branchesSwitchConfirmTitle;

  /// No description provided for @branchesSwitchConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This replaces all local data on this device with \"{label}\"\'s data. Make sure everything is already synced first — this cannot be undone.'**
  String branchesSwitchConfirmBody(String label);

  /// No description provided for @branchesPendingSync.
  ///
  /// In en, this message translates to:
  /// **'This device still has unsynced changes. Wait for sync to finish, then try again.'**
  String get branchesPendingSync;

  /// No description provided for @branchesUnlink.
  ///
  /// In en, this message translates to:
  /// **'Unlink'**
  String get branchesUnlink;

  /// No description provided for @branchesUnlinkConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlink this branch?'**
  String get branchesUnlinkConfirmTitle;

  /// No description provided for @branchesUnlinkConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'\"{label}\" will be removed from your branch list. You can re-link it later with its key.'**
  String branchesUnlinkConfirmBody(String label);

  /// No description provided for @pricingTierTitle.
  ///
  /// In en, this message translates to:
  /// **'Pricing tier'**
  String get pricingTierTitle;

  /// No description provided for @pricingTierOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline pricing'**
  String get pricingTierOffline;

  /// No description provided for @pricingTierOnline.
  ///
  /// In en, this message translates to:
  /// **'Online pricing'**
  String get pricingTierOnline;

  /// No description provided for @pricingTierSwitchToOnline.
  ///
  /// In en, this message translates to:
  /// **'Switch to Online'**
  String get pricingTierSwitchToOnline;

  /// No description provided for @pricingTierSwitchToOffline.
  ///
  /// In en, this message translates to:
  /// **'Switch to Offline'**
  String get pricingTierSwitchToOffline;

  /// No description provided for @pricingTierConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This changes the suggested price on your next renewal request only — it doesn\'t affect your current plan or anything already paid.'**
  String get pricingTierConfirmBody;

  /// No description provided for @pricingTierWhatsTheDifference.
  ///
  /// In en, this message translates to:
  /// **'What\'s the difference?'**
  String get pricingTierWhatsTheDifference;

  /// No description provided for @pricingTierCompareTitle.
  ///
  /// In en, this message translates to:
  /// **'Online vs Offline'**
  String get pricingTierCompareTitle;

  /// No description provided for @pricingTierOnlineExplain.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your email and password on any device to reach this shop — no key to type. Your subscription is linked to your account, so renewing keeps every signed-in device working. Signing out stops Premium features on that device until you sign back in or renew.'**
  String get pricingTierOnlineExplain;

  /// No description provided for @pricingTierOfflineExplain.
  ///
  /// In en, this message translates to:
  /// **'No account or internet needed to keep selling — the license key lives on this device. Adding another device needs its own key (Settings → Devices). Premium stays with the device permanently, regardless of any sign-in.'**
  String get pricingTierOfflineExplain;

  /// No description provided for @recurringExpenseTitle.
  ///
  /// In en, this message translates to:
  /// **'Recurring expenses'**
  String get recurringExpenseTitle;

  /// No description provided for @recurringExpenseManage.
  ///
  /// In en, this message translates to:
  /// **'Manage recurring expenses'**
  String get recurringExpenseManage;

  /// No description provided for @recurringExpenseAddFromTemplate.
  ///
  /// In en, this message translates to:
  /// **'Add from template'**
  String get recurringExpenseAddFromTemplate;

  /// No description provided for @recurringExpenseEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recurring expenses set up yet. Add one for a cost you pay every month, like rent or wages.'**
  String get recurringExpenseEmpty;

  /// No description provided for @recurringExpenseAdd.
  ///
  /// In en, this message translates to:
  /// **'Add recurring expense'**
  String get recurringExpenseAdd;

  /// No description provided for @recurringExpenseEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit recurring expense'**
  String get recurringExpenseEdit;

  /// No description provided for @recurringExpenseSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get recurringExpenseSaved;

  /// No description provided for @recurringExpenseDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted.'**
  String get recurringExpenseDeleted;

  /// No description provided for @recurringExpenseDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this recurring expense?'**
  String get recurringExpenseDeleteConfirmTitle;

  /// No description provided for @recurringExpenseDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This only removes the template — auto-generation stops, but expenses it already created stay untouched.'**
  String get recurringExpenseDeleteConfirmBody;

  /// No description provided for @recurringExpenseAutoGenerate.
  ///
  /// In en, this message translates to:
  /// **'Auto-add every month'**
  String get recurringExpenseAutoGenerate;

  /// No description provided for @recurringExpenseAutoGenerateHint.
  ///
  /// In en, this message translates to:
  /// **'Adds this automatically instead of needing \"Add from template\" — you\'ll still see it in the list right away.'**
  String get recurringExpenseAutoGenerateHint;

  /// No description provided for @recurringExpenseTimingStart.
  ///
  /// In en, this message translates to:
  /// **'Day 1'**
  String get recurringExpenseTimingStart;

  /// No description provided for @recurringExpenseTimingEnd.
  ///
  /// In en, this message translates to:
  /// **'Last day'**
  String get recurringExpenseTimingEnd;

  /// No description provided for @recurringExpenseAutoAdded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 recurring expense added automatically} other{{count} recurring expenses added automatically}}: {names}'**
  String recurringExpenseAutoAdded(int count, String names);

  /// No description provided for @onboardModeTitle.
  ///
  /// In en, this message translates to:
  /// **'How will you use GoldPOSMM?'**
  String get onboardModeTitle;

  /// No description provided for @onboardModeOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get onboardModeOfflineTitle;

  /// No description provided for @onboardModeOfflineBody.
  ///
  /// In en, this message translates to:
  /// **'Start free with Sell + Inventory, no account needed. Add a license key anytime to unlock Premium.'**
  String get onboardModeOfflineBody;

  /// No description provided for @onboardModeOnlineTitle.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get onboardModeOnlineTitle;

  /// No description provided for @onboardModeOnlineBody.
  ///
  /// In en, this message translates to:
  /// **'Create a shop account with your email. Get a 2-month free trial, and manage staff and branches from Settings.'**
  String get onboardModeOnlineBody;

  /// No description provided for @onboardOnlineTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your shop account'**
  String get onboardOnlineTitle;

  /// No description provided for @onboardOnlineBody.
  ///
  /// In en, this message translates to:
  /// **'Your shop name, email, and a password — that\'s all you need to get started with a 2-month free trial.'**
  String get onboardOnlineBody;

  /// No description provided for @onboardOnlineDone.
  ///
  /// In en, this message translates to:
  /// **'Account created. Your free trial has started.'**
  String get onboardOnlineDone;

  /// No description provided for @onboardOnlineCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create shop account'**
  String get onboardOnlineCreateAccount;

  /// No description provided for @currencySymbol.
  ///
  /// In en, this message translates to:
  /// **'Ks'**
  String get currencySymbol;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'my'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'my':
      return AppLocalizationsMy();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
