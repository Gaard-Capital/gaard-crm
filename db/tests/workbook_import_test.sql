-- =====================================================================
-- GAARD Capital CRM · workbook import tests (migrations 7 to 10)
--
-- Builds small tables shaped like Jon's tabs, runs them through
-- import_gaard_tab(), and checks what lands in the CRM. Also covers the
-- review helpers (rematch_outcomes, merge_contacts, spread_overdue_follow_ups).
-- Everything rolls back, so it is safe on a database with data in it:
--     psql "$DATABASE_URL" -f db/tests/workbook_import_test.sql
-- Prints one line per check and a final count of failures.
--
-- Written Oct 14, 2026 against the rebuilt migrations; the Oct 3 version of
-- this file was lost with the original repo zip.
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

-- tables shaped like the tabs (headers exactly as the sheets have them)
create temp table tab_master (
  "Date Sourced" text, "Source" text, "Contact" text, "First Name" text, "Email" text, "Organization" text,
  "Website" text, "Date Outreached" text, "Outcome" text, "Next Steps" text, "Reach Out Again?" text, "Shoe Size" text);
create temp table tab_wrong ("Contact" text, "Email" text, "Organization" text, "a" text);
create temp table tab_onb (
  "Contact" text, "Email" text, "Organization" text, "Sent Onboarding" text, "Account Funded Date" text, "AUM" text, "Channel" text);
create temp table tab_loyal (
  "Client Type" text, "Name" text, "Contact" text, "Mailing Address" text, "Thanksgiving Card" text, "Referral Check in" text);
create temp table tab_bg (
  "Organization" text, "Contact" text, "Email" text, "Plans Served" text, "Commissions" text, "Shared Employers" text,
  "Advertises Retirement" text, "City" text, "State" text);

do $tests$
declare
  v_owner  bigint;
  v_r      jsonb;
  v_n      int; v_n2 int;
  v_c      bigint; v_c2 bigint; v_dup bigint;
  v_org    bigint;
  v_opp    opportunities;
  v_t      bigint; v_t2 bigint;
  v_today  date := local_today();
