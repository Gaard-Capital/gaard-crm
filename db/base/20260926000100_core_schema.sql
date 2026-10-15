-- =====================================================================
-- GAARD Capital CRM · Migration 1 of 6 · Core schema
--
-- One database for every segment (Individuals: OCIO / Robo,
-- Organizations: Nonprofit / Other, 401(k) plans, Affiliates) and every
-- touchpoint (cold email, cold call, events, referrals, RFPs).
--
-- Replaces: master outreach list (2025 + 2026), cold outreach tab,
-- affiliates / individuals / small business tabs, wrong-email tab,
-- next-steps tab, onboarding tab, events worksheet, RFP workbook,
-- cold-call tracking kept offline, newsletter list.
--
-- Target: PostgreSQL 15+ (Supabase). Run on an empty database.
-- =====================================================================

create schema if not exists extensions;
create extension if not exists pg_trgm with schema extensions;         -- similar-name search for duplicate checks
create extension if not exists fuzzystrmatch with schema extensions;   -- typo distance (levenshtein) for duplicate checks


-- ---------------------------------------------------------------------
-- Normalization helpers
-- Used by generated columns, so they must be IMMUTABLE. These are what
-- make duplicate detection reliable: "Jane.Doe@Org.org " and
-- "jane.doe@org.org" become the same key.
-- ---------------------------------------------------------------------

-- lowercase, strip accents, collapse whitespace
create or replace function public.norm_text(p text) returns text
language sql immutable parallel safe set search_path = '' as $$
  select nullif(
           regexp_replace(
             translate(lower(trim(coalesce(p, ''))),
                       'áàâäãåāéèêëēíìîïīóòôöõøōúùûüūñçýÿ',
                       'aaaaaaaeeeeeiiiiiooooooouuuuuncyy'),
             '\s+', ' ', 'g'),
           '')
$$;

-- valid-looking email in lowercase, otherwise NULL (so "N/A" never collides)
create or replace function public.norm_email(p text) returns text
language sql immutable parallel safe set search_path = '' as $$
  select case when e ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then e end
  from (select regexp_replace(lower(trim(coalesce(p, ''))), '^mailto:|[<>\s]', '', 'g') as e) s
$$;

-- any LinkedIn URL variant -> 'linkedin.com/in/<slug>'
--   https://www.linkedin.com/in/Jane-Doe-12ab/?utm=x  -> linkedin.com/in/jane-doe-12ab
create or replace function public.norm_linkedin(p text) returns text
language sql immutable parallel safe set search_path = '' as $$
  select case when m is null then null else 'linkedin.com/' || m[1] || '/' || m[2] end
  from (select regexp_match(lower(coalesce(p, '')),
                            'linkedin\.com/(in|pub|company)/([^/?#\s]+)') as m) s
$$;

-- website or URL -> bare domain: 'https://www.Example.org/about' -> 'example.org'
create or replace function public.norm_domain(p text) returns text
language sql immutable parallel safe set search_path = '' as $$
  select case when d ~ '^[a-z0-9.-]+\.[a-z]{2,}$' then d end
  from (select regexp_replace(
                 regexp_replace(lower(trim(coalesce(p, ''))), '^[a-z]+://', ''),
                 '^www\.|[/:?#].*$', '', 'g') as d) s
$$;

-- organization name -> matching key
--   'The Wasatch Youth Alliance, Inc.' -> 'wasatch youth alliance'
--   'Cache Valley Literacy Ctr.'       -> 'cache valley literacy center'
create or replace function public.norm_org_name(p text) returns text
language sql immutable parallel safe set search_path = '' as $$
  select nullif(trim(regexp_replace(s3, '\s+', ' ', 'g')), '')
  from (select regexp_replace(coalesce(public.norm_text(replace(coalesce(p, ''), '&', ' and ')), ''),
                              '[^a-z0-9 ]', ' ', 'g') as s1) a,
  lateral (select                                                   -- common abbreviations
    regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(s1,
      '\mctr\M', 'center', 'g'),
      '\m(assn|assoc)\M', 'association', 'g'),
      '\m(fdn|fndn|fdtn)\M', 'foundation', 'g'),
      '\m(svcs|svc)\M', 'services', 'g'),
      '\muniv\M', 'university', 'g'),
      '\mintl\M', 'international', 'g'),
      '\mmt\M', 'mount', 'g') as s2) b,
  lateral (select regexp_replace(regexp_replace(s2,
      '^\s*the\s+', ''),                                                                   -- leading "the"
      '(\s+(inc|incorporated|llc|ltd|limited|corp|corporation|co|company|pc|pllc|lp|llp))+\s*$', '')  -- legal suffixes
    as s3) c
