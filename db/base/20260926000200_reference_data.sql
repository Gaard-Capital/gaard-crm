-- =====================================================================
-- GAARD Capital CRM · Migration 2 of 6 · Reference data
--
-- Starting values for the lookup tables. Everything here is meant to be
-- edited: Jon's segment breakdown, flag list and standardized outcomes
-- replace these rows once he sends them.
-- =====================================================================

insert into public.us_states (code, name, is_focus) values
  ('AL','Alabama',false),('AK','Alaska',false),('AZ','Arizona',false),('AR','Arkansas',false),
  ('CA','California',true),('CO','Colorado',false),('CT','Connecticut',false),('DE','Delaware',false),
  ('DC','District of Columbia',false),('FL','Florida',false),('GA','Georgia',false),('HI','Hawaii',false),
  ('ID','Idaho',true),('IL','Illinois',false),('IN','Indiana',false),('IA','Iowa',false),
  ('KS','Kansas',false),('KY','Kentucky',false),('LA','Louisiana',false),('ME','Maine',false),
  ('MD','Maryland',false),('MA','Massachusetts',false),('MI','Michigan',false),('MN','Minnesota',false),
  ('MS','Mississippi',false),('MO','Missouri',false),('MT','Montana',false),('NE','Nebraska',false),
  ('NV','Nevada',false),('NH','New Hampshire',false),('NJ','New Jersey',false),('NM','New Mexico',false),
  ('NY','New York',false),('NC','North Carolina',false),('ND','North Dakota',false),('OH','Ohio',false),
  ('OK','Oklahoma',false),('OR','Oregon',false),('PA','Pennsylvania',false),('RI','Rhode Island',false),
  ('SC','South Carolina',false),('SD','South Dakota',false),('TN','Tennessee',false),('TX','Texas',false),
  ('UT','Utah',true),('VT','Vermont',false),('VA','Virginia',false),('WA','Washington',false),
  ('WV','West Virginia',false),('WI','Wisconsin',false),('WY','Wyoming',true);

-- Segments and sub-levels (Jon: "segments and then sub-levels to those segments")
insert into public.segments (code, segment_group, name, party_type, sort_order, aliases, description) values
  ('IND_OCIO',      'Individuals',               'OCIO',               'individual',   10, '{ocio,individual,individuals,individual ocio}',            'Individual investors served through the OCIO offering'),
  ('IND_ROBO',      'Individuals',               'Robo-advisor',       'individual',   20, '{robo,robo advisor,robo-advisor,roboadvisor}',             'Individual investors for the robo-advisor'),
  ('ORG_NONPROFIT', 'Organizations',             'Nonprofit',          'organization', 30, '{nonprofit,non-profit,non profit,npo,nonprofits}',         'Nonprofits (endowments, reserves, operating funds)'),
  ('ORG_OTHER',     'Organizations',             'Other organization', 'organization', 40, '{other,other org,organization,foundation,endowment}',      'Foundations, associations and other institutions'),
  ('RET_401K',      'Employer retirement plans', '401(k)',             'organization', 50, '{401k,401(k),small business,small biz,retirement plan}',   'Small businesses sponsoring or starting a 401(k)'),
  ('AFFILIATE',     'Affiliates',                'Affiliate',          'organization', 60, '{affiliate,affiliates,partner}',                            'Rows from the Affiliates tab (exact definition to confirm with Jon)');

-- Channels = how a lead was introduced
insert into public.channels (code, name, sort_order, description) values
  ('COLD_EMAIL', 'Cold email',               10, 'Prospect found through research or a database and emailed'),
  ('COLD_CALL',  'Cold call',                20, 'Prospect reached by phone first (cold call campaigns)'),
  ('EVENT',      'Event',                    30, 'Met at a conference, networking event, webinar or workshop (in person or virtual)'),
  ('REFERRAL',   'Referral / personal intro',40, 'Introduced by someone in the network, a family friend or an affiliate'),
  ('RFP',        'RFP',                      50, 'Request for proposal');

