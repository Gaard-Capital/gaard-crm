-- 020_contact_status_override.sql
--
-- One column: the Active / Dormant / Dead value Jon sets by hand on a contact.
-- Left null, the app works the status out on its own (dead when they declined
-- or three follow-ups across three quarters went unanswered, active while an
-- opportunity or a follow-up is open, dormant otherwise), so an empty column
-- changes nothing that is on screen today.
--
-- Safe to run twice. The app does not need it: until this has been run it
-- hides the hand-set option and says so (Live.has), and everything else works.
-- Run it when convenient, then the Status column on Contacts and the Status
-- line on a contact's record can be set by hand.

begin;

alter table public.contacts
  add column if not exists status_override text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.contacts'::regclass
       and conname  = 'contacts_status_override_check'
  ) then
    alter table public.contacts
      add constraint contacts_status_override_check
      check (status_override is null or status_override in ('active','dormant','dead'));
  end if;
end $$;

comment on column public.contacts.status_override is
  'Active / Dormant / Dead set by hand. Null means the app works it out from the activity.';

commit;

-- Check it landed:
--   select column_name, data_type from information_schema.columns
--    where table_schema = 'public' and table_name = 'contacts' and column_name = 'status_override';