$$;

-- are two organization names probably the same organization?
--   typo ('Cache Valey' / 'Cache Valley'), word order ('Literacy Council of Cache Valley' /
--   'Cache Valley Literacy Council'), or only generic words added ('... Youth Soccer' / '... Youth Soccer Club').
--   'Park Charitable Trust' vs 'Rice Charitable Trust' is NOT a match.
create or replace function public.org_names_look_alike(p_a text, p_b text) returns boolean
language sql immutable parallel safe set search_path = '' as $$
  with k as (select public.norm_org_name(p_a) as a, public.norm_org_name(p_b) as b),
  w as (
    select k.a, k.b,
           array(select distinct x from unnest(string_to_array(k.a, ' ')) x where x not in ('of', 'and', 'the')) as wa,
           array(select distinct x from unnest(string_to_array(k.b, ' ')) x where x not in ('of', 'and', 'the')) as wb,
           array['club', 'foundation', 'fund', 'association', 'society', 'organization', 'group', 'center', 'council',
                 'trust', 'partners', 'services', 'network', 'alliance', 'coalition', 'chapter', 'branch',
                 'utah', 'idaho', 'wyoming', 'california'] as generic
      from k)
  select coalesce(
       a = b
    or (least(length(a), length(b)) >= 8 and extensions.levenshtein(a, b) <= 2)
    or (wa @> wb and wb @> wa)
    or (wa @> wb and wa <@ (wb || generic))
    or (wb @> wa and wb <@ (wa || generic))
    or extensions.similarity(a, b) >= 0.85, false)
  from w
$$;

-- are two people probably the same person? Same last name and the same first name,
-- a nickname that is a prefix (Dan / Daniel, Jon / Jonathan, J / Jane) or a one-letter typo.
create or replace function public.person_names_look_alike(p_first_a text, p_last_a text, p_first_b text, p_last_b text)
returns boolean
language sql immutable parallel safe set search_path = '' as $$
  select coalesce(la = lb and (fa = fb or starts_with(fa, fb) or starts_with(fb, fa)
                               or (least(length(fa), length(fb)) >= 4 and extensions.levenshtein(fa, fb) <= 1)), false)
  from (select public.norm_text(p_first_a) as fa, public.norm_text(p_last_a) as la,
               public.norm_text(p_first_b) as fb, public.norm_text(p_last_b) as lb) n
$$;

-- does an email domain match a rule pattern?
--   '.edu'      -> any domain ending in .edu
--   'utah.edu'  -> utah.edu and its subdomains (law.utah.edu)
create or replace function public.domain_matches(p_domain text, p_pattern text) returns boolean
language sql immutable parallel safe set search_path = '' as $$
  select coalesce(
    case when p_domain is null or p_pattern is null then false
         when left(p_pattern, 1) = '.' then p_domain like '%' || lower(p_pattern)
         else p_domain = lower(p_pattern) or p_domain like '%.' || lower(p_pattern)
    end, false)
$$;


-- ---------------------------------------------------------------------
-- Lookup tables (editable configuration, not code)
-- ---------------------------------------------------------------------

create table public.us_states (
  code      char(2) primary key,
  name      text not null unique,
  is_focus  boolean not null default false          -- markets GAARD is actively working (UT, ID, WY, CA)
);

