-- =====================================================================
-- GAARD Capital CRM · Migration 5 of 6 · Views for the app and dashboard
--
-- Working lists (replace the tabs):
--   v_contacts              master list: sort / filter by anything
--   v_organizations         one row per org: who was contacted, rollover flag
--   v_reminders_due         the shared notifications tab
--   v_correspondence        every email / call / meeting, newest first
--   v_outcome_review_queue  suggested outcomes waiting for a click
--   v_newsletter_list       quarterly newsletter recipients
--   v_wrong_emails          the old "wrong email" tab
--   v_possible_duplicates   look-alike people and organizations
--   v_import_results        what process_import_batch() did with each row
-- Dashboard:
--   v_lead_funnel           one row per lead, milestone dates, one source channel
--   v_funnel_by_cohort      funnel counts by quarter / segment / state / channel
--   v_kpis_by_quarter       what happened each quarter (long format)
--   v_channel_performance   which introduction channel works best
--   v_event_performance     cost, people met, meetings, calls, AUM per event
--   v_cold_call_performance dials, connects, calls booked
--   v_pipeline              every opportunity with stage dates and AUM
--   v_aum_by_segment        funded vs onboarding by segment
--   v_funded_aum_by_quarter funded AUM over time
--   v_rfp_tracker           RFPs with deadlines
-- All views use security_invoker so Supabase row-level security applies.
-- =====================================================================

create or replace function public.quarter_label(p date) returns text
language sql immutable set search_path = '' as $$
  select case when p is null then null else to_char(p, 'YYYY') || '-Q' || to_char(p, 'Q') end
$$;


-- ---------------------------------------------------------------------
-- Working lists
-- ---------------------------------------------------------------------

create or replace view public.v_contacts with (security_invoker = true) as
select
  c.id                              as contact_id,
  c.full_name,
  c.first_name,
  c.last_name,
  c.title,
  c.organization_id,
  coalesce(o.name, c.employer)      as organization,
  sg.segment_group,
  sg.name                           as segment,
  c.segment_code,
  c.state,
  st.name                           as state_name,
  c.city,
  c.email,
  c.email_status,
  c.phone,
  c.linkedin_url,
  c.linkedin_connected_on,
  ch.name                           as source_channel,
  c.source_detail,
  ev.name                           as source_event,
  c.sourced_on,
  public.local_date(lt.touched_at)  as last_touch_on,
  ltt.name                          as last_touch_type,
  lo.label                          as last_outcome,
  public.local_date(ls.last_spoke_at) as last_spoke_on,
  nr.due_on                         as next_outreach_on,
  rt.label                          as next_action,
  coalesce(tc.touches, 0)           as touches,
  coalesce(tc.emails_sent, 0)       as emails_sent,
  coalesce(tc.calls_dialed, 0)      as calls_dialed,
  op.stage                          as pipeline_stage,
  op.expected_aum,
  op.funded_aum,
  coalesce(o.reported_aum, c.prospect_aum) as prospect_aum,
  c.is_decision_maker,
  c.is_university_affiliated,
  c.do_not_contact,
  c.dnc_reason,
  c.newsletter_status,
  c.follow_up_style,
  tm.full_name                      as owner,
  c.tags,
  c.notes,
  c.created_at
from public.contacts c
join public.segments sg            on sg.code = c.segment_code
left join public.organizations o   on o.id = c.organization_id
left join public.us_states st      on st.code = c.state
left join public.channels ch       on ch.code = c.source_channel_code
left join public.events ev         on ev.id = c.source_event_id
left join public.team_members tm   on tm.id = c.owner_id
left join lateral (
  select t.touched_at, t.touch_type, t.outcome_code
    from public.touchpoints t
   where t.contact_id = c.id
   order by t.touched_at desc, t.id desc
   limit 1) lt on true
left join public.touch_types ltt   on ltt.code = lt.touch_type
left join public.outcomes lo       on lo.code = lt.outcome_code
left join lateral (
  select max(coalesce(t.responded_at, t.touched_at)) as last_spoke_at
    from public.touchpoints t
    left join public.outcomes x on x.code = t.outcome_code
   where t.contact_id = c.id
     and (coalesce(x.counts_as_response, false) or t.touch_type = 'meeting')) ls on true
