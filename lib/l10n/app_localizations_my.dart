// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Burmese (`my`).
class AppLocalizationsMy extends AppLocalizations {
  AppLocalizationsMy([String locale = 'my']) : super(locale);

  @override
  String get appTitle => 'MM POS';

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
  String get commonYes => 'ဟုတ်ကဲ့';

  @override
  String get commonNo => 'မဟုတ်ပါ';

  @override
  String get commonTotal => 'စုစုပေါင်း';

  @override
  String get commonCopy => 'ကူးယူ';

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
  String get sellCheckout => 'ငွေရှင်း';

  @override
  String get sellSubtotal => 'ကုန်ကျ';

  @override
  String get sellDiscount => 'လျှော့ဈေး';

  @override
  String get sellPaymentMethod => 'ငွေပေးချေမှုနည်းလမ်း';

  @override
  String get sellAmountPaid => 'ပေးချေငွေ';

  @override
  String get sellChange => 'အ‌ကြွေ';

  @override
  String get sellConfirm => 'ရောင်းချမှုအတည်ပြု';

  @override
  String get sellClear => 'ရှင်းမည်';

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
  String get sellCompleted => 'ရောင်းချမှု ပြီးဆုံးပါပြီ';

  @override
  String get sellInsufficientPaid => 'ပေးချေငွေသည် စုစုပေါင်းထက် နည်းနေသည်။';

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
  String get creditTitle => 'အကြွေးစာရင်း';

  @override
  String get creditCustomerName => 'ဝယ်သူအမည်';

  @override
  String get customerPhone => 'ဖုန်း (မဖြည့်လည်းရ)';

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
  String get creditRepaymentSaved => 'ပြန်ဆပ်ငွေ မှတ်တမ်းတင်ပြီး';

  @override
  String get customersTitle => 'ဖောက်သည်များ';

