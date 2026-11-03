-- =====================================================================
-- KABAN: daily job for dated-ahead and repeating entries.
-- Migration 0011 already does this when pg_cron is installed; run this
-- only if 0011 said "pg_cron is not installed yet". Safe to run again.
-- =====================================================================

create extension if not exists pg_cron;

do $$
begin
  perform cron.unschedule(jobname) from cron.job where jobname = 'kaban-daily-entries';
end $$;

select cron.schedule('kaban-daily-entries', '10 16 * * *',   -- 16:10 UTC = 00:10 in Manila
                     'select public.run_daily_entries()');

select jobname, schedule, active from cron.job where jobname like 'kaban-%' order by jobname;
