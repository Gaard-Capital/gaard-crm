-- =====================================================================
-- GAARD Capital CRM · Migration 4 of 6 · Import pipeline
--
-- "We need something where we can just throw in a bunch of content and
--  then we know exactly whether or not we've already outreached to them."
--
-- 1. Put rows into import_rows (paste, CSV upload, or the app) using the
--    outreach sheet's own columns: Date, Source, Contact, First Name,
--    Email, Org, Website, LinkedIn, Added on LinkedIn, Notes,
--    Date Outreached, Outcome, Next Steps (+ optional Phone, AUM, State,
--    Segment, Title, Last Name).
-- 2. select process_import_batch(<batch id>);
-- 3. Each row comes back labelled:
--      new_contact               brand new person (and organization)
--      new_contact_existing_org  new person, organization already known;
--                                shows who was contacted there before
--      existing_contact          already in the CRM (email or LinkedIn)
--      needs_review              looks like a duplicate, a person decides
--      skipped / error           with the reason
-- Used once for the historical migration and then for every new batch.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Parsing helpers for spreadsheet text
-- ---------------------------------------------------------------------

-- '9/1/26', '09/01/2026', '2026-09-01', 'Sep 1, 2026' -> date (NULL if unreadable)
create or replace function public.parse_loose_date(p text) returns date
language plpgsql stable set search_path = '' as $$
declare
  s text := trim(coalesce(p, ''));
begin
  if s = '' then return null; end if;
  if s ~ '^\d{4}-\d{1,2}-\d{1,2}' then return to_date(substring(s from '^\d{4}-\d{1,2}-\d{1,2}'), 'YYYY-MM-DD'); end if;
  if s ~ '^\d{1,2}/\d{1,2}/\d{4}$' then return to_date(s, 'MM/DD/YYYY'); end if;
  if s ~ '^\d{1,2}/\d{1,2}/\d{2}$'  then return to_date(s, 'MM/DD/YY'); end if;
  if s ~ '^\d{1,2}/\d{1,2}$'        then return null; end if;          -- no year: too ambiguous
  return s::date;
exception when others then
  return null;
end $$;

-- '$12.5M', '12,500,000', '850k', '1.2 billion' -> numeric
create or replace function public.parse_amount(p text) returns numeric
language plpgsql immutable set search_path = '' as $$
declare
  s text;
  m text[];
begin
  s := lower(coalesce(p, ''));
  s := replace(replace(replace(s, 'billion', 'b'), 'million', 'm'), 'thousand', 'k');
  s := regexp_replace(s, '[\s$,~]|usd', '', 'g');
  m := regexp_match(s, '^(\d+(?:\.\d+)?)(k|m|mm|b|bn)?$');
  if m is null then return null; end if;
  return m[1]::numeric * case m[2] when 'k' then 1e3 when 'm' then 1e6 when 'mm' then 1e6
                                   when 'b' then 1e9 when 'bn' then 1e9 else 1 end;
end $$;

-- "Added on LinkedIn": 'Yes' / TRUE / 'x' / a date -> date connected
create or replace function public.parse_yes_or_date(p text, p_fallback date) returns date
language plpgsql stable set search_path = public as $$
declare
  s text := lower(trim(coalesce(p, '')));
begin
  if s in ('', 'no', 'n', 'false', 'f', '0', '-', 'n/a', 'na') then return null; end if;
  if s in ('yes', 'y', 'true', 't', 'x', '1', '✓', '✔', 'connected', 'added', 'done') then return p_fallback; end if;
  return coalesce(parse_loose_date(s), p_fallback);
end $$;

create or replace function public.resolve_state(p text) returns char(2)
language sql stable set search_path = '' as $$
  select code from public.us_states
   where code = upper(trim(p)) or lower(name) = lower(trim(p))
   limit 1
$$;

create or replace function public.resolve_segment(p text, p_default text) returns text
language sql stable set search_path = '' as $$
  select coalesce(
    (select code from public.segments s
      where upper(trim(p)) = s.code
         or lower(trim(p)) = lower(s.name)
         or lower(trim(p)) = any (s.aliases)
      order by s.sort_order
      limit 1),
    p_default)
$$;

