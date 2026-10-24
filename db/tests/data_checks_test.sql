-- =====================================================================
-- GAARD Capital CRM · db/013 tests (the weekly data check)
--
-- Runs the check on the database as it is, then scrambles a copy of the
-- data the way a sorted-by-one-column sheet would (touches under the wrong
-- organization, emails swapped between people, a date from the year 205,
-- a slice of rows deleted, security switched off on a table) and checks
-- that the next run catches every one of them. Everything rolls back, so it
-- is safe on a database with data in it:
--     psql "$DATABASE_URL" -f db/tests/data_checks_test.sql
-- Needs at least 60 contacts with touches (the mock seed or the real data).
-- =====================================================================
\set QUIET on
\pset pager off
begin;

create temp table test_results (n serial primary key, test text, ok boolean, detail text) on commit drop;
create function pg_temp.ok(p boolean, p_test text, p_detail text default null) returns void
language plpgsql as $$
begin
  insert into test_results (test, ok, detail) values (p_test, coalesce(p, false), p_detail);
end $$;

do $t$
declare
  j        jsonb;
  j2       jsonb;
  v_run    bigint;
  v_n      int;
  v_org_a  bigint; v_org_b bigint;
  v_ids    bigint[];
  v_tp     bigint;
  v_opp    bigint;
  v_prev_email_name int;
  v_prev_tp int;
  chk      record;
  v_min_touch bigint;
