# Gaard CRM: how-to manual

This is the user's manual for the Gaard Capital CRM: what each screen is for, how to do each everyday task, what happens automatically, and where everything lives. It is written to be read by a person, or given to Claude together with this repository so Claude can answer questions about the CRM. (`CLAUDE.md`, next to this file, is the technical guide for changing the CRM.)

Contents

1. What the CRM is and where it lives
2. Signing in
3. The screens, one by one
4. What happens after an email, a call or a reply (outcomes and follow-ups)
5. Email: mass email, replies, answering, signature and booking link
6. Events: the Events page, the Event Finder and Google Calendar
7. Importing: lists, business cards, people met at events, replies
8. RFPs
9. Connecting your own Claude
10. Keeping the data accurate and safe
11. Going live with real data, and changing the CRM later
12. Questions and answers
13. Words used in the CRM

---

## 1. What the CRM is and where it lives

The CRM replaces Gaard's outreach spreadsheets. It keeps, in one place:

- **people** (contacts) and the **organizations** they belong to;
- every **email, call and meeting** with them (called *activity*), each with its **outcome** (interested, not now, no response, and so on);
- the **follow-ups** each outcome schedules;
- the **pipeline** from first call to funded client;
- **events**, **RFPs**, portfolio **review** dates, and the **numbers** counted from all of it (Dashboard and KPIs).

| What | Where |
|---|---|
| The CRM itself (open it in a browser) | https://project-qp4en.vercel.app/ (a second copy: https://gaard-capital.github.io/gaard-crm/) |
| The data | A Supabase database (project `fgweqsoflzvxkbxgozor`, organization "Gaard"). Everyone sees the same data. |
| The program | GitHub, `Gaard-Capital/gaard-crm`. Every change pushed to the `main` branch goes live on the website within a minute. |
| Google sign-in, Gmail and Calendar permissions | The Google Cloud project "Gaard CRM" (the OAuth client "Gaard CRM Web"). |
| This manual and the technical guide | `MANUAL.md` and `CLAUDE.md` in the repository. |
| Sample files for practice and demos | `demo/` in the repository (all fictional). |

The CRM works in any modern browser, on a computer or a phone. On a phone the menu becomes a strip across the top that scrolls sideways.

**Demo data.** The sign-in page has "Use the demo data instead". That opens the CRM on fictional data kept in your own browser only: safe for practice; nothing reaches the real database and no email can be sent.

## 2. Signing in

1. Open the CRM and press **Sign in with Google** with your Gaard Google account. Only people an admin has added (Settings > Team) can sign in; anyone else is refused.
2. The first time, scan the code shown with an authenticator app (Google Authenticator, Microsoft Authenticator, or the iPhone Passwords app) and type the 6-digit code. After that, each sign-in asks for the current code. This second step is required for everyone.
3. **New phone?** With the old phone still at hand: Settings > "Use a new authenticator app". Lost the phone: an admin presses Settings > Team > **Reset 2-step** for you, and you scan a new code at your next sign-in.
4. **Sign out** is in the account menu (top right, your name).

## 3. The screens, one by one

The menu, top to bottom: **Contacts, Import, Mass Email, Follow-ups, Events, RFPs, Dashboard, KPIs.** Settings and Sign out are in the account menu at the top right. The **bell** at the top right holds what needs attention.

### The bell (Needs attention)

On every page. It lists:
- **replies** from the last three days ("Hayden replied: Not now"), and replies whose outcome the CRM could not tell (choose one);
- outreach that went nowhere and is on nobody's follow-up list;
- overdue follow-ups; RFPs due within a week.

Click a line to go straight to it: a reply opens the person's page, scrolled to that email. **Check Gmail for replies** at the top of the bell looks for new replies now (see section 5).

### Contacts

Tabs: **People**, **Organizations**, **Partners**, **Newsletter**.

**People** is the master list, laid out like the old spreadsheet: one row per person.
- **Search** by name, organization or email; **filters** narrow by segment, state, stage and more.
- **Columns** chooses which columns show; **All columns** at the top ticks or unticks them all; **Default** puts them back. The choice is remembered on your computer.
- **Correspondence** shows the person's latest outcome ("Replied: Not now?" while a reply waits for a choice). Click it to read the emails without leaving the list.
- **Next Reach out Date** is the next follow-up; click it to move it.
- **Editing in place**: click a cell, change it, press Enter (Escape cancels).
- **Ticking rows**: hover the row number to see its tick box. Press and drag over boxes to tick a range, or Shift-click. The box in the heading ticks the whole page. Ticks survive paging and filters.
- **Mail merge**: with people ticked, opens Mass Email with just those people.

