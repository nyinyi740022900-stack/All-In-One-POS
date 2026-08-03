-- Lets a real-login owner account (see 0041's precursor, the `activate`
-- Edge Function's create_shop_login/invite_staff actions) group multiple
-- shop_ids they own as "branches" and switch which one their session is
-- scoped to. Deliberately owner-scoped, not shop-scoped — this table's whole
-- job is to span shops, so it does NOT use the shop_isolation pattern; RLS
-- is keyed off auth.uid() instead. Cloud-only bookkeeping (no Drift table),
-- same precedent as `licenses`.

create table if not exists org_branches (
  owner_user_id uuid not null,
  shop_id       text not null,
  label         text,
  created_at    timestamptz not null default now(),
  unique (owner_user_id, shop_id)
);
create index if not exists idx_org_branches_owner
  on org_branches (owner_user_id);

alter table org_branches enable row level security;
drop policy if exists org_branches_owner on org_branches;
create policy org_branches_owner on org_branches
  for all to authenticated
  using (owner_user_id = auth.uid())
  with check (owner_user_id = auth.uid());
