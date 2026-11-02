-- 021: every event of the Event Finder and every RFP of the tracker in the CRM
--
-- 1. events.attendance may also be 'undecided', for an event the Finder found and
--    Jon has not marked yet. It shows on the Events page as Not decided and is
--    left out of the totals and the KPIs.
-- 2. rfps.tracker_synced_at is stamped by record_rfp, so an RFP that came from
--    Jon's tracker can be told from a sample one (db/022 relies on it).
--
-- Run this before deploying the claude-connector that sends these values.
-- Safe to run twice.

begin;

alter table public.events drop constraint if exists events_attendance_check;
alter table public.events add constraint events_attendance_check
  check (attendance in ('going', 'maybe', 'attended', 'not_going', 'undecided'));

alter table public.rfps add column if not exists tracker_synced_at timestamptz;

commit;

notify pgrst, 'reload schema';
