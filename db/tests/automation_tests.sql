-- =====================================================================
-- GAARD Capital CRM · automation tests (41 checks)
--
-- Exercises every rule once on fresh test records, then rolls everything
-- back, so it is safe to run on a database that has the mock data (or real
-- data) in it:
--     psql "$DATABASE_URL" -f db/tests/automation_tests.sql
-- Prints one line per check and a final count of failures.
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

do $tests$
declare
  v_org   bigint; v_org2 bigint;
  v_c     bigint; v_c2 bigint; v_c3 bigint; v_c4 bigint; v_c5 bigint; v_c6 bigint; v_c7 bigint; v_c8 bigint;
  v_t     bigint;
  v_rfp   bigint;
  v_opp   opportunities;
  v_rem   reminders;
  v_con   contacts;
  v_n     int;
begin
  -- fixtures --------------------------------------------------------------
  insert into organizations (name, segment_code, website, state)
  values ('Test Harbor Youth Alliance', 'ORG_NONPROFIT', 'https://www.testharbor.example/about', 'UT')
  returning id into v_org;
  insert into contacts (organization_id, first_name, last_name, email, linkedin_url, source_channel_code, owner_id)
  values (v_org, 'Tess', 'Tester', 'Tess.Tester@TestHarbor.example',
          'https://www.linkedin.com/in/tess-tester-0001/', 'COLD_EMAIL', 1)
  returning id into v_c;
  select * into v_con from contacts where id = v_c;
  perform pg_temp.ok(v_con.segment_code = 'ORG_NONPROFIT' and v_con.state = 'UT',
                     'Contact inherits segment and state from its organization');
  perform pg_temp.ok(v_con.email_key = 'tess.tester@testharbor.example'
                     and v_con.linkedin_key = 'linkedin.com/in/tess-tester-0001',
                     'Email and LinkedIn are normalized into matching keys', v_con.email_key || ' / ' || v_con.linkedin_key);

  -- duplicates --------------------------------------------------------------
  begin
    insert into contacts (organization_id, first_name, last_name, email) values (v_org, 'T', 'Tester', '  TESS.tester@testharbor.EXAMPLE ');
    perform pg_temp.ok(false, 'Duplicate email (different case / spaces) is blocked');
  exception when unique_violation then
    perform pg_temp.ok(true, 'Duplicate email (different case / spaces) is blocked');
  end;
  begin
    insert into contacts (organization_id, first_name, last_name, email, linkedin_url)
    values (v_org, 'Tess', 'Tester', 'other@testharbor.example', 'http://linkedin.com/in/TESS-TESTER-0001?trk=profile');
    perform pg_temp.ok(false, 'Duplicate LinkedIn (different URL format) is blocked');
  exception when unique_violation then
    perform pg_temp.ok(true, 'Duplicate LinkedIn (different URL format) is blocked');
  end;
  begin
    insert into organizations (name, segment_code, state) values ('The Test Harbor Youth Alliance, Inc.', 'ORG_NONPROFIT', 'UT');
    perform pg_temp.ok(false, 'Same organization entered twice ("The ... , Inc.") is blocked');
  exception when unique_violation then
    perform pg_temp.ok(true, 'Same organization entered twice ("The ... , Inc.") is blocked');
  end;
  perform pg_temp.ok(org_names_look_alike('Cache Valley Literacy Center', 'Cache Valey Literacy Center')
                     and org_names_look_alike('Literacy Council of Cache Valley', 'Cache Valley Literacy Council')
                     and org_names_look_alike('Bear River Youth Soccer', 'Bear River Youth Soccer Club')
                     and not org_names_look_alike('Park Charitable Trust', 'Rice Charitable Trust')
                     and person_names_look_alike('Dan', 'Whitaker', 'Daniel', 'Whitaker')
                     and not person_names_look_alike('Dana', 'Whitaker', 'Daniel', 'Whitaker'),
                     'Look-alike checks catch typos, word order and nicknames but not different organizations');

  -- next outreach dates ------------------------------------------------------
  insert into touchpoints (contact_id, touch_type, touched_at, subject)
  values (v_c, 'email', '2026-09-01 09:00 America/Denver', 'Test outreach') returning id into v_t;
  perform pg_temp.ok((select outcome_code from touchpoints where id = v_t) = 'NO_RESPONSE',
                     'A new outreach email starts as "No response"');
  select * into v_rem from reminders where contact_id = v_c and status = 'open';
  perform pg_temp.ok(v_rem.reminder_type = 'follow_up' and v_rem.due_on = date '2026-11-30',
                     'No response -> follow up in a quarter (Sep 1 -> Nov 30)', v_rem.due_on::text);

  insert into touchpoints (contact_id, touch_type, touched_at, outcome_code, ooo_return_on)
  values (v_c, 'email', '2026-09-08 09:00 America/Denver', 'OUT_OF_OFFICE', '2026-09-21');
  select * into v_rem from reminders where contact_id = v_c and status = 'open';
  perform pg_temp.ok(v_rem.reminder_type = 'ooo_follow_up' and v_rem.due_on = date '2026-09-22',
                     'Out of office until Sep 21 -> reminder Sep 22', v_rem.due_on::text);
  perform pg_temp.ok((select count(*) from reminders where contact_id = v_c and status = 'superseded') = 1,
                     'The older follow-up is closed, so only one reminder per person stays open');

  insert into touchpoints (contact_id, touch_type, touched_at, outcome_code, follow_up_on)
  values (v_c, 'email', '2026-09-15 09:00 America/Denver', 'NOT_NOW', '2026-10-01');
  select * into v_rem from reminders where contact_id = v_c and status = 'open';
  perform pg_temp.ok(v_rem.due_on = date '2026-10-01', '"Check back in October" -> reminder on Oct 1', v_rem.due_on::text);

  -- call booked ----------------------------------------------------------------
  insert into touchpoints (contact_id, touch_type, touched_at, outcome_code, follow_up_on)
  values (v_c, 'email', '2026-09-24 09:00 America/Denver', 'INTERESTED', '2026-09-30') returning id into v_t;
  select * into v_opp from opportunities where contact_id = v_c;
  perform pg_temp.ok(v_opp.stage = 'call' and v_opp.source_channel_code = 'COLD_EMAIL'
                     and v_opp.converting_touchpoint_id = v_t and v_opp.first_call_on = date '2026-09-30'
                     and v_opp.organization_id = v_org,
                     'Interested -> opportunity opened at "call" with its source channel');
  select * into v_con from contacts where id = v_c;
  perform pg_temp.ok(v_con.newsletter_status = 'subscribed' and v_con.email_status = 'valid',
                     'Call booked -> added to the quarterly newsletter (and the email is marked valid)',
                     v_con.newsletter_added_via);
  perform pg_temp.ok((select reminder_type || ' ' || due_on from reminders where contact_id = v_c and status = 'open')
                     = 'post_call 2026-09-30', 'Reminder to log the call on the call date');

  -- a colleague at the same organization also books a call: still one lead
  insert into contacts (organization_id, first_name, last_name, email, source_channel_code, owner_id)
  values (v_org, 'Theo', 'Tester', 'theo@testharbor.example', 'EVENT', 1) returning id into v_c2;
  insert into touchpoints (contact_id, touch_type, touched_at, outcome_code)
  values (v_c2, 'email', '2026-09-25 10:00 America/Denver', 'INTERESTED');
  perform pg_temp.ok((select count(*) from opportunities where organization_id = v_org) = 1,
                     'A second person at the same organization does not create a second opportunity');

  -- pipeline --------------------------------------------------------------------
  insert into touchpoints (contact_id, touch_type, touched_at, outcome_code, notes)
  values (v_c, 'meeting', '2026-09-30 14:00 America/Denver', 'CALL_HELD', 'Intro call');
  insert into touchpoints (contact_id, touch_type, touched_at, outcome_code)
  values (v_c, 'meeting', '2026-10-06 14:00 America/Denver', 'HOT');
  select * into v_opp from opportunities where contact_id = v_c;
  perform pg_temp.ok(v_opp.stage = 'hot' and v_opp.hot_on = date '2026-10-06', 'Hot -> stage hot with its date');
  insert into touchpoints (contact_id, touch_type, touched_at, outcome_code)
  values (v_c, 'meeting', '2026-10-20 14:00 America/Denver', 'READY_TO_ONBOARD');
  select * into v_opp from opportunities where contact_id = v_c;
  perform pg_temp.ok(v_opp.stage = 'onboarding' and v_opp.onboarding_started_on = date '2026-10-20',
                     'Wants to hire us -> onboarding');
  update opportunities set stage = 'funded', funded_aum = 2500000 where id = v_opp.id;
  select * into v_opp from opportunities where id = v_opp.id;
  perform pg_temp.ok(v_opp.funded_on = local_today() and v_opp.closed_on = v_opp.funded_on,
                     'Moving the stage to funded stamps the funding date');
  begin
    update opportunities set stage = 'funded', funded_aum = null where id = v_opp.id;
    perform pg_temp.ok(false, 'A funded account must have its funded AUM');
  exception when check_violation then
    perform pg_temp.ok(true, 'A funded account must have its funded AUM');
  end;

  -- unsubscribe / do not contact --------------------------------------------------
  insert into contacts (segment_code, first_name, last_name, email, state, source_channel_code, owner_id)
  values ('IND_ROBO', 'Una', 'Subscribe', 'una@mail.example', 'UT', 'COLD_EMAIL', 2) returning id into v_c3;
  insert into touchpoints (contact_id, touch_type, touched_at)
  values (v_c3, 'email', '2026-09-10 09:00 America/Denver');
  update touchpoints set outcome_code = 'UNSUBSCRIBE', responded_at = '2026-09-11 08:00 America/Denver'
   where contact_id = v_c3;
  select * into v_con from contacts where id = v_c3;
  perform pg_temp.ok(v_con.do_not_contact and v_con.dnc_reason = 'Asked not to be contacted'
                     and not exists (select 1 from reminders where contact_id = v_c3 and status = 'open'),
                     'Unsubscribe -> do-not-contact, open reminders cleared');
  begin
    insert into touchpoints (contact_id, touch_type, touched_at) values (v_c3, 'email', '2026-09-20 09:00 America/Denver');
    perform pg_temp.ok(false, 'Emailing someone on the do-not-contact list is blocked');
  exception when raise_exception then
    perform pg_temp.ok(true, 'Emailing someone on the do-not-contact list is blocked', sqlerrm);
  end;

  -- bounce -> wrong-email list -> fixed ----------------------------------------------
  insert into contacts (organization_id, first_name, last_name, email, source_channel_code, owner_id)
  values (v_org, 'Bo', 'Unce', 'bo.unce@testharbor.example', 'COLD_EMAIL', 1) returning id into v_c4;
  insert into touchpoints (contact_id, touch_type, touched_at, outcome_code)
  values (v_c4, 'email', '2026-09-14 09:00 America/Denver', 'BOUNCED');
  perform pg_temp.ok((select email_status from contacts where id = v_c4) = 'bounced'
                     and exists (select 1 from v_wrong_emails where contact_id = v_c4)
                     and (select due_on from reminders where contact_id = v_c4 and status = 'open'
                           and reminder_type = 'fix_contact_info') = date '2026-09-16',
                     'Bounce -> wrong-email list + "fix the email" reminder in 2 days');
  update contacts set email = 'bunce@testharbor.example' where id = v_c4;
  perform pg_temp.ok((select email_status from contacts where id = v_c4) = 'unverified'
                     and not exists (select 1 from reminders where contact_id = v_c4 and status = 'open'
                                      and reminder_type = 'fix_contact_info'),
                     'Correcting the email takes them off the list and closes the reminder');

  -- university flag --------------------------------------------------------------------
  insert into contacts (segment_code, first_name, last_name, email, state)
  values ('IND_OCIO', 'Una', 'Versity', 'u.versity@law.utah.edu', 'UT') returning id into v_c5;
  perform pg_temp.ok((select is_university_affiliated from contacts where id = v_c5),
                     'A .edu email address is flagged as a university contact');

  -- outcome must fit the touch -----------------------------------------------------------
  begin
    insert into touchpoints (contact_id, touch_type, touched_at, outcome_code)
    values (v_c5, 'email', now(), 'VOICEMAIL');
    perform pg_temp.ok(false, 'A phone-only outcome cannot be saved on an email');
  exception when raise_exception then
    perform pg_temp.ok(true, 'A phone-only outcome cannot be saved on an email', sqlerrm);
  end;

  -- AI suggests, a person confirms ---------------------------------------------------------
  insert into contacts (segment_code, first_name, last_name, email, state, source_channel_code)
  values ('IND_OCIO', 'Ada', 'Suggest', 'ada.suggest@mail.example', 'UT', 'REFERRAL') returning id into v_c6;
  insert into touchpoints (contact_id, touch_type, touched_at)
  values (v_c6, 'email', '2026-09-21 09:00 America/Denver') returning id into v_t;
  update touchpoints
     set outcome_code = 'INTERESTED', ai_suggested_outcome = 'INTERESTED', ai_confidence = 0.91,
         ai_reason = 'Reply asks for a call', outcome_status = 'needs_review',
         responded_at = '2026-09-22 10:00 America/Denver', follow_up_on = '2026-09-29'
   where id = v_t;
  perform pg_temp.ok(not exists (select 1 from opportunities where contact_id = v_c6)
                     and exists (select 1 from v_outcome_review_queue where touchpoint_id = v_t),
                     'A suggested outcome waits in the review queue and changes nothing yet');
  perform confirm_outcome(v_t, null, null, 1);
  perform pg_temp.ok(exists (select 1 from opportunities where contact_id = v_c6 and source_channel_code = 'REFERRAL')
                     and (select outcome_status from touchpoints where id = v_t) = 'confirmed',
                     'One click to confirm -> the rules run (opportunity opened)');

  -- cold calls: three unanswered dials, then back to quarterly -------------------------------
  insert into contacts (organization_id, first_name, last_name, email, phone, source_channel_code, owner_id)
  values (v_org, 'Cal', 'Ler', 'cal.ler@testharbor.example', '(801) 555-0100', 'COLD_EMAIL', 2) returning id into v_c7;
  insert into touchpoints (contact_id, touch_type, touched_at, outcome_code)
  values (v_c7, 'call', '2026-09-01 10:00 America/Denver', 'NO_ANSWER');
  perform pg_temp.ok((select due_on from reminders where contact_id = v_c7 and status = 'open') = date '2026-09-08',
                     'First unanswered call -> try again in a week');
  insert into touchpoints (contact_id, touch_type, touched_at, outcome_code)
  values (v_c7, 'call', '2026-09-08 10:00 America/Denver', 'VOICEMAIL'),
         (v_c7, 'call', '2026-09-15 10:00 America/Denver', 'NO_ANSWER');
  perform pg_temp.ok((select due_on from reminders where contact_id = v_c7 and status = 'open') = date '2026-12-14',
                     'Third unanswered call in a row -> back to quarterly (Dec 14)');

  -- RFPs flow into the pipeline -------------------------------------------------------------------
  insert into organizations (name, segment_code, state) values ('Test Summit Foundation', 'ORG_OTHER', 'ID') returning id into v_org2;
  insert into contacts (organization_id, first_name, last_name, email, source_channel_code)
  values (v_org2, 'Rita', 'Proposal', 'rita@testsummit.example', 'RFP') returning id into v_c8;
  insert into rfps (organization_id, contact_id, title, status, due_on, est_mandate_aum)
  values (v_org2, v_c8, 'Test OCIO RFP', 'intent_to_bid', '2026-10-30', 12000000) returning id into v_rfp;
  perform pg_temp.ok((select due_on from reminders where rfp_id = v_rfp and status = 'open') = date '2026-10-23',
                     'RFP due Oct 30 -> reminder a week ahead');
  update rfps set status = 'submitted', submitted_on = '2026-10-28' where id = v_rfp;
  update rfps set status = 'finalist', decision_on = '2026-11-20' where id = v_rfp;
  select * into v_opp from opportunities where rfp_id = v_rfp;
  perform pg_temp.ok(v_opp.stage = 'call' and v_opp.source_channel_code = 'RFP'
                     and (select count(*) from touchpoints where rfp_id = v_rfp) = 2,
                     'RFP submitted -> finalist is logged and opens an opportunity');
  update rfps set status = 'won', decision_on = '2026-12-15' where id = v_rfp;
  perform pg_temp.ok((select stage from opportunities where rfp_id = v_rfp) = 'onboarding', 'RFP won -> onboarding');

  -- snooze and wake ---------------------------------------------------------------------------------
  select * into v_rem from reminders where contact_id = v_c7 and status = 'open';
  perform snooze_reminder(v_rem.id, local_today());
  perform wake_snoozed_reminders();
  perform pg_temp.ok((select status from reminders where id = v_rem.id) = 'open', 'Snoozed reminders come back on their date');
  perform complete_reminder(v_rem.id, 2);
  perform pg_temp.ok((select status || ' by ' || completed_by from reminders where id = v_rem.id) = 'done by 2',
                     'Marking a reminder done closes it for the whole team');

  -- stale opportunities ------------------------------------------------------------------------------
  insert into opportunities (contact_id, stage, source_channel_code, opened_on)
  values (v_c5, 'hot', 'EVENT', local_today() - 60) returning * into v_opp;
  perform flag_stale_opportunities(21);
  perform pg_temp.ok(exists (select 1 from reminders where opportunity_id = v_opp.id and status = 'open'),
                     'An opportunity with no activity in 3 weeks gets a reminder');

  -- one-time migration: history loaded without rules, then follow-ups rebuilt in one pass ---------------
  perform set_config('app.seeding', 'on', true);
  insert into touchpoints (contact_id, touch_type, touched_at, outcome_code, follow_up_on)
  values (v_c2, 'email', '2026-09-26 09:00 America/Denver', 'NOT_NOW', '2026-11-02');
  perform set_config('app.seeding', 'off', true);
  update reminders set status = 'dismissed' where contact_id = v_c2 and status = 'open';
  v_n := rebuild_follow_up_reminders();
  perform pg_temp.ok(v_n >= 1
                     and (select due_on from reminders where contact_id = v_c2 and status = 'open') = date '2026-11-02',
                     'After a history import, one pass rebuilds everyone''s next follow-up');

  -- flag list from Jon ------------------------------------------------------------------------------
  insert into flag_rules (match_on, pattern, flag, reason) values ('org_name', 'Test Harbor', 'do_not_contact', 'Test rule');
  perform reapply_flag_rules();
  perform pg_temp.ok((select do_not_contact from organizations where id = v_org)
                     and (select bool_and(do_not_contact) from contacts where organization_id = v_org),
                     'A new do-not-contact rule flags the organization and everyone at it');