left join lateral (
  select r.due_on, r.reminder_type
    from public.reminders r
   where r.contact_id = c.id and r.status in ('open', 'snoozed')
   order by r.due_on
   limit 1) nr on true
left join public.reminder_types rt on rt.code = nr.reminder_type
left join lateral (
  select count(*)                                     as touches,
         count(*) filter (where t.touch_type = 'email') as emails_sent,
         count(*) filter (where t.touch_type = 'call')  as calls_dialed
    from public.touchpoints t
   where t.contact_id = c.id) tc on true
left join lateral (
  select p.stage, p.expected_aum, p.funded_aum
    from public.opportunities p
   where p.contact_id = c.id
      or (sg.party_type = 'organization' and c.organization_id is not null and p.organization_id = c.organization_id)
   order by (p.stage in ('funded', 'lost')), p.opened_on desc
   limit 1) op on true;


create or replace view public.v_organizations with (security_invoker = true) as
select
  o.id                              as organization_id,
  o.name,
  sg.segment_group,
  sg.name                           as segment,
  o.segment_code,
  o.org_type,
  o.state,
  o.city,
  o.website,
  o.reported_aum,
  o.employee_count,
  coalesce(cc.contacts, 0)          as contacts,
  coalesce(cc.decision_makers, 0)   as decision_makers,
  coalesce(tt.people_contacted, 0)  as people_contacted,
  coalesce(tt.touches, 0)           as touches,
  coalesce(tt.responses, 0)         as responses,
  tt.first_touch_on,
  tt.last_touch_on,
  tt.last_outcome,
  tt.last_contacted_person,
  op.stage                          as pipeline_stage,
  op.expected_aum,
  op.funded_aum,
  -- Jon's yearly rollover: nobody answered, so try someone else with leadership authority
  (coalesce(tt.touches, 0) >= 2 and coalesce(tt.responses, 0) = 0
     and tt.last_touch_on < public.local_today() - 90
     and op.stage is null and not o.do_not_contact) as rollover_suggested,
  o.is_university_affiliated,
  o.do_not_contact,
  o.dnc_reason,
  tm.full_name                      as owner,
  o.tags,
  o.notes
from public.organizations o
join public.segments sg          on sg.code = o.segment_code
left join public.team_members tm on tm.id = o.owner_id
left join lateral (
  select count(*) as contacts, count(*) filter (where c.is_decision_maker) as decision_makers
    from public.contacts c where c.organization_id = o.id) cc on true
left join lateral (
  select count(distinct t.contact_id)                                    as people_contacted,
         count(*)                                                        as touches,
         count(*) filter (where x.counts_as_response)                    as responses,
         min(public.local_date(t.touched_at))                            as first_touch_on,
         max(public.local_date(t.touched_at))                            as last_touch_on,
         (array_agg(x.label order by t.touched_at desc))[1]              as last_outcome,
         (array_agg(c.full_name order by t.touched_at desc))[1]          as last_contacted_person
    from public.touchpoints t
    join public.contacts c on c.id = t.contact_id
    left join public.outcomes x on x.code = t.outcome_code
   where c.organization_id = o.id) tt on true
left join lateral (
  select p.stage, p.expected_aum, p.funded_aum
    from public.opportunities p
   where p.organization_id = o.id
   order by (p.stage in ('funded', 'lost')), p.opened_on desc
   limit 1) op on true;


create or replace view public.v_reminders_due with (security_invoker = true) as
select
  r.id                              as reminder_id,
  r.reminder_type,
  rt.label                          as reminder_label,
  r.title,
  r.details,
  r.due_on,
  case when r.due_on <  public.local_today()     then 'overdue'
       when r.due_on =  public.local_today()     then 'today'
       when r.due_on <= public.local_today() + 7 then 'this_week'
       else 'later' end             as due_bucket,
  greatest(public.local_today() - r.due_on, 0) as days_overdue,
  r.status,
  r.follow_up_style,
  r.contact_id,
  c.full_name,
  c.email,
  c.phone,
  coalesce(c.state, o.state)        as state,
  coalesce(o.name, c.employer)      as organization,
  sg.name                           as segment,
  lo.label                          as last_outcome,
  public.local_date(lt.touched_at)  as last_touch_on,
  tm.full_name                      as assigned_to,
  r.opportunity_id,
  r.rfp_id,
  r.created_by,
  r.created_at