insert into public.touch_types (code, name, channel_code, is_outreach, sort_order) values
  ('email',    'Email',                        'COLD_EMAIL', true,  10),
  ('call',     'Phone call (dial)',            'COLD_CALL',  true,  20),
  ('event',    'Met at an event',              'EVENT',      true,  30),
  ('intro',    'Introduction / referral',      'REFERRAL',   true,  40),
  ('rfp',      'RFP response',                 'RFP',        true,  50),
  ('meeting',  'Call / meeting held',          null,         false, 60),
  ('check_in', 'Check-in / relationship email',null,         false, 70);

insert into public.pipeline_stages (code, label, sort_order, is_closed, description) values
  ('call',       'Call',       10, false, 'Call booked or held'),
  ('hot',        'Hot',        20, false, 'Engaged: follow-up calls, proposal, check-ins'),
  ('onboarding', 'Onboarding', 30, false, 'Wants to hire us: materials and contracts out, waiting on board vote or transfer'),
  ('funded',     'Funded',     40, true,  'Assets landed in the account'),
  ('lost',       'Lost',       50, true,  'Closed without funding');

insert into public.reminder_types (code, label, sort_order) values
  ('follow_up',          'Follow up',                              10),
  ('ooo_follow_up',      'Out-of-office follow-up',                20),
  ('post_call',          'After-call follow-up',                   30),
  ('event_follow_up',    'Event follow-up',                        40),
  ('referral_follow_up', 'Reach out to referral / colleague',      50),
  ('fix_contact_info',   'Fix bounced email or wrong number',      60),
  ('find_new_contact',   'Find a new contact at the organization', 70),
  ('check_in',           'Quarterly check-in',                     80),
  ('onboarding_task',    'Onboarding step',                        90),
  ('rfp_deadline',       'RFP deadline',                          100),
  ('custom',             'Other',                                 110);

