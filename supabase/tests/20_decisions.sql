-- Tests for migration 0005 (run on a fresh DB after stubs + 0001..0005).
\set ON_ERROR_STOP on
set client_min_messages = notice;

create schema t5;
create function t5.as_user(p uuid) returns void language sql as $$ select set_config('request.jwt.claim.sub', coalesce(p::text, ''), false) $$;
create function t5.eq(g anyelement, w anyelement, what text) returns void language plpgsql as $$
begin if g is distinct from w then raise exception 'FAIL %: got %, want %', what, g, w; end if; raise notice 'ok: % = %', what, g; end $$;
create function t5.expect_error(p_sql text, p_pat text) returns void language plpgsql as $$
begin begin execute p_sql; exception when others then
  if sqlerrm !~* p_pat then raise exception 'expected /%/, got: %', p_pat, sqlerrm; end if;
  raise notice 'ok (rejected): %', left(sqlerrm, 80); return; end;
  raise exception 'expected /%/ but succeeded', p_pat; end $$;
create table t5.ids (k text primary key, v uuid);
create function t5.id(p text) returns uuid language sql stable as $$ select v from t5.ids where k = p $$;
grant usage on schema t5 to public; grant select on t5.ids to public; grant execute on all functions in schema t5 to public;

insert into auth.users values ('00000000-0000-0000-0000-0000000000a1', 'levi@example.com'),
                              ('00000000-0000-0000-0000-0000000000b2', 'Partner@Example.com'),
                              ('00000000-0000-0000-0000-0000000000c3', 'stranger@example.com');
insert into t5.ids values ('levi','00000000-0000-0000-0000-0000000000a1'),('partner','00000000-0000-0000-0000-0000000000b2'),
                          ('stranger','00000000-0000-0000-0000-0000000000c3'),
                          ('hh', gen_random_uuid()), ('cash', gen_random_uuid()), ('bpi', gen_random_uuid()),
                          ('atome', gen_random_uuid()), ('food', gen_random_uuid()), ('util', gen_random_uuid()),
                          ('sahod', gen_random_uuid());
insert into public.households (id, name, created_by, reserve_horizon, reserve_days, card_debt_mode)
values (t5.id('hh'), 'Test', t5.id('levi'), 'days', 15, 'full');
insert into public.household_members values (t5.id('hh'), t5.id('levi'), 'owner', now());
insert into public.accounts (id, household_id, name, kind, class, is_spendable, created_by) values
  (t5.id('cash'),  t5.id('hh'), 'Cash',  'cash',        'asset',     true,  t5.id('levi')),
  (t5.id('bpi'),   t5.id('hh'), 'BPI Bank', 'bank',     'asset',     true,  t5.id('levi')),
  (t5.id('atome'), t5.id('hh'), 'Atome', 'credit_card', 'liability', false, t5.id('levi'));
insert into public.categories (id, household_id, kind, name) values
  (t5.id('food'), t5.id('hh'), 'expense', 'Pagkain'), (t5.id('util'), t5.id('hh'), 'expense', 'Kuryente'),
  (t5.id('sahod'), t5.id('hh'), 'income', 'Sahod');
-- bills: due in 10 days (inside 15), due in 20 days (outside), and the Atome bill (settles the card)
insert into public.bills (household_id, name, category_id, estimated_amount, starts_on) values
  (t5.id('hh'), 'Meralco', t5.id('util'), 300000, current_date + 10),
  (t5.id('hh'), 'Tubig',   t5.id('util'), 50000,  current_date + 20);
insert into public.bills (household_id, name, category_id, estimated_amount, starts_on, settles_account_id) values
  (t5.id('hh'), 'Atome bill', t5.id('util'), 120000, current_date + 5, t5.id('atome'));
select public.generate_bill_occurrences(current_date + 60);

set role authenticated; select t5.as_user(t5.id('levi'));
do $$ begin
  perform public.post_transaction(t5.id('hh'), 'income', current_date, jsonb_build_array(jsonb_build_object('account_id', t5.id('bpi'), 'amount', 2000000)), t5.id('sahod'));
  perform public.post_transaction(t5.id('hh'), 'opening_balance', current_date, jsonb_build_array(jsonb_build_object('account_id', t5.id('cash'), 'amount', 500000)));
end $$;

-- ---------- rolling 15-day horizon
select t5.eq((select horizon from public.available_to_spend(t5.id('hh'))), current_date + 15, 'horizon = today + 15');

-- ---------- FULL card-debt mode
select t5.eq((select available from public.available_to_spend(t5.id('hh'))), 2200000::bigint, 'before card use: 25,000 - Meralco 3,000 (Tubig outside 15 days)');
do $$ begin perform public.post_transaction(t5.id('hh'), 'expense', current_date,
  jsonb_build_array(jsonb_build_object('account_id', t5.id('atome'), 'amount', -120000)), t5.id('food')); end $$;
select t5.eq((select card_debt from public.available_to_spend(t5.id('hh'))), 120000::bigint, 'card debt counted immediately');
select t5.eq((select available from public.available_to_spend(t5.id('hh'))), 2080000::bigint, 'available drops by the 1,200 card purchase');
select t5.eq((select bills_reserved from public.available_to_spend(t5.id('hh'))), 300000::bigint, 'Atome bill NOT reserved again (no double deduction)');
-- pay the card from BPI: a transfer; available must not move
do $$ begin perform public.post_transaction(t5.id('hh'), 'transfer', current_date, jsonb_build_array(
  jsonb_build_object('account_id', t5.id('bpi'), 'amount', -120000), jsonb_build_object('account_id', t5.id('atome'), 'amount', 120000))); end $$;
