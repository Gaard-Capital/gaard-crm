# Connecting the dashboard to the database

The dashboard (`index.html`) needs two values from Project Settings > API, the project URL and the
publishable key, plus each person's own login. The publishable key is meant to sit in a browser page;
the row-level security rules are what protect the data: a login that is not an active row in
`team_members` sees nothing, and since `db/001` the login must also have passed the second factor.
The secret key and the database password are never used by the app.

```js
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm'
const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY)
await supabase.auth.signInWithPassword({ email, password })
const { data: me } = await supabase.rpc('my_access')   // member?, id, name, role, aal (db/001)
```

## Every screen reads a view (no joins in the app)

| Screen | View | Call |
|---|---|---|
| This week's to-do | `v_reminders_due` | `.select('*').order('due_on')`, bucket in `due_bucket` |
| Master list | `v_contacts` | `.select('*').ilike('full_name', '%q%').range(0, 49)` |
| Organizations | `v_organizations` | same; `rollover_suggested` = try someone else there |
| A person's history | `v_correspondence` | `.eq('contact_id', id).order('occurred_at', { ascending: false })` |
| Review queue | `v_outcome_review_queue` | `.select('*')` |
| Pipeline | `v_pipeline` | `.order('stage_sort').order('opened_on', { ascending: false })` |
| KPIs and charts | `v_kpis_by_quarter`, `v_channel_performance`, `v_funnel_by_cohort`, `v_funded_aum_by_quarter` | `.select('*')` |
| Clients | `v_client_loyalty` | `.select('*')` |
| Benefit groups | `v_benefit_groups` | `.select('*')` |
| Import results | `v_import_results` | `.eq('batch_id', id)` |
| Events | `v_event_performance` | `.select('*').order('start_on', { ascending: false })`; the sheet's own counts are `people_met_reported`, `responses_reported`, `meetings_reported`, `clients_won_usd` (db/012) |
| RFPs | `v_rfp_tracker` | `.select('*').order('due_on')`; the RFP log's columns `reference_number`, `approved_for_submission`, `reviewed_by`, `reviewed_on`, `terms`, `decision_result`, `decision_notes` are at the end (db/012) |
| Data health (Settings) | `v_data_check_latest` | `.select('*').order('sort_order')`: one row per check with `status` (ok / warn / fail), `count`, `previous`, `note` and `sample` (the first five rows behind it). `run_status` and `summary` describe the run; `ran_at` says when. History: `v_data_check_history` (db/013) |

## Every button calls a function (the rules run inside the database)

| Button | Call |
|---|---|
| Save what changed (the app's write path since `db/005`) | `supabase.rpc('apply_changes', { p_changes: [{ table, op: 'insert' \| 'update' \| 'delete', id, row }] })` |
| Done | `supabase.rpc('complete_reminder', { p_reminder_id, p_by: me.id })` |
| Snooze | `supabase.rpc('snooze_reminder', { p_reminder_id, p_until: '2026-11-03' })` |
| Confirm suggested outcome | `supabase.rpc('confirm_outcome', { p_touchpoint_id, p_confirmed_by: me.id })` |
| Confirm a different outcome | add `p_outcome_code: 'NOT_NOW', p_follow_up_on: '2027-01-15'` |
| Log an email or call | `supabase.from('touchpoints').insert({ contact_id, touch_type: 'email', touched_at, outcome_code, notes, owner_id: me.id })` |
| Move a deal | `supabase.from('opportunities').update({ stage: 'hot' }).eq('id', id)` |
| Mark funded | `.update({ stage: 'funded', funded_aum })` |
| Merge two people | `supabase.rpc('merge_contacts', { p_keep, p_remove })` |
| Paste in prospects | upload the rows as a table, then `supabase.rpc('import_uploaded_table', { p_table, p_label, ... })`; show `v_import_results` |
| Re-run the outcome matcher | `supabase.rpc('rematch_outcomes')` |
| Run the data check now | `supabase.rpc('run_data_checks')` returns `{ status, summary, checks: [{ code, status, count }] }`; then read `v_data_check_latest` (db/013) |
| Import the Events sheet / the RFP log | upload the CSV as `upload_events` / `upload_rfps`, then `supabase.rpc('import_gaard_tab', { p_table: 'upload_events', p_tab: 'Events' })` (or `'RFPs'`); the result lists `skipped` rows with reasons and, for RFPs, `responses_to_check` (db/012) |

Outcome dropdowns come from `select code, label, applies_to from outcomes where is_active`, filtered
by the touch type. Reminder types from `reminder_types`, channels from `channels`.

## Deploying

The project URL and publishable key go into Vercel environment variables, not into the repo. In
Supabase, Authentication > URL Configuration needs the Vercel URL as Site URL and in Redirect URLs.
Before real use: Pro plan (daily backups, no pausing after seven idle days).

*Rebuilt on 2026-10-14 from the Oct 4 team brief and the current schema.*