from public.reminders r
join public.reminder_types rt      on rt.code = r.reminder_type
left join public.contacts c        on c.id = r.contact_id
left join public.organizations o   on o.id = coalesce(r.organization_id, c.organization_id)
left join public.segments sg       on sg.code = coalesce(c.segment_code, o.segment_code)
left join public.team_members tm   on tm.id = r.assigned_to
left join lateral (
  select t.touched_at, t.outcome_code from public.touchpoints t
   where t.contact_id = r.contact_id order by t.touched_at desc limit 1) lt on true
left join public.outcomes lo       on lo.code = lt.outcome_code
where r.status in ('open', 'snoozed');


-- the correspondence column, rebuilt: newest first per contact
-- (order by occurred_at desc when querying)
create or replace view public.v_correspondence with (security_invoker = true) as
select
  e.contact_id,
  e.sent_at                         as occurred_at,
  case e.direction when 'inbound' then 'Email received' else 'Email sent' end as kind,
  e.subject                         as headline,
  e.body_text                       as body,
  e.from_email                      as who,
  e.touchpoint_id,
  'email'                           as source
from public.email_messages e
union all
select
  t.contact_id,
  coalesce(t.responded_at, t.touched_at),
  tt.name,
  coalesce(t.subject, x.label),
  coalesce(t.notes, t.response_excerpt),
  tm.full_name,
  t.id,
  'touchpoint'
from public.touchpoints t
join public.touch_types tt       on tt.code = t.touch_type
left join public.outcomes x      on x.code = t.outcome_code
left join public.team_members tm on tm.id = t.owner_id
where not exists (select 1 from public.email_messages e where e.touchpoint_id = t.id);


create or replace view public.v_outcome_review_queue with (security_invoker = true) as
select
  t.id                              as touchpoint_id,
  t.contact_id,
  c.full_name,
  coalesce(o.name, c.employer)      as organization,
  tt.name                           as touch_type,
  public.local_date(t.touched_at)   as touched_on,
  t.responded_at,
  cur.label                         as provisional_outcome,
  sug.label                         as suggested_outcome,
  t.ai_suggested_outcome,
  t.ai_confidence,
  t.ai_reason,
  t.response_excerpt,
  t.outcome_raw,
  (select e.body_text from public.email_messages e
    where e.touchpoint_id = t.id and e.direction = 'inbound'
    order by e.sent_at desc limit 1) as latest_reply
from public.touchpoints t
join public.contacts c          on c.id = t.contact_id
join public.touch_types tt      on tt.code = t.touch_type
left join public.organizations o on o.id = c.organization_id
left join public.outcomes cur   on cur.code = t.outcome_code
left join public.outcomes sug   on sug.code = t.ai_suggested_outcome
where t.outcome_status = 'needs_review';


create or replace view public.v_newsletter_list with (security_invoker = true) as
select c.id as contact_id, c.full_name, c.email, coalesce(o.name, c.employer) as organization,
       sg.segment_group, sg.name as segment, c.state, c.newsletter_added_on, c.newsletter_added_via
  from public.contacts c
  join public.segments sg on sg.code = c.segment_code
  left join public.organizations o on o.id = c.organization_id
 where c.newsletter_status = 'subscribed'
   and not c.do_not_contact
   and c.email_key is not null
   and c.email_status not in ('bounced', 'wrong_person');