create table public.segments (
  code           text primary key,                  -- e.g. ORG_NONPROFIT
  segment_group  text not null,                     -- Individuals / Organizations / Employer retirement plans / Affiliates
  name           text not null,                     -- sub-level: OCIO, Robo-advisor, Nonprofit ...
  party_type     text not null check (party_type in ('individual', 'organization')),
  aliases        text[] not null default '{}',     -- what people type in the Segment column: 'npo', 'robo', '401k' ...
  description    text,
  sort_order     int  not null default 0,
  is_active      boolean not null default true
);

-- how a lead was introduced (the "touchpoint / introduction point" Jon described)
create table public.channels (
  code         text primary key,                    -- COLD_EMAIL, COLD_CALL, EVENT, REFERRAL, RFP
  name         text not null,
  description  text,
  sort_order   int not null default 0
);

-- what kind of interaction a single touchpoint row is
create table public.touch_types (
  code                  text primary key,           -- email, call, event, intro, rfp, meeting, check_in
  name                  text not null,
  channel_code          text references public.channels(code),   -- channel credited when this touch books a call
  is_outreach           boolean not null,           -- counts as prospecting outreach (emails sent, dials, ...)
  sort_order            int not null default 0
);

create table public.pipeline_stages (
  code         text primary key,                    -- call, hot, onboarding, funded, lost
  label        text not null,
  sort_order   int  not null,
  is_closed    boolean not null default false,
  description  text
);

create table public.reminder_types (
  code        text primary key,
  label       text not null,
  sort_order  int not null default 0
);

-- Standardized outcomes. Each row also carries the automation rule for
-- that outcome, so changing "no response -> retry in 90 days" to 60 is
-- a data edit, not a code change.
create table public.outcomes (
  code                 text primary key,
  label                text not null,
  applies_to           text[] not null,             -- touch_types.code values where this outcome can be chosen
  sentiment            text not null check (sentiment in ('positive', 'neutral', 'negative', 'none')),
  counts_as_response   boolean not null default false,   -- a person actually replied / answered
  next_outreach_days   int,                         -- follow up N days after the touch (NULL = no automatic follow-up)
  retry_limit          int,                         -- after this many in a row (e.g. 3 unanswered dials) ...
  after_limit_days     int,                         -- ... wait this long instead (e.g. back to quarterly)
  reminder_type        text references public.reminder_types(code),
  sets_stage           text references public.pipeline_stages(code),
  adds_to_newsletter   boolean not null default false,
  sets_do_not_contact  boolean not null default false,
  marks_email_bad      boolean not null default false,
  sort_order           int not null default 0,
  is_active            boolean not null default true,
  description          text
);

-- free-text phrases from the old "Outcome" column -> standardized outcome
create table public.outcome_aliases (
  phrase        text primary key,                   -- lowercase; matched as whole words, longest phrase wins
  outcome_code  text not null references public.outcomes(code)
);

-- personal email providers: never used to match a person to an organization
create table public.freemail_domains (
  domain  text primary key
);


-- ---------------------------------------------------------------------
-- Team
-- ---------------------------------------------------------------------

create table public.team_members (
  id            bigint generated by default as identity primary key,
  full_name     text not null,
  email         text unique,
  role          text,
  auth_user_id  uuid unique,                         -- Supabase auth.users.id once logins are set up
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);

-- for later: dedicated states or segments per person
create table public.territory_assignments (
  id              bigint generated by default as identity primary key,
  team_member_id  bigint not null references public.team_members(id) on delete cascade,
  state           char(2) references public.us_states(code),
  segment_code    text references public.segments(code),
  unique nulls not distinct (team_member_id, state, segment_code)
);


-- ---------------------------------------------------------------------
-- Events, campaigns
-- ---------------------------------------------------------------------

create table public.events (
  id                   bigint generated by default as identity primary key,
  name                 text not null,
  event_type           text not null check (event_type in ('conference', 'networking', 'webinar', 'workshop', 'other')),
  format               text not null check (format in ('in_person', 'virtual')),
  hosted_by_us         boolean not null default false,
  host_org             text,                         -- association or group running it
  start_on             date not null,
  end_on               date,
  city                 text,
  state                char(2) references public.us_states(code),
  cost_usd             numeric(10,2) not null default 0,   -- registration + travel + sponsorship
  attendees_est        int,
  target_segment_code  text references public.segments(code),
  owner_id             bigint references public.team_members(id),
  notes                text,
  created_at           timestamptz not null default now()
);

