-- =====================================================================
-- GAARD Capital CRM · Migration 7 of 9 · Jon's workbook: tab profiles and the extra columns
--
-- The real outreach workbook has ten tabs, each with its own column set, and
-- the Sep 26 import pipeline only knew the outreach-sheet columns. This
-- migration teaches it the rest:
--
-- 1. import_header_aliases    every header Jon uses -> one field name
-- 2. import_tab_profiles      one row per tab: segment, channel, touch type,
--                             default outcome, follow-up days, tags, header map
-- 3. import_batches/import_rows carry those defaults, plus an `extra` jsonb
--    for columns the outreach sheet never had (city, org type, status,
--    plans served, loyalty dates ...)
-- 4. organizations / contacts get the matching columns (mailing address,
--    activity status, plans served, commissions, "reach out again?" ...)
-- 5. import_uploaded_table()  CSV table uploaded in the dashboard -> a batch
--    import_gaard_tab()       the same, driven by a tab profile
--    check_upload_headers()   says which headers it did not recognise
-- 6. history_load()           a back-fill flag: facts are recorded, but the
--    do-not-contact block and reminder superseding stand down for old rows
-- 7. process_import_batch()   rewritten to use all of the above: name-only
--    matching for tabs with no email column, the Onboarded tab -> the
--    opportunity, the Customer Loyalty tab -> card / check-in reminders
--
-- First run in the Supabase SQL Editor on Oct 3, 2026; this file was
-- rebuilt from the live schema on Oct 14, 2026.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Columns the workbook needs
-- ---------------------------------------------------------------------
alter table public.channels
  add column if not exists aliases text[] not null default '{}';

alter table public.contacts
  add column if not exists activity_status text,
  add column if not exists mailing_address text;
do $$ begin
  alter table public.contacts
    add constraint contacts_activity_status_check check (activity_status in ('active', 'dormant'));
exception when duplicate_object then null; end $$;
COMMENT ON COLUMN public.contacts.activity_status IS 'Next Step / Individuals tabs "Active/Dorm": active = still being worked, dormant = parked';

alter table public.organizations
  add column if not exists plans_served          integer,
  add column if not exists commissions           numeric(14,2),
  add column if not exists shared_employers      text,
  add column if not exists advertises_retirement boolean,
  add column if not exists reach_out_again       boolean,
  add column if not exists no_reach_out_reason   text,
  add column if not exists mailing_address       text;
COMMENT ON COLUMN public.organizations.org_type IS 'Sub-type: human services, community foundation, Benefit group ...; service line for an affiliate (Affiliates: "Services"); industry for a small business';
COMMENT ON COLUMN public.organizations.reported_aum IS 'AUM from sourcing (Form 990, website, research); plan assets for a 401(k) prospect (Small Biz: "PlanAssets")';
COMMENT ON COLUMN public.organizations.employee_count IS 'Headcount, or plan participants for a 401(k) prospect (Small Biz: "Participants")';
COMMENT ON COLUMN public.organizations.reach_out_again IS 'Master list "Reach Out Again?": false = do not re-source this organization next year (not the same as do-not-contact)';

alter table public.import_batches
  add column if not exists default_org_type        text,
  add column if not exists default_outcome_code    text references public.outcomes(code),
  add column if not exists default_follow_up_days  integer,
  add column if not exists tags                    text[]  not null default '{}',
  add column if not exists match_by_name           boolean not null default false,
  add column if not exists header_map              jsonb   not null default '{}',
  add column if not exists history_load            boolean not null default true;

alter table public.import_rows
  add column if not exists follow_up_on text,
  add column if not exists extra_notes  text,
  add column if not exists extra        jsonb not null default '{}';

