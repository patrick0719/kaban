-- =====================================================================
-- KABAN: daily jobs for bills (run once, after migration 0007 and after
-- deploying the bill-reminders Edge Function).
--
--   00:05 Manila  keep 400 days of bill due dates
--   09:00 Manila  send today's bill reminders
--
-- Replace PASTE_CRON_SECRET with the same CRON_SECRET you saved in
-- Edge Functions -> Secrets. Safe to run again (it replaces the jobs).
-- =====================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
begin
  perform cron.unschedule(jobname) from cron.job
   where jobname in ('kaban-bill-due-dates', 'kaban-bill-reminders');
end $$;

select cron.schedule(
  'kaban-bill-due-dates',
  '5 16 * * *',                                    -- 16:05 UTC = 00:05 in Manila
  $$select public.generate_bill_occurrences(current_date + 400)$$
);

select cron.schedule(
  'kaban-bill-reminders',
  '0 1 * * *',                                     -- 01:00 UTC = 09:00 in Manila
  $$select net.http_post(
      url     := 'https://cnilwqcgsbbmvadsbzjh.supabase.co/functions/v1/bill-reminders',
      headers := jsonb_build_object('Content-Type', 'application/json',
                                    'x-cron-secret', 'PASTE_CRON_SECRET'),
      body    := '{}'::jsonb
    )$$
);

select jobname, schedule, active from cron.job where jobname like 'kaban-%' order by jobname;