**A person's page** (click a name):
- the details card (name, title, phone, email, LinkedIn, how we met, newsletter, the organization's details, notes): click any value to change it;
- **Next follow-up** and the **Opportunity** (pipeline stage, expected and funded AUM) on the right;
- **Activity**: every email, call, meeting and reply, newest first. An email that has replies and answers shows them inside it, with a link to turn their order (newest or oldest message first). Long letters show two lines until you press **Show more**.
- **Log activity** records a call, meeting or email by hand; the pencil on an activity edits or deletes it.
- **Edit** (top) holds the name, email status, do not contact and the "in person only" flag.

**Buttons at the top of a person's page:**
- **Write an email**: one letter to this person from your Gmail. Start from any template (the merge fields fill in), change anything, attach files (for example the endowment overview PDF). It is logged on their activity and their reply is read like any other.
- **Schedule a call**: once a time is agreed. Check the title ("[Organization] - Gaard Capital"), the day, the time (Mountain), the length (30 minutes), the guests (the person plus whoever you always invite, set in Settings) and the Zoom link. Google Calendar opens with the invitation filled in: remove the Google Meet link if Google added one, then Save and Send. Then the confirmation email opens, in Jon's wording ("I just sent over a calendar invite with a Zoom link for Thu (7/9) at 12:30PM MT..."), in the same Gmail conversation when there is one. The call becomes the person's next follow-up: "log how it went" on the day.
- **Call brief**: the brief in Jon's layout. The CRM fills the top (the organization with its website, who is on the call with their LinkedIn); you type the mission, PURPOSE OF CALL and NOTES. "Copy the brief" copies it with its links for the shared doc, and the note for JB's list is ready to copy after.

**Onboarding checklist** (on the Opportunity card, from the onboarding stage): the firm's 21 standard steps, each with a status note ("Delivered via email and documented, June 9, 2026", or "Not yet completed", "Awaiting settlement and processing", "To be determined"). The card shows how many are done. "Copy as a table" pastes into the workbook.

**Organizations** lists organizations with their people; **Partners** the referral and benefit-group partners; **Newsletter** who is subscribed.

### Import

Brings people and replies in. See section 7.

### Mass Email

Tabs: **Send as a batch** and **Email templates**. See section 5.

### Follow-ups

Tabs: **One at a time** and **Client reviews**.

**One at a time** is everything due: overdue, today, upcoming, and "fixing" (bounced emails and wrong numbers). Each line has the date, the person and organization, the kind of follow-up, why, and three buttons:
- **Log activity**: record what you did (the outcome schedules the next follow-up);
- **Done**: close it without logging anything;
- **Move**: push it 1 day, 1 week or 1 month.

Click a line to open the person. The search box finds a name.

**Client reviews** is the portfolio review calendar for funded clients: overdue, due within 60 days, later.

**Client loyalty** is the loyalty program: every funded client gets three touches a year, a Thanksgiving card (the Friday before Thanksgiving) and two referral check-ins (a visit, a call or a coffee; the third Friday of February and of August the year after), away from the quarter-end newsletters. A cycle is named for the year of its card. **Add** (or "Add all") puts the three follow-ups on the client; they come up on One at a time when due. Type each client's **mailing address** in the table (an individual's: ask them). Click a date to put the prep day (three weeks before) or the day itself on your Google Calendar. **Copy rows for the Customer Loyalty tab** gives the sheet's columns B to H. When the cycle is done, **Start the next cycle**.

### Events

A one-page dashboard of events that everyone on the team sees: totals, people met per event, in person against virtual, events against cold email, and every event beside the people met there. Filter by period, state, segment, **status** (Attended, Going, Maybe, Not going) and format. Not going events show only under that status and leave the totals. Click an event to see who was met there; click its **name** to open its own page, with its details, results, the event's web page and the Event Finder, where you set its status or delete it. An event people were met at cannot be deleted, because it is part of their history: set it to Not going. Search a name to see every event that person was met at. **Import events** is the fallback for anything the Event Finder did not send: your Google Calendar or your Event ROI Tracker file (section 6).

