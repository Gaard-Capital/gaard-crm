#!/usr/bin/env python3
"""
GAARD Capital CRM: mock data generator.

Writes
  db/mock/seed.sql                          the integrated mock database (load after the migrations)
  db/mock/import_demo/new_prospects_batch.csv   a sourcing batch in the outreach sheet's own columns
  db/mock/import_demo/import_demo.sql              loads that batch and runs process_import_batch()

Deterministic: every run produces the same data (fixed random seed).
Every lead is simulated the way the database rules work (no response -> retry
quarterly, out of office -> 2 weeks, call booked -> opportunity + newsletter ...)
so the seed looks like the system has been running since January 2025.

Safe by construction: all email domains use the reserved .example TLD and all
phone numbers use the 555-01xx range set aside for fiction.
"""
from __future__ import annotations

import csv
import datetime as dt
import re
import random
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
R = random.Random(20260926)
TODAY = dt.date(2026, 9, 26)
LAST = dt.date(2026, 9, 25)                 # last day with activity in the mock data
FAR = dt.date(2099, 1, 1)


# ---------------------------------------------------------------------------
# small helpers
# ---------------------------------------------------------------------------

def days(n: int) -> dt.timedelta:
    return dt.timedelta(days=n)


def bday(d: dt.date) -> dt.date:
    while d.weekday() >= 5:
        d += days(1)
    return d


def at(d: dt.date, hour: int | None = None) -> dt.datetime:
    h = hour if hour is not None else R.choices([8, 9, 10, 11, 13, 14, 15, 16], [3, 5, 5, 4, 3, 3, 2, 1])[0]
    return dt.datetime(d.year, d.month, d.day, h, R.randrange(60), R.randrange(60))


def rint(a: int, b: int) -> int:
    return R.randint(a, b)


def chance(p: float) -> bool:
    return R.random() < p


def pick(seq):
    return R.choice(seq)


def wpick(weights: dict):
    keys = list(weights)
    return R.choices(keys, [weights[k] for k in keys])[0]


def rand_date(a: dt.date, b: dt.date) -> dt.date:
    return a + days(R.randint(0, max(0, (b - a).days)))


def lognormal_money(median: float, sigma: float, lo: float, hi: float, step: float) -> float:
    v = median * pow(2.718281828, R.gauss(0, sigma))
    v = min(hi, max(lo, v))
    return round(v / step) * step


