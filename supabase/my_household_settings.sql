-- =====================================================================
-- KABAN: your household's decisions (run after migration 0005).
--
--   Sahod twice a month, no fixed date -> reserve bills due in the next 15 days
--   Credit card                        -> full debt subtracted immediately
--
-- Safe to run again. Change the values and re-run if you change your mind.
-- =====================================================================

update public.households h
   set reserve_horizon = 'days',      -- rolling window instead of a fixed payday
       reserve_days    = 15,          -- bills due within 15 days (plus overdue) are reserved
       card_debt_mode  = 'full'       -- 'statement' to subtract card debt only via its bill
 where h.id = (select m.household_id from public.household_members m
                 join auth.users u on u.id = m.user_id
                where u.email = 'levisenseisagebulacan@gmail.com' and m.role = 'owner');

select name, reserve_horizon, reserve_days, card_debt_mode
  from public.households h
 where h.id = (select m.household_id from public.household_members m
                 join auth.users u on u.id = m.user_id
                where u.email = 'levisenseisagebulacan@gmail.com' and m.role = 'owner');
