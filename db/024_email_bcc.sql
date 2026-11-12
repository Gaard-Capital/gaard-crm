-- 024_email_bcc.sql
--
-- One column: who a letter was blind-copied to. "Write an email" and "Reply
-- from my Gmail" on a contact's page now have To, Cc and Bcc lines, as in
-- Gmail; To and Cc already had columns (to_emails, cc_emails), Bcc had none.
--
-- Safe to run twice. The app does not need it: until this has been run it
-- writes the Bcc addresses at the foot of the activity ("(Bcc: ...)") instead,
-- so nothing is lost. Once it has been run, the Bcc line shows above the
-- letter on the contact's Activity like To and Cc.

begin;

alter table public.email_messages
  add column if not exists bcc_emails text[] not null default '{}';

commit;
