-- 010: the booking link line in the shared email templates
--
-- Adds one line above the signature of every template that does not have it yet:
--     If it is easier, pick a time here: {{booking_link}}
-- {{booking_link}} is filled with the sender's own Google Calendar booking page
-- (Settings, db/009). For a sender who has not set one, the app leaves the whole
-- line out, so no one ever receives the raw tag.
--
-- Templates without a {{sender_name}} signature line are left alone; add the line
-- by hand in Follow-ups > Email templates if you want it there.
--
-- Safe to run twice: a template that already mentions the booking link is skipped.

begin;

update public.email_templates
   set body = regexp_replace(body, E'\n\\{\\{sender_name\\}\\}', E'\nIf it is easier, pick a time here: {{booking_link}}\n\n{{sender_name}}'),
       updated_at = now()
 where body !~* 'booking[ _]link'
   and body ~ E'\\{\\{sender_name\\}\\}';

commit;

-- What changed
select name, position('{{booking_link}}' in body) > 0 as has_booking_link
  from public.email_templates
 order by name;
