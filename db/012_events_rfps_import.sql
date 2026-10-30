/* ======================================================================
   012  EVENTS AND RFP SHEETS: IMPORTERS FOR JON'S TWO TEMPLATES
   Run once in the Supabase SQL Editor, after 001-011. Safe to run again.

   Jon tracks events and RFPs separately, so each sheet has its own
   importer, run with the same two lines as every workbook tab:

     select * from check_upload_headers('upload_events', 'Events');
     select import_gaard_tab('upload_events', 'Events');
     select * from check_upload_headers('upload_rfps', 'RFPs');
     select import_gaard_tab('upload_rfps', 'RFPs');

   1. events gets the Event ROI Tracker's own counts (# of Contacts,
      # of Responses, # of Meetings, Clients Won ($)); v_event_performance
      shows cost per contact / response / meeting and won-per-dollar from
      them until the CRM can count for itself.
   2. import_header_aliases gets a scope (contact / event / rfp) so the
      Events sheet and the RFP log are read with their own vocabulary.
   3. import_events_table(): one row per event -> events (same name + same
      date = one event, blanks filled, nothing overwritten).
   4. import_rfps_table(): one row per RFP -> organization (matched by
      website or name, else created), optional contact, the rfps row with the
      002 columns (reference_number, approved_for_submission, reviewed_by,
      reviewed_on, terms, decision_result, decision_notes), and the RFP
      touches for submitted / finalist / won / lost. "RFP Name / Issuer" is
      split at the slash; the status comes from WON, then the Response
      wording, then the dates and the approval.
   5. People met at events: a contact sheet with an "Event" column ties
      each person and their touch to that event (process_import_batch v4).
   6. Profiles "Events", "Event attendees", "RFPs"; rfp_status_aliases
      (Watching, Shortlisted, Awarded, No bid ... -> the RFP statuses).
   7. parse_loose_date: stricter free-form fallback ("Oct 3-5, 2025" used
      to come back as the year 2005), keeping 006's rule that a year
      before 1900 is refused.

   If the earlier draft of this file (migration "10", Oct 19) was run, the
   columns it added to rfps are folded into the 002 columns and dropped.
   ====================================================================== */

begin;

alter table public.events add column if not exists people_met_reported int;
comment on column public.events.people_met_reported is 'People met according to the event sheet, used when the attendees were not entered by name';
alter table public.events add column if not exists responses_reported int;
comment on column public.events.responses_reported is 'Follow-up responses according to the event sheet ("# of Responses")';
alter table public.events add column if not exists meetings_reported int;
comment on column public.events.meetings_reported is 'Meetings that came out of the event according to the sheet ("# of Meetings")';
alter table public.events add column if not exists clients_won_usd numeric(14,2);
comment on column public.events.clients_won_usd is 'Dollar value of clients won from the event according to the sheet ("Clients Won ($)")';

-- the RFP log columns are 002's; the Oct 19 draft's duplicates, if they exist, are folded in and dropped
alter table public.rfps
  add column if not exists reference_number        text,
  add column if not exists approved_for_submission boolean,
  add column if not exists reviewed_by             text,
  add column if not exists reviewed_on             date,
  add column if not exists terms                   text,
  add column if not exists decision_result         text,
  add column if not exists decision_notes          text;
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'rfps'
              and column_name in ('reference_no', 'conditions', 'response_text', 'reviewed_by_id')) then
    drop view if exists public.v_rfp_tracker;              -- the draft's view used those columns; rebuilt below
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'rfps' and column_name = 'reference_no') then
    update public.rfps set reference_number = coalesce(reference_number, reference_no) where reference_no is not null;
    alter table public.rfps drop column reference_no;
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'rfps' and column_name = 'conditions') then
    update public.rfps set terms = coalesce(terms, conditions) where conditions is not null;
    alter table public.rfps drop column conditions;
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'rfps' and column_name = 'response_text') then
    update public.rfps set decision_notes = coalesce(decision_notes, 'Response: ' || response_text) where response_text is not null;
    alter table public.rfps drop column response_text;
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'rfps' and column_name = 'reviewed_by_id') then
    update public.rfps r set reviewed_by = coalesce(r.reviewed_by, t.full_name) from public.team_members t where t.id = r.reviewed_by_id;
    alter table public.rfps drop column reviewed_by_id;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 2. Header aliases with a scope
-- ---------------------------------------------------------------------
alter table public.import_header_aliases add column if not exists scope text not null default 'contact';
alter table public.import_header_aliases drop constraint if exists import_header_aliases_pkey;
alter table public.import_header_aliases add primary key (header_key, scope);
alter table public.import_header_aliases drop constraint if exists import_header_aliases_field_check;
-- field names the Oct 19 draft used, if it was run
update public.import_header_aliases set field = 'reference_number' where field = 'reference_no';
update public.import_header_aliases set field = 'terms' where field = 'conditions';
alter table public.import_header_aliases add constraint import_header_aliases_field_check check (
  (scope = 'contact' and field in (
    'date_added', 'source', 'contact', 'first_name', 'last_name', 'title', 'email', 'org', 'website', 'linkedin',
    'added_on_linkedin', 'phone', 'aum', 'state', 'segment', 'notes', 'date_outreached', 'outcome', 'next_steps',
    'follow_up_on', 'extra_notes',
    'city', 'org_type', 'channel', 'status', 'response_notes', 'activity_status', 'newsletter', 'mailing_address',
    'reach_out_again', 'no_reach_out_reason', 'plans_served', 'commissions', 'shared_employers',
    'advertises_retirement', 'employee_count', 'onboarding_sent_on', 'funded_on', 'outcome_2',
    'loyalty_thanksgiving', 'loyalty_referral_1', 'loyalty_referral_2', 'loyalty_referral_3',
    'date_source_approved', 'new_contact', 'new_first_name', 'new_email', 'new_org', 'new_website', 'new_linkedin',
    'new_notes', 'campaign', 'event', 'ignore'))
  or (scope = 'event' and field in (
    'event_name', 'event_type', 'format', 'hosted_by_us', 'host_org', 'start_on', 'end_on', 'city', 'state',
    'cost', 'attendees', 'people_met', 'responses', 'meetings', 'won_usd', 'target_segment', 'owner', 'notes', 'ignore'))
  or (scope = 'rfp' and field in (
    'org', 'website', 'state', 'segment', 'contact', 'first_name', 'last_name', 'email', 'phone', 'contact_title',
    'rfp_title', 'name_issuer', 'reference_number', 'mandate_type', 'found_via', 'est_aum', 'released_on', 'questions_due_on',
    'due_on', 'final_submission', 'submitted_on', 'status', 'decision_on', 'approved', 'reviewed_by', 'reviewed_on', 'response', 'won',
    'terms', 'correspondence', 'owner', 'notes', 'ignore')));

-- people sheets: an "Event" column names the event each row came from
insert into public.import_header_aliases (header_key, field, scope) values
  ('event', 'event', 'contact'), ('eventname', 'event', 'contact'), ('conference', 'event', 'contact'),
  ('metat', 'event', 'contact'), ('eventattended', 'event', 'contact'), ('wheremet', 'event', 'contact')
on conflict (header_key, scope) do update set field = excluded.field;

-- the Events sheet
insert into public.import_header_aliases (header_key, field, scope) values
  ('event', 'event_name', 'event'), ('eventname', 'event_name', 'event'), ('name', 'event_name', 'event'),
  ('conference', 'event_name', 'event'), ('title', 'event_name', 'event'), ('eventtitle', 'event_name', 'event'),
  ('type', 'event_type', 'event'), ('eventtype', 'event_type', 'event'), ('kind', 'event_type', 'event'),
  ('category', 'event_type', 'event'),
  ('format', 'format', 'event'), ('inpersonvirtual', 'format', 'event'), ('virtual', 'format', 'event'),
  ('inperson', 'format', 'event'), ('mode', 'format', 'event'), ('delivery', 'format', 'event'),
  ('hostedbyus', 'hosted_by_us', 'event'), ('ourevent', 'hosted_by_us', 'event'), ('ours', 'hosted_by_us', 'event'),
  ('hosted', 'hosted_by_us', 'event'), ('gaardhosted', 'hosted_by_us', 'event'),
  ('host', 'host_org', 'event'), ('hostorg', 'host_org', 'event'), ('organizer', 'host_org', 'event'),
  ('hostedby', 'host_org', 'event'), ('organization', 'host_org', 'event'), ('association', 'host_org', 'event'),
  ('date', 'start_on', 'event'), ('dates', 'start_on', 'event'), ('startdate', 'start_on', 'event'),
  ('start', 'start_on', 'event'), ('eventdate', 'start_on', 'event'), ('when', 'start_on', 'event'),
  ('datesattended', 'start_on', 'event'),
  ('enddate', 'end_on', 'event'), ('end', 'end_on', 'event'), ('through', 'end_on', 'event'),
  ('city', 'city', 'event'), ('location', 'city', 'event'), ('venue', 'city', 'event'), ('where', 'city', 'event'),
  ('state', 'state', 'event'), ('st', 'state', 'event'),
  ('cost', 'cost', 'event'), ('costusd', 'cost', 'event'), ('price', 'cost', 'event'), ('fee', 'cost', 'event'),
  ('registration', 'cost', 'event'), ('registrationfee', 'cost', 'event'), ('spend', 'cost', 'event'),
  ('totalcost', 'cost', 'event'), ('budget', 'cost', 'event'), ('ticket', 'cost', 'event'),
  ('attendees', 'attendees', 'event'), ('attendance', 'attendees', 'event'), ('attendeesest', 'attendees', 'event'),
  ('expectedattendees', 'attendees', 'event'), ('size', 'attendees', 'event'), ('estattendees', 'attendees', 'event'),
  ('peoplemet', 'people_met', 'event'), ('contactsmade', 'people_met', 'event'), ('contactsmet', 'people_met', 'event'),
  ('leads', 'people_met', 'event'), ('connections', 'people_met', 'event'), ('newcontacts', 'people_met', 'event'),
  ('segment', 'target_segment', 'event'), ('targetsegment', 'target_segment', 'event'),
  ('audience', 'target_segment', 'event'), ('clienttype', 'target_segment', 'event'),
  ('owner', 'owner', 'event'), ('attendedby', 'owner', 'event'), ('who', 'owner', 'event'), ('rep', 'owner', 'event'),
  ('whoattended', 'owner', 'event'),
  ('notes', 'notes', 'event'), ('note', 'notes', 'event'), ('comments', 'notes', 'event'),
  ('outcome', 'notes', 'event'), ('takeaways', 'notes', 'event'), ('result', 'notes', 'event'),
  ('worthit', 'notes', 'event'), ('followup', 'notes', 'event'), ('nextsteps', 'notes', 'event'),
  -- Jon's Event ROI Tracker: # of Contacts / # of Responses / # of Meetings / Clients Won ($)
  ('ofcontacts', 'people_met', 'event'), ('contacts', 'people_met', 'event'), ('numberofcontacts', 'people_met', 'event'),
  ('contactcount', 'people_met', 'event'), ('contactsgained', 'people_met', 'event'),
  ('ofresponses', 'responses', 'event'), ('responses', 'responses', 'event'), ('numberofresponses', 'responses', 'event'),
  ('replies', 'responses', 'event'), ('responded', 'responses', 'event'), ('followupresponses', 'responses', 'event'),
  ('ofmeetings', 'meetings', 'event'), ('meetings', 'meetings', 'event'), ('numberofmeetings', 'meetings', 'event'),
  ('meetingsbooked', 'meetings', 'event'), ('calls', 'meetings', 'event'), ('callsbooked', 'meetings', 'event'),
  ('clientswon', 'won_usd', 'event'), ('clientswonusd', 'won_usd', 'event'), ('wonusd', 'won_usd', 'event'),
  ('aumwon', 'won_usd', 'event'), ('newaum', 'won_usd', 'event'), ('businesswon', 'won_usd', 'event'),
  ('revenue', 'won_usd', 'event'), ('clientswonaum', 'won_usd', 'event'), ('won', 'won_usd', 'event'),
  ('eventstate', 'state', 'event'), ('eventcost', 'cost', 'event')
on conflict (header_key, scope) do update set field = excluded.field;

