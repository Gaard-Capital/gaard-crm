-- =====================================================================
-- GAARD Capital CRM · Migration 9 of 9 · Review helpers
--
-- After the workbook import, 275 touchpoints sat in v_outcome_review_queue
-- with free-text outcomes the matcher could not place. These helpers
-- cleared the queue to 2 and rebuilt the follow-ups:
--
-- 1. outcome_aliases.force_review  an alias that is a hint, not a verdict:
--    it suggests the outcome but a person still confirms it
-- 2. match_outcome()               returns that flag
-- 3. rematch_outcomes()            re-runs the matcher over every touchpoint
--    still waiting for review, after new aliases are added
-- 4. merge_contacts(keep, remove)  the same person twice -> one row, with
--    every touch, reminder, opportunity and email moved across
-- 5. rebuild_follow_up_reminders() one open follow-up per organization (or
--    individual), from the latest touch; explicit dates first, then the cadence
-- 6. spread_overdue_follow_ups(n)  re-dates the overdue backlog over n weeks
--
-- First run in the Supabase SQL Editor on Oct 3, 2026; this file was
-- rebuilt from the live schema on Oct 14, 2026.
-- =====================================================================

alter table public.outcome_aliases
  add column if not exists force_review boolean not null default false;
comment on column public.outcome_aliases.force_review is 'true: the phrase only suggests the outcome; the touchpoint still goes to the review queue';

-- the return type gains a column, so the old version has to go first
drop function if exists public.match_outcome(text);
create or replace function public.match_outcome(p_text text, OUT outcome_code text, OUT is_exact boolean, OUT phrase text, OUT force_review boolean) RETURNS record
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $_$
  select a.outcome_code,
         norm_text(regexp_replace(p_text, '[\s.!]+$', '')) = a.phrase and not a.force_review,
         a.phrase,
         a.force_review
    from outcome_aliases a
   where norm_text(p_text) ~ ('\m' || regexp_replace(a.phrase, '([.^$*+?()\[\]{}|\\])', '\\\1', 'g') || '\M')
   order by length(a.phrase) desc
   limit 1
$_$;

create or replace function public.rematch_outcomes() RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public', 'extensions'
    AS $$
declare
  t        record;
  m        record;
  n_conf   int := 0;
  n_sugg   int := 0;
  n_rem    int;
begin
  perform set_config('app.history_load', 'on', true);       -- facts yes, reminders at the end
  for t in
    select tp.id, tp.touch_type, tp.outcome_raw, tp.ai_suggested_outcome
      from touchpoints tp
     where tp.outcome_status = 'needs_review' and nullif(trim(tp.outcome_raw), '') is not null
     order by tp.touched_at, tp.id
  loop
    select * into m from match_outcome(t.outcome_raw);
    continue when m.outcome_code is null
              or not exists (select 1 from outcomes o where o.code = m.outcome_code and t.touch_type = any (o.applies_to));
    if m.is_exact then
      update touchpoints
         set outcome_code = m.outcome_code, outcome_status = 'confirmed',
             ai_suggested_outcome = null, ai_confidence = null,
             ai_reason = format('Matched "%s" (alias added after the import)', m.phrase),
             confirmed_at = now()
       where id = t.id;
      n_conf := n_conf + 1;
    elsif t.ai_suggested_outcome is distinct from m.outcome_code then
      update touchpoints
         set ai_suggested_outcome = m.outcome_code, ai_confidence = 0.6,
             ai_reason = format('Matched "%s" in the sheet', m.phrase)
       where id = t.id;
      n_sugg := n_sugg + 1;
    end if;
  end loop;
  perform set_config('app.history_load', 'off', true);
  n_rem := rebuild_follow_up_reminders();
  return jsonb_build_object(
    'confirmed',        n_conf,
    'new_suggestions',  n_sugg,
    'still_in_review',  (select count(*) from touchpoints where outcome_status = 'needs_review'),
    'follow_ups_built', n_rem);
end $$;

