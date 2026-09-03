// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Burmese (`my`).
class AppLocalizationsMy extends AppLocalizations {
  AppLocalizationsMy([String locale = 'my']) : super(locale);

  @override
  String get appTitle => 'All In One POS';

  @override
  String get navSell => 'ရောင်းချ';

  @override
  String get navInventory => 'ကုန်ပစ္စည်း';

  @override
  String get navInvoices => 'ပြေစာများ';

  @override
  String get navAnalytics => 'စာရင်းအင်း';

  @override
  String get navSettings => 'ဆက်တင်';

  @override
  String get commonUnexpectedError =>
      'တစ်ခုခု မှားယွင်းသွားပါတယ်။ ထပ်ကြိုးစားပေးပါ။';

  @override
  String get commonSave => 'သိမ်းမည်';

  @override
  String get commonCancel => 'မလုပ်တော့ပါ';

  @override
  String get commonOk => 'အိုကေ';

  @override
  String get commonDelete => 'ဖျက်မည်';

  @override
  String get commonEdit => 'ပြင်မည်';

  @override
  String get commonAdd => 'ထည့်မည်';

  @override
  String get commonSearch => 'ရှာဖွေ';

  @override
  String get commonFilters => 'စစ်ထုတ်ရန်';

  @override
  String get commonYes => 'ဟုတ်ကဲ့';

  @override
  String get commonNo => 'မဟုတ်ပါ';

  @override
  String get commonTotal => 'စုစုပေါင်း';

  @override
  String get commonCopy => 'ကူးယူ';

  @override
  String get commonMore => 'အခြား လုပ်ဆောင်ချက်များ';

  @override
  String get commonClear => 'ရှင်းလင်းရန်';

  @override
  String get commonNetworkError =>
      'အင်တာနက် ချိတ်ဆက်မှု မရှိပါ။ Connection စစ်ပြီး ထပ်စမ်းကြည့်ပါ။';

  @override
  String get commonRetry => 'ထပ်စမ်းမည်';

  @override
  String get commonPleaseWait => 'ခဏစောင့်ပါ…';

  @override
  String get copied => 'ကူးယူပြီး';

  @override
  String get sellTitle => 'ရောင်းချ';

  @override
  String sellStockCap(int count) {
    return 'လက်ကျန် $count ခုသာ ရှိပါသည်';
  }

  @override
  String get sellCart => 'ခြင်းတောင်း';

  @override
  String get sellEmptyCart => 'ပစ္စည်းမရှိသေးပါ။ ထည့်ရန် ပစ္စည်းကို နှိပ်ပါ။';

  @override
  String get ordersSelectHint => 'အော်ဒါတစ်ခု ရွေးပါ';

  @override
  String get invoicesSelectHint => 'ငွေတောင်းခံလွှာတစ်ခု ရွေးပါ';

  @override
  String get sellCheckout => 'ငွေရှင်း';

  @override
  String get sellSubtotal => 'ကုန်ကျ';

  @override
  String get sellDiscount => 'လျှော့ဈေး';

  @override
  String sellItemDiscountTitle(String item) {
    return '$item အတွက် လျှော့ဈေး';
  }

  @override
  String get sellPaymentMethod => 'ငွေပေးချေမှုနည်းလမ်း';

  @override
  String get sellAmountPaid => 'ပေးချေငွေ';

  @override
  String get sellTenderExact => 'အတိအကျ';

  @override
  String get sellChange => 'အ‌ကြွေ';

  @override
  String get sellConfirm => 'ရောင်းချမှုအတည်ပြု';

  @override
  String get sellDecreaseQty => 'အရေအတွက် လျှော့ရန်';

  @override
  String get sellIncreaseQty => 'အရေအတွက် တိုးရန်';

  @override
  String get sellClear => 'ရှင်းမည်';

  @override
  String get sellClearConfirmTitle => 'Cart ကို ရှင်းမလား?';

  @override
  String get sellClearConfirmBody =>
      'ထည့်ထားပြီးသား item အားလုံး ဖယ်ရှားပါမည်။ ဒါကို ပြန်ပြင်လို့မရပါ။';

  @override
  String get scanBarcode => 'Barcode ဖတ်';

  @override
  String get scanTorch => 'မီး';

  @override
  String get scanFlip => 'ကင်မရာ ပြောင်း';

  @override
  String get scanHint => 'Barcode ကို ကင်မရာနဲ့ ချိန်ပါ';

  @override
  String scanAdded(String name) {
    return '$name ထည့်ပြီး';
  }

  @override
  String scanNotFound(String code) {
    return 'barcode $code နဲ့ ပစ္စည်း မတွေ့ပါ';
  }

  @override
  String get scanHardwareHint => 'ကင်မရာ (သို့) USB / Bluetooth scanner';

  @override
  String get scanHardwareOnlyHint =>
      'USB scanner တပ်ပါ (သို့) Bluetooth scanner ကို စက်ရဲ့ Bluetooth ဆက်တင်မှာ ချိတ်ပါ။ ဒီစာမျက်နှာ ဖွင့်ထားပြီး scan ပါ။';

  @override
  String get scanDone => 'ပြီးပြီ';

  @override
  String get scanContinuousHint =>
      'စိတ်ကြိုက် အရေအတွက် scan ပါ — scan သမျှ cart ထဲ ထည့်ပေးပါမယ်။ ပြီးရင် ပြီးပြီ ခလုတ် နှိပ်ပါ။';

  @override
  String get scannerSettings => 'Barcode scanner';

  @override
  String get scannerSettingsIntro =>
      'လက်ကိုင် scanner က ကီးဘုတ်လို ရိုက်သွင်းပါတယ်။ ကွန်ပျူတာ၊ တက်ဘလက်၊ ဖုန်းရဲ့ Bluetooth/USB မှာ ချိတ်ရုံပါ — ဒီ app ထဲမှာ သီးသန့် ချိတ်စရာ မလိုပါ။';

  @override
  String get scannerUsbTitle => 'USB scanner';

  @override
  String get scannerUsbBody =>
      'ကွန်ပျူတာ (သို့) USB-C ပါတဲ့ တက်ဘလက်မှာ တပ်ပါ။ ရောင်းချ ဖွင့်ပြီး scan ရင် cart ထဲ ထည့်ပါတယ်။';

  @override
  String get scannerBluetoothTitle => 'Bluetooth scanner';

  @override
  String get scannerBluetoothBody =>
      'Scanner ဖွင့်ပြီး Android / iOS / Windows Bluetooth ဆက်တင်မှာ ကီးဘုတ်အဖြစ် ချိတ်ပါ။ ရောင်းချ ဖွင့်ပြီး scan ပါ။';

  @override
  String get scannerSellTitle => 'ဘယ်နေရာမှာ သုံးလဲ';

  @override
  String get scannerSellBody =>
      'ရောင်းချ — cart ထဲထည့်။ ကုန်ပစ္စည်း — ရှာသည်။ ပစ္စည်းပြင် — barcode ဖြည့်။ ပြေစာများ — ပြေစာနံပါတ်ရှာ။';

  @override
  String get sellCompleted => 'ရောင်းချမှု ပြီးဆုံးပါပြီ';

  @override
  String get sellCheckoutFailed =>
      'ရောင်းချမှု မသိမ်းနိုင်ခဲ့ပါ — ငွေ ဘာမှ မကောက်ရသေးပါ။ ထပ်စမ်းကြည့်ပါ။';

  @override
  String get sellInsufficientPaid => 'ပေးချေငွေသည် စုစုပေါင်းထက် နည်းနေသည်။';

  @override
  String get sellHoldSale => 'အရောင်း သိမ်းထား';

  @override
  String get sellCartHeld => 'ခြင်းတောင်း သိမ်းထားပြီး';

  @override
  String get sellHeldTitle => 'သိမ်းထားသော အရောင်းများ';

  @override
  String get sellHeldEmpty => 'သိမ်းထားသော အရောင်း မရှိပါ။';

  @override
  String get sellHeldRemoved => 'သိမ်းထားသည်ကို ဖျက်ပြီး';

  @override
  String get sellAutoHeldPrevious => 'အရင်ခြင်းတောင်းကို သိမ်းထားလိုက်ပါပြီ';

  @override
  String get paymentCash => 'ငွေသား';

  @override
  String get paymentKbzPay => 'KBZPay';

  @override
  String get paymentWavePay => 'WavePay';

  @override
  String get paymentAyaPay => 'AYAPay';

  @override
  String get paymentCbPay => 'CBPay';

  @override
  String get paymentCredit => 'အကြွေး';

  @override
  String get paymentCod => 'COD (အရောက်ငွေချေ)';

  @override
  String get paymentSplit => 'ခွဲပြီးပေးချေမှု';

  @override
  String get splitPaymentTitle => 'ခွဲပြီးပေးချေမှု';

  @override
  String get splitPaymentAddMethod => 'နောက်ထပ် payment method ထည့်ရန်';

  @override
  String splitPaymentRemaining(String amount) {
    return 'ကျန်ငွေ: $amount';
  }

  @override
  String get splitPaymentRemoveMethod => 'ဒီ method ကို ဖျက်ရန်';

  @override
  String get splitPaymentEdit => 'ခွဲပေးချေမှု ပြင်ရန်';

  @override
  String get splitPaymentSetUp => 'ခွဲပေးချေမှု စတင်ရန် နှိပ်ပါ';

  @override
  String get cashRegisterTitle => 'ငွေတိုက်';

  @override
  String get cashRegisterOpen => 'ဖွင့်ထား';

  @override
  String get cashRegisterClosed => 'ပိတ်ပြီး';

  @override
  String get cashOpeningAmount => 'အဖွင့်ငွေပမာဏ';

  @override
  String get cashOpenRegister => 'ငွေတိုက် ဖွင့်မည်';

  @override
  String get cashCloseRegister => 'ငွေတိုက် ပိတ်မည်';

  @override
  String get cashExpectedNow => 'ယခု ရှိသင့်သော ငွေပမာဏ';

  @override
  String get cashOpenedAt => 'ဖွင့်ချိန်';

  @override
  String get cashClosingAmount => 'ရေတွက်ရရှိသည့် ငွေပမာဏ';

  @override
  String get cashCloseWarning =>
      'ပိတ်လိုက်ပြီးရင် ဒီအရေအတွက်က သေချာသွားပါမယ် — မှားရိုက်မိရင် session အသစ် မဖွင့်ရသေးမချင်း ဒီ session ကို ငွေတိုက်စာမျက်နှာက ပြန်ဖွင့်ပြီး ပြင်နိုင်ပါတယ်။';

  @override
  String get cashAmountRequired => 'အရင် ငွေပမာဏ ဖြည့်ပါ။';

  @override
  String get cashVariance => 'ကွာခြားချက်';

  @override
  String cashVarianceShort(String amount) {
    return '$amount လျော့နေသည်';
  }

  @override
  String cashVarianceOver(String amount) {
    return '$amount ပိုနေသည်';
  }

  @override
  String get cashVarianceExact => 'အတိအကျ ကိုက်ညီသည်';

  @override
  String get cashNote => 'မှတ်ချက် (ရွေးချယ်ခွင့်)';

  @override
  String get cashHistory => 'မှတ်တမ်းဟောင်း';

  @override
  String get cashNoSession => 'ငွေတိုက် မဖွင့်ရသေးပါ။';

  @override
  String get cashNoHistory => 'ယခင် session မှတ်တမ်း မရှိသေးပါ။';

  @override
  String get cashSessionAlreadyOpen =>
      'ငွေတိုက် ဆက်ရှင်း ဖွင့်ထားပြီးသား — အရင်ပိတ်ပါ';

  @override
  String get cashRegisterOpenedMsg => 'ငွေတိုက် ဖွင့်ပြီး';

  @override
  String get cashRegisterClosedMsg => 'ငွေတိုက် ပိတ်ပြီး';

  @override
  String get cashReopenLastSession => 'မကြာသေးမီ session ကို ပြန်ဖွင့်မည်';

  @override
  String get cashReopenLastSessionConfirm =>
      'ဒါက ခုနက ရိုက်ထည့်လိုက်တဲ့ ပိတ်ချိန်အရေအတွက်ကို ပြန်ဖျက်ပေးမှာပါ — မှန်ကန်တဲ့ ပမာဏနဲ့ ပြန်ရေတွက်ပြီး ပြန်ပိတ်ရပါမယ်။ အနီးဆုံးပိတ်ခဲ့တဲ့ session ကိုသာ ပြန်ဖွင့်နိုင်ပြီး၊ session အသစ် မဖွင့်ရသေးမချင်းမှသာ ဒါကို လုပ်လို့ရပါတယ်။';

  @override
  String get cashReopenLastSessionDone => 'Session ပြန်ဖွင့်ပြီးပါပြီ';

  @override
  String get cashReportTitle => 'ငွေတိုက် Session အစီရင်ခံစာ';

  @override
  String get cashClosedAt => 'ပိတ်ချိန်';

  @override
  String get cashReportPrintBluetooth => 'ပြေစာပရင်တာနဲ့ ထုတ်';

  @override
  String get cashReportSharePdf => 'PDF မျှဝေမည်';

  @override
  String get cashReportShareCsv => 'CSV မျှဝေမည်';

  @override
  String get cashReportCashSales => 'ငွေသား ရောင်းအား';

  @override
  String get cashReportCashRepayments => 'ငွေသား ကြွေးဆပ်ငွေ';

  @override
  String get cashReportTopUps => 'ငွေသား ထပ်ဖြည့်ငွေ';

  @override
  String get cashReportSupplierPayments => 'ငွေသား ကုန်သွင်းငွေ';

  @override
  String get cashAddTopUp => 'ငွေသား ထပ်ဖြည့်ရန်';

  @override
  String get cashTopUpAmount => 'ထပ်ဖြည့်တဲ့ ပမာဏ';

  @override
  String get cashTopUpSaved => 'ငွေသား ထပ်ဖြည့်မှု သိမ်းပြီးပါပြီ';

  @override
  String get creditTitle => 'အကြွေးစာရင်း';

  @override
  String get creditCustomerName => 'ဝယ်သူအမည်';

  @override
  String get customerPhone => 'ဖုန်း (မဖြည့်လည်းရ)';

  @override
  String get phoneFormatHint =>
      'မြန်မာဖုန်းနံပါတ် ပုံစံနဲ့ မတူပါ (ဥပမာ - 09xxxxxxxxx) — ဒါပေမယ့် သိမ်းလို့ ရပါတယ်။';

  @override
  String get checkoutAddCustomer => 'ဝယ်သူ ထည့်';

  @override
  String get checkoutSaveToDirectory => 'Customer list ထဲ သိမ်းရန်';

  @override
  String get checkoutPickCustomer => 'Customer list ကနေ ရွေးရန်';

  @override
  String checkoutTierPricingApplied(String tier) {
    return 'ဒီအရောင်းအတွက် $tier ဈေးနှုန်း သုံးထားသည်';
  }

  @override
  String checkoutItemsCount(int count) {
    return 'ကုန်ပစ္စည်း $count မျိုး';
  }

  @override
  String get checkoutShortfallCreditHint =>
      'လိုငွေကို အကြွေးအဖြစ် မှတ်တမ်းတင်ပါမည် — ဝယ်သူအမည် ထည့်ရန် လိုအပ်သည်။';

  @override
  String get checkoutDone => 'ပြီးပါပြီ';

  @override
  String get checkoutOwnerPinTitle => 'ပိုင်ရှင် PIN';

  @override
  String get checkoutOwnerPinExplain =>
      'လျှော့ဈေးကို ပိုင်ရှင်သာ လုပ်ပိုင်ခွင့်ရှိသည်။ ဒီအရောင်းအတွက် ဖွင့်ရန် ပိုင်ရှင် PIN ထည့်ပါ။';

  @override
  String get checkoutOwnerPinWrong => 'PIN မှားနေပါသည်။';

  @override
  String get creditCustomerRequired => 'အကြွေးရောင်းရန် ဝယ်သူအမည် ထည့်ပါ။';

  @override
  String get creditPaidNow => 'ယခုပေးငွေ (မဖြည့်လည်းရ)';

  @override
  String get creditOwed => 'ကျန်ငွေ';

  @override
  String get creditDeposit => 'စရံ';

  @override
  String get creditBalanceDue => 'ကျန်ငွေ (ပေးရမည်)';

  @override
  String get creditPreviousBalance => 'ယခင်ကျန်ငွေ';

  @override
  String get creditTotalBalanceDue => 'စုစုပေါင်း ကျန်ငွေ (ပေးရမည်)';

  @override
  String get creditTotalOutstanding => 'စုစုပေါင်း ကျန်ရှိငွေ';

  @override
  String creditTotalDue(String amount) {
    return 'ကျန်ငွေ $amount';
  }

  @override
  String get creditNoneDue => 'အကြွေးကျန် မရှိပါ';

  @override
  String get creditEmpty => 'အကြွေးတင်နေသူ မရှိသေးပါ။';

  @override
  String creditOpenInvoices(int count) {
    return 'မဆပ်ရသေး ပြေစာ $count စောင်';
  }

  @override
  String get creditOutstanding => 'ကျန်ရှိငွေ';

  @override
  String get creditInvoices => 'အကြွေး ပြေစာများ';

  @override
  String get creditSettled => 'ဆပ်ပြီး';

  @override
  String get creditFilterOutstanding => 'ကျန်ရှိ';

  @override
  String get creditFilterAll => 'အားလုံး';

  @override
  String get creditRepayments => 'ပြန်ဆပ်မှုများ';

  @override
  String get creditRecordRepayment => 'ပြန်ဆပ်ငွေ မှတ်တမ်းတင်';

  @override
  String get creditAmount => 'ပမာဏ';

  @override
  String creditRepaymentExceedsOutstanding(String outstanding) {
    return 'ကျန်ငွေ ($outstanding) ထက် ပိုနေပါတယ်။';
  }

  @override
  String get accountsPayableTitle => 'ရောင်းသူပေးရန်ကျန်';

  @override
  String get apNoneDue => 'Supplier ကို ကျန်ငွေ မရှိပါ';

  @override
  String get apOutstanding => 'ကျန်ငွေ';

  @override
  String get apEmpty => 'လက်ရှိ ဘယ် Supplier ကိုမှ ကြွေးမကျန်ပါ။';

  @override
  String get apRecordPayment => 'ငွေပေးချေမှု မှတ်တမ်းတင်ရန်';

  @override
  String get apReceivedPOs => 'လက်ခံရရှိပြီး Purchase Order များ';

  @override
  String get apPayments => 'ငွေပေးချေမှုများ';

  @override
  String get apPaymentSaved => 'ငွေပေးချေမှု မှတ်တမ်းတင်ပြီး';

  @override
  String get equityTitle => 'ပိုင်ရှင် အရင်းအနှီး';

  @override
  String get equityPaidInCapital => 'ပေးသွင်းထားသော အရင်း';

  @override
  String get equityRetainedEarnings => 'ဆက်လက်ရှင်သန်နေသော အမြတ်';

  @override
  String get accountingTitle => 'စာရင်းကိုင်';

  @override
  String get accountingBalanceSheet => 'ဘာလန်ရှိတ် စာရင်း';

  @override
  String get accountingBalanceSheetSubtitle =>
      'ပိုင်ဆိုင်မှု၊ ကြွေးကျန်နှင့် ပိုင်ရှင်ရင်းနှီးငွေ ခြုံငုံကြည့်ရန်';

  @override
  String accountingNetWorthFigure(String amount) {
    return 'စုစုပေါင်းပိုင်ဆိုင်မှု: $amount';
  }

  @override
  String get accountingCashFlow => 'ငွေဝင်ငွေထွက် စာရင်း';

  @override
  String get accountingCashFlowSubtitle =>
      'အကောင့်တစ်ခုချင်း ငွေဝင်/ငွေထွက်ကို ကာလရွေးကြည့်ရန်';

  @override
  String accountingCashFlowFigure(String amount) {
    return 'ဒီလ: $amount';
  }

  @override
  String get accountingTaxSummary => 'အခွန် အစီရင်ခံစာ';

  @override
  String get accountingTaxSummarySubtitle =>
      'အခွန်တင်သွင်းရန် ရောင်းအား/ကုန်ကျစရိတ် အချုပ်';

  @override
  String accountingTaxFigure(String amount) {
    return 'အသားတင်အမြတ် (ယခုနှစ်အတွင်း): $amount';
  }

  @override
  String get accountingYearEndClose => 'နှစ်ကုန် ပိတ်စာရင်း';

  @override
  String get accountingYearEndCloseSubtitle =>
      'ပြီးစီးသောနှစ်ကို ပြင်ဆင်ခွင့်ပိတ်ရန်';

  @override
  String get balanceSheetAssets => 'ပိုင်ဆိုင်မှုများ';

  @override
  String get balanceSheetCashAccounts => 'ငွေသားနှင့် အကောင့်များ';

  @override
  String get balanceSheetInventory => 'ကုန်လက်ကျန် (ကုန်ကျစရိတ်)';

  @override
  String get balanceSheetReceivables => 'အကြွေးရှင်များ ကျန်ငွေ';

  @override
  String get balanceSheetLiabilities => 'ကြွေးကျန်များ';

  @override
  String get balanceSheetPayables => 'ပေးရန်ကျန် (Supplier)';

  @override
  String get balanceSheetEquity => 'ပိုင်ရှင် ရင်းနှီးငွေ';

  @override
  String get balanceSheetNetWorth =>
      'စုစုပေါင်းပိုင်ဆိုင်မှု (ပိုင်ဆိုင်မှု − အကြွေးတင်ငွေ)';

  @override
  String get balanceSheetUntracked => 'မှတ်တမ်းမဝင် (အစပိုင်း လက်ကျန်)';

  @override
  String get balanceSheetUntrackedNote =>
      'ယောဘုာအားဖြင့် အစပိုင်းတွင် လက်ဖြင့် ထည့်သွင်းခဲ့သော ကုန်လက်ကျန်တန်ဖိုး (နှင့် လက်ဖြင့်ချိန်ညှိမှုများ) ဖြစ်ပါသည် — ဤစနစ်သည် double-entry စနစ်မဟုတ်သဖြင့် ကွာခြားချက်ကို ဖုံးကွယ်မထားဘဲ ပြထားပါသည်။';

  @override
  String get cashFlowOpening => 'အစလက်ကျန်';

  @override
  String get cashFlowInflow => 'ငွေဝင်';

  @override
  String get cashFlowOutflow => 'ငွေထွက်';

  @override
  String get cashFlowClosing => 'အဆုံးလက်ကျန်';

  @override
  String get cashFlowOwnerNote =>
      'မှတ်ချက် — ပိုင်ရှင် ရင်းနှီးငွေထည့်/ထုတ်မှုများတွင် အကောင့်ကော်လံ မရှိသဖြင့် ဤစာရင်းတွင် မပါဝင်ပါ။ (ပိုင်ရှင်ရင်းနှီးငွေ စာရင်းတွင် ကြည့်ပါ။)';

  @override
  String get cashFlowEmpty => 'ဤကာလအတွင်း အကောင့်လှုပ်ရှားမှု မရှိပါ။';

  @override
  String get taxRevenueLabel => 'ရောင်းအား စုစုပေါင်း';

  @override
  String get taxNetProfitLabel => 'အမြတ်ငွေ (အခွန်တွက်ရန်)';

  @override
  String get taxNoComputationNote =>
      'အခွန်နှုန်းများသည် ဥပဒေအလိုက် ပြောင်းလဲနိုင်သဖြင့် ဤအစီရင်ခံစာတွင် အချက်အလက်များသာ ပြထားပါသည် — အခွန်တွက်ချက်ခြင်းကို စာရင်းကိုင်ထံမှ လုပ်ပါ။';

  @override
  String get yearEndOpenChip => 'စာရင်း ဖွင့်လှစ်ထားပါသည်';

  @override
  String yearEndClosedChip(String date) {
    return 'စာရင်းပိတ်ပြီး — $date အထိ';
  }

  @override
  String get yearEndExplainer =>
      'စာရင်းပိတ်လိုက်ပါက ဤဖုန်းရှိ ကုန်ကျစရိတ်နှင့် ရင်းနှီးငွေ မှတ်တမ်းများကို ပိတ်ထားသောနှစ်အတွင်း ပြင်ဆင်/ဖျက်ခွင့် မရှိတော့ပါ။ ရောင်းချမှုမှတ်တမ်းများက မူလကတည်းက ပြင်မရနိုင်ပါ။ အချိန်မရွေး ပြန်ဖွင့်နိုင်ပါသည်။';