create or replace view public.v_wrong_emails with (security_invoker = true) as
select c.id as contact_id, c.full_name, coalesce(o.name, c.employer) as organization, c.email, c.email_status,
       c.phone, c.linkedin_url, c.state,
       (select max(public.local_date(t.touched_at)) from public.touchpoints t
         where t.contact_id = c.id and t.outcome_code in ('BOUNCED', 'WRONG_PERSON')) as flagged_on,
       (select min(r.due_on) from public.reminders r
         where r.contact_id = c.id and r.status in ('open', 'snoozed')
           and r.reminder_type in ('fix_contact_info', 'find_new_contact')) as fix_due_on
  from public.contacts c
  left join public.organizations o on o.id = c.organization_id
 where c.email_status in ('bounced', 'wrong_person');


create or replace view public.v_possible_duplicates with (security_invoker = true) as
-- people at the same organization with the same name, a nickname or a typo
select 'contact'::text as entity, a.id as id_a, b.id as id_b, a.full_name as name_a, b.full_name as name_b,
       a.email as detail_a, b.email as detail_b,
       case when a.name_key = b.name_key then 'Same name at the same organization'
            else 'Similar name at the same organization' end as reason
  from public.contacts a
  join public.contacts b on a.id < b.id and a.organization_id = b.organization_id
 where public.person_names_look_alike(a.first_name, a.last_name, b.first_name, b.last_name)
union all
-- individuals (no organization) with look-alike names in the same state
select 'contact', a.id, b.id, a.full_name, b.full_name, a.email, b.email,
       'Similar name (individuals, same state)'
  from public.contacts a
  join public.contacts b on a.id < b.id
                        and a.organization_id is null and b.organization_id is null
                        and a.state is not distinct from b.state
                        and public.norm_text(a.last_name) = public.norm_text(b.last_name)
 where public.person_names_look_alike(a.first_name, a.last_name, b.first_name, b.last_name)
union all
-- organizations with the same website, or a look-alike name (typo, word order, extra generic word)
select 'organization', a.id, b.id, a.name, b.name,
       coalesce(a.domain, a.state), coalesce(b.domain, b.state),
       case when a.domain = b.domain then 'Same website' else 'Look-alike name' end
  from public.organizations a
  join public.organizations b on a.id < b.id
                             and (a.domain = b.domain or a.name_key operator(extensions.%) b.name_key)
 where a.domain = b.domain or public.org_names_look_alike(a.name, b.name);


create or replace view public.v_import_results with (security_invoker = true) as
select b.id as batch_id, b.label as batch, b.status as batch_status, ir.row_number, ir.result, ir.result_detail,
       ir.matched_on, ir.contact, ir.first_name, ir.email, ir.org, ir.source, ir.date_outreached, ir.outcome,
       ir.contact_id, ir.organization_id, ir.touchpoint_id,
       ir.review_candidate_contact_id, ir.review_candidate_org_id, ir.review_decision, ir.id as import_row_id
  from public.import_rows ir
  join public.import_batches b on b.id = ir.batch_id;


-- ---------------------------------------------------------------------
-- Dashboard
-- ---------------------------------------------------------------------

-- One row per lead (a person we reached out to, or who has an opportunity).
-- Each lead has exactly one source channel, so nothing is counted twice.
-- Reaching a later stage implies the earlier ones (funded => onboarded => hot => call).
create or replace view public.v_lead_funnel with (security_invoker = true) as
select
  c.id                                         as contact_id,
  c.full_name,
  c.organization_id,
  coalesce(o.name, c.employer)                 as organization,
  c.segment_code,
  sg.segment_group,
  sg.name                                      as segment,
  sg.sort_order                                as segment_sort,
  c.state,
  coalesce(op.source_channel_code, c.source_channel_code, ft.first_channel) as source_channel_code,
  ch.name                                      as source_channel,
  c.source_event_id,
  ft.first_outreach_on,
  public.quarter_label(coalesce(ft.first_outreach_on, op.opened_on)) as cohort_quarter,
  coalesce(fr.first_response_on, op.opened_on) as responded_on,
  op.opened_on                                 as call_booked_on,
  op.first_call_on,
  coalesce(op.hot_on, op.onboarding_started_on, op.funded_on) as hot_on,
  coalesce(op.onboarding_started_on, op.funded_on)            as onboarding_on,
  op.funded_on,
  op.expected_aum,
  op.funded_aum,
  op.stage                                     as current_stage,
  op.id                                        as opportunity_id,
  op.converting_channel_code,
  c.is_university_affiliated
