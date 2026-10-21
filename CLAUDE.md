# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

It is also the handover document for Gaard Capital: anyone who takes over this CRM can give this repository to Claude and work from here. Keep it current. When the architecture, the database, the hosting or the status below changes, update this file in the same commit.

## Before editing (team rules)

Several people edit this repo, and an outdated copy pushed over a newer one erases their work.

- Always run `git pull` before editing. If it brings in changes, tell the user their copy was out of date.
- When `index.html` changes, bump its `build-version` meta tag. Format `YYYY-MM-DD.N`, where N counts the changes made that day. The comment at the very top of `index.html` asks AI assistants to compare this tag with the copy on GitHub; keep that comment.
- Edit only what's needed; never replace whole files with older copies.
- Commit and push small changes with git (pull, commit, push) straight to `main`. No branches. Never upload files through the GitHub website: it silently overwrites newer work.
- Ask the user before committing or pushing. A push to `main` goes live immediately.
- Never commit real client data, personal emails, or any secret (see "Secrets").
- Several people work on `index.html` at once. Pull right before starting and again right before pushing, and push small changes often. If git refuses a push ("fetch first"), pull: git merges the other person's work into yours. A conflict only happens where both of you changed the same lines; keep both changes. The `build-version` line conflicts almost every time: keep one line with the next number for the day. Never force-push and never `git reset` away someone else's commit.
- Say in the team chat which screen you are working on, so two people rarely edit the same part of `index.html`.

## What this is

A CRM for Gaard Capital, an outsourced investment office in Utah. It replaces the outreach spreadsheets: contacts and organizations, every email, call and meeting (touchpoints), the follow-up reminders those generate, the pipeline from first call to funded, events, RFPs, portfolio review cadence, imports from spreadsheets, and the KPIs counted from all of it. Jon Clifford is the business owner and admin.

