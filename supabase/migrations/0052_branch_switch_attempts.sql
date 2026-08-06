-- Idempotent branch switches: client sends switch_token; Edge Function stores
-- the successful response so retries/replays return the same payload without
-- re-applying auth metadata updates. Cloud-only (no Drift). Owner-scoped RLS
-- (service role used by activate still bypasses).

create table if not exists branch_switch_attempts (
  id              uuid primary key default gen_random_uuid(),
  owner_user_id   uuid not null,
  switch_token    text not null,
  from_shop_id    text not null default '',
  to_shop_id      text not null,
  response_json   jsonb not null,
  created_at      timestamptz not null default now(),
  unique (owner_user_id, switch_token)
);

create index if not exists idx_branch_switch_attempts_owner
  on branch_switch_attempts (owner_user_id);

alter table branch_switch_attempts enable row level security;

drop policy if exists branch_switch_attempts_owner on branch_switch_attempts;
create policy branch_switch_attempts_owner on branch_switch_attempts
  for all to authenticated
  using (owner_user_id = auth.uid())
  with check (owner_user_id = auth.uid());