-- the RFP sheet
insert into public.import_header_aliases (header_key, field, scope) values
  ('organization', 'org', 'rfp'), ('org', 'org', 'rfp'), ('company', 'org', 'rfp'), ('client', 'org', 'rfp'),
  ('plansponsor', 'org', 'rfp'), ('issuer', 'org', 'rfp'), ('entity', 'org', 'rfp'), ('name', 'org', 'rfp'),
  ('website', 'website', 'rfp'), ('web', 'website', 'rfp'), ('url', 'website', 'rfp'),
  ('state', 'state', 'rfp'), ('st', 'state', 'rfp'), ('segment', 'segment', 'rfp'), ('clienttype', 'segment', 'rfp'),
  ('contact', 'contact', 'rfp'), ('contactname', 'contact', 'rfp'), ('person', 'contact', 'rfp'),
  ('pointofcontact', 'contact', 'rfp'), ('firstname', 'first_name', 'rfp'), ('lastname', 'last_name', 'rfp'),
  ('email', 'email', 'rfp'), ('contactemail', 'email', 'rfp'), ('phone', 'phone', 'rfp'),
  ('contacttitle', 'contact_title', 'rfp'), ('role', 'contact_title', 'rfp'), ('position', 'contact_title', 'rfp'),
  ('rfp', 'rfp_title', 'rfp'), ('rfpname', 'rfp_title', 'rfp'), ('rfptitle', 'rfp_title', 'rfp'),
  ('title', 'rfp_title', 'rfp'), ('projectname', 'rfp_title', 'rfp'), ('project', 'rfp_title', 'rfp'),
  ('opportunity', 'rfp_title', 'rfp'), ('description', 'rfp_title', 'rfp'), ('mandate', 'rfp_title', 'rfp'),
  ('mandatetype', 'mandate_type', 'rfp'), ('type', 'mandate_type', 'rfp'), ('service', 'mandate_type', 'rfp'),
  ('servicetype', 'mandate_type', 'rfp'), ('scope', 'mandate_type', 'rfp'), ('services', 'mandate_type', 'rfp'),
  ('source', 'found_via', 'rfp'), ('foundvia', 'found_via', 'rfp'), ('howfound', 'found_via', 'rfp'),
  ('via', 'found_via', 'rfp'), ('channel', 'found_via', 'rfp'), ('consultant', 'found_via', 'rfp'),
  ('aum', 'est_aum', 'rfp'), ('estimatedaum', 'est_aum', 'rfp'), ('estaum', 'est_aum', 'rfp'),
  ('mandatesize', 'est_aum', 'rfp'), ('assets', 'est_aum', 'rfp'), ('size', 'est_aum', 'rfp'),
  ('planassets', 'est_aum', 'rfp'), ('estmandateaum', 'est_aum', 'rfp'), ('amount', 'est_aum', 'rfp'),
  ('released', 'released_on', 'rfp'), ('releasedate', 'released_on', 'rfp'), ('releasedon', 'released_on', 'rfp'),
  ('issued', 'released_on', 'rfp'), ('issuedate', 'released_on', 'rfp'), ('datereleased', 'released_on', 'rfp'),
  ('rfpdate', 'released_on', 'rfp'), ('datereceived', 'released_on', 'rfp'), ('received', 'released_on', 'rfp'),
  ('date', 'released_on', 'rfp'),
  ('questionsdue', 'questions_due_on', 'rfp'), ('questionsdueon', 'questions_due_on', 'rfp'),
  ('qadue', 'questions_due_on', 'rfp'), ('questiondeadline', 'questions_due_on', 'rfp'),
  ('questions', 'questions_due_on', 'rfp'),
  ('due', 'due_on', 'rfp'), ('duedate', 'due_on', 'rfp'), ('dueon', 'due_on', 'rfp'), ('deadline', 'due_on', 'rfp'),
  ('proposaldue', 'due_on', 'rfp'), ('submissiondeadline', 'due_on', 'rfp'), ('responsedue', 'due_on', 'rfp'),
  ('submitted', 'submitted_on', 'rfp'), ('submittedon', 'submitted_on', 'rfp'), ('datesubmitted', 'submitted_on', 'rfp'),
  ('submissiondate', 'submitted_on', 'rfp'), ('sent', 'submitted_on', 'rfp'),
  ('status', 'status', 'rfp'), ('stage', 'status', 'rfp'), ('outcome', 'status', 'rfp'), ('result', 'status', 'rfp'),
  ('decision', 'decision_on', 'rfp'), ('decisiondate', 'decision_on', 'rfp'), ('decidedon', 'decision_on', 'rfp'),
  ('awarddate', 'decision_on', 'rfp'), ('award', 'decision_on', 'rfp'), ('expecteddecision', 'decision_on', 'rfp'),
  ('owner', 'owner', 'rfp'), ('lead', 'owner', 'rfp'), ('assignedto', 'owner', 'rfp'),
  ('notes', 'notes', 'rfp'), ('note', 'notes', 'rfp'), ('comments', 'notes', 'rfp'), ('nextsteps', 'notes', 'rfp'),
  -- Jon's RFP Log
  ('rfpnameissuer', 'name_issuer', 'rfp'), ('nameissuer', 'name_issuer', 'rfp'), ('rfpissuer', 'name_issuer', 'rfp'),
  ('rfpnameorissuer', 'name_issuer', 'rfp'), ('rfpandissuer', 'name_issuer', 'rfp'),
  ('rfpreferencenumber', 'reference_number', 'rfp'), ('referencenumber', 'reference_number', 'rfp'), ('reference', 'reference_number', 'rfp'),
  ('refno', 'reference_number', 'rfp'), ('ref', 'reference_number', 'rfp'), ('rfpnumber', 'reference_number', 'rfp'),
  ('rfpno', 'reference_number', 'rfp'), ('solicitationnumber', 'reference_number', 'rfp'), ('bidnumber', 'reference_number', 'rfp'),
  ('finalsubmissiondate', 'final_submission', 'rfp'), ('finalsubmission', 'final_submission', 'rfp'),
  ('submitby', 'due_on', 'rfp'), ('submissiondue', 'due_on', 'rfp'), ('finaldue', 'due_on', 'rfp'),
  ('approvedforsubmission', 'approved', 'rfp'), ('approvedforsubmissionyn', 'approved', 'rfp'),
  ('approved', 'approved', 'rfp'), ('approvedyn', 'approved', 'rfp'), ('approval', 'approved', 'rfp'),
  ('reviewedby', 'reviewed_by', 'rfp'), ('reviewer', 'reviewed_by', 'rfp'),
  ('datereviewed', 'reviewed_on', 'rfp'), ('reviewedon', 'reviewed_on', 'rfp'), ('reviewdate', 'reviewed_on', 'rfp'),
  ('sizeofaum', 'est_aum', 'rfp'), ('aumsize', 'est_aum', 'rfp'), ('totalaum', 'est_aum', 'rfp'),
  ('conditionsorlimitations', 'terms', 'rfp'), ('conditions', 'terms', 'rfp'), ('limitations', 'terms', 'rfp'),
  ('restrictions', 'terms', 'rfp'), ('requirements', 'terms', 'rfp'), ('terms', 'terms', 'rfp'),
  ('response', 'response', 'rfp'), ('issuerresponse', 'response', 'rfp'), ('theirresponse', 'response', 'rfp'),
  ('reply', 'response', 'rfp'), ('feedback', 'response', 'rfp'), ('responsereceived', 'response', 'rfp'),
  ('dateresponded', 'decision_on', 'rfp'), ('respondedon', 'decision_on', 'rfp'), ('responsedate', 'decision_on', 'rfp'),
  ('dateofresponse', 'decision_on', 'rfp'),
  ('correspondence', 'correspondence', 'rfp'), ('emails', 'correspondence', 'rfp'), ('emailthread', 'correspondence', 'rfp'),
  ('communication', 'correspondence', 'rfp'),
  ('won', 'won', 'rfp'), ('wonyn', 'won', 'rfp'), ('wonlost', 'won', 'rfp'), ('awarded', 'won', 'rfp')
on conflict (header_key, scope) do update set field = excluded.field;

-- RFP status wording -> the status column
create table if not exists public.rfp_status_aliases (
  phrase  text primary key,
  status  text not null check (status in ('identified', 'intent_to_bid', 'submitted', 'finalist', 'won', 'lost', 'declined', 'cancelled'))
);
insert into public.rfp_status_aliases (phrase, status) values
  ('identified', 'identified'), ('new', 'identified'), ('open', 'identified'), ('tracking', 'identified'),
  ('watching', 'identified'), ('reviewing', 'identified'), ('received', 'identified'), ('evaluating', 'identified'),
  ('intent to bid', 'intent_to_bid'), ('intent', 'intent_to_bid'), ('bidding', 'intent_to_bid'),
  ('in progress', 'intent_to_bid'), ('working', 'intent_to_bid'), ('drafting', 'intent_to_bid'),
  ('pursuing', 'intent_to_bid'), ('writing', 'intent_to_bid'), ('responding', 'intent_to_bid'),
  ('submitted', 'submitted'), ('sent', 'submitted'), ('proposal submitted', 'submitted'), ('pending', 'submitted'),
  ('under review', 'submitted'), ('awaiting decision', 'submitted'),
  ('finalist', 'finalist'), ('shortlist', 'finalist'), ('shortlisted', 'finalist'), ('presentation', 'finalist'),
  ('finals', 'finalist'), ('interview', 'finalist'), ('final round', 'finalist'),
  ('won', 'won'), ('awarded', 'won'), ('win', 'won'), ('selected', 'won'), ('hired', 'won'), ('success', 'won'),
  ('awarded to us', 'won'), ('yes', 'won'),
  ('lost', 'lost'), ('not selected', 'lost'), ('unsuccessful', 'lost'), ('did not win', 'lost'),
  ('didn''t win', 'lost'), ('no', 'lost'), ('rejected', 'lost'), ('went with another', 'lost'),
  ('selected another', 'lost'), ('chose another', 'lost'), ('went another direction', 'lost'), ('another firm', 'lost'),
  ('another provider', 'lost'), ('another manager', 'lost'), ('not chosen', 'lost'), ('not awarded', 'lost'),
  ('no award', 'lost'), ('declined our proposal', 'lost'), ('decided to stay', 'lost'), ('stay with', 'lost'),
  ('did not advance', 'lost'), ('not moving forward', 'lost'), ('not a fit', 'lost'),
  ('moving forward with us', 'won'), ('chose us', 'won'), ('selected us', 'won'), ('selected gaard', 'won'),
  ('we won', 'won'), ('congratulations', 'won'), ('contract awarded', 'won'),
  ('moved to the next round', 'finalist'), ('next round', 'finalist'), ('finalist presentation', 'finalist'),
  ('oral presentation', 'finalist'), ('site visit', 'finalist'), ('semifinalist', 'finalist'),
  ('awarded to other', 'lost'), ('loss', 'lost'),
  ('declined', 'declined'), ('no bid', 'declined'), ('passed', 'declined'), ('not pursued', 'declined'),
  ('decided not to bid', 'declined'), ('skip', 'declined'), ('pass', 'declined'), ('did not bid', 'declined'),
  ('cancelled', 'cancelled'), ('canceled', 'cancelled'), ('withdrawn', 'cancelled'), ('pulled', 'cancelled'),
  ('on hold', 'cancelled')
on conflict (phrase) do nothing;

create or replace function public.resolve_rfp_status(p text) returns text
language sql stable set search_path = public as $$
  select coalesce(
    (select a.status from rfp_status_aliases a where a.phrase = norm_text(regexp_replace(p, '[\s.!]+$', ''))),
    (select a.status from rfp_status_aliases a                       -- a status word inside a longer reply
      where length(a.phrase) >= 5 and a.phrase not in ('intent', 'pending', 'received')
        and norm_text(p) ~ ('\m' || regexp_replace(a.phrase, '([.^$*+?()\[\]{}|\\])', '\\\1', 'g') || '\M')
      order by length(a.phrase) desc limit 1))
$$;

-- header -> field, now by scope (contact sheets keep the old behaviour)
drop function if exists public.resolve_header(text, jsonb);
create or replace function public.resolve_header(p_header text, p_header_map jsonb default '{}', p_scope text default 'contact') returns text
language sql stable set search_path = public as $$
  select coalesce(
    (select value from jsonb_each_text(coalesce(p_header_map, '{}'))
      where regexp_replace(lower(key), '[^a-z0-9]', '', 'g') = regexp_replace(lower(p_header), '[^a-z0-9]', '', 'g')
      limit 1),
    (select field from import_header_aliases
      where header_key = regexp_replace(lower(p_header), '[^a-z0-9]', '', 'g') and scope = coalesce(p_scope, 'contact')))
$$;

-- parse_loose_date, stricter: the free-form fallback only for strings that look like a date
-- ('Oct 3-5, 2025' used to come back as 2005-10-03)
create or replace function public.parse_loose_date(p text) returns date
language plpgsql stable set search_path = '' as $$
declare
  s text := trim(coalesce(p, ''));
  d date;
