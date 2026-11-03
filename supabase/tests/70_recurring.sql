-- Tests for migration 0011 (fresh DB after stubs + 0001..0011).
\set ON_ERROR_STOP on
set client_min_messages = notice;

create schema t11;
create function t11.as_user(p uuid) returns void language sql as $$ select set_config('request.jwt.claim.sub', coalesce(p::text, ''), false) $$;
create function t11.eq(g anyelement, w anyelement, what text) returns void language plpgsql as $$
begin if g is distinct from w then raise exception 'FAIL %: got %, want %', what, g, w; end if; raise notice 'ok: % = %', what, g; end $$;
create function t11.expect_error(p_sql text, p_pat text) returns void language plpgsql as $$
begin begin execute p_sql; exception when others then
  if sqlerrm !~* p_pat then raise exception 'expected /%/, got: %', p_pat, sqlerrm; end if;
  raise notice 'ok (rejected): %', left(sqlerrm, 80); return; end;
  raise exception 'expected /%/ but succeeded: %', p_pat, left(p_sql, 120); end $$;
create table t11.ids (k text primary key, v uuid);
create function t11.id(p text) returns uuid language sql stable as $$ select v from t11.ids where k = p $$;
create function t11.first(f text, a int, b int, d date) returns date language sql stable security definer as $$ select kaban_private.recurring_first(f, a, b, d) $$;
create function t11.after(f text, a int, b int, d date) returns date language sql stable security definer as $$ select kaban_private.recurring_after(f, a, b, d) $$;
create function t11.today() returns date language sql stable security definer as $$ select kaban_private.household_today(t11.id('hh')) $$;
create function t11.bal(p text) returns bigint language sql stable as $$ select balance from public.account_balances where account_id = t11.id(p) $$;
create function t11.rec(p_name text) returns public.recurring_entries language sql stable as $$ select * from public.recurring_entries where name = p_name $$;
grant usage on schema t11 to public; grant select on t11.ids to public; grant execute on all functions in schema t11 to public;

insert into auth.users values ('00000000-0000-0000-0000-0000000000a1', 'levi@example.com'),
  ('00000000-0000-0000-0000-0000000000b2', 'partner@example.com'), ('00000000-0000-0000-0000-0000000000c3', 'viewer@example.com');
insert into t11.ids values ('levi','00000000-0000-0000-0000-0000000000a1'), ('partner','00000000-0000-0000-0000-0000000000b2'),
  ('viewer','00000000-0000-0000-0000-0000000000c3'), ('hh', gen_random_uuid()), ('cash', gen_random_uuid()),
  ('bpi', gen_random_uuid()), ('mine', gen_random_uuid()), ('card', gen_random_uuid()),
  ('Food', gen_random_uuid()), ('Subscriptions', gen_random_uuid()), ('Salary', gen_random_uuid());
insert into public.households (id, name, created_by) values (t11.id('hh'), 'Test', t11.id('levi'));
insert into public.household_members values (t11.id('hh'), t11.id('levi'), 'owner', now()),
  (t11.id('hh'), t11.id('partner'), 'member', now()), (t11.id('hh'), t11.id('viewer'), 'viewer', now());
insert into public.accounts (id, household_id, owner_user_id, name, kind, class, is_spendable, created_by) values
  (t11.id('cash'), t11.id('hh'), null, 'Cash', 'cash', 'asset', true, t11.id('levi')),
  (t11.id('bpi'), t11.id('hh'), null, 'BPI Bank', 'bank', 'asset', true, t11.id('levi')),
  (t11.id('mine'), t11.id('hh'), t11.id('levi'), 'Levi GCash', 'ewallet', 'asset', true, t11.id('levi')),
  (t11.id('card'), t11.id('hh'), null, 'Card', 'credit_card', 'liability', false, t11.id('levi'));
insert into public.categories (id, household_id, kind, name) values
  (t11.id('Food'), t11.id('hh'), 'expense', 'Food'), (t11.id('Subscriptions'), t11.id('hh'), 'expense', 'Subscriptions'),
  (t11.id('Salary'), t11.id('hh'), 'income', 'Salary');

