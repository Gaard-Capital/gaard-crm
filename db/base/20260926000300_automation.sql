-- =====================================================================
-- GAARD Capital CRM · Migration 3 of 6 · Automation
--
-- The rules Jon does by hand today, done by the database:
--   * duplicate keys + flag rules (university, do-not-contact) on save
--   * outreach emails start as "No response"
--   * a confirmed outcome sets the next outreach date and the reminder
--     (OOO -> 2 weeks, "check back in October" -> Oct 1, no reply -> quarterly)
--   * call booked -> opportunity opened + added to the quarterly newsletter
--   * unsubscribe -> do-not-contact, and outreach to that person is blocked
--   * RFP status changes flow into the pipeline
--
-- The mock-data seed sets app.seeding = 'on' so these rules do not fire
-- while history is being loaded (the seed already contains the results).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------

create or replace function public.automation_enabled() returns boolean
language sql stable set search_path = '' as $$
  select coalesce(current_setting('app.seeding', true), 'off') <> 'on'
$$;

-- the team works in Mountain time; dates are taken in that zone
create or replace function public.local_date(p timestamptz) returns date
language sql stable set search_path = '' as $$
  select (p at time zone 'America/Denver')::date
$$;

create or replace function public.local_today() returns date
language sql stable set search_path = '' as $$
  select (now() at time zone 'America/Denver')::date
$$;

create or replace function public.stage_rank(p_stage text) returns int
language sql stable set search_path = '' as $$
  select sort_order from public.pipeline_stages where code = p_stage
$$;

create or replace function public.add_to_newsletter(p_contact_id bigint, p_on date, p_via text) returns void
language sql set search_path = '' as $$
  update public.contacts
     set newsletter_status = 'subscribed', newsletter_added_on = p_on, newsletter_added_via = p_via
   where id = p_contact_id and newsletter_status = 'not_subscribed' and not do_not_contact;
$$;

create or replace function public.set_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;


-- ---------------------------------------------------------------------
-- Organizations: flag rules on save
-- ---------------------------------------------------------------------

create or replace function public.organizations_before_write() returns trigger
language plpgsql set search_path = public as $$
declare
  r        flag_rules;
  v_domain text := norm_domain(new.website);
  v_key    text := norm_org_name(new.name);
begin
  if (select party_type from segments where code = new.segment_code) = 'individual' then
    raise exception 'Segment % is for individuals. Add the person as a contact without an organization.', new.segment_code;
  end if;

  for r in select * from flag_rules where is_active loop
    if (r.match_on = 'org_name' and v_key like '%' || norm_org_name(r.pattern) || '%')
       or (r.match_on = 'email_domain' and domain_matches(v_domain, r.pattern)) then
      if r.flag = 'university' then
        new.is_university_affiliated := true;
      elsif not new.do_not_contact then
        new.do_not_contact := true;
        new.dnc_reason := coalesce(new.dnc_reason, r.reason, 'Matches the do-not-contact list');
      end if;
    end if;
  end loop;

  if not new.do_not_contact then new.dnc_reason := null; end if;
  if tg_op = 'UPDATE' then new.updated_at := now(); end if;
  return new;
end $$;

-- when an organization gets flagged, its people inherit the flag
create or replace function public.organizations_after_write() returns trigger
language plpgsql set search_path = public as $$
begin
  if (new.do_not_contact and not old.do_not_contact)
     or (new.is_university_affiliated and not old.is_university_affiliated) then
    update contacts set updated_at = now() where organization_id = new.id;   -- re-runs contacts_before_write
  end if;
  return null;
end $$;

create trigger organizations_before_write before insert or update on public.organizations
  for each row execute function public.organizations_before_write();
create trigger organizations_after_write after update on public.organizations
  for each row execute function public.organizations_after_write();


-- ---------------------------------------------------------------------
-- Contacts: defaults from the organization + flag rules on save
-- ---------------------------------------------------------------------

create or replace function public.contacts_before_write() returns trigger
language plpgsql set search_path = public as $$
declare
  o        organizations;
  r        flag_rules;
  v_email  text := norm_email(new.email);
  v_domain text := nullif(split_part(norm_email(new.email), '@', 2), '');
  v_li     text := norm_linkedin(new.linkedin_url);