-- ---------------------------------------------------------------------
-- 2. Header aliases and tab profiles
-- ---------------------------------------------------------------------
create table if not exists public.import_header_aliases (
    header_key text not null,
    field text not null,                 -- the import_rows column (or extra ->> key) this header feeds
    constraint import_header_aliases_field_check check ((field = any (array['date_added'::text, 'source'::text, 'contact'::text, 'first_name'::text, 'last_name'::text, 'title'::text, 'email'::text, 'org'::text, 'website'::text, 'linkedin'::text, 'added_on_linkedin'::text, 'phone'::text, 'aum'::text, 'state'::text, 'segment'::text, 'notes'::text, 'date_outreached'::text, 'outcome'::text, 'next_steps'::text, 'follow_up_on'::text, 'extra_notes'::text, 'city'::text, 'org_type'::text, 'channel'::text, 'status'::text, 'response_notes'::text, 'activity_status'::text, 'newsletter'::text, 'mailing_address'::text, 'reach_out_again'::text, 'no_reach_out_reason'::text, 'plans_served'::text, 'commissions'::text, 'shared_employers'::text, 'advertises_retirement'::text, 'employee_count'::text, 'onboarding_sent_on'::text, 'funded_on'::text, 'outcome_2'::text, 'loyalty_thanksgiving'::text, 'loyalty_referral_1'::text, 'loyalty_referral_2'::text, 'loyalty_referral_3'::text, 'date_source_approved'::text, 'new_contact'::text, 'new_first_name'::text, 'new_email'::text, 'new_org'::text, 'new_website'::text, 'new_linkedin'::text, 'new_notes'::text, 'campaign'::text, 'ignore'::text])))
);
alter table public.import_header_aliases add constraint import_header_aliases_pkey primary key (header_key);
comment on table public.import_header_aliases is 'Every column header Jon''s tabs use, normalised, -> the field it feeds. ''ignore'' drops the column.';

create table if not exists public.import_tab_profiles (
    tab text not null,
    description text,
    segment text,
    channel_code text default 'COLD_EMAIL'::text not null,
    touch_type text default 'email'::text not null,
    org_type text,
    default_outcome_code text,
    follow_up_days integer,
    tags text[] default '{}'::text[] not null,
    match_by_name boolean default false not null,
    header_map jsonb default '{}'::jsonb not null,
    prep_notes text,
    sort_order integer default 0 not null
);
alter table public.import_tab_profiles add constraint import_tab_profiles_pkey primary key (tab);
alter table public.import_tab_profiles
  add constraint import_tab_profiles_channel_code_fkey foreign key (channel_code) references public.channels(code),
  add constraint import_tab_profiles_default_outcome_code_fkey foreign key (default_outcome_code) references public.outcomes(code),
  add constraint import_tab_profiles_touch_type_fkey foreign key (touch_type) references public.touch_types(code);
comment on table public.import_tab_profiles is 'One row per workbook tab: how import_gaard_tab() should read it. The rows are in migration 10.';

-- same access rule as every other table (migration 6)
do $$
declare t text;
begin
  foreach t in array array['import_header_aliases', 'import_tab_profiles'] loop
    execute format('alter table public.%I enable row level security', t);
    if to_regprocedure('public.is_team_member()') is not null then
      execute format('drop policy if exists team_access on public.%I', t);
      execute format('create policy team_access on public.%I for all to authenticated '
                     'using (public.is_team_member()) with check (public.is_team_member())', t);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 3. Helpers
-- ---------------------------------------------------------------------
create or replace function public.history_load() RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select coalesce(current_setting('app.history_load', true), 'off') = 'on'
$$;

