#!/usr/bin/env python3
"""Fictional Events, Event attendees and RFP sheets (including Jon's Event ROI Tracker and RFP Log
header rows), written as CSVs and as the upload tables Supabase would create from them, under
db/tests/fixtures/events_rfps/. The SQL is embedded in db/tests/events_rfps_test.sql; regenerate and
paste it there after changing the rows.

    python3 db/scripts/events_rfps_fixtures.py
"""
import csv
import pathlib

OUT = pathlib.Path(__file__).resolve().parents[1] / "tests" / "fixtures" / "events_rfps"
OUT.mkdir(parents=True, exist_ok=True)

TABS = {
    "events.csv": (
        ["Event", "Date", "Type", "In Person / Virtual", "Host", "Location", "Cost", "Attendees", "Contacts Made",
         "Who Attended", "Notes", "Worth it?"],
        [
            ["Utah Nonprofits Association Conference", "Oct 3-5, 2025", "Conference", "In person", "Utah Nonprofits Association",
             "Salt Lake City, UT", "$1,250", "400", "18", "Test Owner", "Good turnout, sponsor table", "Yes"],
            ["Community Foundation Roundtable", "11/12/2025", "Roundtable", "Virtual", "Philanthropy West", "Zoom", "0", "35",
             "6", "", "Follow up with the moderator", ""],
            ["Idaho Business Benefits Workshop", "2/20/26 - 2/21/26", "Workshop", "", "Boise Chamber", "Boise, ID", "$300", "60",
             "", "Test Teammate", "", "Maybe"],
            ["Utah Nonprofits Association Conference", "10/3/25", "Conference", "In person", "", "Salt Lake City, UT", "", "",
             "", "", "Same event again, second row in the sheet", ""],
            ["", "1/1/26", "", "", "", "", "", "", "", "", "a row with no name", ""],
        ]),
    "event_attendees.csv": (
        ["Event", "Date", "Contact", "First Name", "Email", "Organization", "Website", "Notes", "Outcome", "Next Steps"],
        [
            ["Utah Nonprofits Association Conference", "10/4/25", "Grace Holt", "Grace", "grace@brightpath.example",
             "BrightPath Youth Services", "brightpath.example", "Sat at our table", "Had a meeting at the event", "Send deck"],
            ["Utah Nonprofits Association Conference", "10/4/25", "Omar Haddad", "Omar", "omar@desertarts.example",
             "Desert Arts Council", "desertarts.example", "", "Met at event, exchanged info", ""],
            ["Community Foundation Roundtable", "11/12/25", "Chris Dole", "Chris", "cdole@peakcf.example",
             "Peak Community Foundation", "peakcf.example", "Moderator", "Met at event, exchanged info", "Email next week"],
            ["Utah Nonprofits Association Conference", "10/5/25", "Nina Park", "Nina", "nina@riversidearts.example",
             "Riverside Arts Alliance", "riversidearts.example", "New lead", "Interested, call scheduled", "Call 10/15"],
        ]),
    "rfps.csv": (
        ["Organization", "Contact", "Email", "RFP", "Type", "Source", "Estimated AUM", "Date Released", "Due Date",
         "Submitted", "Status", "Decision Date", "Notes"],
        [
            ["Peak Community Foundation", "Chris Dole", "cdole@peakcf.example", "OCIO services 2026", "OCIO", "Consultant",
             "$40M", "1/15/26", "3/1/26", "2/25/26", "Finalist", "", "Presentation 3/20"],
            ["Grand Foundation", "Rob Steele", "rob@grandfdn.example", "Investment consulting RFP", "Investment consulting",
             "RFP database", "$25M", "9/1/25", "10/15/25", "10/10/25", "Lost", "12/1/25", "Went with incumbent"],
            ["Harbor Literacy Project", "", "", "Endowment management", "OCIO", "Direct invitation", "$1.1M", "3/1/26",
             "4/15/26", "", "Intent to bid", "", ""],
            ["Cedar Clinic Foundation", "Leo Brandt", "leo@cedarclinic.example", "OCIO mandate", "OCIO", "Consultant",
             "$2M", "2/1/25", "4/1/25", "3/28/25", "Won", "5/15/25", "Funded"],
            ["New Horizons Trust", "Pat Lee", "pat@newhorizonstrust.example", "401(k) advisor search", "401(k) plan advisor",
             "Benefit broker", "$3.5M", "5/1/26", "6/30/26", "", "Watching", "", "Due next summer"],
            ["Mystery Foundation", "", "", "Something", "", "", "", "", "", "", "Banana", "", "status nobody understands"],
            ["", "", "", "No org row", "", "", "", "", "", "", "", "", ""],
        ]),
    # Jon's own templates (Oct 19), header rows exactly as in the files, rows made up
    "jon_event_tracker.csv": (
        ["Date", "Cost", "Event Name", "Event Type", "State", "# of Contacts", "# of Responses", "# of Meetings",
         "Clients Won ($)", "Notes"],
        [
            ["3/12/2026", "$2,500", "Utah Philanthropy Day", "Conference", "UT", "22", "6", "3", "$1,500,000", "Sponsor booth"],
            ["4/8/2026", "$150", "Boise Nonprofit Lunch & Learn", "Networking", "ID", "9", "2", "1", "", ""],
            ["5/20/2026", "0", "Endowment 101 Webinar", "Webinar", "", "40", "5", "2", "$0", "GAARD hosted"],
        ]),
    "jon_rfp_log.csv": (
        ["RFP Name / Issuer", "RFP Reference Number", "Final Submission Date", "Approved for Submission (Y/N)",
         "Reviewed By", "Date Reviewed", "Size of AUM", "Conditions or Limitations", "Notes", "Response",
         "Date Responded", "Correspondence", "WON"],
        [
            ["Investment Advisory Services RFP / Mountain West Arts Foundation", "RFP-2026-014", "2026-02-15", "Y",
             "Test Owner", "2026-02-10", "$12,000,000", "Must be registered in UT", "Sent via portal",
             "Shortlisted, finalist presentation 3/20", "2026-03-02", "Emails with the CFO", ""],
            ["Cedar Valley Community Foundation / OCIO Search", "", "2025-11-30", "Y", "Test Teammate", "2025-11-20",
             "$3.5M", "", "", "Not selected", "2026-01-15", "", "N"],
            ["Harbor Literacy Project", "HLP-01", "2026-12-01", "Y", "Test Owner", "2026-10-01", "$1.1M", "", "", "", "",
             "", ""],
            ["Public Pension RFQ / Big County", "BC-77", "2026-01-10", "N", "Test Owner", "2026-01-05", "$900M",
             "Minimum $500M AUM manager", "Too large for us", "", "", "", ""],
            ["Retirement Plan Advisor Search / Peak Community Foundation", "", "2026-03-01", "Y", "Test Owner",
             "2026-02-20", "$2M", "", "", "Thanks, we will review and get back to you", "2026-03-05", "", ""],
            ["Endowment Management / Grand Foundation", "GF-2025", "2025-06-30", "Y", "Test Teammate", "2025-06-25",
             "$25M", "", "", "Awarded", "2025-08-01", "", "Y"],
            ["Investment Advisory Services RFP / Mountain West Arts Foundation", "RFP-2026-014", "", "", "", "", "", "",
             "Second row for the same RFP", "", "", "", ""],
        ]),
}

