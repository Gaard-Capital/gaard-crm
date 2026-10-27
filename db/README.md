# db/

Everything on the database side of the CRM, in the order it is applied.

| Path | What |
|---|---|
| `base/` | the base schema: migrations 1 to 6 (Sep 26, 2026) and 7 to 10 (Oct 3: the workbook import, client views, review helpers, reference rows) |
| `gaard_crm_install.sql` | the same ten files in one, for an empty project (rebuilt by `scripts/build_install.sh`) |
| `001_...` to `013_...` | changes made since, run by hand in the SQL Editor, in order; new changes go here as `014_...`, `015_...`. `012` is the Events / RFP sheet importers (Jon's Event ROI Tracker and RFP Log, as they are); `013` is the weekly data check; `015` connects a person's own Claude. **`016_clear_demo_data.sql` is not part of the setup**: it empties the CRM records at go-live, has a guard line to uncomment, and is run once, by Jon (CLAUDE.md > Going live with real data) |
| `tests/` | `automation_tests.sql` (41 checks), `workbook_import_test.sql` (25), `events_rfps_test.sql` (44, db/012) and `data_checks_test.sql` (14, db/013: scrambles a copy of the data and checks the run catches it); all roll themselves back, safe on real data |
| `docs/` | `database.md` (the write-up), `import_playbook.md` (how Jon's workbook was imported and how to import a tab again), `dashboard_connection.md` (views and functions the app uses) |
| `mock/` | fictional data only: `seed.sql` (or the four `seed_parts/`), the CSV exports, the import demo |
| `scripts/` | `generate_mock_data.py`, `build_install.sh`, `events_rfps_fixtures.py` (the upload tables `events_rfps_test.sql` embeds) |
| `optional/` | `scheduled_jobs.sql` for pg_cron: snoozed reminders, stale deals, and the Monday data check |

## Fresh project

1. Paste `gaard_crm_install.sql` into the SQL Editor and run it.
2. Run `001_auth_roles_audit.sql` to `013_data_checks.sql`, in order.
3. Demo data, if wanted: `mock/seed.sql` with psql, or `mock/seed_parts/` 1 to 4 in the SQL Editor.
4. Every file in `tests/` should end with `failed = 0`.

## The weekly data check (013)

`select run_data_checks();` runs seventeen checks and records the result in `data_check_runs`; the latest
run is `v_data_check_latest` (one row per check), the history `v_data_check_history`. Hard checks must be
zero: a touch, deal or reminder filed under a different organization than its person, a date outside 1990
to next year, a funded deal without a date or amount, a table without row level security or without the
audit trigger, an id counter behind the rows. Drift checks are compared with the previous run, because a
few are normal (an email that does not carry the person's name, an email domain that is not the
organization's website, look-alike duplicates): a jump since last week is the signal. Every run also
records the row count of every table and, from the audit log, who added, changed and deleted how many
rows since the previous run. With pg_cron on (`optional/scheduled_jobs.sql`) it runs every Monday on
its own. Anything it flags comes with the first five rows and, where there is one, the one-line fix.

## Changing the structure

A new numbered file in this folder, run by hand; applied files are never edited. A change to the base
itself (rare) is a new file in `base/` plus `bash scripts/build_install.sh`.

## Never in the repo

Client data, uploaded CSV tables, the secret key, the database password. Everything in `mock/` is
fictional (`.example` addresses, 555-01xx phones).

*Base migrations 7 to 10, the install file, the docs and `workbook_import_test.sql` were rebuilt on
2026-10-14 from the live schema and the Oct 4 team brief.*
