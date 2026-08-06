-- Storefront ops: opening hours (Yangon), require transfer payment proof.
-- Online-only table; no Drift sync.

alter table storefronts
  add column if not exists hours_enabled boolean not null default false;

alter table storefronts
  add column if not exists open_minute int;

alter table storefronts
  add column if not exists close_minute int;

alter table storefronts
  add column if not exists require_transfer_proof boolean not null default true;

comment on column storefronts.hours_enabled is
  'When true, catalog/submit use open_minute/close_minute (Asia/Yangon).';
comment on column storefronts.open_minute is
  'Minutes from midnight Yangon (0–1439). Null = treat as always open if hours_enabled.';
comment on column storefronts.close_minute is
  'Minutes from midnight Yangon. If open > close, schedule spans midnight.';
comment on column storefronts.require_transfer_proof is
  'When true, submit_order with payment_method=transfer requires payment_proof_path.';
