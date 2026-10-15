# Importing Jon's workbook

How the outreach workbook (ten tabs, one Google Sheet) went into the CRM on Oct 3, 2026, and how to
run the same import again for a new tab, a refreshed tab, or a batch of new prospects. Everything
runs in the Supabase SQL Editor with a Developer login; nothing is installed on anyone's computer.

The functions are in `db/base/20261003000100_workbook_import.sql` and
`..._300_review_helpers.sql`; the per-tab settings are rows in `import_tab_profiles`
(`..._400_workbook_reference_rows.sql`).

## One tab, start to finish

1. **Prepare the sheet** (see the per-tab notes below), download the tab as CSV.
2. **Upload it as a table.** Supabase Table Editor > New table > Import data from CSV. Name the table
   after the tab, for example `upload_master_2025`. Keep every column as text. The upload is staging:
   it is dropped at the end.
3. **Check the headers.** In the SQL Editor:
   ```sql
   select * from check_upload_headers('upload_master_2025', 'Master List 2025');
   ```
   Every column shows what it maps to. `NOT RECOGNIZED` means the words will be kept in the contact
   notes; rename the header in the sheet, or add a row to `import_header_aliases`, and re-upload.
4. **Import.**
   ```sql
   select import_gaard_tab('upload_master_2025', 'Master List 2025', p_owner_id => <your team_members.id>);
   ```
   The result says how many rows became new contacts, existing contacts, needs-review rows, skipped
   rows and errors, plus the batch id. `p_run_automation` is false by default: the import is a history
   load, so facts are recorded (touches, outcomes, bounced emails, do-not-contact flags) but no
   reminders are opened and the do-not-contact block does not reject old history. Use
   `p_run_automation => true` only for a fresh batch of prospects you are about to work.
5. **Review.** `select * from v_import_results where batch_id = <id>` lists each row's result;
   `v_outcome_review_queue` holds touches whose outcome text the matcher could not place.
6. **Drop the upload.** `drop table upload_master_2025;`

For a sheet that is not one of the known tabs, call `import_uploaded_table()` directly: it takes the
segment, channel, touch type, default outcome, follow-up days, tags, name matching and header map as
arguments; `import_gaard_tab()` is the same call with those values read from the tab's profile.

## After all tabs are in

* **Outcome wording.** Add Jon's phrasings to `outcome_aliases` (`force_review = true` for a phrase that
  only hints, such as "misc" or "should follow up"), then `select rematch_outcomes();`. It re-reads every
  touch still in review, confirms exact matches, suggests the rest, and rebuilds the follow-ups. On
  Oct 3 this took the queue from 275 rows to 2.
* **Duplicates.** `v_possible_duplicates` lists look-alike people and organizations;
  `select merge_contacts(<keep id>, <remove id>);` moves every touch, reminder, opportunity and email
  to the kept row and deletes the other. The audit log keeps the removed row in full.
* **Follow-ups.** `select rebuild_follow_up_reminders();` opens one follow-up per organization (or
  individual) from the latest confirmed touch: explicit "next reach-out" dates first, then the cadence
  from the outcome rules. `select spread_overdue_follow_ups(6);` re-dates an overdue backlog evenly
  over the next six weeks of working days.
* **Flags.** `select reapply_flag_rules();` after changing `flag_rules` (do-not-contact domains,
  universities, competitors).

## The tabs