The front end is one file, `index.html`: plain HTML, CSS and JavaScript, styled after gaard.capital (Poppins text, Montserrat headings, Gaard blue `#1C6DBD`, a navy sidebar with the site's white logo). No framework, no build step, no tests, no linter. The only outside code is fetched from jsdelivr the first time it is needed, never on page load: Tesseract.js (screenshot reading), SheetJS (`xlsx`, Excel uploads) and JSZip (Word uploads), used by the Import drop zone (a file browsed or dropped) through `Files`. Google Identity Services (accounts.google.com/gsi/client) is loaded the first time someone sends a mail merge from Gmail. The database is Supabase (Postgres).

## Where things live

| What | Where |
|---|---|
| Code | GitHub `Gaard-Capital/gaard-crm`, branch `main`. The repo is public. |
| Live site | Vercel, deployed automatically on every push to `main`: https://project-qp4en.vercel.app/ . GitHub Pages also serves `main`: https://gaard-capital.github.io/gaard-crm/ |
| Database | Supabase project `fgweqsoflzvxkbxgozor` (https://fgweqsoflzvxkbxgozor.supabase.co), organization "Gaard", free plan. |
| Database changes | `db/`, numbered SQL files (see "Changing the database"). |
| Google sign-in | An OAuth client ("Gaard CRM Web") in a Google Cloud project named "Gaard CRM". Currently in Testing mode with the team as test users; to be moved to Gaard's own Google Workspace at handover. |
| Company email | `gaard.capital` is on Google Workspace, so staff can use "Sign in with Google". |

## Secrets

- The Supabase **publishable** key (`sb_publishable_…`) is designed to sit in front-end code. It is only safe because every table has row level security; never weaken that.
- The Supabase **secret** key, the Google OAuth client secret, and any SMTP or Resend credentials never go in this repo, in `index.html`, or in a chat. They live only in the Supabase dashboard (or a server-side environment). Code that needs them runs server-side (a Supabase Edge Function).

## Running it

```bash
python3 -m http.server 8765   # then open http://localhost:8765/index.html
```

Opening the file directly also works; serving it keeps browser storage behaving normally. Edits made in the UI persist in `localStorage` under `gaard_crm_db_v1`; reset them from Settings (or clear that key) to get back to the embedded snapshot. `http://localhost:8765` is registered as an allowed origin for Google sign-in.

## Working with index.html

The file is ~2.3 MB but only ~4,500 lines, because the embedded data snapshot (`const DB_SNAPSHOT = {...}`, in Section 2) sits on one enormous line. Don't read the file whole or print that line: read by line range, and when grepping, exclude or truncate long lines (e.g. pipe through `cut -c1-200`).

Navigate by the section banners (`SECTION 1.` … `SECTION 8.`) and the view banners (`/* ===== Contacts =====`). The order is: CSS, then

1. **Reference data**: segments, channels, touch types, outcomes, and the rule each outcome triggers. These are data rows, not logic, so wording changes go here.
2. **Embedded data**: `DB_SNAPSHOT`, a fictional snapshot of the database tables, stored column-first (`{ c: [cols], r: [[row], ...] }`). `hydrate()` turns it into row objects, adds the generated columns the DB computes (`full_name`, `email_key`, `linkedin_key`), and shifts every `*_at` / `*_on` / `*_until` date by the gap between `DB_ANCHOR` and today (toggle with `SHIFT_DATES_TO_TODAY`) so the demo always looks current. Emails use the reserved `.example` domain and phones the 555-01xx range; keep any new sample data within those ranges.
3. **Data access**: `Persist` (localStorage), `Store`, `MERGE_TEMPLATES`, and `Repo`.
4. **Metrics**: everything the dashboard/KPI screens count.
5. **Intelligence**: the import pipeline. `readRows` reads pasted rows with or without a header row: headers map by name (`autoMap`), and any column left over is recognized from its contents (an @ is an email, m/d/yyyy a date, linkedin.com a profile, $ or large numbers AUM, two capitalized words a name, the column matching a name's first word the first name, and so on). `analyze` checks each row against the book (duplicate detection, organization spelling, outcome wording, AUM classification). Import is three steps shown as a stepper (`impSteps`): Add data (a drop zone for csv, Excel, Word or a picture, a paste box, and a side panel with what can be imported and two samples), Check, Imported. The check is one screen: rows that are clear go in without a question, only a possible duplicate (`needs_review`) asks for a choice, and each row shows at most one short reason. A row that matches someone on file (same email, LinkedIn, or for a row without a usable email the same full name) can open a side-by-side comparison, row against contact, field by field: same, new (ticked to add), different (written only if Replace is ticked); `commitBatch` writes only the ticked lines (`r.picks`), and a match with nothing ticked is left out. After the import the same screen shows what each row became (Added or Updated, with a link to the contact; `commitBatch` sets `r.savedAs` / `r.savedId`). The same email under a different name, and a row whose email is missing or invalid, always ask. "This list is" (new people, met at an event, newsletter sign-ups, benefit group or referral partners) tells `commitBatch` where the people belong: an event links them to it and logs a Met at event activity, the newsletter subscribes them, partners set the segment. Pasted replies (and screenshots) use the same check screen: a reply matched to a person with a clear outcome needs nothing, and only an unknown sender or an unsure outcome asks. Then `Replies`: pasted client replies are split one per email, matched to a contact by address, and given an outcome from their wording by ordered regex rules (bounce and auto-reply first, "not interested" before "interested"); a person confirms, and saving updates the latest email we sent that person and runs `Rules.applyOutcome`. A screenshot of a whole Gmail conversation is cut at its message headers (a sender line with a time such as "8:26 AM"); messages that share most of their words with a letter we sent (that person's outbound activity or any template) are ours, and the newest of the rest is the reply that gets classified and stored. Then `Ocr`, which turns screenshots into text in the browser: a pasted or dropped screenshot is shown inside the box first and is read when Continue is pressed (enlarged and greyed first, which Tesseract reads better). A screenshot of a sheet (several lines, each with an email) is turned into tab-separated rows by `Ocr.sheetRows` and goes through the row check; copying the cells themselves is always more accurate.
6. **Rules**: outcome-driven follow-up scheduling and business-day arithmetic.
7. **Views**: `UI` (per-screen UI state), shared helpers, then one `Views.<name> = { title, render(params), mount(el, params) }` per screen.
8. **Router and boot**: hash routing, nav, tabs.

### Front-end rules that span the file

- **`Repo` is the seam to the database.** Screens read only through `Repo`; each method carries a comment naming the SQL query or view it stands in for (the `v_*` views below). Moving onto Supabase means replacing `Repo` method bodies (and dropping Section 2) with no screen changes. Keep new reads in `Repo` with the matching SQL comment rather than touching `Store.state` from views.
- **All writes go through `Store.commit(label, mutator, { undoable, silent })`.** It snapshots for undo (last 12), bumps `Store.version`, debounces persistence, re-renders every subscriber, and shows a toast with the label (plus an Undo action). Mutating `Store.state` directly skips all of that.
- **Caching is keyed on `Store.version`.** `memo(fn)` caches until the next commit, so derived indexes and metrics are recomputed automatically; anything memoized must only depend on store state.
- **Nothing is stored twice.** Every figure is computed from touchpoints, opportunities and reminders; there is no separate reporting table to keep in sync.
- **Rendering is whole-view.** `render()` rebuilds `#main` from `view.render(params)` as an HTML string, then calls `view.mount()` to attach listeners, restoring scroll positions and the focused input by `id`. Inputs that must keep focus while typing need a stable `id`. Escape interpolated values with `esc()`.
- **Routing** is hash-based: `#/name?k=v`, with `#/contacts/<id>` and `#/organizations/<id>` aliased to the `contact` / `organization` record views. Use `href(name, params)` / `go(name, params)`. Unknown names fall back to the dashboard. `NAV` lists the sidebar entries, `NAV_OF` maps sub-screens to their sidebar owner, and `TABS` groups screens shown as tabs. The sidebar has seven entries: Dashboard, KPIs (tabs KPIs, Pipeline), Follow-ups (One at a time, Send as a batch, Email templates, Client reviews), Contacts (People, Organizations, Partners, Newsletter), Events, RFPs, Import. Workflow ("How it works") and Settings open from the account menu. A new screen needs a `Views` entry and either a `NAV` row or a place in `NAV_OF`/`TABS`.

## The database

Built in Supabase from Jon's mock spreadsheet. The `gaard-crm-db` repository mentioned in older notes is not reachable; the live Supabase project is the source of truth for anything not in `db/`. To see the current schema, run queries in the SQL Editor against `information_schema` and `pg_get_functiondef`.

**Tables (28, schema `public`)**
- Reference and configuration: `segments`, `channels`, `touch_types`, `outcomes`, `outcome_aliases`, `pipeline_stages`, `reminder_types`, `us_states`, `freemail_domains`, `flag_rules`, `benchmarks`, `import_header_aliases`, `import_tab_profiles`. Keyed by `code` (or a natural key), not `id`.
- Core CRM: `organizations`, `contacts`, `touchpoints` (every email, call, meeting, with its outcome), `email_messages`, `opportunities` (one open per contact), `reminders`, `events`, `campaigns`, `rfps`.
- Team: `team_members` (also the sign-in allowlist), `territory_assignments`.
- Import pipeline: `import_batches`, `import_rows` (staging).
- `audit_log` (added by `db/001`) and `email_templates` (added by `db/007`).

`id` columns are `generated by default as identity`. Foreign keys point at the reference tables by `code` and at `team_members.id` for owners.

**Views (21, all `v_*`)** are what `Repo` will read: `v_contacts`, `v_organizations`, `v_correspondence`, `v_reminders_due`, `v_pipeline`, `v_lead_funnel`, `v_funnel_by_cohort`, `v_kpis_by_quarter`, `v_channel_performance`, `v_event_performance`, `v_cold_call_performance`, `v_funded_aum_by_quarter`, `v_aum_by_segment`, `v_rfp_tracker`, `v_client_loyalty`, `v_benefit_groups`, `v_newsletter_list`, `v_wrong_emails`, `v_possible_duplicates`, `v_outcome_review_queue`, `v_import_results`. They respect row level security (an anonymous request returns no rows).

**Automation lives in triggers.** Writing a row does more than store it:
- `contacts_before_write`, `organizations_before_write`: normalize and fill the match keys (`name_key`, `email_key`, `email_domain`, `linkedin_key`, org `domain`) using the `norm_*` helpers, and apply `flag_rules`. The after-write triggers carry changes across (an organization's changes to its contacts, a contact's email change to its reminders).
- `touchpoints_before_write`: fills organization and owner from the contact, **refuses a new outbound email or call to a do-not-contact person** (raises an error the app must show), starts outbound emails as `NO_RESPONSE`, and rejects an outcome that does not fit the touch type.
- `touchpoints_after_write` calls `apply_outcome_rules`, which creates or closes reminders, moves the opportunity stage, adds to the newsletter, or sets do-not-contact, as the `outcomes` row says. Free-text outcome wording is matched to a code by `match_outcome` / `outcome_aliases` (used by the import).
- `opportunities_before_write` fills segment, state, source and owner from the contact and stamps the milestone date (`hot_on`, `funded_on`, …) when the stage changes; `opportunities_after_insert` adds the person to the newsletter. `rfps_after_write` logs a touchpoint and schedules reminders.
- `automation_enabled()` and `history_load()` switch the automation off while history is being loaded.

**Functions the app calls (RPC):** `confirm_outcome`, `complete_reminder`, `snooze_reminder`, `merge_contacts` (folds a duplicate into the kept contact, then deletes it), `process_import_batch`, `import_uploaded_table`, `check_upload_headers`, `rematch_outcomes`, `rebuild_follow_up_reminders`, `spread_overdue_follow_ups`, `flag_stale_opportunities`, `wake_snoozed_reminders`, `reapply_flag_rules`. All run with the caller's rights (security invoker), so row level security applies to them.

## Security model (db/001_auth_roles_audit.sql)

- **Who can sign in:** only people listed in `team_members` (active). `hook_before_user_created` refuses an account for any other email, so a stranger pressing "Sign in with Google" gets nothing. A confirmed sign-in is tied to its row by email (`link_team_member` trigger on `auth.users`).
- **Two-factor is required for everyone.** `is_team_member()` returns true only for a listed, active user whose session is `aal2` (password or Google, plus an authenticator-app code). Every policy calls it. `my_access()` lets the app ask, before 2FA, whether the user is on the list and whether 2FA is done.
- **Roles** (`team_members.access_role`): `member` reads, adds, edits and deletes all CRM data, including merging duplicates. `admin` additionally manages `team_members` (invite, change role, deactivate) and reads `audit_log`. Members can never change `team_members`, so nobody can promote themselves. During the build, all five people on the list are admin; set the builders back before handover.
- **Audit log:** a trigger on every table except `import_rows` writes who, when, which row, and the old and new values (only changed columns on update). A deleted row is kept in full, which is how a wrong delete or merge gets restored. Nobody can write to or delete the log through the API.
- **Dashboard settings this depends on** (Authentication section, needs Administrator role in the Supabase organization): Google provider with the OAuth client, URL Configuration (Site URL and redirect URLs for the Vercel site and localhost), Auth Hooks > Before User Created > `hook_before_user_created`, Multi-Factor > TOTP enabled. Invitation emails need custom SMTP (Authentication > Emails), planned as a Gaard Google Workspace mailbox; Supabase's default sender only delivers to project members.
- The SQL Editor and Table Editor run as `postgres` and bypass all of this.

## Outcome rules

Every logged email, call, meeting or reply carries an outcome, and the outcome decides what happens next. The rules live in two places that must stay the same: `REFERENCE.outcomes` in Section 1 of `index.html` (used by `Rules.applyOutcome`) and the `outcomes` table in the database (used by `apply_outcome_rules` when the database's own automation runs). Change both together. Jon's six reply outcomes are INTERESTED, NOT_NOW, NOT_INTERESTED, BOUNCED (wrong email), OUT_OF_OFFICE and UNSUBSCRIBE (do not contact). Outbound emails start as NO_RESPONSE.

"Next follow-up" is counted from the day the activity happened (an out-of-office reply uses its return date instead). Logging a new activity closes the contact's open follow-ups and schedules the next one from the new outcome.

| Code | Label | Next follow-up | Reminder | Moves stage to | Also |
|---|---|---|---|---|---|
| NO_RESPONSE | No response | 90 days | follow_up |  |  |
| OUT_OF_OFFICE | Out of office (auto-reply) | 14 days | ooo_follow_up |  |  |
| BOUNCED | Bounced / wrong email | 2 days | fix_contact_info |  | marks email wrong |
| WRONG_PERSON | No longer there / wrong person | 7 days | find_new_contact |  |  |
| REFERRED_INTERNALLY | Pointed us to a colleague | 3 days | referral_follow_up |  |  |
| NOT_NOW | Not now, check back later | 90 days | follow_up |  |  |
| HAS_ADVISOR | Already has an advisor | 180 days | follow_up | lost |  |
| NOT_INTERESTED | Not interested / no thank you | none |  | lost |  |
| UNSUBSCRIBE | Asked not to be contacted | none |  | lost | do not contact |
| INTERESTED | Interested, call scheduled | 7 days | post_call | call | adds to newsletter |
| NO_ANSWER | No answer | 7 days | follow_up |  |  |
| VOICEMAIL | Left voicemail | 7 days | follow_up |  |  |
| WRONG_NUMBER | Wrong number | 2 days | fix_contact_info |  |  |
| MET_AT_EVENT | Met at event, exchanged info | 3 days | event_follow_up |  |  |
| MEETING_AT_EVENT | Had a meeting at the event | 5 days | event_follow_up |  |  |
| INTRO_MADE | Introduction made | 3 days | referral_follow_up |  |  |
| REVIEW_HELD | Portfolio review held | none |  |  |  |
| CALL_HELD | Call held, next steps set | 14 days | post_call | call | adds to newsletter |
| HOT | Next steps: a proposal, or taking it to the board | 7 days | post_call | hot | adds to newsletter |
| READY_TO_ONBOARD | Wants to hire us, start onboarding | 14 days | onboarding_task | onboarding | adds to newsletter |
| NOT_A_FIT | Not a fit after the call | none |  | lost |  |
| RFP_SUBMITTED | RFP response submitted | 30 days | follow_up |  |  |
| RFP_FINALIST | RFP finalist, presentation | 7 days | post_call | call | adds to newsletter |
| RFP_WON | RFP won | 14 days | onboarding_task | onboarding | adds to newsletter |

The estimated revenue on an opportunity uses an assumed fee of 0.45% of AUM (`settings.assumed_fee_rate`); it is no longer editable in the app.

## Changing the database

- Each change is a new numbered file in `db/` (`001_…`, `002_…`), written to be safe to run twice, wrapped in `begin; … commit;`, and run by hand in the Supabase SQL Editor. Never edit a file that has already been run; add the next number.
- Keep every table under row level security with policies that call `is_team_member()` / `is_admin()`. A new table needs RLS enabled, policies, and the `zz_audit` trigger (see `db/001`).
- New functions that bypass RLS (`security definer`) must check `is_team_member()` first and set `search_path`.
- `db/base/` plus `db/gaard_crm_install.sql` are the base schema; the numbered files in `db/` are the
changes on top, run by hand in order. A base change (rare) is a new file in `db/base/` followed by
`bash db/scripts/build_install.sh`.


## Status

- **Done:** the full front end. The Supabase schema, views and automation, with fictional data. Row level security on every table. `db/001` (roles, 2FA, audit log, allowlist), `db/002` (RFP log columns), `db/003` (the in-person rule), `db/004` (relinking team members to their current accounts), `db/005` (`apply_changes`), `db/006` (three-digit years; `parse_loose_date` now refuses years before 1900), `db/007` (the shared `email_templates` table), `db/008` (removes `contacts.is_decision_maker`, which no sheet of Jon's has; `v_contacts` and `v_organizations` are rebuilt without it). `db/009` (`team_members.booking_url` and `set_my_booking_url()`, so each person sets their own booking link). The "Don't cold email these addresses" list in Settings (`flag_rules`; matching contacts are labelled No cold email (in person only), left out of the mail merge, and given a "Reach out in person" reminder). Import reads client replies, pasted as text or as a screenshot, into Jon's six outcomes.
- **Settings** is opened from the account menu at the top right (which holds only Settings and Sign out), not the sidebar. It holds only the account (name, email, role, change password) and the No cold email list. Email templates are a tab under Follow-ups (`Views.templates`), stored in the shared `email_templates` table (db/007). `Live.OPTIONAL` lists tables from later db/ files: until such a file has been run the app opens without the table, and templates fall back to the browser (`localStorage` key `gaard_templates`). On first sign-in with the table empty, the app fills it from `MERGE_TEMPLATES`.
- **Mail merge from Contacts:** the contacts sheet has a tick box per row (hover the row number) and one for the page; the ticks (`UI.contacts.sel`) survive paging and filters. Tick boxes there and on the batch screen work like a sheet (`bindDragTick`): press and drag, and the rows between the box pressed and the mouse take the new state (dragging back releases the rows passed); Shift-click sets a range. The batch screen has no filter bar and ignores filters set elsewhere. "Mail merge" opens Follow-ups > Send as a batch with source `picked` (those people only, whatever the letter's segment; the cold introduction is chosen when none of them was written to before). "Mark as sent" logs one email each, outcome No response, schedules the follow-up, and clears the pick. "Send N from my Gmail" sends the letters from the signed-in person's own Gmail (`Gmail`, Google Identity Services, scope `gmail.send` only, so the CRM cannot read the mailbox): one at a time, about a second apart, each person marked Sent or Not sent, and the ones sent are logged as No response. "Send a test to myself" sends the previewed letter to the sender. Letters can use {{booking_link}}: each person pastes their Google Calendar appointment page in Settings (stored as `team_members.booking_url` through `set_my_booking_url()`, db/009), and it is filled with the sender's link; merge fields also accept Jon's style, e.g. {{First Name}}. It needs `GMAIL_CLIENT_ID` (the public client ID of "Gaard CRM Web"), the Gmail API enabled and the gmail.send scope added in that Google Cloud project, and the site origins listed under the client's Authorized JavaScript origins; real sends are refused in demo mode. Copying the letters and "Mark as sent" remain under "Or send from your own email by hand". Jon's own Apps Scripts (Google's Mail Merge sample) send from a Gmail draft with {{Column}} tags and write the date into an "Email Sent" column; the second sends as the founder, Jonathan Brogaard (jonathan@gaard.capital, BCC and Reply-To him).
- **Dashboard** is one screen of numbers and charts, the way a Salesforce or Power BI dashboard reads (the work is on Follow-ups, the detailed tables on KPIs): five numbers with the change against the period before (to contact, new AUM funded, new clients, pipeline, response rate; its own period pick, no filter bar), pipeline by stage, AUM funded by month (last 12), new leads by channel, the funnel from email to client, and what is coming up in 14 days. **Notices live under the bell** in the top bar on every page (replies to confirm, outreach that went nowhere, overdue follow-ups, RFPs due within 7 days), built in `renderNav`.
- **Follow-ups (One at a time)** is a compact table with no filter bar: due, contact and organization, type, why, and Log activity / Done / Move on one line; a search box beside the buckets. Clicking a row opens the contact.
- **Contact page** is one card in pairs: First and Last name, Title and Phone, Email and LinkedIn, How we met and Newsletter, then an Organization section (Organization and Website, City and State, AUM and Segment), then Notes. The right column holds Next follow-up and the Opportunity. AUM is the opportunity's or the prospect figure, and the organization's reported AUM until one is recorded (the contacts sheet shows the same). The opportunity has no owner to choose; the audit log records who changed it. Stored values change in place (click, then Enter, a choice, or Escape to undo) through the same `saveCell` the sheet uses. What is counted from activity (initial outcome, first and last touch) is not repeated there: the Activity list shows it. Phone numbers are stored as 801-555-0123 (`fmtPhone`). The Edit button still holds name, email status, do not contact and the in-person flag.
- **Events page** is one screen, read like a dashboard (`.ev-page`; long lists scroll inside their box): six totals, people met per event, in person against virtual, events against cold email, then every event beside the people met at the chosen one (`#/events?ev=<id>`). People met at an event are the contacts with a touchpoint at it plus those whose `source_event_id` is it. The search box finds a person and lists every event they were met at. Campaigns moved to the KPIs page. Jon's own event list is the "Event Tracker" sheet of Marketing_ROI_Sample.xlsx (23 events of 2026, with counts but no names); `db/mock/jon_event_tracker_2026.sql` loads it into `events`, his counts kept in `notes`.
- **Activity** (touchpoints) on a contact or organization page: `openActivity(contactId, tp)` logs a new one or edits or deletes an existing one. The person signed in is the owner (who logged it); there is no owner choice. Outcomes are grouped (`OUTCOME_GROUPS`) and filtered to the activity type, "No outcome" is allowed, and an outcome that schedules a follow-up shows its date, saved as `follow_up_on`. Deleting an activity dismisses the follow-up it scheduled. The time is the moment it is logged and cannot be edited; times show to the minute (`whenLabel`), and rows from the old sheets carry a date only, stored at noon. A follow-up date must be from tomorrow on. Only the contact's latest activity sets the next follow-up: editing an older one changes the history but leaves the schedule alone (`Repo.touchpoints.update` re-runs the rules only for the latest). The Next follow-up card shows the date and the first line of the reason, never the letter itself. Moving a follow-up by hand (the Next Reach out Date cell, or Move on Follow-ups) also moves the latest activity's "Next follow-up" (`syncFollowUp`), so the two always agree; the activity's own date stays as it happened. "Initial Outcome" in the contacts sheet is the outcome of the first outreach, by design (Jon's column); later outcomes show in Activity.
- **The live database:** the page opens on a sign-in screen (the `Live` and `Gate` objects at the end of `index.html`). Email and password through Supabase Auth, then a TOTP code from an authenticator app, enrolled on first sign-in; `my_access()` checks the team list; then `Live.load` reads every table in `Live.TABLES` (a thousand rows per request) and `Store.useLive` swaps them in for the snapshot. Nothing from the live database goes into browser storage. "Use the demo data instead" keeps the snapshot mode (remembered in `localStorage` key `gaard_mode`).
- **Saving:** in live mode every `Store.commit` and every undo calls `Live.save()`, which diffs the Store against the last saved copy (`Live.shadow`) and sends the inserts, changed columns and deletes, parents first, to `apply_changes()` in one transaction. The top bar shows "Saving…" while a save is on its way and "All changes saved" for a few seconds after (`renderSideFoot`, kept under its old name). That function sets `app.seeding` for the transaction, so the database's automation triggers stand down: the front end's `Rules` already did that work and the database doing it again would duplicate reminders. Keep the two rule sets in step. If the database refuses a change (row level security, the do-not-contact block, a constraint), the app shows the reason and reloads from the database. Inserts leave out empty (null) columns so the database defaults apply (several columns are `not null default …`). New ids are `max + 1` in the browser, so two people adding rows at the same moment can collide; the second save then fails and reloads.
- **Accounts without email setup:** Supabase's default mailer only reaches members of the Supabase organization, and the dashboard's URL settings need the Administrator role. Until both are sorted, a builder with SQL Editor access can confirm an account (`update auth.users set email_confirmed_at = now() where email = …`) or set a temporary password (`encrypted_password = extensions.crypt('…', extensions.gen_salt('bf'))`); the person then changes it from the account menu. Someone who loses their authenticator app is reset with `delete from auth.mfa_factors where user_id = …`.
- **Sign-in and the team:** "Sign in with Google" (`signInWithOAuth`, back to the same page; it does not work from a file opened directly) or email and password, then the TOTP code. The Before User Created hook (`hook_before_user_created`) is on, so an email that is not on `team_members` cannot create an account; "Allow new users to sign up" stays on, because turning it off would also stop listed people's first Google sign-in. URL Configuration lists the Vercel site and localhost. Settings > Team (admins only) adds a person to `team_members` and nothing is emailed: they sign in with Google with that address, and the database links the account (status Added until `auth_user_id` is set, then Joined); Copy invite puts a ready message on the clipboard for the admin to send. Remove sets `is_active = false`. Staff sign in with Google only: "Create an account" is gone from the sign-in page because Supabase's confirmation email cannot reach people outside the Supabase organization without custom SMTP, and Jon prefers not to change gaard.capital's DNS. Existing email-and-password accounts still work. `supabase/functions/invite-member` (deployed, Verify JWT off) can send Supabase's invite email once custom SMTP exists; nothing calls it today.
- **Not built yet:** a screen to read the audit log (use the SQL Editor meanwhile).
- **Not connected yet:** reading replies from a mailbox (they are pasted or screenshotted into Import; a shared outreach@ inbox is under discussion with Jon) and calendar invites (deliberately: when built, an invite is drafted from the thread and a person confirms it before it goes).
- **Open questions for Jon:**
  - Reading screenshots (and very messy pasted emails) with AI needs an Anthropic API account paid by Gaard (a few cents per image), the live Supabase connection (the key must sit server-side, in an Edge Function), and Jon's consent to send that content to the Claude API. Jon may not want to pay; the free fallback is in-browser OCR plus the rule-based reply matching.
  - Universities and referral-first organizations: confirm the "in person only" flag (no cold email, reminder to reach out in person) is what Jon means by "do not contact" before a send, as distinct from the `UNSUBSCRIBE` outcome (the person asked us to stop).
- **Known issue:** at phone width the whole app is wider than the screen (top bar and cards run off the right edge).
- **Before real client data goes in:** every table's demo rows must be removed while keeping the reference and configuration tables and `team_members`; upgrade Supabase to a plan with daily backups; publish the Google OAuth app and move it to Gaard's Workspace.
