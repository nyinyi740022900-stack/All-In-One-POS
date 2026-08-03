-- sales.tax was never set/read anywhere in the app (no checkout UI, no
-- receipt/invoice line ever used it) — dead weight since it was added.
-- Removed after confirming with the shop owner rather than silently kept.

alter table sales drop column if exists tax;