| Tab | Segment | What it is and how it imports | Prepare the sheet first |
|---|---|---|---|
| Affiliates | Affiliate | Main table of the Affiliates tab (rows 1-51): partners GAARD reaches out to. "Services" becomes the organization sub-type. (tag `affiliate`) | Export rows 1 to the "data ends" row only. The four small lists further down the tab are separate CSVs (see the Affiliates: ... profiles). |
| Affiliates: Fundraising Software | Affiliate | The "Fundraising Software" list lower on the Affiliates tab. (tag `affiliate`) | Headers: Organization, Contact, Email, Website, LinkedIn. Put a real header on every column before exporting. |
| Affiliates: Nonprofit Consulting | Affiliate | The "Nonprofit Consulting" lists lower on the Affiliates tab. (tag `affiliate`) | One of these lists has an organization name typed where a header should be: replace it with "Organization". |
| Affiliates: Consulting | Affiliate | The "Consulting" list lower on the Affiliates tab. (tag `affiliate`) |  |
| Individuals and Small Biz | OCIO | Individuals (OCIO / robo) and small businesses. The "Type" column picks the segment per row (Individual, Robo, Small Biz / 401(k)).  | Make sure every row has a Type. Rows without one are treated as OCIO individuals. |
| Benefit Groups | Affiliate | Benefits brokers and consultants who can introduce 401(k) plans. Plans Served, Commissions, Shared Employers and Advertises Retirement are kept on the organization. (tag `benefit_group`, `401k_channel`) | Commissions may be a formatted dollar amount; that is fine. |
| Wrong Emails | Nonprofit | Contacts whose email bounced. Every row is marked bounced (email_status) and gets a "fix contact info" reminder. (every row is `BOUNCED`) | The top table is a FILTER of the master list, so the master import already marks those; import this tab only for rows that exist nowhere else (the second table). Rename the "a" header to "Outcome" or leave it (mapped here). |
| Master List 2025 | Nonprofit | Master List Cold Nonprofits 2025: 2025 outreach plus, in the NEW CONTACT columns, the person re-sourced for 2026. Each row becomes the 2025 contact and, when the NEW columns are filled, a second contact at the same organization (no 2026 touch yet: the 2026 tab brings it).  | Type "Date Sourced" into the blank A1 header. Rename the second First Name / Organization / Website / NOTES headers to "NEW First Name", "NEW Organization", "NEW Website", "NEW NOTES". Export rows 1 to "data ends" (about 1,800) and columns A to W only; delete the color legend and anything to the right. |
| Cold Nonprofits 2026 | Nonprofit | Cold Nonprofits 2026: the re-sourced contacts and their 2026 outcome (the dropdown values are all recognized). "Response Notes" is kept as the reply text.  | Export columns A to M only (the color legend in P-Q and the formula note in X are not data). |
| Next Step Outreach | Nonprofit | Main table of the Next Step Outreach tab: people who responded and were moved out of the cold list. Initial Outcome, Status, correspondence, Next Reach out Date, newsletter flag and Active/Dorm are all kept. (follow-up 90 days after the last touch when the sheet gives no date; tag `next_step`) | Type "Contacted Date" into the blank A1 header. Export rows 1 to "data ends" only. Each titled section below is its own CSV (profiles "Next Step: ..."). |
| Next Step: Limited CRM Notes | Nonprofit | Section "Limited CRM Notes" of the Next Step tab. (follow-up 90 days after the last touch when the sheet gives no date; tag `next_step`, `limited_crm_notes`) | Export the section header row and its rows only. |
| Next Step: No Endowment | Nonprofit | Section "No Endowment / No Money - Check back in 6-12 months". Rows without a next reach-out date get one 9 months after the last contact. (every row is `NOT_NOW`; follow-up 270 days after the last touch when the sheet gives no date; tag `next_step`, `no_endowment`) | Export the section header row and its rows only. |
| Next Step: Has Manager | Nonprofit | Section "Have Endowment and Manager -> Check back in 12 months". Rows without a next reach-out date get one 12 months after the last contact. (every row is `HAS_ADVISOR`; follow-up 365 days after the last touch when the sheet gives no date; tag `next_step`, `has_manager`) | Export the section header row and its rows only. |
| Next Step: Community Foundations | Nonprofit | Section "Community Foundations" of the Next Step tab. (follow-up 180 days after the last touch when the sheet gives no date; tag `next_step`, `community_foundation`) | Export the section header row and its rows only. |
| Next Step: Public Agency | Other | Section "Public Agency -> Connect once listed". (every row is `NOT_NOW`; follow-up 180 days after the last touch when the sheet gives no date; tag `next_step`, `public_agency`) | Export the section header row and its rows only. |
| Next Step: Radar | Nonprofit | The RADAR list at the bottom of the Next Step tab (Contact Name, Email, Organization, with SENT / need to email in the first column). (follow-up 90 days after the last touch when the sheet gives no date; tag `next_step`, `radar`) | Type "Status" into the blank header above the SENT / need to email column. Export the header row and its rows only. |
| Onboarded | Nonprofit | Onboarded clients: each row becomes a contact, its outreach touch, and an opportunity in the onboarding or funded stage (Sent Onboarding, Account Funded Date, AUM = funded AUM). "Channel" sets how the client was found. (tag `client`) | If some clients are individuals or 401(k) plans, add a "Segment" column (Individual / 401(k) / Nonprofit); otherwise every row is a nonprofit. |
| Customer Loyalty | Nonprofit | Customer Loyalty: existing clients matched by name to the Onboarded contacts; Thanksgiving Card and Referral Check-in dates become reminders (past dates are logged as done). (matched by name and organization (no email column); tag `client`) | Delete rows 1-6 so the row with Client Type / Name / Contact / Mailing Address is the header. Rename the second "Referral Check in 2" to "Referral Check in 3". For an individual client, put the person in Contact (Name may repeat it). |
| Small Biz - NEW | 401(k) | Small Biz - NEW: the 401(k) prospect list. Batch becomes a campaign, DateSent the outreach date, DateDelivered the sourced date, Participants and PlanAssets the organization size. (tag `small_biz_list`) | Delete the empty column L. Both "Note" and "Notes" are kept. |

Every imported row keeps `legacy_ref = '<tab> / row <n>'` on the contact, organization and touch, so a
row in the old workbook can always be found in the CRM and the other way round.

## What never goes in the repo

The uploaded tables, the CSVs they came from, and the Supabase error popups (they print whole rows).
`db/mock/` holds mock data only.

*Rebuilt on 2026-10-14 from the live schema and the Oct 4 team brief; the Oct 3 original of this
document was lost with the first repo zip.*