end
$tests$;

-- row-level security (Supabase only): signed-in team members who have passed the second factor see
-- everything; a member without the second factor, a stranger, or anyone not signed in sees nothing.
-- (db/001 added the second-factor requirement; the JWT claims carry "aal": "aal2" after 2FA.)
\set QUIET on
select to_regprocedure('auth.uid()') is not null as has_auth \gset
\if :has_auth
update team_members set auth_user_id = '00000000-0000-0000-0000-000000000001' where id = 1;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-000000000001", "role": "authenticated", "aal": "aal2"}';
select count(*) as member_sees from contacts \gset
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-000000000001", "role": "authenticated", "aal": "aal1"}';
select count(*) as member_aal1_sees from contacts \gset
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000009';
set local request.jwt.claims = '{"sub": "00000000-0000-0000-0000-000000000009", "role": "authenticated", "aal": "aal2"}';
select count(*) as stranger_sees from contacts \gset
reset role;
set local role anon;
select count(*) as anon_sees from contacts \gset
reset role;
insert into test_results (test, ok, detail)
values ('A signed-in team member with the second factor can read the CRM', :member_sees > 0, :'member_sees' || ' contacts visible'),
       ('A team member without the second factor sees nothing', :member_aal1_sees = 0, null),
       ('A signed-in stranger sees nothing', :stranger_sees = 0, null),
       ('Someone who is not signed in sees nothing', :anon_sees = 0, null);
\endif

\set QUIET off
select n, case when ok then 'PASS' else 'FAIL' end as result, test, left(coalesce(detail, ''), 80) as detail
  from test_results order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from test_results;
rollback;