### RFPs

Every request for proposal: organization, mandate, estimated AUM, dates, status and what happened. It is the RFP Log, column for column, shared by everyone. **Add an RFP**, **Copy for the spreadsheet**, and **Update** and **Email** on each row. See section 8.

### Dashboard

One screen of headline numbers and charts: people to contact, new AUM funded, new clients, pipeline, response rate (each against the period before, with its own period choice), the pipeline by stage, AUM funded by month, new leads by channel, the funnel from email to client, and what is coming up in the next 14 days.

### KPIs

Tabs: **KPIs** (the detailed tables: by quarter, by channel, events, campaigns, and the other counts) and **Pipeline** (every open opportunity by stage). Every figure is counted from the activity, opportunities and follow-ups themselves; nothing is typed in twice.

### Settings (account menu, top right)

- **Account**: your name, email and role; **your Google booking link**; **Your Claude** (connect your own Claude, section 9); change password; new authenticator app; sign out.
- **Data health**: the weekly accuracy check (section 10).
- **Team** (admins only): add a person (they then sign in with Google with that address), change a role (Member or Admin), Reset 2-step, Remove, Add back. Copy invite puts a ready message on the clipboard.
- **No cold email list**: email domains (such as universities) whose people are never cold-emailed: they are left out of mass emails, labelled "In person only", and given a "Reach out in person" follow-up. A domain can also be set to Do not contact.

**Roles.** A *member* can read, add, change and delete all CRM data. An *admin* can also manage the team and read the audit log. Nobody can make themselves an admin.

## 4. What happens after an email, a call or a reply

Every activity carries an **outcome**, and the outcome decides what happens next: when the next follow-up is due, whether the pipeline stage moves, whether the person joins the newsletter, or whether they are marked do not contact. Logging a new activity closes the person's open follow-ups and schedules the next one from the new outcome. The next follow-up is counted from the day the activity happened (an out-of-office reply counts from the return date).

The six reply outcomes: **Interested, Not now, Not interested, Bounced (wrong email), Out of office, Unsubscribe (do not contact).** An email you send starts as **No response**.

| Outcome | Next follow-up | Pipeline moves to | Also |
|---|---|---|---|
| No response | 90 days | | |
| Out of office | 14 days (from the return date) | | |
| Bounced / wrong email | 2 days: fix the address | | the email is marked wrong |
| No longer there / wrong person | 7 days: find a new contact | | |
| Pointed us to a colleague | 3 days | | |
| Not now, check back later | 90 days | | |
| Already has an advisor | 180 days | lost | |
| Not interested | none | lost | |
| Asked not to be contacted | none | lost | do not contact |
| Interested, call scheduled | 7 days | call | added to the newsletter |
| No answer / Left voicemail | 7 days | | |
| Wrong number | 2 days: fix the number | | |
| Met at event | 3 days | | |
| Had a meeting at the event | 5 days | | |
| Introduction made | 3 days | | |
| Portfolio review held | none | | |
| Call held, next steps set | 14 days | call | added to the newsletter |
| Hot: a proposal, or going to the board | 7 days | hot | added to the newsletter |
| Wants to hire us: start onboarding | 14 days | onboarding | added to the newsletter |
| Not a fit after the call | none | lost | |
| RFP submitted | 30 days | | |
| RFP finalist | 7 days | call | added to the newsletter |
| RFP won | 14 days | onboarding | added to the newsletter |

**Do not contact.** Once someone is marked do not contact, the database refuses any new email or call to them, and they are left out of mass emails.

**Changing a follow-up by hand.** Move it on Follow-ups, or change the Next Reach out Date on Contacts: the latest activity's "next follow-up" moves with it, so the two always agree.

## 5. Email

### Sending to many people (Mass Email > Send as a batch)

