-- Premium price increase: 10,000 -> 20,000 Ks/month, 100,000 -> 200,000
-- Ks/year (keeps the existing "2 months free" annual-discount ratio).
-- 0008_admin_extras.sql seeded these rows; update in place rather than
-- re-inserting.
update app_config set value = '20000'  where key = 'price.monthly';
update app_config set value = '200000' where key = 'price.yearly';