select t5.eq((select card_debt from public.available_to_spend(t5.id('hh'))), 0::bigint, 'card paid off');
select t5.eq((select available from public.available_to_spend(t5.id('hh'))), 2080000::bigint, 'paying the card does not change available');

-- ---------- STATEMENT mode on the same data, for contrast
reset role; update public.households set card_debt_mode = 'statement' where id = t5.id('hh');
set role authenticated; select t5.as_user(t5.id('levi'));
do $$ begin perform public.post_transaction(t5.id('hh'), 'expense', current_date,
  jsonb_build_array(jsonb_build_object('account_id', t5.id('atome'), 'amount', -50000)), t5.id('food')); end $$;
select t5.eq((select card_debt from public.available_to_spend(t5.id('hh'))), 0::bigint, 'statement mode: card debt not subtracted directly');
select t5.eq((select bills_reserved from public.available_to_spend(t5.id('hh'))), 420000::bigint, 'statement mode: Atome bill reserved instead');
reset role; update public.households set card_debt_mode = 'full' where id = t5.id('hh');
set role authenticated; select t5.as_user(t5.id('levi'));
select t5.expect_error($$ insert into public.bills (household_id, name, category_id, estimated_amount, starts_on, settles_account_id)
  values (t5.id('hh'), 'x', t5.id('util'), 100, current_date, t5.id('cash')) $$, 'credit card or loan');

-- ---------- INVITES
select t5.expect_error($$ select public.accept_invite(gen_random_uuid()) $$, 'not valid');
create temp table inv as select public.invite_member(t5.id('hh'), '  Partner@Example.com ') as id;
grant select on inv to public;
select t5.eq((select email from public.household_invites where id = (select id from inv)), 'partner@example.com', 'invite email normalised');
select t5.expect_error($$ select public.invite_member(t5.id('hh'), 'levi@example.com') $$, 'already a member');
select t5.expect_error($$ select public.invite_member(t5.id('hh'), 'x@example.com', 'owner') $$, 'admin, member or viewer');
select t5.expect_error($$ insert into public.household_invites (household_id, email, invited_by) values (t5.id('hh'), 'y@example.com', t5.id('levi')) $$, 'permission denied');

select t5.as_user(t5.id('stranger'));
-- regression: non-members get a real FALSE from permission helpers (was NULL)
select t5.eq(kaban_private.can_write(t5.id('hh')), false, 'can_write() is false for a non-member');
select t5.eq(kaban_private.is_admin(t5.id('hh')),  false, 'is_admin() is false for a non-member');
select t5.expect_error($$ select public.invite_member(t5.id('hh'), 'friend@example.com') $$, 'only owners and admins');
select t5.expect_error($$ select public.post_transaction(t5.id('hh'), 'expense', current_date,
  jsonb_build_array(jsonb_build_object('account_id', t5.id('cash'), 'amount', -100)), t5.id('food')) $$, 'not allowed to write');
select t5.eq((select count(*) from public.my_pending_invites()), 0::bigint, 'stranger sees no invite');
select t5.expect_error($$ select public.accept_invite((select id from inv)) $$, 'not valid');
select t5.eq((select count(*) from public.accounts), 0::bigint, 'stranger still sees no accounts');

select t5.as_user(t5.id('partner'));
select t5.eq((select household_name from public.my_pending_invites()), 'Test', 'partner sees the invite');
select t5.eq((select count(*) from public.accounts), 0::bigint, 'partner sees nothing before accepting');
select t5.expect_error($$ select public.invite_member(t5.id('hh'), 'z@example.com') $$, 'only owners and admins');
select public.accept_invite((select id from inv));
select t5.eq((select count(*) from public.accounts), 3::bigint, 'partner sees shared accounts after accepting');
select t5.eq((select role::text from public.household_members where user_id = t5.id('partner')), 'member', 'partner joined as member');
select t5.expect_error($$ select public.accept_invite((select id from inv)) $$, 'not valid');   -- reuse
select t5.expect_error($$ select public.invite_member(t5.id('hh'), 'z@example.com') $$, 'only owners and admins');
-- partner can record shared expenses
do $$ begin perform public.post_transaction(t5.id('hh'), 'expense', current_date,
  jsonb_build_array(jsonb_build_object('account_id', t5.id('cash'), 'amount', -10000)), t5.id('food')); end $$;
select t5.eq((select count(*) from public.transactions where created_by = t5.id('partner')), 1::bigint, 'partner logged an expense');

-- expired invites can't be used
reset role;
insert into public.household_invites (household_id, email, invited_by, expires_at)
values (t5.id('hh'), 'stranger@example.com', t5.id('levi'), now() - interval '1 minute');
set role authenticated; select t5.as_user(t5.id('stranger'));
select t5.expect_error($$ select public.accept_invite((select id from public.household_invites where email = 'stranger@example.com')) $$, 'not valid');

\echo '=== 0005 DECISION TESTS PASSED (continuing) ==='

-- 0006 regression: a negative account WITHOUT earmarks must not raise the over-earmarked flag
reset role;
insert into public.accounts (household_id, name, kind, class, is_spendable, created_by)
values (t5.id('hh'), 'Maya Test', 'ewallet', 'asset', true, t5.id('levi'));
set role authenticated; select t5.as_user(t5.id('levi'));
do $$ begin perform public.post_transaction(t5.id('hh'), 'expense', current_date,
  jsonb_build_array(jsonb_build_object('account_id', (select id from public.accounts where name = 'Maya Test'), 'amount', -5000)), t5.id('food')); end $$;
select t5.eq((select over_earmarked from public.available_to_spend(t5.id('hh'))), false, '0006: negative account with no earmarks is not flagged');
\echo '=== 0006 REGRESSION PASSED ==='
