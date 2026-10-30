-- 016: clear the sample (demo) data, before Jon loads his real data
--
-- DO NOT RUN THIS DURING THE BUILD. Unlike every other numbered file, it is not
-- part of setting the database up: it is the first step of going live, run once,
-- by Jon (or Tien for him), after the build team has been removed. CLAUDE.md >
-- "Going live with real data" has the whole sequence.
--
-- It empties every table that holds CRM records (people, organizations, emails,
-- activity, follow-ups, deals, events, campaigns, RFPs, import batches, data
-- check runs) and starts their ids again from 1. It keeps everything that is
-- configuration or people on the team:
--   the reference tables (segments, channels, touch types, outcomes and their
--   rules, pipeline stages, reminder types, states, header aliases, import
--   profiles, benchmarks), team_members and their booking links, the shared
--   email templates, the "Don't cold email" list (flag_rules), and the audit log.
--
-- A guard stops it unless the line marked CONFIRM below is uncommented, so
-- running the db/ files in order by mistake does nothing. Before running it,
-- save a copy (step 1 in CLAUDE.md): there is no undo, and the free Supabase plan
-- keeps no backups.
--
-- How to run: Supabase dashboard > SQL Editor > New query > paste this whole
-- file > remove the two dashes in front of the CONFIRM line > Run. The result
-- shows how many rows each table has afterwards (all 0).

begin;

-- CONFIRM: remove the two dashes at the start of the next line to allow the delete.
-- set local gaard.clear_demo = 'yes, delete the sample data';

do $$
begin
  if coalesce(current_setting('gaard.clear_demo', true), '') <> 'yes, delete the sample data' then
    raise exception 'Nothing was deleted. Uncomment the CONFIRM line (set local gaard.clear_demo = ...) to clear the sample data.';
  end if;
end $$;

-- every CRM record table at once; no CASCADE, so a table not named here is never touched
truncate table
  public.import_rows,
  public.import_batches,
  public.email_messages,
  public.reminders,
  public.opportunities,
  public.touchpoints,
  public.rfps,
  public.contacts,
  public.organizations,
  public.events,
  public.campaigns
restart identity;

-- the weekly data check's history (db/013), if that file has been run
do $$
begin
  if to_regclass('public.data_check_runs') is not null then
    execute 'truncate table public.data_check_runs restart identity';
  end if;
end $$;

-- Claude connector keys (db/015) of people no longer on the team
do $$
begin
  if to_regclass('public.connector_keys') is not null then
    delete from public.connector_keys k
     using public.team_members t
     where t.id = k.team_member_id and not t.is_active;
  end if;
end $$;

-- Optional: the audit log still holds the history of the sample data. To start
-- it empty too, remove the two dashes in front of the next line.
-- truncate table public.audit_log restart identity;

commit;

-- what is left (every line should say 0)
select 'organizations' as table_name, count(*) from public.organizations
union all select 'contacts',       count(*) from public.contacts
union all select 'touchpoints',    count(*) from public.touchpoints
union all select 'email_messages', count(*) from public.email_messages
union all select 'reminders',      count(*) from public.reminders
union all select 'opportunities',  count(*) from public.opportunities
union all select 'events',         count(*) from public.events
union all select 'campaigns',      count(*) from public.campaigns
union all select 'rfps',           count(*) from public.rfps
union all select 'import_batches', count(*) from public.import_batches;
