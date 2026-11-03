-- Tests for migration 0010 (fresh DB after stubs + 0001..0010).
\set ON_ERROR_STOP on
set client_min_messages = notice;

create schema t10;
create function t10.as_user(p uuid) returns void language sql as $$ select set_config('request.jwt.claim.sub', coalesce(p::text, ''), false) $$;
create function t10.eq(g anyelement, w anyelement, what text) returns void language plpgsql as $$
begin if g is distinct from w then raise exception 'FAIL %: got %, want %', what, g, w; end if; raise notice 'ok: % = %', what, g; end $$;
create function t10.expect_error(p_sql text, p_pat text) returns void language plpgsql as $$
begin begin execute p_sql; exception when others then
  if sqlerrm !~* p_pat then raise exception 'expected /%/, got: %', p_pat, sqlerrm; end if;
  raise notice 'ok (rejected): %', left(sqlerrm, 80); return; end;
  raise exception 'expected /%/ but succeeded', p_pat; end $$;
create table t10.ids (k text primary key, v uuid);
create function t10.id(p text) returns uuid language sql stable as $$ select v from t10.ids where k = p $$;
create function t10.mon(n int) returns date language sql stable as $$ select (date_trunc('month', current_date) - make_interval(months => n))::date $$;
create function t10.post(p_type text, p_on date, p_entries jsonb, p_cat text default null, p_goal uuid default null) returns void language sql as $$
  select public.post_transaction(t10.id('hh'), p_type::public.txn_type, p_on, p_entries, t10.id(p_cat), p_goal_id => p_goal)::text::void $$;
create function t10.e(p_acc text, p_amt bigint) returns jsonb language sql stable as $$ select jsonb_build_object('account_id', t10.id(p_acc), 'amount', p_amt) $$;
grant usage on schema t10 to public; grant select on t10.ids to public; grant execute on all functions in schema t10 to public;

insert into auth.users values ('00000000-0000-0000-0000-0000000000a1', 'levi@example.com'),
  ('00000000-0000-0000-0000-0000000000b2', 'partner@example.com'), ('00000000-0000-0000-0000-0000000000d4', 'stranger@example.com');
insert into t10.ids values ('levi','00000000-0000-0000-0000-0000000000a1'), ('partner','00000000-0000-0000-0000-0000000000b2'),
  ('stranger','00000000-0000-0000-0000-0000000000d4'), ('hh', gen_random_uuid()), ('cash', gen_random_uuid()), ('bpi', gen_random_uuid()),
  ('savings', gen_random_uuid()), ('atome', gen_random_uuid()), ('mine', gen_random_uuid()),
  ('Food', gen_random_uuid()), ('Rent', gen_random_uuid()), ('Salary', gen_random_uuid());
insert into public.households (id, name, created_by) values (t10.id('hh'), 'Test', t10.id('levi'));
insert into public.household_members values (t10.id('hh'), t10.id('levi'), 'owner', now()), (t10.id('hh'), t10.id('partner'), 'member', now());
insert into public.accounts (id, household_id, owner_user_id, name, kind, class, is_spendable, created_by) values
  (t10.id('cash'),    t10.id('hh'), null, 'Cash',     'cash',        'asset',     true,  t10.id('levi')),
  (t10.id('bpi'),     t10.id('hh'), null, 'BPI Bank', 'bank',        'asset',     true,  t10.id('levi')),
  (t10.id('savings'), t10.id('hh'), null, 'Savings',  'savings',     'asset',     false, t10.id('levi')),
  (t10.id('atome'),   t10.id('hh'), null, 'Atome',    'credit_card', 'liability', false, t10.id('levi')),
  (t10.id('mine'),    t10.id('hh'), t10.id('partner'), 'Partner GCash', 'ewallet', 'asset', true, t10.id('partner'));
insert into public.categories (id, household_id, kind, name) values
  (t10.id('Food'), t10.id('hh'), 'expense', 'Food'), (t10.id('Rent'), t10.id('hh'), 'expense', 'Rent'), (t10.id('Salary'), t10.id('hh'), 'income', 'Salary');
insert into t10.ids select 'goal', public.save_goal(t10.id('hh'), null, 'Emergency', 10000000, null, 'account', t10.id('savings'))
  from (select set_config('request.jwt.claim.sub', t10.id('levi')::text, false)) x;