begin
  perform set_config('app.seeding', 'on', true);      -- the automation stands down, as in apply_changes()

  -- 1. the first run: a baseline ------------------------------------------------------------------
  j := run_data_checks('manual');
  v_run := (j ->> 'run_id')::bigint;
  perform pg_temp.ok(j ? 'status' and jsonb_array_length(j -> 'checks') >= 16 and exists (select 1 from data_check_runs where id = v_run),
                     'run_data_checks() runs, records the run and reports every check', j ->> 'summary');
  perform pg_temp.ok((select count(*) from v_data_check_latest where run_id = v_run) = jsonb_array_length(j -> 'checks')
                     and (select count(*) from v_data_check_history) >= 1,
                     'v_data_check_latest lists the checks of the latest run; v_data_check_history lists the runs');
  perform pg_temp.ok(not exists (select 1 from v_data_check_latest where code in ('links', 'touch_org', 'deal_org', 'reminder_org', 'keys', 'dates', 'deals', 'rls') and status = 'fail'),
                     'The database as it is passes every hard check',
                     (select string_agg(code || '=' || count, ', ') from v_data_check_latest where status = 'fail'));
  select count into v_prev_email_name from v_data_check_latest where code = 'email_name';
  select (row_counts ->> 'touchpoints')::int into v_prev_tp from data_check_runs where id = v_run;

  -- 2. scramble ------------------------------------------------------------------------------------
  -- two organizations that both have people with touches
  select o.id into v_org_a from organizations o where exists (select 1 from contacts c join touchpoints t on t.contact_id = c.id where c.organization_id = o.id) order by o.id limit 1;
  select o.id into v_org_b from organizations o where o.id <> v_org_a and exists (select 1 from contacts c join touchpoints t on t.contact_id = c.id where c.organization_id = o.id) order by o.id limit 1;

  -- a. three touches of organization A's people filed under organization B (the "status did not follow the name" symptom)
  select array_agg(t.id) into v_ids from (select t.id from touchpoints t join contacts c on c.id = t.contact_id where c.organization_id = v_org_a order by t.id limit 3) t;
  update touchpoints set organization_id = v_org_b where id = any (v_ids);

  -- b. emails swapped between eight pairs of people with different names (names and emails come apart).
  --    The database refuses the same email on two people even for a moment, so the swap goes through a
  --    placeholder: A -> placeholder, B -> A's email, A -> B's old email.
  create temp table scramble_pairs on commit drop as
    select a.id as id_a, b.id as id_b, a.email as email_a, b.email as email_b
      from (select id, email, row_number() over (order by id) rn from contacts where email_key is not null and first_name is not null and last_name is not null) a
      join (select id, email, row_number() over (order by id) rn from contacts where email_key is not null and first_name is not null and last_name is not null) b
        on b.rn = a.rn + 30
     where a.rn <= 8;
  update contacts c set email = 'swap' || c.id || '@placeholder.example' from scramble_pairs p where c.id = p.id_a;
  update contacts c set email = p.email_a from scramble_pairs p where c.id = p.id_b;
  update contacts c set email = p.email_b from scramble_pairs p where c.id = p.id_a;

  -- c. a touch dated in the year 205 (a digit missing)
  select min(id) into v_min_touch from touchpoints;
  update touchpoints set touched_at = timestamptz '0205-11-20 12:00' where id = v_min_touch;

  -- d. a deal marked funded with no amount: the database refuses it outright (funded_needs_aum)
  select id into v_opp from opportunities order by id limit 1;
  begin
    update opportunities set stage = 'funded', funded_on = local_today(), funded_aum = null where id = v_opp;
    perform pg_temp.ok(false, 'The database refuses a funded deal with no amount');
  exception when check_violation then
    perform pg_temp.ok(true, 'The database refuses a funded deal with no amount');
  end;
  -- so the inconsistency planted is one it does not refuse: funded a month before the deal was opened
  select id into v_opp from opportunities where stage = 'funded' and funded_on is not null order by id limit 1;
  if v_opp is not null then
    update opportunities set funded_on = opened_on - 30 where id = v_opp;
  end if;

  -- e. a slice of touches deleted (15%)
  delete from touchpoints where id in (select id from touchpoints order by id desc limit greatest(1, (v_prev_tp * 15) / 100));

  -- f. security switched off on one table, and the id counter of another left behind (a row added with an
  --    id the app chose, far above the counter; setval is never used here because it survives a rollback)
  alter table campaigns disable row level security;
  insert into events (id, name, event_type, format, start_on)
  values ((select coalesce(max(id), 0) + 1000 from events), 'Scramble test event', 'other', 'virtual', local_today());

  -- 3. the next run must see all of it -------------------------------------------------------------
  j2 := run_data_checks('weekly');
  perform pg_temp.ok(j2 ->> 'status' = 'fail', 'The run after the scramble fails', j2 ->> 'summary');
  perform pg_temp.ok((select status || '/' || count from v_data_check_latest where code = 'touch_org') = 'fail/3'
                     and (select jsonb_array_length(sample) from v_data_check_latest where code = 'touch_org') = 3,
                     'Three touches under the wrong organization: found, with the three rows in the sample');
  select count, status into chk from v_data_check_latest where code = 'email_name';
  perform pg_temp.ok(chk.count >= v_prev_email_name + 10 and chk.status = 'warn',
                     'Sixteen emails that no longer carry the person''s name: the jump since the previous run is flagged',
                     'was ' || v_prev_email_name || ', now ' || chk.count);
  perform pg_temp.ok((select status from v_data_check_latest where code = 'dates') = 'fail'
                     and (select sample -> 0 ->> 'what' from v_data_check_latest where code = 'dates') = 'touchpoint',
                     'A touch in the year 205: found');
  perform pg_temp.ok(v_opp is null or ((select status from v_data_check_latest where code = 'deals') = 'fail'
                     and (select sample -> 0 ->> 'why' from v_data_check_latest where code = 'deals') = 'funded before it was opened'),
                     'A deal funded before it was opened: found');
  perform pg_temp.ok((select status from v_data_check_latest where code = 'row_counts') = 'fail'
                     and (select sample -> 0 ->> 'table' from v_data_check_latest where code = 'row_counts') = 'touchpoints',
                     'Fifteen percent of the touches gone: the row count drop is a failure, naming the table');
  perform pg_temp.ok((select status from v_data_check_latest where code = 'rls') = 'fail'
                     and (select sample -> 0 ->> 'table' from v_data_check_latest where code = 'rls') = 'campaigns',
                     'Row level security off on one table: found, naming the table');
  perform pg_temp.ok((select status from v_data_check_latest where code = 'counters') = 'warn'
                     and (select sample -> 0 ->> 'fix' from v_data_check_latest where code = 'counters') like 'select setval(%events%',
                     'An id counter behind the rows: flagged, with the one-line fix');
  if to_regclass('public.audit_log') is not null then
    perform pg_temp.ok((select (changes ->> 'deleted_rows')::int from data_check_runs order by id desc limit 1) >= greatest(1, (v_prev_tp * 15) / 100)
                       and (select changes -> 'by_table' -> 'touchpoints' ->> 'deleted' from data_check_runs order by id desc limit 1) is not null,
                       'The deletions show in the change summary from the audit log');
  end if;
  perform pg_temp.ok((select count(*) from data_check_runs where id >= v_run) = 2
                     and (select previous from v_data_check_latest where code = 'touch_org') = 0,
                     'Each run keeps the previous run''s counts beside its own');
end $t$;

select n, case when ok then 'PASS' else 'FAIL' end as result, test, left(detail, 100) as detail from test_results order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from test_results;
rollback;
