-- Offline vs Online pricing: a shop's tier is fixed at creation time (which
-- action minted its license — key activate/device trial/admin-issued key =
-- offline; the self-serve online signup/create-branch actions = online),
-- never inferred later from whichever session type happens to be active
-- (a real login can be added to an offline shop too, so that wouldn't be a
-- reliable signal). Defaults to 'offline' so every existing license and the
-- admin/reseller create_license RPC path need no changes at all.

alter table licenses add column if not exists tier text not null default 'offline';

-- Lets an admin manually reviewing a submitted renewal see which tier's
-- price should have applied, without recomputing it themselves.
alter table license_requests add column if not exists tier text;
