-- Storefront payment account names, alongside the existing numbers — so a
-- customer transferring via KBZPay/WavePay sees WHO to send to, not just a
-- bare phone number. Purely additive (nullable, existing rows unaffected).

alter table storefronts add column if not exists pay_kpay_name text;
alter table storefronts add column if not exists pay_wave_name text;
