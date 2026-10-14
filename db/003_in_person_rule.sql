/* ======================================================================
   003  NO COLD EMAIL: IN PERSON
   Run once in the Supabase SQL Editor. Safe to run again.

   Universities, and organizations Gaard would rather reach through people,
   get no cold email. They are labelled by email domain (flag_rules, flag
   'university', which contacts_before_write already turns into
   contacts.is_university_affiliated) and get a reminder to reach out in
   person instead. The app shows the label as "No cold email: in person"
   and leaves these contacts out of the mail merge.

   This adds the reminder type and the two domains Jon named. More domains
   are added in the app under Settings > Email domains with a rule.
   ====================================================================== */

begin;

insert into public.reminder_types (code, label, sort_order)
select 'in_person', 'Reach out in person', coalesce(max(sort_order), 0) + 1 from public.reminder_types
on conflict (code) do nothing;

insert into public.flag_rules (match_on, pattern, flag, reason, is_active)
select 'email_domain', v.pattern, 'university', 'University: reach out in person', true
  from (values ('utah.edu'), ('byu.edu')) v(pattern)
 where not exists (select 1 from public.flag_rules f
                    where f.match_on = 'email_domain' and lower(f.pattern) = v.pattern);

-- Label the contacts already on file that these rules match
select public.reapply_flag_rules();

commit;