begin
  if s = '' then return null; end if;
  if    s ~ '^\d{4}-\d{1,2}-\d{1,2}' then d := to_date(substring(s from '^\d{4}-\d{1,2}-\d{1,2}'), 'YYYY-MM-DD');
  elsif s ~ '^\d{1,2}/\d{1,2}/\d{4}$' then d := to_date(s, 'MM/DD/YYYY');
  elsif s ~ '^\d{1,2}/\d{1,2}/\d{2}$'  then d := to_date(s, 'MM/DD/YY');
  elsif s ~ '^\d{1,2}-\d{1,2}-\d{4}$'  then d := to_date(s, 'MM-DD-YYYY');
  elsif s ~ '^\d{1,2}-\d{1,2}-\d{2}$'  then d := to_date(s, 'MM-DD-YY');
  elsif s ~ '^\d{1,2}/\d{1,2}$'        then return null;                 -- no year: too ambiguous
  elsif s ~ '^[A-Za-z]{3,9}\.?\s+\d{1,2},?\s+\d{4}$'                     -- Oct 3, 2025 / October 3 2025
     or s ~ '^\d{1,2}\s+[A-Za-z]{3,9}\.?,?\s+\d{4}$'                   -- 3 Oct 2025
     or s ~ '^[A-Za-z]{3,9}\.?\s+\d{4}$'                               -- Oct 2025 (the 1st)
     or s ~ '^\d{4}/\d{1,2}/\d{1,2}$' then d := s::date;                 -- only strings that look like one date
  else return null;                                                      -- "Oct 3-5, 2025" is for parse_date_range
  end if;
  if d < date '1900-01-01' then return null; end if;                     -- a typo like 11/20/205 (006)
  return d;
exception when others then
  return null;
end $$;

-- "Oct 3-5, 2025", "10/3/25 - 10/5/25", "10/3-10/5/2025", "October 3, 2025" -> start and end dates
create or replace function public.parse_date_range(p text, out start_on date, out end_on date)
language plpgsql stable set search_path = public as $$
declare
  s     text := trim(coalesce(p, ''));
  parts text[];
  m     text[];
  yr    text;
begin
  if s = '' then return; end if;
  -- "Oct 3-5, 2025" / "October 3 - 5, 2025"
  m := regexp_match(s, '^([A-Za-z]{3,9})\.?\s+(\d{1,2})\s*(?:-|–|to)\s*(\d{1,2}),?\s+(\d{4})$');
  if m is not null then
    start_on := to_date(m[1] || ' ' || m[2] || ' ' || m[4], 'Mon DD YYYY');
    end_on   := to_date(m[1] || ' ' || m[3] || ' ' || m[4], 'Mon DD YYYY');
    return;
  end if;
  -- "3-5 Oct 2025"
  m := regexp_match(s, '^(\d{1,2})\s*(?:-|–|to)\s*(\d{1,2})\s+([A-Za-z]{3,9})\.?,?\s+(\d{4})$');
  if m is not null then
    start_on := to_date(m[3] || ' ' || m[1] || ' ' || m[4], 'Mon DD YYYY');
    end_on   := to_date(m[3] || ' ' || m[2] || ' ' || m[4], 'Mon DD YYYY');
    return;
  end if;
  -- two dates around a dash / "to" / "through"
  parts := regexp_split_to_array(s, '\s*(?:\s-\s|–|—|\bto\b|\bthrough\b|\bthru\b)\s*');
  if array_length(parts, 1) <> 2 and s ~ '^\d{1,2}/\d{1,2}(/\d{2,4})?-\d{1,2}/\d{1,2}/\d{2,4}$' then
    parts := regexp_split_to_array(s, '-');
  end if;
  if array_length(parts, 1) = 2 then
    start_on := parse_loose_date(parts[1]);
    end_on   := parse_loose_date(parts[2]);
    if start_on is not null and end_on is not null then return; end if;
    -- "10/3-10/5/2025": the year is only on the second half
    yr := substring(parts[2] from '(\d{4}|\d{2})$');
    if start_on is null and yr is not null and trim(parts[1]) ~ '^\d{1,2}/\d{1,2}$' then
      start_on := parse_loose_date(trim(parts[1]) || '/' || yr);
      if start_on is not null and end_on is not null then return; end if;
    end if;
    start_on := null; end_on := null;
  end if;
  -- a single date
  start_on := parse_loose_date(s);
  end_on   := start_on;
exception when others then
  start_on := null; end_on := null;
end $$;

create or replace function public.resolve_event_type(p text) returns text
language sql immutable set search_path = '' as $$
  select case
    when lower(coalesce(p, '')) ~ 'webinar|zoom|online session|virtual session' then 'webinar'
    when lower(coalesce(p, '')) ~ 'workshop|training|class|seminar|bootcamp' then 'workshop'
    when lower(coalesce(p, '')) ~ 'network|mixer|happy hour|luncheon|lunch|breakfast|dinner|gala|reception|roundtable|meetup|social' then 'networking'
    when lower(coalesce(p, '')) ~ 'conference|summit|convention|expo|forum|symposium|annual meeting|congress' then 'conference'
    when trim(coalesce(p, '')) = '' then 'other'
    else 'other' end
$$;

create or replace function public.resolve_event_format(p_format text, p_type text, p_city text) returns text
language sql immutable set search_path = '' as $$
  select case
    when lower(coalesce(p_format, '')) ~ 'virtual|zoom|online|remote|webinar|teams|web' then 'virtual'
    when lower(coalesce(p_format, '')) ~ 'person|onsite|on-site|live|hybrid' then 'in_person'
    when lower(coalesce(p_type, '')) ~ 'webinar|virtual|online' then 'virtual'
    when lower(coalesce(p_city, '')) ~ '^(virtual|zoom|online|remote)' then 'virtual'
    else 'in_person' end
$$;

create or replace function public.resolve_team_member(p text) returns bigint
language sql stable set search_path = public as $$
  select id from team_members
   where p is not null and trim(p) <> ''
     and (lower(full_name) = lower(trim(p))
          or lower(email) = lower(trim(p))
          or lower(split_part(full_name, ' ', 1)) = lower(trim(p))
          or lower(full_name) like lower(trim(p)) || '%')
   order by is_active desc, id limit 1
$$;


-- "Investment Advisory Services RFP / Utah Arts Foundation" -> title + issuer. Either order: the half that
-- sounds like an RFP is the title. No separator: the whole cell is the issuer (the title is built from it).
create or replace function public.split_rfp_name_issuer(p text, out rfp_title text, out issuer text)
language plpgsql immutable set search_path = '' as $$
declare
  s     text := trim(coalesce(p, ''));
  parts text[];
  a     text; b text;
  a_rfp boolean; b_rfp boolean;
begin
  if s = '' then return; end if;
  parts := regexp_split_to_array(s, '\s*(?:/|\||\s[-–—]\s|:\s)\s*');
  if array_length(parts, 1) >= 2 and trim(parts[1]) <> '' and trim(parts[2]) <> '' then
    a := trim(parts[1]); b := trim(array_to_string(parts[2:], ' / '));
    a_rfp := lower(a) ~ '\m(rfp|rfq|rfi|proposal|services?|advisor|advisory|management|ocio|investment|consulting|search|mandate|401\(?k\)?|retirement|endowment)\M';
    b_rfp := lower(b) ~ '\m(rfp|rfq|rfi|proposal|services?|advisor|advisory|management|ocio|investment|consulting|search|mandate|401\(?k\)?|retirement|endowment)\M';
    if b_rfp and not a_rfp then rfp_title := b; issuer := a;
    else rfp_title := a; issuer := b; end if;            -- the header says "Name / Issuer", so that is the default
    return;
  end if;
  issuer := s;                                             -- one name only: the issuer
end $$;

-- ---------------------------------------------------------------------
-- 3. The Events sheet
-- ---------------------------------------------------------------------
--   select import_events_table('upload_events');
-- One row per event. Same name + same start date = the same event (blanks filled, nothing overwritten).
create or replace function public.import_events_table(p_table regclass, p_label text default 'Events sheet',
                                                      p_header_map jsonb default '{}') returns jsonb
language plpgsql set search_path = public as $$
declare
  v_row     jsonb;
  v_key     text;
  v_val     text;
  v_field   text;
  v_f       jsonb;
  v_extra   text;
  v_n       int := 0;
  v_order   text := '';
  v_used    jsonb := '{}';
  v_kept    text[] := '{}';
  v_created int := 0;
  v_updated int := 0;
  v_skipped jsonb := '[]';
  v_name    text;
  v_dates   record;
  v_id      bigint;
  v_type    text;
  v_format  text;
  v_city    text;
  v_state   char(2);
begin
  if exists (select 1 from pg_attribute where attrelid = p_table and attname = 'id' and not attisdropped) then
    v_order := ' order by t.id';
  end if;
  for v_row in execute format('select to_jsonb(t) from %s t%s', p_table, v_order) loop
    v_n := v_n + 1;
    v_f := '{}'; v_extra := null;
    for v_key, v_val in select key, value from jsonb_each_text(v_row) loop
      continue when v_val is null or btrim(v_val) = '';
      v_field := resolve_header(v_key, p_header_map, 'event');
      if v_field is null then
        continue when lower(v_key) in ('id', 'created_at');
        v_extra := concat_ws(E'\n', v_extra, v_key || ': ' || v_val);
        if not (v_key = any (v_kept)) then v_kept := v_kept || v_key; end if;
      elsif v_field = 'ignore' then
        continue;
      elsif v_field = 'notes' then                                        -- "Worth it?: Yes", plain notes unlabeled
        v_f := v_f || jsonb_build_object(v_field, concat_ws(E'\n', v_f ->> v_field,
                 case when regexp_replace(lower(v_key), '[^a-z0-9]', '', 'g') in ('notes', 'note', 'comments', 'comment')
                      then v_val else v_key || ': ' || v_val end));
        v_used := v_used || jsonb_build_object(v_key, v_field);
      elsif (v_f ->> v_field) is null then
        v_f := v_f || jsonb_build_object(v_field, v_val);
        v_used := v_used || jsonb_build_object(v_key, v_field);
      elsif (v_f ->> v_field) <> v_val then
        v_extra := concat_ws(E'\n', v_extra, v_key || ': ' || v_val);
      end if;
    end loop;
    continue when v_f = '{}';

    v_name := nullif(trim(v_f ->> 'event_name'), '');
    if v_name is null then
      v_skipped := v_skipped || jsonb_build_object('row', v_n + 1, 'reason', 'no event name');
      continue;
    end if;
    select * into v_dates from parse_date_range(v_f ->> 'start_on');
    if v_dates.start_on is null then
      v_skipped := v_skipped || jsonb_build_object('row', v_n + 1, 'reason', 'no readable date: "' || coalesce(v_f ->> 'start_on', '') || '"');
      continue;
    end if;
    if (v_f ->> 'end_on') is not null then
      v_dates.end_on := coalesce(parse_loose_date(v_f ->> 'end_on'), v_dates.end_on);
    end if;
    v_city   := nullif(trim(v_f ->> 'city'), '');
    v_state  := coalesce(resolve_state(v_f ->> 'state'), resolve_state(split_part(coalesce(v_city, ''), ',', 2)));
    if v_city is not null and position(',' in v_city) > 0 then v_city := trim(split_part(v_city, ',', 1)); end if;
    v_type   := resolve_event_type(coalesce(v_f ->> 'event_type', '') || ' ' || v_name);
    v_format := resolve_event_format(v_f ->> 'format', coalesce(v_f ->> 'event_type', '') || ' ' || v_name, v_city);

    select id into v_id from events
     where norm_text(name) = norm_text(v_name) and start_on = v_dates.start_on limit 1;
    if v_id is null then
      insert into events (name, event_type, format, hosted_by_us, host_org, start_on, end_on, city, state, cost_usd,
                          attendees_est, people_met_reported, responses_reported, meetings_reported, clients_won_usd,
                          target_segment_code, owner_id, notes)
      values (v_name, v_type, v_format, coalesce(parse_yes_no(v_f ->> 'hosted_by_us'), false),
              nullif(trim(v_f ->> 'host_org'), ''), v_dates.start_on,
              case when v_dates.end_on <> v_dates.start_on then v_dates.end_on end,
              v_city, v_state, coalesce(parse_amount(v_f ->> 'cost'), 0),
              nullif(regexp_replace(coalesce(v_f ->> 'attendees', ''), '[^0-9]', '', 'g'), '')::int,
              nullif(regexp_replace(coalesce(v_f ->> 'people_met', ''), '[^0-9]', '', 'g'), '')::int,
              nullif(regexp_replace(coalesce(v_f ->> 'responses', ''), '[^0-9]', '', 'g'), '')::int,
              nullif(regexp_replace(coalesce(v_f ->> 'meetings', ''), '[^0-9]', '', 'g'), '')::int,
              parse_amount(v_f ->> 'won_usd'),
              resolve_segment(v_f ->> 'target_segment', null), resolve_team_member(v_f ->> 'owner'),
              nullif(concat_ws(E'\n', nullif(trim(v_f ->> 'notes'), ''), v_extra), ''))
      returning id into v_id;
      v_created := v_created + 1;
    else
      update events
         set event_type          = case when event_type = 'other' then v_type else event_type end,
             host_org            = coalesce(host_org, nullif(trim(v_f ->> 'host_org'), '')),
             end_on              = coalesce(end_on, case when v_dates.end_on <> v_dates.start_on then v_dates.end_on end),
             city                = coalesce(city, v_city),
             state               = coalesce(state, v_state),
             cost_usd            = case when cost_usd = 0 then coalesce(parse_amount(v_f ->> 'cost'), 0) else cost_usd end,
             attendees_est       = coalesce(attendees_est, nullif(regexp_replace(coalesce(v_f ->> 'attendees', ''), '[^0-9]', '', 'g'), '')::int),
             people_met_reported = coalesce(people_met_reported, nullif(regexp_replace(coalesce(v_f ->> 'people_met', ''), '[^0-9]', '', 'g'), '')::int),
             responses_reported  = coalesce(responses_reported, nullif(regexp_replace(coalesce(v_f ->> 'responses', ''), '[^0-9]', '', 'g'), '')::int),
             meetings_reported   = coalesce(meetings_reported, nullif(regexp_replace(coalesce(v_f ->> 'meetings', ''), '[^0-9]', '', 'g'), '')::int),
             clients_won_usd     = coalesce(clients_won_usd, parse_amount(v_f ->> 'won_usd')),
             target_segment_code = coalesce(target_segment_code, resolve_segment(v_f ->> 'target_segment', null)),
             owner_id            = coalesce(owner_id, resolve_team_member(v_f ->> 'owner')),
             notes               = case when nullif(concat_ws(E'\n', nullif(trim(v_f ->> 'notes'), ''), v_extra), '') is null
                                          or position(concat_ws(E'\n', nullif(trim(v_f ->> 'notes'), ''), v_extra) in coalesce(notes, '')) > 0 then notes
                                        else concat_ws(E'\n', notes, concat_ws(E'\n', nullif(trim(v_f ->> 'notes'), ''), v_extra)) end
       where id = v_id;
      v_updated := v_updated + 1;
    end if;
  end loop;
  return jsonb_build_object('sheet', p_label, 'rows', v_n, 'events_created', v_created, 'events_already_there', v_updated,
                            'skipped', v_skipped, 'columns_used', v_used, 'columns_kept_in_notes', to_jsonb(v_kept));