  @override
  String get customersEmpty => 'ဖောက်သည် မထည့်ရသေးပါ။ ပထမဆုံး ဖောက်သည်ထည့်ပါ။';

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
  String get inventoryTitle => 'ကုန်ပစ္စည်း';

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
  String get productOnlineStockLimitHint =>
      'ရွေးချယ်ခွင့် — ဒီပစ္စည်းကို Web storefront ကနေ ဘယ်နှစ်ခုအထိပဲ ရောင်းချမလဲ ဆိုတာ ဆိုင်ထဲက အစစ်လက်ကျန်နဲ့ သီးခြား ကန့်သတ်ပါ။ ကွက်လပ်ထားရင် ကန့်သတ်ချက် မရှိပါ။';

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
  String stockAdjustCurrentStock(int quantity) {
    return 'လက်ရှိလက်ကျန်: $quantity';
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
  String get stockHistoryPickDateRange => 'ရက်စွဲအပိုင်းအခြား ရွေးရန်';

  @override
  String get stockHistoryClearDateRange => 'ရက်စွဲအပိုင်းအခြား ရှင်းရန်';

  @override
  String get stockMovementOpening => 'အစပိုင်း လက်ကျန်';

  @override
  String get stockMovementSale => 'ရောင်းချမှု';

  @override
  String get stockMovementReturn => 'ပြန်အမ်းငွေ';

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
  String get settingsTitle => 'ဆက်တင်';

  @override
  String get settingsSectionBusiness => 'ရောင်းဝယ်ရေး';

  @override
  String get settingsSectionFinance => 'ငွေကြေး';

  @override
  String get settingsSectionDevice => 'စက်/ဝန်ထမ်း';

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
      '၁။ အပေါ်ဆုံးမှာ ရက်စွဲကာလ ရွေးချယ်ပါ — ယနေ့၊ ဒီအပတ်၊ ဒီလ၊ (သို့) ကိုယ်ပိုင်ရွေးချယ်ခြင်း။\n၂။ အဲ့ကာလအတွက် အရောင်းစုစုပေါင်း၊ အမြတ်၊ ရောင်းချမှု အရေအတွက်ကို ကြည့်နိုင်ပါတယ်။\n၃။ အောက်ကို scroll ဆွဲပြီး အရောင်းရဆုံးပစ္စည်းများကို ဝင်ငွေ (သို့) အရေအတွက်အလိုက် အဆင့်သတ်မှတ်ပြထားတာ ကြည့်နိုင်ပါတယ်။\n၄။ အမြတ်ကိန်းဂဏန်းတွေက အဲ့အရောင်းအတွက် တကယ်မှတ်တမ်းတင်ထားတဲ့ အရင်းဈေးကို သုံးထားတာမို့ (ယနေ့ရဲ့ အရင်းဈေးသက်သက်မဟုတ်ဘဲ) — ပစ္စည်းရဲ့ အရင်းဈေး ပြောင်းလဲသွားပြီးနောက်မှာလည်း ယခင်အရောင်းတွေရဲ့ အမြတ် မှန်ကန်နေဆဲပါ။\n၅။ ကာလနှစ်ခုကို ယှဉ်ကြည့်ပြီး ပြန်မှာရမယ့်ပစ္စည်း (သို့) ဈေးနှုန်းပြင်ရမယ့်အရာကို ဆုံးဖြတ်ဖို့ trend ကို ကြိုတင်သိနိုင်ပါတယ်။';

  @override
  String get helpGuideSettingsTitle => 'Settings';

  @override
  String get helpGuideSettingsBody =>
      '၁။ \"ဆိုင်အချက်အလက်\" — ပြေစာနှင့် storefront ပေါ်မှာ ပြသမည့် ဆိုင်နာမည်၊ လိုဂို၊ လိပ်စာ၊ ဆက်သွယ်ရန် အချက်အလက်။\n၂။ \"ပရင်တာ\"/Label printer — Bluetooth receipt printer (သို့) label printer ချိတ်ဆက်ရန်။\n၃။ \"လိုင်စင်\" — key အတည်ပြုရန်၊ plan status ကြည့်ရန်၊ device ထည့်/ဖယ်ရှားရန်။\n၄။ \"My web storefront\" — Online ဆိုင် ဖွင့်ရန်နှင့် KBZPay/WavePay ငွေလွှဲအချက်အလက် သတ်မှတ်ရန်။\n၅။ \"Owner Tools\" (device ၂ လုံးနှင့်အထက် ရှိမှ ပေါ်မည်) — ဒီ device ကို staff တစ်ဦးဆီ လွှဲပေးရန်၊ (သို့) PIN နဲ့ Owner ပြန်ပြောင်းရန်။\n၆။ \"Sync\" — cloud နှင့် ချိတ်ဆက်မှု စစ်ဆေးရန်၊ (သို့) ချက်ချင်း sync ပြန်လုပ်ရန်။\n၇။ ဒီ screen ရဲ့ အပေါ်ဆုံးက dropdown ကနေ မြန်မာ/English ဘာသာစကားကို အချိန်မရွေး ပြောင်းနိုင်ပါတယ်။';

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
  String invoiceOwed(String amount) {
    return 'ကျန်ငွေ $amount';
  }

  @override
  String get invoicePrint => 'ပရင့်ထုတ်';

  @override
  String get invoiceReprint => 'ပြန်ထုတ်';

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
  String get invoiceRefundConfirmTitle => 'ဒီပြေစာကို ပြန်အမ်းမှာလား?';

  @override
  String get invoiceRefundConfirmBody =>
      'ရောင်းချမှုကို ပြန်ပြင်ပြီး ကုန်ပစ္စည်းအရေအတွက် ပြန်ဖြည့်ပါမည်။ နောက်ပြန်ရုတ်သိမ်း၍ မရပါ။';

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
  String get salesReportTitle => 'အရောင်း အစီရင်ခံစာ';

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
  String get salesReportColumnAmount => 'ပမာဏ';

  @override
  String get salesReportPrintBluetooth => 'Print ထုတ် (Bluetooth)';

  @override
  String get salesReportExportPdf => 'PDF ထုတ်';

  @override
  String get salesReportNoPrinter =>
      'Bluetooth printer သတ်မှတ်မထားပါ — Printer settings ကို ကြည့်ပါ။';

  @override
  String salesReportCount(int count) {
    return 'အရောင်း $count ခု';
  }

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
  String get printerPaired => 'ချိတ်ဆက်ထားသော စက်များ';

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
  String get printerPdfPaperSize => 'စာရွက် paper size';

  @override
  String get printerPdfPaperSizeHint =>
      'AirPrint (သို့) ကွန်ပျူတာကနေ print ထုတ်တဲ့ invoice/report အတွက်ပါ — အပေါ်က thermal printer အတွက် မဟုတ်ပါ။';

  @override
  String get paperA4 => 'A4';

  @override
  String get paperA5 => 'A5';

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
  String get productCategory => 'အမျိုးအစား';

  @override
  String get analyticsRevenue => 'ရောင်းရငွေ';

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
  String get analyticsRangeToday => 'ယနေ့';

  @override
  String get analyticsRangeWeek => '၇ ရက်';

  @override
  String get analyticsRangeMonth => '၃၀ ရက်';

  @override
  String get analyticsNoData => 'ဤကာလအတွင်း ရောင်းချမှု မရှိပါ။';

  @override
  String get analyticsDailyRevenue => 'နေ့စဉ် ရောင်းရငွေ';

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
      'လိုင်စင်သက်တမ်းကုန်ပါပြီ — ကြည့်ရှုသာရသည်။ ဆက်ရောင်းရန် သက်တမ်းတိုးပါ။';

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
  String get licenseDeactivate => 'လိုင်စင် ဖယ်ရှား';

  @override
  String get licenseDeactivateConfirm =>
      'ဒီ device ကနေ လိုင်စင် ဖယ်မှာလား? ကုန်ဆုံးရက် အတူတူ ဆက်ရှိနေမယ် — key အတူတူ ပြန် activate ရင် ရက်မပျောက်၊ အစက ပြန်မစပါဘူး။';

  @override
  String get licensePlanLabel => 'အစီအစဉ်';

  @override
  String get licensePlanMonthly => 'လစဉ်';

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
  String get licenseNoKeyTitle => 'Key မရှိသေးဘူးလား?';

  @override
  String get licenseNoKeyHint =>
      'Online စာရင်းသွင်း — KBZPay/WavePay နဲ့ ပေးချေပြီး key ကို ပို့ပေးပါမယ်။';

  @override
  String get licenseSubscribe => 'စာရင်းသွင်း / License ယူ';

  @override
  String get licenseRenew => 'သက်တမ်းတိုး';

  @override
  String licenseExpiringSoon(int days) {
    return 'License သက်တမ်း $days ရက် ကျန် — တိုးရန် နှိပ်ပါ။';
  }

  @override
  String get licenseThankYouTitle => 'ကျေးဇူးတင်ပါတယ်!';

  @override
  String get licenseThankYou24h =>
      'ငွေစစ်ဆေးပြီး ၂၄ နာရီအတွင်း စတင်အသုံးပြုလို့ရပါမယ်။';

  @override
  String get licenseFreeTrial => 'အခမဲ့ ၂ လ စမ်းသုံး';

  @override
  String get licenseTrialStarted => 'အခမဲ့ ၂ လ စမ်းသုံးမှု စတင်ပြီး';

  @override
  String get licenseTrialUsed =>
      'ဒီ device မှာ အခမဲ့ စမ်းသုံးမှု သုံးပြီးသားပါ။';

  @override
  String get licenseRefId => 'App Reference ID';

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
      'KPay/WavePay နဲ့ ပေးချေပြီး မှတ်တမ်းတင်ပြီးရင်၊ admin ကို approve ခိုင်းပါ။ ပြီးရင် \'သက်တမ်းတိုး စစ်ဆေး\' ကို နှိပ်ပါ။';

  @override
  String get deviceSectionTitle => 'Device များ';

  @override
  String deviceCount(int used, int free) {
    return 'အခမဲ့ device $used/$free သုံးထားပြီး';
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
    return 'ဒီဆိုင်က အခမဲ့ device $free လုံးကို အသုံးပြုပြီးဖြစ်ပါသည်။ ထပ်ထည့်ရန် $fee (တစ်ကြိမ်တည်း) ကျသင့်ပါမည် — ပေးချေပြီးရင် သင့် App Reference ID နဲ့ support ကို ဆက်သွယ်ပြီး device အသစ်ရဲ့ key ကို ရယူပါ။';
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
  String get invWebActivateTitle => 'ဒီ Computer ကို Activate လုပ်ပါ';

  @override
  String get invWebActivateHint =>
      'ဖုန်းပေါ်မှာ: Settings → License → Add device ကနေ key ရယူပြီး ဒီနေရာမှာ ကူးထည့်ပါ။';

  @override
  String get invWebKeyLabel => 'Device key';

  @override
  String get invWebActivateButton => 'Activate';

  @override
  String get invWebErrorEmptyKey => 'Device key ထည့်ပါ';

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
    return 'သင့်ဆိုင်အတွက် MM POS သုံးပါ! စာရင်းသွင်းတဲ့အခါ ကျွန်ုပ်၏ referral ကုဒ် $code ကို ထည့်ပါ။ — $shop';
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
  String get backupExportHint => 'data အားလုံးကို file အဖြစ်သိမ်းပြီး share';

  @override
  String get backupImport => 'Backup ပြန်သွင်း';

  @override
  String get backupImportHint => 'Backup file ကနေ data ပြန်ယူ';

  @override
  String get backupShareSubject => 'MM POS backup';

  @override
  String get backupShareText =>
      'MM POS data backup။ နောက်မှ ပြန်ယူဖို့ ဒီ file ကို သိမ်းထားပါ။';

  @override
  String get backupImportConfirmTitle => 'data အားလုံး အစားထိုးမလား?';

  @override
  String get backupImportConfirmBody =>
      'ဒါက လက်ရှိ ကုန်ပစ္စည်း၊ အရောင်း၊ အကြွေး data တွေကို ဖျက်ပြီး backup နဲ့ အစားထိုးမှာပါ။ ပြန်ပြင်လို့ မရပါ။';

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
  String get settingsSync => 'Cloud ချိတ်ဆက်မှု';

  @override
  String get syncNow => 'ယခု sync လုပ်';

  @override
  String get syncIdle => 'အသစ်ဖြစ်နေသည်';

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
  String get orderPaymentTransfer => 'ငွေလွှဲ';

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
  String get orderDeleteConfirm => 'ဒီအော်ဒါ ဖျက်မလား? ပြန်ဖျက်၍ မရပါ။';

  @override
  String get orderBlockCustomer => 'ဒီဝယ်သူကို ပိတ်ပင်မည်';

  @override
  String orderBlockCustomerConfirm(String phone) {
    return '$phone ကို သင့် storefront ပေါ်မှာ order အသစ် ထပ်တင်ခွင့် ပိတ်ပင်မလား?';
  }

  @override
  String get orderCustomerBlocked => 'ဝယ်သူ ပိတ်ပင်ပြီး';

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
      'ပြေစာထုတ်ပြီး catalog ပစ္စည်းများအတွက် stock နှုတ်ပါမည်။';

  @override
  String orderConverted(String invoice) {
    return 'အော်ဒါကို အရောင်းအဖြစ် ပြောင်းပြီး ($invoice)။';
  }

  @override
  String get orderAlreadySale => 'အရောင်းအဖြစ် မှတ်တမ်းတင်ပြီးပြီ။';

  @override
  String get orderCancel => 'ပြန်ပို့အဖြစ် မှတ်မည်';

  @override
  String get orderRestore => 'ပြန်ပို့မှု ပြန်ရုပ်သိမ်းမည်';

  @override
  String get orderReturnConfirmTitle => 'ဒီအော်ဒါကို ပြန်ပို့မည်လား?';

  @override
  String orderReturnConfirmBody(String amount) {
    return 'ဒါက $amount ပြန်အမ်းပေးမည်၊ အရောင်းကို ပြန်ပြင်ပေးမည်၊ ကုန်ပစ္စည်းလက်ကျန်ကိုလည်း ပြန်ထည့်ပေးမည်ဖြစ်ပြီး ပြန်ရုပ်သိမ်းလို့ မရတော့ပါ။';
  }

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
  String get staffWrongPin => 'PIN မှားနေပါသည်';

  @override
  String get staffPinHint => 'ဂဏန်း ၄–၆ လုံး';

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
  String get staffMemberSaved => 'ဝန်ထမ်းအချက်အလက် သိမ်းပြီး';

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
  String get storefrontEnabled => 'ဆိုင် ဖွင့်ထားသည်';

  @override
  String get storefrontCopied => 'Link ကူးယူပြီး';

  @override
  String get storefrontNeedsName => 'ဆိုင်နာမည် ထည့်ပါ';

  @override
  String get storefrontShare =>
      'ဒီ link ကို Facebook, Viber စသည်တွင် ဖောက်သည်များထံ မျှဝေပါ။';

  @override
  String get storefrontBlockedCustomers => 'ပိတ်ပင်ထားသော ဝယ်သူများ';

  @override
  String get storefrontNoBlockedCustomers => 'ဘယ်သူမှ ပိတ်ပင်မထားပါ။';

  @override
  String get storefrontUnblock => 'ပိတ်ပင်ချက် ဖြေလိုက်ပါ';

  @override
  String get storefrontAddBlocked => 'ဖုန်းနံပါတ် ပိတ်ပင်မည်';

  @override
  String get storefrontBlockReasonOptional => 'အကြောင်းရင်း (ရွေးချယ်ခွင့်)';

  @override
  String get storefrontPaymentInfoTitle => 'ငွေပေးချေမှု အကောင့်များ';

  @override
  String get storefrontPaymentInfoHint =>
      'ဖောက်သည်က checkout မှာ ဘယ်သူ့ဆီ လွှဲရမလဲ သိရအောင် ပြပေးပါမည်။';

  @override
  String get storefrontPayKpayName => 'KBZPay အကောင့်နာမည်';

  @override
  String get storefrontPayKpayNumber => 'KBZPay နံပါတ်';

  @override
  String get storefrontPayWaveName => 'WavePay အကောင့်နာမည်';

  @override
  String get storefrontPayWaveNumber => 'WavePay နံပါတ်';

  @override
  String get storefrontNumberCopied => 'နံပါတ် ကူးယူပြီး';

  @override
  String get storefrontRateLimited =>
      'မကြာသေးမီက order များစွာ တင်ထားပါတယ် — မိနစ်အနည်းငယ် စောင့်ပြီး ထပ်ကြိုးစားပါ။';

  @override
  String get storefrontBlocked =>
      'ဒီဆိုင်က ဒီဖုန်းနံပါတ်ကနေ order လက်မခံနိုင်တော့ပါ။ ဆိုင်ကို တိုက်ရိုက် ဆက်သွယ်ပါ။';

  @override
  String get storefrontOutOfStock =>
      'စိတ်မကောင်းပါဘူး၊ Cart ထဲက ပစ္စည်းတစ်ခု Online မှာ ကုန်သွားပါပြီ။ Cart ကို ပြင်ပြီး ထပ်ကြိုးစားပါ။';

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
  String get storefrontBankTransfer => 'ဘဏ်လွှဲ';

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
  String get onboardWelcomeTitle => 'GoldPOSMM မှ ကြိုဆိုပါတယ်';

  @override
  String get onboardWelcomeBody =>
      'မြန်မာဆိုင်များအတွက် offline-first POS app ပါ။ ဆိုင်ကို စတင်သတ်မှတ်ကြရအောင် — မိနစ်ပိုင်းပဲ ကြာပါမယ်။';

  @override
  String get onboardNext => 'ရှေ့ဆက်';

  @override
  String get onboardSkip => 'ကျော်';

  @override
  String get onboardGetStarted => 'စတင်မည်';

  @override
  String get onboardShopTitle => 'သင့်ဆိုင်';

  @override
  String get onboardShopBody => 'ဒါက ပြေစာပေါ်မှာ ပါဝင်ပါမယ်။';

  @override
  String get onboardLicenseTitle => 'အခမဲ့ Trial သို့မဟုတ် License Key';

  @override
  String get onboardLicenseBody =>
      'Card မလို၊ sign up မလိုဘဲ ၂ လ အခမဲ့ trial အလိုအလျောက် ရရှိပါမယ်။ Agent ဆီက license key ရှိပြီးသားလား? အခုပဲ activate လုပ်ပါ ဒါမှမဟုတ် နောက်မှ Settings ကနေ ထည့်နိုင်ပါတယ်။';

  @override
  String get onboardActivateNow => 'License key ချက်ချင်း activate';

  @override
  String get onboardStaffTitle => 'Owner နှင့် Staff Mode';

  @override
  String get onboardStaffBody =>
      'အခု Owner mode မှာ ရှိပါတယ် — အားလုံး ရနိုင်ပါတယ်။ ဖုန်းကို ဝန်ထမ်းကို လက်ဆင့်ကမ်းမလား? Settings → ပိုင်ရှင် Tools → Staff သို့ ပြောင်းပါ။ Staff mode မှာ Sell + Orders ပဲ မြင်ရမယ်၊ Owner ပြန်ဖို့ PIN လိုပါမယ်။';

  @override
  String get currencySymbol => 'ကျပ်';
}