  @override
  String yearEndCloseThroughYear(int year) {
    return '$year အထိ စာရင်းပိတ်ရန်';
  }

  @override
  String yearEndConfirmTitle(int year) {
    return '$year အထိ စာရင်းပိတ်မလား?';
  }

  @override
  String get yearEndConfirmBody =>
      'ပိတ်ထားသောကာလအတွင်း ကုန်ကျစရိတ်နှင့် ရင်းနှီးငွေ မှတ်တမ်းများကို ဤဖုန်းမှ နောက်မှ ပြင်ဆင်/ဖျက်ခွင့် မရှိတော့ပါ။ အချိန်မရွေး ပြန်ဖွင့်နိုင်ပါသည်။';

  @override
  String get yearEndReopen => 'စာရင်း ပြန်ဖွင့်ရန်';

  @override
  String get yearEndReopened => 'စာရင်း ပြန်ဖွင့်ပြီးပါပြီ';

  @override
  String get yearEndReopenNote =>
      'ပြန်ဖွင့်သည်နှင့်တပြိုင်နက ပိတ်ထားခံရသော မှတ်တမ်းများကို ပြင်ဆင်နိုင်ပါသည်။';

  @override
  String yearEndClosedWarn(String date) {
    return 'စာရင်းကို $date အထိ ပိတ်ထားပါသည်။ ပြင်ဆင်ရန် စာရင်းကိုင် → နှစ်ကုန်ပိတ်စာရင်းမှ ပြန်ဖွင့်ပါ။';
  }

  @override
  String get arExportCsv => 'အကြွေးကျန် စာရင်း CSV ထုတ်';

  @override
  String get arExportBenefit =>
      'အကြွေးကျန်စာရင်းကို spreadsheet အဖြစ် export လုပ်နိုင်';

  @override
  String get arHeaderCustomer => 'ဝယ်ယူသူ';

  @override
  String get arHeaderPhone => 'ဖုန်း';

  @override
  String get arHeaderInvoice => 'ဘောင်ချာအမှတ်';

  @override
  String get arHeaderDays => 'ရက်';

  @override
  String get arHeaderBucket => 'ကာလ';

  @override
  String get arHeaderOutstanding => 'ကျန်ငွေ';

  @override
  String get agingBucket0 => '၀–၃၀ ရက်';

  @override
  String get agingBucket1 => '၃၁–၆၀ ရက်';

  @override
  String get agingBucket2 => '၆၁–၉၀ ရက်';

  @override
  String get agingBucket3 => '၉၀+ ရက်';

  @override
  String get apExportCsv => 'ပေးရန်ကျန် CSV ထုတ်';

  @override
  String get apBilledHeader => 'ကြွေးဖြစ်ငွေ';

  @override
  String get apPaidHeader => 'ပေးပြီးငွေ';

  @override
  String get expensesHeaderCategory => 'အမျိုးအစား';

  @override
  String get chartSwipeHint => 'ရက်တိုင်းကြည့်ရန် ဘေးတိုက်ပွတ်ပါ';

  @override
  String get filterByCategory => 'အမျိုးအစား ရွေးရန်';

  @override
  String get equityTotal => 'စုစုပေါင်း အရင်းအနှီး';

  @override
  String get equityContribution => 'အရင်းထည့်ဝင်ငွေ';

  @override
  String get equityDrawing => 'ထုတ်ယူငွေ';

  @override
  String get equityAdd => 'မှတ်တမ်း ထည့်ရန်';

  @override
  String get equityAmount => 'ပမာဏ';

  @override
  String get equityEmpty =>
      'အရင်းထည့်ဝင်ငွေ (သို့) ထုတ်ယူငွေ မှတ်တမ်း မရှိသေးပါ။';

  @override
  String get equitySaved => 'သိမ်းပြီးပါပြီ';

  @override
  String get equityDeleteConfirmTitle => 'ဒီမှတ်တမ်းကို ဖယ်ရှားမလား?';

  @override
  String get equityDeleteConfirmBody => 'ဒီလုပ်ဆောင်ချက်ကို ပြန်ပြင်လို့ မရပါ။';

  @override
  String get equityDeleted => 'မှတ်တမ်း ဖယ်ရှားပြီးပါပြီ';

  @override
  String get creditRepaymentSaved => 'ပြန်ဆပ်ငွေ မှတ်တမ်းတင်ပြီး';

  @override
  String get customersTitle => 'ဖောက်သည်များ';

  @override
  String get customersEmpty => 'ဖောက်သည် မထည့်ရသေးပါ။ ပထမဆုံး ဖောက်သည်ထည့်ပါ။';

  @override
  String get customersNoMatch => 'ရှာဖွေမှုနှင့် ကိုက်ညီသည့် ဖောက်သည် မရှိပါ။';

  @override
  String get customersSearchHint => 'အမည် သို့မဟုတ် ဖုန်းနံပါတ် ရှာပါ';

  @override
  String get customerAdd => 'ဖောက်သည်ထည့်ရန်';

  @override
  String get customerEdit => 'ဖောက်သည်ပြင်ရန်';

  @override
  String get customerNameLabel => 'အမည်';

  @override
  String get customerAddress => 'လိပ်စာ';

  @override
  String get customerTierLabel => 'ဈေးနှုန်းအဆင့်';

  @override
  String get customerTierRetail => 'လက်လီ';

  @override
  String get customerTierWholesale => 'လက်ကား';

  @override
  String get customerTierVip => 'VIP';

  @override
  String get customerSaved => 'ဖောက်သည်အချက်အလက် သိမ်းပြီး';

  @override
  String get customerDeleteConfirmTitle => 'ဒီဖောက်သည်ကို ဖယ်ရှားမှာလား?';

  @override
  String customerDeleteConfirmBody(String name) {
    return '$name ကို checkout မှာ suggestion အဖြစ် နောက်ထပ် မမြင်ရတော့ပါ။ ယခင် invoice တွေမှာတော့ နာမည် ဆက်ပြနေပါမည်။';
  }

  @override
  String get customerDeleted => 'ဖောက်သည် ဖယ်ရှားပြီး';

  @override
  String get suppliersTitle => 'ကုန်ပို့သူများ';

  @override
  String get suppliersEmpty =>
      'ကုန်ပို့သူ မထည့်ရသေးပါ။ ပထမဆုံး ကုန်ပို့သူကို ထည့်ပါ။';

  @override
  String get supplierAdd => 'ကုန်ပို့သူ ထည့်မည်';

  @override
  String get supplierEdit => 'ကုန်ပို့သူ ပြင်မည်';

  @override
  String get supplierNameLabel => 'ကုန်ပို့သူအမည်';

  @override
  String get supplierSaved => 'ကုန်ပို့သူ သိမ်းပြီးပါပြီ။';

  @override
  String get supplierDeleteConfirmTitle => 'ဒီကုန်ပို့သူကို ဖယ်ရှားမလား?';

  @override
  String supplierDeleteConfirmBody(String name) {
    return '$name ကို Purchase order အသစ်တွေမှာ အကြံပြုမှာ မဟုတ်တော့ပါ။ ယခင် Purchase order တွေမှာတော့ အမည် ဆက်ပြပါလိမ့်မယ်။';
  }

  @override
  String supplierDeleteConfirmApWarning(String name, String amount) {
    return '$name က Accounts Payable မှာ $amount ကျန်နေပါသေးတယ်။ Supplier ကို ဖျက်လိုက်ရင် အဲ့ကြွေးကျန်ကို ပယ်ဖျက်မသွားပါဘူး — သူတို့ရဲ့ သိမ်းထားတဲ့ အမည်နဲ့ Accounts Payable မှာ ဆက်ပြနေပါမယ်။';
  }

  @override
  String get supplierDeleted => 'ကုန်ပို့သူ ဖယ်ရှားပြီး';

  @override
  String get paymentAccountsTitle => 'ငွေပေးချေမှု အကောင့်များ';

  @override
  String get paymentAccountsEmpty =>
      'Account မထည့်ရသေးပါ။ ပထမဆုံး Account ကို ထည့်ပါ။';

  @override
  String get paymentAccountAdd => 'Account ထည့်မည်';

  @override
  String get paymentAccountEdit => 'Account ပြင်မည်';

  @override
  String get paymentAccountNameLabel => 'Account အမည်';

  @override
  String get paymentAccountOpeningBalanceLabel => 'အစပိုင်း လက်ကျန်ငွေ';

  @override
  String get paymentAccountSaved => 'Account သိမ်းပြီးပါပြီ။';

  @override
  String get paymentAccountDeleteConfirmTitle => 'ဒီ Account ကို ဖယ်ရှားမလား?';

  @override
  String paymentAccountDeleteConfirmBody(String name) {
    return '$name ကို ငွေရှင်းချိန် payment option အနေနဲ့ ထပ်မပေါ်တော့ပါ။ ယခင်အရောင်းများမှာတော့ အမည် ဆက်ပြပါလိမ့်မယ်။';
  }

  @override
  String get paymentAccountDeleted => 'Account ဖယ်ရှားပြီး';

  @override
  String get expensePaidFrom => 'ဘယ် Account ကနေ ပေးလဲ';

  @override
  String get purchaseOrdersTitle => 'ကုန်ဝယ်အမှာစာများ';

  @override
  String get purchaseOrdersEmpty => 'ကုန်ဝယ်အမှာစာ မရှိသေးပါ။';

  @override
  String get poCreate => 'ကုန်ဝယ်အမှာစာ ဖန်တီးမည်';

  @override
  String get poItems => 'ပစ္စည်းများ';

  @override
  String get poNoItems =>
      'ပစ္စည်း မထည့်ရသေးပါ — Product ထည့်ဖို့ + ကို နှိပ်ပါ။';

  @override
  String get poRemoveLineConfirmTitle => 'ဒီ item ကို draft ထဲကနေ ဖယ်မလား?';

  @override
  String get poUnitCost => 'တစ်ခုချင်း ဝယ်ဈေး';

  @override
  String get poSaveDraft => 'သိမ်းမည်';

  @override
  String get poSaved => 'ကုန်ဝယ်အမှာစာ သိမ်းပြီးပါပြီ။';

  @override
  String get poNeedsSupplier => 'Supplier နာမည် ထည့်ပါ။';

  @override
  String get poNeedsItems => 'မသိမ်းမီ item အနည်းဆုံး တစ်ခု ထည့်ပါ။';

  @override
  String get poNoProductsFound => 'Product မတွေ့ပါ။';

  @override
  String get poStatusOpen => 'ဖွင့်ထား';

  @override
  String get poStatusReceived => 'လက်ခံရရှိပြီး';

  @override
  String get poStatusCancelled => 'ပယ်ဖျက်ပြီး';

  @override
  String get poMarkReceived => 'လက်ခံရရှိကြောင်း မှတ်သားမည်';

  @override
  String get poReceiveConfirmTitle =>
      'ဒီကုန်ဝယ်အမှာစာကို လက်ခံရရှိကြောင်း မှတ်သားမလား?';

  @override
  String get poReceiveConfirmBody =>
      'ဒါက Item အားလုံးရဲ့ မှာထားတဲ့ အရေအတွက်ကို မှာထားတဲ့ ဝယ်ဈေးနဲ့ Stock ထဲ ထည့်ပေးပါလိမ့်မယ်။ ပြန်ပြင်လို့ မရပါ။';

  @override
  String get poReceived =>
      'ကုန်ဝယ်အမှာစာ လက်ခံရရှိပြီ — Stock အသစ်ပြင်ပြီးပါပြီ။';

  @override
  String get poReceiveFailed =>
      'လက်ခံရရှိကြောင်း မှတ်သား၍မရပါ — Stock ကို မွမ်းမံခြင်း မပြုရသေးပါ။ ထပ်ကြိုးစားကြည့်ပါ။';

  @override
  String get poCancelOrder => 'ကုန်ဝယ်အမှာစာ ပယ်ဖျက်မည်';

  @override
  String get poCancelConfirmTitle =>
      'ဒီကုန်ဝယ်အမှာစာကို ပယ်ဖျက်မလား? Stock ကို မထိခိုက်ပါ။';

  @override
  String get poCancelConfirmBody =>
      'ဒါက ဒီအော်ဒါကို ပယ်ဖျက်ခြင်းအဖြစ် မှတ်သားပြီး နောက်ထပ် လက်ခံရရှိကြောင်း မှတ်သား၍ မရတော့ပါ။ Stock ကို မထိခိုက်ပါ။ ဒါကို ပြန်ပြင်လို့ မရပါ။';

  @override
  String get poDeleteConfirmTitle => 'ဒီကုန်ဝယ်အမှာစာကို ဖျက်မလား?';

  @override
  String get poDeleteConfirmBody =>
      'ဒီ draft နှင့် line item အားလုံးကို အပြီးဖျက်ပစ်ပါမည်။ ဒါကို ပြန်ပြင်လို့မရပါ။';

  @override
  String get poDeleteFailedReceived =>
      'လက်ခံရရှိပြီးသား ကုန်ဝယ်အမှာစာကို ဖျက်၍မရပါ။';

  @override
  String get inventoryTitle => 'ကုန်ပစ္စည်း';

  @override
  String get inventoryExportCsv => 'CSV ထုတ်';

  @override
  String get inventoryEmpty => 'ပစ္စည်းမရှိသေးပါ။ ပထမဆုံး ပစ္စည်းထည့်ပါ။';

  @override
  String get inventoryLowStock => 'လက်ကျန်နည်းနေသည်';

  @override
  String get inventoryAddProduct => 'ပစ္စည်းအသစ်ထည့်';

  @override
  String get inventoryEditProduct => 'ပစ္စည်းပြင်ဆင်';

  @override
  String get inventoryNoResults => 'ရှာဖွေမှုနှင့် ကိုက်ညီသော ပစ္စည်းမရှိပါ။';

  @override
  String inventoryFilteredCount(int count) {
    return 'ပစ္စည်း $count ခု';
  }

  @override
  String get inventoryOutOfStock => 'ကုန်ပစ္စည်း ကုန်သွားပါပြီ';

  @override
  String get inventoryOutOfStockBadge => 'ကုန်ပြီ';

  @override
  String get productName => 'ပစ္စည်းအမည်';

  @override
  String get productPhoto => 'ပစ္စည်းဓာတ်ပုံ';

  @override
  String get productPrice => 'ရောင်းဈေး';

  @override
  String get productCost => 'အရင်းဈေး';

  @override
  String get productTierPricesHint =>
      'မထည့်လည်းရပါတယ် — ကွက်လပ်ထားရင် ရောင်းဈေးကို အဲဒီအဆင့်အတွက် သုံးပါမည်။';

  @override
  String get productWholesalePrice => 'လက်ကားဈေး';

  @override
  String get productVipPrice => 'VIP ဈေး';

  @override
  String get productSellOnline => 'Web storefront မှာ ရောင်းမည်';

  @override
  String get productSellOnlineHint =>
      'ပိတ်ထားရင် ဒီပစ္စည်းကို Web storefront ပေါ်မှာ လုံးဝ ဖျောက်ထားပေးပါမယ် — ဆိုင်ထဲမှာတော့ ပုံမှန် ရောင်းလို့ရပါတယ်။ Default အနေနဲ့ ဖွင့်ထားပါတယ်။';

  @override
  String get productOnlineStockLimitHint =>
      'အွန်လိုင်းအတွက် အကြံပြု — Web storefront ကနေ ဒီပစ္စည်း ဘယ်နှစ်ခုအထိ ရောင်းမလဲ သတ်မှတ်ပါ (ဆိုင်ထဲ လက်ကျန် လုံခြုံအောင်)။ ကွက်လပ် = ကန့်သတ် မရှိ။';

  @override
  String get productOnlineStockLimit => 'Online ရောင်းမည့် အများဆုံးအရေအတွက်';

  @override
  String get productBarcode => 'ဘားကုဒ်';

  @override
  String get productSku => 'ကုဒ်နံပါတ်';

  @override
  String get productStock => 'လက်ကျန်';

  @override
  String get productQuantity => 'အရေအတွက်';

  @override
  String get productQuantityEditHint =>
      'ဒီနေရာက လက်ကျန်ကို တိုက်ရိုက် ပြောင်းလဲပါတယ်၊ အကြောင်းရင်း မမှတ်တမ်းတင်ပါဘူး — မှတ်တမ်းပါတဲ့ ပြင်ဆင်မှုအတွက် Inventory list ထဲက Adjust Stock ကို သုံးပါ။';

  @override
  String get productReorderLevel => 'အနည်းဆုံး လက်ကျန်';

  @override
  String get productUnit => 'ယူနစ်';

  @override
  String get inventoryUpdateStock => 'လက်ကျန် ပြင်ဆင်ရန်';

  @override
  String get stockAdjustTitle => 'လက်ကျန် ပြင်ဆင်ရန်';

  @override
  String get stockAdjustModeRestock => 'ပစ္စည်းအသစ်ထည့်';

  @override
  String get stockAdjustModeAdjust => 'ချိန်ညှိရန်';

  @override
  String get stockAdjustQuantity => 'အရေအတွက်';

  @override
  String get stockAdjustQuantityHintRestock => 'ရရှိလိုက်တဲ့ အရေအတွက်';

  @override
  String get stockAdjustQuantityHintAdjust =>
      'တိုးရန် + ၊ လျှော့ရန် − ရိုက်ထည့်ပါ';

  @override
  String get stockAdjustUnitCost => 'ယူနစ်တစ်ခုချင်း အရင်းဈေး (မဖြည့်လည်းရ)';

  @override
  String get stockAdjustUnitCostHint =>
      'မဖြည့်ရင် ပစ္စည်းရဲ့ အရင်းဈေးကို သုံးပါမည်';

  @override
  String get stockAdjustReason => 'အကြောင်းရင်း';

  @override
  String get stockAdjustNote => 'မှတ်ချက် (ရွေးချယ်ခွင့်)';

  @override
  String get stockAdjustSave => 'သိမ်းမည်';

  @override
  String get stockAdjustInvalid => 'မှန်ကန်သော အရေအတွက် ရိုက်ထည့်ပါ';

  @override
  String stockAdjustBelowZero(int quantity) {
    return 'ဒါလုပ်ရင် stock က ဇီးရိုထက်နည်းသွားပါမယ် (လက်ရှိ $quantity)။';
  }

  @override
  String get stockAdjustRace =>
      'Stock ကို အခြားစက်တစ်ခုတွင် ပြောင်းလဲလိုက်ပါသည် — ပြန်လည်စတင်ပြီး ထပ်ကြိုးစားပါ။';

  @override
  String stockAdjustCurrentStock(int quantity) {
    return 'လက်ရှိလက်ကျန်: $quantity';
  }

  @override
  String get stockAdjustConfirmTitle => 'လက်ကျန် ပြောင်းလဲမှု အတည်ပြုပါ';

  @override
  String stockAdjustConfirmBody(String name, int before, int after) {
    return '$name: လက်ကျန် $before ကနေ $after ကို ပြောင်းသွားပါမည်။ ဒါကို stock history မှာ မှတ်တမ်းတင်ထားပေမယ့် အလိုအလျောက် ပြန်ပြင်လို့ မရပါ။';
  }

  @override
  String get stockReasonDamaged => 'ပျက်စီး';

  @override
  String get stockReasonLost => 'ပျောက်ဆုံး/ခိုးမှု';

  @override
  String get stockReasonCount => 'ရေတွက်မှား ပြင်ဆင်ခြင်း';

  @override
  String get stockReasonOther => 'အခြား';

  @override
  String get stockHistoryTitle => 'လက်ကျန်မှတ်တမ်း';

  @override
  String get stockHistoryEmpty => 'လက်ကျန်ပြောင်းလဲမှု မရှိသေးပါ။';

  @override
  String get stockHistoryEmptyFiltered =>
      'အမျိုးအစား သို့မဟုတ် ရက်စွဲ စစ်ထုတ်မှုကြောင့် အချို့ မှတ်တမ်းများ ပျောက်နေနိုင်ပါသည်။';

  @override
  String get stockHistoryShowAll => 'မှတ်တမ်းအားလုံး ပြရန်';

  @override
  String get stockHistoryPickDateRange => 'ရက်စွဲအပိုင်းအခြား ရွေးရန်';

  @override
  String get stockHistoryExportCsv => 'မှတ်တမ်း CSV ထုတ်';

  @override
  String get stockHistoryCsvBenefit =>
      'ကုန်လက်ကျန် ရွှေ့ပြောင်းမှု မှတ်တမ်းကို spreadsheet အဖြစ် export လုပ်နိုင်';

  @override
  String get stockHistoryHeaderDate => 'ရက်စွဲ';

  @override
  String get stockHistoryHeaderType => 'အမျိုးအစား';

  @override
  String get stockHistoryHeaderQtyChange => 'အရေအတွက် ပြောင်းလဲမှု';

  @override
  String get stockHistoryHeaderUnitCost => 'တစ်ခုချင်း ကုန်ကျစရိတ်';

  @override
  String get stockHistoryHeaderNote => 'မှတ်ချက်';

  @override
  String get stockHistoryFilterProduct => 'ပစ္စည်းနာမည်ဖြင့် စစ်ရန်';

  @override
  String get stockHistoryClearDateRange => 'ရက်စွဲအပိုင်းအခြား ရှင်းရန်';

  @override
  String get stockMovementOpening => 'အစပိုင်း လက်ကျန်';

  @override
  String get stockMovementSale => 'ရောင်းချမှု';

  @override
  String get stockMovementReturn => 'ပြန်လည်ရရှိခြင်း';

  @override
  String get stockMovementPurchase => 'ပစ္စည်းအသစ်ထည့်ခြင်း';

  @override
  String get stockMovementAdjustment => 'ချိန်ညှိမှု';

  @override
  String get productViewStockHistory => 'လက်ကျန်မှတ်တမ်း ကြည့်ရန်';

  @override
  String get validationRequired => 'ဖြည့်ရန်လိုအပ်သည်';

  @override
  String get deleteConfirmTitle => 'ဖျက်မလား?';

  @override
  String get deleteConfirmBody => 'ဤပစ္စည်းကို ဖယ်ရှားပါမည်။';

  @override
  String get productDeleteConfirmBody =>
      'Sell နှင့် Inventory ကနေ ဖျောက်ထားမှာပါ၊ ဒါပေမယ့် past sales/invoices/stock history မှာတော့ ဆက်ပေါ်နေပါလိမ့်မယ်။';

  @override
  String get categoryDeleteConfirmBody =>
      'ဒီ category ထဲက products တွေရဲ့ ဈေးနှုန်း/stock ကတော့ ဒီအတိုင်းရှိမှာပါ၊ category မရှိတော့ဘဲ ပြပါလိမ့်မယ်။';

  @override
  String get settingsTitle => 'ဆက်တင်';

  @override
  String get settingsSectionBusiness => 'ရောင်းဝယ်ရေး';

  @override
  String get settingsSectionFinance => 'ငွေကြေး';

  @override
  String get settingsSectionAccountTeam => 'အကောင့်/ဝန်ထမ်း';

  @override
  String get settingsSectionDevice => 'စက်';

  @override
  String get settingsSectionHelp => 'အကူအညီ';

  @override
  String get settingsSectionOwnerTools => 'ပိုင်ရှင် Tools';

  @override
  String get settingsLanguage => 'ဘာသာစကား';

  @override
  String get settingsPrinter => 'ပရင်တာ';

  @override
  String get settingsShop => 'ဆိုင်အချက်အလက်';

  @override
  String get settingsLicense => 'လိုင်စင်';

  @override
  String get settingsSupport => 'အကူအညီ (Support)';

  @override
  String get settingsAppGuide => 'App အသုံးပြုပုံ လမ်းညွှန်';

  @override
  String get settingsAbout => 'အက်ပ်အကြောင်း';

  @override
  String get aboutTitle => 'အက်ပ်အကြောင်း';

  @override
  String get aboutVersion => 'ဗားရှင်း';

  @override
  String get aboutWebsite => 'ဝဘ်ဆိုက်';

  @override
  String get aboutCommunity => 'Community';

  @override
  String get aboutCheckForUpdates => 'အပ်ဒိတ် စစ်ဆေးရန်';