create or replace function public.merge_contacts(p_keep bigint, p_remove bigint) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  k contacts;
  r contacts;
  v_moved_touches int; v_moved_reminders int; v_moved_opps int := 0; v_dropped_opps int := 0;
begin
  if p_keep = p_remove then raise exception 'keep and remove are the same contact'; end if;
  select * into k from contacts where id = p_keep;
  if not found then raise exception 'Contact % (keep) not found', p_keep; end if;
  select * into r from contacts where id = p_remove;
  if not found then raise exception 'Contact % (remove) not found', p_remove; end if;

  update touchpoints set contact_id = p_keep,
         organization_id = coalesce(k.organization_id, organization_id)
   where contact_id = p_remove;
  get diagnostics v_moved_touches = row_count;

  update reminders set contact_id = p_keep,
         organization_id = coalesce(k.organization_id, organization_id)
   where contact_id = p_remove;
  get diagnostics v_moved_reminders = row_count;

  update email_messages set contact_id = p_keep where contact_id = p_remove;
  update import_rows set contact_id = p_keep where contact_id = p_remove;
  update import_rows set review_candidate_contact_id = p_keep where review_candidate_contact_id = p_remove;
  update contacts set referred_by_contact_id = p_keep where referred_by_contact_id = p_remove;

  -- opportunities: at most one open per person; a duplicate open deal is folded into the kept one
  if exists (select 1 from opportunities where contact_id = p_remove and stage not in ('funded', 'lost'))
     and exists (select 1 from opportunities where contact_id = p_keep and stage not in ('funded', 'lost')) then
    update opportunities o
       set notes = concat_ws(E'\n', o.notes, 'Merged a duplicate open opportunity from contact #' || p_remove
                                               || coalesce(': ' || d.notes, ''))
      from opportunities d
     where o.contact_id = p_keep and o.stage not in ('funded', 'lost')
       and d.contact_id = p_remove and d.stage not in ('funded', 'lost');
    update reminders set opportunity_id = (select id from opportunities where contact_id = p_keep and stage not in ('funded', 'lost') limit 1)
     where opportunity_id in (select id from opportunities where contact_id = p_remove and stage not in ('funded', 'lost'));
    delete from opportunities where contact_id = p_remove and stage not in ('funded', 'lost');
    get diagnostics v_dropped_opps = row_count;
  end if;
  update opportunities set contact_id = p_keep,
         organization_id = coalesce(organization_id, k.organization_id)
   where contact_id = p_remove;
  get diagnostics v_moved_opps = row_count;

  update contacts
     set first_name            = coalesce(first_name, r.first_name),
         last_name             = coalesce(last_name, r.last_name),
         title                 = coalesce(title, r.title),
         employer              = coalesce(employer, r.employer),
         email                 = coalesce(email, r.email),
         phone                 = coalesce(phone, r.phone),
         linkedin_url          = coalesce(linkedin_url, r.linkedin_url),
         linkedin_connected_on = coalesce(linkedin_connected_on, r.linkedin_connected_on),
         city                  = coalesce(city, r.city),
         state                 = coalesce(state, r.state),
         mailing_address       = coalesce(mailing_address, r.mailing_address),
         prospect_aum          = coalesce(prospect_aum, r.prospect_aum),
         source_channel_code   = coalesce(source_channel_code, r.source_channel_code),
         source_detail         = coalesce(source_detail, r.source_detail),
         sourced_on            = least(coalesce(sourced_on, r.sourced_on), coalesce(r.sourced_on, sourced_on)),
         activity_status       = coalesce(activity_status, r.activity_status),
         newsletter_status     = case when r.newsletter_status = 'subscribed' and newsletter_status = 'not_subscribed'
                                      then 'subscribed' else newsletter_status end,
         newsletter_added_on   = coalesce(newsletter_added_on, r.newsletter_added_on),
         newsletter_added_via  = coalesce(newsletter_added_via, r.newsletter_added_via),
         do_not_contact        = do_not_contact or r.do_not_contact,
         dnc_reason            = coalesce(dnc_reason, r.dnc_reason),
         tags                  = (select coalesce(array_agg(distinct x), '{}') from unnest(tags || r.tags) x),
         notes                 = concat_ws(E'\n', notes,
                                   case when r.email is not null and email is not null and norm_email(r.email) <> norm_email(email)
                                        then 'Also uses: ' || r.email end,
                                   r.notes,
                                   'Merged with contact #' || p_remove || coalesce(' (' || r.legacy_ref || ')', ''))
   where id = p_keep;

  delete from contacts where id = p_remove;
  return jsonb_build_object('kept', p_keep, 'removed', p_remove, 'touches_moved', v_moved_touches,
                            'reminders_moved', v_moved_reminders, 'opportunities_moved', v_moved_opps,
                            'duplicate_open_opportunities_folded', v_dropped_opps);