UPLOAD = {"events.csv": "upload_events", "event_attendees.csv": "upload_event_attendees", "rfps.csv": "upload_rfps",
          "jon_event_tracker.csv": "upload_event_tracker", "jon_rfp_log.csv": "upload_rfp_log"}


def sql_lit(v):
    return "null" if v == "" else "'" + v.replace("'", "''") + "'"


def ident(h):
    return '"' + h.replace('"', '""') + '"'


lines = ["-- generated by tests/events_rfps_fixtures.py", "set client_min_messages to warning;"]
for name, (headers, rows) in TABS.items():
    with open(OUT / name, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(headers)
        for r in rows:
            assert len(r) == len(headers), (name, r)
            w.writerow(r)
    t = UPLOAD[name]
    cols = ", ".join(f"{ident(h)} text" for h in headers)
    lines.append(f"drop table if exists {t}; create table {t} (id bigint generated by default as identity, {cols});")
    for r in rows:
        lines.append(f"insert into {t} (" + ", ".join(ident(h) for h in headers) + ") values ("
                     + ", ".join(sql_lit(v) for v in r) + ");")
    print(f"{name}: {len(rows)} rows, {len(headers)} columns")
(OUT / "load_uploads.sql").write_text("\n".join(lines) + "\n", encoding="utf-8")
print("load_uploads.sql written")