  @override
  String get aboutOpenFailed => 'ဒီ link ကို ဖွင့်လို့မရပါ။';

  @override
  String get helpGuideTitle => 'App အသုံးပြုပုံ လမ်းညွှန်';

  @override
  String get helpGuideIntro =>
      'Screen တစ်ခုချင်းစီ ဘာလုပ်တာလဲ အကျဉ်းချုပ်။ အပိုင်းတစ်ခုကို နှိပ်ပြီး ကြည့်ပါ။';

  @override
  String get helpGuideSellTitle => 'ရောင်းရန်';

  @override
  String get helpGuideSellBody =>
      '၁။ ကုန်ပစ္စည်း tile ကို tap နှိပ်ပြီး cart ထဲ ထည့်ပါ၊ (သို့) scan icon ဖြင့် barcode ဖတ်ပြီး ထည့်ပါ။\n၂။ Cart ထဲက item ကို tap နှိပ်ပြီး အရေအတွက်ပြောင်းနိုင်ပါတယ်၊ (သို့) ဖယ်ရှားနိုင်ပါတယ်။\n၃။ ဒီဝယ်သူမှာ Wholesale/VIP tier ရှိရင် customer field ထဲမှာ ရွေးလိုက်ပါ — ဈေးနှုန်း အလိုအလျောက် ပြောင်းသွားပါမယ်။\n၄။ \"Checkout\" ကို tap နှိပ်ပြီး ငွေရှင်း screen ဖွင့်ပါ။\n၅။ လိုအပ်ရင် လျှော့ဈေး ထည့်ပြီး ငွေပေးချေမှု နည်းလမ်း ရွေးပါ (ငွေသား၊ KBZPay၊ WavePay၊ AYAPay၊ CBPay၊ (သို့) အကြွေး)။\n၆။ အကြွေးရောင်းချမှုအတွက် ဝယ်သူအမည် (မဖြစ်မနေ) နှင့် ယခုပေးငွေ (ရှိလျှင်) ထည့်ပါ။\n၇။ အရောင်းအတည်ပြုလိုက်ပါ — Stock အလိုအလျောက် လျော့သွားမယ်၊ Printer ချိတ်ထားရင် ပြေစာ print ထွက်ပြီး၊ Analytics ထဲမှာ မှတ်တမ်းတင်ပါလိမ့်မယ်။';

  @override
  String get helpGuideInventoryTitle => 'ကုန်ပစ္စည်းစီမံခန့်ခွဲမှု';

  @override
  String get helpGuideInventoryBody =>
      '၁။ \"ပစ္စည်းအသစ်ထည့်\" ကို tap နှိပ်ပြီး ဖန်တီးပါ — အမည်၊ ဓာတ်ပုံ၊ ရောင်းဈေး၊ အရင်းဈေး၊ ဘားကုဒ်/ကုဒ်နံပါတ်၊ အစပိုင်းလက်ကျန်၊ အနည်းဆုံးလက်ကျန်။\n၂။ Wholesale/VIP ဈေးနှုန်း ရွေးချယ်ထည့်နိုင်ပါတယ် — ကွက်လပ်ထားရင် ရောင်းဈေးကိုပဲ အဲ့ tier တွေအတွက် သုံးပါမယ်။\n၃။ နောက်ပိုင်း ပြင်ဆင်ချင်ရင် ပစ္စည်းကို tap နှိပ်ပါ။\n၄။ Stock icon ကို tap နှိပ်ပြီး Restock/Adjust ဖွင့်ပါ — \"Restock\" က ဝယ်ယူထည့်သွင်းတဲ့ ပစ္စည်းအတွက် (unit cost ရွေးချယ်ထည့်နိုင်)၊ \"Adjust\" က ပျက်စီး/ပျောက်ဆုံး/ရေတွက်မှား စသည့် အကြောင်းရင်းနဲ့ အရေအတွက် ပြင်ဖို့။\n၅။ \"လက်ကျန်မှတ်တမ်း ကြည့်ရန်\" ကို tap နှိပ်ပြီး အဲ့ပစ္စည်းရဲ့ ယခင် movement အားလုံးကို ကြည့်နိုင်ပါတယ်။\n၆။ အနည်းဆုံးလက်ကျန်ထက် နည်းသွားတဲ့ ပစ္စည်းတွေမှာ \"Low stock\" badge အလိုအလျောက် ပေါ်ပါလိမ့်မယ်။\n၇။ Print icon ကို tap နှိပ်ပြီး barcode label ကို receipt printer (သို့) label printer နဲ့ print ထုတ်နိုင်ပါတယ်။';

  @override
  String get helpGuideOrdersTitle => 'Orders';

  @override
  String get helpGuideOrdersBody =>
      '၁။ Order တွေကို board ပေါ်မှာ card အနေနဲ့ ပြပါတယ် — New, Confirmed, Packed, Shipped, Delivered။\n၂။ \"+\" ကို tap နှိပ်ပြီး ကိုယ်တိုင် ထည့်နိုင်ပါတယ် — ဝယ်သူ၊ channel (Facebook, Web, စသည်)၊ ပစ္စည်းများ၊ ငွေပေးချေမှုနည်းလမ်း (ရောက်မှပေး (သို့) transfer)။\n၃။ Card ကို column အသစ်ဆီ ဆွဲပြောင်းနိုင်ပါတယ်၊ (သို့) \"⋮\" menu နဲ့ status တစ်ခုခုဆီ တိုက်ရိုက် ပြောင်းနိုင်ပါတယ်။\n၄။ Card ကို tap နှိပ်ပြီး အသေးစိတ် ကြည့်ပါ — ပစ္စည်းများ၊ ပို့ဆောင်မှုအချက်အလက်၊ transfer order အတွက် ငွေလွှဲအထောက်အထား ဓာတ်ပုံ။\n၅။ \"Mark as paid\"/\"Mark as unpaid\" ဖြင့် ငွေပေးချေမှုကို ပို့ဆောင်မှုအခြေအနေနဲ့ သီးခြား လိုက်စစ်နိုင်ပါတယ်။\n၆။ Order ပြီးစီးသွားရင် \"Convert to sale\" ကို tap နှိပ်ပြီး sales မှတ်တမ်းနှင့် stock ထဲသို့ ရွှေ့ပါ။\n၇။ Online storefront ကနေ ဝယ်သူချင်း တင်လိုက်တဲ့ order တွေက ဒီမှာ အလိုအလျောက် ပေါ်လာပါမယ် — ကိုယ်တိုင် ရိုက်ထည့်စရာ မလိုပါဘူး။';

  @override
  String get helpGuideInvoicesTitle => 'Invoices';

  @override
  String get helpGuideInvoicesBody =>
      '၁။ ပြီးစီးတဲ့ အရောင်းတိုင်း ဒီမှာ invoice အနေနဲ့ ပေါ်ပါတယ်၊ အသစ်ဆုံးကို အရင်ပြပါတယ်။\n၂။ Invoice ကို tap နှိပ်ပြီး အသေးစိတ် ကြည့်ပါ — ပစ္စည်းများ၊ ဝယ်သူ၊ ငွေပေးချေမှုနည်းလမ်း၊ အခြေအနေ။\n၃။ အကြွေးရောင်းချမှုအတွက် invoice အသေးစိတ် screen ကနေတိုက်ရိုက် တစ်စိတ်တစ်ပိုင်း (သို့) အပြည့်အဝ ပြန်ဆပ်ငွေ မှတ်တမ်းတင်နိုင်ပါတယ်။\n၄။ သတ်မှတ်ရက် လွန်နေတဲ့ အကြွေး invoice များကို အထူးပြထားလို့ ဘယ်သူ့ကို ဆက်လိုက်ရမလဲ သိနိုင်ပါတယ်။\n၅။ \"Refund\" ကို tap နှိပ်ပြီး အရောင်းကို ပြန်ပယ်ဖျက်နိုင်ပါတယ် — Stock နှင့် ဝယ်သူရဲ့ အကြွေးလက်ကျန် အလိုအလျောက် ပြန်ပြင်ပေးပါမယ်။\n၆။ Search bar (သို့) scan icon သုံးပြီး invoice နံပါတ်၊ ဝယ်သူအမည်၊ ဖုန်းနံပါတ်နဲ့ ရှာနိုင်ပါတယ်။\n၇။ Invoice တိုင်းမှာ နောက်ပိုင်း လျင်မြန်စွာ ရှာဖွေနိုင်ဖို့ barcode ပါရှိပါတယ်။';

  @override
  String get helpGuideAnalyticsTitle => 'Analytics';

  @override
  String get helpGuideAnalyticsBody =>
      'Analytics က Premium feature ဖြစ်ပါတယ် — Free plan ဆိုင်တစ်ခုက ဒီ screen အစား upgrade prompt ကိုသာ တွေ့ရမှာပါ။\n၁။ အပေါ်ဆုံးမှာ ရက်စွဲကာလ ရွေးချယ်ပါ — ယနေ့၊ ဒီအပတ်၊ ဒီလ၊ (သို့) ကိုယ်ပိုင်ရွေးချယ်ခြင်း။\n၂။ အဲ့ကာလအတွက် အရောင်းစုစုပေါင်း၊ အမြတ်၊ ရောင်းချမှု အရေအတွက်ကို ကြည့်နိုင်ပါတယ်။\n၃။ အောက်ကို scroll ဆွဲပြီး အရောင်းရဆုံးပစ္စည်းများကို ဝင်ငွေ (သို့) အရေအတွက်အလိုက် အဆင့်သတ်မှတ်ပြထားတာ ကြည့်နိုင်ပါတယ်။\n၄။ အမြတ်ကိန်းဂဏန်းတွေက အဲ့အရောင်းအတွက် တကယ်မှတ်တမ်းတင်ထားတဲ့ အရင်းဈေးကို သုံးထားတာမို့ (ယနေ့ရဲ့ အရင်းဈေးသက်သက်မဟုတ်ဘဲ) — ပစ္စည်းရဲ့ အရင်းဈေး ပြောင်းလဲသွားပြီးနောက်မှာလည်း ယခင်အရောင်းတွေရဲ့ အမြတ် မှန်ကန်နေဆဲပါ။\n၅။ ကာလနှစ်ခုကို ယှဉ်ကြည့်ပြီး ပြန်မှာရမယ့်ပစ္စည်း (သို့) ဈေးနှုန်းပြင်ရမယ့်အရာကို ဆုံးဖြတ်ဖို့ trend ကို ကြိုတင်သိနိုင်ပါတယ်။';

  @override
  String get helpGuideSettingsTitle => 'Settings';

  @override
  String get helpGuideSettingsBody =>
      '၁။ \"ဆိုင်အချက်အလက်\" — ပြေစာနှင့် storefront ပေါ်မှာ ပြသမည့် ဆိုင်နာမည်၊ လိုဂို၊ လိပ်စာ၊ ဆက်သွယ်ရန် အချက်အလက်။\n၂။ \"ပရင်တာ\"/Label printer — Bluetooth (သို့) Wi-Fi ဖြင့် ပြေစာပရင်တာ (သို့) label printer ချိတ်ဆက်ရန် (ကွန်ပျူတာမှာ USB ကြိုးလည်း သုံးနိုင်)။\n၃။ \"လိုင်စင်\" — Free plan က Key/Account လုံးဝမလိုဘဲ အမြဲအသုံးပြုနိုင်ပါတယ် (ရောင်းချမှု၊ ကုန်ပစ္စည်း၊ ငွေဒရာဝါ၊ ကုန်ကျစရိတ်၊ ရောင်းဝယ်ဖက်များ၊ အကြွေးစာရင်း စသဖြင့်)။ Premium features (Analytics၊ Staff accounts စသည်) ဖွင့်ချင်ရင် \"Upgrade\" ကို နှိပ်ပါ — App Reference ID နဲ့ Support ဆက်သွယ်ပြီး license key ရယူပါ (app ထဲတွင် ငွေမကောက်ပါ)။\n၄။ \"အကောင့်\" — email/password နဲ့ ဝင်မည်၊ သို့မဟုတ် ဆိုင် login ဖန်တီးမည်။ ပိုင်ရှင်ရော ဝန်ထမ်းပါ ဒီမှာ ထွက်နိုင်ပါတယ်။ Owner အဖြစ် ဝင်ထားရင် အကောင့် ဖျက်နိုင်ပါတယ်။ Password မေ့သွားရင် Sign-in screen ပေါ်က \"Forgot password?\" ကို နှိပ်ပါ။\n၅။ \"My web storefront\" — Online ဆိုင် ဖွင့်ရန်နှင့် KBZPay/WavePay ငွေလွှဲအချက်အလက် သတ်မှတ်ရန်။\n၆။ \"Owner Tools\" — ဒီ device ကို staff တစ်ဦးဆီ လွှဲပေးရန်၊ (သို့) PIN နဲ့ Owner ပြန်ပြောင်းရန်။ Email login ဝင်ထားသည်ဖြစ်စေ၊ မဝင်ထားသည်ဖြစ်စေ အသုံးပြုနိုင်ပါတယ်။\n၇။ \"Sync\" — cloud နှင့် ချိတ်ဆက်မှု စစ်ဆေးရန်၊ (သို့) ချက်ချင်း sync ပြန်လုပ်ရန်။\n၈။ ဒီ screen ရဲ့ အပေါ်ဆုံးက dropdown ကနေ မြန်မာ/English ဘာသာစကားကို အချိန်မရွေး ပြောင်းနိုင်ပါတယ်။';

  @override
  String get helpGuideSettingsBodyNoCommerce =>
      '၁။ \"ဆိုင်အချက်အလက်\" — ပြေစာနှင့် storefront ပေါ်မှာ ပြသမည့် ဆိုင်နာမည်၊ လိုဂို၊ လိပ်စာ၊ ဆက်သွယ်ရန် အချက်အလက်။\n၂။ \"ပရင်တာ\"/Label printer — Bluetooth (သို့) Wi-Fi ဖြင့် ပြေစာပရင်တာ (သို့) label printer ချိတ်ဆက်ရန် (ကွန်ပျူတာမှာ USB ကြိုးလည်း သုံးနိုင်)။\n၃။ \"လိုင်စင်\" — Free plan က Key/Account လုံးဝမလိုဘဲ အမြဲအသုံးပြုနိုင်ပါတယ် (ရောင်းချမှု၊ ကုန်ပစ္စည်း၊ ငွေဒရာဝါ၊ ကုန်ကျစရိတ်၊ ရောင်းဝယ်ဖက်များ၊ အကြွေးစာရင်း စသဖြင့်)။ Premium features (Analytics၊ Staff accounts စသည်) ကတော့ ဒီ device (သို့) ဆိုင် account ပေါ်မှာ Premium လိုင်စင် active ဖြစ်တာနဲ့ အလိုအလျောက် ပွင့်ပါမယ်။\n၄။ \"အကောင့်\" — email/password နဲ့ ဝင်မည်၊ သို့မဟုတ် ဆိုင် login ဖန်တီးမည်။ ပိုင်ရှင်ရော ဝန်ထမ်းပါ ဒီမှာ ထွက်နိုင်ပါတယ်။ Owner အဖြစ် ဝင်ထားရင် အကောင့် ဖျက်နိုင်ပါတယ်။ Password မေ့သွားရင် Sign-in screen ပေါ်က \"Forgot password?\" ကို နှိပ်ပါ။\n၅။ \"My web storefront\" — Online ဆိုင် ဖွင့်ရန်နှင့် KBZPay/WavePay ငွေလွှဲအချက်အလက် သတ်မှတ်ရန်။\n၆။ \"Owner Tools\" — ဒီ device ကို staff တစ်ဦးဆီ လွှဲပေးရန်၊ (သို့) PIN နဲ့ Owner ပြန်ပြောင်းရန်။ Email login ဝင်ထားသည်ဖြစ်စေ၊ မဝင်ထားသည်ဖြစ်စေ အသုံးပြုနိုင်ပါတယ်။\n၇။ \"Sync\" — cloud နှင့် ချိတ်ဆက်မှု စစ်ဆေးရန်၊ (သို့) ချက်ချင်း sync ပြန်လုပ်ရန်။\n၈။ ဒီ screen ရဲ့ အပေါ်ဆုံးက dropdown ကနေ မြန်မာ/English ဘာသာစကားကို အချိန်မရွေး ပြောင်းနိုင်ပါတယ်။';

  @override
  String get settingsTrackStock => 'Stock စီမံ';

  @override
  String get settingsTrackStockHint =>
      'ပိတ်ထားရင် = invoice သီးသန့် (stock ရေတွက်/သတိပေးမှု မရှိ)။';

  @override
  String get settingsAskCustomer => 'ဝယ်သူ မေးမြန်း';

  @override
  String get settingsAskCustomerHint =>
      'Checkout မှာ ဝယ်သူအမည် + ဖုန်း (optional) ပြ။';

  @override
  String get shopProfileHint => 'ပြေစာပေါ်တွင် ဖော်ပြပါမည်။';

  @override
  String get shopLogo => 'ဆိုင်လိုဂို';

  @override
  String get shopName => 'ဆိုင်အမည်';

  @override
  String get shopAddress => 'လိပ်စာ';

  @override
  String get shopPhone => 'ဖုန်း';

  @override
  String get shopCurrency => 'ငွေကြေးအမျိုးအစား';

  @override
  String get shopCurrencyLockedHint =>
      'ပထမဆုံးအရောင်း ဖြစ်ပြီးနောက် ငွေကြေးအမျိုးအစား ပြောင်းလို့မရတော့ပါ။';

  @override
  String get receiptFooter => 'ပြေစာအောက်ခြေ စာသား';

  @override
  String get shopProfileSaved => 'ဆိုင်အချက်အလက် သိမ်းပြီးပါပြီ';

  @override
  String get languageEnglish => 'အင်္ဂလိပ်';

  @override
  String get languageMyanmar => 'မြန်မာ';

  @override
  String get invoicesEmpty => 'ရောင်းချမှု မရှိသေးပါ။';

  @override
  String get invoiceFilterAll => 'အားလုံး';

  @override
  String get invoiceFilterCredit => 'အကြွေး';

  @override
  String get invoiceFilterRefund => 'ပြန်အမ်းငွေ';

  @override
  String invoiceOwed(String amount) {
    return 'ကျန်ငွေ $amount';
  }

  @override
  String get invoicePrint => 'ပရင့်ထုတ်';

  @override
  String get invoiceReprint => 'ပြန်ထုတ်';

  @override
  String get invoiceShare => 'ပြေစာ မျှဝေမည်';

  @override
  String get invoiceDetail => 'ပြေစာ';

  @override
  String get invoiceSearchHint =>
      'ပြေစာနံပါတ်၊ ဖောက်သည်နာမည်၊ ဖုန်းနံပါတ် ရှာပါ';

  @override
  String get invoiceScanToSearch => 'barcode ဖတ်ရန်';

  @override
  String get invoiceRefund => 'ပြန်အမ်းငွေ';

  @override
  String get invoiceDevice => 'စက်ပစ္စည်း';

  @override
  String get invoiceDeviceUnnamed => 'နာမည်မပေးရသေးသော စက်';

  @override
  String get invoiceRefunded => 'ပြန်အမ်းပြီး';

  @override
  String get invoiceStatusPaid => 'ပေးပြီး';

  @override
  String get invoiceStatusPartial => 'တစ်စိတ်တစ်ပိုင်း';

  @override
  String get invoiceStatusUnpaid => 'မပေးရသေး';

  @override
  String get invoiceStatusPayOnDelivery => 'ပစ္စည်းရောက်မှ ပေးချေရမည်';

  @override
  String get invoiceStatusAwaitingConfirmation => 'အတည်ပြုရန် ကျန်';

  @override
  String get invoiceRefundConfirmTitle => 'ဒီပြေစာကို ပြန်အမ်းမှာလား?';

  @override
  String invoiceRefundConfirmBody(String amount) {
    return 'ဒါက $amount ပြန်အမ်းပေးမည်၊ အရောင်းကို ပြန်ပြင်ပေးမည်၊ ကုန်ပစ္စည်းလက်ကျန်ကိုလည်း ပြန်ထည့်ပေးမည်ဖြစ်ပြီး ပြန်ရုပ်သိမ်းလို့ မရတော့ပါ။';
  }

  @override
  String invoiceRefundOf(String invoiceNo) {
    return '$invoiceNo ၏ ပြန်အမ်းငွေ';
  }

  @override
  String invoiceRefundSuccess(String refundNo) {
    return 'ပြန်အမ်းပြီးပါပြီ ($refundNo)။';
  }

  @override
  String get invoiceAlreadyRefunded => 'ဒီပြေစာကို ပြန်အမ်းပြီးသားဖြစ်ပါသည်။';

  @override
  String get invoiceCustomerName => 'ဖောက်သည်အမည်';

  @override
  String get invoicePhoneNumber => 'ဖုန်းနံပါတ်';

  @override
  String get invoiceAddress => 'လိပ်စာ';

  @override
  String get invoiceColItem => 'ပစ္စည်း';

  @override
  String get invoiceColQty => 'ခု';

  @override
  String get invoiceColPrice => 'ဈေး';

  @override
  String get invoiceItemsAmount => 'ကုန်ကျငွေ';

  @override
  String get invoiceAmountDue => 'ပေးရန်ကျန်';

  @override
  String get salesReportTitle => 'အရောင်းအစီရင်ခံစာ';

  @override
  String get salesReportAllDates => 'ရက်စွဲအားလုံး';

  @override
  String get salesReportEmpty => 'ဒီကာလအတွင်း အရောင်း မရှိသေးပါ။';

  @override
  String get salesReportTotal => 'စုစုပေါင်း';

  @override
  String get salesReportColumnInvoice => 'ပြေစာနံပါတ်';

  @override
  String get salesReportColumnDate => 'ရက်စွဲ';

  @override
  String get salesReportColumnCustomer => 'ဖောက်သည်';

  @override
  String get salesReportColumnAddress => 'လိပ်စာ';

  @override
  String get salesReportColumnCashier => 'ရောင်းသူ';

  @override
  String get salesReportColumnAmount => 'ပမာဏ';

  @override
  String get salesReportPrintBluetooth => 'ပြေစာပရင်တာနဲ့ ထုတ်';

  @override
  String get salesReportExportPdf => 'PDF ထုတ်';

  @override
  String get salesReportExportCsv => 'CSV ထုတ်';

  @override
  String get salesReportNoPrinter =>
      'ပရင်တာ မသတ်မှတ်ရသေးပါ — ပရင်တာ ဆက်တင် ကြည့်ပါ။';

  @override
  String get documentPrint => 'ပရင့်ထုတ်';

  @override
  String salesReportCount(int count) {
    return 'အရောင်း $count ခု';
  }

  @override
  String get pnlTitle => 'အမြတ်-အရှုံး စာရင်း';

  @override
  String get pnlDateRange => 'ရက်စွဲကာလ';

  @override
  String get pnlRevenue => 'စုစုပေါင်း ဝင်ငွေ';

  @override
  String get pnlCogs => 'ကုန်ပစ္စည်း ကုန်ကျစရိတ်';

  @override
  String get pnlGrossProfit => 'စုစုပေါင်း အမြတ်';

  @override
  String get pnlTotalExpenses => 'စုစုပေါင်း ကုန်ကျစရိတ်';

  @override
  String get pnlNetProfit => 'အသားတင် အမြတ်';

  @override
  String get pnlLine => 'အကြောင်းအရာ';

  @override
  String get pnlAmount => 'ပမာဏ';

  @override
  String get pnlExportCsv => 'CSV ထုတ်ယူရန်';

  @override
  String get printerSettings => 'ပရင်တာ ဆက်တင်';

  @override
  String get printerSelectDevice => 'ပရင်တာ ရွေးပါ';

  @override
  String get printerPaperSize => 'စက္ကူအရွယ်';

  @override
  String get printerTestPrint => 'စမ်းထုတ်';

  @override
  String get printerNone => 'ပရင်တာ မရွေးရသေးပါ';

  @override
  String get printerConnected => 'ချိတ်ဆက်ပြီး';

  @override
  String get printerPaired => 'ချိတ်ဆက်ထားသော စက်များ';

  @override
  String get printerNoDevicesFound =>
      'ချိတ်ဆက်ထားသော ဘလူးတုသ် စက်များ မတွေ့ပါ။';

  @override
  String get printerChoosePaperSizeTitle =>
      'ဒီ printer က ဘယ်စက္ကူအရွယ်အစား သုံးလဲ?';