1. Choose who: tick people on Contacts and press **Mail merge**, or open Mass Email and tick them there (the box in the list heading ticks everyone).
2. Choose the **letter** (template). The first cold introduction is chosen when none of them was written to before.
3. Read the letter on the right, filled in for each person. **Type in it to change it for that person only** ("Undo my changes" puts it back).
4. **Add my booking link**: tick it to put the line "If it is easier, pick a time here: (your booking link)" in every letter of the batch. It is off to begin with, because a link in a first cold email makes spam filters more suspicious. It is greyed out until you save a booking link in Settings.
5. **Send a test to myself** sends the letter on screen to you first.
6. **Send N from my Gmail** sends the letters from your own Gmail, one at a time, with your Gmail signature. Each is marked Sent or Not sent, appears in your Gmail Sent folder and is logged as an email with outcome No response, and its follow-up is scheduled.

Google asks your permission the first time (a Google window: allow the CRM to send, and to read your email settings and replies). People on the do-not-contact list, with a bounced address, or on the No cold email list are greyed out and never sent to. **Or send from your own email by hand** copies the letters instead and **Mark as sent** logs them.

**Organization names read naturally.** In a letter, the organization's name is tidied for the sentence ("I am curious how ____ manages its investments."): Inc., LLC and Corp. are dropped, an acronym in brackets is dropped, "Of" and "And" become lowercase, and "the" is added to a bare name such as "Community Center" (not to Foundation, Alliance, Association, Trust and the like). Change any one letter by typing in it.

**Preview**, under the letter, shows the email the way the person will see it, with your Gmail signature.

### Templates (Mass Email > Email templates)

The letters everyone shares. The list is on the left; the chosen letter on the right. **Merge fields** (inserted at the cursor) fill in for each person: `{{first_name}}`, `{{organization}}`, `{{booking_link}}`, `{{sender_name}}`, `{{firm_name}}`, and more; Jon's own style (`{{First Name}}`) works too. **Use it** opens the batch screen with that letter.

### Your signature and booking link

- **Your Google booking link**: your Google Calendar appointment page (Calendar > Create > Appointment schedule > Copy link). It fills `{{booking_link}}` in letters you send.
- **Calls**: your Zoom link, and who is always invited to your calls (for example Dr. Brogaard). Schedule a call uses both.
- **Your signature** is the one you set up in Gmail (Gmail > Settings > See all settings > Signature, and choose it for new emails). The CRM reads it and adds it to every letter you send, so it is exactly what your own emails carry. With no signature in Gmail, your name and the firm go at the foot.

### Staying out of spam

Nobody can promise the inbox: Google and each mailbox decide. What the CRM does: it sends plain letters as Gmail itself writes them, from your own address under your own name, never to bounced or do-not-contact people. What helps most from your side: send from your @gaard.capital address; keep cold letters short and personal, with few links; send a steady number every day rather than a large batch now and then, since sending fast in one burst is what filters look for; stop writing to addresses that bounce. Replies are the strongest signal of all. To check a letter, open it in Gmail, press the three dots, then Show original: SPF, DKIM and DMARC should each say PASS.

### Replies come in by themselves

The CRM remembers the Gmail conversation of every letter it sent. It opens **only those conversations** (nothing else in your mailbox), finds new messages from the other person, and:
- stores the reply on the person's page, under the letter;
- reads the wording and sets the closest outcome (an automatic out-of-office reply is Out of office), which schedules the next follow-up;
- lists the reply under the bell for three days.

It checks when you press **Check Gmail for replies** in the bell, and then every ten minutes while the CRM is open (for about an hour after Google last gave permission). The first time, Google asks your permission to read email: tick the box.

**If the outcome is wrong**, open the reply (the bell takes you there) and press **Change** under it. A reply the CRM could not read asks you to choose. You can also always edit an activity with its pencil.

Replies can also be **pasted** into Import, or brought in as a **screenshot**: the same outcomes are set.

### Answering from the CRM

On a reply, **Reply from my Gmail** opens a suggested answer for that outcome (for example, for Interested: a thank-you and your booking link). Change anything, then send. It goes in the same Gmail conversation, so both sides see one thread, and it is logged under the letter.

### One letter to one person

RFPs have an **Email** button that writes a single letter the same way (section 8). Such letters are logged like the mass email, and their replies are read the same way.

## 6. Events

### The Events page

Totals for past events (events, cost, people met, calls, clients and AUM won), the people met per event, in person against virtual, events against cold email, then every event with the people met there. People "met at" an event are those with an activity at it, plus those whose record says they came from it.