from public.contacts c
join public.segments sg          on sg.code = c.segment_code
left join public.organizations o on o.id = c.organization_id
left join lateral (
  select min(public.local_date(t.touched_at))                  as first_outreach_on,
         (array_agg(tt.channel_code order by t.touched_at))[1]  as first_channel
    from public.touchpoints t
    join public.touch_types tt on tt.code = t.touch_type and tt.is_outreach
   where t.contact_id = c.id) ft on true
left join lateral (
  select min(public.local_date(coalesce(t.responded_at, t.touched_at))) as first_response_on
    from public.touchpoints t
    join public.outcomes x on x.code = t.outcome_code and x.counts_as_response
   where t.contact_id = c.id) fr on true
left join lateral (
  select p.* from public.opportunities p
   where p.contact_id = c.id
   order by p.opened_on
   limit 1) op on true
left join public.channels ch on ch.code = coalesce(op.source_channel_code, c.source_channel_code, ft.first_channel)
where ft.first_outreach_on is not null or op.id is not null;


create or replace view public.v_funnel_by_cohort with (security_invoker = true) as
select
  cohort_quarter,
  segment_group,
  segment,
  state,
  source_channel,
  count(*)                    as leads,
  count(responded_on)         as responded,
  count(call_booked_on)       as calls,
  count(hot_on)               as hot,
  count(onboarding_on)        as onboarding,
  count(funded_on)            as funded,
  coalesce(sum(funded_aum), 0) as funded_aum
from public.v_lead_funnel
group by cohort_quarter, segment_group, segment, state, source_channel;


-- What happened in each quarter, one row per (quarter, segment, state, channel, metric).
-- Outreach metrics use the channel of the touch; pipeline metrics use the lead's source channel.
create or replace view public.v_kpis_by_quarter with (security_invoker = true) as
with facts as (
  -- outreach activity
  select public.local_date(t.touched_at) as on_date, c.segment_code, c.state, tt.channel_code,
         case t.touch_type when 'email' then 'emails_sent' when 'call' then 'calls_dialed'
                           when 'event' then 'people_met_at_events' when 'intro' then 'referral_intros'
                           when 'rfp' then 'rfp_updates' end as metric,
         1::numeric as value
    from public.touchpoints t
    join public.contacts c     on c.id = t.contact_id
    join public.touch_types tt on tt.code = t.touch_type and tt.is_outreach
  union all
  select public.local_date(t.touched_at), c.segment_code, c.state, 'COLD_CALL', 'calls_connected', 1
    from public.touchpoints t join public.contacts c on c.id = t.contact_id
   where t.touch_type = 'call' and t.outcome_code not in ('NO_ANSWER', 'VOICEMAIL', 'WRONG_NUMBER')
  union all
  -- replies (a person answered), dated when they answered
  select public.local_date(coalesce(t.responded_at, t.touched_at)), c.segment_code, c.state, tt.channel_code,
         case when x.sentiment = 'positive' then 'positive_responses' else 'other_responses' end, 1
    from public.touchpoints t
    join public.contacts c     on c.id = t.contact_id
    join public.touch_types tt on tt.code = t.touch_type and tt.is_outreach
    join public.outcomes x     on x.code = t.outcome_code and x.counts_as_response
  union all
  select public.local_date(t.touched_at), c.segment_code, c.state, null, 'meetings_held', 1
    from public.touchpoints t join public.contacts c on c.id = t.contact_id
   where t.touch_type = 'meeting'
  union all
  select p.first_call_on, p.segment_code, p.state, p.source_channel_code, 'first_calls_held', 1
    from public.opportunities p where p.first_call_on is not null
  union all
  -- new prospects added
  select c.sourced_on, c.segment_code, c.state, c.source_channel_code, 'new_prospects', 1
    from public.contacts c where c.sourced_on is not null
  union all
  -- pipeline milestones, credited to the lead's source channel
  select p.opened_on, p.segment_code, p.state, p.source_channel_code, 'calls_booked', 1
    from public.opportunities p
  union all
  select p.onboarding_started_on, p.segment_code, p.state, p.source_channel_code, 'onboarding_started', 1
    from public.opportunities p where p.onboarding_started_on is not null
  union all
  select p.funded_on, p.segment_code, p.state, p.source_channel_code, 'funded_accounts', 1
    from public.opportunities p where p.funded_on is not null
  union all
  select p.funded_on, p.segment_code, p.state, p.source_channel_code, 'funded_aum', p.funded_aum
    from public.opportunities p where p.funded_on is not null
  union all
  select e.start_on, e.target_segment_code, e.state, 'EVENT', 'event_spend', e.cost_usd
    from public.events e
)
select public.quarter_label(f.on_date) as quarter,
       f.segment_code, sg.segment_group, sg.name as segment,
       f.state, f.channel_code, ch.name as channel,
       f.metric,
       sum(f.value) as value
  from facts f
  left join public.segments sg on sg.code = f.segment_code
  left join public.channels ch on ch.code = f.channel_code
 where f.on_date is not null and f.on_date <= public.local_today()
 group by 1, 2, 3, 4, 5, 6, 7, 8;