def month_start_after(d: dt.date, months: int) -> dt.date:
    m = d.month - 1 + months
    return bday(dt.date(d.year + m // 12, m % 12 + 1, 1))


def money_text(v: float) -> str:
    return f"${v / 1e6:.1f}M" if v >= 1e6 else f"${v / 1e3:.0f}k"


# ---------------------------------------------------------------------------
# reference values (must match migration 2)
# ---------------------------------------------------------------------------

OUTCOMES = {
    # code: (label, applies_to, counts_as_response, next_days, reminder_type, sets_stage, newsletter, dnc, email_bad)
    'NO_RESPONSE':         ('No response', {'email', 'intro', 'check_in'}, False, 90, 'follow_up', None, False, False, False),
    'OUT_OF_OFFICE':       ('Out of office (auto-reply)', {'email', 'check_in'}, False, 14, 'ooo_follow_up', None, False, False, False),
    'BOUNCED':             ('Bounced / wrong email', {'email', 'check_in'}, False, 2, 'fix_contact_info', None, False, False, True),
    'WRONG_PERSON':        ('No longer there / wrong person', {'email', 'call', 'check_in'}, True, 7, 'find_new_contact', None, False, False, False),
    'REFERRED_INTERNALLY': ('Pointed us to a colleague', {'email', 'call', 'event'}, True, 3, 'referral_follow_up', None, False, False, False),
    'NOT_NOW':             ('Not now, check back later', {'email', 'call', 'event', 'meeting', 'check_in'}, True, 90, 'follow_up', None, False, False, False),
    'HAS_ADVISOR':         ('Already has an advisor', {'email', 'call', 'event', 'check_in'}, True, 180, 'follow_up', 'lost', False, False, False),
    'NOT_INTERESTED':      ('Not interested / no thank you', {'email', 'call', 'event', 'check_in'}, True, None, None, 'lost', False, False, False),
    'UNSUBSCRIBE':         ('Asked not to be contacted', {'email', 'call', 'check_in'}, True, None, None, 'lost', False, True, False),
    'INTERESTED':          ('Interested, call scheduled', {'email', 'call', 'event', 'intro', 'check_in'}, True, 7, 'post_call', 'call', True, False, False),
    'NO_ANSWER':           ('No answer', {'call'}, False, 7, 'follow_up', None, False, False, False),
    'VOICEMAIL':           ('Left voicemail', {'call'}, False, 7, 'follow_up', None, False, False, False),
    'WRONG_NUMBER':        ('Wrong number', {'call'}, False, 2, 'fix_contact_info', None, False, False, False),
    'MET_AT_EVENT':        ('Met at event, exchanged info', {'event'}, False, 3, 'event_follow_up', None, False, False, False),
    'MEETING_AT_EVENT':    ('Had a meeting at the event', {'event'}, True, 5, 'event_follow_up', None, False, False, False),
    'INTRO_MADE':          ('Introduction made', {'intro'}, False, 3, 'referral_follow_up', None, False, False, False),
    'CALL_HELD':           ('Call held, next steps set', {'meeting'}, True, 14, 'post_call', 'call', True, False, False),
    'HOT':                 ('Hot: wants a proposal or another call', {'meeting', 'email', 'check_in'}, True, 7, 'post_call', 'hot', True, False, False),
    'READY_TO_ONBOARD':    ('Wants to hire us, start onboarding', {'meeting', 'email', 'check_in'}, True, 14, 'onboarding_task', 'onboarding', True, False, False),
    'NOT_A_FIT':           ('Not a fit after the call', {'meeting', 'email', 'check_in'}, True, None, None, 'lost', False, False, False),
    'RFP_SUBMITTED':       ('RFP response submitted', {'rfp'}, False, 30, 'follow_up', None, False, False, False),
    'RFP_FINALIST':        ('RFP finalist, presentation', {'rfp'}, True, 7, 'post_call', 'call', True, False, False),
    'RFP_WON':             ('RFP won', {'rfp'}, True, 14, 'onboarding_task', 'onboarding', True, False, False),
    'RFP_LOST':            ('RFP lost', {'rfp'}, True, 365, 'follow_up', 'lost', False, False, False),
}
REMINDER_LABELS = {
    'follow_up': 'Follow up', 'ooo_follow_up': 'Out-of-office follow-up', 'post_call': 'After-call follow-up',
    'event_follow_up': 'Event follow-up', 'referral_follow_up': 'Reach out to referral / colleague',
    'fix_contact_info': 'Fix bounced email or wrong number', 'find_new_contact': 'Find a new contact at the organization',
    'check_in': 'Quarterly check-in', 'onboarding_task': 'Onboarding step', 'rfp_deadline': 'RFP deadline', 'custom': 'Other',
}
TOUCH_NAMES = {'email': 'Email', 'call': 'Phone call (dial)', 'event': 'Met at an event', 'intro': 'Introduction / referral',
               'rfp': 'RFP response', 'meeting': 'Call / meeting held', 'check_in': 'Check-in / relationship email'}
TOUCH_CHANNEL = {'email': 'COLD_EMAIL', 'call': 'COLD_CALL', 'event': 'EVENT', 'intro': 'REFERRAL', 'rfp': 'RFP'}
PARTY = {'IND_OCIO': 'individual', 'IND_ROBO': 'individual', 'ORG_NONPROFIT': 'organization',
         'ORG_OTHER': 'organization', 'RET_401K': 'organization', 'AFFILIATE': 'organization'}
CADENCE_TYPES = {'follow_up', 'ooo_follow_up', 'post_call', 'event_follow_up', 'referral_follow_up', 'check_in'}

TEAM = [
    dict(id=1, full_name='Jon', email='jon@gaard.example', role='Outreach lead'),
    dict(id=2, full_name='Ryan Mitchell', email='ryan@gaard.example', role='Associate (mock team member)'),
]
TEAM_BY_ID = {m['id']: m for m in TEAM}


def owner_for(seg: str, state: str | None) -> int:
    return 2 if state in ('ID', 'WY') or seg in ('IND_ROBO', 'RET_401K') else 1


# ---------------------------------------------------------------------------
# name pools (fictional combinations)
# ---------------------------------------------------------------------------

FIRST = """Michael Linda David Elizabeth William Barbara Richard Susan Joseph Jessica Thomas Sarah Christopher Karen
Daniel Lisa Matthew Nancy Anthony Betty Mark Sandra Donald Ashley Steven Kimberly Andrew Emily Paul Donna Joshua
Michelle Kenneth Carol Kevin Amanda Brian Melissa George Deborah Timothy Stephanie Ronald Rebecca Jason Laura Edward
Sharon Jeffrey Cynthia Kathleen Jacob Amy Gary Angela Nicholas Shirley Eric Brenda Jonathan Emma Stephen Anna Larry
Pamela Justin Nicole Scott Samantha Brandon Katherine Benjamin Christine Samuel Rachel Gregory Carolyn Alexander Janet
Patrick Maria Frank Olivia Raymond Heather Jack Helen Dennis Catherine Tyler Julie Aaron Victoria Jose Lauren Adam
Kelly Nathan Christina Henry Joan Zachary Evelyn Douglas Judith Peter Andrea Kyle Hannah Noah Megan Ethan Cheryl
Jeremy Jacqueline Christian Martha Walter Madison Keith Teresa Austin Gloria Roger Sara Sean Ann Gerald Kathryn Carl
Abigail Dylan Sophia Harold Frances Jordan Jean Jesse Alice Bryan Judy Lawrence Isabella Arthur Julia Gabriel Grace
Bruce Amber Logan Denise Alan Beverly Juan Charlotte Elijah Natalie Albert Diana Wayne Brittany Randy Doris Mason
Kayla Vincent Alexis Liam Lori Roy Marie Caleb Kristen Bradley Hailey Russell Brooke Lucas Mei Hiroshi Sione Malia
Tevita Leilani Priya Arjun Aisha Omar Fatima Lucia Mateo Sofia Diego Camila Minh Linh Jae Chen Wei Kai Nia Imani
Tariq Yusuf Elena Nadia Ivan Anya Rosa Luis Carmen Javier Ana Paulo Ngozi Kwame Amara Dakota Tala Aiyana Makana""".split()

LAST_NAMES = """Smith Johnson Williams Brown Jones Garcia Miller Davis Rodriguez Martinez Hernandez Lopez Gonzalez Wilson
Anderson Thomas Taylor Moore Jackson Martin Lee Perez Thompson White Harris Sanchez Clark Ramirez Lewis Robinson Walker
Young Allen King Wright Scott Torres Nguyen Hill Flores Green Adams Nelson Baker Hall Rivera Campbell Carter Roberts
Gomez Phillips Evans Turner Diaz Parker Cruz Edwards Collins Reyes Stewart Morris Morales Murphy Cook Rogers Gutierrez
Ortiz Morgan Cooper Peterson Bailey Reed Kelly Howard Ramos Kim Cox Ward Richardson Watson Brooks Chavez Wood Bennett
Gray Mendoza Ruiz Hughes Price Alvarez Castillo Sanders Patel Myers Long Ross Foster Jimenez Powell Jenkins Perry
Russell Sullivan Bell Coleman Butler Henderson Barnes Fisher Vasquez Simmons Romero Patterson Hamilton Graham Reynolds
Griffin Wallace Moreno West Cole Hayes Bryant Herrera Gibson Ellis Tran Medina Aguilar Stevens Murray Ford Castro
Marshall Owens Harrison Fernandez Woods Kennedy Wells Vargas Freeman Webb Tucker Guzman Burns Crawford Olson Simpson
Porter Hunter Gordon Mendez Silva Shaw Snyder Dixon Hunt Hicks Holmes Palmer Wagner Black Robertson Boyd Rose Stone
Salazar Fox Warren Mills Meyer Rice Schmidt Garza Daniels Ferguson Nichols Stephens Soto Weaver Gardner Payne Grant
Dunn Spencer Hawkins Arnold Pierce Hansen Peters Santos Hart Knight Elliott Cunningham Duncan Armstrong Hudson Carroll
Lane Riley Andrews Ray Delgado Berry Perkins Hoffman Johnston Matthews Pena Richards Contreras Willis Carpenter
Lawrence Sandoval Christensen Jensen Larsen Nielsen Sorensen Petersen Olsen Madsen Fonua Tuilagi Mahe Havili Nakamura
Tanaka Sato Park Choi Wu Zhang Liu Singh Sharma Okafor Mensah Begay Yazzie Tsosie Whitaker Holloway Whitfield""".split()

PLACES = {
    'UT': ['Wasatch', 'Bonneville', 'Cache Valley', 'Bear River', 'Uinta', 'Timpanogos', 'Red Rock', 'Canyonlands',
           'Ogden Valley', 'Provo River', 'Sanpete', 'Beehive', 'Great Basin', 'Oquirrh', 'Jordan River',
           'Heber Valley', 'Moab', 'Summit County', 'Davis County', 'Utah Valley', 'Wasatch Front', 'Millcreek',
           'Sugar House', 'Cottonwood', 'Kolob', 'Weber River', 'Tooele Valley', 'Castle Valley', 'Escalante',
           'Sevier Valley', 'Box Elder', 'Iron County', 'Morgan Valley', 'Emigration Canyon', 'Salt Lake'],
    'ID': ['Snake River', 'Treasure Valley', 'Sawtooth', 'Gem State', 'Boise River', 'Palouse', 'Magic Valley',
           'Selkirk', 'Owyhee', 'Clearwater', 'Teton Basin', 'Wood River', 'Payette', 'Salmon River', 'Panhandle',
           'Portneuf', 'Lemhi', 'Camas Prairie'],
    'WY': ['Teton', 'Big Horn', 'Wind River', 'Laramie', 'High Plains', 'Powder River', 'Absaroka', 'Medicine Bow',
           'Sweetwater', 'Casper Mountain', 'Snowy Range', 'Green River', 'Shoshone', 'Platte Valley', 'Star Valley'],
    'CA': ['Sierra', 'Bay Area', 'Central Valley', 'Monterey Bay', 'Redwood Coast', 'Tahoe Basin', 'Mojave',
           'San Joaquin', 'Sacramento Valley', 'Santa Cruz Mountains', 'Eastern Sierra', 'Delta'],
}
STATES = {
    'UT': (['Salt Lake City', 'Provo', 'Ogden', 'Park City', 'St. George', 'Logan', 'Sandy', 'Lehi', 'Orem', 'Draper',
            'Moab', 'Heber City', 'Bountiful', 'Layton'], ['801', '385', '435']),
    'ID': (['Boise', 'Idaho Falls', 'Pocatello', "Coeur d'Alene", 'Twin Falls', 'Meridian', 'Nampa', 'Ketchum'], ['208', '986']),
    'WY': (['Cheyenne', 'Casper', 'Laramie', 'Jackson', 'Sheridan', 'Gillette', 'Cody', 'Rock Springs'], ['307']),
    'CA': (['San Francisco', 'Sacramento', 'Oakland', 'San Jose', 'Los Angeles', 'San Diego', 'Fresno', 'Berkeley'],
           ['415', '916', '510', '408', '213', '619']),
    'CO': (['Denver', 'Boulder', 'Fort Collins'], ['303', '720']),
    'NV': (['Las Vegas', 'Reno'], ['702', '775']),
    'AZ': (['Phoenix', 'Tucson', 'Flagstaff'], ['602', '520']),
}
CAUSES = ['Youth', 'Literacy', 'Food Security', 'Housing', 'Arts', 'Community Health', 'Refugee Welcome', 'Animal Rescue',
          'Conservation', 'Mentoring', 'Senior Services', 'Family Services', 'Music', 'Science Education', 'Watershed',
          'Veterans', 'Disability Services', 'Early Learning', 'Recovery', 'Hunger Relief', 'Trails', 'Theater',
          'Homeless Services', 'Adult Education', 'Wildlife', 'Outdoor Education', 'Clean Air', 'Scholarship',
          'Food Bank', 'Dance', 'Chamber Music', 'Habitat', 'Arts Education', 'After School']
NP_WORDS = ['Alliance', 'Center', 'Council', 'Coalition', 'Network', 'Project', 'Collective', 'Society', 'Partners',
            'Services', 'Initiative', 'Association', 'League']
OTHER_PATTERNS = ['{p} Community Foundation', '{p} Health Foundation', '{s} Family Foundation', '{p} Education Foundation',
                  '{p} Arts Endowment', '{p} Civic Trust', '{p} Medical Society', '{p} Conservation Trust',
                  '{p} Library Foundation', '{p} Hospital Foundation', '{p} Heritage Society', '{s} Charitable Trust',
                  '{p} Teachers Association', '{p} Growers Association', '{s}-{s2} Foundation']
BIZ_PATTERNS = ['{p} Dental Group', '{s} & Sons Construction', '{p} Veterinary Clinic', '{p} Brewing Co.', '{s} Engineering',
                '{p} Physical Therapy', '{p} Heating & Air', '{p} Coffee Roasters', '{s} Law Group', '{p} Landscaping',
                '{p} Software', '{p} Auto Works', '{p} Family Dentistry', '{s} Architecture', '{p} Print & Sign',
                '{p} Orthodontics', '{p} Outfitters', '{p} Title & Escrow', '{p} Pediatrics', '{p} Electric',
                '{p} Roofing', '{s} Marketing', '{p} Chiropractic', '{p} Bakery', '{p} Manufacturing', '{p} Home Health',
                '{s} Surveying', '{p} Optometry', '{p} Tire & Service', '{s} Insurance Agency']
AFF_PATTERNS = ['{s} & {s2} CPAs', '{p} Estate Planning Law', '{s} Tax & Advisory', '{p} Benefits Consulting',
                '{p} Insurance Partners', '{s} Law Office', '{p} Payroll Services', '{p} Business Brokers']

NP_DM = ['Executive Director', 'CEO', 'President & CEO', 'Board Treasurer', 'Board Chair', 'Chief Financial Officer',
         'Finance Director']
NP_OTHER = ['Development Director', 'Operations Director', 'Finance Manager', 'Controller', 'Program Director',
            'Office Manager', 'Grants Manager']
OT_DM = ['Executive Director', 'President', 'Chief Financial Officer', 'Investment Committee Chair', 'Treasurer',
         'Vice President of Finance']
OT_OTHER = ['Controller', 'Program Officer', 'Finance Manager', 'Director of Operations']
BIZ_DM = ['Owner', 'President', 'CEO', 'Managing Partner', 'Chief Financial Officer', 'Founder']
BIZ_OTHER = ['HR Director', 'Office Manager', 'Operations Manager', 'Controller', 'HR & Benefits Manager']
AFF_TITLES = ['Partner, CPA', 'Estate Planning Attorney', 'Managing Partner', 'Principal', 'Founder', 'Benefits Consultant',
              'Senior Tax Advisor']
OCIO_TITLES = ['Physician', 'Business Owner', 'Retired Executive', 'Attorney', 'Surgeon', 'Dentist', 'Software Executive',
               'Real Estate Investor', 'Orthodontist', 'Retired Physician', 'Entrepreneur', 'Private Equity Partner']
OCIO_UNI_TITLES = ['Professor of Medicine', 'Professor of Finance', 'Department Chair, Engineering', 'Professor Emeritus',
                   'Dean, School of Business', 'Associate Professor of Law']
ROBO_TITLES = ['Software Engineer', 'Registered Nurse', 'Teacher', 'Data Analyst', 'Product Designer', 'Marketing Manager',
               'Pharmacist', 'Mechanical Engineer', 'Accountant', 'Physical Therapist', 'Sales Manager', 'UX Researcher',
               'Financial Analyst', 'Project Manager', 'Dental Hygienist', 'Paralegal']
ROBO_UNI_TITLES = ['PhD Candidate', 'Assistant Professor', 'Postdoctoral Researcher', 'Research Scientist', 'Lecturer']
EMPLOYERS = ['Wasatch Orthopedics', 'Canyon Crest Dental', 'Granite Peak Health', 'Silver Creek Capital',
             'Red Butte Software', 'Timp Point Medical', 'Beehive Logistics', 'Alta Vista Realty', 'Lone Peak Labs',
             'Silicon Slopes Analytics', 'Sugar House Design Co.', 'Mountain West Clinic', 'Jordan Valley Schools']
UNIVERSITIES = [('Summit Ridge University', 'summitridge.edu.example'),
                ('Canyonlands State University', 'canyonlandsstate.edu.example')]
PERSONAL_DOMAINS = ['mail.example', 'inbox.example', 'webmail.example']


# ---------------------------------------------------------------------------
# stores
# ---------------------------------------------------------------------------

ORGS: list[dict] = []
ORG_BY_ID: dict[int, dict] = {}
ORG_KEYS: set[str] = set()
DOMAINS: set[str] = set()
CONTACTS: list[dict] = []
CT_BY_ID: dict[int, dict] = {}
EMAILS: set[str] = set()
TOUCHES: list[dict] = []
OPPS: list[dict] = []
ORG_OPP_SPANS: dict[int, list] = defaultdict(list)
EVENTS: list[dict] = []
CAMPAIGNS: dict[str, dict] = {}
RFPS: list[dict] = []
EXTRA_REMINDERS: list[dict] = []
LEGACY_ROWS: dict[str, int] = defaultdict(lambda: 2)


def org_key(name: str) -> str:
    """Python mirror of public.norm_org_name (keeps generated names unique the same way the database does)."""
    s = name.lower().replace('&', ' and ')
    s = re.sub(r'[^a-z0-9 ]', ' ', s)
    for pat, rep_ in ((r'\bctr\b', 'center'), (r'\b(assn|assoc)\b', 'association'), (r'\b(fdn|fndn|fdtn)\b', 'foundation'),
                      (r'\b(svcs|svc)\b', 'services'), (r'\buniv\b', 'university'), (r'\bintl\b', 'international'),
                      (r'\bmt\b', 'mount')):
        s = re.sub(pat, rep_, s)
    s = re.sub(r'^\s*the\s+', '', s)
    s = re.sub(r'(\s+(inc|incorporated|llc|ltd|limited|corp|corporation|co|company|pc|pllc|lp|llp))+\s*$', '', s)
    return re.sub(r'\s+', ' ', s).strip()


def make_domain(name: str, tld: str = 'example') -> str:
    words = [w for w in re.sub(r'[^a-z0-9 ]', ' ', name.lower().replace('&', ' ')).split()
             if w not in ('the', 'and', 'of', 'inc', 'llc', 'co')]
    slug = ''.join(words)
    if len(slug) > 22:
        slug = words[0] + ''.join(w[0] for w in words[1:-1]) + words[-1]
    base, i = slug, 2
    while f'{slug}.{tld}' in DOMAINS:
        slug, i = f'{base}{i}', i + 1
    DOMAINS.add(f'{slug}.{tld}')
    return f'{slug}.{tld}'


def website_for(domain: str) -> str:
    return wpick({f'https://www.{domain}': 5, f'https://{domain}': 3, f'http://{domain}/': 1, f'www.{domain}': 1})


def legacy(tab: str) -> str:
    n = LEGACY_ROWS[tab]
    LEGACY_ROWS[tab] += 1
    return f'{tab} row {n}'


def org_name(seg: str, state: str) -> str:
    for _ in range(500):
        p = pick(PLACES.get(state, PLACES['UT']))
        s, s2 = pick(LAST_NAMES), pick(LAST_NAMES)
        if seg == 'ORG_NONPROFIT':
            name = wpick({f'{p} {pick(CAUSES)} {pick(NP_WORDS)}': 70,
                          f'{pick(CAUSES)} {pick(NP_WORDS)} of {p}': 15,
                          f'Friends of {p} {pick(["Library", "Parks", "Trails", "Museum", "Symphony"])}': 15})
        elif seg == 'ORG_OTHER':
            name = pick(OTHER_PATTERNS).format(p=p, s=s, s2=s2)
        elif seg == 'RET_401K':
            name = pick(BIZ_PATTERNS).format(p=p, s=s)
            if chance(0.30) and not name.endswith('Co.'):
                name += wpick({' LLC': 3, ', Inc.': 2})
        else:
            name = pick(AFF_PATTERNS).format(p=p, s=s, s2=s2)
        k = org_key(name)
        if k not in ORG_KEYS:
            ORG_KEYS.add(k)
            return name
    raise RuntimeError('ran out of organization names')


def make_org(seg: str, state: str, sourced: dt.date, source_detail: str, tab: str, name: str | None = None,
             domain: str | None = None, **extra) -> dict:
    name = name or org_name(seg, state)
    ORG_KEYS.add(org_key(name))
    if domain:
        DOMAINS.add(domain)
    domain = domain or make_domain(name)
    if seg == 'ORG_NONPROFIT':
        aum, emp = lognormal_money(2e6, 0.9, 150e3, 40e6, 10e3), None
        org_type = pick(['Human services', 'Arts & culture', 'Education', 'Health', 'Environment', 'Community development'])
    elif seg == 'ORG_OTHER':
        aum, emp = lognormal_money(8e6, 0.8, 1e6, 120e6, 50e3), None
        org_type = 'Foundation' if 'Foundation' in name or 'Trust' in name else 'Association / institution'
    elif seg == 'RET_401K':
        emp = rint(6, 160)
        aum = lognormal_money(emp * 22e3, 0.6, 60e3, 12e6, 5e3) if chance(0.8) else None
        org_type = 'Small business'
    else:
        aum, emp, org_type = None, None, 'Referral partner'
    o = dict(id=len(ORGS) + 1, name=name, segment_code=seg, org_type=org_type,
             website=website_for(domain) if (seg != 'RET_401K' or chance(0.8)) else None,
             domain=domain, phone=phone(state) if chance(0.6) else None,
             city=pick(STATES[state][0]), state=state, reported_aum=aum, employee_count=emp,
             is_university_affiliated=False, do_not_contact=False, dnc_reason=None,
             owner_id=owner_for(seg, state), tags=[], notes=None, source_detail=source_detail,
             legacy_ref=legacy(tab), created_at=at(sourced, 17))
    o.update(extra)
    ORGS.append(o)
    ORG_BY_ID[o['id']] = o
    return o


def phone(state: str) -> str:
    return f"({pick(STATES[state][1])}) 555-01{rint(0, 99):02d}"


def email_local(first: str, last: str, pattern: str) -> str:
    f = re.sub(r'[^a-z]', '', first.lower())
    l_ = re.sub(r'[^a-z]', '', last.lower())
    return {'first.last': f'{f}.{l_}', 'flast': f'{f[0]}{l_}', 'first': f, 'firstl': f'{f}{l_[0]}',
            'first_last': f'{f}_{l_}'}[pattern]


def unique_email(local: str, domain: str) -> str:
    e, i = f'{local}@{domain}', 2
    while e in EMAILS:
        e, i = f'{local}{i}@{domain}', i + 1
    EMAILS.add(e)
    return e


def make_linkedin(first: str, last: str) -> str:
    slug = re.sub(r'[^a-z-]', '', f'{first}-{last}'.lower())
    return f'https://www.linkedin.com/in/{slug}-{R.getrandbits(32):08x}'


def make_contact(seg: str, state: str, sourced: dt.date, channel: str, source_detail: str, tab: str,
                 org: dict | None = None, title: str | None = None, dm: bool | None = None, first: str | None = None,
                 last: str | None = None, email: str | None = None, uni: tuple | None = None,
                 event_id: int | None = None, referred_by: int | None = None, employer: str | None = None) -> dict:
    first = first or pick(FIRST)
    last = last or pick(LAST_NAMES)
    party = PARTY[seg]
    if title is None:
        pools = {'ORG_NONPROFIT': (NP_DM, NP_OTHER), 'ORG_OTHER': (OT_DM, OT_OTHER), 'RET_401K': (BIZ_DM, BIZ_OTHER)}
        if seg in pools:
            dm = chance(0.7) if dm is None else dm
            title = pick(pools[seg][0] if dm else pools[seg][1])
        elif seg == 'AFFILIATE':
            title, dm = pick(AFF_TITLES), True
        elif seg == 'IND_OCIO':
            title = pick(OCIO_UNI_TITLES) if uni else pick(OCIO_TITLES)
        else:
            title = pick(ROBO_UNI_TITLES) if uni else pick(ROBO_TITLES)
    if email is None:
        if org is not None:
            email = unique_email(email_local(first, last, org.setdefault('_pattern', wpick(
                {'first.last': 50, 'flast': 25, 'first': 12, 'firstl': 8, 'first_last': 5}))), org['domain'])
        elif uni:
            email = unique_email(email_local(first, last, 'first.last'), uni[1])
        else:
            email = unique_email(email_local(first, last, 'first.last') + (str(rint(1, 99)) if chance(0.4) else ''),
                                 pick(PERSONAL_DOMAINS))
    else:
        EMAILS.add(email)
    has_li = chance(0.6 if party == 'organization' else 0.45)
    li = make_linkedin(first, last) if has_li else None
    c = dict(id=len(CONTACTS) + 1, organization_id=org['id'] if org else None, segment_code=seg,
             first_name=first, last_name=last, title=title, employer=employer if party == 'individual' else None,
             is_decision_maker=bool(dm) if party == 'organization' else False,
             email=email, email_status='unverified',
             phone=phone(state) if chance(0.75 if party == 'organization' else 0.5) else None,
             linkedin_url=li,
             linkedin_connected_on=min(LAST, sourced + days(rint(0, 30))) if (li and chance(0.4)) else None,
             city=(org['city'] if org else pick(STATES[state][0])), state=state,
             prospect_aum=None, source_channel_code=channel, source_detail=source_detail, source_event_id=event_id,
             referred_by_contact_id=referred_by, sourced_on=sourced,
             is_university_affiliated=bool(uni) or bool(org and org.get('is_university_affiliated')),
             do_not_contact=False, dnc_reason=None, dnc_on=None,
             newsletter_status='not_subscribed', newsletter_added_on=None, newsletter_added_via=None,
             follow_up_style='personalized', owner_id=owner_for(seg, state), tags=[], notes=None,
             legacy_ref=legacy(tab) if tab else None, created_at=at(sourced, 17))
    if seg == 'IND_OCIO':
        c['prospect_aum'] = lognormal_money(3e6, 0.7, 750e3, 25e6, 50e3)
    elif seg == 'IND_ROBO':
        c['prospect_aum'] = lognormal_money(60e3, 0.8, 5e3, 500e3, 1e3)
    if party == 'individual' and employer is None:
        c['employer'] = uni[0] if uni else (pick(EMPLOYERS) if chance(0.7) else None)
    if 'Board' in (title or ''):
        c['tags'] = ['board_member']
    CONTACTS.append(c)
    CT_BY_ID[c['id']] = c
    return c


# ---------------------------------------------------------------------------
# message text
# ---------------------------------------------------------------------------

def org_name_of(c: dict) -> str | None:
    return ORG_BY_ID[c['organization_id']]['name'] if c['organization_id'] else None


def first_subject(c: dict) -> str:
    org = org_name_of(c) or ''
    return {
        'ORG_NONPROFIT': pick([f'Investment support for {org}', f"{org}'s reserves", f"Quick question about {org}'s endowment"]),
        'ORG_OTHER': pick([f'Investment management for {org}', f'OCIO support for {org}']),
        'RET_401K': pick([f'401(k) options for {org}', 'A retirement plan for your team', f'{org} 401(k) question']),
        'AFFILIATE': 'Referral partnership with GAARD Capital',
        'IND_OCIO': pick(['Institutional-style investing for your family', f'Introduction, {c["first_name"]}']),
        'IND_ROBO': pick(['Low-cost automated investing', "GAARD's new robo-advisor"]),
    }[c['segment_code']]


def outbound_body(t: dict, c: dict) -> str:
    me = TEAM_BY_ID[t['owner_id']]['full_name'].split()[0]
    org = org_name_of(c) or 'your family'
    seg = c['segment_code']
    if t['touch_type'] == 'check_in':
        return (f"Hi {c['first_name']},\n\nChecking in and sharing our latest quarterly update. "
                f"Happy to answer any questions or set up time to talk.\n\nBest,\n{me}\nGAARD Capital")
    if (t.get('sequence_step') or 1) > 1:
        return (f"Hi {c['first_name']},\n\nFollowing up on my note below in case it got buried. "
                f"Would a 20-minute call in the next few weeks be useful?\n\nBest,\n{me}")
    pitch = {
        'ORG_NONPROFIT': f"We are a Salt Lake City investment adviser working with nonprofits on reserves and endowments. "
                         f"Many organizations like {org} keep most of their reserves in bank accounts; we help boards put "
                         f"an investment policy in place and manage it at institutional pricing.",
        'ORG_OTHER': f"We provide OCIO-style investment management for foundations and institutions like {org}.",
        'RET_401K': "We help small businesses set up or improve their 401(k): lower fees, better fund lineups, and a "
                    "fiduciary partner for the owner.",
        'AFFILIATE': "Several of our clients came to us through CPAs and attorneys, and I think there is a natural fit "
                     "for a referral relationship.",
        'IND_OCIO': "We bring an institutional, endowment-style approach to families and individuals.",
        'IND_ROBO': "We just launched a low-cost robo-advisor for people getting started with investing.",
    }[seg]
    return f"Hi {c['first_name']},\n\n{pitch}\n\nWould you be open to a short call?\n\nBest,\n{me}\nGAARD Capital"


def reply_for(outcome: str, c: dict, t: dict) -> str:
    me = TEAM_BY_ID[t['owner_id']]['full_name'].split()[0]
    org = org_name_of(c) or 'our family office'
    org_like = PARTY[c['segment_code']] == 'organization'
    if outcome == 'HAS_ADVISOR':
        return pick([f"Hi {me}, thanks for reaching out. We already work with an advisor and are happy with the "
                     f"relationship, so we'll pass for now.",
                     "Thank you for the note. We have a long-standing relationship with our current advisor, so we are "
                     "not looking to make a change.",
                     "Appreciate you thinking of us. We already have an advisor we're happy with. Best of luck!",
                     f"Thanks {me}. We already work with a local firm and aren't looking at alternatives right now."])
    if outcome == 'NOT_NOW':
        month = t['follow_up_on'].strftime('%B')
        why = pick(["we're in the middle of our budget cycle", 'our board meets later in the year',
                    'this quarter is busy for us']) if org_like else pick(["I'm in the middle of a move",
                                                                          'work is busy right now', 'we are traveling'])
        return pick([f"Thanks for following up. Right now {why}. Could you check back in {month}?",
                     f"Not right now, {why}. Please reach out again in {month}.",
                     f"Good timing question, but {why}. Circle back in {month} and we can talk."])
    if outcome == 'INTERESTED':
        return pick([f"Thanks {me}, the timing is actually good. Could we set up a call {t['follow_up_on']:%A the %-d}?",
                     f"Yes, I'd like to learn more. I'm free {t['follow_up_on']:%A} afternoon.",
                     f"This has been on my list. Happy to talk, does {t['follow_up_on']:%b %-d} work?"])
    if outcome == 'NOT_INTERESTED':
        return pick(['No thank you.', "We're not interested, thanks.", 'Not something we are looking at. Thank you.',
                     'No thanks, we are all set.'])
    if outcome == 'UNSUBSCRIBE':
        return pick(['Please remove me from your email list.', 'Unsubscribe', 'Please stop emailing me. Thanks.'])
    if outcome == 'OUT_OF_OFFICE':
        return (f"I am out of the office until {t['ooo_return_on']:%A, %B %-d} with limited access to email. "
                f"For anything urgent please call our main office.")
    if outcome == 'BOUNCED':
        return (f"Address not found. Your message wasn't delivered to {t['_to']} because the address couldn't be found "
                f"or is unable to receive mail.")
    if outcome == 'WRONG_PERSON':
        return pick([f"{c['first_name']} is no longer with {org}. Please reach out to our new executive director.",
                     f"I retired from {org} this spring. Our finance director would be the right person now."])
    if outcome == 'REFERRED_INTERNALLY':
        return f"Thanks. I'm copying our {t.get('_colleague_title', 'finance director')}, who handles our investment accounts."
    if outcome == 'HOT':
        return 'Thanks for the materials. Can we get the rest of the committee on a call?'
    if outcome == 'READY_TO_ONBOARD':
        return 'We are ready to move forward. Please send over the paperwork.'
    if outcome == 'NOT_A_FIT':
        return 'After discussing internally we have decided not to make a change this year.'
    return ''


# ---------------------------------------------------------------------------
# touches
# ---------------------------------------------------------------------------

def add_touch(c: dict, touch_type: str, when: dt.datetime, outcome: str | None, **kw) -> dict:
    if outcome is not None:
        assert touch_type in OUTCOMES[outcome][1], (outcome, touch_type)
    if c['do_not_contact'] and touch_type in ('email', 'call', 'check_in'):
        raise AssertionError(f'outreach to DNC contact {c["id"]}')
    t = dict(id=len(TOUCHES) + 1, contact_id=c['id'], organization_id=c['organization_id'], touch_type=touch_type,
             direction=kw.pop('direction', 'outbound'), touched_at=when, campaign_id=kw.pop('campaign_id', None),
             event_id=kw.pop('event_id', None), rfp_id=kw.pop('rfp_id', None),
             sequence_step=kw.pop('sequence_step', None), subject=kw.pop('subject', None), notes=kw.pop('notes', None),
             outcome_code=outcome, outcome_status='confirmed', outcome_raw=None, responded_at=None,
             response_excerpt=None, follow_up_on=kw.pop('follow_up_on', None), ooo_return_on=None,
             ai_suggested_outcome=None, ai_confidence=None, ai_reason=None, confirmed_by=None, confirmed_at=None,
             owner_id=c['owner_id'], _to=c['email'])
    t.update(kw)
    TOUCHES.append(t)
    return t


def record_reply(c: dict, t: dict, outcome: str, delay_hours: tuple = (3, 70)) -> None:
    """Fill in the reply side of an outreach touch (response time, text, email status, DNC)."""
    sent = t['touched_at']
    if outcome == 'OUT_OF_OFFICE':
        t['responded_at'] = sent + dt.timedelta(minutes=rint(1, 4))
        t['ooo_return_on'] = bday(sent.date() + days(rint(5, 15)))
    elif outcome == 'BOUNCED':
        t['responded_at'] = sent + dt.timedelta(minutes=1)
    elif OUTCOMES[outcome][2]:
        t['responded_at'] = sent + dt.timedelta(hours=rint(*delay_hours))
    else:
        return
    if outcome == 'NOT_NOW' and not t.get('follow_up_on'):
        t['follow_up_on'] = month_start_after(sent.date(), rint(1, 4))
    if outcome == 'INTERESTED' and not t.get('follow_up_on'):
        t['follow_up_on'] = bday(t['responded_at'].date() + days(rint(3, 10)))
    if t['responded_at'].date() > LAST:
        t['responded_at'] = at(LAST, 16)
    text = reply_for(outcome, c, t)
    t['_reply'] = text
    t['response_excerpt'] = text[:140]
    t['confirmed_by'] = c['owner_id']
    t['confirmed_at'] = t['responded_at'] + dt.timedelta(hours=rint(1, 20))
    if t['touch_type'] in ('email', 'check_in'):
        if OUTCOMES[outcome][8]:
            c['email_status'] = 'bounced'
        elif outcome == 'WRONG_PERSON':
            c['email_status'] = 'wrong_person'
        elif OUTCOMES[outcome][2]:
            c['email_status'] = 'valid'
    if outcome == 'UNSUBSCRIBE':
        c['do_not_contact'] = True
        c['dnc_reason'] = 'Asked not to be contacted'
        c['dnc_on'] = sent.date()
        if c['newsletter_status'] == 'subscribed':
            c['newsletter_status'] = 'unsubscribed'


# outcome distributions -------------------------------------------------------

COLD1 = {'NO_RESPONSE': .84, 'OUT_OF_OFFICE': .045, 'BOUNCED': .045, 'WRONG_PERSON': .008, 'REFERRED_INTERNALLY': .006,
         'NOT_NOW': .013, 'HAS_ADVISOR': .012, 'NOT_INTERESTED': .011, 'UNSUBSCRIBE': .003, 'INTERESTED': .012}
COLD2 = {'NO_RESPONSE': .91, 'OUT_OF_OFFICE': .02, 'NOT_NOW': .012, 'HAS_ADVISOR': .011, 'NOT_INTERESTED': .012,
         'UNSUBSCRIBE': .006, 'INTERESTED': .009, 'REFERRED_INTERNALLY': .004}
COLD3 = {'NO_RESPONSE': .94, 'NOT_NOW': .009, 'HAS_ADVISOR': .01, 'NOT_INTERESTED': .015, 'UNSUBSCRIBE': .008,
         'INTERESTED': .006}
REVISIT_NOTNOW = {'NO_RESPONSE': .48, 'INTERESTED': .10, 'NOT_NOW': .18, 'HAS_ADVISOR': .12, 'NOT_INTERESTED': .10,
                  'OUT_OF_OFFICE': .02}
REVISIT_ADVISOR = {'NO_RESPONSE': .62, 'NOT_NOW': .12, 'HAS_ADVISOR': .15, 'INTERESTED': .04, 'NOT_INTERESTED': .07}
EVENT_FU = {'NO_RESPONSE': .58, 'INTERESTED': .10, 'NOT_NOW': .12, 'HAS_ADVISOR': .09, 'NOT_INTERESTED': .07,
            'OUT_OF_OFFICE': .04}
EVENT_FU_MEETING = {'NO_RESPONSE': .35, 'INTERESTED': .22, 'NOT_NOW': .22, 'HAS_ADVISOR': .13, 'NOT_INTERESTED': .08}
REFERRAL_FU = {'NO_RESPONSE': .30, 'INTERESTED': .25, 'NOT_NOW': .20, 'HAS_ADVISOR': .13, 'NOT_INTERESTED': .10,
               'OUT_OF_OFFICE': .02}
CALL_CONNECTED = {'NOT_INTERESTED': .32, 'HAS_ADVISOR': .22, 'NOT_NOW': .22, 'INTERESTED': .14, 'WRONG_PERSON': .03,
                  'REFERRED_INTERNALLY': .02, 'UNSUBSCRIBE': .05}
POSITIVE = {'INTERESTED', 'NOT_NOW', 'REFERRED_INTERNALLY'}
SEG_MULT = {'ORG_NONPROFIT': 1.0, 'ORG_OTHER': 0.85, 'RET_401K': 1.0, 'IND_OCIO': 1.1, 'IND_ROBO': 1.2, 'AFFILIATE': 1.3}
STATE_MULT = {'UT': 1.3, 'ID': 0.85, 'WY': 0.95, 'CA': 0.55}


def sample(dist: dict, c: dict, year: int) -> str:
    m = SEG_MULT[c['segment_code']] * STATE_MULT.get(c['state'], 0.8) * (0.9 if year == 2025 else 1.05)
    d = {k: (v * m if k in POSITIVE else v) for k, v in dist.items()}
    if 'NO_RESPONSE' in d:
        d['NO_RESPONSE'] = max(0.05, 1 - sum(v for k, v in d.items() if k != 'NO_RESPONSE'))
    return wpick(d)


# ---------------------------------------------------------------------------
# journeys
# ---------------------------------------------------------------------------

def email_sequence(c: dict, start: dt.date, campaign: str | None, *, until: dt.date = LAST, subject: str | None = None,
                   dist_first: dict = COLD1, max_attempts: int = 4, step_offset: int = 0) -> str | None:
    """Cold email with follow-ups: 1st email, follow-up a week later, then quarterly retries."""
    d, step, attempts = bday(start), 1, 0
    subject = subject or first_subject(c)
    camp_id = CAMPAIGNS[campaign]['id'] if campaign else None
    while d <= until and attempts < max_attempts and not c['do_not_contact'] and c['email_status'] != 'wrong_person':
        attempts += 1
        dist = dist_first if step == 1 else (COLD2 if step == 2 else COLD3)
        out = sample(dist, c, d.year)
        t = add_touch(c, 'email', at(d), out, campaign_id=camp_id, sequence_step=step + step_offset,
                      subject=subject if step == 1 else f'Re: {subject}')
        record_reply(c, t, out)
        if out == 'NO_RESPONSE':                      # Jon: "we just kind of reach out quarterly"
            d, step = bday(d + days(rint(85, 100))), step + 1
            continue
        if out == 'OUT_OF_OFFICE':
            d, step = bday(t['ooo_return_on'] + days(1)), step + 1
            continue
        if out == 'BOUNCED':
            fix_on = bday(d + days(rint(5, 25)))
            if chance(0.45) and fix_on <= until:
                new = unique_email(email_local(c['first_name'], c['last_name'], 'flast'),
                                   c['email'].split('@')[1])
                c['notes'] = f"Email bounced {d:%m/%d/%y} ({c['email']}); found new address {fix_on:%m/%d/%y}."
                c['email'], c['email_status'] = new, 'unverified'
                d, step = fix_on, 1
                continue
            return 'BOUNCED'
        if out == 'REFERRED_INTERNALLY':
            spawn_colleague(c, t)
            return out
        if out == 'INTERESTED':
            start_opportunity(c, t)
            return out
        if out in ('NOT_NOW', 'HAS_ADVISOR'):
            return revisit(c, t, out, until)
        return out
    return 'NO_RESPONSE' if attempts else None


def revisit(c: dict, t: dict, out: str, until: dt.date, depth: int = 0) -> str:
    """Come back on the date they gave ("check back in October"), or 6 months after "has an advisor"."""
    nxt = t['follow_up_on'] if out == 'NOT_NOW' else bday(t['touched_at'].date() + days(180))
    if depth >= 2 or nxt > until or c['do_not_contact']:
        return out
    dist = REVISIT_NOTNOW if out == 'NOT_NOW' else REVISIT_ADVISOR
    res = sample(dist, c, nxt.year)
    t2 = add_touch(c, 'email', at(nxt), res, subject='Checking back in', sequence_step=None)
    record_reply(c, t2, res)
    if res == 'INTERESTED':
        start_opportunity(c, t2)
    elif res in ('NOT_NOW', 'HAS_ADVISOR'):
        return revisit(c, t2, res, until, depth + 1)
    elif res == 'OUT_OF_OFFICE':
        d = bday(t2['ooo_return_on'] + days(1))
        if d <= until:
            res2 = sample(COLD2, c, d.year)
            t3 = add_touch(c, 'email', at(d), res2, subject='Re: Checking back in')
            record_reply(c, t3, res2)
            if res2 == 'INTERESTED':
                start_opportunity(c, t3)
    return res


def spawn_colleague(c: dict, t: dict) -> None:
    """ "I'm copying our finance director" -> a new contact at the same organization."""
    org = ORG_BY_ID.get(c['organization_id'])
    if not org:
        return
    seg = c['segment_code']
    title = {'ORG_NONPROFIT': 'Finance Director', 'ORG_OTHER': 'Chief Financial Officer',
             'RET_401K': 'HR Director', 'AFFILIATE': 'Managing Partner'}[seg]
    t['_colleague_title'] = title.lower()
    t['response_excerpt'] = reply_for('REFERRED_INTERNALLY', c, t)[:140]
    t['_reply'] = reply_for('REFERRED_INTERNALLY', c, t)
    d = t['responded_at'].date()
    col = make_contact(seg, c['state'], d, c['source_channel_code'], f"Referred by colleague {c['first_name']} {c['last_name']}",
                       None, org=org, title=title, dm=True, referred_by=c['id'])
    fu = bday(d + days(rint(1, 3)))
    if fu <= LAST:
        email_sequence(col, fu, None, subject=f"Introduction via {c['first_name']}", dist_first=REFERRAL_FU)


def event_journey(c: dict, ev: dict) -> None:
    d = ev['start_on']
    out = wpick({'MET_AT_EVENT': 72, 'MEETING_AT_EVENT': 21, 'INTERESTED': 7})
    t = add_touch(c, 'event', at(d, rint(9, 18)), out, event_id=ev['id'],
                  direction='in_person' if ev['format'] == 'in_person' else 'inbound',
                  notes=pick(['Exchanged cards at the booth.', 'Talked after the finance panel.',
                              'Sat at our table at lunch.', 'Asked a question in the Q&A; followed up after.',
                              'Registered and attended the full session.']))
    if out == 'MEETING_AT_EVENT':
        t['responded_at'] = t['touched_at']
        t['notes'] = 'Sat down for 20 minutes at the event: ' + pick(
            ['talked through their reserve policy.', 'discussed their current advisor fees.',
             'walked through how the robo-advisor works.', 'they asked about 401(k) fiduciary coverage.'])
    if out == 'INTERESTED':
        t['responded_at'] = t['touched_at']
        t['follow_up_on'] = bday(d + days(rint(4, 12)))
        t['notes'] = 'Booked a call on the spot.'
        start_opportunity(c, t)
        return
    if chance(0.12):
        c['newsletter_status'], c['newsletter_added_on'], c['newsletter_added_via'] = 'subscribed', d, 'manual: signed up at event'
    fu = bday(d + days(rint(2, 5)))
    if fu <= LAST:
        email_sequence(c, fu, None, subject=f"Great meeting you at {ev['name']}",
                       dist_first=EVENT_FU_MEETING if out == 'MEETING_AT_EVENT' else EVENT_FU)


def referral_journey(c: dict, referrer: dict | None, referrer_name: str) -> None:
    d = c['sourced_on']
    out = wpick({'INTRO_MADE': 85, 'INTERESTED': 15})
    t = add_touch(c, 'intro', at(d), out, direction='inbound', notes=f'Introduced by {referrer_name}.')
    if out == 'INTERESTED':
        t['responded_at'] = t['touched_at'] + dt.timedelta(hours=rint(2, 30))
        t['follow_up_on'] = bday(d + days(rint(3, 10)))
        t['response_excerpt'] = 'Intro email: happy to find a time to talk.'
        t['confirmed_by'], t['confirmed_at'] = c['owner_id'], t['responded_at']
        start_opportunity(c, t)
        return
    email_sequence(c, bday(d + days(rint(1, 3))), None, subject=f"Introduction via {referrer_name.split()[0]}",
                   dist_first=REFERRAL_FU)


def call_campaign(c: dict, start: dt.date, campaign: str, until: dt.date = LAST) -> None:
    d, attempts = bday(start), 0
    camp_id = CAMPAIGNS[campaign]['id']
    while d <= until and attempts < 3 and not c['do_not_contact']:
        attempts += 1
        r = wpick({'NO_ANSWER': 40, 'VOICEMAIL': 33, 'WRONG_NUMBER': 4, 'CONNECTED': 23})
        out = sample(CALL_CONNECTED, c, d.year) if r == 'CONNECTED' else r
        note = {'NO_ANSWER': 'No answer.', 'VOICEMAIL': 'Left a voicemail with callback number.',
                'WRONG_NUMBER': 'Number is disconnected / wrong business.'}.get(out, 'Spoke with them.')
        t = add_touch(c, 'call', at(d), out, campaign_id=camp_id, notes=note)
        if out in ('NO_ANSWER', 'VOICEMAIL'):
            d = bday(d + days(rint(3, 8)))
            continue
        if out == 'WRONG_NUMBER':
            return
        t['responded_at'] = t['touched_at']
        t['confirmed_by'], t['confirmed_at'] = c['owner_id'], t['touched_at'] + dt.timedelta(minutes=10)
        if out == 'NOT_NOW':
            t['follow_up_on'] = month_start_after(d, rint(1, 3))
        if out == 'INTERESTED':
            t['follow_up_on'] = bday(d + days(rint(2, 9)))
            t['notes'] = 'Picked up; interested. Booked a call.'
            start_opportunity(c, t)
        if out == 'UNSUBSCRIBE':
            c['do_not_contact'], c['dnc_reason'], c['dnc_on'] = True, 'Asked not to be contacted', d
        if out == 'REFERRED_INTERNALLY':
            spawn_colleague(c, t)
        if out == 'WRONG_PERSON':
            t['notes'] = 'They said this person no longer works there.'
        return


# ---------------------------------------------------------------------------
# opportunities: call -> hot -> onboarding -> funded
# ---------------------------------------------------------------------------

LOST_AFTER_CALL = ['Too small for our minimums right now', 'Wanted a bundled bank relationship',
                   'Board not ready to change', 'Looking for active trading, not a fit']
LOST_AFTER_HOT = ['Chose another advisor', 'Board voted to stay with incumbent', 'Fees', 'Timing: revisit next fiscal year']


def call_notes(c: dict, aum: float | None) -> str:
    seg = c['segment_code']
    org = ORG_BY_ID.get(c['organization_id'])
    size = money_text(aum) if aum else 'undisclosed'
    ctx = {
        'ORG_NONPROFIT': f"Reserves/endowment of about {size}, mostly in bank CDs; finance committee meets monthly",
        'ORG_OTHER': f"Assets around {size} with a regional consultant; investment policy last updated years ago",
        'RET_401K': f"{(org or {}).get('employee_count') or 'About 20'} employees; " + pick(
            ['current plan through a payroll provider, fees unclear', 'no plan yet, wants to start one this year',
             'owner unhappy with the current fund lineup']),
        'AFFILIATE': 'Talked about how we work with their clients and a referral process',
        'IND_OCIO': f"Investable assets around {size}; wants a hands-off, institutional approach",
        'IND_ROBO': 'Wants low-cost automated investing; walked through the robo-advisor sign-up',
    }[seg]
    nxt = pick({'ORG_NONPROFIT': ['send fee schedule and a sample investment policy', 'join the finance committee meeting'],
                'ORG_OTHER': ['send proposal', 'set up a call with the investment committee chair'],
                'RET_401K': ['send a plan comparison', 'meet with the owner and HR together'],
                'AFFILIATE': ['send our one-pager for their clients', 'grab lunch next month'],
                'IND_OCIO': ['send proposal and fee schedule', 'meet with both spouses'],
                'IND_ROBO': ['send the sign-up link', 'answer questions on the risk questionnaire']}[seg])
    return f"Intro call ({pick([30, 30, 45, 60])} min). {ctx}. Next: {nxt}."


def start_opportunity(c: dict, conv: dict) -> dict | None:
    """A call was booked on touch `conv`. Simulate what happened next and create the opportunity."""
    seg = c['segment_code']
    party = PARTY[seg]
    org = ORG_BY_ID.get(c['organization_id']) if party == 'organization' else None
    d0 = (conv['responded_at'] or conv['touched_at']).date()
    call_on = conv.get('follow_up_on') or bday(d0 + days(rint(3, 10)))
    conv['follow_up_on'] = call_on
    if org:
        base = org['reported_aum'] or lognormal_money(1.5e6, 0.6, 200e3, 8e6, 10e3)
        cap = {'ORG_NONPROFIT': 8e6, 'ORG_OTHER': 15e6}.get(seg, 5e6)
        expected = base if seg == 'RET_401K' else min(base * R.uniform(0.3, 0.9), cap)
    else:
        expected = (c['prospect_aum'] or 50e3) * (R.uniform(0.6, 1.0) if seg == 'IND_ROBO' else R.uniform(0.4, 0.9))
    expected = round(expected, -3) if expected > 20e3 else round(expected, -2)

    plan = []          # (date, touch_type, outcome, notes, extra)
    stage, hot_on, onb_on, contract_on, funded_on, closed_on, lost_reason = 'call', None, None, None, None, None, None
    first_call = None
    if call_on <= LAST:
        first_call = call_on
        r = R.random()
        if r < 0.20:
            lost_reason = pick(LOST_AFTER_CALL)
            plan.append((call_on, 'meeting', 'NOT_A_FIT', f'Intro call. {lost_reason}.', {}))
            stage, closed_on = 'lost', call_on
        else:
            plan.append((call_on, 'meeting', 'CALL_HELD', call_notes(c, expected), {}))
            if r < 0.40:
                ci = bday(call_on + days(rint(30, 60)))
                if ci <= LAST:
                    fu = month_start_after(ci, rint(1, 3))
                    plan.append((ci, 'check_in', 'NOT_NOW', 'Sent follow-up materials; they want to revisit later.',
                                 {'follow_up_on': fu}))
                    if fu <= LAST:
                        o2 = wpick({'NO_RESPONSE': 60, 'NOT_A_FIT': 40})
                        plan.append((fu, 'check_in', o2, 'Checked back in as promised.', {}))
                        if o2 == 'NOT_A_FIT':
                            stage, closed_on, lost_reason = 'lost', fu, 'Timing: revisit next fiscal year'
            else:
                h = bday(call_on + days(rint(7, 24)))
                if h <= LAST:
                    stage, hot_on = 'hot', h
                    plan.append((h, 'meeting', 'HOT', pick(['Follow-up call with the committee. They want a proposal.',
                                                            'Second call: reviewed proposal and fees.',
                                                            'Walked through the investment policy draft.']), {}))
                    p_onb = {'ORG_NONPROFIT': .45, 'ORG_OTHER': .4, 'RET_401K': .5, 'IND_OCIO': .5, 'IND_ROBO': .6,
                             'AFFILIATE': .2}[seg]
                    wait = {'ORG_NONPROFIT': (20, 75), 'ORG_OTHER': (25, 80), 'RET_401K': (14, 45), 'IND_OCIO': (7, 30),
                            'IND_ROBO': (2, 10), 'AFFILIATE': (20, 60)}[seg]
                    # Jon: onboarding "can take sometimes 6 months because organizations move very slowly"
                    fund_wait = {'ORG_NONPROFIT': (60, 200), 'ORG_OTHER': (70, 200), 'RET_401K': (30, 90),
                                 'IND_OCIO': (14, 60), 'IND_ROBO': (2, 10), 'AFFILIATE': (30, 90)}[seg]
                    x = R.random()
                    if x < p_onb:
                        o_d = bday(h + days(rint(*wait)))
                        if o_d <= LAST:
                            stage, onb_on = 'onboarding', o_d
                            plan.append((o_d, 'meeting', 'READY_TO_ONBOARD',
                                         'They want to move forward. Sent onboarding packet and advisory agreement.', {}))
                            f_d = bday(o_d + days(rint(*fund_wait)))
                            c_d = bday(o_d + days(rint(5, max(6, (f_d - o_d).days - 2))))
                            if c_d <= LAST:
                                contract_on = c_d
                            if f_d <= LAST:
                                stage, funded_on = 'funded', f_d
                            else:
                                nd = bday(o_d + days(rint(20, 40)))
                                while nd <= LAST:
                                    plan.append((nd, 'meeting', 'READY_TO_ONBOARD', pick(
                                        ['Onboarding call: custodian account paperwork.',
                                         'Board vote scheduled; answered follow-up questions.',
                                         'Transfer instructions sent; waiting on their bank.']), {}))
                                    nd = bday(nd + days(rint(20, 40)))
                    elif x < p_onb + 0.25:
                        l_d = bday(h + days(rint(14, 45)))
                        if l_d <= LAST:
                            lost_reason = pick(LOST_AFTER_HOT)
                            stage, closed_on = 'lost', l_d
                            plan.append((l_d, 'check_in', 'NOT_A_FIT', lost_reason + '.', {}))
                    if stage == 'hot':
                        nd = bday(h + days(rint(20, 40)))
                        while nd <= LAST:
                            o3 = wpick({'HOT': 40, 'NO_RESPONSE': 35, 'NOT_NOW': 25})
                            extra = {'follow_up_on': bday(nd + days(rint(30, 60)))} if o3 == 'NOT_NOW' else {}
                            plan.append((nd, 'check_in', o3, 'Checked in on the proposal.', extra))
                            nd = bday(nd + days(rint(25, 45)))

    end = funded_on or closed_on or FAR
    if org:
        for (s, e) in ORG_OPP_SPANS[org['id']]:
            if s <= end and d0 <= e:
                return None          # the organization already has an open opportunity: this lead is not counted twice
        ORG_OPP_SPANS[org['id']].append((d0, end))
    elif any(o['contact_id'] == c['id'] and (o['funded_on'] or o['closed_on'] or FAR) >= d0 for o in OPPS):
        return None

    for (d, tt, out, notes, extra) in plan:
        t = add_touch(c, tt, at(d), out, notes=notes, subject='Quarterly check-in' if tt == 'check_in' else None, **extra)
        if OUTCOMES[out][2] and tt in ('check_in', 'email'):
            t['responded_at'] = t['touched_at'] + dt.timedelta(hours=rint(2, 48))
            if t['responded_at'].date() > LAST:
                t['responded_at'] = at(LAST, 16)
            t['_reply'] = reply_for(out, c, t) or 'Thanks, will get back to you.'
            t['response_excerpt'] = t['_reply'][:140]
        if out != 'NO_RESPONSE':
            t['confirmed_by'], t['confirmed_at'] = c['owner_id'], (t['responded_at'] or t['touched_at']) + dt.timedelta(hours=2)
    conv_channel = TOUCH_CHANNEL.get(conv['touch_type'])
    opp = dict(id=len(OPPS) + 1, contact_id=c['id'], organization_id=org['id'] if org else None, segment_code=seg,
               state=c['state'], stage=stage, source_channel_code=c['source_channel_code'] or conv_channel,
               converting_channel_code=conv_channel, converting_touchpoint_id=conv['id'],
               source_event_id=c['source_event_id'], rfp_id=conv.get('rfp_id'), opened_on=d0,
               first_call_on=first_call or call_on, hot_on=hot_on, onboarding_started_on=onb_on,
               contract_signed_on=contract_on, funded_on=funded_on, closed_on=closed_on or funded_on,
               lost_reason=lost_reason, expected_aum=expected,
               funded_aum=round(expected * R.uniform(0.75, 1.05), -3) if funded_on and expected > 20e3
               else (round(expected * R.uniform(0.8, 1.0), -2) if funded_on else None),
               owner_id=c['owner_id'], notes=None, created_at=at(d0, 17))
    OPPS.append(opp)
    if not c['do_not_contact'] and c['newsletter_status'] == 'not_subscribed':
        c['newsletter_status'], c['newsletter_added_on'] = 'subscribed', d0
        c['newsletter_added_via'] = 'auto: ' + OUTCOMES[conv['outcome_code']][0]
    if funded_on:
        c['follow_up_style'] = 'standard_check_in'
    return opp


# ---------------------------------------------------------------------------
# build the story
# ---------------------------------------------------------------------------

RESERVED_ORG_NAMES = [
    'Great Basin Community Foundation', 'Uinta Health Foundation', 'Snake River Arts Council',
    'High Plains Builders Association', 'Wasatch Regional Library Foundation', 'Bay Area Science Education Fund',
    'Gem State Community Trust', 'Laramie Chamber Music Society', 'Provo River Dental Group',
    'Summit Peak Wealth Partners', 'Beehive State Credit Union Foundation', 'Beehive State Credit Union',
    'Summit Ridge University Foundation', 'Canyonlands State University Foundation',
    'Cache Valley Literacy Center', 'Cache Valey Literacy Center', 'Bear River Youth Soccer', 'Bear River Youth Soccer Club',
    # names used by the import demo (must stay new)
    'Teton Watershed Trust', 'Star Valley Arts Guild', 'Teton Valley Youth Orchestra', 'Sweetwater Food Bank Alliance',
    'Jackson Hole Wildlife Society', 'Snake River Watershed Council', 'Wind River Literacy Project',
    'Absaroka Trails Coalition', 'Platte Valley Senior Services',
]


def build() -> None:
    for n in RESERVED_ORG_NAMES:
        ORG_KEYS.add(org_key(n))
    for d in ('summitpeakwealth.example', 'summitridge.edu.example', 'canyonlandsstate.edu.example',
              'tetonwatershedtrust.example', 'beehivestatecu.example'):
        DOMAINS.add(d)
    # events ---------------------------------------------------------------
    ev_specs = [
        ('Wasatch Nonprofit Leadership Summit 2025', 'conference', 'in_person', False, 'Wasatch Nonprofit Network', '2025-04-17', 'Salt Lake City', 'UT', 1450, 400, 'ORG_NONPROFIT', 1),
        ('Nonprofit Finance Roundtable: Ogden', 'networking', 'in_person', False, 'Northern Utah Nonprofit Circle', '2025-06-11', 'Ogden', 'UT', 120, 35, 'ORG_NONPROFIT', 1),
        ('Endowment Basics for Nonprofit Boards (GAARD webinar)', 'webinar', 'virtual', True, None, '2025-09-18', None, 'UT', 150, 60, 'ORG_NONPROFIT', 1),
        ('Boise Philanthropy Forum 2025', 'conference', 'in_person', False, 'Treasure Valley Giving Council', '2025-10-09', 'Boise', 'ID', 1100, 250, 'ORG_OTHER', 2),
        ('Salt Lake Small Business Mixer', 'networking', 'in_person', False, 'Downtown SLC Business Circle', '2025-11-13', 'Salt Lake City', 'UT', 60, 80, 'RET_401K', 2),
        ('Board Treasurer Workshop: Investment Policy 101', 'workshop', 'in_person', True, None, '2026-02-12', 'Salt Lake City', 'UT', 480, 28, 'ORG_NONPROFIT', 1),
        ('Bay Area Foundation Investment Forum', 'conference', 'virtual', False, 'Pacific Philanthropy Network', '2026-03-19', None, 'CA', 295, 300, 'ORG_OTHER', 1),
        ('Wasatch Nonprofit Leadership Summit 2026', 'conference', 'in_person', False, 'Wasatch Nonprofit Network', '2026-04-16', 'Salt Lake City', 'UT', 1600, 450, 'ORG_NONPROFIT', 1),
        ('Cheyenne Small Business Expo', 'conference', 'in_person', False, 'Cheyenne Business Council', '2026-05-07', 'Cheyenne', 'WY', 950, 300, 'RET_401K', 2),
        ('401(k) Fiduciary Basics for Business Owners (GAARD webinar)', 'webinar', 'virtual', True, None, '2026-06-10', None, 'UT', 200, 45, 'RET_401K', 2),
        ('Gem State Nonprofit Conference', 'conference', 'in_person', False, 'Gem State Nonprofit Association', '2026-07-22', 'Boise', 'ID', 1250, 350, 'ORG_NONPROFIT', 2),
        ('Investing for Young Professionals: Robo-Advisor Launch', 'workshop', 'virtual', True, None, '2026-08-13', None, 'UT', 350, 70, 'IND_ROBO', 2),
        ('Jackson Hole Philanthropy Retreat', 'networking', 'in_person', False, 'Teton Giving Circle', '2026-09-17', 'Jackson', 'WY', 2100, 90, 'ORG_OTHER', 1),
    ]
    for i, (name, et, fmt, ours, host, day, city, st, cost, att, seg, own) in enumerate(ev_specs, 1):
        EVENTS.append(dict(id=i, name=name, event_type=et, format=fmt, hosted_by_us=ours, host_org=host,
                           start_on=dt.date.fromisoformat(day), end_on=None, city=city, state=st, cost_usd=cost,
                           attendees_est=att, target_segment_code=seg, owner_id=own,
                           notes='Cost includes registration, travel and sponsorship.' if not ours else 'GAARD-hosted; cost is ads and venue.',
                           created_at=at(dt.date.fromisoformat(day) - days(30), 12)))
    EV = {e['name']: e for e in EVENTS}

    camp_specs = [
        ('2025 Nonprofit Cold Email: Utah', 'COLD_EMAIL', 'ORG_NONPROFIT', ['UT'], '2025-01-13', '2025-12-19', 1),
        ('2025 Foundations & Institutions Email', 'COLD_EMAIL', 'ORG_OTHER', ['UT', 'ID', 'WY', 'CA'], '2025-03-03', '2025-11-21', 1),
        ('2025 OCIO Individuals Email', 'COLD_EMAIL', 'IND_OCIO', [], '2025-05-05', '2025-12-12', 1),
        ('2026 Q1 Rollover: New Leadership Contacts', 'COLD_EMAIL', 'ORG_NONPROFIT', ['UT'], '2026-01-12', '2026-03-27', 1),
        ('2026 Nonprofit Expansion: Idaho & Wyoming', 'COLD_EMAIL', 'ORG_NONPROFIT', ['ID', 'WY'], '2026-02-02', '2026-07-31', 2),
        ('2026 California Foundations Email', 'COLD_EMAIL', 'ORG_OTHER', ['CA'], '2026-03-02', '2026-08-28', 1),
        ('2026 401(k) Small Business Email', 'COLD_EMAIL', 'RET_401K', ['UT', 'ID', 'WY'], '2026-04-06', '2026-09-30', 2),
        ('2026 Robo-Advisor Launch Email', 'COLD_EMAIL', 'IND_ROBO', [], '2026-06-01', '2026-09-30', 2),
        ('2026 Q3 Cold Calls: Email Non-responders', 'COLD_CALL', None, ['UT', 'ID', 'WY'], '2026-07-13', '2026-09-30', 2),
    ]
    for i, (name, ch, seg, sts, s, e, own) in enumerate(camp_specs, 1):
        CAMPAIGNS[name] = dict(id=i, name=name, channel_code=ch, segment_code=seg, target_states=sts,
                               start_on=dt.date.fromisoformat(s), end_on=dt.date.fromisoformat(e), owner_id=own,
                               description=None, created_at=at(dt.date.fromisoformat(s) - days(7), 12))
    C25, CFND, COCIO, CROLL, CIDWY, CCA, C401, CROBO, CCALL = [x[0] for x in camp_specs]

    # affiliates first (they refer people later) -----------------------------
    affiliates = []
    for _ in range(15):
        st = wpick({'UT': 75, 'ID': 15, 'WY': 10})
        d = rand_date(dt.date(2025, 1, 6), dt.date(2025, 8, 29))
        org = make_org('AFFILIATE', st, d, 'Founder network', 'Affiliates tab')
        for k in range(1 if chance(0.7) else 2):
            c = make_contact('AFFILIATE', st, d, wpick({'REFERRAL': 60, 'COLD_EMAIL': 25, 'EVENT': 15}),
                             'Founder network' if k == 0 else 'Colleague of partner', 'Affiliates tab', org=org)
            affiliates.append(c)
            if c['source_channel_code'] == 'REFERRAL':
                referral_journey(c, None, 'the founder')
            else:
                email_sequence(c, bday(d + days(rint(0, 7))), None, dist_first=REFERRAL_FU)

    # 2025 nonprofit cold email: Utah ------------------------------------------
    np25 = []
    for _ in range(70):
        d = bday(rand_date(dt.date(2025, 1, 13), dt.date(2025, 10, 31)))
        org = make_org('ORG_NONPROFIT', 'UT', d, pick(['Candid / GuideStar search', 'Utah nonprofit directory',
                                                       'Board member research', 'Form 990 research']), 'Outreach Master (2025)')
        c = make_contact('ORG_NONPROFIT', 'UT', d, 'COLD_EMAIL', org['source_detail'], 'Outreach Master (2025)', org=org, dm=True)
        np25.append((org, c))
        email_sequence(c, d + days(rint(0, 8)), C25, until=dt.date(2025, 12, 19))

    # 2025 foundations & institutions ------------------------------------------
    for i in range(24):
        st = wpick({'UT': 55, 'ID': 15, 'WY': 15, 'CA': 15})
        d = bday(rand_date(dt.date(2025, 3, 3), dt.date(2025, 10, 31)))
        uni = UNIVERSITIES[0] if i == 3 else (UNIVERSITIES[1] if i == 11 else None)
        if uni:
            name = f"{uni[0]} Foundation"
            ORG_KEYS.add(org_key(name))
            org = make_org('ORG_OTHER', 'UT' if i == 3 else 'ID', d, 'University giving office', 'Outreach Master (2025)',
                           name=name, domain=uni[1], is_university_affiliated=True)
            st = org['state']
        else:
            org = make_org('ORG_OTHER', st, d, pick(['Foundation directory', 'Form 990 research', 'Consultant list']),
                           'Outreach Master (2025)')
        c = make_contact('ORG_OTHER', st, d, 'COLD_EMAIL', org['source_detail'], 'Outreach Master (2025)', org=org, dm=True)
        email_sequence(c, d + days(rint(0, 8)), CFND, max_attempts=6)

    # 2025 events ---------------------------------------------------------------
    def event_batch(ev: dict, n: int, seg: str, states: dict, existing_pool: list, existing_share: float,
                    tab: str = 'Events worksheet') -> list:
        out = []
        for _ in range(n):
            st = wpick(states)
            if existing_pool and chance(existing_share):
                org = pick(existing_pool)[0]
                st = org['state']
                existing_pool.remove(next(x for x in existing_pool if x[0] is org))
            elif PARTY[seg] == 'organization':
                org = make_org(seg, st, ev['start_on'], ev['name'], tab)
            else:
                org = None
            uni = pick(UNIVERSITIES) if (PARTY[seg] == 'individual' and chance(0.2)) else None
            c = make_contact(seg, st, ev['start_on'], 'EVENT', ev['name'], tab, org=org, event_id=ev['id'], uni=uni)
            out.append(c)
            event_journey(c, ev)
        return out

    pool25 = [x for x in np25]
    event_batch(EV['Wasatch Nonprofit Leadership Summit 2025'], 22, 'ORG_NONPROFIT', {'UT': 1}, pool25, 0.35)
    event_batch(EV['Nonprofit Finance Roundtable: Ogden'], 8, 'ORG_NONPROFIT', {'UT': 1}, pool25, 0.25)
    event_batch(EV['Endowment Basics for Nonprofit Boards (GAARD webinar)'], 14, 'ORG_NONPROFIT',
                {'UT': 70, 'ID': 15, 'WY': 10, 'CA': 5}, pool25, 0.2)
    boise = event_batch(EV['Boise Philanthropy Forum 2025'], 9, 'ORG_OTHER', {'ID': 80, 'UT': 20}, [], 0)
    boise += event_batch(EV['Boise Philanthropy Forum 2025'], 3, 'IND_OCIO', {'ID': 100}, [], 0)
    event_batch(EV['Salt Lake Small Business Mixer'], 9, 'RET_401K', {'UT': 1}, [], 0)

    # competitor met at the Boise forum: on the do-not-contact list by rule
    comp_org = make_org('ORG_OTHER', 'ID', EV['Boise Philanthropy Forum 2025']['start_on'], 'Boise Philanthropy Forum 2025',
                        'Events worksheet', name='Summit Peak Wealth Partners', domain='summitpeakwealth.example',
                        do_not_contact=True, dnc_reason='Competitor firm: do not solicit', org_type='Investment firm')
    comp = make_contact('ORG_OTHER', 'ID', EV['Boise Philanthropy Forum 2025']['start_on'], 'EVENT',
                        'Boise Philanthropy Forum 2025', 'Events worksheet', org=comp_org, title='Managing Director', dm=True,
                        event_id=EV['Boise Philanthropy Forum 2025']['id'])
    comp.update(do_not_contact=True, dnc_reason='Competitor firm: do not solicit', dnc_on=comp['sourced_on'])
    add_touch(comp, 'event', at(comp['sourced_on'], 15), 'MET_AT_EVENT', event_id=comp['source_event_id'],
              direction='in_person', notes='Competitor; chatted at the reception.')

    # 2025 OCIO individuals: cold email and referrals ----------------------------
    ocio = []
    for i in range(20):
        st = wpick({'UT': 60, 'ID': 10, 'WY': 10, 'CA': 20})
        d = bday(rand_date(dt.date(2025, 5, 5), dt.date(2025, 11, 14)))
        uni = UNIVERSITIES[i % 2] if i % 4 == 0 else None
        c = make_contact('IND_OCIO', st, d, 'COLD_EMAIL', pick(['LinkedIn search', 'Alumni directory', 'Professional association list']),
                         'Individuals & Small Biz tab', uni=uni)
        ocio.append(c)
        email_sequence(c, d + days(rint(0, 6)), COCIO, max_attempts=5)
    for i in range(18):
        st = wpick({'UT': 70, 'ID': 10, 'CA': 20})
        d = bday(rand_date(dt.date(2025, 2, 3), dt.date(2026, 9, 11)))
        refs = [a for a in affiliates if a['sourced_on'] < d] + [x for x in ocio if x['sourced_on'] < d]
        ref = pick(refs) if refs and chance(0.8) else None
        ref_name = f"{ref['first_name']} {ref['last_name']}" if ref else pick(['a family friend', 'a current client'])
        uni = UNIVERSITIES[0] if i in (2, 9, 15) else None
        c = make_contact('IND_OCIO', st, d, 'REFERRAL', f'Referred by {ref_name}',
                         'Individuals & Small Biz tab' if d < dt.date(2026, 9, 1) else None, uni=uni,
                         referred_by=ref['id'] if ref else None)
        ocio.append(c)
        referral_journey(c, ref, ref_name)

    # the founder's personal friend: on the do-not-contact list by rule (founder reaches out himself)
    fr = make_contact('IND_OCIO', 'UT', dt.date(2025, 6, 2), 'REFERRAL', 'Founder network', 'Individuals & Small Biz tab',
                      first='Robert', last='Hollis', email='r.hollis@mail.example')
    fr.update(do_not_contact=True, dnc_reason='Personal friend of the founder: he reaches out himself', dnc_on=fr['sourced_on'])

    # a partner bank's foundation: on the do-not-contact list by an organization-name rule
    bank = make_org('ORG_OTHER', 'UT', dt.date(2025, 7, 14), 'Form 990 research', 'Outreach Master (2025)',
                    name='Beehive State Credit Union Foundation', do_not_contact=True,
                    dnc_reason='Banking partner: founder handles the relationship')
    bc = make_contact('ORG_OTHER', 'UT', dt.date(2025, 7, 14), 'COLD_EMAIL', 'Form 990 research', 'Outreach Master (2025)',
                      org=bank, dm=True)
    bc.update(do_not_contact=True, dnc_reason='Organization is on the do-not-contact list: Banking partner: founder handles the relationship',
              dnc_on=bc['sourced_on'])

    # 2026 Q1 rollover: new leadership contact at 2025 orgs that never answered ------------
    silent = []
    for org, c in np25:
        ts = [t for t in TOUCHES if t['contact_id'] == c['id']]
        answered = any(OUTCOMES[t['outcome_code']][2] for t in ts if t['outcome_code'])
        org_has_opp = bool(ORG_OPP_SPANS[org['id']])
        if not answered and not org_has_opp and not c['do_not_contact']:
            silent.append((org, c))
    R.shuffle(silent)
    rolled = silent[:max(1, int(len(silent) * 0.8))]
    for org, old in rolled:
        d = bday(rand_date(dt.date(2026, 1, 12), dt.date(2026, 3, 20)))
        title = pick(['Board Treasurer', 'Board Chair', 'Executive Director', 'Chief Financial Officer'])
        c = make_contact('ORG_NONPROFIT', 'UT', d, 'COLD_EMAIL', f"Rollover: {old['first_name']} {old['last_name']} never replied",
                         'Outreach Master (2026)', org=org, title=title, dm=True)
        email_sequence(c, d, CROLL, until=dt.date(2026, 7, 10))
        old['_rolled_over_on'] = d

    # 2026 Idaho & Wyoming nonprofit expansion ----------------------------------------------
    np26 = []
    for _ in range(36):
        st = wpick({'ID': 62, 'WY': 38})
        d = bday(rand_date(dt.date(2026, 2, 2), dt.date(2026, 7, 24)))
        org = make_org('ORG_NONPROFIT', st, d, pick(['Candid / GuideStar search', 'State nonprofit directory', 'Form 990 research']),
                       'Cold Outreach 2026')
        c = make_contact('ORG_NONPROFIT', st, d, 'COLD_EMAIL', org['source_detail'], 'Cold Outreach 2026', org=org, dm=True)
        np26.append(c)
        # early-2026 names stop emailing in July (they go to the Q3 cold-call campaign instead)
        email_sequence(c, d + days(rint(0, 6)), CIDWY, until=dt.date(2026, 7, 10) if d < dt.date(2026, 6, 20) else LAST)

    # 2026 California foundations --------------------------------------------------------------
    for _ in range(12):
        d = bday(rand_date(dt.date(2026, 3, 2), dt.date(2026, 8, 21)))
        org = make_org('ORG_OTHER', 'CA', d, pick(['Foundation directory', 'Consultant list']), 'Cold Outreach 2026')
        c = make_contact('ORG_OTHER', 'CA', d, 'COLD_EMAIL', org['source_detail'], 'Cold Outreach 2026', org=org, dm=True)
        email_sequence(c, d + days(rint(0, 6)), CCA)

    # 2026 events ------------------------------------------------------------------------------------
    rolled_orgs = [(o, c) for (o, c) in np25 if not ORG_OPP_SPANS[o['id']]]
    event_batch(EV['Board Treasurer Workshop: Investment Policy 101'], 12, 'ORG_NONPROFIT', {'UT': 1}, rolled_orgs, 0.3)
    event_batch(EV['Bay Area Foundation Investment Forum'], 7, 'ORG_OTHER', {'CA': 1}, [], 0)
    # Jon's example: met a new person at the summit from an organization already contacted in 2025
    event_batch(EV['Wasatch Nonprofit Leadership Summit 2026'], 24, 'ORG_NONPROFIT', {'UT': 1}, rolled_orgs, 0.4)
    event_batch(EV['Cheyenne Small Business Expo'], 11, 'RET_401K', {'WY': 1}, [], 0)
    event_batch(EV['401(k) Fiduciary Basics for Business Owners (GAARD webinar)'], 15, 'RET_401K',
                {'UT': 60, 'ID': 25, 'WY': 15}, [], 0)
    event_batch(EV['Gem State Nonprofit Conference'], 14, 'ORG_NONPROFIT', {'ID': 1}, [], 0)
    event_batch(EV['Investing for Young Professionals: Robo-Advisor Launch'], 20, 'IND_ROBO',
                {'UT': 45, 'ID': 15, 'WY': 10, 'CA': 20, 'CO': 5, 'NV': 5}, [], 0)
    event_batch(EV['Jackson Hole Philanthropy Retreat'], 6, 'ORG_OTHER', {'WY': 70, 'UT': 30}, [], 0)
    event_batch(EV['Jackson Hole Philanthropy Retreat'], 4, 'IND_OCIO', {'WY': 60, 'UT': 40}, [], 0)

    # 2026 401(k) small business email + direct cold calls ------------------------------------------
    k401 = []
    for _ in range(45):
        st = wpick({'UT': 55, 'ID': 28, 'WY': 17})
        d = bday(rand_date(dt.date(2026, 4, 6), dt.date(2026, 9, 11)))
        org = make_org('RET_401K', st, d, pick(['Chamber of commerce directory', 'Form 5500 search', 'LinkedIn search']),
                       'Cold Outreach 2026')
        c = make_contact('RET_401K', st, d, 'COLD_EMAIL', org['source_detail'], 'Cold Outreach 2026', org=org, dm=True)
        k401.append(c)
        email_sequence(c, d + days(rint(0, 6)), C401, until=dt.date(2026, 7, 10) if d < dt.date(2026, 6, 20) else LAST)
    for _ in range(10):
        st = wpick({'UT': 60, 'ID': 25, 'WY': 15})
        d = bday(rand_date(dt.date(2026, 7, 13), dt.date(2026, 9, 18)))
        org = make_org('RET_401K', st, d, 'Chamber of commerce directory', 'Cold call sheet (offline)')
        c = make_contact('RET_401K', st, d, 'COLD_CALL', 'Chamber of commerce directory', 'Cold call sheet (offline)',
                         org=org, dm=True)
        if not c['phone']:
            c['phone'] = phone(st)
        call_campaign(c, d, CCALL)

    # 2026 robo-advisor launch email ----------------------------------------------------------------
    for i in range(30):
        st = wpick({'UT': 45, 'ID': 15, 'WY': 10, 'CA': 20, 'CO': 4, 'NV': 3, 'AZ': 3})
        d = bday(rand_date(dt.date(2026, 6, 1), dt.date(2026, 9, 14)))
        uni = UNIVERSITIES[i % 2] if i % 6 == 0 else None
        c = make_contact('IND_ROBO', st, d, 'COLD_EMAIL', pick(['Alumni network list', 'LinkedIn search', 'Workshop waitlist']),
                         'Individuals & Small Biz tab' if d < dt.date(2026, 9, 1) else None, uni=uni)
        email_sequence(c, d + days(rint(0, 4)), CROBO)
    for i in range(10):
        st = wpick({'UT': 60, 'CA': 25, 'ID': 15})
        d = bday(rand_date(dt.date(2026, 5, 4), dt.date(2026, 9, 18)))
        clients = [o for o in OPPS if o['stage'] == 'funded' and o['funded_on'] and o['funded_on'] < d
                   and CT_BY_ID[o['contact_id']]['segment_code'].startswith('IND')]
        ref = CT_BY_ID[pick(clients)['contact_id']] if clients and chance(0.7) else None
        ref_name = f"{ref['first_name']} {ref['last_name']}" if ref else 'a family friend'
        c = make_contact('IND_ROBO', st, d, 'REFERRAL', f'Referred by {ref_name}',
                         'Individuals & Small Biz tab' if d < dt.date(2026, 9, 1) else None,
                         referred_by=ref['id'] if ref else None)
        referral_journey(c, ref, ref_name)

    # referrals into organizations (from affiliates) ---------------------------------------------
    for seg, n in (('ORG_NONPROFIT', 8), ('RET_401K', 6), ('ORG_OTHER', 3)):
        for _ in range(n):
            st = wpick({'UT': 70, 'ID': 20, 'WY': 10})
            d = bday(rand_date(dt.date(2025, 3, 3), dt.date(2026, 9, 11)))
            ref = pick([a for a in affiliates if a['sourced_on'] < d] or affiliates)
            ref_name = f"{ref['first_name']} {ref['last_name']}"
            tab = 'Outreach Master (2025)' if d.year == 2025 else 'Cold Outreach 2026'
            org = make_org(seg, st, d, f'Referral from {ref_name}', tab)
            c = make_contact(seg, st, d, 'REFERRAL', f'Referred by {ref_name}', tab, org=org, dm=True, referred_by=ref['id'])
            referral_journey(c, ref, ref_name)

    # 2026 Q3 cold call campaign: people who never answered the 2026 emails --------------------------
    cands = []
    for c in list(CONTACTS):
        ts = [t for t in TOUCHES if t['contact_id'] == c['id']]
        if not ts or c['do_not_contact'] or c['source_channel_code'] != 'COLD_EMAIL':
            continue
        if c['segment_code'] not in ('ORG_NONPROFIT', 'RET_401K') or c['sourced_on'] < dt.date(2026, 1, 1):
            continue
        if any(OUTCOMES[t['outcome_code']][2] for t in ts if t['outcome_code']):
            continue
        if max(t['touched_at'].date() for t in ts) >= dt.date(2026, 7, 10) or c['email_status'] == 'bounced' and chance(0.5):
            continue
        cands.append(c)
    R.shuffle(cands)
    for c in cands[:58]:
        if not c['phone']:
            c['phone'] = phone(c['state'])
        call_campaign(c, bday(rand_date(dt.date(2026, 7, 13), dt.date(2026, 9, 11))), CCALL)

    # RFPs ------------------------------------------------------------------------------------------
    rfp_specs = [
        # org name, segment, state, title, mandate, via, est aum, released, due, submitted, status, decision
        ('Great Basin Community Foundation', 'ORG_OTHER', 'UT', 'Investment Management Services RFP', 'OCIO', 'RFP database',
         18e6, '2025-02-10', '2025-03-21', '2025-03-19', 'won', '2025-06-12'),
        ('Uinta Health Foundation', 'ORG_OTHER', 'UT', 'OCIO Services RFP', 'OCIO', 'Consultant invitation',
         25e6, '2025-07-07', '2025-08-15', '2025-08-14', 'lost', '2025-10-20'),
        ('Snake River Arts Council', 'ORG_NONPROFIT', 'ID', 'Endowment Investment Consultant RFP', 'Investment consulting',
         'Direct invitation', 6e6, '2025-10-06', '2025-11-14', '2025-11-12', 'won', '2026-02-09'),
        ('High Plains Builders Association', 'RET_401K', 'WY', '401(k) Plan Advisor Services RFP', '401(k) plan advisor',
         'RFP database', 4.2e6, '2026-02-16', '2026-03-20', '2026-03-18', 'lost', '2026-05-08'),
        ('Wasatch Regional Library Foundation', 'ORG_OTHER', 'UT', 'Investment Advisory Services for Reserves', 'Investment advisory',
         'RFP database', 9e6, '2026-04-20', '2026-05-29', '2026-05-27', 'finalist', None),
        ('Bay Area Science Education Fund', 'ORG_OTHER', 'CA', 'OCIO Search 2026', 'OCIO', 'Consultant invitation',
         42e6, '2026-09-08', '2026-10-16', None, 'intent_to_bid', None),
        ('Gem State Community Trust', 'ORG_OTHER', 'ID', 'Investment Manager Search', 'Investment management', 'RFP database',
         15e6, '2026-09-21', '2026-10-30', None, 'identified', None),
        ('Laramie Chamber Music Society', 'ORG_NONPROFIT', 'WY', 'Investment Consulting RFP', 'Investment consulting',
         'RFP database', 3e6, '2025-08-11', '2025-09-12', None, 'declined', '2025-08-20'),
        ('Provo River Dental Group', 'RET_401K', 'UT', 'Retirement Plan Consultant RFP', '401(k) plan advisor', 'Direct invitation',
         2.1e6, '2026-07-27', '2026-08-28', '2026-08-27', 'submitted', None),
    ]
    for i, (oname, seg, st, title, mandate, via, aum, rel, due, sub, status, dec) in enumerate(rfp_specs, 1):
        rel_d = dt.date.fromisoformat(rel)
        ORG_KEYS.add(org_key(oname))
        org = make_org(seg, st, rel_d, f'RFP: {title}', 'RFP workbook', name=oname)
        org['reported_aum'] = aum * R.uniform(1.1, 1.6) if seg != 'RET_401K' else aum
        c = make_contact(seg, st, rel_d, 'RFP', f'RFP: {title}', 'RFP workbook', org=org,
                         title=pick(['Chief Financial Officer', 'Executive Director', 'Treasurer']), dm=True)
        due_d = dt.date.fromisoformat(due)
        sub_d = dt.date.fromisoformat(sub) if sub else None
        dec_d = dt.date.fromisoformat(dec) if dec else None
        rfp = dict(id=i, organization_id=org['id'], contact_id=c['id'], title=title, mandate_type=mandate, found_via=via,
                   est_mandate_aum=aum, released_on=rel_d, questions_due_on=rel_d + days(14), due_on=due_d,
                   submitted_on=sub_d, status=status, decision_on=dec_d, owner_id=owner_for(seg, st),
                   notes='Declined: mandate below our minimum and required on-site staff.' if status == 'declined' else None,
                   created_at=at(rel_d, 12))
        RFPS.append(rfp)
        if sub_d:
            add_touch(c, 'rfp', at(sub_d, 16), 'RFP_SUBMITTED', rfp_id=i, notes=f'Submitted response: {title}.')
        if status in ('won', 'lost', 'finalist'):
            fin = bday(sub_d + days(rint(20, 40)))
            if status == 'lost' and chance(0.5):
                t = add_touch(c, 'rfp', at(dec_d, 11), 'RFP_LOST', rfp_id=i, notes='Not selected.')
                t['responded_at'] = t['touched_at']
                continue
            t = add_touch(c, 'rfp', at(fin, 11), 'RFP_FINALIST', rfp_id=i, notes='Named a finalist; presentation scheduled.',
                          follow_up_on=bday(fin + days(rint(7, 14))))
            t['responded_at'] = t['touched_at']
            opp = dict(id=len(OPPS) + 1, contact_id=c['id'], organization_id=org['id'], segment_code=seg, state=st,
                       stage='call', source_channel_code='RFP', converting_channel_code='RFP', converting_touchpoint_id=t['id'],
                       source_event_id=None, rfp_id=i, opened_on=fin, first_call_on=t['follow_up_on'], hot_on=None,
                       onboarding_started_on=None, contract_signed_on=None, funded_on=None, closed_on=None,
                       lost_reason=None, expected_aum=aum, funded_aum=None, owner_id=owner_for(seg, st), notes=None,
                       created_at=at(fin, 17))
            OPPS.append(opp)
            ORG_OPP_SPANS[org['id']].append((fin, FAR))
            c['newsletter_status'], c['newsletter_added_on'], c['newsletter_added_via'] = 'subscribed', fin, 'auto: RFP finalist, presentation'
            if t['follow_up_on'] <= LAST:
                add_touch(c, 'meeting', at(t['follow_up_on'], 10), 'CALL_HELD', rfp_id=i,
                          notes='Finalist presentation to the investment committee.')
            if status == 'won':
                t2 = add_touch(c, 'rfp', at(dec_d, 11), 'RFP_WON', rfp_id=i, notes='Selected. Starting onboarding.')
                t2['responded_at'] = t2['touched_at']
                opp.update(stage='onboarding', hot_on=bday(fin + days(8)), onboarding_started_on=dec_d,
                           contract_signed_on=bday(dec_d + days(rint(10, 25))))
                f_d = bday(dec_d + days(rint(60, 120)))
                if f_d <= LAST:
                    opp.update(stage='funded', funded_on=f_d, closed_on=f_d, funded_aum=round(aum * R.uniform(0.85, 1.0), -3))
                    ORG_OPP_SPANS[org['id']][-1] = (fin, f_d)
                    c['follow_up_style'] = 'standard_check_in'
            elif status == 'lost':
                t2 = add_touch(c, 'rfp', at(dec_d, 11), 'RFP_LOST', rfp_id=i, notes='Not selected after finalist round.')
                t2['responded_at'] = t2['touched_at']
                opp.update(stage='lost', closed_on=dec_d, lost_reason='RFP lost')
                ORG_OPP_SPANS[org['id']][-1] = (fin, dec_d)
            else:
                opp.update(stage='hot', hot_on=t['follow_up_on'])

    # planted look-alikes for the duplicate review list ----------------------------------------------
    plant_duplicates()


def plant_duplicates() -> None:
    """Records that slipped into the old sheets twice. v_possible_duplicates should surface all of them."""
    # 1. same person at the same organization under two emails (2025 email list + 2026 summit list)
    base = next(c for c in CONTACTS if c['segment_code'] == 'ORG_NONPROFIT' and c['organization_id']
                and c['source_channel_code'] == 'COLD_EMAIL' and not c['do_not_contact']
                and not ORG_OPP_SPANS[c['organization_id']])
    org = ORG_BY_ID[base['organization_id']]
    ev = next(e for e in EVENTS if e['name'] == 'Wasatch Nonprofit Leadership Summit 2026')
    dup = make_contact('ORG_NONPROFIT', org['state'], ev['start_on'], 'EVENT', ev['name'], 'Events worksheet', org=org,
                       title=base['title'], dm=True, first=base['first_name'], last=base['last_name'],
                       email=unique_email(email_local(base['first_name'], base['last_name'], 'flast'), org['domain']),
                       event_id=ev['id'])
    add_touch(dup, 'event', at(ev['start_on'], 14), 'MET_AT_EVENT', event_id=ev['id'], direction='in_person',
              notes='Met at the summit.')
    # 2. similar name at the same 401(k) business
    biz = next(o for o in ORGS if o['segment_code'] == 'RET_401K' and not ORG_OPP_SPANS[o['id']])
    make_contact('RET_401K', biz['state'], dt.date(2026, 5, 11), 'COLD_EMAIL', 'Chamber of commerce directory',
                 'Cold Outreach 2026', org=biz, title='Owner', dm=True, first='Jonathan', last='Petersen')
    make_contact('RET_401K', biz['state'], dt.date(2026, 6, 15), 'EVENT', 'Cheyenne Small Business Expo',
                 'Events worksheet', org=biz, title='Owner', dm=True, first='Jon', last='Petersen')
    # 3. the same individual twice under two personal emails
    make_contact('IND_OCIO', 'UT', dt.date(2025, 8, 4), 'COLD_EMAIL', 'Alumni directory', 'Individuals & Small Biz tab',
                 first='Daniel', last='Whitaker', title='Physician')
    make_contact('IND_OCIO', 'UT', dt.date(2026, 2, 12), 'EVENT', 'Board Treasurer Workshop: Investment Policy 101',
                 'Events worksheet', first='Dan', last='Whitaker', title='Physician')
    # 4. one organization entered twice with a spelling difference
    lit = make_org('ORG_NONPROFIT', 'UT', dt.date(2025, 5, 19), 'Utah nonprofit directory', 'Outreach Master (2025)',
                   name='Cache Valley Literacy Center')
    make_contact('ORG_NONPROFIT', 'UT', dt.date(2025, 5, 19), 'COLD_EMAIL', 'Utah nonprofit directory',
                 'Outreach Master (2025)', org=lit, dm=True)
    lit2 = make_org('ORG_NONPROFIT', 'UT', dt.date(2026, 4, 16), 'Wasatch Nonprofit Leadership Summit 2026',
                    'Events worksheet', name='Cache Valey Literacy Center')
    make_contact('ORG_NONPROFIT', 'UT', dt.date(2026, 4, 16), 'EVENT', 'Wasatch Nonprofit Leadership Summit 2026',
                 'Events worksheet', org=lit2, dm=False)
    # 5. two organizations sharing one website
    soc = make_org('ORG_NONPROFIT', 'UT', dt.date(2025, 9, 8), 'Utah nonprofit directory', 'Outreach Master (2025)',
                   name='Bear River Youth Soccer')
    make_org('ORG_NONPROFIT', 'UT', dt.date(2026, 3, 2), 'Referral', 'Cold Outreach 2026',
             name='Bear River Youth Soccer Club', domain=soc['domain'])


# ---------------------------------------------------------------------------
# replies still waiting for a person to confirm (the AI review queue)
# ---------------------------------------------------------------------------

def plant_review_queue() -> None:
    latest = {}
    for t in TOUCHES:
        if t['contact_id'] not in latest or t['touched_at'] > latest[t['contact_id']]['touched_at']:
            latest[t['contact_id']] = t
    cands = [t for t in latest.values() if t['touch_type'] == 'email' and t['outcome_code'] == 'NO_RESPONSE'
             and dt.date(2026, 9, 8) <= t['touched_at'].date() <= dt.date(2026, 9, 23)
             and not CT_BY_ID[t['contact_id']]['do_not_contact']]
    R.shuffle(cands)
    reasons = {
        'HAS_ADVISOR': 'Reply says they already work with an advisor and are happy with it.',
        'NOT_NOW': 'Reply asks us to reach out again later and names a month.',
        'INTERESTED': 'Reply asks for a call and proposes a time.',
        'NOT_INTERESTED': 'Short decline ("no thank you").',
        'OUT_OF_OFFICE': 'Automatic out-of-office reply with a return date.',
        'REFERRED_INTERNALLY': 'Reply forwards us to a colleague.',
    }
    for t in cands[:12]:
        c = CT_BY_ID[t['contact_id']]
        sug = wpick({'HAS_ADVISOR': 25, 'NOT_NOW': 25, 'INTERESTED': 20, 'NOT_INTERESTED': 15, 'OUT_OF_OFFICE': 10,
                     'REFERRED_INTERNALLY': 5})
        t['responded_at'] = min(t['touched_at'] + dt.timedelta(hours=rint(4, 60)), dt.datetime(2026, 9, 25, 16, 40))
        if sug == 'NOT_NOW':
            t['follow_up_on'] = month_start_after(t['responded_at'].date(), rint(1, 3))
        if sug == 'INTERESTED':
            t['follow_up_on'] = bday(dt.date(2026, 9, 29) + days(rint(0, 6)))
        if sug == 'OUT_OF_OFFICE':
            t['responded_at'] = t['touched_at'] + dt.timedelta(minutes=2)
            t['ooo_return_on'] = bday(t['touched_at'].date() + days(rint(8, 16)))
        text = reply_for(sug, c, t)
        t.update(outcome_code=sug, outcome_status='needs_review', ai_suggested_outcome=sug,
                 ai_confidence=round(R.uniform(0.62, 0.97), 3), ai_reason=reasons[sug], response_excerpt=text[:140],
                 _reply=text, _pending=True)


# ---------------------------------------------------------------------------
# reminders: replay the outcome rules over each contact's history
# ---------------------------------------------------------------------------

def build_reminders() -> list[dict]:
    rem: list[dict] = []
    by_contact = defaultdict(list)
    for t in TOUCHES:
        by_contact[t['contact_id']].append(t)
    for cid, ts in by_contact.items():
        c = CT_BY_ID[cid]
        ts.sort(key=lambda t: (t['touched_at'], t['id']))
        open_ids: list[int] = []
        for i, t in enumerate(ts):
            nxt = ts[i + 1] if i + 1 < len(ts) else None
            code = t['outcome_code']
            if t.get('_pending'):
                code = 'NO_RESPONSE'          # the reply is not confirmed yet, so the rules ran for "no response"
            if not code:
                continue
            o = OUTCOMES[code]
            if o[7] or (c['do_not_contact'] and c['dnc_on'] and c['dnc_on'] <= t['touched_at'].date()):
                for r in rem:
                    if r['id'] in open_ids:
                        r.update(status='dismissed', completed_at=t['responded_at'] or t['touched_at'])
                open_ids = []
                continue
            # this touch is the follow-up: earlier cadence reminders are done
            for r in rem:
                if r['id'] in open_ids and r['reminder_type'] in CADENCE_TYPES:
                    team_did_it = t['touch_type'] in ('email', 'call', 'check_in', 'meeting')
                    r.update(status='done' if team_did_it else 'superseded', completed_at=t['touched_at'],
                             completed_by=c['owner_id'] if team_did_it else None)
            open_ids = [x for x in open_ids if rem[x - 1]['status'] == 'open']
            if o[4] is None:
                continue
            due = t['follow_up_on'] if t['follow_up_on'] and not t.get('_pending') else None
            if due is None and code == 'OUT_OF_OFFICE' and t['ooo_return_on']:
                due = t['ooo_return_on'] + days(1)
            if due is None and code in ('NO_ANSWER', 'VOICEMAIL'):
                streak = 0
                for prev in reversed(ts[:i + 1]):          # unanswered dials in a row, up to this one
                    if prev['touch_type'] == 'call' and prev['outcome_code'] in ('NO_ANSWER', 'VOICEMAIL'):
                        streak += 1
                    elif prev['outcome_code'] not in ('NO_ANSWER', 'VOICEMAIL'):
                        break
                if streak >= 3:
                    due = t['touched_at'].date() + days(90)
            if due is None:
                due = t['touched_at'].date() + days(o[3])
            org = ORG_BY_ID.get(c['organization_id'])
            label = f"{c['first_name']} {c['last_name']}" + (f" ({org['name']})" if org else '')
            r = dict(id=len(rem) + 1, reminder_type=o[4], contact_id=cid, organization_id=c['organization_id'],
                     opportunity_id=None, rfp_id=None, touchpoint_id=t['id'], due_on=due,
                     title=f"{REMINDER_LABELS[o[4]]}: {label}",
                     details=f"Last outcome: {o[0]} ({TOUCH_NAMES[t['touch_type']]}, {t['touched_at']:%b %d, %Y})"
                             + (f"\n{t['notes']}" if t['notes'] else ''),
                     follow_up_style=c['follow_up_style'], assigned_to=c['owner_id'], status='open', snoozed_until=None,
                     created_by='system', completed_by=None, completed_at=None,
                     created_at=(t['touched_at'] if not t['responded_at'] or t.get('_pending') else t['responded_at'])
                                + dt.timedelta(seconds=5))
            rem.append(r)
            open_ids.append(r['id'])
            if nxt is None:
                continue
            # non-cadence reminders (fix email, find new contact) are done once someone acts on them
            if o[4] in ('fix_contact_info', 'find_new_contact') and nxt:
                r.update(status='done', completed_at=nxt['touched_at'], completed_by=c['owner_id'])
                open_ids.remove(r['id'])

    # rollover: the old contact's follow-up was dismissed when the new leadership contact was added
    for r in rem:
        c = CT_BY_ID[r['contact_id']]
        if r['status'] == 'open' and c.get('_rolled_over_on') and r['due_on'] <= c['_rolled_over_on'] + days(120):
            r.update(status='dismissed', completed_at=at(c['_rolled_over_on'], 17))
    # funded clients: onboarding reminders were done on the funding date
    funded = {o['contact_id']: o for o in OPPS if o['stage'] == 'funded'}
    for r in rem:
        o = funded.get(r['contact_id'])
        if o and r['status'] == 'open':
            r.update(status='done', completed_at=at(o['funded_on'], 16), completed_by=CT_BY_ID[r['contact_id']]['owner_id'])
    # old items nobody acted on were cleared out after ~6 weeks
    for r in rem:
        if r['status'] == 'open' and r['due_on'] < TODAY - days(30):
            r.update(status='dismissed', completed_at=at(r['due_on'] + days(30), 17))
    # quarterly check-in for every funded client (the standardized "check-in" bucket)
    for o in OPPS:
        if o['stage'] != 'funded':
            continue
        c = CT_BY_ID[o['contact_id']]
        org = ORG_BY_ID.get(c['organization_id'])
        rem.append(dict(id=len(rem) + 1, reminder_type='check_in', contact_id=c['id'], organization_id=c['organization_id'],
                        opportunity_id=o['id'], rfp_id=None, touchpoint_id=None, due_on=dt.date(2026, 10, 1),
                        title=f"Quarterly check-in: {c['first_name']} {c['last_name']}" + (f" ({org['name']})" if org else ''),
                        details='Client. Send the Q4 check-in email and newsletter.', follow_up_style='standard_check_in',
                        assigned_to=c['owner_id'], status='open', snoozed_until=None, created_by='system',
                        completed_by=None, completed_at=None, created_at=at(dt.date(2026, 9, 1), 6)))
    # RFP deadlines
    for rf in RFPS:
        if rf['status'] in ('identified', 'intent_to_bid'):
            rem.append(dict(id=len(rem) + 1, reminder_type='rfp_deadline', contact_id=rf['contact_id'],
                            organization_id=rf['organization_id'], opportunity_id=None, rfp_id=rf['id'], touchpoint_id=None,
                            due_on=rf['due_on'] - days(7), title=f"RFP due {rf['due_on']:%b %d}: {rf['title']}",
                            details=f"Response due {rf['due_on']:%b %d, %Y}. Reminder set a week ahead.",
                            follow_up_style=None, assigned_to=rf['owner_id'], status='open', snoozed_until=None,
                            created_by='system', completed_by=None, completed_at=None, created_at=at(rf['released_on'], 12)))
    # one snoozed reminder so the "snoozed" state shows up
    snoozable = [r for r in rem if r['status'] == 'open' and r['reminder_type'] == 'follow_up' and r['due_on'] < TODAY]
    if snoozable:
        snoozable[0].update(status='snoozed', snoozed_until=dt.date(2026, 10, 5), due_on=dt.date(2026, 10, 5))
    return rem


# ---------------------------------------------------------------------------
# email messages (the correspondence history)
# ---------------------------------------------------------------------------

def build_emails() -> list[dict]:
    msgs: list[dict] = []
    for t in TOUCHES:
        if t['touch_type'] not in ('email', 'check_in'):
            continue
        c = CT_BY_ID[t['contact_id']]
        me = TEAM_BY_ID[t['owner_id']]
        subj = t['subject'] or 'Checking in'
        msgs.append(dict(id=len(msgs) + 1, contact_id=c['id'], touchpoint_id=t['id'], mailbox=me['email'],
                         external_id=f"<mock-{len(msgs) + 1:06d}@gaard.example>", thread_id=f"thread-{t['id']:06d}",
                         direction='outbound', from_email=me['email'], to_emails=[t['_to']], cc_emails=[], subject=subj,
                         body_text=outbound_body(t, c), sent_at=t['touched_at'], is_auto_reply=False,
                         created_at=t['touched_at']))
        if t.get('_reply') and t['responded_at']:
            code = t['outcome_code']
            auto = code in ('OUT_OF_OFFICE', 'BOUNCED')
            msgs.append(dict(id=len(msgs) + 1, contact_id=c['id'], touchpoint_id=t['id'], mailbox=me['email'],
                             external_id=f"<mock-{len(msgs) + 1:06d}@gaard.example>", thread_id=f"thread-{t['id']:06d}",
                             direction='inbound',
                             from_email='mailer-daemon@mail.example' if code == 'BOUNCED' else t['_to'],
                             to_emails=[me['email']], cc_emails=[],
                             subject=('Delivery Status Notification (Failure)' if code == 'BOUNCED'
                                      else f'Automatic reply: {subj}' if code == 'OUT_OF_OFFICE' else f'Re: {subj}'),
                             body_text=t['_reply'], sent_at=t['responded_at'], is_auto_reply=auto,
                             created_at=t['responded_at']))
    return msgs


# ---------------------------------------------------------------------------
# SQL output
# ---------------------------------------------------------------------------

def q(v) -> str:
    if v is None:
        return 'null'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int,)):
        return str(v)
    if isinstance(v, float):
        return repr(round(v, 3))
    if isinstance(v, dt.datetime):
        return f"'{v:%Y-%m-%d %H:%M:%S} America/Denver'"
    if isinstance(v, dt.date):
        return f"'{v:%Y-%m-%d}'"
    if isinstance(v, (list, tuple)):
        return "'{" + ','.join('"' + str(x).replace('"', '\\"') + '"' for x in v) + "}'"
    return "'" + str(v).replace("'", "''") + "'"