-- old free-text outcome -> standardized outcome
--   is_exact = the cell is just the phrase ("No response", "No thank you")
--   otherwise the phrase was found inside longer text (a pasted reply) and a person should confirm
create or replace function public.match_outcome(p_text text, out outcome_code text, out is_exact boolean, out phrase text)
language sql stable set search_path = public as $$
  select a.outcome_code,
         norm_text(regexp_replace(p_text, '[\s.!]+$', '')) = a.phrase,
         a.phrase
    from outcome_aliases a
   where norm_text(p_text) ~ ('\m' || regexp_replace(a.phrase, '([.^$*+?()\[\]{}|\\])', '\\\1', 'g') || '\M')
   order by length(a.phrase) desc
   limit 1
$$;


-- ---------------------------------------------------------------------
-- The import
-- ---------------------------------------------------------------------

create or replace function public.process_import_batch(p_batch_id bigint, p_run_automation boolean default true)
returns jsonb
language plpgsql set search_path = public, extensions as $$
declare
  b             import_batches;
  r             import_rows;
  v_seg         segments;
  v_email       text;
  v_domain      text;
  v_li          text;
  v_first       text;
  v_last        text;
  v_name_key    text;
  v_org_key     text;
  v_web_domain  text;
  v_state       char(2);
  v_sourced     date;
  v_contact_id  bigint;
  v_org_id      bigint;
  v_other_id    bigint;
  v_matched     text;
  v_result      text;
  v_detail      text;
  v_cand_org    bigint;
  v_cand_contact bigint;
  v_force_new   boolean;
  v_touch_on    date;
  v_touch_id    bigint;
  v_out         record;
  v_suggest     text;
  v_outcome     text;
  v_status      text;
  v_flags       text;
  v_summary     jsonb;
