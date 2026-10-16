-- Jon's Event ROI Tracker (Marketing_ROI_Sample.xlsx, sheet "Event Tracker"):
-- the 23 events of 2026, loaded into public.events.
--
-- Run by hand in the Supabase SQL Editor. Safe to run twice: an event with the
-- same name and date is not added again.
--
-- How the sheet maps:
--   In-Person -> in_person, Virtual -> virtual, Speaking (firm-hosted) -> in_person, hosted_by_us
--   WYO -> WY; a blank cost -> 0; "150+240+275" -> 665
--   event_type is read from the name: conference, webinar, workshop (workshops,
--   courses, labs), networking (galas, socials, cookouts, fundraisers), other
--   Jon's own counts (contacts, responses, meetings, clients won) and his notes
--   go into notes. The app does not count them: people met, calls and funded
--   are counted from the contacts linked to the event (an import of "People met
--   at an event", or a "Met at event" activity), so nothing is stored twice.
--
-- New ids continue after the highest id in the table, the way the app numbers
-- rows, so they never collide with rows the app added.

begin;

with src (name, event_type, format, hosted_by_us, start_on, state, cost_usd, notes) as (values
  ('Endowment Basics Workshop (Firm-Hosted)',            'workshop',   'in_person', true,  date '2026-02-18', 'UT',   0, 'Jon''s tracker: 12 contacts, 4 responses, 3 meetings, 1 client won. Speaking. Co-hosted with state nonprofit association.'),
  ('Statewide Giving Day Kickoff',                       'other',      'virtual',   false, date '2026-04-02', 'UT',   0, 'Jon''s tracker: 8 contacts, 3 responses, 1 meeting. One contact had intro call with principal.'),
  ('Conservation Partner Coffee Meeting',                'networking', 'in_person', false, date '2026-04-06', 'UT',   0, 'Jon''s tracker: 2 contacts, 1 response, 0 meetings.'),
  ('Nonprofit Finance Workshop',                         'workshop',   'virtual',   false, date '2026-04-08', 'UT',   0, 'Jon''s tracker: 9 contacts, 2 responses, 1 meeting.'),
  ('Giving Day Strategy Webinar: Matches and Challenges','webinar',    'virtual',   false, date '2026-04-10', 'WY',   0, 'Jon''s tracker: 7 contacts, 2 responses, 0 meetings. 1 not interested, 1 wrong contact.'),
  ('Children''s Charity Spring Gala',                    'networking', 'in_person', false, date '2026-04-23', 'UT',   0, 'Jon''s tracker: 5 contacts, 2 responses, 1 meeting. Met five board members and staff.'),
  ('Community Foundation Awards Gala',                   'networking', 'in_person', false, date '2026-05-12', 'UT',   0, 'Jon''s tracker: 3 contacts. Met development lead from a local nonprofit.'),
  ('Mission Sustainability Series: Session 2',           'webinar',    'virtual',   false, date '2026-05-19', 'UT',  50, 'Jon''s tracker: 3 contacts. Saw two organizations we have already contacted; not interested at this time.'),
  ('State Nonprofit Annual Conference',                  'conference', 'in_person', false, date '2026-05-27', 'WY', 665, 'Jon''s tracker: 18 contacts, 4 responses. Cost 150 + 240 + 275.'),
  ('Summer Garden Social',                               'networking', 'in_person', false, date '2026-06-04', 'UT',   0, 'Jon''s tracker: 6 contacts, 2 responses. Evening event at a local nature center.'),
  ('Board Member Backyard Cookout',                      'networking', 'in_person', false, date '2026-06-17', 'UT',   0, 'Jon''s tracker: 4 contacts, 2 responses, 1 meeting.'),
  ('County Nonprofit Mini-Conference',                   'conference', 'in_person', false, date '2026-06-23', 'UT',   0, 'Jon''s tracker: 6 contacts, 3 responses, 1 meeting. Afternoon session at a county government building.'),
  ('Music Night Fundraiser',                             'networking', 'in_person', false, date '2026-06-26', 'UT',   0, null),
  ('Nonprofit Accounting Lab Series',                    'workshop',   'virtual',   false, date '2026-07-14', 'UT',  40, 'Jon''s tracker: 5 contacts.'),
  ('Nonprofit Foundations Course',                       'workshop',   'virtual',   false, date '2026-07-22', 'UT',   0, 'Jon''s tracker: 8 contacts, responses to be determined.'),
  ('Nonprofit Association Office Hours',                 'other',      'virtual',   false, date '2026-07-29', 'ID',   0, 'Jon''s tracker: 3 contacts, responses to be determined.'),
  ('Giving Day Planning Session',                        'other',      'virtual',   false, date '2026-08-12', 'UT',   0, null),
  ('Nonprofit Network Fundraiser - Local Brewery',       'networking', 'in_person', false, date '2026-08-25', 'UT',   0, 'Jon''s tracker: 2 contacts, responses to be determined. Met an executive director and a board member.'),
  ('Workplace Benefits Webinar',                         'webinar',    'virtual',   false, date '2026-09-03', 'WY',   0, null),
  ('Nonprofit Impact Celebration',                       'networking', 'in_person', false, date '2026-09-15', 'UT',   0, null),
  ('Fundraising Fundamentals Webinar',                   'webinar',    'virtual',   false, date '2026-09-24', 'ID',  85, 'May or may not attend.'),
  ('State Nonprofit Annual Conference',                  'conference', 'in_person', false, date '2026-09-29', 'ID', 195, 'Jon''s tracker: 21 contacts, responses to be determined.'),
  ('Grant Writing Workshop',                             'workshop',   'virtual',   false, date '2026-10-08', 'ID', 125, 'May or may not attend.')
),
fresh as (
  select s.*, row_number() over (order by s.start_on, s.name) as n
    from src s
   where not exists (select 1 from public.events e where e.name = s.name and e.start_on = s.start_on)
)
insert into public.events (id, name, event_type, format, hosted_by_us, start_on, state, cost_usd, notes)
select (select coalesce(max(id), 0) from public.events) + n,
       name, event_type, format, hosted_by_us, start_on, state, cost_usd, notes
  from fresh;

commit;

-- What is in the table now
select count(*) as events, count(*) filter (where start_on between date '2026-02-18' and date '2026-10-08') as in_jons_dates
  from public.events;