-- Standardized outcomes + the automation each one triggers
insert into public.outcomes
  (code, label, applies_to, sentiment, counts_as_response, next_outreach_days, reminder_type, sets_stage,
   adds_to_newsletter, sets_do_not_contact, marks_email_bad, sort_order, description) values
  -- replies to outreach
  ('NO_RESPONSE',        'No response',                      '{email,intro,check_in}',                    'none',     false,   90, 'follow_up',          null,         false, false, false,  10, 'Default once an email goes out. Retry quarterly.'),
  ('OUT_OF_OFFICE',      'Out of office (auto-reply)',       '{email,check_in}',                          'none',     false,   14, 'ooo_follow_up',      null,         false, false, false,  20, 'Follow up in 2 weeks, or the day after the return date when the auto-reply gives one.'),
  ('BOUNCED',            'Bounced / wrong email',            '{email,check_in}',                          'none',     false,    2, 'fix_contact_info',   null,         false, false, true,   30, 'Moves the contact to the wrong-email list and asks someone to find the right address.'),
  ('WRONG_PERSON',       'No longer there / wrong person',   '{email,call,check_in}',                     'neutral',  true,     7, 'find_new_contact',   null,         false, false, false,  40, 'Find someone else at the organization with leadership authority.'),
  ('REFERRED_INTERNALLY','Pointed us to a colleague',        '{email,call,event}',                        'neutral',  true,     3, 'referral_follow_up', null,         false, false, false,  50, 'Reach out to the colleague they named.'),
  ('NOT_NOW',            'Not now, check back later',        '{email,call,event,meeting,check_in}',       'neutral',  true,    90, 'follow_up',          null,         false, false, false,  60, 'Uses the date they gave ("check back in October") when there is one; otherwise a quarter later.'),
  ('HAS_ADVISOR',        'Already has an advisor',           '{email,call,event,check_in}',               'negative', true,   180, 'follow_up',          'lost',       false, false, false,  70, 'Check in again in 6 months. Closes an open opportunity.'),
  ('NOT_INTERESTED',     'Not interested / no thank you',    '{email,call,event,check_in}',               'negative', true,   null, null,                 'lost',       false, false, false,  80, 'No automatic follow-up. Closes an open opportunity.'),
  ('UNSUBSCRIBE',        'Asked not to be contacted',        '{email,call,check_in}',                     'negative', true,   null, null,                 'lost',       false, true,  false,  90, 'Puts the contact on the do-not-contact list.'),
  ('INTERESTED',         'Interested, call scheduled',       '{email,call,event,intro,check_in}',         'positive', true,     7, 'post_call',          'call',       true,  false, false, 100, 'Opens an opportunity, adds them to the quarterly newsletter, reminds the owner to log the call.'),
  -- cold calls
  ('NO_ANSWER',          'No answer',                        '{call}',                                    'none',     false,    7, 'follow_up',          null,         false, false, false, 110, 'Try again in a week; after 3 unanswered calls in a row, back to quarterly.'),
  ('VOICEMAIL',          'Left voicemail',                   '{call}',                                    'none',     false,    7, 'follow_up',          null,         false, false, false, 120, 'Try again in a week; after 3 unanswered calls in a row, back to quarterly.'),
  ('WRONG_NUMBER',       'Wrong number',                     '{call}',                                    'none',     false,    2, 'fix_contact_info',   null,         false, false, false, 130, 'Find the right phone number.'),
  -- events and referrals
  ('MET_AT_EVENT',       'Met at event, exchanged info',     '{event}',                                   'neutral',  false,    3, 'event_follow_up',    null,         false, false, false, 140, 'Send a follow-up within a few days.'),
  ('MEETING_AT_EVENT',   'Had a meeting at the event',       '{event}',                                   'positive', true,     5, 'event_follow_up',    null,         false, false, false, 150, 'Sat down with them at the event.'),
  ('INTRO_MADE',         'Introduction made',                '{intro}',                                   'neutral',  false,    3, 'referral_follow_up', null,         false, false, false, 160, 'Reach out to the person we were introduced to.'),
  -- after a call
  ('CALL_HELD',          'Call held, next steps set',        '{meeting}',                                 'positive', true,    14, 'post_call',          'call',       true,  false, false, 170, 'First call happened.'),
  ('HOT',                'Hot: wants a proposal or another call', '{meeting,email,check_in}',             'positive', true,     7, 'post_call',          'hot',        true,  false, false, 180, 'Several follow-up calls and check-ins can happen here.'),
  ('READY_TO_ONBOARD',   'Wants to hire us, start onboarding','{meeting,email,check_in}',                 'positive', true,    14, 'onboarding_task',    'onboarding', true,  false, false, 190, 'Send onboarding materials and contracts.'),
  ('NOT_A_FIT',          'Not a fit after the call',         '{meeting,email,check_in}',                  'negative', true,   null, null,                 'lost',       false, false, false, 200, 'Closes the opportunity.'),
  -- RFPs
  ('RFP_SUBMITTED',      'RFP response submitted',           '{rfp}',                                     'neutral',  false,   30, 'follow_up',          null,         false, false, false, 210, 'Check on the decision in 30 days.'),
  ('RFP_FINALIST',       'RFP finalist, presentation',       '{rfp}',                                     'positive', true,     7, 'post_call',          'call',       true,  false, false, 220, 'Counts like a booked call.'),
  ('RFP_WON',            'RFP won',                          '{rfp}',                                     'positive', true,    14, 'onboarding_task',    'onboarding', true,  false, false, 230, 'Start onboarding.'),
  ('RFP_LOST',           'RFP lost',                         '{rfp}',                                     'negative', true,   365, 'follow_up',          'lost',       false, false, false, 240, 'Check in before the next RFP cycle.');

update public.outcomes set retry_limit = 3, after_limit_days = 90 where code in ('NO_ANSWER', 'VOICEMAIL');