begin
  if new.organization_id is not null then
    select * into o from organizations where id = new.organization_id;
    new.segment_code := coalesce(new.segment_code, o.segment_code);
    new.state        := coalesce(new.state, o.state);
    new.city         := coalesce(new.city, o.city);
    if o.do_not_contact and not new.do_not_contact then
      new.do_not_contact := true;
      new.dnc_reason := coalesce(new.dnc_reason, 'Organization is on the do-not-contact list: ' || coalesce(o.dnc_reason, 'no reason given'));
    end if;
    if o.is_university_affiliated then new.is_university_affiliated := true; end if;
  end if;

  for r in select * from flag_rules where is_active loop
    if (r.match_on = 'email_domain' and domain_matches(v_domain, r.pattern))
       or (r.match_on = 'email'    and v_email = norm_email(r.pattern))
       or (r.match_on = 'linkedin' and v_li    = norm_linkedin(r.pattern)) then
      if r.flag = 'university' then
        new.is_university_affiliated := true;
      elsif not new.do_not_contact then
        new.do_not_contact := true;
        new.dnc_reason := coalesce(new.dnc_reason, r.reason, 'Matches the do-not-contact list');
      end if;
    end if;
  end loop;

  if new.do_not_contact then
    new.dnc_on := coalesce(new.dnc_on, local_today());
    if new.newsletter_status = 'subscribed' then new.newsletter_status := 'unsubscribed'; end if;
  else
    new.dnc_on := null;
    new.dnc_reason := null;
  end if;

  -- a corrected email address starts fresh (off the wrong-email list)
  if tg_op = 'UPDATE' and v_email is distinct from norm_email(old.email)
     and new.email_status = old.email_status and new.email_status in ('bounced', 'wrong_person') then
    new.email_status := 'unverified';
  end if;

  if tg_op = 'UPDATE' then new.updated_at := now(); end if;
  return new;
end $$;

-- fixing the email or phone closes the "fix contact info" reminder
create or replace function public.contacts_after_update() returns trigger
language plpgsql set search_path = public as $$
begin
  if automation_enabled()
     and (norm_email(new.email) is distinct from norm_email(old.email) or new.phone is distinct from old.phone) then
    update reminders set status = 'done', completed_at = now()
     where contact_id = new.id and reminder_type = 'fix_contact_info' and status in ('open', 'snoozed');
  end if;
  return null;
end $$;

create trigger contacts_before_write before insert or update on public.contacts
  for each row execute function public.contacts_before_write();
create trigger contacts_after_update after update on public.contacts
  for each row execute function public.contacts_after_update();


-- ---------------------------------------------------------------------
-- Touchpoints: guard rails before save
-- ---------------------------------------------------------------------

create or replace function public.touchpoints_before_write() returns trigger
language plpgsql set search_path = public as $$
declare
  c  contacts;
  tt touch_types;
  o  outcomes;
begin
  select * into c  from contacts    where id   = new.contact_id;
  select * into tt from touch_types where code = new.touch_type;
  new.organization_id := coalesce(new.organization_id, c.organization_id);
  new.owner_id        := coalesce(new.owner_id, c.owner_id);

  -- do-not-contact: block new emails / calls after someone is flagged
  if tg_op = 'INSERT' and new.direction = 'outbound' and new.touch_type in ('email', 'call', 'check_in')
     and c.do_not_contact and (c.dnc_on is null or local_date(new.touched_at) > c.dnc_on) then
    raise exception 'DO NOT CONTACT: % is on the do-not-contact list (%)',
                    coalesce(c.full_name, c.email), coalesce(c.dnc_reason, 'no reason given')
      using hint = 'Remove the flag on the contact, or the matching flag rule, if this is intentional.';
  end if;

  -- outreach emails start as "No response" until a reply comes in
  if new.outcome_code is null and new.direction = 'outbound' and new.touch_type in ('email', 'check_in') then
    new.outcome_code := 'NO_RESPONSE';
  end if;

  -- the outcome has to fit the kind of touch
  if new.outcome_code is not null then
    select * into o from outcomes where code = new.outcome_code;
    if not (new.touch_type = any (o.applies_to)) then
      raise exception 'Outcome "%" cannot be used on a "%" touch (allowed on: %)',
                      o.label, tt.name, array_to_string(o.applies_to, ', ');
    end if;
  end if;
  if new.ai_suggested_outcome is not null and not exists (
       select 1 from outcomes where code = new.ai_suggested_outcome and new.touch_type = any (applies_to)) then
    raise exception 'Suggested outcome % does not fit a "%" touch', new.ai_suggested_outcome, tt.name;
  end if;

  -- a person confirmed a suggested outcome
  if tg_op = 'UPDATE' and new.outcome_status = 'confirmed' and old.outcome_status = 'needs_review' then
    new.confirmed_at := coalesce(new.confirmed_at, now());
  end if;

  if tg_op = 'UPDATE' then new.updated_at := now(); end if;
  return new;