end $$;


-- ---------------------------------------------------------------------
-- 4. The RFP sheet
-- ---------------------------------------------------------------------
--   select import_rfps_table('upload_rfps');
-- One row per RFP. The organization is matched (website, then name) or created; a contact is
-- attached when the sheet names one; the same organization + same title = the same RFP.
-- Submitted / finalist / won / lost RFPs with a contact also get their RFP touch, so the pipeline
-- and the funnel count them (won opens an onboarding opportunity unless one already exists).
create or replace function public.import_rfps_table(p_table regclass, p_label text default 'RFP sheet',
                                                    p_segment text default 'Nonprofit',
                                                    p_header_map jsonb default '{}') returns jsonb
language plpgsql set search_path = public, extensions as $$
declare
  v_row      jsonb;
  v_key      text;
  v_val      text;
  v_field    text;
  v_f        jsonb;
  v_extra    text;
  v_n        int := 0;
  v_order    text := '';
  v_used     jsonb := '{}';
  v_kept     text[] := '{}';
  v_created  int := 0;
  v_updated  int := 0;
  v_orgs_new int := 0;
  v_cts_new  int := 0;
  v_touches  int := 0;
  v_skipped  jsonb := '[]';
  v_seg      segments;
  v_org_text text;
  v_org_key  text;
  v_domain   text;
  v_org_id   bigint;
  v_state    char(2);
  v_email    text;
  v_first    text;
  v_last     text;
  v_cid      bigint;
  v_title    text;
  v_status   text;
  v_rfp_id   bigint;
  v_released date;
  v_due      date;
  v_submit   date;
  v_decide   date;
  v_outcome  text;
  v_on       date;
  v_ni       record;
  v_ref      text;
  v_won      boolean;
  v_approved boolean;
  v_resp     text;
  v_resp_st  text;
  v_rev_by   text;
  v_rev_on   date;
  v_notes    text;
  v_final    date;
  v_resp_yn  boolean;
  v_result   text;
  v_dnotes   text;
  v_to_check jsonb := '[]';
