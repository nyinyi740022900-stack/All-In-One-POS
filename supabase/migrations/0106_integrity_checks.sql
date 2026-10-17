-- Play Integrity verdicts for the Android calls that grant a trial or a
-- Premium receipt (activate: refresh_account_license, resync_session,
-- switch_branch, start_trial). See supabase/functions/_shared/play_integrity.ts.
--
-- Service-role only: written by the activate Edge Function, read by the admin
-- function. RLS is on with NO policies, so anon/authenticated see nothing.
create table if not exists public.integrity_checks (
  id                bigint generated always as identity primary key,
  created_at        timestamptz not null default now(),
  user_id           uuid,
  shop_id           text,
  device_id         text,
  action            text not null,
  platform          text,
  app_build         integer,
  verdict           text not null,
  reason            text,
  app_verdict       text,
  device_verdict    text,
  licensing_verdict text,
  version_code      bigint,
  -- One-time value bound into the token's request hash; reusing it is a
  -- replay, which the unique index turns into an insert conflict.
  nonce             text,
  mode              text not null default 'monitor'
);

create unique index if not exists integrity_checks_nonce_uq
  on public.integrity_checks (nonce) where nonce is not null;
create index if not exists integrity_checks_created_idx
  on public.integrity_checks (created_at desc);

alter table public.integrity_checks enable row level security;
revoke all on public.integrity_checks from anon, authenticated;

-- Start in monitor mode: every verdict is recorded, nothing is blocked. The
-- admin console flips this to 'enforce' after the closed beta.
insert into public.app_config (key, value)
values ('integrity.android_mode', 'monitor')
on conflict (key) do nothing;