def inserts(table: str, cols: list[str], rows: list[dict], chunk: int = 200) -> str:
    out = []
    for i in range(0, len(rows), chunk):
        part = rows[i:i + chunk]
        vals = ',\n'.join('  (' + ', '.join(q(r.get(c)) for c in cols) + ')' for r in part)
        out.append(f'insert into public.{table} ({", ".join(cols)}) values\n{vals};\n')
    return '\n'.join(out)


def write_seed(reminders: list[dict], msgs: list[dict]) -> None:
    tm_cols = ['id', 'full_name', 'email', 'role']
    org_cols = ['id', 'name', 'segment_code', 'org_type', 'website', 'phone', 'city', 'state', 'reported_aum',
                'employee_count', 'is_university_affiliated', 'do_not_contact', 'dnc_reason', 'owner_id', 'tags', 'notes',
                'source_detail', 'legacy_ref', 'created_at']
    ct_cols = ['id', 'organization_id', 'segment_code', 'first_name', 'last_name', 'title', 'employer', 'is_decision_maker',
               'email', 'email_status', 'phone', 'linkedin_url', 'linkedin_connected_on', 'city', 'state', 'prospect_aum',
               'source_channel_code', 'source_detail', 'source_event_id', 'referred_by_contact_id', 'sourced_on',
               'is_university_affiliated', 'do_not_contact', 'dnc_reason', 'dnc_on', 'newsletter_status',
               'newsletter_added_on', 'newsletter_added_via', 'follow_up_style', 'owner_id', 'tags', 'notes', 'legacy_ref',
               'created_at']
    ev_cols = ['id', 'name', 'event_type', 'format', 'hosted_by_us', 'host_org', 'start_on', 'end_on', 'city', 'state',
               'cost_usd', 'attendees_est', 'target_segment_code', 'owner_id', 'notes', 'created_at']
    cp_cols = ['id', 'name', 'channel_code', 'segment_code', 'target_states', 'start_on', 'end_on', 'owner_id', 'description',
               'created_at']
    rfp_cols = ['id', 'organization_id', 'contact_id', 'title', 'mandate_type', 'found_via', 'est_mandate_aum', 'released_on',
                'questions_due_on', 'due_on', 'submitted_on', 'status', 'decision_on', 'owner_id', 'notes', 'created_at']
    tp_cols = ['id', 'contact_id', 'organization_id', 'touch_type', 'direction', 'touched_at', 'campaign_id', 'event_id',
               'rfp_id', 'sequence_step', 'subject', 'notes', 'outcome_code', 'outcome_status', 'outcome_raw',
               'responded_at', 'response_excerpt', 'follow_up_on', 'ooo_return_on', 'ai_suggested_outcome',
               'ai_confidence', 'ai_reason', 'confirmed_by', 'confirmed_at', 'owner_id', 'created_at']
    em_cols = ['id', 'contact_id', 'touchpoint_id', 'mailbox', 'external_id', 'thread_id', 'direction', 'from_email',
               'to_emails', 'cc_emails', 'subject', 'body_text', 'sent_at', 'is_auto_reply', 'created_at']
    op_cols = ['id', 'contact_id', 'organization_id', 'segment_code', 'state', 'stage', 'source_channel_code',
               'converting_channel_code', 'converting_touchpoint_id', 'source_event_id', 'rfp_id', 'opened_on',
               'first_call_on', 'hot_on', 'onboarding_started_on', 'contract_signed_on', 'funded_on', 'closed_on',
               'lost_reason', 'expected_aum', 'funded_aum', 'owner_id', 'notes', 'created_at']
    rm_cols = ['id', 'reminder_type', 'contact_id', 'organization_id', 'opportunity_id', 'rfp_id', 'touchpoint_id', 'due_on',
               'title', 'details', 'follow_up_style', 'assigned_to', 'status', 'snoozed_until', 'created_by', 'completed_by',
               'completed_at', 'created_at']
    for t in TOUCHES:
        t['created_at'] = t['touched_at'] + dt.timedelta(minutes=1)
    # referrals point forward in a few cases: insert contacts first, link referrers after
    refs = [(c['id'], c['referred_by_contact_id']) for c in CONTACTS if c['referred_by_contact_id']]
    ct_rows = [dict(c, referred_by_contact_id=None) for c in CONTACTS]

    parts = [
        '-- =====================================================================',
        '-- GAARD Capital CRM · mock data (generated by db/scripts/generate_mock_data.py)',
        '-- Load after the migrations. Everything here is fictional: .example email',
        '-- domains, 555-01xx phone numbers, invented names and organizations.',
        f'-- {len(ORGS)} organizations, {len(CONTACTS)} contacts, {len(TOUCHES)} touchpoints, {len(OPPS)} opportunities,',
        f'-- {len(reminders)} reminders, {len(msgs)} email messages, {len(EVENTS)} events, {len(RFPS)} RFPs.',
        '-- =====================================================================',
        '',
        "select set_config('app.seeding', 'on', false);   -- history is loaded as-is; the automation rules stay quiet",
        '',
        '-- mock-only lookups and flag rules',
        "insert into public.freemail_domains (domain) values ('mail.example'), ('inbox.example'), ('webmail.example') on conflict do nothing;",
        'insert into public.flag_rules (match_on, pattern, flag, reason) values',
        "  ('email_domain', '.edu.example', 'university', 'Mock data: stands in for .edu addresses'),",
        "  ('email_domain', 'summitpeakwealth.example', 'do_not_contact', 'Competitor firm: do not solicit'),",
        "  ('org_name', 'Beehive State Credit Union', 'do_not_contact', 'Banking partner: founder handles the relationship'),",
        "  ('email', 'r.hollis@mail.example', 'do_not_contact', 'Personal friend of the founder: he reaches out himself');",
        '',
        inserts('team_members', tm_cols, TEAM),
        "insert into public.territory_assignments (team_member_id, state, segment_code) values (1, 'UT', null), (1, 'CA', null), (2, 'ID', null), (2, 'WY', null), (2, null, 'IND_ROBO'), (2, null, 'RET_401K');",
        '',
        inserts('events', ev_cols, EVENTS),
        inserts('campaigns', cp_cols, list(CAMPAIGNS.values())),
        inserts('organizations', org_cols, ORGS),
        inserts('contacts', ct_cols, ct_rows),
        '-- who referred whom',
        ('update public.contacts c set referred_by_contact_id = v.ref from (values '
         + ', '.join(f'({a}, {b})' for a, b in refs) + ') as v(id, ref) where c.id = v.id;\n') if refs else '',
        inserts('rfps', rfp_cols, RFPS),
        inserts('touchpoints', tp_cols, TOUCHES),
        inserts('email_messages', em_cols, msgs),
        inserts('opportunities', op_cols, OPPS),
        inserts('reminders', rm_cols, reminders),
        '-- continue numbering after the mock rows',
    ]
    for tbl in ['team_members', 'territory_assignments', 'events', 'campaigns', 'organizations', 'contacts', 'rfps',
                'touchpoints', 'email_messages', 'opportunities', 'reminders', 'flag_rules']:
        parts.append(f"select setval(pg_get_serial_sequence('public.{tbl}', 'id'), (select coalesce(max(id), 1) from public.{tbl}));")
    parts += ['', "select set_config('app.seeding', 'off', false);", '']
    (ROOT / 'mock' / 'seed.sql').write_text('\n'.join(parts))

    # same data split into pieces small enough to paste into the Supabase SQL editor (run in order)
    on, off = "select set_config('app.seeding', 'on', false);", "select set_config('app.seeding', 'off', false);"
    body = '\n'.join(parts)
    cut1 = body.index('insert into public.rfps')
    cut2 = body.index('insert into public.email_messages')
    cut3 = body.index('insert into public.opportunities')
    pieces = [body[:cut1], body[cut1:cut2], body[cut2:cut3], body[cut3:]]
    out_dir = ROOT / 'mock' / 'seed_parts'
    out_dir.mkdir(parents=True, exist_ok=True)
    for i, piece in enumerate(pieces, 1):
        head = f'-- GAARD CRM mock data, part {i} of {len(pieces)}. Run the parts in order after the migrations.\n'
        text = piece if i == 1 else f'{on}\n\n{piece}'
        if i < len(pieces):
            text = f'{text}\n{off}\n'
        (out_dir / f'seed_part_{i}_of_{len(pieces)}.sql').write_text(head + text)


