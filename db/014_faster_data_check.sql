/* ======================================================================
   014  THE DATA CHECK WITHIN THE API'S TIME LIMIT
   Run once in the Supabase SQL Editor, after 013. Safe to run again.

   "Run the check now" in Settings calls run_data_checks() through the API,
   where a signed-in user's statement may take 8 seconds (Supabase's default
   for the authenticated role). The duplicates check read v_possible_duplicates,
   whose look-alike search compares every organization name with every other
   by trigram similarity: fine for a person in the SQL Editor, far too slow
   for the button on a couple of thousand rows. The weekly check now looks
   for exact duplicates only (same name at one organization, two organizations
   with one website); the look-alike view stays for people.

   Same function, same result shape; nothing else changes.
   ====================================================================== */

begin;

create or replace function public.run_data_checks(p_trigger text default 'manual') returns jsonb
language plpgsql security definer set search_path = 'public', 'pg_temp' as $$
declare
  v_t0        timestamptz := clock_timestamp();
  v_me        bigint;
  v_prev      data_check_runs;
  v_checks    jsonb := '[]';
  v_counts    jsonb := '{}';
  v_changes   jsonb;
  v_status    text := 'ok';
  v_st        text;
  v_n         int;
  v_prev_n    int;
  v_max_id    bigint;
  v_counter   bigint;
  v_sample    jsonb;
  v_rec       record;
  v_people    int;
  v_core      constant text[] := array['organizations', 'contacts', 'touchpoints', 'opportunities', 'reminders', 'events', 'rfps', 'team_members'];
  v_run       data_check_runs;