end $$;

create trigger touchpoints_before_write before insert or update on public.touchpoints
  for each row execute function public.touchpoints_before_write();


-- ---------------------------------------------------------------------
-- The outcome rules (runs after a touchpoint's outcome is confirmed)
-- ---------------------------------------------------------------------

create or replace function public.apply_outcome_rules(p_touch public.touchpoints) returns void
language plpgsql set search_path = public as $$
declare
  o          outcomes;
  c          contacts;
  seg        segments;
  tt         touch_types;
  v_day      date := local_date(p_touch.touched_at);
  v_label    text;
  v_dnc      boolean;
  v_due      date;
  v_opp      opportunities;
  v_latest   boolean;
  v_streak   int;
begin
  select * into o   from outcomes    where code = p_touch.outcome_code;
  if not found then return; end if;
  select * into c   from contacts    where id   = p_touch.contact_id;
  select * into seg from segments    where code = c.segment_code;
  select * into tt  from touch_types where code = p_touch.touch_type;
  v_label := coalesce(c.full_name, c.email, 'Contact #' || c.id)
             || coalesce(' (' || (select name from organizations where id = c.organization_id) || ')', '');

  -- 1. contact flags ----------------------------------------------------
  if o.sets_do_not_contact then
    update contacts
       set do_not_contact = true,
           dnc_reason     = coalesce(dnc_reason, o.label),
           dnc_on         = coalesce(dnc_on, v_day)
     where id = c.id;
    update reminders set status = 'dismissed', completed_at = now()
     where contact_id = c.id and status in ('open', 'snoozed');
  end if;

  if p_touch.touch_type in ('email', 'check_in') then
    if o.marks_email_bad then
      update contacts set email_status = 'bounced' where id = c.id;
    elsif o.code = 'WRONG_PERSON' then
      update contacts set email_status = 'wrong_person' where id = c.id;
    elsif o.counts_as_response then
      update contacts set email_status = 'valid' where id = c.id and email_status <> 'valid';
    end if;
  end if;

  if o.adds_to_newsletter then
    perform add_to_newsletter(c.id, v_day, 'auto: ' || o.label);
  end if;

  v_dnc := c.do_not_contact or o.sets_do_not_contact;

  -- 2. next outreach date = the reminder ----------------------------------
  -- only the most recent touch sets the cadence (back-filled history does not)
  v_latest := not exists (
    select 1 from touchpoints t
     where t.contact_id = c.id and t.id <> p_touch.id and t.touched_at > p_touch.touched_at);

  if v_latest then
    update reminders set status = 'superseded', completed_at = now()
     where contact_id = c.id and status in ('open', 'snoozed')
       and reminder_type in ('follow_up', 'ooo_follow_up', 'post_call', 'event_follow_up',
                             'referral_follow_up', 'check_in');

    if o.reminder_type is not null and not v_dnc then
      -- e.g. the 3rd unanswered dial in a row: stop calling weekly, go back to quarterly
      if o.retry_limit is not null then
        select count(*) into v_streak
          from touchpoints t join outcomes x on x.code = t.outcome_code
         where t.contact_id = c.id and t.touch_type = p_touch.touch_type and x.retry_limit is not null
           and t.touched_at <= p_touch.touched_at
           and t.touched_at > coalesce((select max(t2.touched_at) from touchpoints t2
                                          join outcomes x2 on x2.code = t2.outcome_code
                                         where t2.contact_id = c.id and x2.retry_limit is null
                                           and t2.touched_at <= p_touch.touched_at), '-infinity');
      end if;
      v_due := coalesce(
        p_touch.follow_up_on,                                                   -- "check back in October"
        case when o.code = 'OUT_OF_OFFICE' then p_touch.ooo_return_on + 1 end, -- back from vacation
        case when v_streak >= o.retry_limit then v_day + o.after_limit_days end,
        v_day + o.next_outreach_days);                                          -- default cadence
      if v_due is not null then
        insert into reminders (reminder_type, contact_id, organization_id, touchpoint_id, due_on,
                               title, details, follow_up_style, assigned_to)
        values (o.reminder_type, c.id, c.organization_id, p_touch.id, v_due,
                (select label from reminder_types where code = o.reminder_type) || ': ' || v_label,
                'Last outcome: ' || o.label || ' (' || tt.name || ', ' || to_char(v_day, 'Mon DD, YYYY') || ')'
                  || coalesce(E'\n' || p_touch.notes, ''),
                c.follow_up_style, c.owner_id);
      end if;
    end if;
  end if;

  -- 3. pipeline -----------------------------------------------------------
  if o.sets_stage is not null then
    -- the open opportunity for this person, or for their organization
    select * into v_opp from opportunities op
     where op.stage not in ('funded', 'lost')
       and (op.contact_id = c.id
            or (seg.party_type = 'organization' and c.organization_id is not null
                and op.organization_id = c.organization_id))
     order by (op.contact_id = c.id) desc, op.opened_on desc
     limit 1;

    if found then
      if o.sets_stage = 'lost' then
        update opportunities
           set stage = 'lost', closed_on = coalesce(closed_on, v_day), lost_reason = coalesce(lost_reason, o.label)
         where id = v_opp.id;
      else
        update opportunities
           set stage = case when stage_rank(o.sets_stage) > stage_rank(v_opp.stage) then o.sets_stage else stage end,
               first_call_on = coalesce(first_call_on, case when p_touch.touch_type = 'meeting' then v_day end),
               hot_on = case when o.sets_stage = 'hot' then coalesce(hot_on, v_day) else hot_on end,
               onboarding_started_on = case when o.sets_stage = 'onboarding'
                                            then coalesce(onboarding_started_on, v_day) else onboarding_started_on end
         where id = v_opp.id;
      end if;
    elsif o.sets_stage <> 'lost' then
      -- a call was just booked: open the opportunity
      insert into opportunities (contact_id, organization_id, segment_code, state, stage,
                                 source_channel_code, converting_channel_code, converting_touchpoint_id,
                                 source_event_id, rfp_id, opened_on, first_call_on, hot_on,
                                 onboarding_started_on, owner_id)
      values (c.id,
              case when seg.party_type = 'organization' then c.organization_id end,
              c.segment_code, c.state, o.sets_stage,
              coalesce(c.source_channel_code, tt.channel_code, 'COLD_EMAIL'),
              tt.channel_code, p_touch.id, c.source_event_id, p_touch.rfp_id, v_day,
              case when p_touch.touch_type = 'meeting' then v_day else p_touch.follow_up_on end,
              case when o.sets_stage = 'hot' then v_day end,
              case when o.sets_stage = 'onboarding' then v_day end,
              c.owner_id);
    end if;
  end if;
end $$;

create or replace function public.touchpoints_after_write() returns trigger
language plpgsql set search_path = public as $$
begin
  if not automation_enabled() then return null; end if;
  if new.outcome_status = 'confirmed' and new.outcome_code is not null and (
       tg_op = 'INSERT'
       or old.outcome_code   is distinct from new.outcome_code
       or old.outcome_status is distinct from new.outcome_status
       or old.follow_up_on   is distinct from new.follow_up_on
       or old.ooo_return_on  is distinct from new.ooo_return_on) then
    perform apply_outcome_rules(new);
  end if;
  return null;
end $$;

create trigger touchpoints_after_write after insert or update on public.touchpoints
  for each row execute function public.touchpoints_after_write();


-- ---------------------------------------------------------------------
-- Opportunities: defaults, stage dates, newsletter
-- ---------------------------------------------------------------------

create or replace function public.opportunities_before_write() returns trigger
language plpgsql set search_path = public as $$
declare
  c   contacts;
  seg segments;
begin
  select * into c from contacts where id = new.contact_id;
  new.segment_code := coalesce(new.segment_code, c.segment_code);
  new.state        := coalesce(new.state, c.state);
  select * into seg from segments where code = new.segment_code;

  if tg_op = 'INSERT' then
    if new.organization_id is null and seg.party_type = 'organization' then
      new.organization_id := c.organization_id;
    end if;
    new.source_channel_code := coalesce(new.source_channel_code, c.source_channel_code, new.converting_channel_code);
    new.source_event_id     := coalesce(new.source_event_id, c.source_event_id);
    new.owner_id            := coalesce(new.owner_id, c.owner_id);
    new.opened_on           := coalesce(new.opened_on, local_today());
  end if;

  -- moving the stage by hand stamps the milestone date
  if tg_op = 'UPDATE' and new.stage is distinct from old.stage then
    case new.stage
      when 'hot'        then new.hot_on                := coalesce(new.hot_on, local_today());
      when 'onboarding' then new.onboarding_started_on := coalesce(new.onboarding_started_on, local_today());
      when 'funded'     then new.funded_on             := coalesce(new.funded_on, local_today());
      when 'lost'       then new.closed_on             := coalesce(new.closed_on, local_today());
      else null;
    end case;
  end if;
  if new.stage = 'funded' then new.closed_on := coalesce(new.closed_on, new.funded_on); end if;

  if tg_op = 'UPDATE' then new.updated_at := now(); end if;
  return new;
end $$;

-- Jon: "every time we have a call with someone, we want to put them on
-- this quarterly newsletter list"
create or replace function public.opportunities_after_insert() returns trigger
language plpgsql set search_path = public as $$
begin
  if automation_enabled() then
    perform add_to_newsletter(new.contact_id, new.opened_on, 'auto: call booked');
  end if;
  return null;
end $$;

create trigger opportunities_before_write before insert or update on public.opportunities
  for each row execute function public.opportunities_before_write();
create trigger opportunities_after_insert after insert on public.opportunities
  for each row execute function public.opportunities_after_insert();


-- ---------------------------------------------------------------------
-- RFPs: deadline reminders, and status changes flow into the pipeline
-- ---------------------------------------------------------------------

create or replace function public.rfps_after_write() returns trigger
language plpgsql set search_path = public as $$
declare
  v_outcome text;
  v_on      date;
begin
  if not automation_enabled() then return null; end if;

  if new.status in ('identified', 'intent_to_bid') and new.due_on is not null then
    update reminders set due_on = new.due_on - 7
     where rfp_id = new.id and reminder_type = 'rfp_deadline' and status in ('open', 'snoozed');
    if not found then
      insert into reminders (reminder_type, rfp_id, organization_id, contact_id, due_on, title, details, assigned_to)
      values ('rfp_deadline', new.id, new.organization_id, new.contact_id, new.due_on - 7,
              'RFP due ' || to_char(new.due_on, 'Mon DD') || ': ' || new.title,
              'Response due ' || to_char(new.due_on, 'Mon DD, YYYY') || '. Reminder set a week ahead.',
              new.owner_id);
    end if;
  else
    update reminders set status = 'done', completed_at = now()
     where rfp_id = new.id and reminder_type = 'rfp_deadline' and status in ('open', 'snoozed');
  end if;

  if tg_op = 'UPDATE' and new.status is distinct from old.status and new.contact_id is not null then
    v_outcome := case new.status when 'submitted' then 'RFP_SUBMITTED' when 'finalist' then 'RFP_FINALIST'
                                 when 'won' then 'RFP_WON' when 'lost' then 'RFP_LOST' end;
    if v_outcome is not null then
      v_on := case when new.status = 'submitted' then coalesce(new.submitted_on, local_today())
                   else coalesce(new.decision_on, local_today()) end;
      insert into touchpoints (contact_id, organization_id, touch_type, direction, touched_at, rfp_id,
                               outcome_code, notes, owner_id)
      values (new.contact_id, new.organization_id, 'rfp', 'outbound',
              (v_on + time '12:00') at time zone 'America/Denver', new.id, v_outcome,
              'RFP status changed to ' || new.status || ': ' || new.title, new.owner_id);
    end if;
  end if;
  return null;
end $$;

create trigger rfps_set_updated_at before update on public.rfps
  for each row execute function public.set_updated_at();
create trigger rfps_after_write after insert or update on public.rfps
  for each row execute function public.rfps_after_write();


-- ---------------------------------------------------------------------
-- Functions the app calls (review queue, notifications tab)
-- ---------------------------------------------------------------------

-- Review queue: accept the suggested outcome (or pick another) in one click
create or replace function public.confirm_outcome(
  p_touchpoint_id bigint,
  p_outcome_code  text   default null,     -- NULL = accept the suggestion
  p_follow_up_on  date   default null,     -- e.g. the "check back in October" date
  p_confirmed_by  bigint default null
) returns public.touchpoints
language plpgsql set search_path = public as $$
declare
  t touchpoints;
begin
  update touchpoints
     set outcome_code   = coalesce(p_outcome_code, ai_suggested_outcome, outcome_code),
         follow_up_on   = coalesce(p_follow_up_on, follow_up_on),
         outcome_status = 'confirmed',
         confirmed_by   = p_confirmed_by,
         confirmed_at   = now()
   where id = p_touchpoint_id
  returning * into t;
  if not found then raise exception 'Touchpoint % not found', p_touchpoint_id; end if;
  return t;
end $$;

-- Notifications tab: done for one person = done for everyone
create or replace function public.complete_reminder(p_reminder_id bigint, p_by bigint default null) returns void
language sql set search_path = '' as $$
  update public.reminders set status = 'done', completed_by = p_by, completed_at = now()
   where id = p_reminder_id and status in ('open', 'snoozed');
$$;

create or replace function public.snooze_reminder(p_reminder_id bigint, p_until date) returns void
language sql set search_path = '' as $$
  update public.reminders set status = 'snoozed', snoozed_until = p_until, due_on = p_until
   where id = p_reminder_id and status in ('open', 'snoozed');
$$;

-- Daily job: snoozed reminders come back
create or replace function public.wake_snoozed_reminders() returns int
language plpgsql set search_path = public as $$
declare n int;
begin
  update reminders set status = 'open', snoozed_until = null
   where status = 'snoozed' and snoozed_until <= local_today();
  get diagnostics n = row_count;
  return n;
end $$;

-- Weekly job: open opportunities nobody has touched in a while
create or replace function public.flag_stale_opportunities(p_days int default 21) returns int
language plpgsql set search_path = public as $$
declare n int;
begin
  insert into reminders (reminder_type, contact_id, organization_id, opportunity_id, due_on, title, details,
                         assigned_to, created_by)
  select case when op.stage = 'onboarding' then 'onboarding_task' else 'post_call' end,
         op.contact_id, op.organization_id, op.id, local_today(),
         'No activity in ' || p_days || ' days: ' || coalesce(c.full_name, c.email)
           || coalesce(' (' || o.name || ')', ''),
         'Stage: ' || ps.label || '. Last touch: ' || coalesce(to_char(lt.last_at, 'Mon DD, YYYY'), 'none'),
         op.owner_id, 'system: stale check'
    from opportunities op
    join contacts c          on c.id = op.contact_id
    join pipeline_stages ps  on ps.code = op.stage
    left join organizations o on o.id = op.organization_id
    left join lateral (
      select max(t.touched_at) as last_at from touchpoints t
       where t.contact_id = op.contact_id
          or (op.organization_id is not null and t.organization_id = op.organization_id)) lt on true
   where op.stage in ('call', 'hot', 'onboarding')
     and coalesce(lt.last_at, op.opened_on::timestamptz) < now() - make_interval(days => p_days)
     and not exists (select 1 from reminders r
                      where r.status in ('open', 'snoozed')
                        and (r.opportunity_id = op.id or r.contact_id = op.contact_id));
  get diagnostics n = row_count;
  return n;
end $$;

-- After the one-time migration from the sheets (imported with p_run_automation => false):
-- give everyone the follow-up their latest outcome calls for, in one pass
create or replace function public.rebuild_follow_up_reminders() returns int
language plpgsql set search_path = public as $$
declare
  t touchpoints;
  n int := 0;
begin
  for t in
    select distinct on (tp.contact_id) tp.*
      from touchpoints tp
     where tp.outcome_status = 'confirmed' and tp.outcome_code is not null
       and not exists (select 1 from reminders r where r.contact_id = tp.contact_id and r.status in ('open', 'snoozed'))
     order by tp.contact_id, tp.touched_at desc, tp.id desc
  loop
    perform apply_outcome_rules(t);
    n := n + 1;
  end loop;
  return n;
end $$;

-- After loading Jon's flag list: re-check everyone against the rules
create or replace function public.reapply_flag_rules() returns int
language plpgsql set search_path = public as $$
declare n int;
begin
  update organizations set name = name;   -- re-runs organizations_before_write
  update contacts set email = email;      -- re-runs contacts_before_write
  get diagnostics n = row_count;
  return n;
end $$;