  @override
  String get printerChoosePaperSizeHint =>
      'Printer တစ်ခုစီက သူ့ရဲ့ size ကို သီးခြား မှတ်ထားပါတယ် — ဒီနေရာကနေ အချိန်မရွေး ပြောင်းလို့ရပါတယ်။';

  @override
  String get printSuccess => 'ပရင့်ထုတ်ပြီးပါပြီ';

  @override
  String get printFailed => 'ပရင့်ထုတ်၍ မရပါ';

  @override
  String get bluetoothOff =>
      'Bluetooth ပိတ်ထားသည်။ ဖွင့်ပြီး ပရင်တာ ချိတ်ဆက်ပါ။';

  @override
  String get receiptInvoice => 'ပြေစာ';

  @override
  String get receiptDate => 'ရက်စွဲ';

  @override
  String get receiptCashier => 'ဝန်ထမ်း';

  @override
  String get receiptCustomer => 'ဖောက်သည်';

  @override
  String get receiptPhone => 'ဖုန်း';

  @override
  String get receiptThankYou => 'ဝယ်ယူအားပေးမှုအတွက် ကျေးဇူးတင်ပါသည်။';

  @override
  String get paper58 => '၅၈ မီလီမီတာ';

  @override
  String get paper80 => '၈၀ မီလီမီတာ';

  @override
  String get paper80Narrow => '၈၀ မီလီမီတာ (ကျဉ်းသော ပုံနှိပ်)';

  @override
  String get printerPaperHint =>
      'စာလုံးတွေ ကျော်ထွက်နေ (သို့) ဖြတ်သွားနေရင် အခြားအရွယ်အစား စမ်းကြည့်ပါ — Epson TM-T88 မျိုး ပရင်တာတွေမှာ ကျဉ်းသော အရွယ်ကို သုံးပါ။';

  @override
  String get printerModel => 'ပရင်တာ အမျိုးအစား';

  @override
  String get printerModelHint =>
      'သင့်ပရင်တာရဲ့ အမှတ်တံဆိပ်နဲ့ အမျိုးအစားကို ရွေးလိုက်ရင် သင့်တော်တဲ့ စက္ကူအရွယ်အစားကို အလိုအလျောက် ချိန်ပေးပါမယ်။';

  @override
  String get printerModelCustom => 'အခြား / စာရင်းမှာ မပါပါ';

  @override
  String get printerPdfPaperSize => 'စာရွက် paper size';

  @override
  String get printerPdfPaperSizeHint =>
      'AirPrint (သို့) ကွန်ပျူတာကနေ print ထုတ်တဲ့ invoice/report အတွက်ပါ — အပေါ်က thermal printer အတွက် မဟုတ်ပါ။';

  @override
  String get paperA4 => 'A4';

  @override
  String get paperA5 => 'A5';

  @override
  String get printerConnectionType => 'ဒီစက်က ပရင်တာနဲ့ ဘယ်လို ချိတ်မလဲ';

  @override
  String get printerConnectionBluetooth => 'Bluetooth';

  @override
  String get printerConnectionWifi => 'Wi-Fi';

  @override
  String get printerConnectionUsb => 'USB';

  @override
  String get printerWifiHint =>
      'ဒီ Wi-Fi ပေါ်က ပရင်တာတွေ စာရင်းမှာ ပေါ်ပါမယ်။ ဖုန်း၊ ကွန်ပျူတာနှင့် ပရင်တာ တူညီတဲ့ network ပေါ်မှာ ရှိရပါမယ်။';

  @override
  String get printerWifiIpLabel => 'ပရင်တာ IP လိပ်စာ';

  @override
  String get printerWifiPortLabel => 'Port';

  @override
  String get printerWifiUse => 'ဒီပရင်တာ သုံးမည်';

  @override
  String get printerWifiScan => 'ဒီ Wi-Fi ပေါ်က ပရင်တာ ရှာမည်';

  @override
  String get printerWifiScanning => 'Wi-Fi ပေါ်မှာ ရှာနေသည်…';

  @override
  String get printerWifiNoneFound =>
      'Wi-Fi ပရင်တာ မတွေ့ပါ။ ပရင်တာ စမ်းထုတ် စာမျက်နှာက IP ကို ရိုက်ထည့်ပါ။';

  @override
  String get printerWifiDeniedHint =>
      'မတွေ့သေးဘူးဆိုရင် — iPhone မှာ Settings > Privacy & Security > Local Network ထဲမှာ All In One POS ကို ခွင့်ပြုပြီး Refresh နှိပ်ပါ။ ပရင်တာနဲ့ ဖုန်းက တစ် Wi-Fi တည်းပေါ်မှာ ရှိနေရပါမယ်။';

  @override
  String get printerWifiList => 'ဒီ Wi-Fi ပေါ်က ပရင်တာများ';

  @override
  String get printerWifiManualHint =>
      'စာရင်းမှာ မပေါ်ရင် ပရင်တာ စမ်းထုတ် စာမျက်နှာက IP ကို ရိုက်ထည့်ပါ။';

  @override
  String get printerInvalidIp =>
      'ပရင်တာ IP လိပ်စာ ရိုက်ထည့်ပါ (ဥပမာ 192.168.1.100)။';

  @override
  String get printerNetworkUnreachable =>
      'ပရင်တာကို ဆက်သွယ်မရပါ။ IP နှင့် တူညီတဲ့ Wi-Fi ပေါ်မှာ ရှိမရှိ စစ်ပါ။';

  @override
  String get printerUsbHint =>
      'ပရင်တာကို ဒီကွန်ပျူတာနဲ့ USB ကြိုးချိတ်ပြီး စာရင်းထဲက ရွေးပါ။ Windows ရဲ့ Printers ထဲမှာ ပေါ်နေရပါမယ်။';

  @override
  String get printerUsbNoneFound =>
      'ပရင်တာ မတွေ့ပါ။ ကြိုးချိတ်ပါ၊ Windows က တောင်းရင် install လုပ်ပါ၊ ပြီးရင် Refresh နှိပ်ပါ။';

  @override
  String get printerUsbRefresh => 'ပြန်ရှာမည်';

  @override
  String get settingsLabelPrinter => 'Label ပရင်တာ';

  @override
  String get settingsDeviceName => 'စက်ပစ္စည်းအမည်';

  @override
  String get settingsDeviceNameUnset =>
      'မသတ်မှတ်ရသေးပါ — ဒီစက်ကို နာမည်ပေးရန် နှိပ်ပါ';

  @override
  String get settingsDeviceNameHint => 'ဥပမာ - Counter A, Owner ဖုန်း';

  @override
  String get labelPrinterSettings => 'Label ပရင်တာ ဆက်တင်';

  @override
  String get labelPrinterSize => 'Label အရွယ်အစား';

  @override
  String get labelSize40x30 => '၄၀ x ၃၀ မီလီမီတာ';

  @override
  String get labelSize50x30 => '၅၀ x ၃၀ မီလီမီတာ';

  @override
  String get labelSize50x40 => '၅၀ x ၄၀ မီလီမီတာ';

  @override
  String get labelSize30x20 => '၃၀ x ၂၀ မီလီမီတာ';

  @override
  String get labelSize60x40 => '၆၀ x ၄၀ မီလီမီတာ';

  @override
  String get labelSize100x50 => '၁၀၀ x ၅၀ မီလီမီတာ';

  @override
  String get inventoryPrintLabel => 'Label ပရင့်ထုတ်ရန်';

  @override
  String get labelPrintDialogTitle => 'Label ပရင့်ထုတ်ရန်';

  @override
  String get labelCopies => 'အရေအတွက်';

  @override
  String get labelPrintTargetStrip =>
      'ပြေစာပရင်တာပေါ်မှာ strip အနေနဲ့ ထုတ်ပါမည်';

  @override
  String get labelPrintTargetDedicated => 'Label ပရင်တာပေါ်မှာ ထုတ်ပါမည်';

  @override
  String get labelPrintNoTarget =>
      'ပရင်တာ ချိတ်ဆက်မထားပါ။ Settings ထဲမှာ ပရင်တာတစ်ခု ဦးစွာ ချိတ်ဆက်ပါ။';

  @override
  String get categoriesTitle => 'အမျိုးအစားများ';

  @override
  String get manageCategories => 'အမျိုးအစား စီမံ';

  @override
  String get categoryAdd => 'အမျိုးအစား ထည့်';

  @override
  String get categoryEdit => 'အမျိုးအစား ပြင်';

  @override
  String get categoryName => 'အမျိုးအစား အမည်';

  @override
  String get categoryNone => 'အမျိုးအစား မသတ်မှတ်';

  @override
  String get categoryAll => 'အားလုံး';

  @override
  String get categoriesEmpty => 'အမျိုးအစား မရှိသေးပါ။';

  @override
  String get categoryPickerNoResults => 'ရှာနေတဲ့ အမျိုးအစား မတွေ့ပါ။';

  @override
  String get productCategory => 'အမျိုးအစား';

  @override
  String get analyticsRevenue => 'ရောင်းရငွေ';

  @override
  String analyticsTrendVsPrevious(String sign, int percent) {
    return 'ရှေ့ကာလထက် $sign$percent%';
  }

  @override
  String get analyticsProfit => 'စုစုပေါင်းအမြတ်';

  @override
  String get analyticsExpenses => 'ကုန်ကျစရိတ် စုစုပေါင်း';

  @override
  String get analyticsNetProfit => 'အသားတင်အမြတ်';

  @override
  String get analyticsSalesCount => 'အရောင်း';

  @override
  String get analyticsStockValue => 'လက်ကျန်တန်ဖိုး';

  @override
  String get analyticsDiscountGiven => 'လျှော့ဈေး';

  @override
  String get analyticsTopProducts => 'အရောင်းရဆုံး ပစ္စည်းများ';

  @override
  String get analyticsSalesByEmployee => 'ဝန်ထမ်းအလိုက် ရောင်းအား';

  @override
  String get analyticsRangeToday => 'ယနေ့';

  @override
  String get analyticsRangeWeek => '၇ ရက်';

  @override
  String get analyticsRangeMonth => '၃၀ ရက်';

  @override
  String get analyticsNoData => 'ဤကာလအတွင်း ရောင်းချမှု မရှိပါ။';

  @override
  String analyticsUnitsSold(int count) {
    return '$count ခု ရောင်းပြီး';
  }

  @override
  String get analyticsDailyRevenue => 'နေ့စဉ် ရောင်းရငွေ';

  @override
  String get weekdayShortMon => 'တလာ';

  @override
  String get weekdayShortTue => 'အင်္ဂါ';

  @override
  String get weekdayShortWed => 'ဗုဒ္ဓဟူး';

  @override
  String get weekdayShortThu => 'ကြာသ';

  @override
  String get weekdayShortFri => 'သောကြာ';

  @override
  String get weekdayShortSat => 'စနေ';

  @override
  String get weekdayShortSun => 'တနွေ';

  @override
  String get analyticsCollected => 'လက်ခံရရှိငွေ';

  @override
  String get analyticsCreditOutstanding => 'အကြွေးကျန်';

  @override
  String get expensesTitle => 'ကုန်ကျစရိတ်များ';

  @override
  String get expensesEmpty =>
      'ဤကာလအတွင်း ကုန်ကျစရိတ် မှတ်တမ်းတင်ထားခြင်း မရှိသေးပါ။';

  @override
  String get expensesTotal => 'ကုန်ကျစရိတ် စုစုပေါင်း';

  @override
  String get expenseAdd => 'ကုန်ကျစရိတ် ထည့်ရန်';

  @override
  String get expenseEdit => 'ကုန်ကျစရိတ် ပြင်ရန်';

  @override
  String get expenseAmount => 'ပမာဏ';

  @override
  String get expenseNote => 'မှတ်ချက် (ရွေးချယ်ခွင့်)';

  @override
  String get expenseCategoryRent => 'ဆိုင်ငှားခ';

  @override
  String get expenseCategoryUtilities => 'လျှပ်စစ်/ရေခ';

  @override
  String get expenseCategoryWages => 'ဝန်ထမ်းလစာ';

  @override
  String get expenseCategoryTransport => 'ပို့ဆောင်ခ';

  @override
  String get expenseCategoryPackaging => 'ထုပ်ပိုးစရိတ်';

  @override
  String get expenseCategoryOther => 'အခြား';

  @override
  String get expenseReceiptPhotoAdd => 'ဘောင်ချာပုံ ပူးတွဲရန်';

  @override
  String get expenseReceiptPhotoReplace => 'ပုံ အစားထိုးရန်';

  @override
  String get expenseReceiptPhotoView => 'ပုံ ကြည့်ရန်';

  @override
  String get expenseReceiptPhotoSave => 'မိတ္တူ သိမ်းရန်';

  @override
  String get expenseReceiptPhotoHint =>
      'ဒီဖုန်းပေါ်မှာပဲ သိမ်းထားမှာဖြစ်ပြီး backup ထဲ ပါမည် မဟုတ်ပါ။ ဖုန်းအစားထိုးမလုပ်မီ ကိုယ်တိုင် တစ်နေရာရာသို့ မျှဝေထားပါ။';

  @override
  String get expenseReceiptPhotoMissing =>
      'ဒီဘောင်ချာပုံက ဒီဖုန်းပေါ်မှာ မရှိပါ။';

  @override
  String get expenseSaved => 'ကုန်ကျစရိတ် သိမ်းဆည်းပြီးပါပြီ';

  @override
  String get expenseDeleteConfirmTitle => 'ဒီကုန်ကျစရိတ်ကို ဖျက်မလား?';

  @override
  String get expenseDeleteConfirmBody =>
      'ဒီကုန်ကျစရိတ် မှတ်တမ်းကို အပြီးဖျက်ပစ်ပါမည်။ ဒါကို ပြန်ပြင်လို့မရပါ။';

  @override
  String get expenseDeleted => 'ကုန်ကျစရိတ် ဖျက်ပြီးပါပြီ';

  @override
  String get licenseActivateTitle => 'လိုင်စင် အသက်သွင်း';

  @override
  String get licenseKeyLabel => 'လိုင်စင် key';

  @override
  String get licenseActivateBtn => 'အသက်သွင်း';

  @override
  String get licenseStatusActive => 'အသုံးပြုနိုင်';

  @override
  String get licenseStatusGrace => 'ဆိုင်းငံ့ကာလ';

  @override
  String get licenseStatusExpired => 'သက်တမ်းကုန်';

  @override
  String get licenseStatusNone => 'အသက်မသွင်းရသေး';

  @override
  String licenseExpires(String date) {
    return 'သက်တမ်းကုန်: $date';
  }

  @override
  String licenseGraceLeft(int days) {
    return 'ဆိုင်းငံ့ရက် $days ရက် ကျန်';
  }

  @override
  String get licenseReadOnly =>
      'ဆိုင်အချက်အလက် မပြည့်သေးလို့ ရောင်းချမှု မပြီးနိုင်ပါ။';

  @override
  String get licenseInvalidKey => 'လိုင်စင် key မမှန်ကန်ပါ။';

  @override
  String get licenseActivateFailed => 'အသက်သွင်း၍ မရပါ။ အင်တာနက် စစ်ဆေးပါ။';

  @override
  String get licenseRateLimited =>
      'ကြိုးစားမှု အကြိမ်ကြိမ် များနေပါတယ် — မိနစ်အနည်းငယ် စောင့်ပြီး ထပ်ကြိုးစားပါ။';

  @override
  String get licenseActivated => 'လိုင်စင် အသက်သွင်းပြီးပါပြီ';

  @override
  String get licenseRenewTitle => 'သက်တမ်းတိုး ငွေပေးချေမှု မှတ်တမ်း';

  @override
  String get licenseRecordPayment => 'ငွေပေးချေမှု မှတ်တမ်းတင်';

  @override
  String get licensePaymentSaved => 'သက်တမ်းတိုးငွေ မှတ်တမ်းတင်ပြီး';

  @override
  String get licenseAmount => 'ပမာဏ';

  @override
  String get licenseRefNo => 'ကိုးကားနံပါတ်';

  @override
  String get licensePayTo => 'လိုင်စင်ကြေး ဤသို့ လွှဲပါ:';

  @override
  String get licenseTxnId => 'Transaction ID (နောက်ဆုံး ၆ လုံး)';

  @override
  String get licenseFixConnection => 'Connection ပြဿနာ ပြင်ရန်';

  @override
  String get licenseFixConnectionHint =>
      'App ကို ပိတ်ပြီးပြန်ဖွင့်ပြီးနောက်တောင် Publish/Register ကနေ \"session needs refreshing\" ဆိုတာ ထပ်ခါထပ်ခါ ပြနေရင် ဒါကို စမ်းကြည့်ပါ — ဒေတာ ဘာမှ မပျောက်ဘဲ device ကို ပြန်ချိတ်ဆက်ပေးပါလိမ့်မယ်။';

  @override
  String get licenseFixConnectionSuccess =>
      'Connection ပြင်ပြီးပါပြီ — ထပ်စမ်းကြည့်ပါ။';

  @override
  String get licenseDeactivate => 'လိုင်စင် ဖယ်ရှား';

  @override
  String get licenseDeactivateConfirm =>
      'ဒီ device ကနေ လိုင်စင် ဖယ်မှာလား? ကုန်ဆုံးရက် အတူတူ ဆက်ရှိနေမယ် — key အတူတူ ပြန် activate ရင် ရက်မပျောက်၊ အစက ပြန်မစပါဘူး။ ဒီအကြားမှာ ဒီ device က Free plan ကို ပြောင်းသွားမှာမို့ ရောင်းချမှု + ကုန်ပစ္စည်းစီမံခန့်ခွဲမှု ဆက်အလုပ်လုပ်ပါလိမ့်မယ်။';

  @override
  String get licensePlanLabel => 'အစီအစဉ်';

  @override
  String get licensePlanMonthly => 'လစဉ်';

  @override
  String get licensePlanFree => 'အခမဲ့ အစီအစဉ်';

  @override
  String premiumFeatureTitle(String featureName) {
    return '$featureName က Premium feature ဖြစ်ပါတယ်';
  }

  @override
  String get premiumFeatureBody =>
      'အခု Free plan ကို သုံးနေပါတယ် — ရောင်းချမှု၊ ကုန်ပစ္စည်း၊ ငွေဒရာဝါ၊ ကုန်ကျစရိတ်၊ ရောင်းဝယ်ဖက်များ၊ အကြွေးစာရင်း တို့ကတော့ ဆက်အလုပ်လုပ်ပါမယ်၊ ဒီ feature ကိုတော့ Premium subscription ဒါမှမဟုတ် license key active ရှိမှ သုံးလို့ရပါမယ်။';

  @override
  String get premiumUpgradeCta => 'Upgrade လုပ်မည်';

  @override
  String get premiumManageLicenseCta => 'လိုင်စင် စီမံရန်';

  @override
  String get analyticsBenefit1 =>
      'အရောင်းအရဆုံး ကုန်ပစ္စည်းတွေကို တစ်ချက်ကြည့်ရုံနဲ့ သိနိုင်';

  @override
  String get analyticsBenefit2 =>
      'နေ့စဉ် အမြတ် လမ်းကြောင်း (trend) ကို ကြည့်နိုင်';

  @override
  String get analyticsBenefit3 => 'ဒီလကို ပြီးခဲ့တဲ့လနဲ့ နှိုင်းယှဉ်ကြည့်နိုင်';

  @override
  String get pnlBenefit1 => 'တကယ့်အမြတ် — ဝင်ငွေ အထွက်ငွေ နှုတ်ပြီး';

  @override
  String get pnlBenefit2 => 'လစဉ် အလိုအလျောက် တွက်ချက်ပေး';

  @override
  String get equityBenefit1 =>
      'လုပ်ငန်းက ပိုင်ရှင်ကို ဘယ်လောက်တင်နေလဲ တိတိကျကျ သိနိုင်';

  @override
  String get equityBenefit2 =>
      'ရင်းနှီးထည့်ဝင်ငွေ vs ချန်ထားတဲ့အမြတ် ခွဲခြားကြည့်နိုင်';

  @override
  String get purchaseOrdersBenefit1 =>
      'ရောင်းဝယ်ဖက်ဆီက မှာထားတဲ့ ပစ္စည်းများ ခြေရာခံနိုင်';

  @override
  String get purchaseOrdersBenefit2 =>
      'ရောက်ပြီးသား/စောင့်ဆိုင်းနေဆဲ ခွဲကြည့်နိုင်';

  @override
  String get accountsPayableBenefit1 =>
      'ရောင်းဝယ်ဖက် တစ်ဦးချင်းစီကို ဘယ်လောက်ကျန်နေလဲ တိတိကျကျ သိနိုင်';

  @override
  String get accountsPayableBenefit2 =>
      'ငွေမရှင်းရသေးတဲ့ ဘောက်ချာ ဘယ်တော့မှ မမေ့တော့ဘူး';

  @override
  String get paymentAccountsBenefit1 =>
      'KBZPay၊ WavePay စတဲ့ အကောင့်တွေရဲ့ လက်ကျန် ခြေရာခံနိုင်';

  @override
  String get paymentAccountsBenefit2 =>
      'ငွေတွေ ဘယ်နေရာမှာ ရှိနေလဲ တိတိကျကျ သိနိုင်';

  @override
  String get salesReportBenefit1 =>
      'ကာလ မည်သည့်အချိန်မဆို print/share လုပ်လို့ရတဲ့ report';

  @override
  String get salesReportBenefit2 =>
      'စာရင်းကိုင်ဆီ သန့်ရှင်းတဲ့ report ပေးနိုင်';

  @override
  String get storefrontBenefit1 =>
      'ဆိုင်အတွက် အခမဲ့ အွန်လိုင်း ရောင်းချစာမျက်နှာ';

  @override
  String get storefrontBenefit2 =>
      'ဖောက်သည်တွေ ဖုန်းမခေါ်ဘဲ browse လုပ်ပြီး order တင်နိုင်';

  @override
  String get branchesBenefit1 =>
      'ဆိုင်ခွဲများကို account တစ်ခုတည်းကနေ စီမံနိုင်';

  @override
  String get branchesBenefit2 =>
      'ဆိုင်ခွဲတစ်ခုချင်းစီရဲ့ stock/ရောင်းအား သီးခြားကြည့်နိုင်';

  @override
  String get staffAccountsBenefit1 =>
      'ဝန်ထမ်းတစ်ဦးချင်းစီကို ကိုယ်ပိုင် login ပေးနိုင်';

  @override
  String get staffAccountsBenefit2 => 'PIN တစ်ခုတည်း အားလုံးမျှမသုံးရတော့ဘူး';

  @override
  String get inventoryCsvBenefit =>
      'ကုန်ပစ္စည်းစာရင်းအားလုံးကို spreadsheet အဖြစ် export လုပ်နိုင်';

  @override
  String get settingsSignInRequired =>
      'ဒါကို သုံးဖို့ ဆိုင် account တစ်ခုနဲ့ အရင် sign in ဝင်ပါ (အပေါ်က အကောင့်)။';

  @override
  String get settingsSignIn => 'Sign In ဝင်မည်';

  @override
  String get settingsOwnerModeRequired =>
      'ဒီဖုန်းက Staff mode ဖြစ်နေပါတယ်။ သုံးချင်ရင် အောက်က Owner Tools မှာ Owner ပြန်ပြောင်းပါ။';

  @override
  String get onboardingContinueFree => 'အခမဲ့ ဆက်သုံးမည်';

  @override
  String get accountSignOutPremiumConfirmBody =>
      'ဒီ device ပေါ်က Premium feature တွေ ရပ်သွားပြီး Free plan ကို ကျသွားပါလိမ့်မယ် (Sell နဲ့ Inventory ကတော့ ဆက်အလုပ်လုပ်ပါမယ်)။ ပြန်ဝင်ဖို့ email နဲ့ password ထပ်လိုအပ်ပြီး Premium ကို ပြန်ရမှာပါ။';

  @override
  String get licenseDowngradedToFreeNotice =>
      'Subscription/key သက်တမ်းကုန်သွားပါပြီ — ဒီ device က Free plan ကို ရောက်သွားပါပြီ။ Sell နဲ့ Inventory ကတော့ ဆက်အလုပ်လုပ်ပါမယ်၊ Premium ပြန်ရဖို့ renew လုပ်ပါ။';