begin
  -- who is asking: a team member through the app, or nobody (the scheduled job, which runs as postgres)
  if auth.uid() is not null then
    if not is_team_member() then
      raise exception 'Sign in as a team member, with your two-step code, to run the data check' using errcode = '42501';
    end if;
    select id into v_me from team_members where auth_user_id = auth.uid() and is_active;
  end if;

  select * into v_prev from data_check_runs order by ran_at desc, id desc limit 1;
  select count(*) into v_people from contacts;

  /* ---- A. Hard checks: a scrambled database fails these; a healthy one is at zero ---- */

  -- A1. Every link points at a row that exists (the database enforces this; the check proves it)
  select count(*) into v_n from (
    select 1 from contacts c left join organizations o on o.id = c.organization_id where c.organization_id is not null and o.id is null
    union all select 1 from touchpoints t left join contacts c on c.id = t.contact_id where c.id is null
    union all select 1 from opportunities p left join contacts c on c.id = p.contact_id where c.id is null
    union all select 1 from reminders r left join contacts c on c.id = r.contact_id where r.contact_id is not null and c.id is null
    union all select 1 from rfps f left join organizations o on o.id = f.organization_id where o.id is null) x;
  v_st := case when v_n = 0 then 'ok' else 'fail' end; v_status := data_check_worse(v_status, v_st);
  v_checks := v_checks || data_check_item('links', 'Every touch, deal, reminder and RFP points at a person or organization that exists', 'hard', v_st, v_n,
                 data_check_prev(v_prev.checks, 'links'), 'Enforced by the database itself (foreign keys).', null);

  -- A2. A touch belongs to the same organization as its person
  with bad as (
    select t.id as touchpoint_id, c.full_name as person, o1.name as touch_says, o2.name as person_is_at
      from touchpoints t join contacts c on c.id = t.contact_id
      left join organizations o1 on o1.id = t.organization_id
      left join organizations o2 on o2.id = c.organization_id
     where t.organization_id is not null and c.organization_id is not null and t.organization_id <> c.organization_id)
  select count(*), (select jsonb_agg(to_jsonb(smp)) from (select * from bad limit 5) smp) into v_n, v_sample from bad;
  v_st := case when v_n = 0 then 'ok' else 'fail' end; v_status := data_check_worse(v_status, v_st);
  v_checks := v_checks || data_check_item('touch_org', 'Each logged email, call or meeting sits under the same organization as the person', 'hard', v_st, v_n,
                 data_check_prev(v_prev.checks, 'touch_org'),
                 'This is the "status did not follow the name" symptom. Fix: update touchpoints set organization_id = (select organization_id from contacts where id = contact_id) where id = <touchpoint_id>.',
                 v_sample);

  -- A3. A deal belongs to the same organization as its person
  with bad as (
    select p.id as opportunity_id, c.full_name as person, p.stage, o1.name as deal_says, o2.name as person_is_at
      from opportunities p join contacts c on c.id = p.contact_id
      left join organizations o1 on o1.id = p.organization_id
      left join organizations o2 on o2.id = c.organization_id
     where p.organization_id is not null and c.organization_id is not null and p.organization_id <> c.organization_id)
  select count(*), (select jsonb_agg(to_jsonb(smp)) from (select * from bad limit 5) smp) into v_n, v_sample from bad;
  v_st := case when v_n = 0 then 'ok' else 'fail' end; v_status := data_check_worse(v_status, v_st);
  v_checks := v_checks || data_check_item('deal_org', 'Each deal in the pipeline sits under the same organization as the person', 'hard', v_st, v_n,
                 data_check_prev(v_prev.checks, 'deal_org'), null, v_sample);

  -- A4. A reminder that names both a person and an organization names the person's organization
  with bad as (
    select r.id as reminder_id, r.title, c.full_name as person, o1.name as reminder_says, o2.name as person_is_at
      from reminders r join contacts c on c.id = r.contact_id
      left join organizations o1 on o1.id = r.organization_id
      left join organizations o2 on o2.id = c.organization_id
     where r.organization_id is not null and c.organization_id is not null and r.organization_id <> c.organization_id)
  select count(*), (select jsonb_agg(to_jsonb(smp)) from (select * from bad limit 5) smp) into v_n, v_sample from bad;
  v_st := case when v_n = 0 then 'ok' else 'fail' end; v_status := data_check_worse(v_status, v_st);
  v_checks := v_checks || data_check_item('reminder_org', 'Each follow-up reminder sits under the same organization as the person', 'hard', v_st, v_n,
                 data_check_prev(v_prev.checks, 'reminder_org'), null, v_sample);

  -- A5. The match keys the triggers maintain agree with the visible columns
  with bad as (
    select c.id as contact_id, c.full_name as person, c.email, c.email_key from contacts c
     where c.email_key is distinct from norm_email(c.email)
        or c.name_key is distinct from norm_text(concat_ws(' ', c.first_name, c.last_name)))
  select count(*), (select jsonb_agg(to_jsonb(smp)) from (select * from bad limit 5) smp) into v_n, v_sample from bad;
  v_st := case when v_n = 0 then 'ok' else 'fail' end; v_status := data_check_worse(v_status, v_st);
  v_checks := v_checks || data_check_item('keys', 'The hidden match keys (used to spot duplicates) agree with each person''s name and email', 'hard', v_st, v_n,
                 data_check_prev(v_prev.checks, 'keys'),
                 'Fix: update contacts set updated_at = now() where id = <contact_id> (the trigger recomputes them).', v_sample);

  -- A6. Dates inside a believable range (the 11/20/205 class of typo, see 006)
  with bad as (
    select 'contact' as what, c.id, c.full_name as who, c.sourced_on::text as date from contacts c
     where c.sourced_on < date '1990-01-01' or c.sourced_on > local_today() + 366
    union all
    select 'touchpoint', t.id, c.full_name, t.touched_at::date::text from touchpoints t join contacts c on c.id = t.contact_id
     where t.touched_at < timestamptz '1990-01-01' or t.touched_at > now() + interval '366 days'
    union all
    select 'opportunity', p.id, c.full_name, p.opened_on::text from opportunities p join contacts c on c.id = p.contact_id
     where p.opened_on < date '1990-01-01' or p.opened_on > local_today() + 366
       or p.funded_on < date '1990-01-01' or p.funded_on > local_today() + 366
    union all
    select 'reminder', r.id, r.title, r.due_on::text from reminders r
     where r.due_on < date '1990-01-01' or r.due_on > local_today() + 3660
    union all
    select 'event', e.id, e.name, e.start_on::text from events e
     where e.start_on < date '1990-01-01' or e.start_on > local_today() + 1100
    union all
    select 'rfp', f.id, f.title, coalesce(f.due_on, f.released_on)::text from rfps f
     where least(f.released_on, f.due_on, f.submitted_on, f.decision_on) < date '1990-01-01'
        or greatest(f.released_on, f.due_on, f.submitted_on, f.decision_on) > local_today() + 1100)
  select count(*), (select jsonb_agg(to_jsonb(smp)) from (select * from bad limit 5) smp) into v_n, v_sample from bad;
  v_st := case when v_n = 0 then 'ok' else 'fail' end; v_status := data_check_worse(v_status, v_st);
  v_checks := v_checks || data_check_item('dates', 'Every date is between 1990 and a year or so ahead', 'hard', v_st, v_n,
                 data_check_prev(v_prev.checks, 'dates'), 'A sheet cell like 11/20/205 (a digit missing) is the usual cause.', v_sample);

  -- A7. Deals are consistent with themselves
  with bad as (
    select p.id as opportunity_id, c.full_name as person, p.stage,
           case when p.stage = 'funded' and (p.funded_on is null or coalesce(p.funded_aum, 0) = 0) then 'funded without a funded date or AUM'
                when p.stage <> 'funded' and p.funded_on is not null then 'has a funded date but is not funded'
                when p.funded_on < p.opened_on then 'funded before it was opened'
                when p.closed_on < p.opened_on then 'closed before it was opened' end as why
      from opportunities p join contacts c on c.id = p.contact_id)
  select count(*), (select jsonb_agg(to_jsonb(smp)) from (select * from bad where why is not null limit 5) smp) into v_n, v_sample from bad where why is not null;
  v_st := case when v_n = 0 then 'ok' else 'fail' end; v_status := data_check_worse(v_status, v_st);
  v_checks := v_checks || data_check_item('deals', 'A funded deal has a funded date and an amount; dates run in order', 'hard', v_st, v_n,
                 data_check_prev(v_prev.checks, 'deals'), null, v_sample);

  -- A8. Security is on for every table, and the audit log watches every table it should
  select count(*), jsonb_agg(jsonb_build_object('table', relname)) into v_n, v_sample
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
  v_st := case when v_n = 0 then 'ok' else 'fail' end; v_status := data_check_worse(v_status, v_st);
  v_checks := v_checks || data_check_item('rls', 'Row level security is switched on for every table', 'hard', v_st, v_n,
                 data_check_prev(v_prev.checks, 'rls'), 'Without it the publishable key in the web page would read the table.', v_sample);

  if to_regprocedure('public.audit_row()') is not null then
    select count(*), jsonb_agg(jsonb_build_object('table', relname)) into v_n, v_sample
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r'
       and c.relname not in ('audit_log', 'import_rows', 'data_check_runs')
       and not exists (select 1 from pg_trigger g where g.tgrelid = c.oid and g.tgname = 'zz_audit' and not g.tgisinternal);
    v_st := case when v_n = 0 then 'ok' else 'fail' end; v_status := data_check_worse(v_status, v_st);
    v_checks := v_checks || data_check_item('audit', 'The audit log records every change to every table', 'hard', v_st, v_n,
                   data_check_prev(v_prev.checks, 'audit'), 'The audit log is how a wrong change is traced and undone.', v_sample);
  end if;

  -- A9. Id counters are ahead of the ids in use (the app picks ids itself when it adds rows)
  v_sample := '[]'; v_n := 0;
  for v_rec in
    select c.relname as tbl, pg_get_serial_sequence('public.' || quote_ident(c.relname), 'id') as seq
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
      join pg_attribute a on a.attrelid = c.oid and a.attname = 'id' and a.attidentity <> ''
     where n.nspname = 'public' and c.relkind = 'r' order by 1
  loop
    continue when v_rec.seq is null;
    execute format('select coalesce(max(id), 0) from public.%I', v_rec.tbl) into v_max_id;
    execute format('select case when is_called then last_value else last_value - 1 end from %s', v_rec.seq) into v_counter;
    if v_counter < v_max_id then
      v_n := v_n + 1;
      v_sample := v_sample || jsonb_build_object('table', v_rec.tbl, 'highest_id', v_max_id, 'counter', v_counter,
                    'fix', format('select setval(%L, %s)', v_rec.seq, v_max_id));
    end if;
  end loop;
  v_st := case when v_n = 0 then 'ok' else 'warn' end; v_status := data_check_worse(v_status, v_st);
  v_checks := v_checks || data_check_item('counters', 'Each table''s id counter is ahead of the highest id in use', 'hard', v_st, v_n,
                 data_check_prev(v_prev.checks, 'counters'),
                 'If a counter falls behind, the next row the database creates itself fails with a duplicate id. The fix is in the sample.', v_sample);

  /* ---- B. Drift checks: some of these are normal; a jump since last week is the signal ---- */

  -- B1. The email address carries the person's name (jsmith@, jane.smith@, jane@ ...)
  with bad as (
    select c.id as contact_id, c.full_name as person, c.email from contacts c
     cross join lateral (select email_local_letters(c.email) as loc,
                                regexp_replace(lower(coalesce(c.first_name, '')), '[^a-z]', '', 'g') as fn,
                                regexp_replace(lower(coalesce(c.last_name, '')), '[^a-z]', '', 'g') as ln) k
     where c.email_key is not null and length(k.loc) >= 3 and (length(k.fn) >= 3 or length(k.ln) >= 3)
       and k.loc !~ '^(info|office|admin|contact|hello|team|hr|finance|accounting|accounts|ceo|cfo|coo|president|director|exec|executive|ed|board|donate|development|giving|support|help|mail|email|general|main|frontdesk|reception|foundation|grants|marketing|communications|comms|media|press|pr|outreach|programs|volunteer|jobs|careers|membership|events|sales|billing|payroll|benefits|plan|retirement|trust|investments|treasurer|secretary|chair|staff|webmaster|noreply|donotreply|questions|inquiries|services|operations|ops)'
       and not (length(k.fn) >= 3 and position(k.fn in k.loc) > 0)
       and not (length(k.ln) >= 3 and position(k.ln in k.loc) > 0)
       and not (length(k.ln) >= 3 and length(k.fn) >= 1 and position(left(k.fn, 1) || k.ln in k.loc) > 0)
       and not (length(k.fn) >= 3 and length(k.ln) >= 1 and position(k.fn || left(k.ln, 1) in k.loc) > 0)
       and not (length(k.fn) >= 3 and position(left(k.fn, 3) in k.loc) > 0 and length(k.loc) <= 6))
  select count(*), (select jsonb_agg(to_jsonb(smp)) from (select * from bad limit 5) smp) into v_n, v_sample from bad;
  v_prev_n := data_check_prev(v_prev.checks, 'email_name');
  v_st := case when v_prev_n is null then 'ok' when v_n > v_prev_n + greatest(5, v_people / 100) then 'warn' else 'ok' end;
  v_status := data_check_worse(v_status, v_st);
  v_checks := v_checks || data_check_item('email_name', 'The email address carries the person''s name', 'drift', v_st, v_n, v_prev_n,
                 'Nicknames and shared mailboxes are normal here. A jump since the last run means names and emails have come apart.', v_sample);

  -- B2. The email domain matches the organization's website
  with bad as (
    select c.id as contact_id, c.full_name as person, c.email_domain, o.name as organization, o.domain as website
      from contacts c join organizations o on o.id = c.organization_id
     where c.email_domain is not null and o.domain is not null and c.email_domain <> o.domain
       and not exists (select 1 from freemail_domains f where f.domain = c.email_domain)
       and split_part(c.email_domain, '.', 1) <> split_part(o.domain, '.', 1))
  select count(*), (select jsonb_agg(to_jsonb(smp)) from (select * from bad limit 5) smp) into v_n, v_sample from bad;
  v_prev_n := data_check_prev(v_prev.checks, 'email_org');
  v_st := case when v_prev_n is null then 'ok' when v_n > v_prev_n + greatest(5, v_people / 100) then 'warn' else 'ok' end;
  v_status := data_check_worse(v_status, v_st);
  v_checks := v_checks || data_check_item('email_org', 'The email domain matches the organization''s website', 'drift', v_st, v_n, v_prev_n,
                 'A consultant or a fiscal sponsor is a normal mismatch. A jump means people and organizations have come apart.', v_sample);

  -- B3. A touch is not older than the day the person was sourced
  with bad as (
    select t.id as touchpoint_id, c.full_name as person, t.touched_at::date as touched, c.sourced_on as sourced
      from touchpoints t join contacts c on c.id = t.contact_id
     where c.sourced_on is not null and t.touched_at::date < c.sourced_on - 7)
  select count(*), (select jsonb_agg(to_jsonb(smp)) from (select * from bad limit 5) smp) into v_n, v_sample from bad;
  v_prev_n := data_check_prev(v_prev.checks, 'touch_before_sourced');
  v_st := case when v_prev_n is null then 'ok' when v_n > v_prev_n then 'warn' else 'ok' end;
  v_status := data_check_worse(v_status, v_st);
  v_checks := v_checks || data_check_item('touch_before_sourced', 'Nobody was emailed more than a week before they were sourced', 'drift', v_st, v_n, v_prev_n,
                 'A few come from the old sheets (the sourced date typed later than the email). New ones mean a date landed on the wrong person.', v_sample);

  -- B4. Duplicates by exact key (same name at the same organization; organizations sharing a website).
  --     The look-alike search (v_possible_duplicates, trigram similarity) is too slow for the API's
  --     time limit on a few thousand rows; run that one in the SQL Editor when wanted.
  with bad as (
    select 'contact' as what, a.full_name as a, b.full_name as b, 'same name at the same organization' as reason
      from contacts a join contacts b on a.id < b.id and a.organization_id = b.organization_id and a.name_key = b.name_key
    union all
    select 'organization', a.name, b.name, 'same website'
      from organizations a join organizations b on a.id < b.id and a.domain is not null and a.domain = b.domain)
  select count(*), (select jsonb_agg(to_jsonb(smp)) from (select * from bad limit 5) smp) into v_n, v_sample from bad;
  v_prev_n := data_check_prev(v_prev.checks, 'duplicates');
  v_st := case when v_prev_n is null then 'ok' when v_n > v_prev_n then 'warn' else 'ok' end;
  v_status := data_check_worse(v_status, v_st);
  v_checks := v_checks || data_check_item('duplicates', 'No person or organization is entered twice', 'drift', v_st, v_n, v_prev_n,
                 'Same name at one organization, or two organizations with one website. Merge with merge_contacts(keep_id, remove_id). For look-alike spellings run v_possible_duplicates in the SQL Editor.', v_sample);

  -- B5. Open reminders for people who asked not to be contacted
  with bad as (
    select r.id as reminder_id, r.title, c.full_name as person from reminders r join contacts c on c.id = r.contact_id
     where r.status in ('open', 'snoozed') and c.do_not_contact
       and r.reminder_type not in ('fix_contact_info', 'in_person', 'custom'))
  select count(*), (select jsonb_agg(to_jsonb(smp)) from (select * from bad limit 5) smp) into v_n, v_sample from bad;
  v_st := case when v_n = 0 then 'ok' else 'warn' end; v_status := data_check_worse(v_status, v_st);
  v_checks := v_checks || data_check_item('dnc_reminders', 'Nobody marked do-not-contact has an open follow-up', 'drift', v_st, v_n,
                 data_check_prev(v_prev.checks, 'dnc_reminders'), 'Fix: select complete_reminder(<reminder_id>, null) or dismiss it in the app.', v_sample);

  /* ---- C. Row counts, against the previous run ---- */
  for v_rec in select c.relname as tbl from pg_class c join pg_namespace n on n.oid = c.relnamespace
                where n.nspname = 'public' and c.relkind = 'r' and c.relname not in ('audit_log', 'import_rows', 'data_check_runs') order by 1 loop
    execute format('select count(*) from public.%I', v_rec.tbl) into v_n;
    v_counts := v_counts || jsonb_build_object(v_rec.tbl, v_n);
  end loop;
  with shrunk as (
    select k.key as "table", (v_prev.row_counts ->> k.key)::int as was, k.value::int as now
      from jsonb_each_text(v_counts) k
     where k.key = any (v_core) and v_prev.row_counts ? k.key and k.value::int < (v_prev.row_counts ->> k.key)::int)
  select count(*), jsonb_agg(to_jsonb(shrunk)) into v_n, v_sample from shrunk;
  v_st := case when coalesce(v_n, 0) = 0 then 'ok'
               when exists (select 1 from jsonb_array_elements(coalesce(v_sample, '[]'::jsonb)) e
                             where (e ->> 'now')::numeric < 0.9 * (e ->> 'was')::numeric) then 'fail'
               else 'warn' end;
  v_status := data_check_worse(v_status, v_st);
  v_checks := v_checks || data_check_item('row_counts', 'No table lost rows since the last run', 'drift', v_st, coalesce(v_n, 0), null,
                 'Rows removed on purpose (a merge, a cleanup) show in the audit log; anything else deserves a look.', v_sample);

  /* ---- D. What changed since the previous run (the audit log) ---- */
  if to_regclass('public.audit_log') is not null then
    select jsonb_build_object(
             'since', coalesce(v_prev.ran_at, now() - interval '7 days'),
             'by_table', coalesce((select jsonb_object_agg(table_name, j) from (
                 select table_name, jsonb_build_object('inserted', count(*) filter (where action = 'insert'),
                                                       'updated',  count(*) filter (where action = 'update'),
                                                       'deleted',  count(*) filter (where action = 'delete')) as j
                   from audit_log where at >= coalesce(v_prev.ran_at, now() - interval '7 days') group by table_name) t), '{}'::jsonb),
             'by_person', coalesce((select jsonb_object_agg(coalesce(actor_email, 'database / import'), n) from (
                 select actor_email, count(*) as n from audit_log where at >= coalesce(v_prev.ran_at, now() - interval '7 days') group by actor_email) t), '{}'::jsonb),
             'deleted_rows', (select count(*) from audit_log where at >= coalesce(v_prev.ran_at, now() - interval '7 days') and action = 'delete'))
      into v_changes;
    v_n := (v_changes ->> 'deleted_rows')::int;
    v_st := case when v_n > 50 then 'warn' else 'ok' end; v_status := data_check_worse(v_status, v_st);
    v_checks := v_checks || data_check_item('deletes', 'Few rows were deleted since the last run', 'drift', v_st, v_n, null,
                   'Every deleted row is kept in full in audit_log and can be put back.', null);
  end if;

  /* ---- E. Record the run ---- */
  insert into data_check_runs (trigger, ran_by, status, summary, checks, row_counts, changes, duration_ms)
  values (p_trigger, v_me, v_status,
          case when v_status = 'ok' then 'All ' || jsonb_array_length(v_checks) || ' checks passed'
               else concat_ws(', ',
                      nullif((select count(*) from jsonb_array_elements(v_checks) c where c ->> 'status' = 'fail') || ' to fix', '0 to fix'),
                      nullif((select count(*) from jsonb_array_elements(v_checks) c where c ->> 'status' = 'warn') || ' to look at', '0 to look at')) end,
          v_checks, v_counts, v_changes, (extract(epoch from clock_timestamp() - v_t0) * 1000)::int)
  returning * into v_run;

  return jsonb_build_object('run_id', v_run.id, 'ran_at', v_run.ran_at, 'status', v_run.status, 'summary', v_run.summary,
                            'checks', (select jsonb_agg(jsonb_build_object('code', c ->> 'code', 'status', c ->> 'status', 'count', c -> 'count'))
                                         from jsonb_array_elements(v_checks) c),
                            'see', 'select * from v_data_check_latest order by sort_order');
end $$;

revoke execute on function public.run_data_checks(text) from public, anon;
grant  execute on function public.run_data_checks(text) to authenticated;

commit;

notify pgrst, 'reload schema';