begin
  select * into v_seg from segments where code = resolve_segment(p_segment, 'ORG_NONPROFIT');
  if exists (select 1 from pg_attribute where attrelid = p_table and attname = 'id' and not attisdropped) then
    v_order := ' order by t.id';
  end if;
  perform set_config('app.history_load', 'on', true);     -- RFP touches for old statuses: facts, no reminders

  for v_row in execute format('select to_jsonb(t) from %s t%s', p_table, v_order) loop
    v_n := v_n + 1;
    v_f := '{}'; v_extra := null; v_org_id := null; v_cid := null; v_rfp_id := null;
    for v_key, v_val in select key, value from jsonb_each_text(v_row) loop
      continue when v_val is null or btrim(v_val) = '';
      v_field := resolve_header(v_key, p_header_map, 'rfp');
      if v_field is null then
        continue when lower(v_key) in ('id', 'created_at');
        v_extra := concat_ws(E'\n', v_extra, v_key || ': ' || v_val);
        if not (v_key = any (v_kept)) then v_kept := v_kept || v_key; end if;
      elsif v_field = 'ignore' then
        continue;
      elsif v_field = 'notes' then                                        -- "Worth it?: Yes", plain notes unlabeled
        v_f := v_f || jsonb_build_object(v_field, concat_ws(E'\n', v_f ->> v_field,
                 case when regexp_replace(lower(v_key), '[^a-z0-9]', '', 'g') in ('notes', 'note', 'comments', 'comment')
                      then v_val else v_key || ': ' || v_val end));
        v_used := v_used || jsonb_build_object(v_key, v_field);
      elsif (v_f ->> v_field) is null then
        v_f := v_f || jsonb_build_object(v_field, v_val);
        v_used := v_used || jsonb_build_object(v_key, v_field);
      elsif (v_f ->> v_field) <> v_val then
        v_extra := concat_ws(E'\n', v_extra, v_key || ': ' || v_val);
      end if;
    end loop;
    continue when v_f = '{}';

    begin
      -- "RFP Name / Issuer" in one cell (Jon's log) -> title + organization
      select * into v_ni from split_rfp_name_issuer(v_f ->> 'name_issuer');
      v_org_text := coalesce(nullif(trim(v_f ->> 'org'), ''), v_ni.issuer);
      if v_org_text is null then
        v_skipped := v_skipped || jsonb_build_object('row', v_n + 1, 'reason', 'no organization');
        continue;
      end if;
      v_org_key := norm_org_name(v_org_text);
      v_domain  := norm_domain(v_f ->> 'website');
      v_state   := resolve_state(v_f ->> 'state');
      v_email   := norm_email(v_f ->> 'email');
      if v_domain is null and v_email is not null
         and not exists (select 1 from freemail_domains d where d.domain = split_part(v_email, '@', 2)) then
        v_domain := split_part(v_email, '@', 2);
      end if;

      -- the organization: website, then exact name, then a look-alike name, else new
      if v_domain is not null then
        select id into v_org_id from organizations where domain = v_domain order by id limit 1;
      end if;
      if v_org_id is null then
        select id into v_org_id from organizations where name_key = v_org_key
         order by (state is not distinct from v_state) desc, id limit 1;
      end if;
      if v_org_id is null then
        select id into v_org_id from organizations
         where name_key % v_org_key and org_names_look_alike(name, v_org_text)
         order by similarity(name_key, v_org_key) desc limit 1;
      end if;
      if v_org_id is null then
        insert into organizations (name, segment_code, website, state, source_detail, legacy_ref)
        values (v_org_text, coalesce(resolve_segment(v_f ->> 'segment', null), v_seg.code),
                nullif(trim(v_f ->> 'website'), ''), v_state, 'RFP', p_label || ' / row ' || (v_n + 1))
        returning id into v_org_id;
        v_orgs_new := v_orgs_new + 1;
      end if;

      -- the contact, when the sheet names one
      v_first := coalesce(nullif(trim(v_f ->> 'first_name'), ''), nullif(split_part(trim(coalesce(v_f ->> 'contact', '')), ' ', 1), ''));
      v_last  := coalesce(nullif(trim(v_f ->> 'last_name'), ''),
                          nullif(trim(regexp_replace(trim(coalesce(v_f ->> 'contact', '')), '^\S+\s*', '')), ''));
      if v_email is not null then
        select id into v_cid from contacts where email_key = v_email;
      end if;
      if v_cid is null and v_first is not null then
        select id into v_cid from contacts
         where organization_id = v_org_id and person_names_look_alike(first_name, last_name, v_first, v_last)
         order by (name_key = norm_text(v_first || ' ' || coalesce(v_last, ''))) desc, id limit 1;
      end if;
      if v_cid is null and (v_first is not null or v_email is not null) then
        insert into contacts (organization_id, first_name, last_name, title, email, phone, source_channel_code,
                              source_detail, sourced_on, legacy_ref)
        values (v_org_id, v_first, v_last, nullif(trim(v_f ->> 'contact_title'), ''), v_email,
                nullif(trim(v_f ->> 'phone'), ''), 'RFP', 'RFP contact',
                coalesce(parse_loose_date(v_f ->> 'released_on'), local_today()), p_label || ' / row ' || (v_n + 1))
        returning id into v_cid;
        v_cts_new := v_cts_new + 1;
      end if;

      -- the RFP
      v_released := parse_loose_date(v_f ->> 'released_on');
      v_due      := parse_loose_date(v_f ->> 'due_on');
      v_submit   := parse_loose_date(v_f ->> 'submitted_on');
      v_decide   := parse_loose_date(v_f ->> 'decision_on');
      v_title    := coalesce(nullif(trim(v_f ->> 'rfp_title'), ''), v_ni.rfp_title,
                             'RFP: ' || v_org_text || coalesce(' ' || to_char(coalesce(v_released, v_due), 'YYYY'), ''));
      v_ref      := nullif(trim(v_f ->> 'reference_number'), '');
      v_won      := parse_yes_no(v_f ->> 'won');
      v_approved := parse_yes_no(v_f ->> 'approved');
      v_resp     := nullif(trim(v_f ->> 'response'), '');
      v_resp_yn  := parse_yes_no(v_resp);                   -- "Response" as Y/N: did they answer at all
      if v_resp_yn is not null then v_resp := null; end if;
      v_resp_st  := resolve_rfp_status(v_resp);
      v_rev_by   := nullif(trim(v_f ->> 'reviewed_by'), '');
      v_rev_on   := parse_loose_date(v_f ->> 'reviewed_on');
      -- "Final Submission Date": the day it went out when it has passed, the deadline when it has not
      v_final    := parse_loose_date(v_f ->> 'final_submission');
      if v_final is not null then
        if v_final <= local_today() and v_approved is not false then v_submit := coalesce(v_submit, v_final); end if;
        v_due := coalesce(v_due, v_final);
      end if;
      if v_submit is null and v_approved and v_due is not null and v_due <= local_today() then
        v_submit := v_due;                                   -- approved and the submission date has passed: it went out
      end if;

      -- the status: a Status word when there is one; otherwise WON / Response / Approved / the dates (Jon's log)
      if nullif(trim(v_f ->> 'status'), '') is not null then
        v_status := resolve_rfp_status(v_f ->> 'status');
        if v_status is null then
          v_skipped := v_skipped || jsonb_build_object('row', v_n + 1, 'reason', 'status not understood: "' || (v_f ->> 'status') || '"');
          continue;
        end if;
      else
        v_status := case
          when v_won then 'won'
          when v_won is false and (v_decide is not null or v_resp is not null or v_resp_yn) then 'lost'
          when v_resp_st is not null then v_resp_st
          when v_resp is not null or v_decide is not null or v_resp_yn then 'submitted'   -- they answered something: it was submitted
          when v_approved is false and v_rev_on is not null then 'declined'  -- reviewed and not approved to send
          when v_submit is not null then 'submitted'
          when v_due is not null and v_due < local_today() and v_approved is not false then 'submitted'
          when v_approved or (v_approved is false) then 'intent_to_bid'
          else 'identified' end;
        if v_resp is not null and v_resp_st is null and v_won is null then   -- a reply nobody could read, no Y/N either
          v_to_check := v_to_check || jsonb_build_object('row', v_n + 1, 'response', left(v_resp, 80), 'status', v_status);
        end if;
      end if;

      v_result := case
        when v_status = 'won' then 'awarded'
        when v_status <> 'lost' then null
        when lower(coalesce(v_resp, '')) ~ 'disqualif' then 'disqualified'
        when lower(coalesce(v_resp, '')) ~ 'not shortlisted|not short-listed|did not advance|not selected for the final|first round' then 'not_shortlisted'
        when lower(coalesce(v_resp, '')) ~ 'finalist|shortlist|final round|presentation' then 'finalist_not_selected'
        else 'not_awarded' end;
      v_dnotes := nullif(concat_ws(E'\n',
                    case when v_resp is not null then 'Response: ' || v_resp end,
                    nullif(trim(v_f ->> 'correspondence'), '')), '');
      v_notes  := nullif(concat_ws(E'\n', nullif(trim(v_f ->> 'notes'), ''), v_extra), '');

      -- the same RFP twice: by reference number, else by organization + title
      if v_ref is not null then
        select id into v_rfp_id from rfps where organization_id = v_org_id and lower(reference_number) = lower(v_ref) limit 1;
      end if;
      if v_rfp_id is null then
        select id into v_rfp_id from rfps where organization_id = v_org_id and norm_text(title) = norm_text(v_title) limit 1;
      end if;
      if v_rfp_id is null then
        insert into rfps (organization_id, contact_id, title, reference_number, mandate_type, found_via, est_mandate_aum, released_on,
                          questions_due_on, due_on, submitted_on, status, decision_on, approved_for_submission, reviewed_by,
                          reviewed_on, terms, decision_result, decision_notes, owner_id, notes)
        values (v_org_id, v_cid, v_title, v_ref, nullif(trim(v_f ->> 'mandate_type'), ''), nullif(trim(v_f ->> 'found_via'), ''),
                parse_amount(v_f ->> 'est_aum'), v_released, parse_loose_date(v_f ->> 'questions_due_on'), v_due, v_submit,
                v_status, v_decide, v_approved, v_rev_by, v_rev_on, nullif(trim(v_f ->> 'terms'), ''), v_result, v_dnotes,
                coalesce(resolve_team_member(v_f ->> 'owner'), resolve_team_member(v_rev_by)), v_notes)
        returning id into v_rfp_id;
        v_created := v_created + 1;
      else
        update rfps
           set contact_id       = coalesce(contact_id, v_cid),
               reference_number = coalesce(reference_number, v_ref),
               mandate_type     = coalesce(mandate_type, nullif(trim(v_f ->> 'mandate_type'), '')),
               found_via        = coalesce(found_via, nullif(trim(v_f ->> 'found_via'), '')),
               est_mandate_aum  = coalesce(est_mandate_aum, parse_amount(v_f ->> 'est_aum')),
               released_on      = coalesce(released_on, v_released),
               questions_due_on = coalesce(questions_due_on, parse_loose_date(v_f ->> 'questions_due_on')),
               due_on           = coalesce(due_on, v_due),
               submitted_on     = coalesce(submitted_on, v_submit),
               decision_on      = coalesce(decision_on, v_decide),
               status           = case when (v_f ->> 'status') is not null or v_won is not null or v_resp is not null or v_resp_yn then v_status else status end,
               approved_for_submission = coalesce(approved_for_submission, v_approved),
               reviewed_by      = coalesce(reviewed_by, v_rev_by),
               reviewed_on      = coalesce(reviewed_on, v_rev_on),
               terms            = coalesce(terms, nullif(trim(v_f ->> 'terms'), '')),
               decision_result  = coalesce(decision_result, v_result),
               decision_notes   = case when v_dnotes is null or position(v_dnotes in coalesce(decision_notes, '')) > 0 then decision_notes
                                       else concat_ws(E'\n', decision_notes, v_dnotes) end,
               owner_id         = coalesce(owner_id, resolve_team_member(v_f ->> 'owner'), resolve_team_member(v_rev_by)),
               notes            = case when v_notes is null or position(v_notes in coalesce(notes, '')) > 0 then notes
                                       else concat_ws(E'\n', notes, v_notes) end
         where id = v_rfp_id;
        v_updated := v_updated + 1;
      end if;

      -- the RFP touch for a status that already happened (the trigger only logs status *changes*)
      v_outcome := case v_status when 'submitted' then 'RFP_SUBMITTED' when 'finalist' then 'RFP_FINALIST'
                                 when 'won' then 'RFP_WON' when 'lost' then 'RFP_LOST' end;
      if v_cid is not null and v_outcome is not null
         and not exists (select 1 from touchpoints t where t.rfp_id = v_rfp_id and t.outcome_code = v_outcome) then
        v_on := case when v_status = 'submitted' then coalesce(v_submit, v_due, v_released, local_today())
                     else coalesce(v_decide, v_submit, v_due, local_today()) end;
        insert into touchpoints (contact_id, organization_id, touch_type, direction, touched_at, rfp_id, outcome_code, notes)
        values (v_cid, v_org_id, 'rfp', 'outbound', (v_on + time '12:00') at time zone 'America/Denver', v_rfp_id, v_outcome,
                'From ' || p_label || ': ' || v_title);
        v_touches := v_touches + 1;
      end if;
    exception when others then
      v_skipped := v_skipped || jsonb_build_object('row', v_n + 1, 'reason', sqlerrm);
    end;
  end loop;
  perform set_config('app.history_load', 'off', true);
  return jsonb_build_object('sheet', p_label, 'rows', v_n, 'rfps_created', v_created, 'rfps_already_there', v_updated,
                            'organizations_created', v_orgs_new, 'contacts_created', v_cts_new, 'rfp_touches_logged', v_touches,
                            'skipped', v_skipped, 'responses_to_check', v_to_check,
                            'columns_used', v_used, 'columns_kept_in_notes', to_jsonb(v_kept));
end $$;


-- ---------------------------------------------------------------------
-- 5. People sheets: an "Event" column ties each row to its event by name
-- ---------------------------------------------------------------------
create or replace function public.process_import_batch(p_batch_id bigint, p_run_automation boolean default true)
returns jsonb
language plpgsql set search_path = public, extensions as $$
declare
  b              import_batches;
  r              import_rows;
  v_seg          segments;
  v_email        text;
  v_domain       text;
  v_li           text;
  v_first        text;
  v_last         text;
  v_name_key     text;
  v_org_text     text;
  v_org_key      text;
  v_web_domain   text;
  v_state        char(2);
  v_sourced      date;
  v_contact_id   bigint;
  v_org_id       bigint;
  v_other_id     bigint;
  v_matched      text;
  v_result       text;
  v_detail       text;
  v_cand_org     bigint;
  v_cand_contact bigint;
  v_force_new    boolean;
  v_touch_on     date;
  v_touch_id     bigint;
  v_out          record;
  v_suggest      text;
  v_outcome      text;
  v_outcome_text text;
  v_status       text;
  v_flags        text;
  v_summary      jsonb;
  v_x            jsonb;
  v_channel      text;
  v_campaign_id  bigint;
  v_follow_up    date;
  v_onb_on       date;
  v_funded_on    date;
  v_aum          numeric;
  v_opp          opportunities;
  v_due          date;
  v_k            text;
  v_v            text;
  v_notes_add    text;
  v_event_id     bigint;
begin
  select * into b from import_batches where id = p_batch_id for update;
  if not found then raise exception 'Import batch % not found', p_batch_id; end if;
  if not p_run_automation then
    perform set_config('app.history_load', 'on', true);   -- facts yes, reminders no (see history_load())
  end if;

  for r in
    select * from import_rows
     where batch_id = p_batch_id
       and (processed_at is null or (result = 'needs_review' and review_decision is not null))
     order by row_number, id
  loop
    begin   -- each row in its own sub-transaction: one bad row never stops the batch
      v_contact_id := null; v_org_id := null; v_matched := null; v_result := null; v_detail := null;
      v_cand_org := null; v_cand_contact := null; v_touch_id := null; v_flags := ''; v_campaign_id := null;
      v_x := coalesce(r.extra, '{}');

      if r.review_decision = 'skip' then
        update import_rows set result = 'skipped', result_detail = 'Skipped after review', processed_at = now()
         where id = r.id;
        continue;
      end if;
      v_force_new := coalesce(r.review_decision = 'create_new', false);

      select * into v_seg from segments where code = resolve_segment(r.segment, b.default_segment_code);
      if v_seg.code is null then
        raise exception 'No segment: fill the Segment column or set default_segment_code on the batch';
      end if;

      v_email      := norm_email(r.email);
      v_domain     := nullif(split_part(v_email, '@', 2), '');
      v_li         := norm_linkedin(r.linkedin);
      v_first      := coalesce(nullif(trim(r.first_name), ''), nullif(split_part(trim(coalesce(r.contact, '')), ' ', 1), ''));
      v_last       := coalesce(nullif(trim(r.last_name), ''),
                               nullif(trim(regexp_replace(trim(coalesce(r.contact, '')), '^\S+\s*', '')), ''));
      v_org_text   := nullif(trim(r.org), '');
      -- Customer Loyalty style rows: an individual whose name sits in the "Name" (organization) column
      if v_seg.party_type = 'individual' and v_first is null and v_org_text is not null then
        v_first := nullif(split_part(v_org_text, ' ', 1), '');
        v_last  := nullif(trim(regexp_replace(v_org_text, '^\S+\s*', '')), '');
        v_org_text := null;
      end if;
      v_name_key   := norm_text(coalesce(v_first, '') || ' ' || coalesce(v_last, ''));
      v_org_key    := norm_org_name(v_org_text);
      v_web_domain := norm_domain(r.website);
      v_state      := resolve_state(r.state);
      v_touch_on   := parse_loose_date(r.date_outreached);
      if v_touch_on is null and b.default_touch_type = 'event' then
        v_touch_on := coalesce(parse_loose_date(r.date_added), (select e.start_on from events e where e.id = coalesce(
                        (select e2.id from events e2 where norm_text(e2.name) = norm_text(v_x ->> 'event') order by e2.start_on desc limit 1), b.event_id)));
      end if;
      v_sourced    := coalesce(parse_loose_date(r.date_added), v_touch_on, local_date(b.created_at));
      v_channel    := resolve_channel(v_x ->> 'channel', b.default_channel_code);
      -- "Event" column: the event this row came from, by name (falls back to the batch's event)
      v_event_id   := coalesce((select e.id from events e
                                 where norm_text(e.name) = norm_text(v_x ->> 'event')
                                 order by e.start_on desc limit 1), b.event_id);
      if v_event_id is not null then v_channel := coalesce(resolve_channel(v_x ->> 'channel', null), 'EVENT'); end if;
      if v_email is null and v_li is null and v_name_key is null then
        update import_rows set result = 'skipped', result_detail = 'No name, email or LinkedIn on this row', processed_at = now()
         where id = r.id;
        continue;
      end if;

      -- 1) already in the CRM? (email, then LinkedIn, then a reviewer's decision)
      if v_email is not null then
        select id into v_contact_id from contacts where email_key = v_email;
        if found then v_matched := 'email'; end if;
      end if;
      if v_contact_id is null and v_li is not null then
        select id into v_contact_id from contacts where linkedin_key = v_li;
        if found then v_matched := 'LinkedIn'; end if;
      end if;
      if v_contact_id is null and r.review_decision = 'use_candidate' and r.review_candidate_contact_id is not null then
        v_contact_id := r.review_candidate_contact_id;
        v_matched := 'reviewer: same person';
        update contacts set notes = concat_ws(E'\n', notes, 'Also uses: ' || coalesce(v_email, trim(r.email)))
         where id = v_contact_id and v_email is not null;
      end if;
      -- a tab with no email column (Customer Loyalty): the exact same name at the same organization is the same person
      if v_contact_id is null and b.match_by_name and v_name_key is not null then
        select c.id into v_contact_id
          from contacts c
          left join organizations o on o.id = c.organization_id
         where c.name_key = v_name_key
           and (   (v_org_key is not null and (o.name_key = v_org_key or (v_web_domain is not null and o.domain = v_web_domain)))
                or (v_org_key is null and v_seg.party_type = 'individual' and c.organization_id is null))
         order by c.id limit 1;
        if found then v_matched := 'name'; end if;
      end if;

      -- the email points at one person and the LinkedIn at another
      if v_contact_id is not null and v_li is not null then
        select id into v_other_id from contacts where linkedin_key = v_li and id <> v_contact_id;
        if found then
          update import_rows
             set result = 'needs_review', matched_on = 'email and LinkedIn disagree',
                 review_candidate_contact_id = v_other_id, contact_id = v_contact_id,
                 result_detail = format('Email matches contact #%s but LinkedIn matches contact #%s. Possibly the same person entered twice.',
                                        v_contact_id, v_other_id),
                 processed_at = now()
           where id = r.id;
          continue;
        end if;
      end if;

      if v_contact_id is not null then
        -- fill blanks only, never overwrite what the team already has
        update contacts
           set phone                 = coalesce(phone, nullif(trim(r.phone), '')),
               email                 = coalesce(email, nullif(trim(r.email), '')),
               linkedin_url          = coalesce(linkedin_url, nullif(trim(r.linkedin), '')),
               title                 = coalesce(title, nullif(trim(r.title), '')),
               linkedin_connected_on = coalesce(linkedin_connected_on, parse_yes_or_date(r.added_on_linkedin, v_sourced)),
               notes                 = case when nullif(trim(r.extra_notes), '') is null
                                              or position(trim(r.extra_notes) in coalesce(notes, '')) > 0 then notes
                                            else concat_ws(E'\n', notes, trim(r.extra_notes)) end
         where id = v_contact_id;
        select organization_id into v_org_id from contacts where id = v_contact_id;
        v_result := 'existing_contact';
        select format('Already in the CRM (matched on %s): %s%s. %s%s',
                      v_matched, coalesce(c.full_name, c.email), coalesce(' at ' || o.name, ''),
                      coalesce('Last touch ' || to_char(lt.touched_at, 'Mon DD, YYYY') || ' via ' || tt.name || ': ' || oc.label,
                               'No outreach logged yet'),
                      case when c.do_not_contact then '. DO NOT CONTACT: ' || coalesce(c.dnc_reason, '') else '' end)
          into v_detail
          from contacts c
          left join organizations o on o.id = c.organization_id
          left join lateral (select t.touched_at, t.touch_type, t.outcome_code from touchpoints t
                              where t.contact_id = c.id order by t.touched_at desc limit 1) lt on true
          left join touch_types tt on tt.code = lt.touch_type
          left join outcomes oc on oc.code = lt.outcome_code
         where c.id = v_contact_id;
      else
        -- 2) a new person: is their organization already here?
        if v_seg.party_type = 'organization' then
          if r.review_decision = 'use_candidate' and r.review_candidate_org_id is not null then
            v_org_id := r.review_candidate_org_id; v_matched := 'reviewer: same organization';
          end if;
          if v_org_id is null and v_web_domain is not null then
            select id into v_org_id from organizations where domain = v_web_domain order by id limit 1;
            if found then v_matched := 'website'; end if;
          end if;
          if v_org_id is null and v_org_key is not null then
            select id into v_org_id from organizations where name_key = v_org_key
             order by (state is not distinct from v_state) desc, id limit 1;
            if found then v_matched := 'organization name'; end if;
          end if;
          if v_org_id is null and v_domain is not null
             and not exists (select 1 from freemail_domains f where f.domain = v_domain) then
            select organization_id into v_org_id from contacts
             where email_domain = v_domain and organization_id is not null
             group by organization_id order by count(*) desc limit 1;
            if found then v_matched := 'email domain'; end if;
          end if;
          -- close but not exact (typo, word order, "... Club"): a person decides
          if v_org_id is null and v_org_key is not null and not v_force_new then
            select id into v_cand_org
              from organizations
             where name_key % v_org_key
               and org_names_look_alike(name, v_org_text)
             order by similarity(name_key, v_org_key) desc
             limit 1;
            if v_cand_org is not null then
              update import_rows
                 set result = 'needs_review', matched_on = 'similar organization name',
                     review_candidate_org_id = v_cand_org,
                     result_detail = format('"%s" looks like existing organization "%s". Same organization?',
                                            v_org_text, (select name from organizations where id = v_cand_org)),
                     processed_at = now()
               where id = r.id;
              continue;
            end if;
          end if;
        end if;

        -- 3) same (or nickname / typo) name already there under another email: a person decides
        if not v_force_new and v_name_key is not null then
          select id into v_cand_contact from contacts
           where person_names_look_alike(first_name, last_name, v_first, v_last)
             and (organization_id = v_org_id
                  or (v_org_id is null and organization_id is null and v_seg.party_type = 'individual'
                      and (v_state is null or state is null or state = v_state)))
           order by (name_key = v_name_key) desc, id
           limit 1;
          if found then
            update import_rows
               set result = 'needs_review', matched_on = 'same or similar name', review_candidate_contact_id = v_cand_contact,
                   organization_id = v_org_id,
                   result_detail = format('%s is already in the CRM with email %s. Same person with a new email?',
                                          (select full_name from contacts where id = v_cand_contact),
                                          coalesce((select email from contacts where id = v_cand_contact), '(none)')),
                   processed_at = now()
             where id = r.id;
            continue;
          end if;
        end if;

        -- what already happened at this organization (the "row 2500 vs row 600" hunt)
        if v_org_id is not null then
          select format('Organization already in the CRM (matched on %s). %s other %s there; last touch %s with %s: %s',
                        v_matched, count(distinct c.id), case when count(distinct c.id) = 1 then 'person' else 'people' end,
                        coalesce(to_char(max(t.touched_at), 'Mon DD, YYYY'), 'none'),
                        coalesce((array_agg(c2.full_name order by t.touched_at desc) filter (where t.id is not null))[1], 'nobody'),
                        coalesce((array_agg(oc.label order by t.touched_at desc) filter (where t.id is not null))[1], 'no outreach yet'))
            into v_detail
            from contacts c
            left join touchpoints t on t.contact_id = c.id
            left join contacts c2 on c2.id = t.contact_id
            left join outcomes oc on oc.code = t.outcome_code
           where c.organization_id = v_org_id;
          v_result := 'new_contact_existing_org';
        else
          v_result := 'new_contact';
          if v_seg.party_type = 'organization' and v_org_key is not null then
            insert into organizations (name, segment_code, org_type, website, city, state, reported_aum, owner_id,
                                       source_detail, legacy_ref)
            values (v_org_text, v_seg.code, coalesce(nullif(trim(v_x ->> 'org_type'), ''), b.default_org_type),
                    nullif(trim(r.website), ''), nullif(trim(v_x ->> 'city'), ''), coalesce(v_state, b.default_state),
                    parse_amount(r.aum), b.owner_id, nullif(trim(r.source), ''),
                    b.label || ' / row ' || coalesce(r.row_number::text, '?'))
            returning id into v_org_id;
          end if;
          v_detail := 'Added';
        end if;

        insert into contacts (organization_id, segment_code, first_name, last_name, title, employer, email, phone,
                              linkedin_url, linkedin_connected_on, city, state, prospect_aum, source_channel_code,
                              source_detail, source_event_id, sourced_on, owner_id, notes, legacy_ref)
        values (v_org_id, v_seg.code, v_first, v_last, nullif(trim(r.title), ''),
                case when v_seg.party_type = 'individual' then v_org_text end,
                v_email, nullif(trim(r.phone), ''), nullif(trim(r.linkedin), ''),
                parse_yes_or_date(r.added_on_linkedin, v_sourced),
                nullif(trim(v_x ->> 'city'), ''),
                coalesce(v_state, (select state from organizations where id = v_org_id), b.default_state),
                case when v_seg.party_type = 'individual' then parse_amount(r.aum) end,
                v_channel, nullif(trim(r.source), ''), v_event_id, v_sourced, b.owner_id,
                nullif(concat_ws(E'\n', nullif(trim(r.notes), ''), nullif(trim(r.extra_notes), '')), ''),
                b.label || ' / row ' || coalesce(r.row_number::text, '?'))
        returning id into v_contact_id;
        if v_email is null and nullif(trim(r.email), '') is not null then
          v_detail := v_detail || format('. Email "%s" is not valid and was left blank', trim(r.email));
        end if;
      end if;

      -- 3b) the workbook's extra columns -------------------------------------------------
      -- organization facts (fill blanks; "Reach Out Again?" is newer information and overwrites)
      if v_org_id is not null then
        update organizations
           set org_type              = coalesce(org_type, nullif(trim(v_x ->> 'org_type'), ''), b.default_org_type),
               city                  = coalesce(city, nullif(trim(v_x ->> 'city'), '')),
               reported_aum          = coalesce(reported_aum, parse_amount(r.aum)),
               employee_count        = coalesce(employee_count, nullif(regexp_replace(coalesce(v_x ->> 'employee_count', ''), '[^0-9]', '', 'g'), '')::int),
               plans_served          = coalesce(plans_served, nullif(regexp_replace(coalesce(v_x ->> 'plans_served', ''), '[^0-9]', '', 'g'), '')::int),
               commissions           = coalesce(commissions, parse_amount(v_x ->> 'commissions')),
               shared_employers      = coalesce(shared_employers, nullif(trim(v_x ->> 'shared_employers'), '')),
               advertises_retirement = coalesce(advertises_retirement, parse_yes_no(v_x ->> 'advertises_retirement')),
               reach_out_again       = coalesce(parse_yes_no(v_x ->> 'reach_out_again'), reach_out_again),
               no_reach_out_reason   = coalesce(nullif(trim(v_x ->> 'no_reach_out_reason'), ''), no_reach_out_reason),
               mailing_address       = coalesce(mailing_address, nullif(trim(v_x ->> 'mailing_address'), ''))
         where id = v_org_id;
      end if;

      -- contact facts
      v_notes_add := null;
      if nullif(trim(v_x ->> 'status'), '') is not null and nullif(trim(r.outcome), '') is not null then
        v_notes_add := concat_ws(E'\n', v_notes_add, 'Status (sheet): ' || trim(v_x ->> 'status'));
      end if;
      if nullif(trim(v_x ->> 'outcome_2'), '') is not null then
        v_notes_add := concat_ws(E'\n', v_notes_add, 'Outcome 2 (sheet): ' || trim(v_x ->> 'outcome_2'));
      end if;
      if nullif(trim(v_x ->> 'no_reach_out_reason'), '') is not null and v_org_id is null then
        v_notes_add := concat_ws(E'\n', v_notes_add, 'Reason not to reach out again: ' || trim(v_x ->> 'no_reach_out_reason'));
      end if;
      update contacts
         set city            = coalesce(city, nullif(trim(v_x ->> 'city'), '')),
             mailing_address = coalesce(mailing_address, nullif(trim(v_x ->> 'mailing_address'), '')),
             activity_status = coalesce(case when lower(trim(coalesce(v_x ->> 'activity_status', ''))) ~ '^(dorm|inactive|parked)' then 'dormant'
                                             when lower(trim(coalesce(v_x ->> 'activity_status', ''))) ~ '^active' then 'active' end,
                                        activity_status),
             source_channel_code = coalesce(source_channel_code, v_channel),
             source_event_id     = coalesce(source_event_id, v_event_id),
             tags            = (select coalesce(array_agg(distinct x), '{}') from unnest(tags || b.tags) x),
             notes           = case when v_notes_add is null or position(v_notes_add in coalesce(notes, '')) > 0 then notes
                                    else concat_ws(E'\n', notes, v_notes_add) end
       where id = v_contact_id;
      if parse_yes_no(v_x ->> 'newsletter') then
        perform add_to_newsletter(v_contact_id, v_sourced, 'sheet: ' || b.label);
      end if;

      -- flags the rules raised on this person
      select concat_ws('. ',
               case when do_not_contact then 'FLAGGED DO NOT CONTACT: ' || coalesce(dnc_reason, '') end,
               case when is_university_affiliated then 'University contact: founder may know them' end)
        into v_flags
        from contacts where id = v_contact_id;
      if coalesce(v_flags, '') <> '' then v_detail := v_detail || '. ' || v_flags; end if;

      -- "Batch" column (Small Biz list) -> campaign
      if nullif(trim(v_x ->> 'campaign'), '') is not null then
        select id into v_campaign_id from campaigns where lower(name) = lower(trim(v_x ->> 'campaign'));
        if v_campaign_id is null then
          insert into campaigns (name, channel_code, segment_code, description)
          values (trim(v_x ->> 'campaign'), b.default_channel_code, v_seg.code, 'From ' || b.label)
          returning id into v_campaign_id;
        end if;
      end if;

      -- 4) the outreach columns become a touchpoint
      v_outcome_text := coalesce(nullif(trim(r.outcome), ''), nullif(trim(v_x ->> 'status'), ''));
      if v_touch_on is null and b.default_outcome_code is not null and v_outcome_text is null then
        v_touch_on := v_sourced;     -- e.g. the Wrong Emails tab: the bounce is the fact, the date is secondary
      end if;
      if v_touch_on is not null then
        select * into v_out from match_outcome(v_outcome_text);
        v_suggest := case when exists (select 1 from outcomes o
                                        where o.code = v_out.outcome_code and b.default_touch_type = any (o.applies_to))
                          then v_out.outcome_code end;
        if v_outcome_text is null and b.default_outcome_code is not null then
          v_outcome := b.default_outcome_code; v_status := 'confirmed';
        elsif v_outcome_text is null then                                     -- blank = still no response (or just met, at an event)
          v_outcome := case when b.default_touch_type in ('email', 'check_in') then 'NO_RESPONSE'
                            when b.default_touch_type = 'event' then 'MET_AT_EVENT' end;
          v_status  := 'confirmed';
        elsif lower(trim(v_outcome_text)) in ('review', 'needs review', 'to review', '?') then
          v_outcome := case when b.default_touch_type in ('email', 'check_in') then 'NO_RESPONSE'
                            when b.default_touch_type = 'event' then 'MET_AT_EVENT' end;
          v_status  := 'needs_review'; v_suggest := null;
        elsif v_suggest is not null and v_out.is_exact then                   -- a clean label
          v_outcome := v_suggest; v_status := 'confirmed';
        elsif v_suggest is not null then                                      -- phrase inside a pasted reply, or a hint
          v_outcome := coalesce(b.default_outcome_code,
                                case when b.default_touch_type in ('email', 'check_in') then 'NO_RESPONSE'
                                     when b.default_touch_type = 'event' then 'MET_AT_EVENT' end);
          v_status  := 'needs_review';
        else                                                                  -- could not tell
          v_outcome := coalesce(b.default_outcome_code,
                                case when b.default_touch_type in ('email', 'check_in') then 'NO_RESPONSE'
                                     when b.default_touch_type = 'event' then 'MET_AT_EVENT' end);
          v_status  := 'needs_review';
        end if;
        -- a blank outcome but a pasted reply: let the reply suggest
        if v_outcome_text is null and nullif(trim(v_x ->> 'response_notes'), '') is not null then
          select * into v_out from match_outcome(v_x ->> 'response_notes');
          if v_out.outcome_code is not null and exists (select 1 from outcomes o where o.code = v_out.outcome_code
                                                          and b.default_touch_type = any (o.applies_to)) then
            v_suggest := v_out.outcome_code; v_status := 'needs_review';
          end if;
        end if;

        v_follow_up := parse_loose_date(r.follow_up_on);
        if v_follow_up is null and b.default_follow_up_days is not null then
          v_follow_up := greatest(v_touch_on + b.default_follow_up_days, local_today());
        end if;

        -- re-importing the same sheet does not create the touch twice
        select id into v_touch_id from touchpoints
         where contact_id = v_contact_id and touch_type = b.default_touch_type and local_date(touched_at) = v_touch_on
         limit 1;
        if v_touch_id is null then
          insert into touchpoints (contact_id, touch_type, direction, touched_at, campaign_id, event_id,
                                   outcome_code, outcome_status, outcome_raw, response_excerpt,
                                   ai_suggested_outcome, ai_confidence, ai_reason, notes, owner_id, follow_up_on)
          values (v_contact_id, b.default_touch_type,
                  case when b.default_touch_type = 'event' and coalesce((select format from events where id = v_event_id), 'in_person') = 'in_person' then 'in_person' else 'outbound' end,
                  (v_touch_on + time '09:00') at time zone 'America/Denver', coalesce(v_campaign_id, b.campaign_id), v_event_id,
                  v_outcome, v_status, v_outcome_text, nullif(trim(v_x ->> 'response_notes'), ''),
                  case when v_status = 'needs_review' then v_suggest end,
                  case when v_status = 'needs_review' and v_suggest is not null then 0.6 end,
                  case when v_status = 'needs_review' and v_suggest is not null and v_out.phrase is not null
                       then format('Matched "%s" in the sheet', v_out.phrase)
                       when v_status = 'needs_review' then 'Could not match the Outcome text; a person decides' end,
                  nullif(trim(r.next_steps), ''), b.owner_id, v_follow_up)
          returning id into v_touch_id;
        end if;
      else
        v_follow_up := parse_loose_date(r.follow_up_on);
        if v_follow_up is null and b.default_follow_up_days is not null then
          v_follow_up := greatest(v_sourced + b.default_follow_up_days, local_today());
        end if;
        if v_outcome_text is not null then      -- an outcome / status with no date: keep the words
          update contacts set notes = concat_ws(E'\n', notes, 'Outcome (sheet, no date): ' || v_outcome_text)
           where id = v_contact_id and position('Outcome (sheet, no date): ' || v_outcome_text in coalesce(notes, '')) = 0;
        end if;
      end if;

      -- the sheet's next reach-out date (or the section's "check back in N months") -> one open reminder
      -- (live imports with an outreach date leave this to the outcome rules)
      if v_follow_up is not null and (v_touch_on is null or not p_run_automation)
         and not exists (select 1 from reminders
                          where contact_id = v_contact_id and status in ('open', 'snoozed')
                            and reminder_type in ('follow_up', 'ooo_follow_up', 'post_call', 'check_in')) then
        insert into reminders (reminder_type, contact_id, organization_id, touchpoint_id, due_on, title, details, assigned_to, created_by)
        select 'follow_up', c.id, c.organization_id, v_touch_id, v_follow_up,
               'Follow up: ' || coalesce(c.full_name, c.email) || coalesce(' (' || o.name || ')', ''),
               'Next reach-out date from ' || b.label
                 || coalesce(E'\n' || nullif(trim(r.next_steps), ''), '')
                 || coalesce(E'\nStatus: ' || nullif(trim(v_x ->> 'status'), ''), ''),
               coalesce(c.owner_id, b.owner_id), 'import'
          from contacts c left join organizations o on o.id = c.organization_id
         where c.id = v_contact_id and not c.do_not_contact;
      end if;

      -- 5) Onboarded tab: Sent Onboarding / Account Funded Date / AUM -> the opportunity
      v_onb_on    := parse_loose_date(v_x ->> 'onboarding_sent_on');
      v_funded_on := parse_loose_date(v_x ->> 'funded_on');
      if v_onb_on is null and v_funded_on is null and parse_yes_no(v_x ->> 'onboarding_sent_on') then
        v_onb_on := coalesce(v_touch_on, v_sourced);                        -- "Yes" with no date
      end if;
      if v_onb_on is not null or v_funded_on is not null then
        v_aum := parse_amount(r.aum);
        select * into v_opp from opportunities op
         where (op.contact_id = v_contact_id
                or (v_seg.party_type = 'organization' and v_org_id is not null and op.organization_id = v_org_id))
         order by (op.stage not in ('funded', 'lost')) desc, (op.contact_id = v_contact_id) desc, op.opened_on desc
         limit 1;
        if not found then
          insert into opportunities (contact_id, organization_id, segment_code, state, stage, source_channel_code,
                                     converting_channel_code, converting_touchpoint_id, opened_on, onboarding_started_on,
                                     funded_on, funded_aum, expected_aum, owner_id, notes)
          values (v_contact_id, case when v_seg.party_type = 'organization' then v_org_id end, v_seg.code, v_state,
                  case when v_funded_on is not null and v_aum is not null then 'funded' else 'onboarding' end,
                  v_channel, b.default_channel_code, v_touch_id,
                  coalesce(v_touch_on, v_onb_on, v_funded_on), coalesce(v_onb_on, v_funded_on),
                  case when v_aum is not null then v_funded_on end,
                  case when v_funded_on is not null then v_aum end, v_aum, b.owner_id,
                  'From ' || b.label)
          returning * into v_opp;
        else
          update opportunities
             set stage                 = case when v_funded_on is not null and coalesce(v_aum, funded_aum) is not null then 'funded'
                                              when stage_rank('onboarding') > stage_rank(stage) then 'onboarding' else stage end,
                 onboarding_started_on = coalesce(onboarding_started_on, v_onb_on, v_funded_on),
                 funded_on             = case when coalesce(v_aum, funded_aum) is not null then coalesce(funded_on, v_funded_on) else funded_on end,
                 funded_aum            = coalesce(funded_aum, case when v_funded_on is not null then v_aum end),
                 expected_aum          = coalesce(expected_aum, v_aum),
                 closed_on             = case when v_funded_on is not null and coalesce(v_aum, funded_aum) is not null
                                              then coalesce(closed_on, v_funded_on) else closed_on end
           where id = v_opp.id
           returning * into v_opp;
        end if;
        if v_funded_on is not null and v_opp.funded_aum is null then
          v_detail := v_detail || format('. Funded on %s but no AUM in the sheet: left in onboarding until funded_aum is entered',
                                         to_char(v_funded_on, 'Mon DD, YYYY'));
          insert into reminders (reminder_type, contact_id, organization_id, opportunity_id, due_on, title, details, assigned_to, created_by)
          select 'onboarding_task', v_contact_id, v_opp.organization_id, v_opp.id, local_today(),
                 'Enter the funded AUM: ' || coalesce(c.full_name, c.email),
                 'The Onboarded sheet shows this account funded on ' || to_char(v_funded_on, 'Mon DD, YYYY')
                   || ' but has no AUM. Fill opportunities.funded_aum and set the stage to funded.',
                 coalesce(c.owner_id, b.owner_id), 'import'
            from contacts c where c.id = v_contact_id
             and not exists (select 1 from reminders x where x.opportunity_id = v_opp.id and x.status in ('open', 'snoozed')
                                                          and x.reminder_type = 'onboarding_task');
        end if;
        update contacts set tags = (select coalesce(array_agg(distinct x), '{}') from unnest(tags || '{client}') x)
         where id = v_contact_id;
      end if;

      -- 6) Customer Loyalty tab: card and check-in dates -> reminders (past dates logged as done)
      for v_k, v_v in
        select * from (values ('loyalty_thanksgiving', 'thanksgiving_card'), ('loyalty_referral_1', 'referral_check_in'),
                              ('loyalty_referral_2', 'referral_check_in'), ('loyalty_referral_3', 'referral_check_in')) t(k, typ)
      loop
        v_due := parse_loose_date(v_x ->> v_k);
        continue when v_due is null;
        if not exists (select 1 from reminders where contact_id = v_contact_id and reminder_type = v_v and due_on = v_due) then
          insert into reminders (reminder_type, contact_id, organization_id, due_on, title, details, assigned_to, created_by,
                                 status, completed_at)
          select v_v, c.id, c.organization_id, v_due,
                 (select label from reminder_types where code = v_v) || ': ' || coalesce(c.full_name, c.email)
                   || coalesce(' (' || o.name || ')', ''),
                 'From ' || b.label || coalesce(E'\nMail to: ' || coalesce(c.mailing_address, o.mailing_address), ''),
                 coalesce(c.owner_id, b.owner_id), 'import',
                 case when v_due < local_today() then 'done' else 'open' end,
                 case when v_due < local_today() then (v_due + time '12:00') at time zone 'America/Denver' end
            from contacts c left join organizations o on o.id = c.organization_id
           where c.id = v_contact_id;
        end if;
      end loop;

      update import_rows
         set result = v_result, result_detail = v_detail, matched_on = v_matched,
             contact_id = v_contact_id,
             organization_id = (select organization_id from contacts where id = v_contact_id),
             touchpoint_id = v_touch_id, processed_at = now()
       where id = r.id;

    exception when others then
      update import_rows set result = 'error', result_detail = sqlerrm, processed_at = now() where id = r.id;
    end;
  end loop;

  select jsonb_build_object(
           'batch',                          b.label,
           'rows',                           count(*),
           'new_contacts',                   count(*) filter (where ir.result = 'new_contact'),
           'new_contacts_at_known_orgs',     count(*) filter (where ir.result = 'new_contact_existing_org'),
           'already_in_crm',                 count(*) filter (where ir.result = 'existing_contact'),
           'needs_review',                   count(*) filter (where ir.result = 'needs_review'),
           'skipped',                        count(*) filter (where ir.result = 'skipped'),
           'errors',                         count(*) filter (where ir.result = 'error'),
           'flagged_do_not_contact',         count(*) filter (where c.do_not_contact),
           'flagged_university',             count(*) filter (where c.is_university_affiliated),
           'outcomes_to_confirm',            count(*) filter (where t.outcome_status = 'needs_review'))
    into v_summary
    from import_rows ir
    left join contacts c    on c.id = ir.contact_id
    left join touchpoints t on t.id = ir.touchpoint_id
   where ir.batch_id = p_batch_id;

  update import_batches set status = 'processed', processed_at = now(), summary = v_summary where id = p_batch_id;
  perform set_config('app.history_load', 'off', true);   -- back to normal for the rest of the transaction
  return v_summary;