end $$;

create or replace function public.rebuild_follow_up_reminders() RETURNS integer
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  t touchpoints;
  n int := 0;
  v_types text[] := '{follow_up,ooo_follow_up,post_call,event_follow_up,referral_follow_up,check_in,fix_contact_info,find_new_contact,onboarding_task}';
begin
  -- pass 1: explicit dates
  for t in
    select distinct on (tp.contact_id) tp.*
      from touchpoints tp
      join contacts c on c.id = tp.contact_id
      left join organizations o on o.id = c.organization_id
     where tp.outcome_status = 'confirmed' and tp.outcome_code is not null and tp.follow_up_on is not null
       and not c.do_not_contact
       and coalesce(o.reach_out_again, true)
       and not exists (select 1 from touchpoints t2 where t2.contact_id = tp.contact_id and t2.touched_at > tp.touched_at)
       and not exists (select 1 from reminders r where r.contact_id = tp.contact_id
                          and r.status in ('open', 'snoozed') and r.reminder_type = any (v_types))
     order by tp.contact_id, tp.touched_at desc, tp.id desc
  loop
    perform apply_outcome_rules(t);
    n := n + 1;
  end loop;

  -- pass 2: the cadence, once per organization (or individual)
  for t in
    select distinct on (coalesce(c.organization_id, -tp.contact_id)) tp.*
      from touchpoints tp
      join contacts c on c.id = tp.contact_id
      left join organizations o on o.id = c.organization_id
     where tp.outcome_status = 'confirmed' and tp.outcome_code is not null
       and not c.do_not_contact
       and coalesce(o.reach_out_again, true)
       and not exists (
             select 1 from reminders r
             join contacts c2 on c2.id = r.contact_id
            where r.status in ('open', 'snoozed') and r.reminder_type = any (v_types)
              and (r.contact_id = tp.contact_id
                   or (c.organization_id is not null and c2.organization_id = c.organization_id)))
     order by coalesce(c.organization_id, -tp.contact_id),
              exists (select 1 from opportunities op where op.contact_id = tp.contact_id and op.stage not in ('funded', 'lost')) desc,
              tp.touched_at desc, tp.id desc
  loop
    perform apply_outcome_rules(t);
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.spread_overdue_follow_ups(p_weeks integer DEFAULT 6) RETURNS integer
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  n int;
begin
  with overdue as (
    select id, row_number() over (order by due_on, id) - 1 as rn, count(*) over () as total
      from reminders
     where status = 'open' and due_on < local_today()
       and reminder_type in ('follow_up', 'ooo_follow_up', 'post_call', 'event_follow_up', 'referral_follow_up', 'check_in')
  ),
  slots as (
    select d as day, row_number() over (order by d) - 1 as slot
      from generate_series(local_today(), local_today() + (p_weeks * 7 - 1), interval '1 day') d
     where extract(isodow from d) < 6
  )
  update reminders r
     set due_on = s.day,
         details = concat_ws(E'\n', r.details, 'Was due ' || to_char(r.due_on, 'Mon DD, YYYY') || '; re-dated with the backlog')
    from overdue o
    join slots s on s.slot = floor(o.rn * (select count(*) from slots)::numeric / greatest(o.total, 1))
   where r.id = o.id;
  get diagnostics n = row_count;
  return n;
end $$;