create table public.campaigns (
  id             bigint generated by default as identity primary key,
  name           text not null unique,
  channel_code   text not null references public.channels(code),
  segment_code   text references public.segments(code),
  target_states  char(2)[] not null default '{}',
  start_on       date,
  end_on         date,
  owner_id       bigint references public.team_members(id),
  description    text,
  created_at     timestamptz not null default now()
);


-- ---------------------------------------------------------------------
-- Organizations and contacts
-- ---------------------------------------------------------------------

create table public.organizations (
  id                        bigint generated by default as identity primary key,
  name                      text not null,
  name_key                  text generated always as (public.norm_org_name(name)) stored,
  segment_code              text not null references public.segments(code),
  org_type                  text,                    -- sub-type: human services, community foundation, dental practice ...
  website                   text,
  domain                    text generated always as (public.norm_domain(website)) stored,
  phone                     text,
  city                      text,
  state                     char(2) references public.us_states(code),
  reported_aum              numeric(16,2),           -- the AUM column from sourcing (Form 990, website, research)
  employee_count            int,                     -- sizing for 401(k) plans
  is_university_affiliated  boolean not null default false,
  do_not_contact            boolean not null default false,
  dnc_reason                text,
  owner_id                  bigint references public.team_members(id),
  tags                      text[] not null default '{}',
  notes                     text,
  source_detail             text,
  legacy_ref                text,                    -- pointer back to the old sheet row
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);
-- same organization cannot be entered twice in the same state
create unique index organizations_name_state_uq on public.organizations (name_key, coalesce(state, ''));
create index organizations_domain_idx on public.organizations (domain);
create index organizations_name_trgm  on public.organizations using gin (name_key extensions.gin_trgm_ops);
create index organizations_segment_idx on public.organizations (segment_code, state);

