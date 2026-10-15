-- =====================================================================
-- GAARD Capital CRM · Scheduled jobs (optional, Supabase only)
--
-- Run once, after turning on the pg_cron extension
-- (Supabase dashboard > Database > Extensions > pg_cron).
-- Times are UTC: 13:00 UTC = 7:00 Mountain in summer, 6:00 in winter.
-- =====================================================================

-- every morning: snoozed reminders come back to the notifications tab
select cron.schedule('crm-wake-snoozed-reminders', '0 13 * * *',
                     $$select public.wake_snoozed_reminders()$$);

-- Monday mornings: open opportunities with no activity in 3 weeks get a reminder
select cron.schedule('crm-stale-opportunities', '15 13 * * 1',
                     $$select public.flag_stale_opportunities(21)$$);

-- to see or remove them:
--   select * from cron.job;
--   select cron.unschedule('crm-stale-opportunities');
