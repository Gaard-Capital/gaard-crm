# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Before editing (team rules)

Several people edit this repo, and an outdated copy pushed over a newer one erases their work.

- Always run `git pull` before editing. If it brings in changes, tell the user their copy was out of date.
- Bump the `build-version` meta tag near the top of `index.html` on every change. Format `YYYY-MM-DD.N`, where N counts the changes made that day.
- Edit only what's needed; never replace whole files with older copies.
- Commit and push small changes with git (pull, commit, push). Never upload files through the GitHub website: it silently overwrites newer work.
- Never commit real client data or the Supabase secret key.

## What this is

A single-file prototype CRM for GAARD Capital (outreach, follow-ups, pipeline, KPIs). The whole app is `index.html`: plain HTML, CSS and JavaScript. No framework, no dependencies, no build step, no tests, no linter. The only network request is a Google font. It is deployed by GitHub Pages straight from `main` at the repo root (https://gaard-capital.github.io/gaard-crm/).

All data is fictional: emails use the reserved `.example` domain and phones the 555-01xx range. Keep any new sample data within those reserved ranges.

## Running it

```bash
python3 -m http.server 8765   # then open http://localhost:8765/index.html
```

Opening the file directly also works; serving it keeps browser storage behaving normally. A change is one edit and a refresh. Edits made in the UI persist in `localStorage` under `gaard_crm_db_v1`; reset them from Settings (or clear that key) to get back to the embedded snapshot.

## Working with index.html

The file is ~2.3 MB but only ~4,500 lines, because the embedded data snapshot (`const DB_SNAPSHOT = {...}`, in Section 2 around line 650) sits on one enormous line. Don't read the file whole or print that line: read by line range, and when grepping, exclude or truncate long lines (e.g. pipe through `cut -c1-200`).

Navigate by the section banners (`SECTION 1.` … `SECTION 8.`) and the view banners (`/* ===== Contacts =====`). The order is: CSS, then

1. **Reference data**: segments, channels, touch types, outcomes, and the rule each outcome triggers. These are data rows, not logic, so wording changes go here.
2. **Embedded data**: `DB_SNAPSHOT`, exported from the Postgres tables in the separate `gaard-crm-db` repo, stored column-first (`{ c: [cols], r: [[row], ...] }`). `hydrate()` turns it into row objects, adds the generated columns the DB computes (`full_name`, `email_key`, `linkedin_key`), and shifts every `*_at` / `*_on` / `*_until` date by the gap between `DB_ANCHOR` and today (toggle with `SHIFT_DATES_TO_TODAY`) so the demo always looks current.
3. **Data access**: `Persist` (localStorage), `Store`, `MERGE_TEMPLATES`, and `Repo`.
4. **Metrics**: everything the dashboard/KPI screens count.
5. **Intelligence**: the import pipeline (column mapping, duplicate detection, outcome wording, AUM classification).
6. **Rules**: outcome-driven follow-up scheduling and business-day arithmetic.
7. **Views**: `UI` (per-screen UI state), shared helpers, then one `Views.<name> = { title, render(params), mount(el, params) }` per screen.
8. **Router and boot**: hash routing, nav, tabs.

## Architecture rules that span the file

- **`Repo` is the seam to the real database.** Screens read only through `Repo`; each method carries a comment naming the SQL query/view it stands in for. Moving to Supabase means replacing `Repo` method bodies (and dropping Section 2) with no screen changes. Keep new reads in `Repo` with the matching SQL comment rather than touching `Store.state` from views.
- **All writes go through `Store.commit(label, mutator, { undoable, silent })`.** It snapshots for undo (last 12), bumps `Store.version`, debounces persistence, re-renders every subscriber, and shows a toast with the label (plus an Undo action). Mutating `Store.state` directly skips all of that.
- **Caching is keyed on `Store.version`.** `memo(fn)` caches until the next commit, so derived indexes and metrics are recomputed automatically; anything memoized must only depend on store state.
- **Nothing is stored twice.** Every figure is computed from touchpoints, opportunities and reminders; there is no separate reporting table to keep in sync.
- **Rendering is whole-view.** `render()` rebuilds `#main` from `view.render(params)` as an HTML string, then calls `view.mount()` to attach listeners, restoring scroll positions and the focused input by `id`. Inputs that must keep focus while typing need a stable `id`. Escape interpolated values with `esc()`.
- **Routing** is hash-based: `#/name?k=v`, with `#/contacts/<id>` and `#/organizations/<id>` aliased to the `contact` / `organization` record views. Use `href(name, params)` / `go(name, params)`. Unknown names fall back to the dashboard. `NAV` lists the sidebar entries, `NAV_OF` maps sub-screens to their sidebar owner, and `TABS` groups screens shown as tabs (e.g. Pipeline under KPIs, Organizations/Correspondence under Contacts, the batch mail merge under Follow-ups). A new screen needs a `Views` entry and either a `NAV` row or a place in `NAV_OF`/`TABS`.

## Not connected yet (by design)

Sending email (the merge screen fills letters and records them as sent), calendar invites, and the live database. These are documented in the Settings screen; keep that list accurate if one of them changes.