-- Which introduction channel works best (each lead counted once, under its source channel)
create or replace view public.v_channel_performance with (security_invoker = true) as
select
  ch.code                                       as channel_code,
  ch.name                                       as channel,
  count(f.contact_id)                           as leads,
  count(f.responded_on)                         as responded,
  count(f.call_booked_on)                       as calls,
  count(f.hot_on)                               as hot,
  count(f.onboarding_on)                        as onboarding,
  count(f.funded_on)                            as funded,
  coalesce(sum(f.funded_aum), 0)                as funded_aum,
  round(count(f.responded_on)::numeric   / nullif(count(f.contact_id), 0), 4)     as response_rate,
  round(count(f.call_booked_on)::numeric / nullif(count(f.contact_id), 0), 4)     as lead_to_call_rate,
  round(count(f.funded_on)::numeric      / nullif(count(f.call_booked_on), 0), 4) as call_to_funded_rate
from public.channels ch
left join public.v_lead_funnel f on f.source_channel_code = ch.code
group by ch.code, ch.name, ch.sort_order
order by ch.sort_order;


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
  round(e.cost_usd / nullif(m.people_met, 0), 2) as cost_per_person_met,
  round(e.cost_usd / nullif(f.calls, 0), 2)      as cost_per_call
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


create or replace view public.v_cold_call_performance with (security_invoker = true) as
select
  coalesce(cp.name, '(no campaign)')  as campaign,
  sg.segment_group,
  sg.name                             as segment,
  c.state,
  count(*)                            as dials,
  count(distinct t.contact_id)        as people_called,
  round(count(*)::numeric / nullif(count(distinct t.contact_id), 0), 2) as dials_per_person,
  count(*) filter (where t.outcome_code not in ('NO_ANSWER', 'VOICEMAIL', 'WRONG_NUMBER')) as connects,
  count(*) filter (where t.outcome_code = 'VOICEMAIL')    as voicemails,
  count(*) filter (where t.outcome_code = 'WRONG_NUMBER') as wrong_numbers,
  count(*) filter (where t.outcome_code = 'INTERESTED')   as calls_booked,
  round(count(*) filter (where t.outcome_code not in ('NO_ANSWER', 'VOICEMAIL', 'WRONG_NUMBER'))::numeric
        / nullif(count(*), 0), 4)     as connect_rate
from public.touchpoints t
join public.contacts c        on c.id = t.contact_id
join public.segments sg       on sg.code = c.segment_code
left join public.campaigns cp on cp.id = t.campaign_id
where t.touch_type = 'call'
group by 1, 2, 3, 4;