-- Old free-text outcomes -> standardized outcome (whole-word match, longest phrase wins)
insert into public.outcome_aliases (phrase, outcome_code) values
  ('no response','NO_RESPONSE'), ('no reply','NO_RESPONSE'), ('nr','NO_RESPONSE'), ('no resp','NO_RESPONSE'),
  ('out of office','OUT_OF_OFFICE'), ('out of the office','OUT_OF_OFFICE'), ('ooo','OUT_OF_OFFICE'),
  ('auto reply','OUT_OF_OFFICE'), ('auto-reply','OUT_OF_OFFICE'), ('automatic reply','OUT_OF_OFFICE'),
  ('on leave','OUT_OF_OFFICE'), ('on vacation','OUT_OF_OFFICE'), ('away until','OUT_OF_OFFICE'),
  ('bounced','BOUNCED'), ('bounce','BOUNCED'), ('undeliverable','BOUNCED'), ('wrong email','BOUNCED'),
  ('invalid email','BOUNCED'), ('address not found','BOUNCED'), ('delivery failed','BOUNCED'),
  ('no longer with','WRONG_PERSON'), ('no longer at','WRONG_PERSON'), ('left the organization','WRONG_PERSON'),
  ('wrong person','WRONG_PERSON'), ('retired','WRONG_PERSON'),
  ('forwarded to','REFERRED_INTERNALLY'), ('pointed us to','REFERRED_INTERNALLY'), ('reach out to our','REFERRED_INTERNALLY'),
  ('copying my colleague','REFERRED_INTERNALLY'),
  ('check back','NOT_NOW'), ('circle back','NOT_NOW'), ('not right now','NOT_NOW'), ('not at this time','NOT_NOW'),
  ('maybe later','NOT_NOW'), ('next year','NOT_NOW'), ('next quarter','NOT_NOW'), ('reach back out','NOT_NOW'),
  ('follow up later','NOT_NOW'), ('not now','NOT_NOW'),
  ('advisor','HAS_ADVISOR'), ('have an advisor','HAS_ADVISOR'), ('has an advisor','HAS_ADVISOR'),
  ('already have an advisor','HAS_ADVISOR'), ('current advisor','HAS_ADVISOR'), ('existing advisor','HAS_ADVISOR'),
  ('already work with','HAS_ADVISOR'),
  ('no thank you','NOT_INTERESTED'), ('no thanks','NOT_INTERESTED'), ('not interested','NOT_INTERESTED'),
  ('we will pass','NOT_INTERESTED'), ('pass for now','NOT_INTERESTED'),
  ('unsubscribe','UNSUBSCRIBE'), ('remove me','UNSUBSCRIBE'), ('do not contact','UNSUBSCRIBE'),
  ('stop emailing','UNSUBSCRIBE'), ('take me off','UNSUBSCRIBE'),
  ('interested','INTERESTED'), ('call scheduled','INTERESTED'), ('set up a call','INTERESTED'),
  ('meeting scheduled','INTERESTED'), ('booked a call','INTERESTED'), ('schedule a call','INTERESTED'), ('call booked','INTERESTED'),
  ('no answer','NO_ANSWER'), ('voicemail','VOICEMAIL'), ('left vm','VOICEMAIL'), ('vm','VOICEMAIL'),
  ('left message','VOICEMAIL'), ('wrong number','WRONG_NUMBER'),
  ('call held','CALL_HELD'), ('not a fit','NOT_A_FIT');

insert into public.freemail_domains (domain) values
  ('gmail.com'),('googlemail.com'),('yahoo.com'),('ymail.com'),('outlook.com'),('hotmail.com'),('live.com'),
  ('msn.com'),('icloud.com'),('me.com'),('mac.com'),('aol.com'),('comcast.net'),('att.net'),('verizon.net'),
  ('protonmail.com'),('proton.me'),('gmx.com'),('zoho.com'),('hey.com'),('fastmail.com'),('q.com'),('xmission.com');

-- Jon: "if there's any organizations that have like a university kind of
-- email address, we flag it because there's a chance he might know them"
insert into public.flag_rules (match_on, pattern, flag, reason) values
  ('email_domain', '.edu', 'university', 'University email: the founder may know them, consider a personal reach-out');

-- Industry norms: left empty on purpose. Enter a value only with its source.
insert into public.benchmarks (metric, channel_code, segment_code, notes) values
  ('response_rate',          'COLD_EMAIL', null, 'Share of cold emails that get a human reply'),
  ('call_rate',              'COLD_EMAIL', null, 'Share of emailed contacts that book a call'),
  ('connect_rate',           'COLD_CALL',  null, 'Share of dials where someone picks up'),
  ('call_rate',              'COLD_CALL',  null, 'Share of dialed contacts that book a call'),
  ('call_rate',              'EVENT',      null, 'Share of event contacts that book a call'),
  ('call_rate',              'REFERRAL',   null, 'Share of referrals that book a call'),
  ('rfp_win_rate',           'RFP',        null, 'Share of submitted RFPs won'),
  ('call_to_funded_rate',    null,         null, 'Share of calls that end in a funded account');
