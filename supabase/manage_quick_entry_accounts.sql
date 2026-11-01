-- =====================================================================
-- KABAN: change the "Saan galing?" choices of your Back Tap Shortcut.
-- Run ONE block at a time in the Supabase SQL Editor (highlight it, then Run).
-- The Shortcut picks up changes on its next tap; nothing to edit on the iPhone.
-- =====================================================================

-- 0. SEE what the menu shows now -------------------------------------
select a.name, a.id = q.default_account_id as una_sa_listahan
  from public.quick_entry_tokens q
  join public.accounts a on a.id = q.default_account_id or a.id = any (q.allowed_account_ids)
 where q.user_id = (select id from auth.users where email = 'levisenseisagebulacan@gmail.com')
   and q.revoked_at is null
 order by 2 desc, 1;


-- 1. ADD a new account and put it in the menu ------------------------
--    Change 'UnionBank' and 'bank' (choices: cash, bank, ewallet, other).
with me as (
  select m.user_id, m.household_id from public.household_members m
   where m.user_id = (select id from auth.users where email = 'levisenseisagebulacan@gmail.com')
), new_acct as (
  insert into public.accounts (household_id, name, kind, class, is_spendable, created_by)
  select household_id, 'UnionBank', 'bank', 'asset', true, user_id from me
  returning id
)
update public.quick_entry_tokens q
   set allowed_account_ids = q.allowed_account_ids || (select id from new_acct)
 where q.user_id = (select user_id from me) and q.revoked_at is null;


-- 2. ADD an EXISTING account to the menu -----------------------------
update public.quick_entry_tokens q
   set allowed_account_ids = array(select distinct unnest(q.allowed_account_ids || a.id))
  from public.accounts a
 where a.household_id = q.household_id and a.name = 'Maya'
   and q.user_id = (select id from auth.users where email = 'levisenseisagebulacan@gmail.com')
   and q.revoked_at is null;


-- 3. REMOVE an account from the menu (the account itself stays) ------
update public.quick_entry_tokens q
   set allowed_account_ids = array_remove(q.allowed_account_ids, a.id)
  from public.accounts a
 where a.household_id = q.household_id and a.name = 'BPI'
   and q.user_id = (select id from auth.users where email = 'levisenseisagebulacan@gmail.com')
   and q.revoked_at is null;


-- 4. RENAME an account (menu shows the new name) ---------------------
update public.accounts a
   set name = 'GCash (Levi)'
 where a.name = 'GCash'
   and a.household_id = (select household_id from public.household_members
                          where user_id = (select id from auth.users where email = 'levisenseisagebulacan@gmail.com'));


-- 5. CHANGE which account is FIRST in the menu (the default) ---------
update public.quick_entry_tokens q
   set allowed_account_ids = array(select distinct unnest(q.allowed_account_ids || q.default_account_id)),
       default_account_id  = a.id
  from public.accounts a
 where a.household_id = q.household_id and a.name = 'GCash'
   and q.user_id = (select id from auth.users where email = 'levisenseisagebulacan@gmail.com')
   and q.revoked_at is null;
