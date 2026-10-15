/* ======================================================================
   006  DATES WITH A THREE-DIGIT YEAR
   Run once in the Supabase SQL Editor. Safe to run again.

   A sheet cell typed as 11/20/205 (a 2 missing from 2025) did not match
   any of parse_loose_date's patterns, fell through to a plain cast, and
   was stored as the year 205. One contact and one touchpoint came in that
   way.

   1. Those dates are moved to the 2020s (205 becomes 2025), which is
      when the rest of the sheet's dates fall.
   2. parse_loose_date now refuses any year before 1900 and returns null,
      so the import flags the row instead of storing a wrong date.
   ====================================================================== */

begin;

-- The app's automation stands down for these corrections, as in apply_changes()
select set_config('app.seeding', 'on', true);

update public.contacts      set sourced_on = sourced_on + interval '1820 years'
 where sourced_on < date '1000-01-01';
update public.touchpoints   set touched_at = touched_at + interval '1820 years'
 where touched_at < timestamptz '1000-01-01';
update public.opportunities set opened_on = opened_on + interval '1820 years'
 where opened_on < date '1000-01-01';
update public.reminders     set due_on = due_on + interval '1820 years'
 where due_on < date '1000-01-01';

create or replace function public.parse_loose_date(p text)
 returns date
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  s text := trim(coalesce(p, ''));
  d date;
begin
  if s = '' then return null; end if;
  if s ~ '^\d{4}-\d{1,2}-\d{1,2}' then d := to_date(substring(s from '^\d{4}-\d{1,2}-\d{1,2}'), 'YYYY-MM-DD');
  elsif s ~ '^\d{1,2}/\d{1,2}/\d{4}$' then d := to_date(s, 'MM/DD/YYYY');
  elsif s ~ '^\d{1,2}/\d{1,2}/\d{2}$'  then d := to_date(s, 'MM/DD/YY');
  elsif s ~ '^\d{1,2}/\d{1,2}$'        then return null;          -- no year: too ambiguous
  else d := s::date;
  end if;
  if d < date '1900-01-01' then return null; end if;            -- a typo like 11/20/205
  return d;
exception when others then
  return null;
end $function$;

commit;

-- Check: both should be 0
select (select count(*) from public.contacts where sourced_on < date '1990-01-01') as contacts_left,
       (select count(*) from public.touchpoints where touched_at < timestamptz '1990-01-01') as touchpoints_left;
