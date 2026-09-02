-- Per-shop POS currency (Ks/THB/$/¥) — see the multi-country foundation
-- design doc. shop_isolation RLS already covers this table row-level; no
-- policy change.
alter table shop_profiles add column if not exists currency_code text not null default 'MMK';