  @override
  String get licensePlanYearly => 'နှစ်စဉ်';

  @override
  String get licenseDuration => 'ကြာချိန်';

  @override
  String get unitMonths => 'လ';

  @override
  String get unitYears => 'နှစ်';

  @override
  String get licenseGetKey => 'စာရင်းသွင်းစဉ်က ရရှိသော key ကို ထည့်ပါ။';

  @override
  String get licenseHaveKeyTitle => 'License key ရပြီးသားလား?';

  @override
  String get licensePaymentProofLabel => 'ငွေလွှဲ Screenshot (မထည့်လည်းရ)';

  @override
  String get licensePaymentProofAttach => 'Screenshot ထည့်ရန်';

  @override
  String get licensePaymentProofAttached => 'Screenshot ထည့်ပြီးပါပြီ';

  @override
  String get licenseNoKeyTitle => 'Key မရှိသေးဘူးလား?';

  @override
  String get licenseNoKeyHint =>
      'App Reference ID နဲ့ Support Viber ကို ဆက်သွယ်ပါ — license key ပို့ပေးပါမယ်။ ပြီးရင် အောက်မှာ activate လုပ်ပါ။';

  @override
  String get licenseContactSupportTitle => 'Support ဆက်သွယ်ရန်';

  @override
  String get licensePremiumContactHint =>
      'Premium ကို app အပြင် Support က ဖွင့်ပေးသည် (license key သို့မဟုတ် Online account)။ Viber နံပါတ် ကူးပြီး App Reference ID ပို့ကာ upgrade/renew တောင်းပါ။ ငွေပေးချေမှုကို ဤ app ထဲတွင် မကောက်ပါ။';

  @override
  String get licensePremiumContactHintOnline =>
      'Online ဆိုင်အတွက် Premium ကို Support က သင့် shop account ပေါ်မှာ ဖွင့်ပေးသည် (license key ရိုက်စရာမလို)။ Viber နံပါတ် ကူးပြီး sign-in သုံးတဲ့ email ပို့ကာ upgrade/renew တောင်းပါ။ ငွေပေးချေမှုကို ဤ app ထဲတွင် မကောက်ပါ။';

  @override
  String get licenseSubscribe => 'Subscribe';

  @override
  String get licenseGetKeyTitle => 'License Key ယူရန်';

  @override
  String get licenseOnlineApplyHint =>
      'Admin approve လုပ်ပြီးရင် Account ပေါ်မှာ အလိုအလျောက် သက်ရောက်ပါလိမ့်မယ် — Key ထည့်စရာမလိုပါ။';

  @override
  String get licenseRenew => 'သက်တမ်းတိုး';

  @override
  String get licenseBuyOrRenewTitle =>
      'Premium ဝယ်ရန် သို့မဟုတ် သက်တမ်းတိုးရန်';

  @override
  String get licenseBuyOrRenewIntro =>
      'နည်းလမ်း နှစ်ခု — website ကနေ၊ သို့မဟုတ် Viber။ ငွေပေးချေမှုကို ဤ app ထဲတွင် မကောက်ပါ။';

  @override
  String get licensePayOnline => 'အွန်လိုင်းက ပေးချေမည်';

  @override
  String get licensePayOnlineHint =>
      'ကျွန်ုပ်တို့ website ပေါ်မှာ ငွေပေးချေမှု တောင်းဆိုမှု ပို့ပါ။ Premium အသစ်ဝယ်တာရော သက်တမ်းတိုးတာရော ရပါတယ် — app ထဲ account မလိုပါ။';

  @override
  String get licenseChooseRegionTitle => 'သင့်ဆိုင် ဘယ်နေရာမှာလဲ';

  @override
  String get licenseRegionMyanmar => 'မြန်မာနိုင်ငံ';

  @override
  String get licenseRegionInternational => 'အခြားဒေသ';

  @override
  String get licenseContactViber => 'Viber ကနေ ဆက်သွယ်မည်';

  @override
  String get licenseContactViberHint =>
      'Viber ပွင့်ပါမယ်။ အပေါ်က App Reference ID နဲ့ Premium ဝယ်ရန် သို့မဟုတ် သက်တမ်းတိုးရန် တောင်းပါ။';

  @override
  String get licenseContactViberHintOnline =>
      'Viber ပွင့်ပါမယ်။ sign-in သုံးတဲ့ email နဲ့ Premium ဝယ်ရန် သို့မဟုတ် သက်တမ်းတိုးရန် တောင်းပါ။';

  @override
  String get supportViberOpenFailed =>
      'Viber မဖွင့်နိုင်ပါ။ နံပါတ်ကို ကူးပြီးပါပြီ — Viber ထဲမှာ paste လုပ်ပါ။';

  @override
  String get licenseAfterPaymentTitle =>
      'ပေးပြီးပြီလား၊ Support ကို ပြောပြီးပြီလား?';

  @override
  String get licenseManagedElsewhereTitle => 'Premium လိုင်စင်';

  @override
  String get licenseManagedElsewhereBody =>
      'Premium ကို ဤ app ပြင်ပတွင် သင့် All In One POS ဝန်ဆောင်မှုပေးသူနှင့် စီစဉ်ရပါသည်။ ဤစက် (သို့) ဆိုင် account ပေါ်တွင် active ဖြစ်သည်နှင့် Premium features များ အလိုအလျောက် ပွင့်ပါမည်။';

  @override
  String get licenseAlreadyLicensedTitle => 'Premium ရှိပြီးသားလား?';

  @override
  String licenseExpiringSoon(int days) {
    return 'License သက်တမ်း $days ရက် ကျန် — တိုးရန် နှိပ်ပါ။';
  }

  @override
  String licenseExpiringSoonNeutral(int days) {
    return 'License သက်တမ်း $days ရက် ကျန်ပါတယ်။';
  }

  @override
  String get licenseThankYouTitle => 'ကျေးဇူးတင်ပါတယ်!';

  @override
  String get licenseThankYou24h =>
      'ငွေစစ်ဆေးပြီး ၂၄ နာရီအတွင်း စတင်အသုံးပြုလို့ရပါမယ်။';

  @override
  String get licenseFreeTrial => 'Premium စမ်းကြည့်ရန်';

  @override
  String get licensePlanTrial => 'အခမဲ့ စမ်းသုံး';

  @override
  String get licenseTrialStartConfirm =>
      'ဒီ device မှာ Premium ၂ လ စမ်းသုံးမှုကို အခုပဲ စတင်မလား? Premium feature အကုန် ချက်ချင်း ဖွင့်ပေးပါမယ်၊ ငွေပေးစရာ မလိုပါ။ Device တစ်ခုကို တစ်ကြိမ်ပဲ — စတင်ဖို့ အင်တာနက် လိုအပ်ပါတယ်။';

  @override
  String get licenseTrialSelfServeHint =>
      '၂ လ၊ Premium feature အကုန်၊ ငွေပေးစရာ မလို — device တစ်ခုကို တစ်ကြိမ်ပဲ။';

  @override
  String get licenseTrialContactHint =>
      'Premium စမ်းသုံးခွင့်ကို app ထဲက မယူရပါ — Support ကသာ အခမဲ့ ပေးပါတယ်။ Viber နံပါတ် ကူးပြီး App Reference ID ပို့ကာ trial key တောင်းပါ။';

  @override
  String get licenseTrialContactHintOnline =>
      'Online ဆိုင်အတွက် Premium စမ်းသုံးခွင့်ကို Support ကသာ အခမဲ့ ပေးပါတယ်။ Viber နံပါတ် ကူးပြီး shop account email ပို့ကာ အဲဒီ account ပေါ် trial တောင်းပါ — key ရိုက်စရာမလိုပါ။';

  @override
  String get licenseTrialViberMissing =>
      'Support Viber မသတ်မှတ်ရသေးပါ။ Settings → Support ရနိုင်မှ သုံးပါ၊ သို့မဟုတ် App Reference ID နဲ့ တခြားလမ်းက ဆက်သွယ်ပါ။';

  @override
  String get licenseTrialStarted => 'အခမဲ့ ၂ လ စမ်းသုံးမှု စတင်ပြီး';

  @override
  String get licenseTrialUsed =>
      'ဒီ device မှာ အခမဲ့ စမ်းသုံးမှု သုံးပြီးသားပါ။';

  @override
  String get licenseRefId => 'App Reference ID';

  @override
  String get licenseAccountEmail => 'ဆိုင် account email';

  @override
  String get licenseAccountEmailMissing =>
      'Support က ရှာနိုင်အောင် Settings → အကောင့် မှာ sign in ဝင်ထားပါ။';

  @override
  String get licenseRequestSent =>
      'တောင်းဆိုမှု ပို့ပြီးပါပြီ။ ငွေစစ်ဆေးပြီး key ပို့ပေးပါမယ်။';

  @override
  String licenseRequestSentViber(String viber) {
    return 'တောင်းဆိုမှု ပို့ပြီးပါပြီ။ Viber $viber ကနေ key ပို့ပေးပါမယ်။';
  }

  @override
  String get licenseCheckRenewal => 'သက်တမ်းတိုး စစ်ဆေး';

  @override
  String get licenseRefreshed => 'လိုင်စင်အခြေအနေ update ဖြစ်ပြီး';

  @override
  String get licenseRenewHint =>
      'Support က သက်တမ်းတိုးပေးပြီးရင် \'သက်တမ်းတိုး စစ်ဆေး\' ကို နှိပ်ပါ (သို့မဟုတ် key အသစ် activate လုပ်ပါ)။';

  @override
  String get licenseRenewHintOnline =>
      'Support က Online subscription သက်တမ်းတိုးပေးပြီးရင် \'သက်တမ်းတိုး စစ်ဆေး\' ကို နှိပ်ပါ — Premium က account ပေါ် အလိုအလျောက် သက်ရောက်ပါတယ် (key မလို)။';

  @override
  String get licenseRenewNotFound =>
      'ဒီ account အတွက် subscription မတွေ့သေးပါ။ Support က သက်တမ်းတိုးပြီးရင် \'သက်တမ်းတိုး စစ်ဆေး\' ကို ထပ်နှိပ်ပါ။';

  @override
  String get deviceSectionTitle => 'Device များ';

  @override
  String deviceAddOnlineHint(int free) {
    return 'ဒီဖုန်းကို မရေပါ။ ဖုန်း/ကွန်ပျူတာ အပို: owner သို့မဟုတ် staff email နဲ့ sign in ဝင်ပြီး Check for renewal နှိပ်ပါ။ Key မလိုပါ။ အပို $free လုံး သုံးနိုင်ပါတယ် (ဖုန်းနဲ့ ကွန်ပျူတာ တူတူပဲ)။ အခမဲ့ ၂ လုံးကျော်ရင် Support က ခွင့်ပြုပေးပါတယ်။';
  }

  @override
  String get premiumFeatureBodyOnline =>
      'Free plan ဖြစ်နေပါတယ် — ရောင်းချမှု၊ ကုန်ပစ္စည်း၊ ငွေဒရာဝါ၊ ကုန်ကျစရိတ်၊ ရောင်းဝယ်ဖက်များ၊ အကြွေးစာရင်း တို့ ဆက်သုံးနိုင်ပြီး ဤ feature အတွက် Online Premium subscription လိုအပ်ပါတယ်။';

  @override
  String deviceCount(int used, int free) {
    return 'အပို device $used/$free သုံးထားပြီး';
  }

  @override
  String get deviceThisDevice => 'ဒီ device';

  @override
  String deviceLastActive(String when) {
    return 'နောက်ဆုံးအသုံးပြုခဲ့သည် $when';
  }

  @override
  String get deviceNeverVerified => 'မ activate လုပ်ရသေးပါ';

  @override
  String get deviceAdd => 'Device အသစ်ထည့်ရန်';

  @override
  String get deviceRelease => 'ဖြုတ်ရန်';

  @override
  String get deviceReleaseConfirmTitle => 'ဒီ device ကို ဖြုတ်မှာလား?';

  @override
  String get deviceReleaseConfirmBody =>
      'ဒီ device က နောက်တစ်ကြိမ် license စစ်ဆေးချိန်မှာ ဒီဆိုင်ကို ဝင်ရောက်ခွင့် ဆုံးရှုံးသွားပါမည်။ နောက်ပိုင်း အဲဒီနေရာမှာ device အသစ် ထပ်ထည့်နိုင်ပါသည်။';

  @override
  String get deviceReleased => 'Device ကို ဖြုတ်ပြီးပါပြီ';

  @override
  String get deviceKeyReadyTitle => 'Device အသစ် အသင့်ဖြစ်ပါပြီ';

  @override
  String get deviceKeyReadyHint =>
      'Device အသစ်ရဲ့ activate screen မှာ ဒီ QR code ကို scan ဖတ်ပါ၊ ဒါမှမဟုတ် အောက်က key ကို ရိုက်ထည့်ပါ။';

  @override
  String get deviceKeyCopied => 'Key ကို ကူးယူပြီးပါပြီ';

  @override
  String get devicePaymentRequiredTitle => 'Device fee ပေးချေရန် လိုအပ်သည်';

  @override
  String devicePaymentRequiredBody(int free, String fee) {
    return 'ဒီဆိုင်က ပင်မဖုန်းအပါအဝင် အခမဲ့ device $free လုံး သုံးပြီးပါပြီ။ ထပ်ထည့်ရန် $fee (တစ်ကြိမ်တည်း) ကျသင့်ပါမည် — ပေးချေပြီးရင် သင့် App Reference ID နဲ့ support ကို ဆက်သွယ်ပြီး device အသစ်ရဲ့ key ကို ရယူပါ။';
  }

  @override
  String get deviceOnlyOnPaidPlan =>
      'Subscription active ဖြစ်မှသာ device ထပ်ထည့်နိုင်ပါသည် (free trial အတွင်း မရနိုင်ပါ)။';

  @override
  String get deviceRequestFailed => 'Device ထပ်ထည့်လို့ မရပါ — ထပ်စမ်းကြည့်ပါ။';

  @override
  String get deviceRoleTitle => 'ဒီ device ကို ဘယ်သူ့အတွက် ထည့်မှာလဲ?';

  @override
  String get deviceRoleHint =>
      'အခုပဲ ရွေးထားလိုက်ရင် — device အသစ် activate ဖြစ်တာနဲ့ ချက်ချင်း မှန်ကန်စွာ ပြင်ဆင်ပြီးသားဖြစ်နေပါမယ် — device အသစ်ပေါ်မှာ ထပ်ပြင်စရာ မလိုတော့ပါ။';

  @override
  String get deviceRoleStaffMember => 'ဝန်ထမ်း (ရွေးချယ်ခွင့်)';

  @override
  String get deviceRoleAppliesOnScan =>
      'ဒီ QR ကို scan ဖတ်ပြီး activate လုပ်တဲ့အခါ Staff mode ကို အလိုအလျောက် သတ်မှတ်ပေးပါမည်။';

  @override
  String get invWebActivateTitle => 'ဒီ computer မှာ invoice ကြည့်ရန်';

  @override
  String get invWebActivateHint =>
      'ဖုန်းမှာ သုံးနေတဲ့ ဆိုင် email နဲ့ sign in ဝင်ပါ။ ဒီ computer က extra device တစ်လုံးအဖြစ် ရေပါတယ်။ Account မရှိတဲ့ Free plan: Windows POS app ဖွင့်ပြီး Continue Free နှိပ်ပါ — key မလိုပါ။';

  @override
  String get invWebFreeHint =>
      'Free plan က activate မလိုပါ။ ဒီ computer မှာ ရောင်းချင်ရင် Windows POS app ဖွင့်ပြီး Continue Free နှိပ်ပါ။ ဒီစာမျက်နှာက ဆိုင် account နဲ့ sign in ဝင်မှ invoice ပြပါတယ်။';

  @override
  String get invWebKeySection => 'Offline device key ရှိပါသလား?';

  @override
  String get invWebKeyLabel => 'Device key';

  @override
  String get invWebActivateButton => 'Key နဲ့ Activate';

  @override
  String get invWebErrorEmptyKey => 'Device key ထည့်ပါ';

  @override
  String get invWebErrorEmptySignIn => 'Email နဲ့ password ထည့်ပါ';

  @override
  String get invWebErrorNotAShop => 'ဒီ login က ဆိုင် account မဟုတ်ပါ';

  @override
  String get invWebErrorInvalidKey =>
      'ဒီ key က မမှန်ကန် (သို့) သက်တမ်းကုန်သွားပါပြီ';

  @override
  String get invWebErrorDeviceMismatch =>
      'ဒီ key က တခြား device တစ်ခုနဲ့ချိတ်ဆက်ပြီးသားပါ';

  @override
  String get invWebErrorPaymentRequired =>
      'ဒီ computer ထပ်ထည့်ဖို့ device fee ပေးရပါမယ် — support ကို ဆက်သွယ်ပြီး ငွေပေးချေပါ၊ ပြီးမှ ထပ်ကြိုးစားပါ';

  @override
  String get invWebErrorActivationFailed =>
      'Activate မလုပ်နိုင်ပါ — key ကို ပြန်စစ်ပြီး ထပ်ကြိုးစားပါ';

  @override
  String get invWebErrorNetwork =>
      'Network error — connection ကို စစ်ပြီး ထပ်ကြိုးစားပါ';

  @override
  String get invWebErrorRefreshPending =>
      'Activate ဖြစ်သွားပါပြီ — ဆက်လုပ်ရန် ဒီစာမျက်နှာကို reload လုပ်ပါ';

  @override
  String get invWebSignOut => 'ဒီ computer ကို sign out လုပ်မည်';

  @override
  String get invWebDownloadPdf => 'PDF ဒေါင်းလုဒ်';

  @override
  String get invWebSearchHint =>
      'Invoice နံပါတ်၊ ဝယ်သူအမည်၊ (သို့) ဖုန်းနံပါတ်ဖြင့် ရှာပါ';

  @override
  String get invWebNoResults => 'ရှာဖွေမှုနှင့် ကိုက်ညီသော invoice မရှိပါ။';

  @override
  String get referralTitle => 'မိတ်ဆွေမျှ၍ ဝင်ငွေရ';

  @override
  String get referralSubtitle =>
      'သင့်ကုဒ်ကို မျှဝေပါ။ သင်စပ်ပေးထားတဲ့ ဆိုင်က လတိုင်း ကြေးပေးတိုင်း သင် commission ရပြီး license သက်တမ်းထဲ တိုက်ရိုက် ပေါင်းသွားပါမယ်။';

  @override
  String get referralMyCode => 'ကျွန်ုပ်၏ referral ကုဒ်';

  @override
  String get referralShare => 'ကုဒ် မျှဝေမည်';

  @override
  String get referralCopied => 'ကုဒ် ကူးယူပြီးပါပြီ';

  @override
  String referralShareText(String code, String shop) {
    return 'သင့်ဆိုင်အတွက် All In One POS သုံးပါ! စာရင်းသွင်းတဲ့အခါ ကျွန်ုပ်၏ referral ကုဒ် $code ကို ထည့်ပါ။ — $shop';
  }

  @override
  String get referralBalance => 'သင့် ဝင်ငွေ';

  @override
  String get referralEarnedTotal => 'စုစုပေါင်း ရရှိပြီး';

  @override
  String get referralActiveShops => 'သင်စပ်ပေးထားသော ဆိုင်များ';

  @override
  String get referralRedeem => 'License ရက်အဖြစ် လဲယူမည်';

  @override
  String referralRedeemDone(int months) {
    return 'သင့် license ကို $months လ ပေါင်းထည့်ပြီးပါပြီ!';
  }

  @override
  String get referralRedeemNotEnough =>
      'လက်ကျန်ငွေ မလုံလောက်သေးပါ — နောက်ထပ် ၁ ဆိုင် စပ်ပေးပါ!';

  @override
  String referralNextGoal(String amount) {
    return 'နောက် အခမဲ့ ၁ လ အတွက် $amount လိုပါသေးသည်';
  }

  @override
  String get referralCodeOptional => 'Referral ကုဒ် (ရွေးချယ်နိုင်)';

  @override
  String get referralCodeHint =>
      'မိတ်ဆွေ့ရဲ့ ကုဒ် ရှိလား? ထည့်ပါ — သင့်ငွေပေးချေမှု approve ဖြစ်တဲ့အခါ သူ commission ရပါမယ်။';

  @override
  String get referralEmpty =>
      'referral မရှိသေးပါ။ ကုဒ်ကို မျှဝေပြီး လတိုင်း ဝင်ငွေ စတင်ရှာပါ။';

  @override
  String get referralNotifTitle => '🎉 Commission ဝင်ပါပြီ!';

  @override
  String referralNotifBody(String amount) {
    return '$amount ကို သင့် referral wallet ထဲ ပေါင်းထည့်လိုက်ပါပြီ။ App ဖွင့်၍ license အခမဲ့ရက်အဖြစ် လဲယူပါ။';
  }

  @override
  String get referralHowTitle => 'Refer & earn ဘယ်လို အလုပ်လုပ်လဲ';

  @override
  String get referralStep1 => 'သင့်ကုဒ်ကို တခြားဆိုင်ရှင်များထံ မျှဝေပါ။';

  @override
  String get referralStep2 =>
      'သူတို့ subscribe လုပ်ပြီး ကြေးပေးတဲ့အခါ သင့်ကုဒ်ကို ရိုက်ထည့်ပါတယ်။';

  @override
  String get referralStep3 =>
      'သူတို့ လစဉ် ကြေးဆက်ပေးနေသရွေ့ သင် commission ရပါတယ်။';

  @override
  String get referralStep4 =>
      'သင့် balance ကို license အခမဲ့ရက်အဖြစ် အချိန်မရွေး လဲယူပါ။';

  @override
  String get referralHaveCode => 'Referral ကုဒ် ရှိပါသလား?';

  @override
  String get referralHaveCodeHint =>
      'မိတ်ဆွေက ကုဒ်ပေးထားလား? အောက်မှာ ရိုက်ထည့်ပါ — သင့်ငွေပေးချေမှု approve ဖြစ်ရင် သူ commission ရပါမယ်။ မရှိရင် ကွက်လပ်ထားခဲ့ပါ။';

  @override
  String get referralRedeemConfirmTitle => 'လဲယူမလား?';

  @override
  String referralRedeemConfirmBody(int months, String amount) {
    return 'သင့် balance မှ $amount သုံးပြီး license ကို $months လ ပေါင်းထည့်မလား?';
  }

  @override
  String get referralRedeemAction => 'လဲယူမည်';

  @override
  String get backupTitle => 'Backup & ပြန်ယူ';

  @override
  String get backupHint =>
      'သင့် data ကို ဒီဖုန်းထဲမှာ သိမ်းထားပါတယ်။ Backup file ထုတ်ပြီး လုံခြုံစွာ သိမ်းပါ (ဥပမာ Viber → My Notes သို့ ပို့ပါ)။';

  @override
  String get backupExport => 'Backup ထုတ်';

  @override
  String get backupExportHint =>
      'ဒီဆိုင်ရဲ့ လုပ်ငန်း data (အရောင်း၊ stock၊ အော်ဒါ၊ ဖောက်သည်၊ ငွေသား၊ ဝန်ထမ်း၊ ပေးသွင်းသူ) ကို file အဖြစ်သိမ်းပြီး share။ ဖုန်း settings နဲ့ sync တန်းကို မပါဝင်ပါ။';

  @override
  String get backupImport => 'Backup ပြန်သွင်း';

  @override
  String get backupImportHint => 'Backup file ကနေ data ပြန်ယူ';

  @override
  String get backupShareSubject => 'All In One POS backup';

  @override
  String get backupShareText =>
      'All In One POS data backup။ နောက်မှ ပြန်ယူဖို့ ဒီ file ကို သိမ်းထားပါ။';

  @override
  String get backupImportConfirmTitle => 'data အားလုံး အစားထိုးမလား?';

  @override
  String get backupImportConfirmBody =>
      'ဒါက ဒီဆိုင်ရဲ့ လက်ရှိ လုပ်ငန်း data (ကုန်ပစ္စည်း၊ အရောင်း၊ အော်ဒါ၊ ဖောက်သည်၊ ငွေသား၊ ဝန်ထမ်း၊ ပေးသွင်းသူ စသည်) ကို ဖျက်ပြီး backup နဲ့ အစားထိုးမှာပါ။ ဖုန်း settings ကျန်ပါမည်။ ပြန်ပြင်လို့ မရပါ။';

