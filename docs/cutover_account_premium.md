# Account-Premium cutover runbook (0094–0096)

Written 2026-10-04, after rehearsing the chain locally. No staging project
exists: the org's Free plan holds two projects (production `All In One POS` and
the unrelated `Hello SG MM`). This runbook is what makes a staging-free cutover
defensible — and names the parts it cannot cover.

## What the rehearsal already settled

Run `python3 -m unittest supabase.tests.migration_chain_test
supabase.tests.migration_rollback_test` to reproduce all of it locally.

- All 96 migrations apply in order to a database holding only the platform's own
  objects. RLS ends up on every public table and no `dev_open` policy survives.
- On a production-shaped 0093 state the backfill carries every shop across: plan
  and latest expiry preserved, owner bound from the JWT claim, superseded
  devices dropped, archived shop flagged, revision 1 everywhere.
- A legacy key-only shop (no owner account) backfills with no owner and is
  refused a paid renewal rather than silently renewable.
- Historical trials stay spent, including deleted MM SHOP's for its two retained
  owner accounts, so nobody gets a second free term.
- `0094` refuses two owner accounts on one shop, or a shop over the three-device
  limit, **before any DDL** — a refused push leaves nothing half-built.
- Nothing in `0094`–`0096` is destructive: no table, column or row is dropped.
  `licenses` stays as audit evidence.
- `supabase/rollback/0094_0096_rollback.sql` returns the schema to 0093 exactly
  (tables, columns, function signatures, policy definitions, RLS flags,
  indexes), keeps every shop/licence/user/branch row, and the cutover reapplies
  cleanly afterwards.

## What no local rehearsal can cover

These are real-platform behaviours. They are the reason to want a staging
project, and the risk accepted by going straight to production.

1. **RLS through a real JWT.** `auth_shop_id()` now also requires a current
   subscription, trusted membership and a provisioned active device. The
   rehearsal fakes `auth.uid()`; only a real GoTrue session proves the claim
   shape matches. If it does not, existing devices lose cloud sync until they
   sign in again — local records and the outbox are untouched either way.
2. **Edge Functions as deployed**, with `ENTITLEMENT_SIGNING_KEY_HEX` signing a
   receipt the app then verifies. Docker is not installed here, so
   `supabase functions serve` is unavailable; `deno test`/`deno check` cover the
   handler logic only.
3. **Google/Apple login.** Untestable without a real Auth project. Both
   providers ship disabled, so this is not a cutover blocker — it stays
   unverified until there is a project to verify it on.
4. **Lemon Squeezy test mode.** The webhook needs a public URL, and the plan's
   own rule is that production must refuse test charges. Payment setup is the
   one piece that genuinely wants a separate project; keep it off until then.

## Order of operations

Stop if any step fails; the rollback below is only simple while the client is
still the pre-cutover build.

1. **Dump production first.** Free-plan backups are not a substitute. Take it
   yourself — an automated review has already rejected a full-data export from
   this session once.
2. Re-run the read-only preflight (`supabase/tests/account_premium_preflight.sql`)
   and confirm zero ownership, capacity and paid-allowance blockers. The
   2026-10-04 run was clean; re-run it, because the migration aborts on what it
   finds, not on what was true then.
3. `supabase db push` (applies 0094, 0095, 0096). A failure here is safe: the
   preflight raises before any DDL.
4. Deploy the Edge Functions, then the three web targets, then install the app.
   The order matters — the new functions tolerate the old client, not the
   reverse.
5. Verify on your own phone before anyone else's: sign in, confirm Premium is
   honoured from a signed receipt, add a third device, confirm the fourth is
   refused, then go offline and confirm expiry behaviour.
6. Confirm an existing staff device still syncs, and that a lapsed shop keeps
   its local records and outbox.

## Rolling back

```bash
psql "$PRODUCTION_URL" -f supabase/rollback/0094_0096_rollback.sql
```

Then redeploy the pre-cutover functions, web targets and app, and clear the
CLI's ledger so a later push reapplies the three migrations:

```sql
delete from supabase_migrations.schema_migrations
 where version in ('0094', '0095', '0096');
```

The script is verified by `supabase/tests/migration_rollback_test.py`. Re-derive
both it and that test if you add a migration above 0093.
