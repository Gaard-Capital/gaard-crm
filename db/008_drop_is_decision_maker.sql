-- 008: remove contacts.is_decision_maker
--
-- None of Jon's sheets has a decision-maker column. The schema added it for the
-- yearly rollover (try someone else at an organization that never answered),
-- but nothing fills it, the app never shows it, and every row is false.
--
-- Two views show it: v_contacts (the column itself) and v_organizations (a
-- count, decision_makers). A view cannot lose a column in place, so both are
-- rebuilt from their live definitions with those parts taken out. If a
-- definition does not look as expected, or a function still uses the column,
-- the script stops and nothing is changed.
--
-- Safe to run twice: once the column is gone it does nothing.
-- db/mock (seed.sql, csv) still lists the column; it describes the base schema
-- before this change.

begin;

do $$
declare
  def_contacts text;
  def_orgs     text;
  n            int;
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'contacts' and column_name = 'is_decision_maker') then
    raise notice 'contacts.is_decision_maker is already gone; nothing to do.';
    return;
  end if;

  -- A function that names the column would only fail when it runs, so stop now instead
  select count(*) into n
    from pg_proc p join pg_namespace s on s.oid = p.pronamespace
   where s.nspname = 'public' and p.prosrc ilike '%is_decision_maker%';
  if n > 0 then
    raise exception '% function(s) still use is_decision_maker; nothing was changed', n;
  end if;

  def_contacts := pg_get_viewdef('public.v_contacts'::regclass, true);
  def_orgs     := pg_get_viewdef('public.v_organizations'::regclass, true);

  def_contacts := regexp_replace(def_contacts, '\s*c\.is_decision_maker,', '', 'g');
  def_orgs     := regexp_replace(def_orgs, '\s*COALESCE\(cc\.decision_makers,[^A]*AS decision_makers,', '', 'g');
  def_orgs     := regexp_replace(def_orgs, ',\s*count\(\*\) FILTER \(WHERE \(?c\.is_decision_maker\)?\) AS decision_makers', '', 'g');
  def_contacts := regexp_replace(def_contacts, ';\s*$', '');
  def_orgs     := regexp_replace(def_orgs, ';\s*$', '');

  if def_contacts ilike '%decision_maker%' or def_orgs ilike '%decision_maker%' then
    raise exception 'The view definitions did not look as expected; nothing was changed';
  end if;

  -- Without cascade: if any other view is built on these two, this stops here
  drop view public.v_contacts;
  drop view public.v_organizations;

  alter table public.contacts drop column is_decision_maker;

  execute 'create view public.v_contacts with (security_invoker = true) as ' || def_contacts;
  execute 'create view public.v_organizations with (security_invoker = true) as ' || def_orgs;
  grant select on public.v_contacts, public.v_organizations to authenticated;
end $$;

commit;

-- The API picks up the changed columns
notify pgrst, 'reload schema';
