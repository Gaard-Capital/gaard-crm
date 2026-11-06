-- 023: keep only the events and RFPs Gaard acts on
--
-- Jon's rule (email of Nov 2026): the CRM holds only events marked Going or
-- Attended in the Event Finder, and only RFPs Gaard submitted (then shortlisted,
-- won or lost). The connector now refuses the rest (record_event, record_rfp);
-- this file takes off what came in before that change.
--
-- Events marked Maybe or Not decided (db/021): removed, unless people were met
-- at one, in which case it was attended and is marked Attended.
-- RFPs identified, intent to bid or declined, and one cancelled before it was
-- submitted: removed. Activities and deals that pointed at them stay, with the
-- link emptied; follow-ups tied to a removed RFP go with it. The audit log keeps
-- each deleted row in full, so a wrong removal can be put back.
--
-- How to run: Supabase dashboard > SQL Editor > New query > paste this whole
-- file > Run: nothing is deleted and a notice says so. Run only the first select
-- to see the counts. Then remove the two dashes in front of the CONFIRM line and
-- Run the whole file again. Safe to run twice.

-- What would change
select 'events removed (maybe or not decided, nobody met)' as what, count(*) from public.events e
 where e.attendance in ('maybe', 'undecided')
   and not exists (select 1 from public.touchpoints t where t.event_id = e.id)
   and not exists (select 1 from public.contacts c where c.source_event_id = e.id)
union all select 'events marked attended (people were met there)', count(*) from public.events e
 where e.attendance in ('maybe', 'undecided')
   and (exists (select 1 from public.touchpoints t where t.event_id = e.id) or exists (select 1 from public.contacts c where c.source_event_id = e.id))
union all select 'rfps removed (not submitted)', count(*) from public.rfps
 where status in ('identified', 'intent_to_bid', 'declined') or (status = 'cancelled' and submitted_on is null)
union all select 'rfps kept', count(*) from public.rfps
 where not (status in ('identified', 'intent_to_bid', 'declined') or (status = 'cancelled' and submitted_on is null));

begin;

-- CONFIRM: remove the two dashes at the start of the next line to allow the change.
-- set local gaard.only_acted_on = 'yes, keep only going, attended and submitted';

do $$
begin
  if coalesce(current_setting('gaard.only_acted_on', true), '') <> 'yes, keep only going, attended and submitted' then
    raise notice 'Nothing was changed. Uncomment the CONFIRM line to go ahead.';
    return;
  end if;

  -- the links are emptied without the automation, so no follow-up is rescheduled
  perform set_config('app.seeding', 'on', true);

  update public.events e set attendance = 'attended'
   where e.attendance in ('maybe', 'undecided')
     and (exists (select 1 from public.touchpoints t where t.event_id = e.id) or exists (select 1 from public.contacts c where c.source_event_id = e.id));
  update public.opportunities o set source_event_id = null from public.events e where o.source_event_id = e.id and e.attendance in ('maybe', 'undecided');
  update public.import_batches b set event_id = null from public.events e where b.event_id = e.id and e.attendance in ('maybe', 'undecided');
  delete from public.events where attendance in ('maybe', 'undecided');

  update public.touchpoints t set rfp_id = null from public.rfps r where t.rfp_id = r.id
     and (r.status in ('identified', 'intent_to_bid', 'declined') or (r.status = 'cancelled' and r.submitted_on is null));
  update public.opportunities o set rfp_id = null from public.rfps r where o.rfp_id = r.id
     and (r.status in ('identified', 'intent_to_bid', 'declined') or (r.status = 'cancelled' and r.submitted_on is null));
  delete from public.rfps where status in ('identified', 'intent_to_bid', 'declined') or (status = 'cancelled' and submitted_on is null);
end $$;

commit;

-- What is there now
select attendance as what, count(*) from public.events group by attendance
union all select 'rfp ' || status, count(*) from public.rfps group by status;