create or replace view public.v_pipeline with (security_invoker = true) as
select
  op.id                             as opportunity_id,
  op.stage,
  ps.label                          as stage_label,
  ps.sort_order                     as stage_sort,
  op.contact_id,
  c.full_name                       as contact,
  op.organization_id,
  coalesce(o.name, c.employer)      as organization,
  sg.segment_group,
  sg.name                           as segment,
  op.state,
  sch.name                          as source_channel,
  cch.name                          as converted_by,
  ev.name                           as source_event,
  rf.title                          as rfp,
  op.opened_on,
  op.first_call_on,
  op.hot_on,
  op.onboarding_started_on,
  op.contract_signed_on,
  op.funded_on,
  op.closed_on,
  op.lost_reason,
  op.expected_aum,
  op.funded_aum,
  case when not ps.is_closed then public.local_today()
       - coalesce(op.onboarding_started_on, op.hot_on, op.first_call_on, op.opened_on) end as days_in_stage,
  lt.last_touch_on,
  nr.next_step_on,
  tm.full_name                      as owner
from public.opportunities op
join public.pipeline_stages ps     on ps.code = op.stage
join public.contacts c             on c.id = op.contact_id
join public.segments sg            on sg.code = op.segment_code
left join public.organizations o   on o.id = op.organization_id
left join public.channels sch      on sch.code = op.source_channel_code
left join public.channels cch      on cch.code = op.converting_channel_code
left join public.events ev         on ev.id = op.source_event_id
left join public.rfps rf           on rf.id = op.rfp_id
left join public.team_members tm   on tm.id = op.owner_id
left join lateral (
  select max(public.local_date(t.touched_at)) as last_touch_on from public.touchpoints t
   where t.contact_id = op.contact_id
      or (op.organization_id is not null and t.organization_id = op.organization_id)) lt on true
left join lateral (
  select min(r.due_on) as next_step_on from public.reminders r
   where r.status in ('open', 'snoozed') and (r.opportunity_id = op.id or r.contact_id = op.contact_id)) nr on true;


-- "separate clients who are already onboarded and clients who are onboarding, by business type"
create or replace view public.v_aum_by_segment with (security_invoker = true) as
select
  sg.segment_group,
  sg.name                                                              as segment,
  sg.code                                                              as segment_code,
  count(op.id) filter (where op.stage = 'funded')                      as funded_clients,
  coalesce(sum(op.funded_aum) filter (where op.stage = 'funded'), 0)   as funded_aum,
  count(op.id) filter (where op.stage = 'onboarding')                  as onboarding_clients,
  coalesce(sum(op.expected_aum) filter (where op.stage = 'onboarding'), 0) as onboarding_expected_aum,
  count(op.id) filter (where op.stage in ('call', 'hot'))              as early_pipeline,
  coalesce(sum(op.expected_aum) filter (where op.stage in ('call', 'hot')), 0) as early_pipeline_expected_aum
from public.segments sg
left join public.opportunities op on op.segment_code = sg.code
group by sg.segment_group, sg.name, sg.code, sg.sort_order
order by sg.sort_order;


create or replace view public.v_funded_aum_by_quarter with (security_invoker = true) as
select public.quarter_label(op.funded_on) as quarter, sg.segment_group, sg.name as segment, op.state,
       sch.name as source_channel, count(*) as funded_accounts, sum(op.funded_aum) as funded_aum
  from public.opportunities op
  join public.segments sg      on sg.code = op.segment_code
  left join public.channels sch on sch.code = op.source_channel_code
 where op.funded_on is not null
 group by 1, 2, 3, 4, 5;


create or replace view public.v_rfp_tracker with (security_invoker = true) as
select
  r.id                              as rfp_id,
  r.title,
  o.name                            as organization,
  sg.name                           as segment,
  o.state,
  c.full_name                       as contact,
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
  op.stage                          as pipeline_stage,
  op.funded_aum,
  tm.full_name                      as owner,
  r.notes
from public.rfps r
join public.organizations o       on o.id = r.organization_id
join public.segments sg           on sg.code = o.segment_code
left join public.contacts c       on c.id = r.contact_id
left join public.team_members tm  on tm.id = r.owner_id
left join lateral (
  select p.stage, p.funded_aum from public.opportunities p where p.rfp_id = r.id
   order by p.opened_on desc limit 1) op on true;