create or replace function public.parse_yes_no(p text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select case
    when lower(trim(coalesce(p, ''))) in ('yes', 'y', 'true', 't', 'x', '1', '✓', '✔') then true
    when lower(trim(coalesce(p, ''))) in ('no', 'n', 'false', 'f', '0')                then false
    when lower(trim(coalesce(p, ''))) ~ '^yes\M'                                       then true
    when lower(trim(coalesce(p, ''))) ~ '^no\M'                                        then false
    else null end
$$;

create or replace function public.resolve_channel(p text, p_default text) RETURNS text
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select coalesce(
    (select c.code from public.channels c
      where upper(trim(p)) = c.code or lower(trim(p)) = lower(c.name) or lower(trim(p)) = any (c.aliases)
      order by c.sort_order limit 1),
    (select c.code from public.channels c, unnest(c.aliases) a
      where lower(trim(coalesce(p, ''))) like '%' || a || '%'
      order by length(a) desc, c.sort_order limit 1),
    p_default)
$$;

create or replace function public.resolve_header(p_header text, p_header_map jsonb DEFAULT '{}'::jsonb) RETURNS text
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  select coalesce(
    (select value from jsonb_each_text(coalesce(p_header_map, '{}'))
      where regexp_replace(lower(key), '[^a-z0-9]', '', 'g') = regexp_replace(lower(p_header), '[^a-z0-9]', '', 'g')
      limit 1),
    (select field from import_header_aliases
      where header_key = regexp_replace(lower(p_header), '[^a-z0-9]', '', 'g')))
$$;

create or replace function public.check_upload_headers(p_table regclass, p_tab text DEFAULT NULL::text) RETURNS TABLE(column_name text, maps_to text, filled_rows bigint, note text)
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public'
    AS $$
declare
  v_map  jsonb := '{}';
  a      record;
  v_n    bigint;
begin
  if p_tab is not null then
    select header_map into v_map from import_tab_profiles where lower(tab) = lower(p_tab);
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
    maps_to     := resolve_header(a.attname, v_map);
    filled_rows := v_n;
    note := case
      when lower(a.attname) in ('id', 'created_at') and maps_to is null then 'added by Supabase, ignored'
      when maps_to is null       then 'NOT RECOGNIZED: kept in the contact notes. Rename the header, or add it to import_header_aliases'
      when maps_to = 'ignore'    then 'dropped'
      when maps_to = 'extra_notes' then 'appended to the contact notes'
      when maps_to in ('new_contact', 'new_first_name', 'new_email', 'new_org', 'new_website', 'new_linkedin', 'new_notes')
                                 then 'second contact at the same organization (or the contact itself when there is no other name/email column)'
      when v_n = 0               then 'empty column'
      else '' end;
    return next;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 4. The import, rewritten for the whole workbook
-- ---------------------------------------------------------------------
create or replace function public.process_import_batch(p_batch_id bigint, p_run_automation boolean DEFAULT true) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public', 'extensions'
    AS $$
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
      v_sourced    := coalesce(parse_loose_date(r.date_added), v_touch_on, local_date(b.created_at));
      v_channel    := resolve_channel(v_x ->> 'channel', b.default_channel_code);
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
                v_channel, nullif(trim(r.source), ''), b.event_id, v_sourced, b.owner_id,
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
        elsif v_outcome_text is null then                                     -- blank = still no response
          v_outcome := case when b.default_touch_type in ('email', 'check_in') then 'NO_RESPONSE' end;
          v_status  := 'confirmed';
        elsif lower(trim(v_outcome_text)) in ('review', 'needs review', 'to review', '?') then
          v_outcome := case when b.default_touch_type in ('email', 'check_in') then 'NO_RESPONSE' end;
          v_status  := 'needs_review'; v_suggest := null;
        elsif v_suggest is not null and v_out.is_exact then                   -- a clean label
          v_outcome := v_suggest; v_status := 'confirmed';
        elsif v_suggest is not null then                                      -- phrase inside a pasted reply, or a hint
          v_outcome := coalesce(b.default_outcome_code,
                                case when b.default_touch_type in ('email', 'check_in') then 'NO_RESPONSE' end);
          v_status  := 'needs_review';
        else                                                                  -- could not tell
          v_outcome := coalesce(b.default_outcome_code,
                                case when b.default_touch_type in ('email', 'check_in') then 'NO_RESPONSE' end);
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
                  case when b.default_touch_type = 'event' then 'in_person' else 'outbound' end,
                  (v_touch_on + time '09:00') at time zone 'America/Denver', coalesce(v_campaign_id, b.campaign_id), b.event_id,
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

create or replace function public.import_uploaded_table(p_table regclass, p_label text, p_segment text DEFAULT NULL::text, p_channel text DEFAULT 'COLD_EMAIL'::text, p_touch_type text DEFAULT 'email'::text, p_state character DEFAULT NULL::bpchar, p_event_id bigint DEFAULT NULL::bigint, p_campaign_id bigint DEFAULT NULL::bigint, p_owner_id bigint DEFAULT NULL::bigint, p_run_automation boolean DEFAULT false, p_org_type text DEFAULT NULL::text, p_default_outcome text DEFAULT NULL::text, p_follow_up_days integer DEFAULT NULL::integer, p_tags text[] DEFAULT '{}'::text[], p_match_by_name boolean DEFAULT false, p_header_map jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  v_batch     bigint;
  v_row       jsonb;
  v_key       text;
  v_val       text;
  v_field     text;
  v_f         jsonb;
  v_x         jsonb;
  v_extra     text;
  v_n         int := 0;
  v_order     text := '';
  v_used      jsonb := '{}';
  v_kept      text[] := '{}';
  v_split     int := 0;
  v_core      text[] := '{date_added,source,contact,first_name,last_name,title,email,org,website,linkedin,added_on_linkedin,phone,aum,state,segment,notes,date_outreached,outcome,next_steps,follow_up_on}';
  v_outcome   text;
begin
  if exists (select 1 from pg_attribute where attrelid = p_table and attname = 'id' and not attisdropped) then
    v_order := ' order by t.id';                 -- keep the sheet's row order
  end if;
  if p_default_outcome is not null then
    select code into v_outcome from outcomes where code = upper(p_default_outcome);
    if v_outcome is null then
      select outcome_code into v_outcome from match_outcome(p_default_outcome);
    end if;
    if v_outcome is null then raise exception 'Unknown default outcome "%"', p_default_outcome; end if;
  end if;

  insert into import_batches (label, source_file, default_segment_code, default_channel_code, default_touch_type,
                              default_state, campaign_id, event_id, owner_id, default_org_type, default_outcome_code,
                              default_follow_up_days, tags, match_by_name, header_map, history_load)
  values (p_label, p_table::text, resolve_segment(p_segment, null), p_channel, p_touch_type,
          p_state, p_campaign_id, p_event_id, p_owner_id, p_org_type, v_outcome,
          p_follow_up_days, coalesce(p_tags, '{}'), p_match_by_name, coalesce(p_header_map, '{}'), not p_run_automation)
  returning id into v_batch;

  for v_row in execute format('select to_jsonb(t) from %s t%s', p_table, v_order) loop
    v_n := v_n + 1;
    v_f := '{}'; v_x := '{}';
    v_extra := null;
    for v_key, v_val in select key, value from jsonb_each_text(v_row) loop
      continue when v_val is null or btrim(v_val) = '';
      v_field := resolve_header(v_key, p_header_map);
      if v_field is null then
        continue when lower(v_key) in ('id', 'created_at');      -- columns Supabase adds by itself
        v_extra := concat_ws(E'\n', v_extra, v_key || ': ' || v_val);
        if not (v_key = any (v_kept)) then v_kept := v_kept || v_key; end if;
      elsif v_field = 'ignore' then
        continue;
      elsif v_field = 'extra_notes' then
        v_extra := concat_ws(E'\n', v_extra, v_key || ': ' || v_val);
        v_used := v_used || jsonb_build_object(v_key, v_field);
      elsif v_field = any (v_core) then
        -- two headers for the same field ("Note" and "Notes"): text fields are joined, single-value
        -- fields (dates, email, AUM ...) keep the first value and the second goes to the notes
        if v_field in ('notes', 'next_steps', 'outcome', 'source', 'title') or (v_f ->> v_field) is null then
          v_f := v_f || jsonb_build_object(v_field,
                   concat_ws(case when v_field in ('notes', 'next_steps') then E'\n' else ' ' end, v_f ->> v_field, v_val));
        elsif (v_f ->> v_field) <> v_val then
          v_extra := concat_ws(E'\n', v_extra, v_key || ': ' || v_val);
        end if;
        v_used := v_used || jsonb_build_object(v_key, v_field);
      else
        if (v_x ->> v_field) is null or v_field in ('status', 'response_notes', 'new_notes', 'no_reach_out_reason') then
          v_x := v_x || jsonb_build_object(v_field, concat_ws(E'\n', v_x ->> v_field, v_val));
        elsif (v_x ->> v_field) <> v_val then
          v_extra := concat_ws(E'\n', v_extra, v_key || ': ' || v_val);
        end if;
        v_used := v_used || jsonb_build_object(v_key, v_field);
      end if;
    end loop;
    continue when v_f = '{}' and v_x = '{}';                      -- an empty line in the sheet

    -- a sheet whose only people columns are the NEW CONTACT ones (Cold Nonprofits 2026): they are the person
    if coalesce(v_f ->> 'contact', v_f ->> 'email', v_f ->> 'linkedin') is null
       and coalesce(v_x ->> 'new_contact', v_x ->> 'new_email', v_x ->> 'new_linkedin') is not null then
      v_f := v_f || jsonb_strip_nulls(jsonb_build_object(
               'contact', v_x ->> 'new_contact', 'first_name', coalesce(v_x ->> 'new_first_name', v_f ->> 'first_name'),
               'email', v_x ->> 'new_email',
               'linkedin', v_x ->> 'new_linkedin', 'org', coalesce(v_f ->> 'org', v_x ->> 'new_org'),
               'website', coalesce(v_f ->> 'website', v_x ->> 'new_website'),
               'notes', concat_ws(E'\n', v_f ->> 'notes', v_x ->> 'new_notes')));
      v_x := v_x - '{new_contact,new_first_name,new_email,new_linkedin,new_org,new_website,new_notes}'::text[];
    end if;

    insert into import_rows (batch_id, row_number, date_added, source, contact, first_name, last_name, title, email,
                             org, website, linkedin, added_on_linkedin, phone, aum, state, segment, notes,
                             date_outreached, outcome, next_steps, follow_up_on, extra_notes, extra)
    values (v_batch, v_n + 1, v_f->>'date_added', v_f->>'source', v_f->>'contact', v_f->>'first_name',
            v_f->>'last_name', v_f->>'title', v_f->>'email', v_f->>'org', v_f->>'website', v_f->>'linkedin',
            v_f->>'added_on_linkedin', v_f->>'phone', v_f->>'aum', v_f->>'state', v_f->>'segment', v_f->>'notes',
            v_f->>'date_outreached', v_f->>'outcome', v_f->>'next_steps', v_f->>'follow_up_on', v_extra,
            v_x - '{new_contact,new_first_name,new_email,new_linkedin,new_org,new_website,new_notes}'::text[]);

    -- Master list: the NEW CONTACT columns are a second person at the same organization,
    -- sourced on "Date Source Approved", with no touch yet (the 2026 tab brings the 2026 outreach)
    if coalesce(v_x ->> 'new_contact', v_x ->> 'new_email', v_x ->> 'new_linkedin') is not null then
      v_split := v_split + 1;
      insert into import_rows (batch_id, row_number, date_added, source, contact, first_name, email, org, website,
                               linkedin, state, segment, notes, extra)
      values (v_batch, v_n + 1, coalesce(v_x ->> 'date_source_approved', v_f ->> 'date_added'), v_f ->> 'source',
              v_x ->> 'new_contact', v_x ->> 'new_first_name', v_x ->> 'new_email',
              coalesce(v_x ->> 'new_org', v_f ->> 'org'), coalesce(v_x ->> 'new_website', v_f ->> 'website'),
              v_x ->> 'new_linkedin', v_f ->> 'state', v_f ->> 'segment', v_x ->> 'new_notes',
              jsonb_build_object('derived_from', 'NEW CONTACT columns of row ' || (v_n + 1)));
    end if;
  end loop;

  return process_import_batch(v_batch, p_run_automation)
         || jsonb_build_object('batch_id', v_batch, 'columns_used', v_used, 'columns_kept_in_notes', to_jsonb(v_kept),
                               'new_contact_rows_split_off', v_split);
end $$;

create or replace function public.import_gaard_tab(p_table regclass, p_tab text, p_owner_id bigint DEFAULT NULL::bigint, p_run_automation boolean DEFAULT false, p_label text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  p import_tab_profiles;
begin
  select * into p from import_tab_profiles where lower(tab) = lower(p_tab);
  if not found then
    raise exception 'Unknown tab "%". Known tabs: %', p_tab,
      (select string_agg(tab, ', ' order by sort_order) from import_tab_profiles);
  end if;
  return import_uploaded_table(
           p_table, coalesce(p_label, p.tab), p.segment, p.channel_code, p.touch_type, null, null, null, p_owner_id,
           p_run_automation, p.org_type, p.default_outcome_code, p.follow_up_days, p.tags, p.match_by_name, p.header_map)
         || jsonb_build_object('tab', p.tab);
end $$;

-- ---------------------------------------------------------------------
-- 5. Rules that stand down during a history load
-- ---------------------------------------------------------------------
create or replace function public.touchpoints_before_write() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  c  contacts;
  tt touch_types;
  o  outcomes;
begin
  select * into c  from contacts    where id   = new.contact_id;
  select * into tt from touch_types where code = new.touch_type;
  new.organization_id := coalesce(new.organization_id, c.organization_id);
  new.owner_id        := coalesce(new.owner_id, c.owner_id);

  -- do-not-contact: block new emails / calls after someone is flagged (old history is only recorded)
  if tg_op = 'INSERT' and new.direction = 'outbound' and new.touch_type in ('email', 'call', 'check_in')
     and c.do_not_contact and (c.dnc_on is null or local_date(new.touched_at) > c.dnc_on)
     and not history_load() then
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

create or replace function public.apply_outcome_rules(p_touch public.touchpoints) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
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

  if v_latest and not history_load() then
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

  -- 3. pipeline (affiliates are partners, not prospects: no opportunity for them) ----
  if o.sets_stage is not null and seg.segment_group <> 'Affiliates' then
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
    elsif o.sets_stage <> 'lost'
      -- a touch older than a deal that already closed for this person / organization is history, not a new deal
      and not exists (
            select 1 from opportunities op
             where op.stage in ('funded', 'lost')
               and (op.contact_id = c.id
                    or (seg.party_type = 'organization' and c.organization_id is not null
                        and op.organization_id = c.organization_id))
               and coalesce(op.closed_on, op.funded_on, op.opened_on) >= v_day) then
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

-- ---------------------------------------------------------------------
-- 6. The master list shows the two new contact columns
-- ---------------------------------------------------------------------
create or replace view public.v_contacts with (security_invoker = true) as
 SELECT c.id AS contact_id,
    c.full_name,
    c.first_name,
    c.last_name,
    c.title,
    c.organization_id,
    COALESCE(o.name, c.employer) AS organization,
    sg.segment_group,
    sg.name AS segment,
    c.segment_code,
    c.state,
    st.name AS state_name,
    c.city,
    c.email,
    c.email_status,
    c.phone,
    c.linkedin_url,
    c.linkedin_connected_on,
    ch.name AS source_channel,
    c.source_detail,
    ev.name AS source_event,
    c.sourced_on,
    public.local_date(lt.touched_at) AS last_touch_on,
    ltt.name AS last_touch_type,
    lo.label AS last_outcome,
    public.local_date(ls.last_spoke_at) AS last_spoke_on,
    nr.due_on AS next_outreach_on,
    rt.label AS next_action,
    COALESCE(tc.touches, (0)::bigint) AS touches,
    COALESCE(tc.emails_sent, (0)::bigint) AS emails_sent,
    COALESCE(tc.calls_dialed, (0)::bigint) AS calls_dialed,
    op.stage AS pipeline_stage,
    op.expected_aum,
    op.funded_aum,
    COALESCE(o.reported_aum, c.prospect_aum) AS prospect_aum,
    c.is_decision_maker,
    c.is_university_affiliated,
    c.do_not_contact,
    c.dnc_reason,
    c.newsletter_status,
    c.follow_up_style,
    tm.full_name AS owner,
    c.tags,
    c.notes,
    c.created_at,
    c.activity_status,
    c.mailing_address
   FROM ((((((((((((((public.contacts c
     JOIN public.segments sg ON ((sg.code = c.segment_code)))
     LEFT JOIN public.organizations o ON ((o.id = c.organization_id)))
     LEFT JOIN public.us_states st ON ((st.code = c.state)))
     LEFT JOIN public.channels ch ON ((ch.code = c.source_channel_code)))
     LEFT JOIN public.events ev ON ((ev.id = c.source_event_id)))
     LEFT JOIN public.team_members tm ON ((tm.id = c.owner_id)))
     LEFT JOIN LATERAL ( SELECT t.touched_at,
            t.touch_type,
            t.outcome_code
           FROM public.touchpoints t
          WHERE (t.contact_id = c.id)
          ORDER BY t.touched_at DESC, t.id DESC
         LIMIT 1) lt ON (true))
     LEFT JOIN public.touch_types ltt ON ((ltt.code = lt.touch_type)))
     LEFT JOIN public.outcomes lo ON ((lo.code = lt.outcome_code)))
     LEFT JOIN LATERAL ( SELECT max(COALESCE(t.responded_at, t.touched_at)) AS last_spoke_at
           FROM (public.touchpoints t
             LEFT JOIN public.outcomes x ON ((x.code = t.outcome_code)))
          WHERE ((t.contact_id = c.id) AND (COALESCE(x.counts_as_response, false) OR (t.touch_type = 'meeting'::text)))) ls ON (true))
     LEFT JOIN LATERAL ( SELECT r.due_on,
            r.reminder_type
           FROM public.reminders r
          WHERE ((r.contact_id = c.id) AND (r.status = ANY (ARRAY['open'::text, 'snoozed'::text])))
          ORDER BY r.due_on
         LIMIT 1) nr ON (true))
     LEFT JOIN public.reminder_types rt ON ((rt.code = nr.reminder_type)))
     LEFT JOIN LATERAL ( SELECT count(*) AS touches,
            count(*) FILTER (WHERE (t.touch_type = 'email'::text)) AS emails_sent,
            count(*) FILTER (WHERE (t.touch_type = 'call'::text)) AS calls_dialed
           FROM public.touchpoints t
          WHERE (t.contact_id = c.id)) tc ON (true))
     LEFT JOIN LATERAL ( SELECT p.stage,
            p.expected_aum,
            p.funded_aum
           FROM public.opportunities p
          WHERE ((p.contact_id = c.id) OR ((sg.party_type = 'organization'::text) AND (c.organization_id IS NOT NULL) AND (p.organization_id = c.organization_id)))
          ORDER BY (p.stage = ANY (ARRAY['funded'::text, 'lost'::text])), p.opened_on DESC
         LIMIT 1) op ON (true));