### Import events

The Event Finder sends your events by itself; **Events > Import events** is for anything it did not send. It has two sources. Each one checks the other: an event already on the page (the same name, or a close one within three days) is matched, never added twice.

- **From my Google Calendar**: reads your calendar for four months back and six months ahead and lists what looks like an event (an event word in the title, many guests, or a place and all day or two hours or more). Events the **Gaard Event Finder** put on your calendar are recognized and marked "From your Event Finder". Google asks permission to see your calendar the first time.
- **From my event tracker file**: your Event ROI Tracker (Excel or CSV, as you keep it): date, cost, event name, type, state, number of contacts, responses, meetings, clients won.

Tick what to add, press **Add**. Matched events get their blanks and the tracker's counts filled in.

### The Gaard Event Finder

Jon's Event Finder (a page on claude.ai that searches for Utah events twice a week; **Event Finder** on the Events page opens it) connects to the CRM three ways. The CRM website cannot read the Finder's data itself: it lives inside claude.ai, which only the Finder page and its editors can reach. So the Finder (or Claude) sends events to the CRM:

1. **Directly from the Finder (the best way, once set up).** The Finder page can already use your claude.ai connectors (it adds events to Google Calendar that way). With the Gaard CRM connector added to your claude.ai (section 9), the Finder can send an event to the CRM the moment you mark it Going or Attended. To set it up once, open the Finder in claude.ai and ask Claude:

   > *In this Gaard Event Finder artifact: whenever I mark an event Going, Maybe or Attended, or save its cost and contacts, send it to my "Gaard CRM" connector, and whenever I take that mark off, send the same event with status not_going: `const mcp = await window.claude.use("mcp"); await mcp.callTool("Gaard CRM", "record_event", { finder_id: the event's id, name, date: "YYYY-MM-DD", end_date, status: "going" | "maybe" | "attended" | "not_going", format: "in_person" | "virtual" | "hybrid", kind: "conference" | "networking" | "webinar" | "workshop" | "other", host, city, state: two letters, cost_usd, people_met, url, notes })`. Do it quietly; if the connector is not there, carry on as before. Add a small "Send to CRM" button on each Going or Attended event too, and show "In the CRM" once it is sent. Use the connector's `list_events` to mark events the CRM already has.*

   Use the connector name exactly as it appears in claude.ai > Settings > Connectors. To also catch up by itself, ask: *"Each time this Event Finder opens, compare my Going, Maybe and Attended events with list_events and send any the CRM does not have."* An event already in the CRM is updated, never added twice. Taking the mark off removes it from the CRM within a minute, or, if people were met there, marks it Not going.
2. **Through Google Calendar.** When you put an event from the Finder on your calendar, the Finder writes "From the Gaard Event Finder" in it. **Events > Import events > From my Google Calendar** picks those up (one click; it is not a background sync).
3. **Through your Claude, by asking.** With the connector added, ask in claude.ai: *"Look at my Gaard Event Finder and put every event I marked Going or Attended on the Gaard CRM Events page."* Claude uses the CRM's `record_event` tool.

### People met at an event

Use Import (next section): write **Met at** and the event's name on the first line.

## 7. Importing

**Import** takes: a file dropped on the box or chosen with **browse** (CSV, Excel, Word, or pictures), rows pasted from a sheet (with or without the header row), the text of client replies, or screenshots (Ctrl+V). On a phone, tap the box to choose a file or take photos.

Three steps: **Add data, Check, Imported.**

**The check.** Every row is compared with the people already in the CRM before anything is saved:
- clear rows go in without a question;
- someone **already on file** (same email or LinkedIn, or for a row without email the same full name) is matched, not added twice. **Compare with the contact on file** shows the row beside the person, line by line: *same*, *new* (ticked: it fills a blank), *different* (written only if you tick Replace);
- only a **possible duplicate**, the same email under another name, or a missing or broken email asks you to choose.

Messy values are cleaned on their own: capitals and spaces in emails, "NR", "no reply" and "no response" all become No response, "$11 million" and "$4.2M" become amounts, and so on.