  @override
  String get backupImportConfirmAction => 'အစားထိုး';

  @override
  String backupImportDone(int count) {
    return 'row $count ခု ပြန်ယူပြီး';
  }

  @override
  String backupFailed(String error) {
    return 'Backup မအောင်မြင်: $error';
  }

  @override
  String get backupInvalidFile => 'ဒါက မှန်ကန်တဲ့ backup ဖိုင် မဟုတ်ပုံရပါတယ်။';

  @override
  String get settingsSync => 'Cloud ချိတ်ဆက်မှု';

  @override
  String get syncNow => 'ယခု sync လုပ်';

  @override
  String get syncIdle => 'အသစ်ဖြစ်နေသည်';

  @override
  String get syncPendingUploads => 'တင်ရန် ကျန်ရှိနေသည်';

  @override
  String get syncHasIssues =>
      'Sync ပြန်ကြိုးစားနေသည် — လိုရင် Branches ဖွင့်ပါ';

  @override
  String get syncSyncing => 'sync လုပ်နေသည်…';

  @override
  String get syncOffline => 'အော့ဖ်လိုင်း';

  @override
  String get syncError => 'sync အမှား';

  @override
  String get syncDisabled => 'Cloud sync မသတ်မှတ်ရသေးပါ';

  @override
  String get syncNever => 'sync မလုပ်ရသေးပါ';

  @override
  String syncLastSynced(String time) {
    return 'နောက်ဆုံး sync: $time';
  }

  @override
  String get syncRealtimeOn => 'Live update ဖွင့်ထားသည်';

  @override
  String syncIssuesTitle(int count) {
    return 'Sync အခြေအနေ ($count)';
  }

  @override
  String get syncIssuesEmpty => 'စောင့်ဆိုင်းနေသည် မရှိ — sync ရှင်းပါပြီ။';

  @override
  String get syncIssuesBackgroundHint =>
      'Held uploads ကို background sync က အလိုအလျောက် ပြီးစေပါတယ်။ Offline ဖြစ်ခဲ့ရင် online ပြန်ရောက်မှ ပြီးပါမယ်။ ယခု ပြန်လုပ်ချင်ရင် Sync now နှိပ်ပါ။';

  @override
  String syncIssuesPendingHint(int count) {
    return 'Upload $count ခု ပြန်ကြိုးစားနေဆဲ — Sync now နှိပ်ပါ။';
  }

  @override
  String syncIssuesQuarantinedRow(String table) {
    return 'ပြီးဆုံးနေသည်: $table';
  }

  @override
  String get syncIssuesQuarantinedHeld =>
      'Cloud sync အလိုအလျောက် ပြီးသည်အထိ ဒီစက်မှာ ထားထားသည်။';

  @override
  String get syncIssuesInvoiceCollision =>
      'ဒီ invoice နံပါတ်ကို တခြား device ကနေ အရောင်းတစ်ခုက အသုံးပြုပြီးသားဖြစ်နေသည်။ အရောင်းကိုယ်တိုင်တော့ ဘေးကင်းပါသည် — invoice နံပါတ်အသစ် ပြန်ပေးရန် support ကို ဆက်သွယ်ပါ။';

  @override
  String get navOrders => 'အော်ဒါ';

  @override
  String get ordersTitle => 'Social အော်ဒါများ';

  @override
  String get ordersEmpty => 'အော်ဒါ မရှိသေးပါ။ ထည့်ရန် + ကိုနှိပ်ပါ။';

  @override
  String get orderNew => 'အော်ဒါအသစ်';

  @override
  String get orderEditTitle => 'အော်ဒါ ပြင်ဆင်';

  @override
  String get orderStatusNew => 'အသစ်';

  @override
  String get orderStatusDelivered => 'ရောက်ရှိပြီး';

  @override
  String get orderStatusCancelled => 'ပြန်ပို့ပြီး';

  @override
  String get orderChannelFacebook => 'Facebook';

  @override
  String get orderChannelViber => 'Viber';

  @override
  String get orderChannelTiktok => 'TikTok';

  @override
  String get orderChannelPhone => 'ဖုန်း';

  @override
  String get orderChannelStorefront => 'ဝက်ဘ်ဆိုက်';

  @override
  String get orderChannelOther => 'အခြား';

  @override
  String get orderCustomerName => 'ဖောက်သည်အမည်';

  @override
  String get orderCustomerPhone => 'ဖုန်း (ရွေးချယ်နိုင်)';

  @override
  String get orderChannel => 'ချန်နယ်';

  @override
  String get orderDeliveryAddress => 'ပို့ဆောင်လိပ်စာ';

  @override
  String get orderDeliveryFee => 'ပို့ဆောင်ခ';

  @override
  String get orderNote => 'မှတ်စု';

  @override
  String get orderMoreDetails => 'အသေးစိတ် (ဖုန်း၊ လိပ်စာ၊ ပို့ဆောင်ခ၊ မှတ်စု)';

  @override
  String get orderItems => 'ပစ္စည်းများ';

  @override
  String get orderAddItem => 'ပစ္စည်းထည့်';

  @override
  String get orderItemName => 'ပစ္စည်းအမည်';

  @override
  String get orderItemPrice => 'ဈေးနှုန်း';

  @override
  String get orderItemQty => 'အရေအတွက်';

  @override
  String get orderItemsTotal => 'ပစ္စည်း စုစုပေါင်း';

  @override
  String get orderTotal => 'စုစုပေါင်း';

  @override
  String get orderPayment => 'ငွေပေးချေမှု';

  @override
  String get orderPayUnpaid => 'မပေးရသေး';

  @override
  String get orderPaymentTransfer => 'ဝေလက် လွှဲပြောင်း';

  @override
  String get orderPaymentCod => 'အိမ်ရောက်ငွေချေ';

  @override
  String get orderPaymentCodNote =>
      'အိမ်ရောက်ငွေချေ — ပစ္စည်းရောက်မှ ငွေကောက်ခံမည်';

  @override
  String get orderPayPaid => 'ပေးပြီး';

  @override
  String get orderAwaitingPayment => 'ငွေမရရှိသေးပါ';

  @override
  String get orderMarkAsPaid => 'ငွေရရှိပြီဟု မှတ်သားရန်';

  @override
  String get orderMarkAsUnpaid => 'ငွေမရရှိသေးဟု ပြန်ပြင်ရန်';

  @override
  String get orderSave => 'အော်ဒါ သိမ်း';

  @override
  String get orderEdit => 'ပြင်ဆင်';

  @override
  String get orderDelete => 'အော်ဒါ ဖျက်';

  @override
  String get orderDeleteConvertedWarn =>
      'ဒီအော်ဒါက ငွေတောင်းခံလွှာ ထွက်ပြီးသား။ အော်ဒါ ဖျက်လိုက်ရုံသာ — ငွေတောင်းခံလွှာနှင့် ပြန်အမ်းငွေတို့က Invoices စာရင်းမှာ ရှိနေမည်။';

  @override
  String get orderInvalidLine =>
      'အတန်းများ စစ်ပါ — ဖြည့်ထားသော အတန်းတိုင်းမှာ အမည်နှင့် အရေအတွက် နှစ်ခုလုံး လိုသည်';

  @override
  String get orderDeleteConfirm => 'ဒီအော်ဒါ ဖျက်မလား? ပြန်ဖျက်၍ မရပါ။';

  @override
  String get orderBlockCustomer => 'ဒီ IP ကို ပိတ်ပင်မည်';

  @override
  String orderBlockCustomerConfirm(String ip) {
    return '$ip ကို သင့် storefront ပေါ်မှာ order အသစ် ထပ်တင်ခွင့် ပိတ်ပင်မလား?';
  }

  @override
  String get orderCustomerBlocked => 'IP ပိတ်ပင်ပြီး';

  @override
  String get orderBlockFailed => 'ဒီ IP ကို ပိတ်ပင်၍ မရပါ။';

  @override
  String get orderIpCopied => 'IP ကူးယူပြီး';

  @override
  String get orderBlockIpHint =>
      'Block ကို နှိပ်ရင် ဒီ network ကနေ web order အသစ် တင်လို့ မရတော့ပါ။ ပြန်ဖြေချင်ရင် Settings → ကျွန်ုပ်၏ Web ဆိုင် → ပိတ်ပင်ထားသော IP များ မှာ ဖြေနိုင်ပါတယ်။';

  @override
  String get orderNoCustomerIp => 'ဒီ order မှာ IP မပါပါ';

  @override
  String get orderNoCustomerIpHint =>
      'ဒီ web order ကို IP မသိမ်းခင် တင်ထားတာပါ။ ပိတ်ချင်ရင် Settings → ကျွန်ုပ်၏ Web ဆိုင် → ပိတ်ပင်ထားသော IP များ မှာ IP ထည့်ပါ။';

  @override
  String get orderBlockCustomerHow =>
      'ပိတ်ပြီးရင် ဒီ network က web order အသစ် တင်လို့ မရတော့ပါ။ ရှိပြီးသား order တွေ မပျက်ပါ။ Settings → ပိတ်ပင်ထားသော IP များ မှာ ပြန်ဖြေနိုင်ပါတယ်။';

  @override
  String get orderLowStockAtOrder =>
      'ဒီ order တင်တဲ့အချိန်မှာ မှတ်တမ်းတင်ထားတဲ့ လက်ကျန်ထက် ပိုတောင်းထားပါတယ်';

  @override
  String get orderCarrierHint => 'Carrier ရိုက်ထည့် (သို့) ရွေးပါ';

  @override
  String get orderHandOffButton => 'Carrier ကို အပ်ပြီး';

  @override
  String orderHandedOffTo(String carrier) {
    return '$carrier ကို အပ်ပြီး';
  }

  @override
  String get orderChangeCarrier => 'ပြောင်းမည်';

  @override
  String get orderConvertToSale => 'အရောင်းအဖြစ် ပြောင်း';

  @override
  String get orderConvertHint =>
      'ကောက်ခံရရှိသော ပမာဏကို အရောင်းအဖြစ် မှတ်ပြီး catalog ပစ္စည်းများအတွက် stock နှုတ်ပါမည်။ မပေးရသေးသော COD ကို ကောက်ခံသည့် ပမာဏ ထည့်မှသာ ပေးပြီးဟု မှတ်ပါမည်။';

  @override
  String orderConverted(String invoice) {
    return 'အော်ဒါကို အရောင်းအဖြစ် ပြောင်းပြီး ($invoice)။';
  }

  @override
  String get orderConvertFailed =>
      'ဒီအော်ဒါကို အရောင်းအဖြစ် ပြောင်း၍မရပါ။ ထပ်ကြိုးစားကြည့်ပါ။';

  @override
  String get orderAlreadySale => 'အရောင်းအဖြစ် မှတ်တမ်းတင်ပြီးပြီ။';

  @override
  String get orderCancel => 'ပြန်ပို့အဖြစ် မှတ်မည်';

  @override
  String get orderCancelConfirmTitle => 'ဒီအော်ဒါကို ပယ်ဖျက်မည်လား?';

  @override
  String get orderCancelConfirmBody =>
      'အော်ဒါကို ပယ်ဖျက်အဖြစ် မှတ်ပါမည်။ အရောင်းအဖြစ် မပြောင်းရသေးသဖြင့် ပြေစာ သို့မဟုတ် stock ပြန်ပြင်စရာ မရှိပါ။';

  @override
  String get orderRestore => 'ပြန်ပို့မှု ပြန်ရုပ်သိမ်းမည်';

  @override
  String get orderReturnConfirmTitle => 'ဒီအော်ဒါကို ပြန်ပို့မည်လား?';

  @override
  String orderReturnConfirmBody(String amount) {
    return 'ဒါက $amount ပြန်အမ်းပေးမည်၊ အရောင်းကို ပြန်ပြင်ပေးမည်၊ ကုန်ပစ္စည်းလက်ကျန်ကိုလည်း ပြန်ထည့်ပေးမည်ဖြစ်ပြီး ပြန်ရုပ်သိမ်းလို့ မရတော့ပါ။';
  }

  @override
  String get orderReturnFailed =>
      'ပြန်ပို့မှုကို လုပ်ဆောင်၍မရပါ။ ထပ်မကြိုးစားမီ Invoices တွင် စစ်ဆေးပါ။';

  @override
  String get orderNeedsName => 'ဖောက်သည်အမည် ထည့်ပါ။';

  @override
  String get orderNeedsItem => 'ပစ္စည်း အနည်းဆုံး တစ်ခု ထည့်ပါ။';

  @override
  String get orderSaved => 'အော်ဒါ သိမ်းပြီး။';

  @override
  String orderItemsCount(int count) {
    return 'ပစ္စည်း $count ခု';
  }

  @override
  String get orderPickPaymentMethod => 'ငွေပေးချေနည်း';

  @override
  String get orderPaymentProof => 'ငွေပေးချေမှု screenshot';

  @override
  String get orderInvoice => 'ဘောက်ချာ မျှဝေ';

  @override
  String get orderPrint => 'Print ထုတ်';

  @override
  String get deliveryTownship => 'မြို့နယ်';

  @override
  String get deliveryTownshipNone => 'မြို့နယ် မသတ်မှတ်ရသေး';

  @override
  String get deliveryCarrier => 'ပို့ဆောင်ရေးကုမ္ပဏီ';

  @override
  String get deliveryCarrierNone => 'မသတ်မှတ်ရသေး';

  @override
  String get deliveryTrackingNumber => 'Tracking / waybill နံပါတ်';

  @override
  String get deliveryTrackingHint =>
      'ကုမ္ပဏီရဲ့ app/website မှာ book ပြီးမှ ဒီမှာ ရိုက်ထည့်ပါ';

  @override
  String get deliverySave => 'ပို့ဆောင်ရေးအချက်အလက် သိမ်း';

  @override
  String get deliverySaved => 'ပို့ဆောင်ရေးအချက်အလက် သိမ်းပြီး';

  @override
  String get deliveryManualNote =>
      'အခုထိ ကုမ္ပဏီ API တိုက်ရိုက် မချိတ်ဆက်ရသေးပါ — waybill ကို ကုမ္ပဏီရဲ့ app/website မှာ ကိုယ်တိုင် book လုပ်ပြီး tracking number ကို ဒီမှာ မှတ်ထားပါ။';

  @override
  String get ordersSearchHint => 'နာမည်၊ ဖုန်း၊ order #၊ invoice # ရှာ';

  @override
  String get ordersNoMatch => 'filter နဲ့ ကိုက်ညီတဲ့ order မရှိပါ။';

  @override
  String get ordersClearFilters => 'filter ရှင်း';

  @override
  String get orderFilterChannel => 'ချန်နယ်';

  @override
  String get orderFilterPayment => 'ငွေပေးချေမှု';

  @override
  String get staffMode => 'ဝန်ထမ်း mode';

  @override
  String get staffRoleOwner => 'ပိုင်ရှင်';

  @override
  String get staffRoleStaff => 'ဝန်ထမ်း';

  @override
  String staffCurrentRole(String role) {
    return 'လက်ရှိ: $role';
  }

  @override
  String staffSwitchTo(String role) {
    return '$role သို့ ပြောင်း';
  }

  @override
  String get staffUnlockOwner => 'ပိုင်ရှင် ဖွင့်';

  @override
  String get staffSetPin => 'ပိုင်ရှင် PIN သတ်မှတ်';

  @override
  String get staffChangePin => 'ပိုင်ရှင် PIN ပြောင်း';

  @override
  String get staffEnterPin => 'ပိုင်ရှင် PIN ရိုက်ထည့်';

  @override
  String get staffConfirmPin => 'ပိုင်ရှင် PIN ထပ်ရိုက်ပါ';

  @override
  String get staffPinMismatch => 'PIN နှစ်ခု မတူပါ။';

  @override
  String get staffWrongPin => 'PIN မှားနေပါသည်';

  @override
  String staffPinTryAgainIn(int seconds) {
    return 'ကြိမ်နှုန်းများနေပါသည်။ $seconds စက္ကန့်အကြာ ပြန်စမ်းပါ';
  }

  @override
  String get staffPinHint => 'ဂဏန်း ၄–၆ လုံး';

  @override
  String get staffOwnerPinRequired =>
      'ဝန်ထမ်းက ပိုင်ရှင်သို့ မပြောင်းခင် ပိုင်ရှင်က Settings မှာ PIN ဦးစွာ သတ်မှတ်ရပါမည်။';

  @override
  String get staffPinSaved => 'PIN သိမ်းပြီး';

  @override
  String get staffOwnerOnly => 'ပိုင်ရှင်သာ ကြည့်နိုင်';

  @override
  String get staffOwnerOnlyDesc =>
      'ဒါကို ကြည့်ရန် Owner mode (Settings) သို့ ပြောင်းပါ။';

  @override
  String get staffBadge => 'ဝန်ထမ်း mode';

  @override
  String get staffManageMembers => 'ဝန်ထမ်းများ စီမံရန်';

  @override
  String get staffMembersTitle => 'ဝန်ထမ်းများ';

  @override
  String get staffMembersEmpty =>
      'ဝန်ထမ်း မထည့်ရသေးပါ။ ရောင်းချမှုတိုင်းကို ဘယ်ဝန်ထမ်းလုပ်လဲ သိရအောင် ထည့်ပါ။';

  @override
  String get staffAddMember => 'ဝန်ထမ်းထည့်ရန်';

  @override
  String get staffEditMember => 'ဝန်ထမ်းပြင်ရန်';

  @override
  String get staffMemberName => 'အမည်';

  @override
  String get staffMemberPin => 'PIN (ဂဏန်း ၄–၆ လုံး)';

  @override
  String get staffMemberPinKeepHint =>
      'လက်ရှိ PIN ကို ဆက်ထားချင်ရင် ကွက်လပ်ထားပါ';

  @override
  String get staffMemberEmail => 'Email (ရွေးချယ်ခွင့်)';

  @override
  String get staffMemberEmailHint =>
      'ဒီလူမှာ Staff account (Email login) ပါရှိရင်၊ ခွင့်ပြုထားတဲ့ permission တွေက အဲဒီ account မှာလည်း အလုပ်လုပ်ပါမယ်';

  @override
  String get staffMemberSaved => 'ဝန်ထမ်းအချက်အလက် သိမ်းပြီး';

  @override
  String get staffPermissionsTooltip => 'ခွင့်ပြုချက်များ';

  @override
  String staffPermissionsTitle(String name) {
    return '$name ရဲ့ ခွင့်ပြုချက်များ';
  }

  @override
  String staffPermissionsIntro(String name) {
    return 'Sell နဲ့ Orders အပြင် $name အသုံးပြုနိုင်မယ့် feature တွေကို ဖွင့်ပေးပါ။ ပုံမှန်အားဖြင့် ပိတ်ထားသည်။';
  }

  @override
  String get staffCapabilityInventoryEdit => 'စာရင်းကုန် ပြင်ဆင်ခွင့်';

  @override
  String get staffCapabilitySettingsSensitive =>
      'အထူးဆက်တင်များ (stock tracking, backup)';

  @override
  String get staffRemoveMember => 'ဖယ်ရှားရန်';

  @override
  String get staffRemoveConfirmTitle => 'ဒီဝန်ထမ်းကို ဖယ်ရှားမှာလား?';

  @override
  String staffRemoveConfirmBody(String name) {
    return '$name ကို Staff mode ပြောင်းတဲ့အခါ နောက်ထပ် မမြင်ရတော့ပါ။ ယခင်ရောင်းချမှုတွေမှာတော့ နာမည် ဆက်ပြနေပါမည်။';
  }

  @override
  String get staffMemberRemoved => 'ဝန်ထမ်း ဖယ်ရှားပြီး';

  @override
  String get staffWhoAreYou => 'ဒီ device ကို ဘယ်သူသုံးနေလဲ?';

  @override
  String get staffNoNamedStaff => 'အမည်မထည့်ဘဲ — Staff mode ပဲသုံးမည်';

  @override
  String get storefrontTitle => 'ကျွန်ုပ်၏ Web ဆိုင်';

  @override
  String get storefrontDesc =>
      'ဖောက်သည်များ app မလိုဘဲ order တင်နိုင်တဲ့ public catalog ထုတ်ဝေပါ။';

  @override
  String get storefrontPublish => 'ဆိုင် ထုတ်ဝေမည်';

  @override
  String get storefrontDisplayName => 'ဆိုင်နာမည်';

  @override
  String get storefrontYourLink => 'သင့်ဆိုင် link';

  @override
  String get storefrontViewAction => 'ဆိုင်ကို ကြည့်ရန်';

  @override
  String get storefrontEnabled => 'ဆိုင် ဖွင့်ထားသည်';

  @override
  String get storefrontCopied => 'Link ကူးယူပြီး';

  @override
  String get storefrontNeedsName => 'ဆိုင်နာမည် ထည့်ပါ';

  @override
  String get storefrontOrderNeedsName => 'Order တင်ဖို့ သင့်အမည်ကို ထည့်ပါ။';

  @override
  String get storefrontSessionStale =>
      'Session ကို refresh လုပ်ဖို့ လိုပါတယ်။ App ကို ပိတ်ပြီး ပြန်ဖွင့်ကာ ထပ်စမ်းကြည့်ပါ။';

  @override
  String get storefrontPhoneShown => 'ဖုန်း (ဖောက်သည်များ မြင်ရမည်)';

  @override
  String get storefrontAddressShown => 'လိပ်စာ (ဖောက်သည်များ မြင်ရမည်)';

  @override
  String get storefrontLogoLabel => 'ဆိုင် Logo';

  @override
  String get storefrontEditInShopProfile => 'ဆိုင်အချက်အလက်မှာ ပြင်ရန်';

  @override
  String get storefrontFromShopProfileHint =>
      'အမည်၊ ဖုန်း၊ လိပ်စာ၊ Logo နဲ့ Payment accounts တွေက ပြေစာနဲ့ တူတူသုံးထားတာပါ — Settings → ဆိုင်အချက်အလက် ထဲမှာ တစ်နေရာတည်း ပြင်ပါ။';

  @override
  String get storefrontProfileSaved => 'သိမ်းပြီးပါပြီ';

  @override
  String get storefrontShare =>
      'ဒီ link ကို Facebook, Viber စသည်တွင် ဖောက်သည်များထံ မျှဝေပါ။';

  @override
  String get storefrontShareAction => 'Link မျှဝေမည်';

  @override
  String storefrontShareText(String name, String url) {
    return '$name\nဒီနေရာမှာ မှာယူပါ: $url';
  }

  @override
  String get storefrontClosed =>
      'ဒီဆိုင်သည် အွန်လိုင်း မှာယူမှု လက်မခံသေးပါ။ ဖွင့်ချိန်အတွင်း ထပ်ကြိုးစားပါ။';

  @override
  String get storefrontProofRequired => 'မှာယူမီ လွှဲငွေ screenshot တွဲပေးပါ။';

  @override
  String get storefrontPricesChanged =>
      'ဈေးနှုန်း အချို့ ပြောင်းလဲသွားပါတယ် — ခြင်းတောင်းကို ပြန်စစ်ပြီး ထပ်မှာပေးပါ။';

  @override
  String get storefrontAttachProofRequired => 'ငွေလွှဲ screenshot တွဲပါ *';

  @override
  String get storefrontHoursTitle => 'ဖွင့်ချိန် (ရန်ကုန် အချိန်)';

  @override
  String get storefrontHoursEnabled => 'ဖွင့်ချိန်အတွင်းသာ မှာယူမှု လက်ခံမည်';

  @override
  String get storefrontHoursOpen => 'ဖွင့်ချိန်';

  @override
  String get storefrontHoursClose => 'ပိတ်ချိန်';

  @override
  String get storefrontRequireProof => 'လွှဲငွေ screenshot မဖြစ်မနေ လိုအပ်';

  @override
  String get storefrontRequireProofHint =>
      'ဖွင့်ထားရင် ဘဏ်လွှဲ checkout မှာ ငွေလွှဲ အထောက်အထား တင်ရမည်။';

  @override
  String get storefrontOrderNotifTitle => 'Web မှာယူမှု အသစ်';

  @override
  String storefrontOrderNotifBody(int count) {
    return 'Storefront မှာယူမှု အသစ် $count ခု — Orders ကို ဖွင့်ကြည့်ပါ။';
  }

