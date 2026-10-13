# GAARD Capital CRM

A working prototype of the CRM that replaces the outreach spreadsheets. One
file, no build step, no server. Open it and it runs.

Everything in it is fictional. Email addresses use the reserved `.example`
domain and phone numbers use the reserved 555-01xx range, so nothing in here
can reach a real person.

## Run it

Open `index.html` in any browser. That is the whole install.

To work on it locally, serve the folder so browser storage behaves normally:

```bash
python3 -m http.server 8765
```

Then open http://localhost:8765/index.html

## Put it on the web

GitHub Pages serves this repository as it stands.

1. Settings, then Pages.
2. Source: Deploy from a branch.
3. Branch: `main`, folder: `/ (root)`. Save.
4. Wait a minute, then open the URL Pages shows you.

`index.html` is at the root, so the site URL needs no path. The `.nojekyll`
file stops GitHub trying to process the folder as a Jekyll blog.

A public repository means the code is public. The data inside is invented, so
nothing confidential is published, but anyone can read it.

## What it does

| Screen | What it is for |
|---|---|
| Dashboard | the work waiting on you, and whether the outreach is landing: the headline numbers, the funnel from emails sent to funded with the conversion between every stage, and today's email queue |
| KPIs | the same period cut further: eight cards, the charts, what happened lane by lane, warm against dormant, and the emails by state. Pipeline sits beside it as a tab |
| Follow-ups | the shared reminder list, one at a time or as a batch mail merge, with a tab for outreach that went nowhere |
| Contacts | the master list as a spreadsheet, with Organizations and Correspondence as tabs. Every cell edits in place |
| Newsletter | the subscribers, as the same sheet |
| Partners | benefit groups and referral partners, the firms to work with rather than sell to |
| Reviews | funded accounts and when each is next owed a performance report, on a quarterly, semi-annual or annual cadence |
| Events, RFPs | what each event cost and produced, measured against cold email, and the RFP tracker |
| Import | paste or upload a sheet, every row checked against the master list before anything is written |
| Workflow | how a name becomes a funded client, step by step |
| Settings | the configuration tables, the email templates, and what is not connected yet |

Nothing is typed in twice. Every figure is counted from the touchpoints,
opportunities and reminders, so there is no separate reporting tab to keep up
to date.

## How it is built

`index.html` is one file of plain HTML, CSS and JavaScript. No framework, no
dependencies, no bundler. The only network request is a Google font.

It has eight labelled sections:

1. Reference data. Categories, channels, outcomes and the rule each outcome
   triggers. These are rows, not code, so the wording can change without a
   developer.
2. Embedded data. A snapshot of every table, stored column first to keep the
   file small.
3. Data access. A small layer whose method names match the SQL views the real
   application will call. This is the seam.
4. Metrics. Everything the dashboard shows.
5. Intelligence. The import pipeline: column mapping, duplicate detection,
   outcome wording, AUM classification.
6. Rules. Follow-up scheduling and business day arithmetic.
7. Views. The screens.
8. Router and boot.

Edits are kept in the browser under one storage key, so a demo can be changed
freely and reset from Settings.

## Connecting a real database

The database lives in its own repository, `gaard-crm-db`: the Postgres schema,
the migrations and the seed data. Connecting it is a change to section 3 only.
Every read already goes through that one layer, so the screens do not change.

## What is not connected yet

Written down in the application itself, under Settings.

- **Sending email.** The merge screen fills the letters and records that they
  were sent. The sending happens in your own mailbox. To make the button
  really send: a sending service or mailbox, a verified sending domain, and a
  reply address that posts replies back in.
- **Calendar invites.** Nothing writes to a calendar, deliberately. When it is
  built, the invite is drafted from the confirmed thread and shown for review,
  and a person confirms the time, the attendees and the link before it is sent.
- **The database.** The prototype reads the embedded snapshot. Supabase is the
  data layer.

## Changing it

The whole application is one file, so a change is one edit and a refresh.
Search for the section banners to find your way around.
