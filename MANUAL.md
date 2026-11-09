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
- **events**, **RFPs**, portfolio **review** dates, and the **numbers** counted from all of it (KPIs).

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

The menu, top to bottom: **Contacts, Import, Mass Email, Follow-ups, Events, RFPs, KPIs.** The CRM opens on KPIs. Settings and Sign out are in the account menu at the top right. The **bell** at the top right holds what needs attention.

### The bell (Needs attention)

On every page. It lists:
- **replies** from the last three days ("Hayden replied: Not now"), and replies whose outcome the CRM could not tell (choose one);
- outreach that went nowhere and is on nobody's follow-up list;
- overdue follow-ups; RFPs due within a week.

Click a line to go straight to it: a reply opens the person's page, scrolled to that email. **Opening a line takes it off the bell** and lowers the count, so what is left is what you have not looked at. The lines that count something ("36 follow-ups are overdue") come back on their own as soon as the number changes, so clearing one never hides a problem that is still growing. What you have opened is remembered in your own browser, not shared with the team. **Check Gmail for replies** at the top of the bell looks for new replies now (see section 5).

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
- **Copy for the merge sheet**, with people ticked, copies those rows ready to paste into your Google Sheets merge sheet.
- **Delete**, with people ticked, removes them. It is greyed out if any of them has anything logged (an activity, a deal, or an open follow-up); hover it and it tells you. Delete the activity first, or untick those people. Undo puts them back.

**Every column sorts.** Click a heading to sort by it, click again to reverse. Four sort the way you read them rather than A to Z: Initial Outcome runs through the five, Status goes Active, Dormant, Dead, Stage follows the pipeline, and Newsletter goes subscribed to unsubscribed. Sort a column and then copy it and you get it in that order.

**Three things every sheet can do** (Contacts, Organizations, Correspondence, Partners, Newsletter, RFPs):
- **Widen a column**: drag the line between two headings.
- **Move a column**: drag the heading sideways. The first columns stay put so you never lose your place.
- **Copy**: hover a heading for a small copy mark that copies **that one column on its own**, nothing else, which is what you want for a list of addresses. Hover a row for the same mark beside the name to copy **the whole row**. Both copy only what you can see, so a column you have hidden is left out.

Widths and column order are remembered per screen on your computer. On Contacts, **Columns** > **Default** puts that sheet's columns, widths and order back.

**The columns.** Date (the day they were added), Contact Name, First Name, Email, Organization, AUM, Notes, Correspondence, Initial Outcome, Status, Stage, Next Reach out Date, Newsletter, Source Event, Segment, State, First reached, Last touch, Touches, Channel.
- **Initial Outcome** is one of five: No Response, Call, Responded - Interested, Responded - Not Now, Responded - Not Interested. Click it to change it, and the follow-up and the pipeline move with it. Underneath those five sit the delivery problems (bounced, out of office, wrong person), because each of those raises its own reminder.
- **Status** is Active, Dormant or Dead, worked out on its own: Dead when they said no, or when three follow-ups at least six months apart went unanswered; Active while a deal or a follow-up is open; Dormant otherwise. Click it to set it by hand, or back to automatic.
- **Stage** is where they sit on the pipeline (Call, Next steps, Onboarding, Funded, Lost). It used to be called Status, which was confusing.
- **Source Event** is the event where you met them.
- **Correspondence** is a quoted line from their latest reply.