  @override
  String get storefrontBlockedCustomers => 'ပိတ်ပင်ထားသော IP များ';

  @override
  String get storefrontNoBlockedCustomers => 'IP တစ်ခုမှ ပိတ်ပင်မထားပါ။';

  @override
  String get storefrontBlockedHow =>
      'Network တစ်ခုက web order အသစ် မတင်နိုင်အောင် ပိတ်နိုင်ပါတယ်။ ဒီမှာ IP ထည့်ပါ၊ သို့မဟုတ် IP ပြသော web order ပေါ်က Block ကို နှိပ်ပါ။';

  @override
  String get storefrontUnblock => 'ပိတ်ပင်ချက် ဖြေလိုက်ပါ';

  @override
  String get storefrontAddBlocked => 'IP လိပ်စာ ပိတ်ပင်မည်';

  @override
  String get storefrontIpAddress => 'IP လိပ်စာ';

  @override
  String get storefrontIpInvalid => 'မှန်ကန်သော IP လိပ်စာ ထည့်ပါ။';

  @override
  String get storefrontBlockReasonOptional => 'အကြောင်းရင်း (ရွေးချယ်ခွင့်)';

  @override
  String get storefrontPaymentInfoTitle => 'ငွေပေးချေမှု အကောင့်များ';

  @override
  String get storefrontPaymentInfoHint =>
      'ဖောက်သည်က checkout မှာ ဘယ်သူ့ဆီ လွှဲရမလဲ သိရအောင် ပြပေးပါမည်။';

  @override
  String get paymentMethodLabel => 'ငွေပေးချေမှုနည်းလမ်း (ဥပမာ KBZPay, PayPal)';

  @override
  String get paymentMethodAccountName => 'အကောင့်နာမည်';

  @override
  String get paymentMethodAccountNumber => 'အကောင့်နံပါတ်';

  @override
  String get paymentMethodAdd => 'ငွေပေးချေမှုနည်းလမ်း ထပ်ထည့်ရန်';

  @override
  String get paymentMethodRemove => 'ငွေပေးချေမှုနည်းလမ်း ဖျက်ရန်';

  @override
  String get storefrontNumberCopied => 'နံပါတ် ကူးယူပြီး';

  @override
  String get storefrontRateLimited =>
      'မကြာသေးမီက order များစွာ တင်ထားပါတယ် — မိနစ်အနည်းငယ် စောင့်ပြီး ထပ်ကြိုးစားပါ။';

  @override
  String get storefrontBlocked =>
      'ဒီဆိုင်က ဒီ network ကနေ order လက်မခံနိုင်တော့ပါ။ ဆိုင်ကို တိုက်ရိုက် ဆက်သွယ်ပါ။';

  @override
  String get storefrontContactShopTitle => 'ဆိုင်ကို ဆက်သွယ်ရန်';

  @override
  String get storefrontCallShop => 'ဖုန်းခေါ်ရန်';

  @override
  String get storefrontChatViber => 'Viber ဖြင့် ဆက်သွယ်ရန်';

  @override
  String get storefrontOutOfStock =>
      'စိတ်မကောင်းပါဘူး၊ Cart ထဲက ပစ္စည်းတစ်ခု Online မှာ ကုန်သွားပါပြီ။ Cart ကို ပြင်ပြီး ထပ်ကြိုးစားပါ။';

  @override
  String get storefrontInvalidProduct =>
      'Cart ထဲက ပစ္စည်းတစ်ခုသည် ရရှိနိုင်တော့ပါ။ ၎င်းကို ဖယ်ရှားပြီး ထပ်ကြိုးစားပါ။';

  @override
  String storefrontOnlineLeft(int count) {
    return 'Online ကျန် $count ခု';
  }

  @override
  String get storefrontSoldOut => 'Online မှာ ကုန်သွားပါပြီ';

  @override
  String storefrontCheckoutBar(int count, String total) {
    return 'ငွေရှင်း · $count item(s) · $total';
  }

  @override
  String get storefrontNoSearchResults =>
      'ရှာဖွေမှုနှင့် ကိုက်ညီသော ပစ္စည်းမရှိပါ။';

  @override
  String get storefrontCatalogEmpty => 'ဒီဆိုင်တွင် ပစ္စည်းများ မထည့်ရသေးပါ။';

  @override
  String poLineCatalogCostDiffers(String amount) {
    return 'Catalog ဈေးနှုန်း: $amount';
  }

  @override
  String get storefrontYourCart => 'သင့်ဈေးဝယ်တောင်း';

  @override
  String get storefrontCartEmptyTitle => 'သင့်ဈေးဝယ်တောင်း ဗလာဖြစ်နေပါသည်';

  @override
  String get storefrontCartEmptyBody =>
      'ဆိုင်ကို လှည့်ကြည့်ပြီး ပစ္စည်းများ ထည့်ပါ။';

  @override
  String get storefrontContinueShopping => 'ဆက်လက်ဝယ်ယူရန်';

  @override
  String get storefrontProceedToCheckout => 'ရှေ့ဆက်မည်';

  @override
  String get storefrontShopFallbackName => 'ဆိုင်';

  @override
  String get storefrontPhoneCopied => 'ဖုန်းနံပါတ် ကူးယူပြီး';

  @override
  String get storefrontAdd => 'ထည့်မည်';

  @override
  String get storefrontYourDetails => 'သင့်အချက်အလက်';

  @override
  String get storefrontNameRequired => 'အမည် *';

  @override
  String get storefrontPayment => 'ငွေပေးချေမှု';

  @override
  String get storefrontBankTransfer => 'ဝေလက် လွှဲပြောင်း';

  @override
  String get storefrontCashOnDelivery => 'ပစ္စည်းရောက်မှ ငွေချေမည်';

  @override
  String get storefrontPayTo => 'ငွေလွှဲရန်:';

  @override
  String get storefrontAttachProof => 'ငွေလွှဲ screenshot ပူးတွဲပါ';

  @override
  String storefrontProofAttached(String name) {
    return 'Screenshot: $name';
  }

  @override
  String get storefrontCodNoticeBeforeOrder =>
      'အော်ဒါ ရောက်ရှိချိန်မှာ courier ကို ငွေသားပေးချေရပါမည်။';

  @override
  String storefrontTotal(String amount) {
    return 'စုစုပေါင်း: $amount';
  }

  @override
  String get storefrontPlaceOrder => 'အော်ဒါတင်မည်';

  @override
  String get storefrontOrderPlaced => 'အော်ဒါတင်ပြီးပါပြီ!';

  @override
  String storefrontOrderNo(String orderNo) {
    return 'အော်ဒါနံပါတ်: $orderNo';
  }

  @override
  String get storefrontTransferInstructions =>
      'ငွေလွှဲပြီး screenshot ကို ဆိုင်ဆီ ပို့ပါ:';

  @override
  String get storefrontCodNoticeAfterOrder =>
      'ပစ္စည်းရောက်ရှိချိန် courier ကို ငွေသားပေးချေရပါမည်။';

  @override
  String get storefrontSaveToPhotos => 'Photos ထဲ သိမ်းမည်';

  @override
  String get storefrontDone => 'ပြီးပါပြီ';

  @override
  String get storefrontCopyNumber => 'နံပါတ် ကူးယူရန်';

  @override
  String storefrontNotFound(String slug) {
    return '\"$slug\" ဆိုင်ကို ရှာမတွေ့ပါ သို့မဟုတ် မထုတ်ပြန်ရသေးပါ။';
  }

  @override
  String get storefrontOpenShopLink =>
      'ဆိုင်လင့်ခ်ကို ဖွင့်ပါ၊ ဥပမာ - /your-shop-slug';

  @override
  String get storefrontRenewTitle => 'စာရင်းသွင်းမှု သက်တမ်းတိုးရန်';

  @override
  String get storefrontRenewHint =>
      'အောက်တွင် ငွေပေးချေမှု အချက်အလက်များ ဖြည့်သွင်းပါ — စစ်ဆေးပြီး သင့်စာရင်းသွင်းမှု သက်တမ်းကို တိုးပေးပါမည်။';

  @override
  String get storefrontRenewShopName => 'ဆိုင်အမည် *';

  @override
  String get storefrontRenewDeviceIdHint =>
      'ဖုန်းထဲမှာ ရှာပါ - Settings → License → App Reference ID။ Account နဲ့ sign in ဝင်ထားရင် ဒါကို ကျော်ပြီး အောက်က email ကို ဖြည့်ပါ။';

  @override
  String get storefrontRenewEmail => 'အီးမေးလ် (account ရှိရင်)';

  @override
  String get storefrontRenewEmailHint =>
      'ဒါရှိရင် အပေါ်က App Reference ID မလိုပါဘူး — တစ်ခုပဲ ဖြည့်ရင် ရပါတယ်။';

  @override
  String get storefrontRenewSignInPrompt =>
      'Account ရှိပြီးသားလား။ အချက်အလက် ထပ်မရိုက်ရအောင်နဲ့ ယခင် တောင်းဆိုမှုများ ကြည့်ရအောင် Sign in ဝင်ပါ။';

  @override
  String get storefrontRenewSignInFailed =>
      'Sign in ဝင်လို့မရပါ။ Email နဲ့ Password ကို ပြန်စစ်ပါ။';

  @override
  String storefrontRenewSignedInAs(String email) {
    return '$email အနေနဲ့ Sign in ဝင်ထားပါတယ်';
  }

  @override
  String get storefrontRenewHistoryTitle => 'ယခင် တောင်းဆိုမှုများ';

  @override
  String get storefrontRenewHistoryEmpty => 'တောင်းဆိုမှု မရှိသေးပါ။';

  @override
  String get storefrontRenewPlan => 'အစီအစဉ်';

  @override
  String storefrontRenewPricePerMonth(String price) {
    return '$price / လ';
  }

  @override
  String storefrontRenewPricePerYear(String price) {
    return '$price / နှစ်';
  }

  @override
  String get storefrontRenewMonths => 'လအရေအတွက်';

  @override
  String get storefrontRenewAmountLockedHint =>
      'ဒါက သင့် plan အတွက် သတ်မှတ်ထားတဲ့ ပမာဏ ဖြစ်ပါတယ် — ဒီပမာဏအတိုင်း လွှဲပေးပါ။';

  @override
  String get storefrontRenewAmountPaid => 'ပေးချေရမည့် ငွေပမာဏ (ကျပ်) *';

  @override
  String get storefrontRenewRefNo =>
      'လွှဲပြောင်းမှု ကိုးကားနံပါတ်၏ နောက်ဆုံး ၆ လုံး *';

  @override
  String get storefrontRenewRefNoHint =>
      'KBZPay/WavePay confirmation ထဲက transaction ID ရဲ့ အဆုံးမှာ ရှာပါ။';

  @override
  String get storefrontRenewSubmit => 'တောင်းဆိုမှု ပို့ပါ';

  @override
  String get storefrontRenewSubmitted =>
      'တောင်းဆိုမှု ပို့ပြီးပါပြီ! သင့်ငွေပေးချေမှုကို စစ်ဆေးပြီး မကြာမီ သက်တမ်းတိုးပေးပါမည်။';

  @override
  String storefrontRenewRequestId(String requestId) {
    return 'ကိုးကားနံပါတ်: $requestId';
  }

  @override
  String get storefrontRenewFailed =>
      'တစ်ခုခု မှားယွင်းသွားပါသည်။ ထပ်မံကြိုးစားပါ ဒါမှမဟုတ် support ကို ဆက်သွယ်ပါ။';

  @override
  String get storefrontRenewRateLimited =>
      'တောင်းဆိုမှု အကြိမ်များစွာ ပို့ထားပါသည် — မိနစ်အနည်းငယ် စောင့်ပြီး ထပ်ကြိုးစားပါ။';

  @override
  String get storefrontRenewMissingFields =>
      'ဆိုင်အမည်၊ App Reference ID (သို့) email၊ လအရေအတွက်၊ ငွေပမာဏနှင့် transaction number ရဲ့ နောက်ဆုံး ၆ လုံးတို့ကို ဖြည့်သွင်းပါ။';

  @override
  String get storefrontRenewMonthsTooHigh =>
      'လအရေအတွက်သည် ၆၀ လ (၅ နှစ်) ထက် ပိုမနိုင်ပါ။ ကျေးဇူးပြု၍ ပိုနည်းသောနံပါတ်တစ်ခု ထည့်ပါ။';

  @override
  String get onboardWelcomeTitle => 'All In One POS မှ ကြိုဆိုပါတယ်';

  @override
  String get onboardWelcomeBody =>
      'မြန်မာဆိုင်များအတွက် offline-first POS app ပါ။ ဆိုင်ကို စတင်သတ်မှတ်ကြရအောင် — မိနစ်ပိုင်းပဲ ကြာပါမယ်။';

  @override
  String get onboardNext => 'ရှေ့ဆက်';

  @override
  String get onboardBack => 'နောက်ပြန်';

  @override
  String get onboardSkip => 'ကျော်';

  @override
  String get onboardGetStarted => 'စတင်မည်';

  @override
  String get onboardShopTitle => 'သင့်ဆိုင်';

  @override
  String get onboardShopBody => 'ဒါက ပြေစာပေါ်မှာ ပါဝင်ပါမယ်။';

  @override
  String get onboardLicenseTitle => 'Free Plan နဲ့ စသုံးပါမယ်';

  @override
  String get onboardLicenseBody =>
      'ရောင်းချ + ကုန်ပစ္စည်းကို Card မလို၊ sign up မလို၊ Key မလိုဘဲ အမြဲသုံးနိုင်ပါတယ်။ Agent ဆီက license key ရှိရင် နောက်မှ Settings မှာ ထည့်နိုင်ပါတယ်။ ဆိုင် email ရှိပြီးသားဆိုရင် နောက်စာမျက်နှာမှာ Sign in နှိပ်ပါ။';

  @override
  String get onboardActivateNow => 'License key ချက်ချင်း activate';

  @override
  String get onboardAccountTitle => 'Email အကောင့် (မလုပ်လည်းရ)';

  @override
  String get onboardAccountBody =>
      'ဒီဆိုင်ကို ဖုန်းတခြားမှာပါ သုံးမယ်၊ ဒါမှမဟုတ် ဝန်ထမ်း login ထည့်မယ်ဆိုမှသာ လိုအပ်ပါတယ်။';

  @override
  String get onboardAccountBenefits =>
      'Email နဲ့ သုံးရင်:\n• ဖုန်းတခြားမှာ ဒီဆိုင် ဖွင့်နိုင်\n• အင်တာနက်ရှိရင် cloud backup ရှိ\n• ဝန်ထမ်းကို သူ့ email နဲ့ ဝင်ခိုင်းနိုင်';

  @override
  String get onboardAccountWhyEmail => 'Email ဘာကြောင့် ထည့်ရမလဲ?';

  @override
  String get onboardAccountSkip => 'အခုအတွက် ကျော်မည်';

  @override
  String get onboardAccountSignedInTitle => 'Sign in ဝင်ပြီးပါပြီ';

  @override
  String get onboardStaffTitle => 'Owner နှင့် Staff Mode';

  @override
  String get onboardStaffBody =>
      'အခု Owner mode မှာ ရှိပါတယ် — အားလုံး ရနိုင်ပါတယ်။\nဖုန်းကို ဝန်ထမ်းကို လက်ဆင့်ကမ်းမလား? Settings → ပိုင်ရှင် Tools → Staff သို့ ပြောင်းပါ။\nStaff mode မှာ Sell + Orders ပဲ မြင်ရမယ်၊ Owner ပြန်ဖို့ PIN လိုပါမယ်။\nဒီ PIN အတူတူပဲ ဒီနေ့ဆိုင် ဘယ်သူဖွင့်လဲ ဆိုတာကို အတည်ပြုဖို့လည်း သုံးပါတယ်။';

  @override
  String get accountShopLoginTitle => 'အကောင့်';

  @override
  String get accountShopLoginHint =>
      'ချန်လှပ်ထားနိုင်ပါတယ်— အခြားစက်တစ်လုံးက ဆိုင်ကို ဝင်ရောက်ဖို့ Email + Password နဲ့ Login ဖန်တီးနိုင်ပါတယ်။ Licenseကီးနဲ့ PIN quick-switch အတိုင်း ဆက်အလုပ်လုပ်ပါလိမ့်မယ်။';

  @override
  String get accountProfileSubtitleSignedOut =>
      'ဝင်ရောက်မည် သို့မဟုတ် ဆိုင် login ဖန်တီးမည်';

  @override
  String get accountCreatedSignedIn =>
      'အကောင့် ဖန်တီးပြီးပါပြီ။ ဝင်ရောက်ပြီးသား ဖြစ်ပါတယ်။';

  @override
  String get accountReadyNoEmailWait =>
      'အတည်ပြုအီးမေးလ် စောင့်ရန် မလိုပါ — ဒီအီးမေးလ်နှင့် စကားဝှက်ကို မည်သည့်စက်တွင်မဆို ချက်ချင်း သုံးနိုင်ပါတယ်။';

  @override
  String get accountEmail => 'အီးမေးလ်';

  @override
  String get accountPassword => 'စကားဝှက်';

  @override
  String get accountPasswordRememberedHint =>
      'ဒီဖုန်းပေါ်မှာ ဝင်ပြီးရင် email နဲ့ စကားဝှက်ကို မှတ်ထားပါတယ်။';

  @override
  String get accountConfirmPassword => 'စကားဝှက် အတည်ပြုပါ';

  @override
  String get accountShowPassword => 'စကားဝှက် ပြရန်';

  @override
  String get accountHidePassword => 'စကားဝှက် ဖျောက်ရန်';

  @override
  String get accountPasswordMismatch => 'စကားဝှက်များ မတူညီပါ';

  @override
  String get passwordStrengthWeak => 'အားနည်း';

  @override
  String get passwordStrengthFair => 'အလယ်အလတ်';

  @override
  String get passwordStrengthGood => 'ကောင်း';

  @override
  String get passwordStrengthStrong => 'ကြံ့ခိုင်';

  @override
  String get accountForgotPassword => 'စကားဝှက် မေ့နေပါသလား?';

  @override
  String get accountResetPasswordTitle => 'စကားဝှက် ပြန်လည်သတ်မှတ်ရန်';

  @override
  String get accountResetPasswordHint =>
      'ဆိုင်အကောင့်ရဲ့ email ကို ထည့်ပါ — စကားဝှက် ပြန်လည်သတ်မှတ်ဖို့ link ကို ပို့ပေးပါမယ်။';

  @override
  String get accountResetPasswordSend => 'Reset link ပို့မည်';

  @override
  String get accountResetPasswordSent => 'Reset link ကို email မှာ စစ်ကြည့်ပါ။';

  @override
  String get accountResetPasswordNewLabel => 'စကားဝှက်အသစ်';

  @override
  String get accountResetPasswordSave => 'စကားဝှက်အသစ် သိမ်းမည်';

  @override
  String get accountResetPasswordSuccess =>
      'စကားဝှက် ပြောင်းပြီးပါပြီ — ဝင်ရောက်ထားပါပြီ။';

  @override
  String get accountCreateShopLogin => 'ဆိုင် Login ဖန်တီးမည်';

  @override
  String get accountSignIn => 'ဝင်ရောက်မည်';

  @override
  String get accountSignOut => 'ထွက်မည်';

  @override
  String get accountDeleteAccount => 'အကောင့် ဖျက်မည်';

  @override
  String get accountDeleteConfirmTitle => 'အကောင့် ဖျက်မလား?';

  @override
  String get accountDeleteConfirmBody =>
      'Online ဆိုင်အကောင့်၊ ဤဆိုင်၏ staff login များ၊ ပိုင်ဆိုင်သော shop များ၏ cloud ဒေတာကို အပြီးဖျက်မည်။ ဤဖုန်းသည် Free plan သို့ ပြန်သွားမည်။ ပြန်မရနိုင်ပါ။';

  @override
  String get accountDeletePasswordLabel => 'စကားဝှက်ဖြင့် အတည်ပြုပါ';

  @override
  String get accountDeleteSuccess =>
      'အကောင့် ဖျက်ပြီးပါပြီ — Free plan သို့ ပြောင်းထားသည်။';

  @override
  String get accountDeleteFailed =>
      'အကောင့် မဖျက်နိုင်ပါ။ စကားဝှက်နှင့် အင်တာနက် စစ်ပါ။';

  @override
  String get accountDeleteWrongPassword => 'စကားဝှက် မှားနေသည်။';

  @override
  String get accountDeleteOwnerOnly => 'ဆိုင်ပိုင်ရှင်သာ အကောင့် ဖျက်နိုင်သည်။';

  @override
  String get accountSignedIn => 'ဝင်ရောက်ပြီးပါပြီ။';

  @override
  String get accountSignedOut => 'ထွက်ပြီးပါပြီ။';

  @override
  String get accountSignOutConfirmTitle => 'ထွက်မှာ သေချာပါသလား?';

  @override
  String get accountSignOutConfirmBody =>
      'ပြန်ဝင်ဖို့ email နဲ့ password ထပ်လိုအပ်ပါလိမ့်မယ်။ Device-key activation နဲ့ local PIN quick-switch ကို ဒါက မထိခိုက်ပါ။';

  @override
  String get accountSignOutConfirmBodyStaff =>
      'ပြန်ဝင်ဖို့ email နဲ့ password ထပ်လိုအပ်ပါလိမ့်မယ်။';

  @override
  String get accountSignInWipeConfirmTitle =>
      'ဒီ account က ဆိုင်တခြားတစ်ခုနှင့် သက်ဆိုင်ပါတယ်';

  @override
  String get accountSignInWipeConfirmBody =>
      'ဒီစက်ပေါ်မှာ တခြားဆိုင်ရဲ့ data ရှိနေပါတယ်။ ဆက်လုပ်ရင် ဒီစက်ပေါ်က local data အားလုံးကို ဒီ account ရဲ့ ဆိုင်data နဲ့ အစားထိုးပစ်ပါလိမ့်မယ်။ အရင် sync အပြည့်ဖြစ်အောင် သေချာစေပါ — ဒါကို ပြန်ပြင်လို့မရပါ။';

  @override
  String get accountLoginCreated => 'Login ဖန်တီးပြီးပါပြီ။';

  @override
  String get accountEmailTaken => 'ဒီအီးမေးလ်ကို အသုံးပြုပြီးသားဖြစ်ပါတယ်။';

  @override
  String get accountTrialAlreadyUsed =>
      'ဒီစက် (သို့) အကောင့်က အခမဲ့စမ်းသုံးခွင့် သုံးပြီးသားဖြစ်ပါတယ်။ ဆက်လက်သုံးရန် support ကို ဆက်သွယ်ပါ။';

  @override
  String get accountNotActivated => 'ဒီစက်ကို အရင် Activate လုပ်ပါ။';

  @override
  String get accountNoBackend => 'အင်တာနက် ချိတ်ဆက်မှု မရှိပါ။';

  @override
  String get accountPendingSync =>
      'ဒီစက်မှာ sync မလုပ်ရသေးတဲ့ ပြောင်းလဲမှုတွေ ရှိပါတယ်။ Sync ပြီးအောင်စောင့်ပြီး ထပ်ကြိုးစားပါ။';

  @override
  String get accountActionFailed =>
      'တစ်ခုခု မှားယွင်းသွားပါတယ်။ ထပ်ကြိုးစားကြည့်ပါ။';

  @override
  String get accountInvalidCredentials =>
      'Email သို့မဟုတ် password မှားနေပါတယ်။';

  @override
  String get accountSignInSessionFailed =>
      'Sign in ဝင်ပြီးပါပြီ။ ဒီဖုန်းက ဆိုင်ကို ဆွဲမရသေးပါ။ Sign in ကို ထပ်နှိပ်ပါ။';

  @override
  String get accountSignInNoShop =>
      'ဒီ email ကို ဆိုင်နှင့် မချိတ်ရသေးပါ။ ပေးပြီးသားဆိုရင် Support ကို ပြောပါ — ပြီးရင် Check for renewal ကို နှိပ်ပါ။';

  @override
  String get accountSignInDeviceLimit =>
      'ဒီဆိုင်က ပင်မဖုန်းအပြင် ဖုန်း/ကွန်ပျူတာ နောက်ထပ် ၂ လုံး ချိတ်ပြီးပါပြီ။ Device အဟောင်း ဖြုတ်ပေးဖို့ Support ကို ပြောပါ။';