-- ---------- schedule math
select t11.eq(t11.after('monthly', 31, null, '2026-01-31'), '2026-02-28'::date, 'monthly on the 31st: Jan 31 -> Feb 28');
select t11.eq(t11.after('monthly', 31, null, '2026-02-28'), '2026-03-31'::date, 'Feb 28 -> Mar 31 (back to the last day)');
select t11.eq(t11.after('monthly', 5, null, '2026-12-05'), '2027-01-05'::date, 'monthly across the year end');
select t11.eq(t11.after('twice_a_month', 15, 31, '2026-02-14'), '2026-02-15'::date, '15th and last day: Feb 14 -> Feb 15');
select t11.eq(t11.after('twice_a_month', 15, 31, '2026-02-15'), '2026-02-28'::date, 'Feb 15 -> Feb 28');
select t11.eq(t11.after('twice_a_month', 15, 31, '2026-02-28'), '2026-03-15'::date, 'Feb 28 -> Mar 15');
select t11.eq(t11.after('weekly', null, null, '2026-11-03'), '2026-11-10'::date, 'weekly adds 7 days');
select t11.eq(t11.after('every_2_weeks', null, null, '2026-11-03'), '2026-11-17'::date, 'every 2 weeks adds 14 days');
select t11.eq(t11.first('twice_a_month', 15, 31, '2026-11-03'), '2026-11-15'::date, 'first date on/after Nov 3 = Nov 15');
select t11.eq(t11.first('twice_a_month', 15, 31, '2026-11-15'), '2026-11-15'::date, 'on the day itself counts');
select t11.eq(t11.first('twice_a_month', 15, 31, '2026-11-16'), '2026-11-30'::date, 'Nov 16 -> Nov 30');
select t11.eq(t11.first('weekly', null, null, '2026-11-04'), '2026-11-04'::date, 'weekly starts on the chosen date');

-- ---------- saving
set role authenticated; select t11.as_user(t11.id('levi'));
select public.save_recurring(t11.id('hh'), null, 'Salary', 'income', 2500000, t11.id('Salary'), t11.id('bpi'), null,
                             'twice_a_month', 15, 31, t11.today(), false);
select t11.eq((t11.rec('Salary')).next_due, t11.first('twice_a_month', 15, 31, t11.today()), 'next date snapped to the 15th or last day');
select t11.eq((t11.rec('Salary')).owner_user_id, null::uuid, 'shared account = shared repeating entry');
select public.save_recurring(t11.id('hh'), null, 'Netflix', 'expense', 54900, t11.id('Subscriptions'), t11.id('card'), null,
                             'monthly', 31, 7, t11.today(), true);
select t11.eq((t11.rec('Netflix')).day2, null::smallint, 'monthly ignores a second day');
select public.save_recurring(t11.id('hh'), null, 'My allowance', 'transfer', 100000, t11.id('Food'), t11.id('bpi'), t11.id('mine'),
                             'weekly', null, null, t11.today(), false);
select t11.eq((t11.rec('My allowance')).category_id, null::uuid, 'transfer drops the category');
select t11.eq((t11.rec('My allowance')).owner_user_id, t11.id('levi'), 'touches my personal account = personal');