set role authenticated; select t10.as_user(t10.id('levi'));
do $$ begin
  -- last month: salary 30,000; food 5,000 (cash 3,000 + card 2,000); rent 8,000; saved 4,000
  perform t10.post('income',  t10.mon(1) + 1,  jsonb_build_array(t10.e('bpi', 3000000)), 'Salary');
  perform t10.post('expense', t10.mon(1) + 2,  jsonb_build_array(t10.e('cash', -300000)), 'Food');
  perform t10.post('expense', t10.mon(1) + 9,  jsonb_build_array(t10.e('atome', -200000)), 'Food');
  perform t10.post('expense', t10.mon(1) + 4,  jsonb_build_array(t10.e('bpi', -800000)), 'Rent');
  perform t10.post('savings_contribution', t10.mon(1) + 15, jsonb_build_array(t10.e('bpi', -400000), t10.e('savings', 400000)), null, t10.id('goal'));
  -- this month: salary 32,000; food 1,500 minus 300 refund; saved 2,000
  perform t10.post('income',  current_date, jsonb_build_array(t10.e('bpi', 3200000)), 'Salary');
  perform t10.post('expense', current_date, jsonb_build_array(t10.e('cash', -150000)), 'Food');
  perform t10.post('refund',  current_date, jsonb_build_array(t10.e('cash', 30000)), 'Food');
  perform t10.post('savings_contribution', current_date, jsonb_build_array(t10.e('bpi', -200000), t10.e('savings', 200000)), null, t10.id('goal'));
  -- never counted: card payment, transfer, correction, voided expense
  perform t10.post('transfer', current_date, jsonb_build_array(t10.e('bpi', -200000), t10.e('atome', 200000)));
  perform t10.post('transfer', current_date, jsonb_build_array(t10.e('bpi', -100000), t10.e('cash', 100000)));
  perform t10.post('adjustment', current_date, jsonb_build_array(t10.e('cash', -999)));
  perform public.void_transaction(public.post_transaction(t10.id('hh'), 'expense', current_date, jsonb_build_array(t10.e('cash', -777700)), t10.id('Food')), 'test');
end $$;
-- partner spends from a personal wallet this month
select t10.as_user(t10.id('partner'));
select t10.post('expense', current_date, jsonb_build_array(t10.e('mine', -50000)), 'Food');
select t10.as_user(t10.id('levi'));

-- ---------- categories
select t10.eq((select spent from public.report_categories(t10.id('hh'), current_date) where category = 'Food'), 120000::bigint, 'Food this month = 1,500 - 300 refund (Levi cannot see partner''s personal spend)');
select t10.eq((select prev_spent from public.report_categories(t10.id('hh'), current_date) where category = 'Food'), 500000::bigint, 'Food last month = 5,000 incl. card purchase');
select t10.eq((select spent::text || '/' || prev_spent from public.report_categories(t10.id('hh'), current_date) where category = 'Rent'), '0/800000', 'Rent listed for last month only');
select t10.eq((select string_agg(category, ',') from public.report_categories(t10.id('hh'), current_date)), 'Food,Rent', 'sorted by this month''s spending');

-- ---------- trend
select t10.eq((select count(*) from public.report_trend(t10.id('hh'), current_date, 6)), 6::bigint, 'six months, including empty ones');
select t10.eq((select income::text || ' ' || spent || ' ' || saved from public.report_trend(t10.id('hh'), current_date, 6) where month = t10.mon(1)),
              '3000000 1300000 400000', 'last month: income 30,000, spent 13,000, saved 4,000');
select t10.eq((select income::text || ' ' || spent || ' ' || saved from public.report_trend(t10.id('hh'), current_date, 6) where month = t10.mon(0)),
              '3200000 120000 200000', 'this month: transfers, card payment, correction and void excluded');
select t10.eq((select income + spent + saved from public.report_trend(t10.id('hh'), current_date, 6) where month = t10.mon(5)), 0::bigint, 'empty month is zero');
select t10.eq((select count(*) from public.report_trend(t10.id('hh'), current_date, 99)), 24::bigint, 'capped at 24 months');

-- ---------- privacy
select t10.as_user(t10.id('partner'));
select t10.eq((select spent from public.report_categories(t10.id('hh'), current_date) where category = 'Food'), 170000::bigint, 'partner sees shared spending plus their own');
select t10.as_user(t10.id('stranger'));
select t10.eq((select count(*) from public.report_categories(t10.id('hh'), current_date)), 0::bigint, 'outsider sees nothing');
select t10.eq((select sum(income + spent + saved) from public.report_trend(t10.id('hh'), current_date, 6)), 0::numeric, 'outsider sees zeros only');
reset role; set role anon;
select t10.expect_error($$ select * from public.report_trend(t10.id('hh'), current_date, 6) $$, 'permission denied');

\echo '=== 0010 REPORT TESTS PASSED ==='