create table public.contacts (
  id                        bigint generated by default as identity primary key,
  organization_id           bigint references public.organizations(id) on delete set null,
  segment_code              text not null references public.segments(code),
  first_name                text,
  last_name                 text,
  full_name                 text generated always as (nullif(trim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')), '')) stored,
  name_key                  text generated always as (public.norm_text(coalesce(first_name, '') || ' ' || coalesce(last_name, ''))) stored,
  title                     text,
  employer                  text,                    -- individuals only: where they work (not a client org)
  is_decision_maker         boolean not null default false,   -- has leadership authority (used for the yearly rollover)
  email                     text,
  email_key                 text generated always as (public.norm_email(email)) stored,
  email_domain              text generated always as (split_part(public.norm_email(email), '@', 2)) stored,
  email_status              text not null default 'unverified'
                            check (email_status in ('unverified', 'valid', 'bounced', 'wrong_person')),
  phone                     text,
  linkedin_url              text,
  linkedin_key              text generated always as (public.norm_linkedin(linkedin_url)) stored,
  linkedin_connected_on     date,                    -- "Added on LinkedIn"
  city                      text,
  state                     char(2) references public.us_states(code),
  prospect_aum              numeric(16,2),           -- individuals: estimated investable assets
  source_channel_code       text references public.channels(code),   -- how we first met them (one channel, no double counting)
  source_detail             text,                    -- the old "Source" column: database, event, who referred them
  source_event_id           bigint references public.events(id),
  referred_by_contact_id    bigint references public.contacts(id) on delete set null,
  sourced_on                date,                    -- the old "Date" column
  is_university_affiliated  boolean not null default false,
  do_not_contact            boolean not null default false,
  dnc_reason                text,
  dnc_on                    date,
  newsletter_status         text not null default 'not_subscribed'
                            check (newsletter_status in ('not_subscribed', 'subscribed', 'unsubscribed')),
  newsletter_added_on       date,
  newsletter_added_via      text,
  follow_up_style           text not null default 'personalized'
                            check (follow_up_style in ('personalized', 'standard_check_in')),
  owner_id                  bigint references public.team_members(id),
  tags                      text[] not null default '{}',
  notes                     text,
  legacy_ref                text,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);
-- hard duplicate rules: one person per email address and per LinkedIn profile
create unique index contacts_email_uq    on public.contacts (email_key)    where email_key is not null;
create unique index contacts_linkedin_uq on public.contacts (linkedin_key) where linkedin_key is not null;
create index contacts_org_idx          on public.contacts (organization_id);
create index contacts_email_domain_idx on public.contacts (email_domain);
create index contacts_name_trgm        on public.contacts using gin (name_key extensions.gin_trgm_ops);
create index contacts_segment_idx      on public.contacts (segment_code, state);


-- ---------------------------------------------------------------------
-- RFPs (was a separate workbook)
-- ---------------------------------------------------------------------

create table public.rfps (
  id                bigint generated by default as identity primary key,
  organization_id   bigint not null references public.organizations(id),
  contact_id        bigint references public.contacts(id) on delete set null,
  title             text not null,
  mandate_type      text,                            -- OCIO, investment consulting, 401(k) plan advisor ...
  found_via         text,                            -- consultant, RFP database, direct invitation
  est_mandate_aum   numeric(16,2),
  released_on       date,
  questions_due_on  date,
  due_on            date,
  submitted_on      date,
  status            text not null default 'identified'
                    check (status in ('identified', 'intent_to_bid', 'submitted', 'finalist', 'won', 'lost', 'declined', 'cancelled')),
  decision_on       date,
  owner_id          bigint references public.team_members(id),
  notes             text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);


-- ---------------------------------------------------------------------
-- Touchpoints: every interaction, one row each
-- (an outreach email starts as "No response" and is updated when the
--  reply comes in, the same way the sheet works today)
-- ---------------------------------------------------------------------

create table public.touchpoints (
  id                    bigint generated by default as identity primary key,
  contact_id            bigint not null references public.contacts(id) on delete cascade,
  organization_id       bigint references public.organizations(id) on delete set null,
  touch_type            text not null references public.touch_types(code),
  direction             text not null default 'outbound' check (direction in ('outbound', 'inbound', 'in_person')),
  touched_at            timestamptz not null,       -- the old "Date outreached"
  campaign_id           bigint references public.campaigns(id),
  event_id              bigint references public.events(id),
  rfp_id                bigint references public.rfps(id),
  sequence_step         smallint,                   -- 1 = first email, 2 = first follow-up ...
  subject               text,
  notes                 text,                       -- call / meeting notes
  -- standardized result
  outcome_code          text references public.outcomes(code),
  outcome_status        text not null default 'confirmed' check (outcome_status in ('confirmed', 'needs_review')),
  outcome_raw           text,                       -- original free text from the old sheet
  responded_at          timestamptz,
  response_excerpt      text,
  follow_up_on          date,                       -- explicit "check back in October" date; overrides the cadence
  ooo_return_on         date,                       -- return date from an out-of-office reply
  -- layer 2: AI proposes the outcome, a person confirms it
  ai_suggested_outcome  text references public.outcomes(code),
  ai_confidence         numeric(4,3) check (ai_confidence between 0 and 1),
  ai_reason             text,
  confirmed_by          bigint references public.team_members(id),
  confirmed_at          timestamptz,
  owner_id              bigint references public.team_members(id),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index touchpoints_contact_idx   on public.touchpoints (contact_id, touched_at desc);
create index touchpoints_org_idx       on public.touchpoints (organization_id);
create index touchpoints_type_date_idx on public.touchpoints (touch_type, touched_at);
create index touchpoints_event_idx     on public.touchpoints (event_id) where event_id is not null;
create index touchpoints_campaign_idx  on public.touchpoints (campaign_id) where campaign_id is not null;
create index touchpoints_review_idx    on public.touchpoints (touched_at) where outcome_status = 'needs_review';


-- ---------------------------------------------------------------------
-- Email history (layer 2 fills this from the team's inboxes;
-- replaces copy-pasting replies into the correspondence column)
-- ---------------------------------------------------------------------

create table public.email_messages (
  id              bigint generated by default as identity primary key,
  contact_id      bigint references public.contacts(id) on delete cascade,
  touchpoint_id   bigint references public.touchpoints(id) on delete set null,
  mailbox         text,                             -- which team inbox it came from
  external_id     text unique,                      -- Gmail / Outlook message id, prevents double logging
  thread_id       text,
  direction       text not null check (direction in ('outbound', 'inbound')),
  from_email      text not null,
  to_emails       text[] not null default '{}',
  cc_emails       text[] not null default '{}',
  subject         text,
  body_text       text,
  sent_at         timestamptz not null,
  is_auto_reply   boolean not null default false,
  created_at      timestamptz not null default now()
);
create index email_messages_contact_idx on public.email_messages (contact_id, sent_at desc);
create index email_messages_thread_idx  on public.email_messages (thread_id);


-- ---------------------------------------------------------------------
-- Opportunities: outreach -> call -> hot -> onboarding -> funded
-- Created when a call is booked. One open opportunity per person
-- (individuals) and per organization, so a lead is never counted twice.
-- ---------------------------------------------------------------------

create table public.opportunities (
  id                        bigint generated by default as identity primary key,
  contact_id                bigint not null references public.contacts(id),
  organization_id           bigint references public.organizations(id),
  segment_code              text not null references public.segments(code),
  state                     char(2) references public.us_states(code),
  stage                     text not null default 'call' references public.pipeline_stages(code),
  source_channel_code       text not null references public.channels(code),   -- first touch: how we met them
  converting_channel_code   text references public.channels(code),            -- the touch that booked the call
  converting_touchpoint_id  bigint references public.touchpoints(id) on delete set null,
  source_event_id           bigint references public.events(id),
  rfp_id                    bigint references public.rfps(id),
  opened_on                 date not null,           -- call booked
  first_call_on             date,
  hot_on                    date,
  onboarding_started_on     date,                    -- onboarding materials / contracts sent
  contract_signed_on        date,
  funded_on                 date,                    -- money landed in the account
  closed_on                 date,
  lost_reason               text,
  expected_aum              numeric(16,2),
  funded_aum                numeric(16,2),
  owner_id                  bigint references public.team_members(id),
  notes                     text,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  constraint funded_needs_aum check (stage <> 'funded' or (funded_aum is not null and funded_on is not null)),
  constraint lost_needs_date  check (stage <> 'lost' or closed_on is not null)
);
create unique index opportunities_one_open_per_contact on public.opportunities (contact_id)
  where stage not in ('funded', 'lost');
create unique index opportunities_one_open_per_org on public.opportunities (organization_id)
  where organization_id is not null and stage not in ('funded', 'lost');
create index opportunities_stage_idx on public.opportunities (stage);


-- ---------------------------------------------------------------------
-- Reminders: the shared notification list. When anyone marks one done
-- it is done for the whole team.
-- ---------------------------------------------------------------------

create table public.reminders (
  id               bigint generated by default as identity primary key,
  reminder_type    text not null references public.reminder_types(code),
  contact_id       bigint references public.contacts(id) on delete cascade,
  organization_id  bigint references public.organizations(id) on delete cascade,
  opportunity_id   bigint references public.opportunities(id) on delete cascade,
  rfp_id           bigint references public.rfps(id) on delete cascade,
  touchpoint_id    bigint references public.touchpoints(id) on delete set null,   -- what created it
  due_on           date not null,
  title            text not null,
  details          text,
  follow_up_style  text check (follow_up_style in ('personalized', 'standard_check_in')),
  assigned_to      bigint references public.team_members(id),       -- NULL = anyone on the team
  status           text not null default 'open'
                   check (status in ('open', 'snoozed', 'done', 'dismissed', 'superseded')),
  snoozed_until    date,
  created_by       text not null default 'system',
  completed_by     bigint references public.team_members(id),
  completed_at     timestamptz,
  created_at       timestamptz not null default now(),
  constraint reminder_has_target check (num_nonnulls(contact_id, organization_id, opportunity_id, rfp_id) >= 1)
);
create index reminders_open_idx    on public.reminders (due_on) where status in ('open', 'snoozed');
create index reminders_contact_idx on public.reminders (contact_id);


-- ---------------------------------------------------------------------
-- Flag rules: Jon's list of emails / domains / organizations to flag
-- ---------------------------------------------------------------------

create table public.flag_rules (
  id          bigint generated by default as identity primary key,
  match_on    text not null check (match_on in ('email_domain', 'email', 'org_name', 'linkedin')),
  pattern     text not null,          -- email_domain: 'utah.edu' (domain + subdomains) or '.edu' (suffix)
  flag        text not null check (flag in ('do_not_contact', 'university')),
  reason      text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  unique (match_on, pattern, flag)
);


-- ---------------------------------------------------------------------
-- Industry benchmarks for "how do we compare to the norm"
-- (values stay NULL until someone enters them with a source)
-- ---------------------------------------------------------------------

create table public.benchmarks (
  id            bigint generated by default as identity primary key,
  metric        text not null,        -- response_rate, call_rate, onboard_rate, cold_call_connect_rate, rfp_win_rate
  channel_code  text references public.channels(code),
  segment_code  text references public.segments(code),
  value         numeric(6,4),         -- 0.0850 = 8.5%
  source        text,
  notes         text,
  unique nulls not distinct (metric, channel_code, segment_code)
);


-- ---------------------------------------------------------------------
-- Import staging: paste or upload rows in the outreach sheet's own
-- columns, then run process_import_batch() (migration 4).
-- Used once for the historical migration and then every time the team
-- dumps in 50-100 cleaned prospects.
-- ---------------------------------------------------------------------

create table public.import_batches (
  id                    bigint generated by default as identity primary key,
  label                 text not null,
  source_file           text,
  default_segment_code  text references public.segments(code),
  default_channel_code  text references public.channels(code),
  default_touch_type    text not null default 'email' references public.touch_types(code),
  default_state         char(2) references public.us_states(code),
  campaign_id           bigint references public.campaigns(id),
  event_id              bigint references public.events(id),
  owner_id              bigint references public.team_members(id),
  status                text not null default 'pending' check (status in ('pending', 'processed')),
  summary               jsonb,
  created_at            timestamptz not null default now(),
  processed_at          timestamptz
);

create table public.import_rows (
  id                           bigint generated by default as identity primary key,
  batch_id                     bigint not null references public.import_batches(id) on delete cascade,
  row_number                   int,
  -- the outreach sheet's columns, as text, exactly as pasted
  date_added                   text,   -- "Date"
  source                       text,   -- "Source"
  contact                      text,   -- "Contact" (full name)
  first_name                   text,   -- "First Name"
  last_name                    text,
  title                        text,
  email                        text,   -- "Email"
  org                          text,   -- "Org"
  website                      text,   -- "Website"
  linkedin                     text,   -- "LinkedIn"
  added_on_linkedin            text,   -- "Added on LinkedIn"
  phone                        text,
  aum                          text,
  state                        text,
  segment                      text,
  notes                        text,   -- "Notes"
  date_outreached              text,   -- "Date Outreached"
  outcome                      text,   -- "Outcome"
  next_steps                   text,   -- "Next Steps"
  -- written by process_import_batch()
  result                       text check (result in ('new_contact', 'new_contact_existing_org', 'existing_contact',
                                                      'needs_review', 'skipped', 'error')),
  result_detail                text,
  matched_on                   text,
  contact_id                   bigint references public.contacts(id) on delete set null,
  organization_id              bigint references public.organizations(id) on delete set null,
  touchpoint_id                bigint references public.touchpoints(id) on delete set null,
  review_candidate_contact_id  bigint references public.contacts(id) on delete set null,
  review_candidate_org_id      bigint references public.organizations(id) on delete set null,
  -- a person's answer for a 'needs_review' row, then run process_import_batch() again
  review_decision              text check (review_decision in ('use_candidate', 'create_new', 'skip')),
  processed_at                 timestamptz
);
create index import_rows_batch_idx on public.import_rows (batch_id, row_number);
