# db/

Everything on the database side of the CRM, in the order it is applied.

| Path | What |
|---|---|
| `base/` | the base schema: migrations 1 to 6 (Sep 26, 2026) and 7 to 10 (Oct 3: the workbook import, client views, review helpers, reference rows) |
| `gaard_crm_install.sql` | the same ten files in one, for an empty project (rebuilt by `scripts/build_install.sh`) |
| `001_...` to `005_...` | changes made since, run by hand in the SQL Editor, in order; new changes go here as `006_...`, `007_...` |
| `tests/` | `automation_tests.sql` (41 checks) and `workbook_import_test.sql` (25 checks); both roll themselves back, safe on real data |
| `docs/` | `database.md` (the write-up), `import_playbook.md` (how Jon's workbook was imported and how to import a tab again), `dashboard_connection.md` (views and functions the app uses) |
| `mock/` | fictional data only: `seed.sql` (or the four `seed_parts/`), the CSV exports, the import demo |
| `scripts/` | `generate_mock_data.py`, `build_install.sh` |
| `optional/` | `scheduled_jobs.sql` for pg_cron |

## Fresh project

1. Paste `gaard_crm_install.sql` into the SQL Editor and run it.
2. Run `001_auth_roles_audit.sql` to `005_apply_changes.sql`, in order.
3. Demo data, if wanted: `mock/seed.sql` with psql, or `mock/seed_parts/` 1 to 4 in the SQL Editor.
4. `tests/automation_tests.sql` and `tests/workbook_import_test.sql` should both end with `failed = 0`.

## Changing the structure

A new numbered file in this folder, run by hand; applied files are never edited. A change to the base
itself (rare) is a new file in `base/` plus `bash scripts/build_install.sh`.

## Never in the repo

Client data, uploaded CSV tables, the secret key, the database password. Everything in `mock/` is
fictional (`.example` addresses, 555-01xx phones).

*Base migrations 7 to 10, the install file, the docs and `workbook_import_test.sql` were rebuilt on
2026-10-14 from the live schema and the Oct 4 team brief.*