begin
  select * into b from import_batches where id = p_batch_id for update;
  if not found then raise exception 'Import batch % not found', p_batch_id; end if;
  if not p_run_automation then
    perform set_config('app.seeding', 'on', true);          -- history back-fill: no reminders for old rows
  end if;

  for r in
    select * from import_rows
     where batch_id = p_batch_id
       and (processed_at is null or (result = 'needs_review' and review_decision is not null))
     order by row_number, id
  loop
    begin   -- each row in its own sub-transaction: one bad row never stops the batch
      v_contact_id := null; v_org_id := null; v_matched := null; v_result := null; v_detail := null;
      v_cand_org := null; v_cand_contact := null; v_touch_id := null; v_flags := '';

      if r.review_decision = 'skip' then
        update import_rows set result = 'skipped', result_detail = 'Skipped after review', processed_at = now()
         where id = r.id;
        continue;
      end if;
      v_force_new := coalesce(r.review_decision = 'create_new', false);

      v_email      := norm_email(r.email);
      v_domain     := nullif(split_part(v_email, '@', 2), '');
      v_li         := norm_linkedin(r.linkedin);
      v_first      := coalesce(nullif(trim(r.first_name), ''), nullif(split_part(trim(coalesce(r.contact, '')), ' ', 1), ''));
      v_last       := coalesce(nullif(trim(r.last_name), ''),
                               nullif(trim(regexp_replace(trim(coalesce(r.contact, '')), '^\S+\s*', '')), ''));
      v_name_key   := norm_text(coalesce(v_first, '') || ' ' || coalesce(v_last, ''));
      v_org_key    := norm_org_name(r.org);
      v_web_domain := norm_domain(r.website);
      v_state      := resolve_state(r.state);
      v_sourced    := coalesce(parse_loose_date(r.date_added), local_date(b.created_at));
      select * into v_seg from segments where code = resolve_segment(r.segment, b.default_segment_code);
      if v_seg.code is null then
        raise exception 'No segment: fill the Segment column or set default_segment_code on the batch';
      end if;
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
               linkedin_url          = coalesce(linkedin_url, nullif(trim(r.linkedin), '')),
               title                 = coalesce(title, nullif(trim(r.title), '')),
               linkedin_connected_on = coalesce(linkedin_connected_on, parse_yes_or_date(r.added_on_linkedin, v_sourced))
         where id = v_contact_id;
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
               and org_names_look_alike(name, r.org)
             order by similarity(name_key, v_org_key) desc
             limit 1;
            if v_cand_org is not null then
              update import_rows
                 set result = 'needs_review', matched_on = 'similar organization name',
                     review_candidate_org_id = v_cand_org,
                     result_detail = format('"%s" looks like existing organization "%s". Same organization?',
                                            trim(r.org), (select name from organizations where id = v_cand_org)),
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
            insert into organizations (name, segment_code, website, state, reported_aum, owner_id, source_detail, legacy_ref)
            values (trim(r.org), v_seg.code, nullif(trim(r.website), ''), coalesce(v_state, b.default_state),
                    parse_amount(r.aum), b.owner_id, nullif(trim(r.source), ''),
                    b.label || ' / row ' || coalesce(r.row_number::text, '?'))
            returning id into v_org_id;
          end if;
          v_detail := 'Added';
        end if;

        insert into contacts (organization_id, segment_code, first_name, last_name, title, employer, email, phone,
                              linkedin_url, linkedin_connected_on, state, prospect_aum, source_channel_code,
                              source_detail, source_event_id, sourced_on, owner_id, notes, legacy_ref)
        values (v_org_id, v_seg.code, v_first, v_last, nullif(trim(r.title), ''),
                case when v_seg.party_type = 'individual' then nullif(trim(r.org), '') end,
                v_email, nullif(trim(r.phone), ''), nullif(trim(r.linkedin), ''),
                parse_yes_or_date(r.added_on_linkedin, v_sourced),
                coalesce(v_state, (select state from organizations where id = v_org_id), b.default_state),
                case when v_seg.party_type = 'individual' then parse_amount(r.aum) end,
                b.default_channel_code, nullif(trim(r.source), ''), b.event_id, v_sourced, b.owner_id,
                nullif(trim(r.notes), ''), b.label || ' / row ' || coalesce(r.row_number::text, '?'))
        returning id into v_contact_id;
        if v_email is null and nullif(trim(r.email), '') is not null then
          v_detail := v_detail || format('. Email "%s" is not valid and was left blank', trim(r.email));
        end if;
      end if;

      -- flags the rules raised on this person
      select concat_ws('. ',
               case when do_not_contact then 'FLAGGED DO NOT CONTACT: ' || coalesce(dnc_reason, '') end,
               case when is_university_affiliated then 'University contact: founder may know them' end)
        into v_flags
        from contacts where id = v_contact_id;
      if coalesce(v_flags, '') <> '' then v_detail := v_detail || '. ' || v_flags; end if;

      -- 4) the outreach columns become a touchpoint
      v_touch_on := parse_loose_date(r.date_outreached);
      if v_touch_on is not null then
        select * into v_out from match_outcome(r.outcome);
        v_suggest := case when exists (select 1 from outcomes o
                                        where o.code = v_out.outcome_code and b.default_touch_type = any (o.applies_to))
                          then v_out.outcome_code end;
        if nullif(trim(coalesce(r.outcome, '')), '') is null then          -- blank = still no response
          v_outcome := case when b.default_touch_type in ('email', 'check_in') then 'NO_RESPONSE' end;
          v_status  := 'confirmed';
        elsif v_suggest is not null and v_out.is_exact then               -- a clean label
          v_outcome := v_suggest; v_status := 'confirmed';
        elsif v_suggest is not null then                                  -- phrase inside a pasted reply
          v_outcome := v_suggest; v_status := 'needs_review';
        else                                                              -- could not tell
          v_outcome := case when b.default_touch_type in ('email', 'check_in') then 'NO_RESPONSE' end;
          v_status  := 'needs_review';
        end if;

        -- re-importing the same sheet does not create the touch twice
        select id into v_touch_id from touchpoints
         where contact_id = v_contact_id and touch_type = b.default_touch_type and local_date(touched_at) = v_touch_on
         limit 1;
        if v_touch_id is null then
          insert into touchpoints (contact_id, touch_type, direction, touched_at, campaign_id, event_id,
                                   outcome_code, outcome_status, outcome_raw,
                                   ai_suggested_outcome, ai_confidence, ai_reason, notes, owner_id)
          values (v_contact_id, b.default_touch_type,
                  case when b.default_touch_type = 'event' then 'in_person' else 'outbound' end,
                  (v_touch_on + time '09:00') at time zone 'America/Denver', b.campaign_id, b.event_id,
                  v_outcome, v_status, nullif(trim(r.outcome), ''),
                  case when v_status = 'needs_review' then v_suggest end,
                  case when v_status = 'needs_review' and v_suggest is not null then 0.6 end,
                  case when v_status = 'needs_review' and v_suggest is not null
                       then format('Matched "%s" in the old Outcome text', v_out.phrase)
                       when v_status = 'needs_review' then 'Could not match the old Outcome text' end,
                  nullif(trim(r.next_steps), ''), b.owner_id)
          returning id into v_touch_id;
        end if;
      end if;

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
  return v_summary;
end $$;