end $$;


-- ---------------------------------------------------------------------
-- 6. Profiles and the two commands
-- ---------------------------------------------------------------------
alter table public.import_tab_profiles add column if not exists scope text not null default 'contact'
  check (scope in ('contact', 'event', 'rfp'));

insert into public.import_tab_profiles
  (tab, sort_order, scope, segment, channel_code, touch_type, org_type, default_outcome_code, follow_up_days, tags, match_by_name, header_map, description, prep_notes) values
  ('Events', 110, 'event', null, 'EVENT', 'event', null, null, null, '{}', false, '{}',
   'One row per event: name, date (a range like "Oct 3-5, 2025" is fine), type, in person or virtual, host, city/state, cost, attendees, # of contacts / responses / meetings, clients won ($), notes. Same name + same date twice = one event. Jon''s "Event ROI Tracker" is understood as is.',
   'The header row must be row 1 and column A must be a data column: in the Event ROI Tracker, delete rows 1-13 (title and description) and the empty column A, or paste B14 down into a fresh sheet. If the people met are listed by name, put them on their own tab with an "Event" column (profile "Event attendees").'),
  ('Event attendees', 111, 'contact', 'Nonprofit', 'EVENT', 'event', null, null, null, '{}', false, '{"date": "date_outreached", "datemet": "date_outreached"}',
   'People met at events: the usual contact columns plus an "Event" column naming the event (import the Events sheet first). Each person gets an event touch tied to that event and EVENT as their source channel.',
   'Add a "Date" or "Date Contacted" column if the sheet has one; without it the touch is dated on the event start date only when the event is known.'),
  ('RFPs', 120, 'rfp', 'Nonprofit', 'RFP', 'rfp', null, null, null, '{}', false, '{}',
   'One row per RFP. Jon''s "RFP Log" columns are understood as is: "RFP Name / Issuer" is split into title and organization, Final Submission Date is the due date (and the submitted date once it has passed and the row is approved), Approved (Y/N), Reviewed By / Date Reviewed, Size of AUM, Conditions, Response and Date Responded, Correspondence, WON (Y/N). The status comes from WON, then the Response wording, then the dates. Won and lost RFPs with a contact are logged as touches so the pipeline sees them.',
   'The header row must be row 1 and column A a data column: in the RFP Log, delete rows 1-3 and the empty column A. Write the issuer after a slash ("Investment advisory RFP / Utah Arts Foundation"); a cell with no slash is taken as the issuer. A Response the importer cannot read as won / lost / shortlisted is kept as text and listed under responses_to_check in the result.')
