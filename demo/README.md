# Demo files

Sample inputs for showing the CRM, in the shapes Jon's real data comes in. Everything here is
fictional: emails use the reserved `.example` domain and phones the 555-01xx range, so nothing can
reach a real person. Use them with the demo data ("Use the demo data instead" on the sign-in page)
or on a test database, never mixed into real data.

| File | What it shows | Where to use it |
|---|---|---|
| `1_contacts_messy.csv` | A sourcing sheet in Jon's columns, deliberately messy: capitals and spaces in emails, `$11 million` and `$4.2M`, "NR" and "no reply", a broken email (`lbenson@`), a row without an email, the same person twice, and Isabella Foster, who is already on file, with a new phone number. | Import: drop the file, Continue. The check asks only about the rows that need a person. |
| `2_met_at_event.txt` | "Met at Park City Philanthropy Lunch" on the first line, then three people. | Import: paste the text. The event is new, so the check screen offers it as "+ A new event"; on import it appears on the Events page with the three people. |
| `3_business_cards/` | Three photos of business cards. Card 3 is Isabella Foster again, with the new phone. | Import: drop the three pictures (on a phone, tap the box and take photos), write "Met at Park City Philanthropy Lunch" in the box, Continue. Two new people; Isabella's phone is updated and the meeting is added to her activity. |
| `4_client_replies.txt` | Four replies to the first cold email: interested, out of office, not now, already has an advisor. The senders are in the demo data. | Import: paste the text. Each reply is matched to its sender and given an outcome, which schedules the next follow-up. |
| `5_event_tracker.csv` | Jon's Event ROI Tracker columns (Date, Cost, Event Name, Event Type, State, # of Contacts, ...). | Events > Bring in events > From my event tracker file. Run it twice: the second time every event is "Already there". |
| `6_rfp_log.csv` | Jon's RFP Log columns. | The RFP log is loaded in the SQL Editor (`import_gaard_tab(..., 'RFPs')`, see `db/docs/import_playbook.md`). On the RFPs page, Update marks one won or lost, and Email writes to ask who won and how we scored. |

## A ten-minute walk-through (for a live demo or the video)

1. **Contacts**: the list, the Correspondence column, one person's page with their activity.
2. **Import** `1_contacts_messy.csv`: what was cleaned up on its own, the few questions, Isabella matched.
3. **Import** the business cards with "Met at Park City Philanthropy Lunch"; open **Events** to show the new event and the people met there.
4. **Mass Email**: tick a few contacts on Contacts, Mail merge, the letter per person, the booking link box, send a test to yourself.
5. **Replies**: paste `4_client_replies.txt` into Import (or, live, "Check Gmail for replies" under the bell); show the outcome set and the follow-up scheduled, and Change.
6. **Follow-ups**: what is due, Log activity, Move.
7. **Events > Bring in events** with `5_event_tracker.csv`.
8. **RFPs**: Update one to Lost with who won; Email; the follow-up on Follow-ups.
9. **Dashboard** and **KPIs**.
10. **Settings > Data health**: the weekly check that keeps every record under the right person.
