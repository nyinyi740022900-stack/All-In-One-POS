-- Replaces the fixed KBZPay/WavePay-only pay_kpay*/pay_wave* columns with a
-- flexible list so a shop outside Myanmar can name whatever payment method
-- it actually uses (PayPal, PromptPay, bank transfer, ...). Old columns are
-- kept (not dropped) — no client reads/writes them anymore after this
-- deploy, but dropping columns with real production data needs a separate,
-- explicit decision, not bundled into this feature migration.
alter table storefronts
  add column if not exists payment_methods jsonb not null default '[]'::jsonb;

-- Backfill: any shop that already set KBZPay/WavePay gets an equivalent
-- payment_methods entry, so existing storefronts keep working unchanged.
update storefronts
set payment_methods = (
  select jsonb_agg(entry)
  from (
    select jsonb_build_object(
      'label', 'KBZPay',
      'account_name', coalesce(pay_kpay_name, ''),
      'account_number', pay_kpay
    ) as entry
    where pay_kpay is not null and pay_kpay <> ''
    union all
    select jsonb_build_object(
      'label', 'WavePay',
      'account_name', coalesce(pay_wave_name, ''),
      'account_number', pay_wave
    )
    where pay_wave is not null and pay_wave <> ''
  ) entries
)
where (pay_kpay is not null and pay_kpay <> '')
   or (pay_wave is not null and pay_wave <> '');
