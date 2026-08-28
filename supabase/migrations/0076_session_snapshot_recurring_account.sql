-- Freeze Cash Register expected cash at close (so a later expense edit
-- cannot rewrite yesterday's variance), and let recurring templates copy
-- an account_id onto generated expenses (null = till, same as expenses).

alter table cash_sessions
  add column if not exists expected_cash_at_close integer;

alter table recurring_expenses
  add column if not exists account_id text;
