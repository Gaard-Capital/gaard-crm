-- =====================================================================
-- Demo: a new sourcing batch goes through the import pipeline.
-- Rows come from db/mock/import_demo/new_prospects_batch.csv (the outreach
-- sheet's own column names). Run after seed.sql.
-- =====================================================================

with batch as (
  insert into public.import_batches (label, source_file, default_segment_code, default_channel_code,
                                     default_touch_type, event_id, owner_id)
  values ('Sept 2026 sourcing: Jackson Hole Philanthropy Retreat', 'new_prospects_batch.csv', 'ORG_NONPROFIT', 'EVENT', 'email', 13, 1)
  returning id)
insert into public.import_rows (batch_id, row_number, date_added, source, contact, first_name, email, org, website, linkedin, added_on_linkedin, notes, date_outreached, outcome, next_steps, phone, aum, state, segment)
select batch.id, v.* from batch, (values
  (2, '9/18/26', 'Jackson Hole retreat attendee list', 'Sofia Havili', 'Sofia', '  SOFIA.HAVILI@PLATTEVDCOALITION.EXAMPLE ', 'Platte Valley Dance Coalition', 'https://www.plattevdcoalition.example', null, null, null, null, null, null, null, null, 'WY', null),
  (3, '9/18/26', 'Jackson Hole retreat attendee list', 'Mark Jimenez', 'Mark', '  MJIMENEZ@FRIENDSOQUIRRHPARKS.EXAMPLE ', 'Friends of Oquirrh Parks', 'https://www.friendsoquirrhparks.example', null, null, null, null, null, null, null, null, 'UT', null),
  (4, '9/18/26', 'Jackson Hole retreat attendee list', 'Olivia Hawkins', 'Olivia', '  OLIVIA@BEARRSEPARTNERS.EXAMPLE ', 'Bear River Science Education Partners', 'https://www.bearrsepartners.example', null, null, null, null, null, null, null, null, 'UT', null),
  (5, '9/18/26', 'Jackson Hole retreat attendee list', 'Leilani Lewis', 'Leilani', '  LEILANI.LEWIS@FRIENDSTIMPANOGOSPARKS.EXAMPLE ', 'Friends of Timpanogos Parks', 'https://www.friendstimpanogosparks.example', null, null, null, null, null, null, null, null, 'UT', null),
  (6, '9/18/26', 'Jackson Hole retreat attendee list', 'Victoria Rogers', 'Victoria', 'vrogers@friendsmvparks.example', 'Friends of Morgan Valley Parks', null, null, null, null, null, null, null, null, null, null, null),
  (7, '2026-09-18', 'Retreat dinner', 'Kenneth Pena', 'Kenneth', null, 'Davis County Community Foundation', null, 'http://linkedin.com/in/KENNETH-PENA-B0091189/?trk=retreat', null, null, null, null, null, null, null, null, null),
  (8, '2026-09-18', 'Retreat dinner', 'Timothy Tsosie', 'Timothy', null, 'Summit County Growers Association', null, 'http://linkedin.com/in/TIMOTHY-TSOSIE-0539F24B/?trk=retreat', null, null, null, null, null, null, null, null, null),
  (9, '9/19/26', 'Met at Jackson Hole Philanthropy Retreat', 'Angela Martinez', 'Angela', 'angela.martinez@boxefbnetwork.example', 'BOX ELDER FOOD BANK NETWORK', null, null, null, 'New board treasurer; interested in reserve policy.', null, null, null, null, null, 'UT', null),
  (10, '9/19/26', 'Met at Jackson Hole Philanthropy Retreat', 'Donald Romero', 'Donald', 'donald.romero@hebervcaservices.example', 'Heber Valley Clean Air Services, Inc.', null, null, null, 'New board treasurer; interested in reserve policy.', null, null, null, null, null, 'UT', null),
  (11, '9/19/26', 'Met at Jackson Hole Philanthropy Retreat', 'Kyle Moore', 'Kyle', 'kyle.moore@daviscseinitiative.example', null, 'https://www.daviscseinitiative.example/about-us', null, null, 'New board treasurer; interested in reserve policy.', null, null, null, null, null, 'UT', null),
  (12, '9/19/26', 'Met at Jackson Hole Philanthropy Retreat', 'Stephen White', 'Stephen', 'stephen.white@summitcmcoalition.example', 'Summit County Mentoring Coalition (Utah)', null, null, null, 'New board treasurer; interested in reserve policy.', null, null, null, null, null, 'UT', null),
  (13, '9/19/26', 'Met at Jackson Hole Philanthropy Retreat', 'Lawrence Fisher', 'Lawrence', 'lawrence.fisher@tooelevaassociation.example', 'Tooele Valley Arts Association', null, null, null, 'New board treasurer; interested in reserve policy.', null, null, null, null, null, 'UT', null),
  (14, '9/19/26', 'Retreat attendee list', 'Michelle Yazzie', 'Michelle', 'michelle@greatbasinearlylearningleagues.example', 'Great Basin Early Learning Leagues', null, null, null, null, null, null, null, null, null, 'UT', null),
  (15, '9/19/26', 'Retreat attendee list', 'Eric Wagner', 'Eric', 'eric@musiccouncilofpowderrivers.example', 'Music Council of Powder Rivers', null, null, null, null, null, null, null, null, null, 'WY', null),
  (16, '9/19/26', 'Business card', 'Peter Rogers', 'Peter', 'peter.rogers.board@castlevvcouncil.example', 'Castle Valley Veterans Council', null, null, null, 'Card says a different email than we have.', null, null, null, null, null, null, null),
  (17, '9/18/26', 'Retreat attendee list', 'Greta Lindqvist', 'Greta', 'greta.lindqvist@summitpeakwealth.example', 'Summit Peak Wealth Partners', null, null, null, null, null, null, null, null, null, 'ID', 'Other'),
  (18, '9/18/26', 'Retreat attendee list', 'Marcus Bell', 'Marcus', 'mbell@beehivestatecu.example', 'Beehive State Credit Union', null, null, null, null, null, null, null, null, null, 'UT', 'Other'),
  (19, '9/19/26', 'Retreat dinner', 'Helen Okafor', 'Helen', 'helen.okafor@summitridge.edu.example', null, null, null, null, 'Professor; knows the founder from the business school.', null, null, null, null, '$4.5M', 'UT', 'OCIO'),
  (20, '9/19/26', 'Retreat dinner', 'Samuel Begay', 'Samuel', 'sbegay@canyonlandsstate.edu.example', 'Canyonlands State University Foundation', null, null, null, null, null, null, null, null, null, 'ID', 'Other'),
  (21, '9/18/26', 'Retreat attendee list', 'Priya Raman', 'Priya', 'priya.raman@tetonwatershedtrust.example', 'Teton Watershed Trust', 'tetonwatershedtrust.example', null, null, null, null, null, null, null, '12,000,000', 'WY', 'Nonprofit'),
  (22, '9/19/26', 'Business card', 'Priya Raman', 'Priya', 'Priya.Raman@TetonWatershedTrust.example', 'Teton Watershed Trust', null, null, null, null, null, null, null, '(307) 555-0142', null, 'WY', 'Nonprofit'),
  (23, '9/19/26', 'Retreat attendee list', 'Luis Ortega', 'Luis', 'N/A', 'Star Valley Arts Guild', null, 'https://www.linkedin.com/in/luis-ortega-starvalley', null, null, null, null, null, null, null, 'WY', 'Nonprofit'),
  (24, '9/19/26', 'Retreat attendee list', null, null, null, null, null, null, null, '(blank row from the sheet)', null, null, null, null, null, null, null),
  (25, 'Sep 18, 2026', 'Jackson Hole retreat attendee list', 'Brittany Porter', 'Brittany', 'bporter@tetonvalleyyouthorchestra.example', 'Teton Valley Youth Orchestra', 'https://tetonvalleyyouthorchestra.example', null, 'Yes', null, '9/22/26', 'No response', null, null, '$850k', 'WY', 'Nonprofit'),
  (26, 'Sep 18, 2026', 'Jackson Hole retreat attendee list', 'Bruce Porter', 'Bruce', 'bporter@sweetwaterfoodbankalliance.example', 'Sweetwater Food Bank Alliance', 'https://sweetwaterfoodbankalliance.example', null, 'No', null, '9/22/26', 'No thank you, we already have an advisor we are happy with.', null, null, '$2.1M', 'WY', 'Nonprofit'),
  (27, 'Sep 18, 2026', 'Jackson Hole retreat attendee list', 'Christopher Edwards', 'Christopher', 'cedwards@jacksonholewildlifesociety.example', 'Jackson Hole Wildlife Society', 'https://jacksonholewildlifesociety.example', null, 'Yes', null, '9/22/26', 'OOO until 10/6', null, null, '$6.3M', 'WY', 'Nonprofit'),
  (28, 'Sep 18, 2026', 'Jackson Hole retreat attendee list', 'Isabella Larsen', 'Isabella', 'ilarsen@snakeriverwatershedcouncil.example', 'Snake River Watershed Council', 'https://snakeriverwatershedcouncil.example', null, 'TRUE', null, '9/23/26', 'Interested - call scheduled', 'Call Thu 10/1 at 2pm', null, '$3.4M', 'ID', 'Nonprofit'),
  (29, 'Sep 18, 2026', 'Jackson Hole retreat attendee list', 'Rachel Barnes', 'Rachel', 'rbarnes@windriverliteracyproject.example', 'Wind River Literacy Project', 'https://windriverliteracyproject.example', null, 'TRUE', null, '9/23/26', 'left vm', null, null, '$400k', 'WY', 'Nonprofit'),
  (30, 'Sep 18, 2026', 'Jackson Hole retreat attendee list', 'Alice Walker', 'Alice', 'awalker@absarokatrailscoalition.example', 'Absaroka Trails Coalition', 'https://absarokatrailscoalition.example', null, '9/19/26', null, '9/23/26', 'Thanks for the note. Please check back after our board meeting in November.', null, null, '$1.2M', 'WY', 'Nonprofit'),
  (31, 'Sep 18, 2026', 'Jackson Hole retreat attendee list', 'Janet Tucker', 'Janet', 'jtucker@plattevalleyseniorservices.example', 'Platte Valley Senior Services', 'https://plattevalleyseniorservices.example', null, 'TRUE', null, null, null, null, null, null, 'WY', 'Nonprofit'),
  (32, '9/19/26', 'Workshop waitlist', 'Keanu Mahe', 'Keanu', 'keanu.mahe@mail.example', null, null, null, null, null, null, null, null, null, '40k', 'UT', 'Robo')
) as v(row_number, date_added, source, contact, first_name, email, org, website, linkedin, added_on_linkedin, notes, date_outreached, outcome, next_steps, phone, aum, state, segment);

-- 2. run it: every row is matched against the CRM and labelled
select jsonb_pretty(public.process_import_batch((select max(id) from public.import_batches))) as summary;

select row_number, result, matched_on, left(result_detail, 160) as what_happened
  from public.v_import_results
 where batch_id = (select max(id) from public.import_batches)
 order by row_number;

-- 3. a person answers the "needs_review" rows (in the app this is a button), then run it again
update public.import_rows ir
   set review_decision = case when ir.matched_on = 'similar organization name' and ir.org ilike 'Beehive%'
                              then 'create_new' else 'use_candidate' end
 where ir.batch_id = (select max(id) from public.import_batches) and ir.result = 'needs_review';
select jsonb_pretty(public.process_import_batch((select max(id) from public.import_batches))) as summary_after_review;

-- 4. the old free-text outcomes that need a click: confirm them and the rules run
select touchpoint_id, full_name, organization, provisional_outcome, left(outcome_raw, 60) as old_outcome_text
  from public.v_outcome_review_queue
 where touchpoint_id in (select touchpoint_id from public.import_rows
                          where batch_id = (select max(id) from public.import_batches));