**This list is**: new people, people met at an event, newsletter sign-ups, benefit-group partners, or referral partners. It tells the CRM where the people belong (an event links them to it and logs a "Met at event" activity; newsletter sign-ups are subscribed; partners get their segment). **Segment, where a row does not say** sets the segment for rows without one.

**People met at an event.** Put **Met at** and the event's name on the first line of the box ("Met at Utah Nonprofits Summit"), then the people below (or their business cards). If the event is not on the Events page yet, the check offers **+ A new event** with its name and date; it is added when you import. People already on file get the meeting added to their activity.

**Business cards.** Drop photos of cards (or take them with a phone). Each card is read on your device (the picture is never uploaded) and becomes one row: name, title, organization, email, phone, website. New people are added; someone already on file is matched, and the card's phone and title are ticked to replace the old ones (untick to keep the old).

**Replies.** Paste the text of the emails (with the From line if you can), or screenshots of them. Each is matched to the sender and given an outcome. A screenshot of a whole Gmail conversation keeps only the client's newest message.

**After the import**, the screen shows what each row became (Added or Updated, with a link to the person). The message at the bottom has **Undo**.

**The whole workbook at once** (many tabs, thousands of rows) is better loaded in the database itself: see `db/docs/import_playbook.md`.

## 8. RFPs

**Add an RFP**: paste either the RFP screen Claude gives you (the headline and the seven fields) or a row of your RFP log (the 13 tab-separated columns). The CRM reads the issuer, the size of AUM, the type of arrangement, the due date and the requirements (or every column of the log row) and shows them for checking before saving. A log row for an RFP already in the CRM updates it. A new RFP with a deadline ahead gets an "RFP due" follow-up five working days before.

**The RFP tracker** connects through the same connector as the Event Finder, so there is nothing new to connect: with Gaard CRM added to your claude.ai (section 9), your RFP agent can write to the log. Ask Claude to change the tracker or the agent once:

> *Whenever an RFP is found and screened, and whenever anything about it changes, send it to my "Gaard CRM" connector with its `record_rfp` tool: rfp_name, issuer, reference_number, final_submission_date, approved_for_submission, reviewed_by, date_reviewed, size_of_aum, conditions_or_limitations, notes, response, date_responded, correspondence, won, plus status, arrangement, winner, how_we_scored and url. Dates are YYYY-MM-DD and AUM a plain number. Use `list_rfps` to see what the CRM already has.*

Everyone on the team sees the same log within a minute. **Copy for the spreadsheet** gives the 13 columns of the RFP Log with their headers.

Each RFP row has:
- **Update**: every column of the log, the status (identified, intend to bid, submitted, finalist, won, lost, declined, cancelled), **who won**, and **how we scored and their feedback**.
  - Marking it **won** adds a check-in to Follow-ups two months later.
  - Marking it **lost** adds "ask who won and how we scored" to Follow-ups for this week.
- **Email** (on a won or lost RFP): a ready letter to the RFP's contact. Lost: thanks, and who was chosen and how we scored. Won: how the start has gone. Edit and send from your Gmail. It is logged on the person's activity, with a follow-up five working days later, and their reply is read like any other.

The "Outcome so far" column shows who won and the feedback once written.

## 9. Connecting your own Claude

Your own Claude (claude.ai, with Gmail connected there) can work with the CRM through a **connector** that can do these things and nothing else:
- list who was emailed and has not replied;
- look a person up;
- store a reply with its outcome (which schedules the follow-up, as above);
- list the events on the Events page;
- add, update or take back an event (from the Event Finder);
- read the RFP log, and add or update an RFP (from your RFP tracker).

It cannot send, delete anything else, or read anything else.

1. Settings > **Your Claude** > **Connect my Claude**, then **Copy it and open Claude**. That copies your CRM address (shown once; keep it to yourself, like a password) and opens claude.ai's Connectors page. (claude.ai lets no other website add a connector for you, so this one paste is needed.)
2. On that page: **Add custom connector**, name it "Gaard CRM", paste, **Add**.
3. Ask, for example: *"Check my Gmail for replies to my Gaard outreach and record them in Gaard CRM."*

**New address** replaces the old one; **Disconnect** cuts it off. Removing someone from the team also cuts their Claude off.

## 10. Keeping the data accurate and safe