select t11.expect_error($$ select public.save_recurring(t11.id('hh'), null, 'X', 'income', 100, t11.id('Salary'), t11.id('card'), null, 'monthly', 1, null, t11.today(), false) $$, 'money account');
select t11.expect_error($$ select public.save_recurring(t11.id('hh'), null, 'X', 'income', 100, t11.id('Food'), t11.id('bpi'), null, 'monthly', 1, null, t11.today(), false) $$, 'category not available');
select t11.expect_error($$ select public.save_recurring(t11.id('hh'), null, 'X', 'transfer', 100, null, t11.id('bpi'), t11.id('bpi'), 'monthly', 1, null, t11.today(), false) $$, 'different accounts');
select t11.expect_error($$ select public.save_recurring(t11.id('hh'), null, 'X', 'expense', 100, t11.id('Food'), t11.id('cash'), null, 'twice_a_month', 15, 15, t11.today(), false) $$, 'two different days');
select t11.expect_error($$ select public.save_recurring(t11.id('hh'), null, 'X', 'expense', 0, t11.id('Food'), t11.id('cash'), null, 'monthly', 1, null, t11.today(), false) $$, 'more than zero');
select t11.expect_error($$ select public.save_recurring(t11.id('hh'), null, 'X', 'expense', 100, t11.id('Food'), t11.id('cash'), null, 'monthly', 1, null, t11.today() - 90, false) $$, 'within the last month');
select t11.expect_error($$ insert into public.recurring_entries (household_id, name, kind, amount, category_id, account_id, frequency, day1, next_due, created_by) values (t11.id('hh'), 'X', 'expense', 1, t11.id('Food'), t11.id('cash'), 'monthly', 1, current_date, t11.id('levi')) $$, 'permission denied');
select t11.expect_error($$ select * from public.run_daily_entries() $$, 'permission denied');

-- ---------- confirming and skipping
do $$
declare r public.recurring_entries := t11.rec('Salary'); v1 uuid; v2 uuid;
begin
  v1 := public.record_recurring(r.id, r.next_due, 2480000, t11.today(), 'k-salary-1');   -- arrived early, a bit less
  v2 := public.record_recurring(r.id, r.next_due, 2480000, t11.today(), 'k-salary-1');   -- double tap
  perform t11.eq(v2, v1, 'same request twice = one entry');
  perform t11.eq(t11.bal('bpi'), 2480000::bigint, 'the amount actually received was recorded');
  perform t11.eq((select recurring_id from public.transactions where id = v1), r.id, 'entry is linked to its repeating entry');
  perform t11.eq((select description from public.transactions where id = v1), 'Salary', 'entry is named after it');
  perform t11.eq((t11.rec('Salary')).next_due, t11.after('twice_a_month', 15, 31, r.next_due), 'moved on to the next pay date');
end $$;
select t11.expect_error($$ select public.record_recurring((t11.rec('Salary')).id, (t11.rec('Salary')).next_due - 1, 1, current_date, 'k-other') $$, 'already recorded or skipped');
do $$
declare r public.recurring_entries := t11.rec('Salary');
begin
  perform public.skip_recurring(r.id, r.next_due);
  perform public.skip_recurring(r.id, r.next_due);            -- the same skip again does nothing more
  perform t11.eq((t11.rec('Salary')).next_due, t11.after('twice_a_month', 15, 31, r.next_due), 'skip moves one date only');
  perform t11.eq(t11.bal('bpi'), 2480000::bigint, 'skipping records nothing');
end $$;

-- ---------- visibility and permissions
select t11.as_user(t11.id('partner'));
select t11.eq((select count(*) from public.recurring_entries), 2::bigint, 'partner sees the shared ones, not my personal allowance');
select t11.expect_error($$ select public.stop_recurring((select id from public.recurring_entries where owner_user_id is not null limit 1)) $$, 'not available');
select t11.as_user(t11.id('viewer'));
select t11.expect_error($$ select public.skip_recurring((t11.rec('Salary')).id, (t11.rec('Salary')).next_due) $$, 'not available');
select t11.expect_error($$ select public.save_recurring(t11.id('hh'), null, 'X', 'expense', 100, t11.id('Food'), t11.id('cash'), null, 'monthly', 1, null, t11.today(), false) $$, 'not allowed to write');
reset role; set role anon;
select t11.expect_error($$ select * from public.recurring_entries $$, 'permission denied');
reset role;

