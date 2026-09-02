-- Shop country flag: routes the License screen to Myanmar's /renew web
-- page vs. the in-app Lemon Squeezy checkout for non-Myanmar shops.
-- shop_isolation RLS already covers this table row-level; no policy change.
alter table shop_profiles add column if not exists country text not null default 'MM';