The spreadsheet problem (log an email, sort or filter, move rows between tabs, and someone's outreach ends up on another person's row) cannot happen here:
- **every email, call, follow-up and deal is tied to its person** by an id, not by its place in a list;
- **sorting and filtering only change what you see**, never the data, and there are no tabs to move rows between;
- **every change is saved in one go** (all of it or none of it), and the database refuses what breaks a rule.

**Data health** (Settings) is an independent check that runs inside the database every Monday (once the weekly schedule is switched on), and whenever someone presses **Run the check now**. It confirms that every activity, deal, follow-up and RFP points at a person or organization that exists and sits under the right organization, that dates and amounts make sense, and that nothing is duplicated. Each count is compared with the week before, so a sudden jump stands out. Every line should say **OK**; anything else shows the rows behind it.

**Undo.** Every change shows a message at the bottom with **Undo** (the last 12 changes).

**Audit log.** The database records who changed what, when, and the old values. A wrong edit, delete or merge can be put back (ask Claude or the admin; it is read in the Supabase SQL Editor).

**Privacy.** The CRM reads only the Gmail conversations it started; screenshots and card photos are read on your own device; nothing from the live database is kept in the browser.

## 11. Going live with real data, and changing the CRM later

Until handover every row in the database is sample data. **The full step-by-step is in `CLAUDE.md`, section "Going live with real data".** In short:
1. remove the build team (Settings > Team);
2. make Google sign-in internal to Gaard's Workspace;
3. upgrade Supabase for daily backups;
4. clear the sample data with `db/016_clear_demo_data.sql` (a guard line must be switched on first);
5. load the real data through Import (or the SQL Editor for the whole workbook);
6. run Data health.

Tien can do it with you.

**Changing the CRM.** Give Claude this repository and describe the change in plain words ("send the follow-up after 60 days for Not now"). Claude reads `CLAUDE.md` first, makes the change, and explains it. Try it on your own computer before it goes live: a change pushed to GitHub is live on the website within a minute.

## 12. Questions and answers

**Someone's email bounced.** The outcome Bounced marks the address wrong and adds a "fix the address" follow-up. Correct the email on their page; that clears the flag and the follow-up.

**I logged the wrong outcome.** Use the pencil on the activity, or Change under a reply. The follow-up is rescheduled.

**A person shows up twice.** Import never adds someone twice by email or LinkedIn. For look-alikes already in the CRM (a nickname, a typo), the database keeps a list of possible duplicates (`v_possible_duplicates`), and `merge_contacts` folds one into the other, keeping every email and follow-up. There is no screen for this yet: it is done in the Supabase SQL Editor, or ask Claude to do it.

**The Send button is grey.** Real sending works only on the live database (not the demo data), and only on the website or localhost. Check that people are ticked and have an email address.

**Google says "Access blocked".** Either the account is not on the Google project's list of test users (until the app is internal to Gaard's Workspace), or it is under Google's Advanced Protection, which refuses reading email for apps Google has not verified. Sending still works; replies can be pasted into Import.

**Replies are not showing up.** Press Check Gmail for replies in the bell and allow reading. The CRM only finds replies to letters it sent from Gmail, to the same Gmail account that is signed in now.

**Where is the audit log?** In the database (Supabase > SQL Editor: `select * from audit_log order by id desc limit 50`). There is no screen for it yet.

**How do I add a team member?** Settings > Team (admins): name, email, role, Add. They sign in with Google with that address. Copy invite gives a ready message to send them.

## 13. Words used in the CRM

- **Activity (touchpoint)**: one email, call, meeting, event conversation or check-in with a person.
- **Outcome**: what came of an activity; it decides the next follow-up.
- **Follow-up (reminder)**: the next thing to do for a person, and when.
- **Opportunity / pipeline**: a person or organization from first call to funded: call, hot, onboarding, funded, or lost.
- **Segment**: the kind of prospect (nonprofit, 401(k), family office, affiliate, and so on).
- **Channel**: how we met them (cold email, event, referral, cold call, RFP...).
- **AUM**: assets under management.
- **Do not contact**: never email or call again (they asked, or a rule says so).
- **In person only (No cold email)**: never cold-emailed; reach out personally.
- **Merge fields**: the `{{...}}` places in a template filled in for each person.
- **Connector**: the address that lets your own Claude work with the CRM.
