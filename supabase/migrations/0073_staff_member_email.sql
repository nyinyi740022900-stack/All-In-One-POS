-- Optional email on a staff_members roster row, linking it to an invited
-- StaffAccount (Supabase Auth 'staff' login) sharing the same address, so a
-- granted OwnerCapability follows whichever way that person signs in.
-- No RLS change needed — shop_isolation already covers this table.
alter table staff_members add column if not exists email text;
