-- Per-IP rate limit for the new self-serve `start_trial` action (activate
-- Edge Function). Same shape as 0037_activate_rate_limit.sql /
-- 0056_license_request_rate_limit.sql — self-serve trial has no email
-- requirement, so IP throttling is the main anti-farming backstop.
create table if not exists start_trial_attempts (
  id         uuid primary key default gen_random_uuid(),
  ip         text not null,
  created_at timestamptz not null default now()
);
create index if not exists idx_start_trial_attempts_lookup
  on start_trial_attempts (ip, created_at);

alter table start_trial_attempts enable row level security;
-- No policies: only the service-role client (which bypasses RLS) ever
-- touches this table.
