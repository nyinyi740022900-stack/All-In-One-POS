# နိုင်ငံတကာ Premium ငွေပေးချေမှု Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lemon Squeezy မှ ငွေပေးချေပြီးလျှင် မှန်ကန်သော ဆိုင်အကောင့်၏ Premium သက်တမ်းကို တစ်ကြိမ်သာ တိုးပေးနိုင်ရန် server configuration ထည့်ပြီး staging မှ live သို့ စစ်ဆေးတင်ပို့ရန်။

**Architecture:** ဆိုင်ရှင်အကောင့်ကို စစ်ပြီး server က checkout link ဖန်တီးသည်။ ငွေပေးချေပြီးကြောင်း Lemon Squeezy ပေးပို့သည့် လက်မှတ်ပါအကြောင်းကြားချက်ကို စစ်ပြီးမှ ဆိုင်၏ သက်တမ်းကို တိုးသည်။ စမ်းသပ်စနစ်နှင့် live စနစ်၏ key၊ product variant နှင့် webhook များကို သီးခြားထားသည်။

**Tech Stack:** Flutter၊ Supabase Auth/Postgres/Edge Functions၊ Lemon Squeezy API/webhooks။

**Spec:** `docs/superpowers/specs/2026-10-03-account-premium-design.md`။ ယခုပြင်ဆင်မှုမှာ နိုင်ငံတကာငွေပေးချေမှု ချိတ်ဆက်ရန်ဖြစ်သည်။

## Global Constraints

- Premium ဝယ်ရန် owner account မဖြစ်မနေလိုပြီး ဆိုင်တစ်ဆိုင်ကို ရွေးရမည်။
- ဆိုင်တစ်ဆိုင် Premium သည် device စုစုပေါင်း၃ခု၊ grace၁၄ရက်ဖြစ်သည်။
- မြန်မာဈေးနှုန်းသည် တစ်လ၂၀,၀၀၀ကျပ်၊ တစ်နှစ်၂၀၀,၀၀၀ကျပ်ဖြစ်သည်။ နိုင်ငံတကာ variant ၏ လက်ရှိဈေးနှုန်း၊ ငွေကြေးကို ဤအလုပ်တွင် မပြောင်းပါ။
- API key ကို Supabase server secrets တွင်သာ ထားရမည်။ Chat၊ Git၊ Flutter app၊ admin public config နှင့် build artifacts ထဲ မထည့်ရ။
- ပေးချေမှုတစ်ခုအတွက် သက်တမ်းတစ်ကြိမ်သာ တိုးရမည်။ Checkout success page ဖွင့်ခြင်းတစ်ခုတည်းဖြင့် Premium မဖွင့်ရ။
- Staging စမ်းသပ်ပြီးမှ production ပြောင်းရမည်။ လက်ရှိ app/web/backend contract ပြောင်းလဲမှုကို အတူတကွ တင်ရမည်။
- ယခုစာတမ်းသည် plan ဖြစ်သည်။ Credentials မထည့်ရသေး၊ live deployment မလုပ်ရသေး။

## လက်ရှိအခြေအနေ

မကြာသေးမီ read-only စစ်ဆေးမှုအရ production တွင် API key နှင့် Store ID secret အမည်နှစ်ခု မရှိသေးပါ။ `LEMONSQUEEZY_WEBHOOK_SECRET` နှင့် Premium receipt signing secret အမည်များ ရှိနေသည်။ ရှိနေကြောင်းသာ စစ်ထားပြီး webhook secret မှန်ကန်မှုကို Lemon Squeezy နှင့် ထပ်တိုက်စစ်ရန်လိုသည်။

`storefront/index.ts` သည် configuration နှစ်ခု မရှိလျှင် checkout ကို `checkout_unavailable` ဖြင့် ငြင်းသည်။ `lemonsqueezy-webhook/index.ts` သည် စမ်းသပ်ငွေပေးချေမှုကို လက်ရှိတွင် ငြင်းသည်။ Product monthly/yearly variant ID များကို admin config မှဖတ်သည်။ Public Buy Now URL သည် account-bound checkout လမ်းကြောင်း၏ authority မဟုတ်ပါ။