-- ---------- the daily job: automatic entries catch up, and only once
update public.recurring_entries set next_due = t11.today() - 20 where name = 'Netflix';
update public.recurring_entries set frequency = 'weekly', day1 = null where name = 'Netflix';
select t11.eq((select recorded from public.run_daily_entries()), 3, 'weekly, 20 days behind: three automatic entries');
select t11.eq(t11.bal('card'), -164700::bigint, 'card charged 3 x 549');
select t11.eq((t11.rec('Netflix')).next_due, t11.today() + 1, 'next one is tomorrow');
select t11.eq((select count(*) from public.transactions where recurring_id = (t11.rec('Netflix')).id and source = 'system'), 3::bigint, 'marked as automatic');
select t11.eq((select recorded from public.run_daily_entries()), 0, 'running again records nothing');
update public.recurring_entries set next_due = t11.today() - 6 where name = 'Netflix';    -- pretend the date was moved back
select t11.eq((select recorded from public.run_daily_entries()), 1, 'already-recorded dates are not posted twice');
select t11.eq(t11.bal('card'), -164700::bigint, 'still 3 x 549 (same date, same key)');
select t11.eq((select recorded from public.run_daily_entries()), 0, 'and then nothing more');

-- the person who set it up can no longer write: it fails, keeps nothing, and says why
update public.household_members set role = 'viewer' where user_id = t11.id('levi');
update public.recurring_entries set next_due = t11.today() where name = 'Netflix';
select t11.eq((select failed from public.run_daily_entries()), 1, 'automatic entry fails cleanly');
select t11.eq((t11.rec('Netflix')).next_due, t11.today(), 'stays due, retried tomorrow');
select t11.eq((t11.rec('Netflix')).last_error is not null, true, 'reason saved for the app');
update public.household_members set role = 'owner' where user_id = t11.id('levi');
select t11.eq((select recorded from public.run_daily_entries()), 1, 'works again once allowed');
select t11.eq((t11.rec('Netflix')).last_error, null::text, 'error cleared');

-- confirm-first entries are never posted by the job
update public.recurring_entries set next_due = t11.today() - 3 where name = 'Salary';
select public.run_daily_entries();
select t11.eq(t11.bal('bpi'), 2480000::bigint, 'asks-first salary was not recorded automatically');

-- ---------- the fix: entries dated ahead post on their date
set role authenticated; select t11.as_user(t11.id('levi'));
select public.post_transaction(t11.id('hh'), 'expense', t11.today() + 2,
  jsonb_build_array(jsonb_build_object('account_id', t11.id('cash'), 'amount', -30000)), t11.id('Food'), 'Birthday cake');
select t11.eq(t11.bal('cash'), 0::bigint, 'dated ahead: not in the balance yet');
reset role;
select t11.eq((select posted_scheduled from public.run_daily_entries()), 0, 'not before its date');
update public.transactions set occurred_on = t11.today() where description = 'Birthday cake';   -- time passes
select t11.eq((select posted_scheduled from public.run_daily_entries()), 1, 'posted on its date');
select t11.eq(t11.bal('cash'), -30000::bigint, 'now in the balance');

-- ---------- stopping
set role authenticated; select t11.as_user(t11.id('levi'));
select public.stop_recurring((t11.rec('Salary')).id);
select t11.expect_error($$ select public.record_recurring((t11.rec('Salary')).id, (t11.rec('Salary')).next_due, 1, current_date, 'k-x') $$, 'stopped');
select t11.eq((select count(*) from public.transactions where recurring_id = (t11.rec('Salary')).id), 1::bigint, 'recorded entries stay after stopping');
-- editing brings it back with a new schedule
select public.save_recurring(t11.id('hh'), (t11.rec('Salary')).id, 'Salary', 'income', 2600000, t11.id('Salary'), t11.id('bpi'), null,
                             'monthly', 30, null, t11.today(), false);
select t11.eq((t11.rec('Salary')).is_active, true, 'editing restarts it');
select t11.eq((t11.rec('Salary')).next_due, t11.first('monthly', 30, null, t11.today()), 'new schedule applies');
reset role;

\echo '=== 0011 RECURRING TESTS PASSED ==='
