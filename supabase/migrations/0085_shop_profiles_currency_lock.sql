-- Server-side backstop for the after-first-sale currency lock. The app's own
-- check (SettingsRepository.currencyChangeAllowed) only looks at the LOCAL
-- `sales` table on the calling device — a second device that hasn't yet
-- pulled down the shop's sales could otherwise push a currency change before
-- its own lock catches up. This mirrors the same rule at the database level
-- so no device, however stale, can get a currency change through.
--
-- UPDATE-only: a brand-new shop_profiles row (first-ever insert) can't have
-- a prior sale yet, so there's nothing to lock at insert time; the race this
-- guards against is a device pushing a *change* to an existing row.
create or replace function enforce_shop_currency_lock() returns trigger
language plpgsql
as $$
begin
  if new.currency_code is distinct from old.currency_code then
    if exists (
      select 1 from sales
      where shop_id = new.shop_id and is_deleted = false
      limit 1
    ) then
      raise exception 'currency_locked_after_first_sale'
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists shop_profiles_currency_lock on shop_profiles;
create trigger shop_profiles_currency_lock
  before update on shop_profiles
  for each row
  execute function enforce_shop_currency_lock();
