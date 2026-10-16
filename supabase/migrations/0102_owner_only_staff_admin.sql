-- Staff administration is the owner's, on the server too.
--
-- 0026 and 0072 were written when every device of a shop signed in as one
-- shared shop session, so `shop_id = auth_shop_id()` for ALL operations was
-- the only boundary there was to draw, and both files said so. 0094 changed
-- that: an invited staff member now holds their own authenticated identity,
-- and `auth_shop_id()` resolves for them exactly as it does for the owner.
-- The old policies therefore let a provisioned staff session grant itself
-- capabilities (staff_permissions) and rewrite another person's PIN or the
-- email that links an account to a roster profile (staff_members). The app
-- hid those screens; a client sending its own request was never stopped.
--
-- Reads stay shop-wide — a staff device needs the roster to pick a cashier
-- and its own grants to resolve permissions. Writes now also require the
-- caller to be the shop's owner (account_shop_role). Shop isolation and the
-- provisioned-device check inside auth_shop_id() are unchanged.
--
-- A write a staff device already queued is refused with 42501; the sync
-- engine keeps such a row in the outbox and retries it rather than wedging
-- the queue or discarding it, and the owner's own devices are unaffected.
-- Edge Functions using the service role bypass RLS as before.

create or replace function auth_is_shop_owner() returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
  select coalesce(
    account_shop_role(auth.uid(), nullif(auth_shop_id(), '')) = 'owner',
    false);
$$;
revoke all on function auth_is_shop_owner() from public, anon;
grant execute on function auth_is_shop_owner() to authenticated, service_role;

drop policy if exists shop_isolation on staff_permissions;
drop policy if exists owner_insert on staff_permissions;
drop policy if exists owner_update on staff_permissions;
drop policy if exists owner_delete on staff_permissions;
create policy shop_isolation on staff_permissions
  for select to authenticated
  using (shop_id = auth_shop_id());
create policy owner_insert on staff_permissions
  for insert to authenticated
  with check (shop_id = auth_shop_id() and auth_is_shop_owner());
create policy owner_update on staff_permissions
  for update to authenticated
  using (shop_id = auth_shop_id() and auth_is_shop_owner())
  with check (shop_id = auth_shop_id() and auth_is_shop_owner());
create policy owner_delete on staff_permissions
  for delete to authenticated
  using (shop_id = auth_shop_id() and auth_is_shop_owner());

drop policy if exists shop_isolation on staff_members;
drop policy if exists owner_insert on staff_members;
drop policy if exists owner_update on staff_members;
drop policy if exists owner_delete on staff_members;
create policy shop_isolation on staff_members
  for select to authenticated
  using (shop_id = auth_shop_id());
create policy owner_insert on staff_members
  for insert to authenticated
  with check (shop_id = auth_shop_id() and auth_is_shop_owner());
create policy owner_update on staff_members
  for update to authenticated
  using (shop_id = auth_shop_id() and auth_is_shop_owner())
  with check (shop_id = auth_shop_id() and auth_is_shop_owner());
create policy owner_delete on staff_members
  for delete to authenticated
  using (shop_id = auth_shop_id() and auth_is_shop_owner());
