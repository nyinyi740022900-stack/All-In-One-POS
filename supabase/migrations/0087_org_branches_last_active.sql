-- Tracks which branch an owner's real-login session was last actually
-- switched to, so `resolveShopId` (activate/index.ts) can restore that
-- branch when a reinstalled/reissued session's JWT loses its `shop_id`
-- claim. Previously that fallback picked whichever of the owner's branches
-- had the furthest license `expires_at` — a device could silently get
-- rebound to a completely different (longer-remaining) branch than the one
-- the owner was actually using, with sales then recorded into the wrong
-- branch's ledger.
--
-- Defaults to now() so every EXISTING branch row (created before this
-- migration) reads as "just active" until the owner next switches, which is
-- strictly safer than the previous furthest-expiry heuristic it replaces —
-- worst case it's a coin-flip among branches with the same default instead
-- of a systematic bias toward whichever branch happens to have the longest
-- remaining license.
alter table org_branches
  add column if not exists last_active_at timestamptz not null default now();
