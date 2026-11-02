-- 022: take the sample events and RFPs off, keep what Jon's tools sent
--
-- Run once, after Jon's Claude has finished its catch-up (every Finder event and
-- tracker RFP sent through the connector, db/021). NOT before: an event or RFP
-- that has not been sent yet would be removed.
--
-- It removes every event with no finder_id and every RFP with no
-- tracker_synced_at. Activities, contacts, deals and import batches that pointed
-- at them stay, with the link emptied. Follow-ups tied to a removed RFP go with
-- it. People, organizations and activities are not deleted. The audit log keeps
-- each deleted row in full, so a wrong removal can be put back.
--
-- How to run: Supabase dashboard > SQL Editor > New query > paste this whole
-- file > Run: nothing is deleted and a notice says so. Run only the first select
-- to see the counts. Then remove the two dashes in front of the CONFIRM line and
-- Run the whole file again.

-- What would be removed, and what stays
select 'events removed' as what, count(*) from public.events where finder_id is null
union all select 'events kept', count(*) from public.events where finder_id is not null
union all select 'rfps removed', count(*) from public.rfps where tracker_synced_at is null
union all select 'rfps kept', count(*) from public.rfps where tracker_synced_at is not null;

begin;

-- CONFIRM: remove the two dashes at the start of the next line to allow the delete.
-- set local gaard.keep_only_finder = 'yes, remove the sample events and RFPs';

do $$
begin
  if coalesce(current_setting('gaard.keep_only_finder', true), '') <> 'yes, remove the sample events and RFPs' then
    raise notice 'Nothing was deleted. Uncomment the CONFIRM line to go ahead.';
    return;
  end if;
  if not exists (select 1 from public.events where finder_id is not null)
     or not exists (select 1 from public.rfps where tracker_synced_at is not null) then
    raise exception 'Nothing was deleted: the catch-up has not reached both the events and the RFPs yet.';
  end if;

  -- the links are emptied without the automation, so no follow-up is rescheduled
  perform set_config('app.seeding', 'on', true);

  update public.touchpoints t set event_id = null from public.events e where t.event_id = e.id and e.finder_id is null;
  update public.contacts c set source_event_id = null from public.events e where c.source_event_id = e.id and e.finder_id is null;
  update public.opportunities o set source_event_id = null from public.events e where o.source_event_id = e.id and e.finder_id is null;
  update public.import_batches b set event_id = null from public.events e where b.event_id = e.id and e.finder_id is null;
  delete from public.events where finder_id is null;

  update public.touchpoints t set rfp_id = null from public.rfps r where t.rfp_id = r.id and r.tracker_synced_at is null;
  update public.opportunities o set rfp_id = null from public.rfps r where o.rfp_id = r.id and r.tracker_synced_at is null;
  delete from public.rfps where tracker_synced_at is null;
end $$;

commit;

-- What is there now
select 'events' as what, count(*) from public.events
union all select 'rfps', count(*) from public.rfps;
