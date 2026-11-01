-- =====================================================================
-- KABAN one-time setup: your household, accounts, categories, and the
-- first quick-entry token for your iPhone Shortcut.
--
-- BEFORE RUNNING:
--   1. Supabase Dashboard -> Authentication -> Users -> Add user
--      (your email + a password, tick "Auto Confirm User").
--   2. Values below are already filled in (change them if needed).
--   3. Run this whole file once in the SQL Editor.
--
-- The last result row shows your token ONCE. Copy it straight into the
-- Shortcut. Only its hash is stored, so it cannot be shown again
-- (if you lose it, revoke it and make a new one).
-- =====================================================================

create temp table settings as select
  'levisenseisagebulacan@gmail.com'::text as my_email,  -- the email you added in Authentication
  'Aming Household'::text       as household_name,
  'Cash'::text                  as quick_entry_account; -- first choice in the "Saan galing?" menu

do $$
declare
  s        record;
  v_user   uuid;
  v_hh     uuid;
begin
  select * into s from settings;
  select id into v_user from auth.users where email = s.my_email;
  if v_user is null then
    raise exception 'No user with email %. Add it first in Authentication -> Users.', s.my_email;
  end if;
  if exists (select 1 from public.household_members where user_id = v_user) then
    raise exception 'This user already has a household. Setup was already run.';
  end if;

  insert into public.households (name, created_by) values (s.household_name, v_user) returning id into v_hh;
  insert into public.household_members (household_id, user_id, role) values (v_hh, v_user, 'owner');

  -- Shared accounts. Balances start at 0; add opening balances in the app later.
  insert into public.accounts (household_id, name, kind, class, is_spendable, created_by) values
    (v_hh, 'Cash',           'cash',    'asset', true,  v_user),
    (v_hh, 'GCash',          'ewallet', 'asset', true,  v_user),
    (v_hh, 'Maya',           'ewallet', 'asset', true,  v_user),
    (v_hh, 'BPI',            'bank',    'asset', true,  v_user),
    (v_hh, 'GoTyme Savings', 'savings', 'asset', false, v_user);   -- outside the spending pool

  insert into public.categories (household_id, kind, name) values
    (v_hh, 'income',  'Sahod'),
    (v_hh, 'income',  'Iba pang kita'),
    (v_hh, 'expense', 'Pagkain'),
    (v_hh, 'expense', 'Grocery'),
    (v_hh, 'expense', 'Transportasyon'),
    (v_hh, 'expense', 'Load at Internet'),
    (v_hh, 'expense', 'Kuryente'),
    (v_hh, 'expense', 'Tubig'),
    (v_hh, 'expense', 'Upa at Bahay'),
    (v_hh, 'expense', 'Gamot at Kalusugan'),
    (v_hh, 'expense', 'Eskwela'),
    (v_hh, 'expense', 'Personal'),
    (v_hh, 'expense', 'Iba pa');

  -- Act as this user for the token call (it checks auth.uid()).
  perform set_config('request.jwt.claim.sub', v_user::text, false);
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, false);
end $$;

-- Your first quick-entry token: expenses only, from Cash, GCash, Maya or BPI;
-- max PHP 20,000 per entry, 30 entries a day, valid 90 days.
select t.token      as "COPY THIS TOKEN NOW (shown once)",
       t.expires_at as "expires"
  from public.create_quick_entry_token(
         (select m.household_id from public.household_members m
            join auth.users u on u.id = m.user_id
           where u.email = (select my_email from settings)),
         'My iPhone',
         (select a.id from public.accounts a
            join public.household_members m on m.household_id = a.household_id
            join auth.users u on u.id = m.user_id
           where u.email = (select my_email from settings)
             and a.name = (select quick_entry_account from settings)),
         p_allowed_accounts => array(           -- the "Saan galing?" choices:
           select a.id from public.accounts a    -- every spendable shared account (not savings)
             join public.household_members m on m.household_id = a.household_id
             join auth.users u on u.id = m.user_id
            where u.email = (select my_email from settings)
              and a.is_spendable and a.owner_user_id is null and not a.is_archived)
       ) t;