| ထည့်ရမည့် configuration | ရှင်းလင်းချက် | သိမ်းရမည့်နေရာ |
|---|---|---|
| `LEMONSQUEEZY_API_KEY` | Server က ငွေပေးချေမှု link ဖန်တီးခြင်း၊ subscription အချက်အလက် စစ်ခြင်းအတွက် အသုံးပြုသော လျှို့ဝှက်သော့ | Supabase → Edge Functions → Secrets |
| `LEMONSQUEEZY_STORE_ID` | ငွေလက်ခံမည့် Lemon Squeezy ဆိုင်၏ နံပါတ် ID။ Store slug သို့မဟုတ် product ID မဟုတ်ပါ | Supabase → Edge Functions → Secrets |

## Task 1: ဆိုင်၊ အစီအစဉ်နှင့် credentials ကို တိုက်စစ်ခြင်း

**Files:** ဤ plan နှင့် `docs/superpowers/plans/2026-10-03-account-premium.md` တွင် လျှို့ဝှက်တန်ဖိုးမပါသော စစ်ဆေးရလဒ်များသာ မှတ်တမ်းတင်ရန်။

- [ ] Lemon Squeezy ဆိုင်၏ live ငွေလက်ခံနိုင်မှု၊ ရွေးထားသောဆိုင်နှင့် ပေးချေမှုလက်ခံမည့် account ကို dashboard တွင် စစ်ရန်။ မခွင့်ပြုသေးလျှင် checkout မဖွင့်ရ။
- [ ] Monthly/yearly product များသည် တစ်လ/တစ်နှစ် recurring subscription ဖြစ်ကြောင်း စစ်ရန်။ ဈေးနှုန်း၊ ငွေကြေး၊ product variant နှစ်ခုသည် မှန်ကန်သော Store ID အောက်တွင်ရှိကြောင်း စစ်ရန်။
- [ ] Staging အတွက် သီးခြား Supabase project ကို သတ်မှတ်ရန်။ လက်ရှိတွေ့ထားသော အခြားလုပ်ငန်း project ကို staging ဟု မယူဆရ။
- [ ] Lemon Squeezy Settings → API တွင် စမ်းသပ်မုဒ်အတွက် key တစ်ခု၊ live အတွက် key တစ်ခု ဖန်တီးရန်။ Dashboard မှ တိုက်ရိုက် secret storage ထဲ ထည့်ပြီး key တန်ဖိုးကို chat ထဲ မပို့ရန်။ [တရားဝင် API လမ်းညွှန်](https://docs.lemonsqueezy.com/guides/developer-guide/getting-started)။
- [ ] API ဖြင့် store အချက်အလက်ကို ဖတ်ပြီး numeric Store ID နှင့် monthly/yearly variants ကို တိုက်စစ်ရန်။ အောင်မြင်ကြောင်းနှင့် ကိုက်ညီကြောင်းသာ log ထုတ်ရန်။

**အောင်မြင်မှုစံ:** မှန်ကန်သော store၊ variant နှစ်ခုနှင့် သက်ဆိုင်ရာ test/live key များ သီးခြားအတည်ပြုပြီးဖြစ်ရမည်။

## Task 2: Staging တွင် စမ်းသပ်ငွေပေးချေမှု လမ်းကြောင်းပြင်ဆင်ခြင်း

**Files:**
- Create: `supabase/functions/_shared/gateway_mode.ts`
- Modify: `supabase/functions/storefront/index.ts` — checkout attributes တွင် test mode ကို server ဆုံးဖြတ်ရန်။
- Modify: `supabase/functions/lemonsqueezy-webhook/index.ts` — invoice/subscription နှစ်ခု၏ mode ကို စစ်ရန်။
- Test: `supabase/functions/tests/gateway_billing_test.ts`
- Create test: `supabase/functions/tests/gateway_mode_test.ts`

**Interface:** `gatewayTestMode(): boolean`။ `LEMONSQUEEZY_TEST_MODE=true` ကို staging မှာသာ အသုံးပြုနိုင်သည်။ Production project မှာ true ဖြစ်နေလျှင် configuration error ဖြင့် ပိတ်ထားရမည်။ ဤ flag သည် staging စမ်းသပ်ရေးအတွက်သာဖြစ်ပြီး live အတွက် မရှိလည်း false ဖြစ်ရမည်။

- [ ] Test များကို ဦးစွာရေးပြီး လက်ရှိ implementation မရှိသဖြင့် fail ဖြစ်ကြောင်း စစ်ရန်။ Cases: default false၊ staging true၊ production true ငြင်းခြင်း၊ expected mode နှင့် invoice/subscription မကိုက်ညီလျှင် payment မဖြည့်ခြင်း။
- [ ] Shared mode helper ကို အောက်ပါစည်းကမ်းအတိုင်း ထည့်ရန်။

```ts
export function gatewayTestMode(): boolean {
  const test = Deno.env.get("LEMONSQUEEZY_TEST_MODE") === "true";
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  if (test && (!url || new URL(url).hostname === "gnikispsurwrmkspuisj.supabase.co")) {
    throw new Error("test_mode_not_allowed");
  }
  return test;
}
```

- [ ] `handleCheckout` တွင် helper ကိုဖတ်၍ checkout `attributes.test_mode` သတ်မှတ်ရန်။ Configuration error ကို checkout unavailable ဖြင့် ပြန်ပေးရန်။ Client body ထဲမှ test mode ကို မယူရ။
- [ ] Webhook တွင် helper ကိုဖတ်၍ invoice `attrs.test_mode` နှင့် API မှဖတ်ထားသော subscription `test_mode` နှစ်ခုလုံး expected mode နှင့်တူမှသာ လက်ခံရန်။ Signature၊ store၊ variant၊ owner နှင့် invoice-id စစ်ဆေးမှုများကို ဆက်ထားရန်။
- [ ] Handler regression များတွင် production test-charge ကို ငြင်းကြောင်း၊ staging test-charge ကို staging ဆိုင်မှာသာ သက်တမ်းတိုးကြောင်း စစ်ရန်။ Test key နှင့် live key သည် သက်ဆိုင်ရာ mode မှာသာ အလုပ်လုပ်သည်။ [Lemon Squeezy စမ်းသပ်လမ်းညွှန်](https://docs.lemonsqueezy.com/guides/developer-guide/testing-going-live)။

**အောင်မြင်မှုစံ:** စမ်းသပ်ငွေဖြင့် live Premium ဖွင့်မရဘဲ staging တွင် အဆုံးထိ စမ်းနိုင်ရမည်။

## Task 3: Secrets၊ variants နှင့် webhook တပ်ဆင်ခြင်း

**Files/config:** Staging Supabase Edge Functions Secrets၊ app_config နှင့် Lemon Squeezy Settings → Webhooks။ Application source ထဲ credential မထည့်ရ။

- [ ] Staging Supabase တွင် `LEMONSQUEEZY_API_KEY`၊ `LEMONSQUEEZY_STORE_ID`၊ သီးခြား `LEMONSQUEEZY_WEBHOOK_SECRET` နှင့် staging-only `LEMONSQUEEZY_TEST_MODE=true` ထည့်ရန်။ [Supabase secrets လမ်းညွှန်](https://supabase.com/docs/guides/functions/secrets)။
- [ ] Staging admin config တွင် `pay.lemonsqueezy.variant_monthly` နှင့် `pay.lemonsqueezy.variant_yearly` တို့ကို စမ်းသပ် variants ဖြင့် သတ်မှတ်ရန်။
- [ ] Staging migrations0094/0095 ကို rehearsal လုပ်၍ `storefront` နှင့် `lemonsqueezy-webhook` တင်ရန်။ Webhook function တွင် platform JWT verification ပိတ်ပြီး handler ထဲက provider signature စစ်ဆေးမှု ဆက်ရှိရမည်။ Provider သည် Supabase user JWT မပို့ပါ။ [Supabase external webhook လမ်းညွှန်](https://supabase.com/docs/guides/functions/auth#external-webhooks)။
- [ ] Lemon Squeezy webhook URL ကို staging function URL အတိအကျဖြင့် ထည့်ပြီး `subscription_payment_success` event ကို ရွေးရန်။ Signing secret ကို staging secret နှင့် တူအောင် ထည့်ရန်။
- [ ] မရှိသော/မမှန်သော signature ဖြင့် request ကို ငြင်းကြောင်း စစ်ရန်။ မှန်ကန်သော signed event သာ handler သို့ဝင်ပြီး သက်တမ်းတိုးနိုင်ကြောင်း စစ်ရန်။

**အောင်မြင်မှုစံ:** Checkout ဖန်တီးနိုင်ပြီး provider အကြောင်းကြားချက်ကို မှန်ကန်စွာ လက်ခံ/ငြင်းနိုင်ရမည်။

## Task 4: ငွေပေးချေမှုနှင့် သက်တမ်းတိုးမှု စမ်းသပ်ခြင်း

**Tests:** `supabase/functions/tests/account_billing_test.ts`၊ `gateway_billing_test.ts`၊ `gateway_mode_test.ts`၊ `supabase/tests/account_billing_test.py`။

- [ ] Owner login → ဆိုင်ရွေး → monthly checkout → test payment → ဆိုင်သက်တမ်းတစ်လတိုး → app receipt refresh ဖြင့် Premium ဖွင့်ကြောင်း စစ်ရန်။
- [ ] Yearly checkout ဖြင့် တစ်နှစ်တိုးကြောင်း စစ်ရန်။ Checkout တွင် Lemon Squeezy trial ထပ်မရဘဲ app ၏ owner-once trial စည်းကမ်းသာ ဖြစ်ရမည်။
- [ ] တူညီသော invoice event ကို နှစ်ကြိမ်ပို့၍ expiry မထပ်တိုးကြောင်း၊ initial order event နှင့် invoice event ကြောင့် နှစ်ခါမတိုးကြောင်း စစ်ရန်။
- [ ] Grace အတွင်းတိုးလျှင် expiry ဟောင်းမှ၊ grace ကျော်လျှင် ယခုအချိန်မှ တိုးကြောင်း စစ်ရန်။
- [ ] အခြားဆိုင်ဝယ်ရန် ကြိုးစားခြင်း၊ owner မဟုတ်သော account၊ ပယ်ဖျက်ထားသော owner၊ wrong store/variant၊ အမည်မသိ checkout၊ ပေးချေမှုမအောင်မြင်ခြင်းတို့ဖြင့် Premium မဖွင့်ကြောင်း စစ်ရန်။
- [ ] Payment success redirect တစ်ခုတည်းဖြင့် Premium မဖွင့်ကြောင်း၊ webhook ကို စောင့်ပြီး receipt refresh လုပ်ရကြောင်း စစ်ရန်။
- [ ] `flutter analyze`၊ full `flutter test`၊ `deno check`၊ Deno handler tests နှင့် isolated SQL tests အားလုံး ပြန်စစ်ရန်။

**အောင်မြင်မှုစံ:** ငွေပေးချေမှုတစ်ခု၊ ဆိုင်တစ်ဆိုင်၊ သက်တမ်းတိုးမှုတစ်ကြိမ် ဖြစ်ရမည်။

## Task 5: Live သို့ပြောင်းခြင်း

**Files:** `PROJECT_SPEC.md` §12 နှင့် မူလ Premium execution plan တွင် အမှန်တကယ် deploy/test ရလဒ်ကို မှတ်တမ်းတင်ရန်။

- [x] 2026-10-04 တွင် MM SHOP (`shop-5bd659ab60b5`) နှင့် Home (`shop-d4937cb8b3`) ဆိုင်နှစ်ဆိုင်သာ ဖျက်ပြီးဖြစ်သည်။ License2၊ branch link3၊ payment account4 ဖျက်ပြီး ဆိုင်သို့ချိတ်ထားသော metadata4 ခု၏ shop_id ကို ဖြုတ်သည်။ Owner အကောင့်နှစ်ခုလုံးနှင့် account131ခု ဆက်ရှိသည်။ Business ledger rows နှင့် shop-prefix storage objects မရှိကြောင်း count-only စစ်ထားပြီး အခြားဆိုင် rows အရေအတွက် မပြောင်းကြောင်း transaction ထဲတွင် assert လုပ်ထားသည်။
- [x] Cleanup ပြီးလျှင် ownership preflight ကို ပြန်စစ်ပြီး ownership/device/paid-allowance blockers မရှိကြောင်း အတည်ပြုပြီးဖြစ်သည်။
- [ ] Processor ရှိ legacy recurring subscriptions ကို ရှိ/မရှိ စစ်ပြီး ရှိလျှင် verified owner/shop binding တည်ဆောက်ပြီးမှ ချိတ်ဆက်ရန်။ လက်ရှိ payment request/event record မရှိခြင်းကိုသာ အားကိုး၍ processor မှာ subscription မရှိဟု မယူဆရ။
- [ ] မူလ account-Premium migration ကို live မတင်မီ ဖျက်ထားသော MM SHOP ၏ historical trial evidence ကို owner account eligibility အတွက် ဆက်ထိန်းရန်။ Pre-delete read-only report တွင် MM SHOP သည် historical_trial=true ဖြစ်ပြီး trusted owner account နှစ်ခု ချိတ်ထားခဲ့သည်။ `0094_account_premium.sql` ၏ trial backfill ကို licenses မကျန်တော့သော ဤ legacy case အတွက် trusted server-side audit mapping ဖြင့် ဖြည့်စွက်ပြီး၊ account မဖျက်ဘဲ ဆိုင်ဖျက်ခြင်းကြောင့် once-owner trial ပြန်မရကြောင်း isolated SQL regression ထည့်ရန်။ Trial ရရှိရန်မဟုတ်ဘဲ အသုံးပြုပြီးသော trial အဖြစ် မှတ်တမ်းထိန်းရန်ဖြစ်သည်။
- [ ] Production secrets တွင် live API key၊ မှန်ကန်သော Store ID နှင့် live webhook signing secret ထည့်ရန်။ `LEMONSQUEEZY_TEST_MODE` ကို မထားရန် သို့မဟုတ် false ဖြစ်ရန်။ Test variant များကို production config ထဲ မထည့်ရ။
- [ ] စစ်ပြီး migrations/functions၊ admin/shop/invoices web နှင့် app ကို coordinated rollout ဖြင့် တင်ရန်။ Live webhook URL သည် `https://gnikispsurwrmkspuisj.supabase.co/functions/v1/lemonsqueezy-webhook` ဖြစ်သည်။
- [ ] တကယ်ငွေကုန်ကျမည့် live payment စမ်းသပ်မှုအတွက် plan နှင့် ဈေးနှုန်းကို ပြပြီး သီးခြားအတည်ပြုချက်ရယူရန်။ ပြီးလျှင် တစ်ကြိမ်သာ သက်တမ်းတိုး၊ မှန်ကန်သောဆိုင်မှာ Premium ပြန်ဖွင့်၊ device၃ခုစည်းကမ်းကို မပြောင်းကြောင်း စစ်ရန်။
- [ ] API outage၊ signature failure၊ unknown checkout ဖြစ်လျှင် ငွေပေးချေမှုထပ်လုပ်ခိုင်းမည့်အစား processor invoice နှင့် account binding ကို support က စစ်နိုင်ရန် error များကို တိုက်စစ်ရန်။ လိုအပ်လျှင် new checkout ကို ယာယီပိတ်ပြီး paid invoice evidence နှင့် renewal retry များကို ဆက်ထိန်းထားရန်။

**အောင်မြင်မှုစံ:** Live account-bound payment/renewal အလုပ်လုပ်ပြီး staging ငွေပေးချေမှုက live ဆိုင်ကို မသက်ရောက်ရ။

## ယခုအဆင့်၏ ရလဒ်

Plan ရေးပြီးဖြစ်သည်။ MM SHOP/Home ဆိုင်နှစ်ဆိုင် cleanup ပြီးဖြစ်ပြီး owner accounts ဆက်ရှိသည်။ Staging project နှင့် secure dashboard မှ ထည့်မည့် credentials တို့သည် payment execution အတွက် input များဖြစ်သည်။ Payment secrets၊ staging-mode code၊ deployment နှင့် live charge မလုပ်ရသေးပါ။

2026-10-04 cleanup verification: ကျန်ဆိုင်8ဆိုင်၊ legacy license9rows; ambiguous owner0၊ unverified branch0၊ excess device0၊ paid allowance0။ Local full-data backup export ကို automatic approval review ငြင်းသဖြင့် မလုပ်ခဲ့ပါ။ ခွင့်ပြုထားသော count-only စစ်ဆေးမှုနှင့် scoped transaction ဖြင့်သာ ဆိုင်နှစ်ဆိုင်ကို ရှင်းခဲ့သည်။


## 2026-10-04 configuration evidence

Owner explicitly approved creating the live API key and saving it in production Supabase. Created through Chrome for All In One POS, expiry2027-04-04. LEMONSQUEEZY_API_KEY saved on gnikispsurwrmkspuisj; local API-key SHA256 matched the server hash (CLI JSON uses a value field for the64-character hash). Merchant Store ID461190 was read from the Stores UI and saved as LEMONSQUEEZY_STORE_ID. Both set commands succeeded. Temporary0600 key file removed after verification. Extra JSON re-list rejected by automatic approval review; no bypass performed. No secret in repo/chat. This completes only the two live configuration values: staging/test-mode implementation, product/variant validation, signed webhook verification, deleted-trial audit preservation and coordinated Premium rollout are still pending. No real charge or checkout created.
