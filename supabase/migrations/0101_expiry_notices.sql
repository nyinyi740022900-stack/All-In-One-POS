-- Email reminders before Premium lapses.
--
-- The in-app watcher (license_expiry_watcher.dart) already warns at 7/3/1/0
-- days and is the right place for most of it: a POS is opened every trading
-- day. Its own comment names the assumption, and the assumption is where the
-- gap is — an owner who is travelling, who has changed phone, or who has
-- stopped opening the app after it lapsed is precisely the one who needs
-- telling, and is the one it cannot reach.
--
-- Claiming is separated from sending on purpose. A notice row is inserted
-- first and the mail goes out second, so two overlapping cron runs cannot
-- both send: the unique constraint refuses the second claim. A send that
-- then fails deletes its own claim, so the next run retries it. The failure
-- this orders for is a duplicate, because a second identical email is worse
-- than one arriving a day late.
create table shop_expiry_notices (
  shop_id text not null references shop_subscriptions(shop_id) on delete cascade,
  -- '<expires_at ISO>|<threshold>'. The expiry is inside the stamp, so
  -- renewing invalidates every outstanding claim on its own and the next
  -- cycle warns again, with no reset to remember anywhere.
  stamp text not null,
  channel text not null default 'email' check (channel in ('email')),
  sent_at timestamptz not null default now(),
  primary key (shop_id, stamp, channel)
);
alter table shop_expiry_notices enable row level security;
-- No policy: this is service-role-only bookkeeping. A shop has no reason to
-- read, and certainly none to write, the record of what it has been sent.

-- Days are counted in the shop's own calendar, not UTC. "7 days left" has to
-- mean what an owner in Yangon would say, or the mail arrives on the wrong day.
create function expiry_days_left(p_expires_at timestamptz) returns int
language sql immutable as $$
  select (date(p_expires_at at time zone 'Asia/Yangon')
        - date(now() at time zone 'Asia/Yangon'))::int
$$;

-- Claims the notices due right now and returns them to be sent.
--
-- 7/3/1 before, matching the in-app thresholds so the two never disagree,
-- plus one the day AFTER expiry — the case the in-app watcher deliberately
-- stays silent on, and the one an owner who has stopped opening the app can
-- only hear about by mail.
create function claim_expiry_notices(p_limit int default 200)
returns table (shop_id text, shop_name text, email text, plan text,
               expires_at timestamptz, days_left int, stamp text)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  return query
  with due as (
    select s.shop_id, s.shop_name, u.email::text as email, s.plan, s.expires_at,
           expiry_days_left(s.expires_at) as days_left
      from shop_subscriptions s
      join auth.users u on u.id = s.owner_user_id
     where s.is_archived = false
       and s.plan <> 'free'
       and coalesce(u.email, '') <> ''
       and not coalesce(u.is_anonymous, false)
       and (u.banned_until is null or u.banned_until <= now())
       and expiry_days_left(s.expires_at) in (7, 3, 1, -1)
     order by s.expires_at
     limit p_limit
  ), claimed as (
    insert into shop_expiry_notices (shop_id, stamp)
    select d.shop_id, d.expires_at::text || '|' || d.days_left from due d
    on conflict do nothing
    returning shop_expiry_notices.shop_id, shop_expiry_notices.stamp
  )
  select d.shop_id, d.shop_name, d.email, d.plan, d.expires_at, d.days_left, c.stamp
    from claimed c join due d on d.shop_id = c.shop_id;
end $$;

-- Undoes a claim whose mail did not go out, so the next run tries again.
create function release_expiry_notice(p_shop_id text, p_stamp text) returns void
language sql security definer set search_path=public,pg_temp as $$
  delete from shop_expiry_notices
   where shop_id = p_shop_id and stamp = p_stamp and channel = 'email'
$$;

revoke all on function claim_expiry_notices(int), release_expiry_notice(text,text),
  expiry_days_left(timestamptz) from public, anon, authenticated;
grant execute on function claim_expiry_notices(int), release_expiry_notice(text,text)
  to service_role;
