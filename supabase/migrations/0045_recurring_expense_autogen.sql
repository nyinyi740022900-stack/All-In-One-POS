-- Optional automatic generation for a recurring expense template, at
-- month-start or month-end, alongside the manual "Add from template"
-- quick-fill this feature originally shipped with (still available, unaffected).

alter table recurring_expenses
  add column if not exists auto_generate boolean not null default false;
alter table recurring_expenses
  add column if not exists generation_timing text not null default 'month_start';
alter table recurring_expenses
  add column if not exists last_generated_period text;
