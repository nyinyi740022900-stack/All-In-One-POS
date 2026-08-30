-- If 0077 stopped after DELETE and before rename, or was applied twice after
-- the column was already `ip`, finish the rename without failing.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'storefront_blocklist'
      and column_name = 'phone'
  ) then
    alter table storefront_blocklist rename column phone to ip;
  end if;
end $$;