**A person's page** (click a name):
- the details card (name, title, phone, email, LinkedIn, how we met, newsletter, the organization's details, notes): click any value to change it;
- **Next follow-up** and the **Opportunity** (pipeline stage, expected and funded AUM) on the right;
- **Activity**: every email, call, meeting and reply, newest first. An email that has replies and answers shows them inside it, with a link to turn their order (newest or oldest message first). Long letters show two lines until you press **Show more**.
- **Log activity** records a call, meeting or email by hand; the pencil on an activity edits or deletes it. Under Notes, **Record** lets you say the notes instead of typing them (see "Speaking instead of typing", section 7).
- **Edit** (top) holds the name, email status, do not contact and the "in person only" flag.
- **Status** sits above Newsletter on the details card: Active, Dormant or Dead, with a line saying whether it was worked out or set by hand. Changing it here changes the Status column on the list, and the other way round.
- **Copy row** (top) copies this one person as a row with its headings, ready to paste into a sheet.
- **Delete** (top) removes the person. It is greyed out while anything is logged against them, and hovering it says what: "Cannot be deleted while it has 3 logged activities. Delete the activity first." Clear those and it turns on. Undo puts them back.

**Buttons at the top of a person's page:**
- **Write an email**: one letter to this person from your Gmail. Start from any template (the merge fields fill in), change anything, attach files (for example the endowment overview PDF). It is logged on their activity and their reply is read like any other.
- **Schedule a call**: once a time is agreed. Check the title ("[Organization] - Gaard Capital"), the day, the time (Mountain), the length (30 minutes), the guests (the person; add anyone else, separated by commas) and your Zoom link. Google Calendar opens with the invitation filled in: remove the Google Meet link if Google added one, then Save and Send. Then the confirmation email opens, in Jon's wording ("I just sent over a calendar invite with a Zoom link for Thu (7/9) at 12:30PM MT..."), in the same Gmail conversation when there is one. The call becomes the person's next follow-up: "log how it went" on the day.
- **Call brief**: the brief in Jon's layout. The CRM fills the top (the organization with its website, who is on the call with their LinkedIn); you type the mission, PURPOSE OF CALL and NOTES. "Copy the brief" copies it with its links for the shared doc, and the note for JB's list is ready to copy after.

**Onboarding checklist** (on the Opportunity card, from the onboarding stage): the firm's 21 standard steps, each with a status note ("Delivered via email and documented, June 9, 2026", or "Not yet completed", "Awaiting settlement and processing", "To be determined"). The card shows how many are done. "Copy as a table" pastes into the workbook.

**Organizations** lists organizations with their people; **Partners** the referral and benefit-group partners.

**Newsletter** is who is subscribed, in five columns only, the way your own newsletter sheet reads: the date they joined the list, Contact Name, First Name, Email, Organization. Turning the Newsletter column on or off anywhere carries everywhere at once: the count on the tab, this list, the person's page and the numbers. Somebody who leaves and comes back is dated from the day they came back, not the first time.

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

A one-page dashboard of events that everyone on the team sees: totals, people met per event, in person against virtual, events against cold email, and every event beside the people met there. Filter by period, state, segment, **status** (Attended, Going, Not going) and format. Only events you marked Going or Attended in the Event Finder come in (section 6). Not going events show only under that status and leave the totals. Click an event to see who was met there; click its **name** to open its own page, with its details, results, the event's web page and the Event Finder, where you set its status or delete it. An event people were met at cannot be deleted, because it is part of their history: set it to Not going. Search a name to see every event that person was met at. **Import events** is the fallback for anything the Event Finder did not send: your Google Calendar or your Event ROI Tracker file (section 6).

### RFPs

Every request for proposal: organization, mandate, estimated AUM, dates, status and what happened. It is the RFP Log, column for column, shared by everyone. **Add an RFP**, **Copy for the spreadsheet**, and **Update** and **Email** on each row. See section 8.

The log reads like the Contacts list: one tight row per RFP with the name held on the left as you scroll sideways, every heading sorting, a search over name, issuer, reference and notes, the same zoom, and pages at the bottom. It can also widen, reorder and copy columns and rows like any other sheet.

### KPIs

One page for how the business is doing, read like a Power BI report (the Dashboard and the KPIs became one page in November 2026). Its first question is **which source brings the money in, and for how much effort**, so the firm can put more into what pays. Tabs: **KPIs** and **Pipeline** (every open opportunity by stage). Every figure is counted from the activity, opportunities and follow-ups themselves; nothing is typed in twice. It opens on **this quarter**, so every number has the quarter before to compare with. From the top:

- **Five numbers**, each against the period before: new AUM funded, estimated yearly revenue (0.45% of that AUM), clients closed, the **active pipeline** (warm opportunities only, with the dormant amount beside it), and the response rate.
- **Where the money comes from**: one bar per source (cold outreach by segment, affiliates and referrals, events in person and virtual, speaking and workshops, the RFP database), longest first, with its revenue, its share and the change against the period before. The line beneath names the source that brought the most, and how long its clients took to close.
- **Revenue by quarter**: the last six quarters, each column split by source, so you can see which source is growing and which is fading.
- **Return by source**: one row per source, the numbers your old Marketing Dashboard tracked and what they lead to. *Effort* (emails and calls, events, or RFPs, whichever is that source's first step), replies and **reply rate**, next steps and **next-step rate** (the darker the cell, the better the source), clients, **revenue**, **cost** (what the events cost), **per $1** (a year's fee for each dollar spent), **days to close** (the middle client's time from first contact to funding) and the **warm pipeline** (the yearly fee the warm opportunities would bring). Click a row for the pipeline.
- **Still to come**: the open opportunities by source, warm in blue and dormant in grey.
- **This quarter and this year**: side by side with the same span a quarter and a year ago (below).
- **From email to client** (the funnel) and what is **coming up** in the next 14 days.
- **More reporting** (closed until you open it): by segment, by state, events and campaigns.

**Speaking / workshops** is its own source: a person met at an event of the kind *workshop*, or at an event Gaard hosted, counts there rather than under Events.

**Choosing the period.** The button at the top right shows the stretch being counted and its two dates. The period on KPIs is its own: choosing one here does not filter the Contacts list. Press it for three ways to change it: the usual stretches (last 30 days, last 90 days, this quarter, last quarter, this year, last year, all time); **any quarter of any year**, with arrows to step the year and Q1 to Q4 beneath; and **From** and **To** dates with the calendar, for any two points you like. Picking either date makes it a custom range, and the panel stays open so you can set the second one. The same picker is on the other screens, in the filter bar.

**This quarter and this year, side by side**: emails sent, replies, calls booked, next steps, clients funded, AUM funded and estimated yearly revenue, each against the same stretch a quarter ago and a year ago, with the change beside it. Clients, AUM and revenue are counted by the day the client funded, like the numbers at the top. No toggling back and forth to compare.

**Which channel gets the credit.** Somebody can be cold-emailed with no reply, then met at an event, then booked a call. The emails and the event are both still counted as activity, but the **conversion** is credited to whatever actually produced the call, which is the event. The filter bar on KPIs and Pipeline has a switch between *what converted them* (the normal reading) and *how we first met* (the old one). It is only on those two screens, because it changes how figures are counted rather than which people are listed. A person's page shows the route in one line, for example "Cold email (no response), met at Jackson Hole, call."

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

1. Choose who: tick people on Contacts and press **Mail merge**, or open Mass Email and tick them there (the box in the list heading ticks everyone). **Find a name** beside the count narrows the list to one person so you can read their letter; it never changes who is ticked, and clearing it brings everyone back.
2. Choose the **letter** (template). The first cold introduction is chosen when none of them was written to before.
3. Read the letter on the right, filled in for each person. **Type in it to change it for that person only** ("Undo my changes" puts it back).
4. **Add my booking link**: tick it to put the line "If it is easier, pick a time here: (your booking link)" in every letter of the batch. It is off to begin with, because a link in a first cold email makes spam filters more suspicious. It is greyed out until you save a booking link in Settings.
5. **Send a test to myself** sends the letter on screen to you first.
6. **Send N from my Gmail** first asks: *"Are you sure you want to send [the letter] to these N emails?"*, with the subject, the address it goes out from and the first names on the list. Press **Yes, send N emails** to go on, or **Cancel** (pressing Enter alone cancels, so nothing is sent by accident). Then the letters go out from your own Gmail, one at a time, with your Gmail signature; **Stop sending** halts the rest, which stay ticked. Each is marked Sent or Not sent, appears in your Gmail Sent folder and is logged as an email with outcome No response, and its follow-up is scheduled.

Google asks your permission the first time (a Google window: allow the CRM to send, and to read your email settings and replies). People on the do-not-contact list, with a bounced address, or on the No cold email list are greyed out and never sent to. **Or send from your own email by hand** copies the letters instead and **Mark as sent** logs them.

**Organization names read naturally.** In a letter, the organization's name is tidied for the sentence ("I am curious how ____ manages its investments."): Inc., LLC and Corp. are dropped, an acronym in brackets is dropped, "Of" and "And" become lowercase, and "the" is added to a bare name such as "Community Center" (not to Foundation, Alliance, Association, Trust and the like). Change any one letter by typing in it.

**Preview**, under the letter, shows the email the way the person will see it, with your Gmail signature. When your signature cannot be added, Preview, the test and the send all say why in a yellow note, and how to fix it (see "Your signature" below).

### Templates (Mass Email > Email templates)

The letters everyone shares. The list is on the left; the chosen letter on the right. **Merge fields** (inserted at the cursor) fill in for each person: `{{first_name}}`, `{{organization}}`, `{{booking_link}}`, `{{sender_name}}`, `{{firm_name}}`, and more; Jon's own style (`{{First Name}}`) works too. **Use it** opens the batch screen with that letter.

### Your signature and booking link

- **Your Google booking link**: your Google Calendar appointment page (Calendar > Create > Appointment schedule > Copy link). It fills `{{booking_link}}` in letters you send.
- **Your signature** is the one you set up in Gmail. The CRM reads it and adds it to every letter you send, so it is exactly what your own emails carry. Two things must be true:
  1. **Gmail has it chosen for new emails.** Google gives the CRM one signature only: the one under *For new emails use*, whatever its name. If you have several (say "Gaard" and a personal one), choose the one for the CRM there. In Gmail: the gear > **See all settings** > **General** > **Signature**, then under **Signature defaults** set **For new emails use** to your signature, and press **Save Changes** at the bottom of the page.
  2. **You let the CRM read your Gmail settings.** The first time you press Preview or send, Google opens a window asking for two permissions: to send email for you, and to *view your email messages and settings*. **Tick both** (Google may show them as two boxes, or "Select all"). The second is how the CRM reads your signature, and the replies to letters it sent; it reads nothing else. If you left it unticked, press **Preview** again: Google asks again. To start over, remove "Gaard CRM" at myaccount.google.com > Security > Your connections to third-party apps, then press Preview.

  Until both are true, your name and the firm go at the foot instead (for example "Jon Clifford / GAARD Capital"), and the yellow note under Preview says which of the two is missing. After fixing it, press **Preview** to check: the CRM reads the signature again.

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

**Only what we act on.** The CRM holds the events you marked **Going** or **Attended** in the Event Finder, nothing else (Jon's rule, November 2026). An event that is only found, or marked Maybe, stays in the Finder. Taking the mark off, or hiding the event, takes it off the CRM; if people were met there, it stays, marked Not going. Past events count too: mark the ones you went to **Attended**, so you can record who you met there.

**Notes are said once.** The Event Finder tells the CRM about an event every time you change its status, and repeats its note each time. The CRM now keeps one copy of each note instead of stacking up the same line eight times, and the kind of event reads as a word (Networking, not networking).

### The Gaard Event Finder

Jon's Event Finder (a page on claude.ai that searches for Utah events twice a week; **Event Finder** on the Events page opens it) connects to the CRM three ways. The CRM website cannot read the Finder's data itself: it lives inside claude.ai, which only the Finder page and its editors can reach. So the Finder (or Claude) sends events to the CRM:

1. **Directly from the Finder (the best way, once set up).** The Finder page can already use your claude.ai connectors (it adds events to Google Calendar that way). With the Gaard CRM connector added to your claude.ai (section 9), the Finder can send an event to the CRM the moment you mark it Going or Attended. To set it up once, open the Finder in claude.ai and ask Claude:

   > *In this Gaard Event Finder artifact: whenever I mark an event Going or Attended, or save its cost and contacts, send it to my "Gaard CRM" connector, and whenever I take that mark off (or change it to Maybe), send the same event with status not_going: `const mcp = await window.claude.use("mcp"); await mcp.callTool("Gaard CRM", "record_event", { finder_id: the event's id, name, date: "YYYY-MM-DD", end_date, status: "going" | "attended" | "not_going", format: "in_person" | "virtual" | "hybrid", kind: "conference" | "networking" | "webinar" | "workshop" | "other", host, city, state: two letters, cost_usd, people_met, url, notes })`. Do it quietly; if the connector is not there, carry on as before. Add a small "Send to CRM" button on each Going or Attended event too, and show "In the CRM" once it is sent. Use the connector's `list_events` to mark events the CRM already has.*

   Use the connector name exactly as it appears in claude.ai > Settings > Connectors. To also catch up by itself, ask: *"Each time this Event Finder opens, compare my Going and Attended events with list_events and send any the CRM does not have."* An event already in the CRM is updated, never added twice. Taking the mark off removes it from the CRM within a minute, or, if people were met there, marks it Not going.
2. **Through Google Calendar.** When you put an event from the Finder on your calendar, the Finder writes "From the Gaard Event Finder" in it. **Events > Import events > From my Google Calendar** picks those up (one click; it is not a background sync).
3. **Through your Claude, by asking.** With the connector added, ask in claude.ai: *"Look at my Gaard Event Finder and put every event I marked Going or Attended on the Gaard CRM Events page."* Claude uses the CRM's `record_event` tool.

### People met at an event

Use Import (next section): write **Met at** and the event's name on the first line.

## 7. Importing

**Import** takes: a file dropped on the box or chosen with **browse** (CSV, Excel, Word, or pictures), rows pasted from a sheet (with or without the header row), the text of client replies, screenshots (Ctrl+V), or a sentence you say with **Record**. On a phone, tap the box to choose a file or take photos.

**Speaking instead of typing (Record).** The **Record** button sits beside Continue on Import, under Notes in **Log activity** on a contact's page, and under the answer in **Reply from my Gmail** (what you say goes in a new paragraph after the suggested answer, unless you click into the letter first: then it goes where the cursor is).
1. Press **Record**. The first time, the browser asks to use the microphone: choose **Allow**.
2. Speak normally, in English. The button turns red and reads **Stop**, and the time counts up. The first words show after about eight seconds, then follow a few seconds behind you (the box cannot be typed in while it records). A word may change as more of the sentence is heard.
3. Press **Stop**. The last words are written out within a few seconds, and the box can be typed in again.
4. Read it through and correct any name it misheard, then press Continue (Import), Save (Log activity) or Send from my Gmail (a reply).

On Import, say it the way you would write it, for example *"Met Sarah Rodgers at the Park City summit, she is keen to talk next week."* The CRM finds Sarah's record and logs the meeting, as if you had typed the sentence.

The recording is written out **on your computer**: the sound is never uploaded or kept. The very first time, the browser downloads the speech reader (about 40 MB, the message under the button shows its progress); after that it is ready at once. If the microphone was refused, click the lock beside the web address, allow the microphone, and press Record again.

Three steps: **Add data, Check, Imported.**

**Say what it is, if it guesses wrong.** Beside Continue is a box reading **Work it out**. Left alone, the CRM decides for itself whether you have given it a list of people, business cards or email replies. If it cannot tell, it stops and asks rather than guessing: *"Which is it? This does not read as a list, a card or an email."* Set the box to **A list of people**, **Business cards** or **Email replies** and it is read that way, no argument. Use that whenever a photo comes out badly.

A photo is never filed as an email unless the words of an email are actually in it. Before, anything that did not read as a spreadsheet was treated as a reply, which is how a blurry business card once ended up as a message from nobody with gibberish as its text.

**When a photo is hard to read** the CRM says so and gives it a score out of 100, so you know to check every field. A dark card with fancy lettering reads badly: a straight-on photo in good light is worth retaking.

**The check.** Every row is compared with the people already in the CRM before anything is saved:
- clear rows go in without a question;
- someone **already on file** (same email or LinkedIn, or for a row without email the same full name) is matched, not added twice. **Compare with the contact on file** shows the row beside the person, line by line: *same*, *new* (ticked: it fills a blank), *different* (written only if you tick Replace);
- only a **possible duplicate**, the same email under another name, or a missing or broken email asks you to choose.

**Fixing a row the CRM got wrong.** Every row on the check screen has a pencil on the right. Press it and you can correct the name, email, organization, title, phone and website by hand, then **Save this row**. The checks run again on what you typed, so a row that said "Left out: no contact name in this row" becomes a proper new person once you give it a name. Do it here, before importing: afterwards the row is already saved or already lost.

Messy values are cleaned on their own: capitals and spaces in emails, "NR", "no reply" and "no response" all become No response, "$11 million" and "$4.2M" become amounts, and so on.

**This list is**: new people, people met at an event, newsletter sign-ups, benefit-group partners, or referral partners. It tells the CRM where the people belong (an event links them to it and logs a "Met at event" activity; newsletter sign-ups are subscribed; partners get their segment). **Segment, where a row does not say** sets the segment for rows without one.

**People met at an event.** On the first line of the box, say who you met, where and when, then put the people below (rows from a sheet, or their business cards). For example: "Met Maria Olivia at Mentor International July 2025", "Met these people at the UNA Conference last Tuesday", "Spoke with John Smith and Ann Lee at the Park City Summit on 8/14/2026", or just "Event: Utah Nonprofits Summit, Aug 12 2026". Dates can be written 8/14/2026, Aug 14 2026, Aug 2026 (counted as the 1st), in March, yesterday, last week or last Friday; with no date, the event's own date is used. A line with names and nothing below it logs the meeting for those people if they are already on file, and offers to add anyone who is not. If the event is not on the Events page yet (or the one there is more than about six weeks from the date you said, like the same summit a year later), the check offers **+ A new event** with its name and that date; it is added when you import. People already on file get the meeting added to their activity on its own date, so their page shows every event you met them at; the earliest stays as their Source Event. The words it understands are listed at the top of the code (`MET_WORDS`); if Jon says something it does not understand, ask Claude to add the words there.

**Business cards.** Drop photos of cards (or take them with a phone). Each card is read on your device (the picture is never uploaded) and becomes one row: name, title, organization, email, phone, website. New people are added; someone already on file is matched, and the card's phone and title are ticked to replace the old ones (untick to keep the old).

**Replies.** Paste the text of the emails (with the From line if you can), or screenshots of them. Each is matched to the sender and given an outcome. A screenshot of a whole Gmail conversation keeps only the client's newest message.

**After the import**, the screen shows what each row became (Added or Updated, with a link to the person). The message at the bottom has **Undo**.

**The whole workbook at once** (many tabs, thousands of rows) is better loaded in the database itself: see `db/docs/import_playbook.md`.

## 8. RFPs

**Add an RFP**: paste either the RFP screen Claude gives you (the headline and the seven fields) or a row of your RFP log (the 13 tab-separated columns). The CRM reads the issuer, the size of AUM, the type of arrangement, the due date and the requirements (or every column of the log row) and shows them for checking before saving. A log row for an RFP already in the CRM updates it. A new RFP with a deadline ahead gets an "RFP due" follow-up five working days before.

**The RFP tracker** connects through the same connector as the Event Finder, so there is nothing new to connect: with Gaard CRM added to your claude.ai (section 9), your RFP agent can write to the log. Ask Claude to change the tracker or the agent once:

> *Whenever we submit an RFP, and whenever anything about a submitted RFP changes (shortlisted, won, lost), send it to my "Gaard CRM" connector with its `record_rfp` tool: rfp_name, issuer, reference_number, final_submission_date, approved_for_submission, reviewed_by, date_reviewed, size_of_aum, conditions_or_limitations, notes, response, date_responded, correspondence, won, plus status, arrangement, winner, how_we_scored and url. Dates are YYYY-MM-DD and AUM a plain number. Use `list_rfps` to see what the CRM already has.*

Only RFPs we **submit** go in (Jon's rule, November 2026), then each later change: shortlisted (finalist), won or lost. One that was only screened, passed on or not bid stays in the tracker; the connector refuses it and says why. Everyone on the team sees the same log within a minute. **Copy for the spreadsheet** gives the 13 columns of the RFP Log with their headers.

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

**Privacy.** The CRM reads only the Gmail conversations it started; screenshots, card photos and voice recordings are read on your own device; nothing from the live database is kept in the browser.

## 11. Going live with real data, and changing the CRM later

Until handover every row in the database is sample data. **The full step-by-step is in `CLAUDE.md`, section "Going live with real data".** In short:
1. remove the build team (Settings > Team);
2. make Google sign-in internal to Gaard's Workspace (the next part of this section, step by step);
3. upgrade Supabase for daily backups;
4. clear the sample data with `db/016_clear_demo_data.sql` (a guard line must be switched on first);
5. load the real data through Import (or the SQL Editor for the whole workbook);
6. run Data health.

Tien can do it with you.

### Moving Google sign-in to Gaard's Workspace (Internal)

**Why.** Today the Google side of the CRM ("Sign in with Google", sending from Gmail, reading replies, reading the calendar) runs on a Google Cloud project the build team created, in *Testing* mode: only people on its test list can use it, and Google lets a test permission lapse after a week. Reading replies needs the *gmail.readonly* permission, which Google only allows without a long security review for an app that is **Internal** to a company's Google Workspace. Moving the project into Gaard's Workspace makes it Gaard's own, lets every gaard.capital account use all of it, and keeps everyone else out. Do it **before the build team is removed**, so someone can help if a step goes wrong.

**What changes for staff.** Nothing they have to learn: the same buttons. Google's permission window shows "Gaard CRM" with no "unverified app" warning, and replies are read for everyone. Only gaard.capital accounts can sign in with Google afterwards; a personal Gmail can no longer.

**Before you start** (about 30 minutes)
- The person doing it signs in with a **gaard.capital account that is a Google Workspace super admin** (Jon, or whoever manages Gaard's Google Workspace).
- Someone with the **Administrator** role in the Supabase organization "Gaard" (Tien today) is at hand for step 7.
- Have three browser tabs ready: https://console.cloud.google.com , https://supabase.com/dashboard/project/fgweqsoflzvxkbxgozor , and the CRM.
- Google renames menus from time to time. If a name below is not on your screen, use the search box at the top of the Google Cloud console and type the name in **bold**.

**Step 1. Check that Gaard has a Google Cloud organization.**
1. Open https://console.cloud.google.com signed in as the gaard.capital super admin (the picture at the top right shows which account; switch there if needed). Accept the terms if asked.
2. Click the **project picker** at the top left (next to "Google Cloud"). A window opens; at its top, the box shows where you are. Open it: **gaard.capital** should be listed as an organization.
3. If it is not, close the window, create any project once (step 2 below does that), and look again: Google creates the organization for a Workspace domain the first time an admin uses the console.

**Step 2. Create the project inside Gaard's organization.**
1. Project picker > **New project**.
2. Project name: **Gaard CRM**. Organization: **gaard.capital**. Location: **gaard.capital**. Press **Create**.
3. When the bell at the top right says it is ready, choose **Select project**. The name at the top now reads Gaard CRM. Every step below happens in this project.

(We make a new project rather than moving the old one: the old one belongs to a builder's personal account, and a new one is Gaard's from the first day.)

**Step 3. Turn on the two Google services the CRM uses.**
1. Menu (the three lines at the top left) > **APIs & Services** > **Library**.
2. Search **Gmail API**, open it, press **Enable**.
3. Back to the Library, search **Google Calendar API**, open it, press **Enable**.

**Step 4. Describe the app, and make it Internal.**
1. Menu > **APIs & Services** > **OAuth consent screen** (on newer screens this opens **Google Auth Platform**). Press **Get started**.
2. **App information**: App name **Gaard CRM**. User support email: a gaard.capital address (for example Jon's). **Next**.
3. **Audience**: choose **Internal**. **Next**. (If Internal cannot be chosen, the project is not inside the gaard.capital organization: go back to step 2.)
4. **Contact information**: a gaard.capital address. **Next**. Tick that you agree to the Google API Services User Data Policy, then **Create**.
5. Optional, under **Branding**: the Gaard logo and the home page https://project-qp4en.vercel.app/ . This is what people see in Google's permission window.

**Step 5. List the permissions the CRM asks for.**
1. In Google Auth Platform, open **Data Access** > **Add or remove scopes**.
2. Tick, or paste into "Manually add scopes" and press **Add to table**, these six:
   - `openid`
   - `.../auth/userinfo.email`
   - `.../auth/userinfo.profile`
   - `https://www.googleapis.com/auth/gmail.send` (send the letters)
   - `https://www.googleapis.com/auth/gmail.readonly` (read your signature and the replies to letters the CRM sent)
   - `https://www.googleapis.com/auth/calendar.readonly` (Events > Import events > From my Google Calendar)
3. Press **Update**, then **Save** at the bottom of the page.

**Step 6. Create the sign-in key the website uses (the OAuth client).**
1. In Google Auth Platform, open **Clients** > **Create client**.
2. Application type: **Web application**. Name: **Gaard CRM Web**.
3. Under **Authorized JavaScript origins**, press **Add URI** three times and enter, one per line, exactly (no slash at the end):
   - `https://project-qp4en.vercel.app`
   - `https://gaard-capital.github.io`
   - `http://localhost:8765`
4. Under **Authorized redirect URIs**, press **Add URI** and enter exactly:
   - `https://fgweqsoflzvxkbxgozor.supabase.co/auth/v1/callback`
5. Press **Create**. A window shows the **Client ID** (it ends in `.apps.googleusercontent.com`) and the **Client secret**. Press **Download JSON** and keep the file somewhere private: Google may not show the secret again.
   - The **Client ID** is public. It goes into the CRM's code (step 8).
   - The **Client secret** is private. It goes **only** into Supabase (step 7). Never paste it in a chat, an email, the team chat or the repository.

**Step 7. Point Supabase's "Sign in with Google" at the new client** (Supabase Administrator).
1. Supabase dashboard > project **fgweqsoflzvxkbxgozor** > **Authentication** > **Sign In / Providers** > **Google**.
2. Replace **Client IDs** with the new Client ID, and **Client Secret (for OAuth)** with the new secret. Leave the rest as it is. Press **Save**.
3. Check under Authentication > **URL Configuration** that the Site URL and the redirect URLs still list the Vercel site and http://localhost:8765 (nothing should need changing).

**Step 8. Put the new Client ID in the CRM** (do it the same day as step 7).
1. Open Claude with this repository (Claude Code in the folder, or claude.ai with the GitHub repository).
2. Say: *"Change GMAIL_CLIENT_ID in index.html to <the new Client ID>, bump the build-version, and update the Google sign-in row in CLAUDE.md: the OAuth client is now in the Gaard CRM project of Gaard's Workspace, Internal. Then pull, commit and push."*
3. Wait a minute for the website to update, then reload the CRM.

**Step 9. Let Workspace trust its own app** (Workspace super admin, https://admin.google.com).
1. **Security** > **Access and data control** > **API controls**.
2. Press **Settings** (in the "Domain wide delegation" area or at the top, depending on the screen) and make sure **Trust internal, domain-owned apps** is ticked. Save.
3. Only if someone is enrolled in Google's **Advanced Protection**: under API controls > **Manage Third-Party App Access** > **Configure new app**, search the new Client ID, choose **Gaard CRM**, and set it to **Trusted**. Without this, Google refuses reading Gmail for that person (the CRM then sends with their name and the firm instead of their signature, and says so).

**Step 10. Test, with one person, then everyone.**
1. In the CRM: account menu > **Sign out**, then **Sign in with Google** with a gaard.capital account, and enter the 6-digit code as usual.
2. **Mass Email** > pick anyone > **Preview**. Google's window opens and names **Gaard CRM** with no "unverified" warning. **Tick every box** (send email, and view your email messages and settings) > **Continue**. The preview shows your own Gmail signature. If a yellow note appears instead, it says what is missing (section 5, "Your signature").
3. **Send a test to myself**: it arrives in your inbox with the signature.
4. The **bell** > **Check Gmail for replies**: it runs without an error.
5. **Events** > **Import events** > **From my Google Calendar**: Google asks once for the calendar, and the list appears.
6. Ask each person to do 1 and 2 once. Anyone who sees "Access blocked" is either not on a gaard.capital account, or step 9 is not done.

**Step 11. Tidy up, a week later.** Once everyone has used it for a week without trouble, the builder who owns the old project deletes the old OAuth client (or the whole old "Gaard CRM" project) in their own Google Cloud console. Until then, leave it: it costs nothing, and it is the way back if something was missed.

**If something goes wrong**
- *"Error 400: redirect_uri_mismatch"* when signing in: the redirect URI in step 6.4 is not exactly `https://fgweqsoflzvxkbxgozor.supabase.co/auth/v1/callback`.
- *"Error 400: origin_mismatch"* or nothing happens when sending from Gmail: the site's address is missing from the JavaScript origins in step 6.3 (it must match the address bar, with https and no slash at the end).
- *"Access blocked: this app's request is invalid"* or *"invalid_client"*: the Client ID in Supabase (step 7) or in the CRM (step 8) is the old one, or was copied with a space.
- *"Access blocked: Gaard CRM can only be used within its organization"*: the person signed in with an account outside gaard.capital. That is Internal working as intended.
- To go back: put the old Client ID and secret back in Supabase (step 7) and ask Claude to put the old `GMAIL_CLIENT_ID` back (it is in the repository's history).

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
- **Outcome**: what came of an activity; it decides the next follow-up. You pick from five: No Response, Call, Responded - Interested, Responded - Not Now, Responded - Not Interested. The delivery problems (bounced, out of office, wrong person) sit under them, because each raises its own reminder.
- **Status**: whether a person is **Active**, **Dormant** or **Dead**. Worked out on its own unless you set it. Not the same as Stage.
- **Stage**: where a person sits on the pipeline (Call, Next steps, Onboarding, Funded, Lost). This column used to be called Status.
- **Follow-up (reminder)**: the next thing to do for a person, and when.
- **Opportunity / pipeline**: a person or organization from first call to funded: call, hot, onboarding, funded, or lost.
- **Segment**: the kind of prospect (nonprofit, 401(k), family office, affiliate, and so on).
- **Channel**: how we met them (cold email, event, referral, cold call, RFP...).
- **AUM**: assets under management.
- **Do not contact**: never email or call again (they asked, or a rule says so).
- **In person only (No cold email)**: never cold-emailed; reach out personally.
- **Merge fields**: the `{{...}}` places in a template filled in for each person.
- **Connector**: the address that lets your own Claude work with the CRM.