  @override
  String get staffAccountsTitle => 'ဝန်ထမ်း Account (Email login)';

  @override
  String get staffAccountsSubtitle =>
      'အွန်လိုင်း: ဝန်ထမ်းတစ်ဦးချင်းစီက မိမိ email + password နဲ့ login ဝင်သည်။';

  @override
  String get staffModeSubtitle =>
      'ဒီဖုန်းအတွက်သာ: Owner PIN နဲ့ device ကို သော့ခတ်သည် (offline မှာလည်း အလုပ်လုပ်သည်)။';

  @override
  String get staffPinEmailOwnerHint =>
      'ပိုင်ရှင် PIN ကို ဒီမှာ သတ်မှတ်/ပြောင်းပါ။ ကုန်သည်ကို ဖုန်းလွှဲပေးရင် Staff ပြောင်းပါ — email login ဝင်ထားဖို့ မလိုပါ။ အဲ့ PIN က Owner ပြန်ဖွင့်ဖို့နဲ့ နေ့စဉ်ဆိုင်ဖွင့်သူ အတည်ပြုဖို့ သုံးပါတယ်။';

  @override
  String get staffAccountsInvite => 'ဝန်ထမ်း ဖိတ်ခေါ်မည်';

  @override
  String get staffAccountsEmpty =>
      'ဝန်ထမ်း Account မရှိသေးပါ။ Email + Password နဲ့ ဖိတ်ခေါ်ပြီး သူတို့ကိုယ်ပိုင်စက်နဲ့ ဝင်ရောက်နိုင်အောင် လုပ်ပေးပါ။';

  @override
  String get staffAccountsActive => 'အသုံးပြုနေဆဲ';

  @override
  String get staffAccountsRevoked => 'ပယ်ဖျက်ပြီး';

  @override
  String get staffAccountsRevoke => 'ပယ်ဖျက်မည်';

  @override
  String get staffAccountsRevokeConfirmTitle => 'ဒီ Account ကို ပယ်ဖျက်မလား?';

  @override
  String staffAccountsRevokeConfirmBody(String email) {
    return '$email ဟာ နောက်ထပ် ဝင်ရောက်လို့ မရတော့ပါ။';
  }

  @override
  String get branchesTitle => 'ဆိုင်ခွဲများ';

  @override
  String get branchesCreate => 'ဆိုင်ခွဲ အသစ် ဖန်တီးမည်';

  @override
  String get branchesCreated => 'ဆိုင်ခွဲ ဖန်တီးပြီးပါပြီ။';

  @override
  String get branchesEmpty => 'ဆိုင်ခွဲ မရှိသေးပါ။';

  @override
  String get branchesSectionCurrent => 'လက်ရှိ ဆိုင်ခွဲ';

  @override
  String get branchesSectionOther => 'အခြား ဆိုင်ခွဲများ';

  @override
  String get branchesNoOther => 'အခြား ဆိုင်ခွဲ မရှိသေးပါ။';

  @override
  String get branchesPinnedCurrentTitle => 'လက်ရှိဆိုင်ခွဲ (Pinned)';

  @override
  String get branchesPinnedCurrentHint =>
      'ဒီစက်က လက်ရှိ ဒီဆိုင်ခွဲနဲ့ ချိတ်ထားပါတယ်။';

  @override
  String get branchesHealthSafeSwitch => 'ပြောင်းရန် အဆင်ပြေ';

  @override
  String get branchesHealthSyncNeeded => 'Sync လိုအပ်';

  @override
  String branchesRowPending(int count) {
    return 'ဒီစက် — တင်မရသေးသော uploads: $count';
  }

  @override
  String branchesRowLastSync(String time) {
    return 'နောက်ဆုံး sync: $time';
  }

  @override
  String get branchesCurrent => 'လက်ရှိ';

  @override
  String get branchesSwitch => 'ပြောင်းမည်';

  @override
  String get branchesSwitched => 'ဆိုင်ခွဲ ပြောင်းပြီးပါပြီ။';

  @override
  String get branchesSwitchSyncing =>
      'ဒီဆိုင်ရဲ့ ဒေတာကို sync လုပ်နေပါသည် — connection နှေးရင် အချိန် အနည်းငယ် ကြာနိုင်ပါသည်။';

  @override
  String get branchesSwitchConfirmTitle => 'ဒီဆိုင်ခွဲကို ပြောင်းမလား?';

  @override
  String branchesSwitchConfirmBody(String label) {
    return 'ဒီစက်ပေါ်က Data အားလုံးကို \"$label\" ရဲ့ Data နဲ့ အစားထိုးပါလိမ့်မယ်။ Data အားလုံး sync ပြီးသားဖြစ်ကြောင်း သေချာအောင် စစ်ပါ — ပြန်လှည့်လို့ မရပါ။';
  }

  @override
  String get branchesSwitchBlockedTitle => 'အရင် Sync ပြဿနာဖြေရှင်းပါ';

  @override
  String get branchesSwitchBlockedStuckOutbox =>
      'Upload တချို့ ပြန်ကြိုးစားနေဆဲပါ။ Sync now နှိပ်ပြီး ခဏစောင့်ကာ ပြန် switch ပါ။';

  @override
  String get branchesSwitchFixSyncIssues => 'Sync အခြေအနေ ကြည့်မည်';

  @override
  String get branchesPendingSync =>
      'ဒီစက်မှာ sync မလုပ်ရသေးတဲ့ ပြောင်းလဲမှုတွေ ရှိပါတယ်။ Sync ပြီးအောင်စောင့်ပြီး ထပ်ကြိုးစားပါ။';

  @override
  String branchesPreflightTitle(String label) {
    return '\"$label\" သို့ ပြောင်းရန် အဆင်သင့်ဖြစ်ပြီလား?';
  }

  @override
  String get branchesPreflightTarget => 'ပြောင်းမည့် ဆိုင်ခွဲ';

  @override
  String branchesPreflightPending(int count) {
    return 'မ sync ရသေးတဲ့ local ပြောင်းလဲမှု: $count';
  }

  @override
  String branchesPreflightStuck(int count) {
    return 'ပြန်ကြိုးစားနေသော uploads: $count';
  }

  @override
  String branchesPreflightNetwork(String status) {
    return 'Network: $status';
  }

  @override
  String branchesPreflightLastSync(String time) {
    return 'နောက်ဆုံး sync: $time';
  }

  @override
  String get branchesPreflightNeedSync =>
      'local data မပျောက်အောင် အရင် Sync လုပ်ပြီးမှ ပြောင်းပါ။';

  @override
  String branchesSwitchUploadFailed(int count) {
    return 'Local ပြောင်းလဲမှု $count ခု မတင်ရသေးပါ။ Sync now နှိပ်ပြီး ပြန် switch ပါ။ ထိန်းထားသော items က background မှာ အလိုအလျောက် ပြီးပြီး switch မပိတ်ပါ။';
  }

  @override
  String get branchesPreflightNeedOnline =>
      'လက်ရှိ Offline ဖြစ်နေပါတယ်။ branch ပြောင်းရန် internet ချိတ်ပါ။';

  @override
  String get branchesPreflightSyncAndSwitch => 'Sync လုပ်ပြီး ပြောင်းမည်';

  @override
  String get branchesPreflightSyncFirst => 'အရင် Sync လုပ်မည်';

  @override
  String get branchesPreflightSwitchNow => 'ယခု ပြောင်းမည်';

  @override
  String get branchesPreflightDetails => 'အသေးစိတ်';

  @override
  String get branchesPreflightSummaryReady =>
      'Online — Sync လုပ်ပြီး ပြောင်းနိုင်ပါပြီ။';

  @override
  String get branchesStuckBannerTitle => 'Branch မပြောင်းခင် Sync လုပ်ပါ';

  @override
  String get branchesStuckBannerBody =>
      'Sync now နှိပ်ပြီး ပြန်တင်ပါ။ ထိန်းထားသော items က အလိုအလျောက် ပြီးပြီး branch ပြောင်းခြင်းကို မပိတ်ပါ။';

  @override
  String get branchesStuckBannerSyncNow => 'Sync now';

  @override
  String get branchesStuckBannerReview => 'Sync အခြေအနေ ကြည့်မည်';

  @override
  String get branchesQuarantineBannerTitle =>
      'Upload အချို့ background မှာ ပြီးဆုံးနေသည်';

  @override
  String get branchesQuarantineBannerBody =>
      'ဒီစက်မှာ ကျန်ပြီး branch ပြောင်းခြင်းကို မပိတ်ပါ။ Sync က အလိုအလျောက် ပြီးစေပါမယ်။';

  @override
  String get branchesQuarantineBannerOpen => 'Sync အခြေအနေ ကြည့်မည်';

  @override
  String get branchesSwitchInProgressTitle => 'ဆိုင်ခွဲ ပြောင်းနေသည်';

  @override
  String get branchesSwitchStepCheckingDataSafety =>
      'Data လုံခြုံမှု စစ်ဆေးနေသည်';

  @override
  String get branchesSwitchStepSwitchingAccountClaim =>
      'Account claim ပြောင်းနေသည်';

  @override
  String get branchesSwitchStepRefreshingSession =>
      'Session ကို ပြန်လည်ပြင်ဆင်နေသည်';

  @override
  String get branchesSwitchStepClearingOldData => 'ဒီဆိုင်ရဲ့ data ဖွင့်နေသည်';

  @override
  String get branchesSwitchStepSyncingNewData =>
      'ဆိုင်အသစ် data Sync လုပ်နေသည်';

  @override
  String branchesRecoveryBody(String shopId) {
    return '$shopId သို့ branch ပြောင်းခြင်း လုပ်ငန်းစဉ် မပြီးသေးပါ။ Sync ကို ထပ်စမ်းနိုင်ပါတယ်။';
  }

  @override
  String branchesRecoveryBodyWithError(String shopId, String error) {
    return '$shopId သို့ branch ပြောင်းခြင်း မပြီးသေးပါ — $error';
  }

  @override
  String get branchesRecoveryRetrySync => 'Sync ပြန်လုပ်မည်';

  @override
  String get branchesRecoveryDismiss => 'ဖျောက်မည်';

  @override
  String get branchesRecoveryResolved => 'Branch setup ပြီးစီးပါပြီ။';

  @override
  String get branchesRecoveryStillPending =>
      'Branch setup မပြီးသေးပါ။ Banner ကနေ ထပ်ကြိုးစားပါ။';

  @override
  String get branchesVerifyTitle => 'Branch setup ဆက်ပြီးနေသည်';

  @override
  String get branchesVerifyBody =>
      'Branch data တချို့ မပြည့်စုံသေးပါ။ ယခု sync ပြန်လုပ်မလား၊ background မှာ ဆက်ပြီးလုပ်မလား ရွေးနိုင်ပါတယ်။';

  @override
  String get branchesVerifyRetryNow => 'ယခု ပြန်လုပ်မည်';

  @override
  String get branchesVerifyFinishBackground => 'Background မှာ ဆက်လုပ်မည်';

  @override
  String get branchesNetworkOnline => 'Online';

  @override
  String get branchesNetworkOffline => 'Offline';

  @override
  String get branchesNetworkRetry =>
      'Internet မတည်ငြိမ်ပါ။ ခဏနေပြီး ထပ်ကြိုးစားပါ။';

  @override
  String get branchesAuthExpired =>
      'Session သက်တမ်းကုန်သွားပါပြီ။ ပြန်ဝင် (sign in) လုပ်ပါ။';

  @override
  String get branchesInvalidState =>
      'ဒီ branch ကို ဒီ account နဲ့ မချိတ်ထားတော့ပါ (သို့) ခွင့်မပြုတော့ပါ။';

  @override
  String get branchesUnlink => 'ဖြုတ်မည်';

  @override
  String get branchesUnlinkConfirmTitle => 'ဒီဆိုင်ခွဲကို ဖြုတ်မလား?';

  @override
  String branchesUnlinkConfirmBody(String label) {
    return '\"$label\" ကို ဆိုင်ခွဲစာရင်းမှ ဖယ်ရှားပါလိမ့်မယ်။ Key နဲ့ နောက်ပိုင်း ပြန်ချိတ်နိုင်ပါတယ်။';
  }

  @override
  String get recurringExpenseTitle => 'လစဉ် ပုံသေ ကုန်ကျစရိတ်';

  @override
  String get recurringExpenseManage => 'လစဉ် ကုန်ကျစရိတ် စီမံမည်';

  @override
  String get recurringExpenseAddFromTemplate => 'Template မှ ထည့်မည်';

  @override
  String get recurringExpenseEmpty =>
      'လစဉ် ပုံသေ ကုန်ကျစရိတ် မထည့်ရသေးပါ။ ဆိုင်ခန်းငှားခ ဒါမှမဟုတ် ဝန်ထမ်းစရိတ်လို လစဉ်ပေးရတဲ့ စရိတ်တစ်ခု ထည့်ပါ။';

  @override
  String get recurringExpenseAdd => 'လစဉ် ကုန်ကျစရိတ် ထည့်မည်';

  @override
  String get recurringExpenseEdit => 'လစဉ် ကုန်ကျစရိတ် ပြင်မည်';

  @override
  String get recurringExpenseSaved => 'သိမ်းပြီးပါပြီ။';

  @override
  String get recurringExpenseDeleted => 'ဖျက်ပြီးပါပြီ။';

  @override
  String get recurringExpenseDeleteConfirmTitle =>
      'ဒီ လစဉ်ကုန်ကျစရိတ်ကို ဖျက်မလား?';

  @override
  String get recurringExpenseDeleteConfirmBody =>
      'ဒါက template ကိုပဲ ဖျက်ပါမည် — auto-generate ရပ်သွားပါလိမ့်မယ်၊ ဒါပေမယ့် အရင်က generate ဖြစ်ပြီးသား ကုန်ကျစရိတ်တွေကတော့ မထိခိုက်ပါ။';

  @override
  String get recurringExpenseAutoGenerate => 'လစဉ် အလိုအလျောက် ထည့်မည်';

  @override
  String get recurringExpenseAutoGenerateHint =>
      '\"Template မှ ထည့်မည်\" မလိုတော့ဘဲ အလိုအလျောက် ထည့်ပေးပါမယ် — List ထဲမှာ ချက်ချင်း မြင်ရပါလိမ့်မယ်။';

  @override
  String get recurringExpenseTimingStart => 'လ၏ ၁ ရက်နေ့';

  @override
  String get recurringExpenseTimingEnd => 'လကုန်ရက်';

  @override
  String recurringExpenseAutoAdded(int count, String names) {
    return 'လစဉ်ကုန်ကျစရိတ် $count ခု အလိုအလျောက် ထည့်ပြီးပါပြီ — $names';
  }

  @override
  String get onboardModeTitle => 'All In One POS ကို ဘယ်လို သုံးမှာလဲ?';

  @override
  String get onboardModeOfflineTitle => 'Offline';

  @override
  String get onboardModeOfflineBody =>
      'ရောင်းချ + ကုန်ပစ္စည်းစီမံခန့်ခွဲမှုနဲ့ Account မလိုဘဲ အခမဲ့ စတင်နိုင်ပါတယ်။ Premium ဖွင့်ချင်ရင် License key ကို အချိန်မရွေး ထည့်နိုင်ပါတယ်။';

  @override
  String get onboardModeOnlineTitle => 'Online';

  @override
  String get onboardModeOnlineBody =>
      'Email နဲ့ ဆိုင် Account ဖန်တီးပါ။ 2လ အခမဲ့ စမ်းသုံးခွင့်ရမယ်၊ Settings ကနေ ဝန်ထမ်းနဲ့ ဆိုင်ခွဲတွေကို စီမံနိုင်ပါတယ်။';

  @override
  String get onboardModeCompareTitle => 'Online နဲ့ Offline — မရွေးခင် ဖတ်ပါ';

  @override
  String get onboardModeAckLabel => 'ကွာခြားချက်ကို ဖတ်ပြီးပါပြီ';

  @override
  String get onboardModeChooseHint =>
      'ဒီရွေးချယ်မှုက ဒီစက်ပေါ်မှာ အမြဲတမ်းပါ။ Settings ထဲကနေ နောက်မှ ပြောင်းလို့ မရပါ။';

  @override
  String get onboardModeOnlineBullets =>
      '• Device မရွေး email နဲ့ ဝင်နိုင်\n• ဝန်ထမ်းအကောင့်၊ ဆိုင်ခွဲ၊ cloud sync\n• Free ရပါတယ်။ Premium က online feature ပိုဖွင့်ပေး';

  @override
  String get onboardModeOfflineBullets =>
      '• Account / အင်တာနက် မလိုဘဲ ရောင်းနိုင်\n• License key က ဒီစက်ပေါ်မှာ\n• Free ရပါတယ်။ Premium က key နဲ့ — multi-device account feature မပါ';

  @override
  String get onboardOnlineTitle => 'ဆိုင် Account ဖန်တီးပါ';

  @override
  String get onboardOnlineBody =>
      'ဆိုင်အမည်၊ Email နဲ့ Password ပဲ လိုပါတယ် — 2လ အခမဲ့ စမ်းသုံးခွင့်နဲ့ စတင်နိုင်ပါပြီ။';

  @override
  String get onboardOnlineDone =>
      'Account ဖန်တီးပြီးပါပြီ။ အခမဲ့ စမ်းသုံးခွင့် စတင်ပါပြီ။';

  @override
  String get onboardOnlineCreateAccount => 'ဆိုင် Account ဖန်တီးမည်';

  @override
  String get onboardOnlineSignInTitle => 'ဆိုင် Account သို့ ဝင်မည်';

  @override
  String get onboardOnlineSignInBody =>
      'ရှိပြီးသားဆိုင်၏ email နဲ့ password ကို သုံးပါ။';

  @override
  String get onboardOnlineTabRegister => 'အကောင့်ဖန်တီးမည်';

  @override
  String get onboardOnlineTabSignIn => 'ဝင်မည်';

  @override
  String get onboardOnlineSignedIn => 'ဝင်ရောက်ပြီးပါပြီ။ ဆက်လုပ်နိုင်ပါတယ်။';

  @override
  String get modeMigrateTitle => 'ဆိုင်အလုပ်လုပ်ပုံကို အတည်ပြုပါ';

  @override
  String get modeMigrateBody =>
      'All In One POS က Online သို့မဟုတ် Offline mode ကို အမြဲတမ်း သတ်မှတ်အသုံးပြုပါသည်။ တစ်ကြိမ်သာ အတည်ပြုပါ — အက်ပ်ထဲကနေ နောက်မှ ပြောင်းလို့ မရပါ။';

  @override
  String get modeMigrateSuggestOnline =>
      'အကြံပြုချက်: Online (account / cloud)';

  @override
  String get modeMigrateSuggestOffline =>
      'အကြံပြုချက်: Offline (ဒီစက် + license key)';

  @override
  String get modeMigrateConfirm => 'အတည်ပြုပြီး ဆက်မည်';

  @override
  String get dailyGateTitle => 'ဒီနေ့ဆိုင် စသုံးမည်';

  @override
  String get dailyGateAccountStep => 'Account';

  @override
  String get dailyGateRoleStep => 'ဒီစက်ကို ဘယ်သူသုံးမလဲ';

  @override
  String get dailyGateBranchStep => 'ဆိုင်ခွဲ';

  @override
  String get dailyGateOpeningStep => 'ဖွင့်ငွေ';

  @override
  String get dailyGateContinue => 'ဆက်မည်';

  @override
  String get dailyGateSkipOpening => 'ဖွင့်ငွေ ကျော်မည်';

  @override
  String get dailyGateRoleOwner => 'ပိုင်ရှင်';

  @override
  String get dailyGateRoleStaff => 'ဝန်ထမ်း';

  @override
  String get dailyGateOpeningHint =>
      'ငွေကိုက်ထဲရှိငွေ ထည့်ပါ။ ဒီနေ့ till မလိုက်ဘူးဆိုရင် ကျော်နိုင်ပါတယ်။';

  @override
  String get dailyGateContinueAsOwner => 'ပိုင်ရှင်အဖြစ် ဆက်မည်';

  @override
  String get dailyGateContinueAsStaff => 'ဝန်ထမ်းအဖြစ် ဆက်မည်';

  @override
  String get dailyGateOrSignIn => 'သို့မဟုတ် account နဲ့ Sign in လုပ်ပါ';

  @override
  String get dailyGateWhoIsOpening => 'ဒီနေ့ဆိုင် ဘယ်သူဖွင့်မလဲ?';

  @override
  String get dailyGateCheckingShop => 'ဒီနေ့ဆိုင် စစ်နေပါတယ်…';

  @override
  String get operatingModeLabel => 'ဆိုင် mode';

  @override
  String get licenseAccountLinked => 'Cloud account ချိတ်ဆက်ထားပြီး';

  @override
  String get operatingModeOnline => 'Online';

  @override
  String get operatingModeOffline => 'Offline';

  @override
  String get currencySymbol => 'ကျပ်';

  @override
  String get receiptTitle => 'သက်တမ်းတိုး ပြေစာ';

  @override
  String get receiptStatusPending => 'အတည်ပြုရန် စောင့်ဆိုင်းဆဲ';

  @override
  String get receiptStatusPendingBody =>
      'ငွေပေးချေမှုကို ၂၄ နာရီအတွင်း စစ်ဆေးပါမယ်။ ဒီစာမျက်နှာကို သိမ်းထားပါ — အခြေအနေကို ဒီမှာပဲ ပြပါမယ်။';

  @override
  String get receiptStatusPaidBody =>
      'ငွေ လက်ခံရရှိပါပြီ။ လိုင်စင် ထုတ်ပေးနေပါတယ် — မကြာမီ ဒီစာမျက်နှာမှာ ပေါ်ပါမယ်။';

  @override
  String get receiptStatusFulfilled => 'အတည်ပြုပြီး';

  @override
  String get receiptStatusFulfilledBody =>
      'Premium သက်ဝင်ပါပြီ။ App ဖွင့်ပြီး Settings → လိုင်စင် မှာ \"သက်တမ်း ပြန်စစ်မည်\" ကို နှိပ်ပါ။';

  @override
  String get receiptStatusRejected => 'အတည်မပြုနိုင်ပါ';

  @override
  String get receiptShop => 'ဆိုင်နာမည်';

  @override
  String get receiptDeviceTail => 'App Reference ID နောက်ဆုံး';

  @override
  String get receiptPlan => 'အစီအစဉ်';

  @override
  String receiptMonths(int count) {
    return '$count လ';
  }

  @override
  String get receiptAmount => 'ပမာဏ';

  @override
  String get receiptMethod => 'ငွေလွှဲနည်း';

  @override
  String get receiptRefNo => 'လွှဲပြောင်းမှု နံပါတ်';

  @override
  String get receiptSubmittedAt => 'တင်သွင်းသည့်ရက်';

  @override
  String get receiptYourKey => 'သင့် License Key';

  @override
  String get receiptSaveLink =>
      'အခြေအနေ နောက်မှ ပြန်စစ်ရန် ဒီ link ကို သိမ်းထားပါ။';

  @override
  String get receiptCopyLink => 'Link ကူးမည်';

  @override
  String get receiptLinkCopied => 'Link ကူးပြီးပါပြီ';

  @override
  String get receiptRefresh => 'အခြေအနေ ပြန်စစ်မည်';

  @override
  String get receiptPrint => 'ပရင့်ထုတ်မည်';

  @override
  String get receiptNotFound => 'ဒီ link နဲ့ ပြေစာ မတွေ့ပါ။';

  @override
  String get receiptLoadFailed =>
      'ပြေစာ မဖတ်နိုင်ပါ။ အင်တာနက် စစ်ပြီး ထပ်ကြိုးစားပါ။';

  @override
  String get licenseExpiryNotifTitle => 'Premium သက်တမ်း ကုန်ခါနီးပါပြီ';

  @override
  String licenseExpiryNotifBody(int count, String shop) {
    return '$shop ရဲ့ Premium သက်တမ်း $count ရက် ကျန်ပါတယ်။';
  }

  @override
  String get licenseExpiryNotifTitleToday => 'Premium သက်တမ်း ဒီနေ့ ကုန်ပါမယ်';

  @override
  String licenseExpiryNotifBodyToday(String shop) {
    return '$shop ရဲ့ Premium သက်တမ်းက ဒီနေ့ နောက်ဆုံးရက် ဖြစ်ပါတယ်။';
  }
}