# ---------------------------------------------------------------------------
# demo import batch, in the outreach sheet's own columns
# ---------------------------------------------------------------------------

def write_import_demo() -> None:
    R2 = random.Random(7)
    ev = next(e for e in EVENTS if e['name'] == 'Jackson Hole Philanthropy Retreat')
    rows = []

    def row(**kw):
        base = {k: '' for k in ['Date', 'Source', 'Contact', 'First Name', 'Email', 'Org', 'Website', 'LinkedIn',
                                'Added on LinkedIn', 'Notes', 'Date Outreached', 'Outcome', 'Next Steps', 'Phone', 'AUM',
                                'State', 'Segment']}
        base.update(kw)
        rows.append(base)

    def fullname(c):
        return f"{c['first_name']} {c['last_name']}"

    # already in the CRM: same email typed differently
    exist = [c for c in CONTACTS if c['segment_code'] == 'ORG_NONPROFIT' and c['organization_id'] and not c['do_not_contact']
             and c['email_status'] != 'bounced']
    for c in R2.sample(exist, 4):
        org = ORG_BY_ID[c['organization_id']]
        row(Date='9/18/26', Source='Jackson Hole retreat attendee list', Contact=fullname(c), **{'First Name': c['first_name']},
            Email='  ' + c['email'].upper() + ' ', Org=org['name'], Website=org['website'] or '', State=org['state'])
    unsub = next(c for c in CONTACTS if c['dnc_reason'] == 'Asked not to be contacted' and c['organization_id'])
    row(Date='9/18/26', Source='Jackson Hole retreat attendee list', Contact=fullname(unsub),
        **{'First Name': unsub['first_name']}, Email=unsub['email'], Org=ORG_BY_ID[unsub['organization_id']]['name'])
    # already in the CRM: same LinkedIn written a different way, different or missing email
    with_li = [c for c in CONTACTS if c['linkedin_url'] and c['segment_code'] == 'ORG_OTHER' and not c['do_not_contact']]
    for c in R2.sample(with_li, 2):
        slug = c['linkedin_url'].rsplit('/', 1)[1]
        row(Date='2026-09-18', Source='Retreat dinner', Contact=fullname(c), **{'First Name': c['first_name']},
            Email='', Org=ORG_BY_ID[c['organization_id']]['name'], LinkedIn=f'http://linkedin.com/in/{slug.upper()}/?trk=retreat')
    # new person, known organization (matched by website, name, or a colleague's email domain)
    silent_orgs = [o for o in ORGS if o['segment_code'] == 'ORG_NONPROFIT' and o['state'] == 'UT' and not ORG_OPP_SPANS[o['id']]
                   and not o['do_not_contact'] and o['legacy_ref'].startswith('Outreach Master (2025)')]
    picks = R2.sample(silent_orgs, 5)
    for i, o in enumerate(picks):
        f, l_ = R2.choice(FIRST), R2.choice(LAST_NAMES)
        kw = dict(Date='9/19/26', Source='Met at Jackson Hole Philanthropy Retreat', Contact=f'{f} {l_}', **{'First Name': f},
                  Email=f"{f.lower()}.{l_.lower()}@{o['domain']}", State='UT', Notes='New board treasurer; interested in reserve policy.')
        if i in (0, 1):
            kw.update(Org=o['name'].upper() if i == 0 else o['name'] + ', Inc.', Website='')
        elif i == 2:
            kw.update(Org='', Website=f"https://www.{o['domain']}/about-us")
        else:
            kw.update(Org=o['name'] + (' (Utah)' if i == 3 else ''), Website='')
        row(**kw)
    # look-alike organization names: a person decides
    for o in R2.sample([o for o in ORGS if o['segment_code'] == 'ORG_NONPROFIT' and len(o['name']) > 20
                        and not o['name'].startswith('Friends')], 2):
        f, l_ = R2.choice(FIRST), R2.choice(LAST_NAMES)
        words = o['name'].split()
        typo = ' '.join(words[:-1] + [words[-1][:-1] if words[-1].endswith('s') else words[-1] + 's'])
        row(Date='9/19/26', Source='Retreat attendee list', Contact=f'{f} {l_}', **{'First Name': f},
            Email=f"{f.lower()}@{typo.lower().replace(' ', '')}.example", Org=typo, State=o['state'])
    # same name at a known organization, different email
    twin = next(c for c in CONTACTS if c['segment_code'] == 'ORG_NONPROFIT' and c['organization_id']
                and c['source_channel_code'] == 'COLD_EMAIL' and c['id'] > 40 and not c['do_not_contact'])
    torg = ORG_BY_ID[twin['organization_id']]
    row(Date='9/19/26', Source='Business card', Contact=fullname(twin), **{'First Name': twin['first_name']},
        Email=f"{twin['first_name'].lower()}.{twin['last_name'].lower()}.board@{torg['domain']}", Org=torg['name'],
        Notes='Card says a different email than we have.')
    # flag rules: competitor domain, banking partner organization, university
    row(Date='9/18/26', Source='Retreat attendee list', Contact='Greta Lindqvist', **{'First Name': 'Greta'},
        Email='greta.lindqvist@summitpeakwealth.example', Org='Summit Peak Wealth Partners', State='ID', Segment='Other')
    row(Date='9/18/26', Source='Retreat attendee list', Contact='Marcus Bell', **{'First Name': 'Marcus'},
        Email='mbell@beehivestatecu.example', Org='Beehive State Credit Union', State='UT', Segment='Other')
    row(Date='9/19/26', Source='Retreat dinner', Contact='Helen Okafor', **{'First Name': 'Helen'},
        Email='helen.okafor@summitridge.edu.example', Org='', State='UT', Segment='OCIO', AUM='$4.5M',
        Notes='Professor; knows the founder from the business school.')
    row(Date='9/19/26', Source='Retreat dinner', Contact='Samuel Begay', **{'First Name': 'Samuel'},
        Email='sbegay@canyonlandsstate.edu.example', Org='Canyonlands State University Foundation', State='ID', Segment='Other')
    # the same person twice inside this batch
    row(Date='9/18/26', Source='Retreat attendee list', Contact='Priya Raman', **{'First Name': 'Priya'},
        Email='priya.raman@tetonwatershedtrust.example', Org='Teton Watershed Trust', Website='tetonwatershedtrust.example',
        State='WY', AUM='12,000,000', Segment='Nonprofit')
    row(Date='9/19/26', Source='Business card', Contact='Priya Raman', **{'First Name': 'Priya'},
        Email='Priya.Raman@TetonWatershedTrust.example', Org='Teton Watershed Trust', State='WY', Segment='Nonprofit',
        Phone='(307) 555-0142')
    # bad email, empty row
    row(Date='9/19/26', Source='Retreat attendee list', Contact='Luis Ortega', **{'First Name': 'Luis'}, Email='N/A',
        Org='Star Valley Arts Guild', State='WY', LinkedIn='https://www.linkedin.com/in/luis-ortega-starvalley', Segment='Nonprofit')
    row(Date='9/19/26', Source='Retreat attendee list', Notes='(blank row from the sheet)')
    # brand new, some already emailed with the old free-text outcomes
    fresh = [
        ('Teton Valley Youth Orchestra', 'WY', '$850k', '9/22/26', 'No response', ''),
        ('Sweetwater Food Bank Alliance', 'WY', '$2.1M', '9/22/26', 'No thank you, we already have an advisor we are happy with.', ''),
        ('Jackson Hole Wildlife Society', 'WY', '$6.3M', '9/22/26', 'OOO until 10/6', ''),
        ('Snake River Watershed Council', 'ID', '$3.4M', '9/23/26', 'Interested - call scheduled', 'Call Thu 10/1 at 2pm'),
        ('Wind River Literacy Project', 'WY', '$400k', '9/23/26', 'left vm', ''),
        ('Absaroka Trails Coalition', 'WY', '$1.2M', '9/23/26',
         'Thanks for the note. Please check back after our board meeting in November.', ''),
        ('Platte Valley Senior Services', 'WY', '', '', '', ''),
    ]
    for oname, st, aum, d_out, outc, nxt in fresh:
        f, l_ = R2.choice(FIRST), R2.choice(LAST_NAMES)
        dom = re.sub(r'[^a-z]', '', oname.lower()) + '.example'
        row(Date='Sep 18, 2026', Source='Jackson Hole retreat attendee list', Contact=f'{f} {l_}', **{'First Name': f},
            Email=f"{f[0].lower()}{l_.lower()}@{dom}", Org=oname, Website=f'https://{dom}', State=st, AUM=aum,
            **{'Added on LinkedIn': R2.choice(['Yes', 'TRUE', '', 'No', '9/19/26'])},
            **{'Date Outreached': d_out, 'Outcome': outc, 'Next Steps': nxt}, Segment='Nonprofit')
    f, l_ = 'Keanu', 'Mahe'
    row(Date='9/19/26', Source='Workshop waitlist', Contact=f'{f} {l_}', **{'First Name': f}, Email='keanu.mahe@mail.example',
        Org='', State='UT', Segment='Robo', AUM='40k')

    out_csv = ROOT / 'mock' / 'import_demo' / 'new_prospects_batch.csv'
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with out_csv.open('w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    cols = {'Date': 'date_added', 'Source': 'source', 'Contact': 'contact', 'First Name': 'first_name', 'Email': 'email',
            'Org': 'org', 'Website': 'website', 'LinkedIn': 'linkedin', 'Added on LinkedIn': 'added_on_linkedin',
            'Notes': 'notes', 'Date Outreached': 'date_outreached', 'Outcome': 'outcome', 'Next Steps': 'next_steps',
            'Phone': 'phone', 'AUM': 'aum', 'State': 'state', 'Segment': 'segment'}
    lines = [
        '-- =====================================================================',
        '-- Demo: a new sourcing batch goes through the import pipeline.',
        '-- Rows come from db/mock/import_demo/new_prospects_batch.csv (the outreach',
        "-- sheet's own column names). Run after seed.sql.",
        '-- =====================================================================',
        '',
        'with batch as (',
        '  insert into public.import_batches (label, source_file, default_segment_code, default_channel_code,',
        '                                     default_touch_type, event_id, owner_id)',
        f"  values ('Sept 2026 sourcing: {ev['name']}', 'new_prospects_batch.csv', 'ORG_NONPROFIT', 'EVENT', 'email', {ev['id']}, 1)",
        '  returning id)',
        'insert into public.import_rows (batch_id, row_number, ' + ', '.join(cols.values()) + ')',
        'select batch.id, v.* from batch, (values',
    ]
    vals = []
    for i, r in enumerate(rows, start=2):
        vals.append('  (' + ', '.join([str(i)] + [q(r[k]) if r[k] != '' else 'null' for k in cols]) + ')')
    lines.append(',\n'.join(vals))
    lines.append(') as v(row_number, ' + ', '.join(cols.values()) + ');')
    lines += ['',
              '-- 2. run it: every row is matched against the CRM and labelled',
              "select jsonb_pretty(public.process_import_batch((select max(id) from public.import_batches))) as summary;",
              '',
              'select row_number, result, matched_on, left(result_detail, 160) as what_happened',
              '  from public.v_import_results',
              ' where batch_id = (select max(id) from public.import_batches)',
              ' order by row_number;',
              '',
              '-- 3. a person answers the "needs_review" rows (in the app this is a button), then run it again',
              'update public.import_rows ir',
              "   set review_decision = case when ir.matched_on = 'similar organization name' and ir.org ilike 'Beehive%'",
              "                              then 'create_new' else 'use_candidate' end",
              " where ir.batch_id = (select max(id) from public.import_batches) and ir.result = 'needs_review';",
              "select jsonb_pretty(public.process_import_batch((select max(id) from public.import_batches))) as summary_after_review;",
              '',
              '-- 4. the old free-text outcomes that need a click: confirm them and the rules run',
              "select touchpoint_id, full_name, organization, provisional_outcome, left(outcome_raw, 60) as old_outcome_text",
              '  from public.v_outcome_review_queue',
              ' where touchpoint_id in (select touchpoint_id from public.import_rows',
              '                          where batch_id = (select max(id) from public.import_batches));',
              '']
    out_sql = ROOT / 'mock' / 'import_demo' / 'import_demo.sql'
    out_sql.parent.mkdir(parents=True, exist_ok=True)
    out_sql.write_text('\n'.join(lines))


def main() -> None:
    build()
    plant_review_queue()
    TOUCHES.sort(key=lambda t: (t['touched_at'], t['id']))
    remap = {t['id']: i for i, t in enumerate(TOUCHES, 1)}
    for t in TOUCHES:
        t['id'] = remap[t['id']]
    for o in OPPS:
        o['converting_touchpoint_id'] = remap[o['converting_touchpoint_id']]
    reminders = build_reminders()
    msgs = build_emails()
    write_seed(reminders, msgs)
    write_import_demo()
    n_open = sum(1 for r in reminders if r['status'] in ('open', 'snoozed'))
    stages = defaultdict(int)
    for o in OPPS:
        stages[o['stage']] += 1
    print(f'orgs={len(ORGS)} contacts={len(CONTACTS)} touches={len(TOUCHES)} opps={len(OPPS)} {dict(stages)} '
          f'reminders={len(reminders)} (open {n_open}) emails={len(msgs)}')
    print('funded AUM $%.1fM' % (sum(o['funded_aum'] or 0 for o in OPPS if o['stage'] == 'funded') / 1e6))


if __name__ == '__main__':
    main()