on conflict (tab) do update set
  scope = excluded.scope, header_map = excluded.header_map, description = excluded.description, prep_notes = excluded.prep_notes,
  channel_code = excluded.channel_code, touch_type = excluded.touch_type, segment = excluded.segment, sort_order = excluded.sort_order;

-- check_upload_headers: reads the scope from the profile
create or replace function public.check_upload_headers(p_table regclass, p_tab text default null)
returns table (column_name text, maps_to text, filled_rows bigint, note text)
language plpgsql stable set search_path = public as $$
declare
  v_map   jsonb := '{}';
  v_scope text := 'contact';
  a       record;
  v_n     bigint;
begin
  if p_tab is not null then
    select header_map, scope into v_map, v_scope from import_tab_profiles where lower(tab) = lower(p_tab);
    if not found then
      raise exception 'Unknown tab "%". Known tabs: %', p_tab,
        (select string_agg(tab, ', ' order by sort_order) from import_tab_profiles);
    end if;
  end if;
  for a in
    select attname from pg_attribute
     where attrelid = p_table and attnum > 0 and not attisdropped
     order by attnum
  loop
    execute format('select count(*) from %s where nullif(btrim(%I::text), '''') is not null', p_table, a.attname) into v_n;
    column_name := a.attname;
    maps_to     := resolve_header(a.attname, v_map, v_scope);
    filled_rows := v_n;
    note := case
      when lower(a.attname) in ('id', 'created_at') and maps_to is null then 'added by Supabase, ignored'
      when maps_to is null       then 'NOT RECOGNIZED: kept in the notes. Rename the header, or add it to import_header_aliases (scope ' || v_scope || ')'
      when maps_to = 'ignore'    then 'dropped'
      when maps_to = 'extra_notes' then 'appended to the contact notes'
      when maps_to in ('new_contact', 'new_first_name', 'new_email', 'new_org', 'new_website', 'new_linkedin', 'new_notes')
                                 then 'second contact at the same organization (or the contact itself when there is no other name/email column)'
      when maps_to = 'event'     then 'ties the row to that event by name (import the Events sheet first)'
      when v_n = 0               then 'empty column'
      else '' end;
    return next;
  end loop;
end $$;

-- import_gaard_tab: dispatches on the profile's scope
create or replace function public.import_gaard_tab(
  p_table           regclass,
  p_tab             text,
  p_owner_id        bigint  default null,
  p_run_automation  boolean default false,
  p_label           text    default null
) returns jsonb
language plpgsql set search_path = public as $$
declare
  p import_tab_profiles;
begin
  select * into p from import_tab_profiles where lower(tab) = lower(p_tab);
  if not found then
    raise exception 'Unknown tab "%". Known tabs: %', p_tab,
      (select string_agg(tab, ', ' order by sort_order) from import_tab_profiles);
  end if;
  if p.scope = 'event' then
    return import_events_table(p_table, coalesce(p_label, p.tab), p.header_map) || jsonb_build_object('tab', p.tab);
  elsif p.scope = 'rfp' then
    return import_rfps_table(p_table, coalesce(p_label, p.tab), p.segment, p.header_map) || jsonb_build_object('tab', p.tab);
  end if;
  return import_uploaded_table(
           p_table, coalesce(p_label, p.tab), p.segment, p.channel_code, p.touch_type, null, null, null, p_owner_id,
           p_run_automation, p.org_type, p.default_outcome_code, p.follow_up_days, p.tags, p.match_by_name, p.header_map)
         || jsonb_build_object('tab', p.tab);
end $$;


-- ---------------------------------------------------------------------
-- 7. v_event_performance: the sheet's own counts next to what the CRM can count itself
--    (contacts / responses / meetings / clients won from Jon's Event ROI Tracker)
-- ---------------------------------------------------------------------
create or replace view public.v_event_performance with (security_invoker = true) as
select
  e.id                                  as event_id,
  e.name,
  e.event_type,
  e.format,
  e.hosted_by_us,
  e.host_org,
  e.start_on,
  public.quarter_label(e.start_on)      as quarter,
  e.city,
  e.state,
  sg.name                               as target_segment,
  e.cost_usd,
  coalesce(m.people_met, 0)             as people_met,
  coalesce(m.meetings_at_event, 0)      as meetings_at_event,
  coalesce(n.new_contacts, 0)           as new_contacts,
  coalesce(f.responded, 0)              as responded,
  coalesce(f.calls, 0)                  as calls,
  coalesce(f.onboarding, 0)             as onboarding,
  coalesce(f.funded, 0)                 as funded,
  coalesce(f.funded_aum, 0)             as funded_aum,
  round(e.cost_usd / nullif(coalesce(nullif(m.people_met, 0), e.people_met_reported), 0), 2) as cost_per_person_met,
  round(e.cost_usd / nullif(coalesce(nullif(f.calls, 0), e.meetings_reported), 0), 2)       as cost_per_call,
  e.people_met_reported,
  e.notes,
  e.end_on,
  e.responses_reported,
  e.meetings_reported,
  e.clients_won_usd,
  round(e.cost_usd / nullif(coalesce(nullif(f.responded, 0), e.responses_reported), 0), 2)  as cost_per_response,
  case when e.cost_usd > 0 then round(coalesce(nullif(f.funded_aum, 0), e.clients_won_usd) / e.cost_usd, 1) end as won_per_dollar_spent
from public.events e
left join public.segments sg on sg.code = e.target_segment_code
left join lateral (
  select count(distinct t.contact_id) as people_met,
         count(*) filter (where t.outcome_code in ('MEETING_AT_EVENT', 'INTERESTED')) as meetings_at_event
    from public.touchpoints t
   where t.event_id = e.id and t.touch_type = 'event') m on true
left join lateral (
  select count(*) as new_contacts from public.contacts c where c.source_event_id = e.id) n on true
left join lateral (
  select count(lf.responded_on) as responded, count(lf.call_booked_on) as calls,
         count(lf.onboarding_on) as onboarding, count(lf.funded_on) as funded,
         coalesce(sum(lf.funded_aum), 0) as funded_aum
    from public.v_lead_funnel lf
   where lf.source_event_id = e.id) f on true;

-- what people write about someone they met at an event
insert into public.outcome_aliases (phrase, outcome_code, force_review) values
  ('met at event', 'MET_AT_EVENT', false), ('met at event, exchanged info', 'MET_AT_EVENT', false),
  ('met at the event', 'MET_AT_EVENT', false), ('exchanged info', 'MET_AT_EVENT', false),
  ('exchanged cards', 'MET_AT_EVENT', false), ('exchanged contact info', 'MET_AT_EVENT', false),
  ('met briefly', 'MET_AT_EVENT', false), ('introduced at event', 'MET_AT_EVENT', false),
  ('had a meeting at the event', 'MEETING_AT_EVENT', false), ('meeting at the event', 'MEETING_AT_EVENT', false),
  ('meeting at event', 'MEETING_AT_EVENT', false), ('sat down with', 'MEETING_AT_EVENT', false),
  ('had a meeting', 'MEETING_AT_EVENT', false), ('long conversation', 'MEETING_AT_EVENT', false),
  ('interested, call scheduled', 'INTERESTED', false), ('interested, follow up', 'INTERESTED', false),
  ('interested, send info', 'INFO_REQUESTED', false), ('asked for info', 'INFO_REQUESTED', false),
  ('wants to talk', 'INTERESTED', false), ('not a fit', 'NOT_A_FIT', false)
on conflict (phrase) do nothing;

-- v_rfp_tracker: the RFP log's own columns, appended
create or replace view public.v_rfp_tracker with (security_invoker = true) as
select
  r.id                                   as rfp_id,
  r.title,
  o.name                                 as organization,
  sg.name                                as segment,
  o.state,
  c.full_name                            as contact,
  r.mandate_type,
  r.found_via,
  r.est_mandate_aum,
  r.status,
  r.released_on,
  r.questions_due_on,
  r.due_on,
  case when r.status in ('identified', 'intent_to_bid') then r.due_on - public.local_today() end as days_until_due,
  r.submitted_on,
  r.decision_on,
  op.stage                               as pipeline_stage,
  op.funded_aum,
  tm.full_name                           as owner,
  r.notes,
  r.reference_number,
  r.approved_for_submission,
  r.reviewed_by,
  r.reviewed_on,
  r.terms,
  r.decision_result,
  r.decision_notes
from public.rfps r
join public.organizations o on o.id = r.organization_id
join public.segments sg on sg.code = o.segment_code
left join public.contacts c on c.id = r.contact_id
left join public.team_members tm on tm.id = r.owner_id
left join lateral (
  select p.stage, p.funded_aum from public.opportunities p where p.rfp_id = r.id order by p.opened_on desc limit 1) op on true;

-- the new table, under the same rules as every other (001): team reads and writes, the audit log watches
alter table public.rfp_status_aliases enable row level security;
drop policy if exists team_access  on public.rfp_status_aliases;
drop policy if exists team_read    on public.rfp_status_aliases;
drop policy if exists team_insert  on public.rfp_status_aliases;
drop policy if exists team_update  on public.rfp_status_aliases;
drop policy if exists team_delete  on public.rfp_status_aliases;
create policy team_read   on public.rfp_status_aliases for select to authenticated using (public.is_team_member());
create policy team_insert on public.rfp_status_aliases for insert to authenticated with check (public.is_team_member());
create policy team_update on public.rfp_status_aliases for update to authenticated using (public.is_team_member()) with check (public.is_team_member());
create policy team_delete on public.rfp_status_aliases for delete to authenticated using (public.is_team_member());
grant select, insert, update, delete on public.rfp_status_aliases to authenticated;
revoke all on public.rfp_status_aliases from anon;
do $$
begin
  if to_regprocedure('public.audit_row()') is not null then
    drop trigger if exists zz_audit on public.rfp_status_aliases;
    create trigger zz_audit after insert or update or delete on public.rfp_status_aliases
      for each row execute function public.audit_row();
  end if;
end $$;

commit;

-- The API picks up the new columns and functions
notify pgrst, 'reload schema';
