-- 019: what the Event Finder and the RFP tracker send to the CRM
--
-- 1. events.attendance: going, maybe, attended or not_going, so marking an event
--    "not going" in the Event Finder reaches the CRM. events.finder_id is the
--    Finder's own id for the event (one event, however its name changes) and
--    events.source_url its page.
-- 2. rfps: the RFP Log's own columns that had no column of their own. response
--    and correspondence are Jon's "Response" and "Correspondence"; winner is who
--    won a bid we lost; source_url is the RFP's page. decision_result stays what
--    db/002 made it (five fixed endings). Scoring and feedback stay in
--    decision_notes.
--
-- Safe to run twice.

begin;

alter table public.events
  add column if not exists attendance text,
  add column if not exists finder_id  text,
  add column if not exists source_url text;

do $$ begin
  alter table public.events add constraint events_attendance_check
    check (attendance in ('going', 'maybe', 'attended', 'not_going'));
exception when duplicate_object then null; end $$;

create unique index if not exists events_finder_id_uq on public.events (finder_id) where finder_id is not null;

alter table public.rfps
  add column if not exists response       text,
  add column if not exists correspondence text,
  add column if not exists winner         text,
  add column if not exists source_url     text;

commit;

notify pgrst, 'reload schema';
