// Emails a shop owner before Premium lapses, and once after it has.
//
// The in-app watcher covers the ordinary case and this does not duplicate it:
// it exists for the owner the app cannot reach — travelling, on a new phone,
// or no longer opening an app whose Premium has already gone.
//
// Intended to be called once a day by Supabase's scheduled jobs with the
// service-role key. Deployed with JWT verification ON (the default), so the
// schedule's Authorization header is the only way in; there is nothing here
// for an anonymous caller.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// The sender that actually passes: `auth.allinonepos.app` is the subdomain
// carrying SPF, DKIM and DMARC, and the local part moved off "no-reply"
// when the deliverability work was done. The apex domain is not set up
// to send, so defaulting there is what made the first live run fail.
const FROM = Deno.env.get("REMINDER_FROM") ??
  "All In One POS <account@auth.allinonepos.app>";

interface Due {
  shop_id: string;
  shop_name: string | null;
  email: string;
  plan: string;
  expires_at: string;
  days_left: number;
  stamp: string;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const apiKey = Deno.env.get("RESEND_API_KEY");
  // Fail loudly rather than claiming notices it cannot then send: a claim
  // without a mail is a reminder silently swallowed for good.
  if (!apiKey) return json({ error: "mail_not_configured" }, 503);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data, error } = await admin.rpc("claim_expiry_notices", { p_limit: 200 });
  if (error) return json({ error: "server_error" }, 500);
  const due = (data ?? []) as Due[];

  let sent = 0;
  const failed: string[] = [];
  for (const row of due) {
    try {
      const mail = compose(row);
      const res = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        signal: AbortSignal.timeout(15000),
        body: JSON.stringify({
          from: FROM,
          to: [row.email],
          subject: mail.subject,
          html: mail.html,
        }),
      });
      if (!res.ok) {
        // The processor's own words, not a bare status: a rejected sender or
        // an unverified domain is otherwise indistinguishable from a timeout,
        // and the first live run cost exactly that diagnosis.
        throw new Error(`${res.status} ${(await res.text()).slice(0, 300)}`);
      }
      sent++;
    } catch (error) {
      console.error(`expiry reminder for ${row.shop_id} failed:`, error);
      // Hand the claim back so tomorrow retries it, rather than leaving a
      // reminder that was recorded as sent and never was.
      await admin.rpc("release_expiry_notice", {
        p_shop_id: row.shop_id,
        p_stamp: row.stamp,
      });
      failed.push(row.shop_id);
    }
  }
  return json({ ok: true, claimed: due.length, sent, failed: failed.length });
});

/// Bilingual, like every other mail this project sends: Myanmar first,
/// English under it. Says what lapses and what does not — a shop that keeps
/// selling on Free should not read this as "your till stops on Friday".
function compose(row: Due): { subject: string; html: string } {
  const shop = row.shop_name?.trim() || row.shop_id;
  const lapsed = row.days_left < 0;
  const days = row.days_left;
  const subject = lapsed
    ? `Premium သက်တမ်းကုန်သွားပါပြီ — ${shop}`
    : `Premium သက်တမ်း ${days} ရက် ကျန် — ${shop}`;
  const headlineMy = lapsed
    ? "Premium သက်တမ်း ကုန်သွားပါပြီ"
    : `Premium သက်တမ်း ${days} ရက် ကျန်ပါတယ်`;
  const headlineEn = lapsed
    ? "Premium has expired"
    : `${days} day${days === 1 ? "" : "s"} of Premium left`;
  const bodyMy = lapsed
    ? `${shop} ရဲ့ Premium သက်တမ်း ကုန်သွားပါပြီ။ အရောင်း၊ ကုန်ပစ္စည်းစာရင်း၊ ငွေဒရာဝါ၊ အကြွေးစာအုပ်နဲ့ backup တွေကတော့ အခမဲ့ ဆက်သုံးလို့ ရပါတယ်။ Cloud sync၊ အသေးစိတ် report နဲ့ ဝန်ထမ်းစီမံခြင်းတို့ ပြန်လိုချင်ရင် အောက်က ခလုတ်ကနေ သက်တမ်းတိုးနိုင်ပါတယ်။`
    : `${shop} ရဲ့ Premium သက်တမ်းက ${days} ရက်အတွင်း ကုန်ပါတော့မယ်။ သက်တမ်းတိုးထားရင် ဘာမှ ရပ်မသွားပါဘူး။`;
  const bodyEn = lapsed
    ? `Premium for ${shop} has ended. Selling, inventory, the cash register, the credit book and backups keep working on Free. Renew below to bring back cloud sync, detailed reports and staff accounts.`
    : `Premium for ${shop} ends in ${days} day${days === 1 ? "" : "s"}. Renewing before then keeps everything running without interruption.`;
  return {
    subject,
    html: `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="format-detection" content="telephone=no,date=no,address=no,email=no,url=no">
<style>a[x-apple-data-detectors]{color:inherit!important;text-decoration:none!important;}</style>
</head><body style="margin:0;padding:0;background:#f2f5fa;color:#17233b;font-family:Arial,'Noto Sans Myanmar',sans-serif;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f2f5fa;"><tr><td align="center" style="padding:28px 16px;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;">
<tr><td style="padding:0 8px 20px;font-size:19px;font-weight:bold;color:#1E63DB;">ALL IN ONE POS</td></tr>
<tr><td style="background:#ffffff;border:1px solid #e0e7f1;border-top:5px solid #1E63DB;border-radius:12px;padding:30px 24px;">
<p lang="my" style="margin:0 0 8px;font-size:22px;font-weight:bold;line-height:1.7;">${esc(headlineMy)}</p>
<h1 style="margin:0 0 22px;font-size:18px;line-height:1.5;color:#50627e;font-weight:normal;">${esc(headlineEn)}</h1>
<p lang="my" style="margin:0 0 14px;font-size:15px;line-height:1.9;">${esc(bodyMy)}</p>
<p style="margin:0 0 24px;font-size:14px;line-height:1.7;color:#50627e;">${esc(bodyEn)}</p>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0"><tr><td align="center" bgcolor="#1E63DB" style="border-radius:8px;">
<a href="https://shop.allinonepos.app/renew" style="display:block;padding:16px 12px;color:#ffffff;font-size:16px;font-weight:bold;line-height:1.8;text-decoration:none;">
<span lang="my">သက်တမ်း တိုးရန်</span><br><span style="font-size:14px;font-weight:normal;">Renew Premium</span></a>
</td></tr></table>
<p lang="my" style="margin:22px 0 0;font-size:13px;line-height:1.9;color:#67768c;">ဤစာသည် သင့်ဆိုင်၏ သက်တမ်းအကြောင်း အသိပေးချက် ဖြစ်ပါသည်။</p>
<p style="margin:4px 0 0;font-size:12px;line-height:1.7;color:#67768c;">A service notice about your own shop's subscription.</p>
</td></tr>
<tr><td align="center" style="padding:20px 12px;color:#78859a;font-size:12px;line-height:1.9;">All In One POS</td></tr>
</table></td></tr></table></body></html>`,
  };
}

function esc(s: string): string {
  return s.replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]!);
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