begin
  insert into team_members (full_name, email, role) values ('Test Owner', 'test.owner@testharbor.example', 'Tester')
  returning id into v_owner;

  -- helpers ------------------------------------------------------------------------------------------
  perform pg_temp.ok(resolve_header('Date Outreached') = 'date_outreached'
                     and resolve_header('Reach Out Again?') = 'reach_out_again'
                     and resolve_header('Account Funded Date') = 'funded_on',
                     'Headers resolve whatever the spacing, case and punctuation');
  perform pg_temp.ok(resolve_header('Name', '{"name": "org"}') = 'org',
                     'A tab profile''s header map wins over the shared aliases');
  perform pg_temp.ok(resolve_channel('cold outreach', 'EVENT') = 'COLD_EMAIL'
                     and resolve_channel('Met at conference', 'COLD_EMAIL') = 'EVENT'
                     and resolve_channel('???', 'RFP') = 'RFP',
                     'Words in a Source column resolve to a channel code, with a fallback');
  perform pg_temp.ok(parse_yes_no('Yes') and not parse_yes_no('N') and parse_yes_no('maybe') is null,
                     'parse_yes_no reads yes / no / anything else');
  perform pg_temp.ok(not history_load(), 'history_load() is off unless an import turns it on');

  -- check_upload_headers ------------------------------------------------------------------------------
  select count(*) filter (where maps_to is not null), count(*) filter (where note like 'NOT RECOGNIZED%')
    into v_n, v_n2
    from check_upload_headers('tab_master', 'Master List 2025');
  perform pg_temp.ok(v_n = 11 and v_n2 = 1,
                     'check_upload_headers maps the known headers and names the one it does not know',
                     v_n || ' mapped, ' || v_n2 || ' unknown');

  -- Master List tab: a history load -------------------------------------------------------------------
  insert into tab_master values
    ('1/15/2025', 'Candid', 'Pat Harbor', 'Pat', 'pat.harbor@testharbor.example', 'Test Harbor Foundation',
     'testharbor.example', '2/1/2025', 'No response', 'Try again in Q3', 'Yes', '11'),
    ('1/16/2025', 'Candid', 'Lee Quay', 'Lee', 'lee.quay@testquay.example', 'Test Quay Trust',
     'testquay.example', '2/2/2025', 'Interested, wants the deck', 'Send deck', null, null),
    ('1/17/2025', 'Candid', 'Sam Pier', 'Sam', 'sam.pier@testpier.example', 'Test Pier Fund',
     'testpier.example', null, null, null, 'No', null);
  v_r := import_gaard_tab('tab_master', 'Master List 2025', v_owner);
  perform pg_temp.ok((v_r ->> 'batch_id') is not null
                     and (select count(*) from contacts where legacy_ref like 'Master List 2025 / row %') = 3,
                     'A Master List tab becomes one contact per row, each pointing back to its sheet row', v_r::text);
  select id, organization_id into v_c, v_org from contacts where email = 'pat.harbor@testharbor.example';
  perform pg_temp.ok((select outcome_code from touchpoints where contact_id = v_c) = 'NO_RESPONSE'
                     and (select outcome_status from touchpoints where contact_id = v_c) = 'confirmed',
                     '"No response" on the sheet is a confirmed NO_RESPONSE touch on Feb 1');
  perform pg_temp.ok(not exists (select 1 from reminders where contact_id = v_c and status in ('open', 'snoozed')),
                     'A history load records the touch but opens no reminder');
  perform pg_temp.ok((select reach_out_again from organizations where name = 'Test Pier Fund') = false
                     and (select reach_out_again from organizations where name = 'Test Harbor Foundation') = true,
                     '"Reach Out Again?" lands on the organization');
  perform pg_temp.ok((select notes from contacts where id = v_c) like '%Shoe Size: 11%',
                     'A column nobody recognised is kept in the contact notes, not lost');
  select id into v_c2 from contacts where email = 'lee.quay@testquay.example';
  perform pg_temp.ok((select outcome_status from touchpoints where contact_id = v_c2) = 'needs_review'
                     and (select ai_suggested_outcome from touchpoints where contact_id = v_c2) = 'INTERESTED',
                     'A phrase inside a longer outcome is suggested and left for a person to confirm');

  -- Wrong Emails tab: header "a" is mapped to Outcome by the profile, every row is bounced ---------------
  insert into tab_wrong values
    ('Pat Harbor', 'pat.harbor@testharbor.example', 'Test Harbor Foundation', null),
    ('Sam Pier',   'sam.pier@testpier.example',     'Test Pier Fund',         'mailbox full');
  v_r := import_gaard_tab('tab_wrong', 'Wrong Emails', v_owner);
  perform pg_temp.ok((select count(*) from contacts where email in ('pat.harbor@testharbor.example', 'sam.pier@testpier.example')) = 2,
                     'Re-importing known emails does not create second people');
  perform pg_temp.ok((select email_status from contacts where id = v_c) = 'bounced'
                     and exists (select 1 from touchpoints where contact_id = v_c and outcome_code = 'BOUNCED' and outcome_status = 'confirmed'),
                     'The Wrong Emails tab marks the contact bounced through the profile''s default outcome');
  perform pg_temp.ok((select notes from contacts where email = 'sam.pier@testpier.example') like '%Outcome (sheet, no date): mailbox full%',
                     'Words in the outcome column with no date are kept in the notes rather than guessed into a touch');

  -- Onboarded tab: the opportunity ------------------------------------------------------------------
  insert into tab_onb values ('Lee Quay', 'lee.quay@testquay.example', 'Test Quay Trust', '3/1/2025', '4/1/2025', '$2,500,000', 'Referral');
  v_r := import_gaard_tab('tab_onb', 'Onboarded', v_owner);
  select * into v_opp from opportunities
   where contact_id = v_c2 or organization_id = (select organization_id from contacts where id = v_c2)
   order by opened_on desc limit 1;
  perform pg_temp.ok(v_opp.stage = 'funded' and v_opp.funded_aum = 2500000 and v_opp.funded_on = date '2025-04-01',
                     'The Onboarded tab opens a funded opportunity with the sheet''s AUM and dates',
                     coalesce(v_opp.stage, 'no opportunity') || ' ' || coalesce(v_opp.funded_aum::text, ''));
  perform pg_temp.ok((select 'client' = any (tags) from contacts where id = v_c2), 'An onboarded contact is tagged client');

  -- Customer Loyalty tab: no email column, matched by name --------------------------------------------
  insert into tab_loyal values ('Nonprofit', 'Test Quay Trust', 'Lee Quay', '1 Quay St, Salt Lake City, UT',
                                to_char(v_today - 200, 'MM/DD/YYYY'), to_char(v_today + 30, 'MM/DD/YYYY'));
  v_r := import_gaard_tab('tab_loyal', 'Customer Loyalty', v_owner);
  perform pg_temp.ok((select count(*) from contacts where name_key = norm_text('Lee Quay')) = 1
                     and coalesce((select mailing_address from contacts where id = v_c2),
                                  (select o.mailing_address from organizations o join contacts c on c.organization_id = o.id where c.id = v_c2))
                         like '1 Quay St%',
                     'Customer Loyalty matches the existing client by name and organization and adds the mailing address');
  perform pg_temp.ok((select status from reminders where contact_id = v_c2 and reminder_type = 'thanksgiving_card') = 'done'
                     and (select status from reminders where contact_id = v_c2 and reminder_type = 'referral_check_in') = 'open',
                     'Past loyalty dates are logged as done, future ones stay open');
  perform pg_temp.ok((select next_referral_check_in from v_client_loyalty where contact_id = v_c2) = v_today + 30,
                     'v_client_loyalty shows the next referral check-in');

  -- Benefit Groups tab ---------------------------------------------------------------------------------
  insert into tab_bg values ('Test Benefits Group', 'Kim Dock', 'kim.dock@testbenefits.example', '12', '$45,000',
                             'Acme Testing', 'Yes', 'Provo', 'UT');
  v_r := import_gaard_tab('tab_bg', 'Benefit Groups', v_owner);
  perform pg_temp.ok((select plans_served from v_benefit_groups where name = 'Test Benefits Group') = 12
                     and (select commissions from v_benefit_groups where name = 'Test Benefits Group') = 45000
                     and (select advertises_retirement from v_benefit_groups where name = 'Test Benefits Group'),
                     'A benefit group''s plans, commissions and flags land on the organization and show in v_benefit_groups');

  -- rematch_outcomes: aliases added after an import ---------------------------------------------------
  insert into touchpoints (contact_id, touch_type, touched_at, outcome_status, outcome_raw)
  values (v_c, 'email', now() - interval '10 days', 'needs_review', 'misc, should follow up?') returning id into v_t;
  insert into touchpoints (contact_id, touch_type, touched_at, outcome_status, outcome_raw)
  values (v_c, 'email', now() - interval '9 days', 'needs_review', 'Not interested') returning id into v_t2;
  v_r := rematch_outcomes();
  perform pg_temp.ok((select outcome_status from touchpoints where id = v_t) = 'needs_review'
                     and (select ai_suggested_outcome from touchpoints where id = v_t) = 'NOT_NOW',
                     'A force_review alias suggests the outcome but leaves the row for a person', v_r::text);
  perform pg_temp.ok((select outcome_status from touchpoints where id = v_t2) = 'confirmed'
                     and (select outcome_code from touchpoints where id = v_t2) = 'NOT_INTERESTED',
                     'An exact alias confirms the outcome');

  -- merge_contacts: the same person twice --------------------------------------------------------------
  insert into contacts (organization_id, first_name, last_name, email, source_channel_code, owner_id)
  values (v_org, 'Patricia', 'Harbor', 'p.harbor@testharbor.example', 'COLD_EMAIL', v_owner) returning id into v_dup;
  insert into touchpoints (contact_id, touch_type, touched_at, outcome_code) values (v_dup, 'call', now() - interval '3 days', 'NO_ANSWER');
  select count(*) into v_n from touchpoints where contact_id = v_c;
  v_r := merge_contacts(v_c, v_dup);
  perform pg_temp.ok(not exists (select 1 from contacts where id = v_dup)
                     and (select count(*) from touchpoints where contact_id = v_c) = v_n + 1,
                     'merge_contacts keeps one row and moves the other''s touches across', v_r::text);

  -- spread_overdue_follow_ups: the backlog ---------------------------------------------------------------
  insert into reminders (reminder_type, contact_id, organization_id, due_on, title, assigned_to, created_by)
  select 'follow_up', v_c, v_org, v_today - g, 'Overdue test follow-up ' || g, v_owner, 'test'
    from generate_series(10, 19) g;
  v_n := spread_overdue_follow_ups(2);
  perform pg_temp.ok(v_n >= 10
                     and not exists (select 1 from reminders where contact_id = v_c and status = 'open' and due_on < v_today)
                     and (select max(due_on) from reminders where contact_id = v_c and status = 'open') <= v_today + 13,
                     'spread_overdue_follow_ups re-dates the overdue follow-ups over the next weeks', v_n || ' re-dated');
end
$tests$;

\set QUIET off
select n, case when ok then 'PASS' else 'FAIL' end as result, test, left(coalesce(detail, ''), 80) as detail
  from test_results order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from test_results;
rollback;
