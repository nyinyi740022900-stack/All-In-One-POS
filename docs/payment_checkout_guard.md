# Payment fixes — 2026-10-05

Owner requested fixing the two payment findings from the Codex audit.

## Behavior

- `0097_gateway_checkout_guard.sql` serializes reservations using the shop row;
  two Edge Function instances cannot independently create two checkout links.
- A bound, ongoing processor subscription refuses a fresh purchase and offers
  the processor's verified management URL. Cancelled, paused, past-due and
  unpaid subscriptions stay blocked; only API-confirmed `expired` may close
  that binding and open a new one. Owner/store/mode checks remain mandatory.
- A pending URL is issued to its creating request only. It is never handed to
  another request/tab: hosted checkout links may create another payable cart.
- Closing a browser, reaching checkout expiry, processor timeouts or ambiguous
  responses never prove no payment occurred. Such reservations require support
  reconciliation; delayed signed invoices remain fulfilable. A definitive
  processor 4xx rejection before any URL was issued permits a new attempt.
- Existing duplicate/owner-mismatched bindings fail closed for support review;
  no financial history is deleted and no existing subscription is cancelled or
  refunded automatically. Direct reuse of a previously copied processor URL is
  outside the app's checkout issuance guard; the invoice RPC refuses a second
  subscription identity and such processor charges need support reconciliation.
- Real Supabase 502/503 `FunctionException` responses map to the dedicated
  unavailable message. 409 has existing-subscription/pending feedback in both
  languages. Authentication/ownership and transport failures retain their type.
- The checkout request remains bounded at 75 seconds to cover up to four
  sequential, separately bounded 15-second processor API calls plus DB work.

## Verification and scope

Tests reproduced the original failures before fixes: a second recurring
subscription received another term, checkout 502/503 escaped as FunctionException,
and another tab was handed an already-issued payable URL. Regression checks now
cover reservation races, delayed invoices, existing subscription statuses,
verified expiry, unsafe management links and original 403 errors.

Ripple audit: billing_checkouts is service-only, with no Drift copy, settings
keys or client derived providers. Its readers/writers are storefront and the
signed webhook; existing invoice identity, shop/owner checks and renewal
semantics remain. Full migration and cutover rollback tests include 0097.

- Isolated PostgreSQL: 120 passing tests, including the full 97-migration chain
  and rollback to 0093. No hosted staging project exists.
- Backend: 53 passing Deno tests; every Edge Function type-checks.
- Flutter: analyzer clean; all 1,026 tests pass, including the finalized HTTP error mapping tests.
- Deployment: production ledger independently confirms0097; storefront version44
  is ACTIVE. Shop deployment dpl_6gV4iKZiXXG9q4R8aAWp56guwMWJ is READY,
  aliased to https://shop.allinonepos.app. The live main.dart.js SHA256 matches
  the verified local build, /renew returns200 with the correct shop title, and
  an unauthenticated checkout request returns401/not_authenticated.
  No owner checkout, real charge, refund or cancellation was performed.
  Authenticated live purchase/management smoke testing remains to be done.

## Rollout order

1. Apply migration0097 before deploying the storefront function.
2. Deploy storefront; the existing signed webhook calls the replaced invoice
   RPC, so its source does not need a deployment.
3. Build the shop target with `tool/build_web.sh shop`; link the correct Vercel
   project immediately before production deployment and remove its generated
   `.env.local` from the upload directory. Verify the live shop title.
4. Verify the owner-facing existing/pending/unavailable states on the renewal
   web page. No store upload or phone build is required for this web-only fix.

Any live deployment rejection must be recorded here with the exact action and
reason, leaving the tested migration and web artifact ready for the owner.
