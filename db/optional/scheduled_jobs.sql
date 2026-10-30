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

-- Monday mornings: the weekly data check (db/013), written to data_check_runs / v_data_check_latest
select cron.schedule('crm-weekly-data-check', '30 13 * * 1',
                     $$select public.run_data_checks('weekly')$$);

-- to see or remove them:
--   select * from cron.job;
--   select * from cron.job_run_details order by start_time desc limit 10;
--   select cron.unschedule('crm-stale-opportunities');
