-- Tests for migration 0009 (fresh DB after stubs + 0001..0009).
\set ON_ERROR_STOP on
set client_min_messages = notice;

create schema t9;
create function t9.as_user(p uuid) returns void language sql as $$ select set_config('request.jwt.claim.sub', coalesce(p::text, ''), false) $$;
create function t9.eq(g anyelement, w anyelement, what text) returns void language plpgsql as $$
begin if g is distinct from w then raise exception 'FAIL %: got %, want %', what, g, w; end if; raise notice 'ok: % = %', what, g; end $$;
create function t9.expect_error(p_sql text, p_pat text) returns void language plpgsql as $$
begin begin execute p_sql; exception when others then
  if sqlerrm !~* p_pat then raise exception 'expected /%/, got: %', p_pat, sqlerrm; end if;
  raise notice 'ok (rejected): %', left(sqlerrm, 80); return; end;
  raise exception 'expected /%/ but succeeded: %', p_pat, left(p_sql, 120); end $$;
create table t9.ids (k text primary key, v uuid);
create function t9.id(p text) returns uuid language sql stable as $$ select v from t9.ids where k = p $$;
-- first day of the month N months before this one
create function t9.mon(n int) returns date language sql stable as $$ select (date_trunc('month', current_date) - make_interval(months => n))::date $$;
create function t9.row(p_cat text) returns jsonb language sql stable as $$
  select to_jsonb(b) from public.budget_status(t9.id('hh'), current_date) b where b.category = p_cat $$;
create function t9.spend(p_cat text, p_amount bigint, p_on date, p_acc text default 'cash') returns void language sql as $$
  select public.post_transaction(t9.id('hh'), 'expense', p_on, jsonb_build_array(jsonb_build_object('account_id', t9.id(p_acc), 'amount', -p_amount)), t9.id(p_cat))::text::void $$;
grant usage on schema t9 to public; grant select on t9.ids to public; grant execute on all functions in schema t9 to public;

insert into auth.users values ('00000000-0000-0000-0000-0000000000a1', 'levi@example.com'), ('00000000-0000-0000-0000-0000000000c3', 'viewer@example.com');
insert into t9.ids values ('levi','00000000-0000-0000-0000-0000000000a1'), ('viewer','00000000-0000-0000-0000-0000000000c3'),
  ('hh', gen_random_uuid()), ('cash', gen_random_uuid()), ('bpi', gen_random_uuid()), ('atome', gen_random_uuid()),
  ('Food', gen_random_uuid()), ('Groceries', gen_random_uuid()), ('Electricity', gen_random_uuid()), ('Transport', gen_random_uuid()),
  ('Salary', gen_random_uuid());
insert into public.households (id, name, created_by) values (t9.id('hh'), 'Test', t9.id('levi'));
insert into public.household_members values (t9.id('hh'), t9.id('levi'), 'owner', now()), (t9.id('hh'), t9.id('viewer'), 'viewer', now());
insert into public.accounts (id, household_id, name, kind, class, is_spendable, created_by) values
  (t9.id('cash'), t9.id('hh'), 'Cash', 'cash', 'asset', true, t9.id('levi')),
  (t9.id('bpi'), t9.id('hh'), 'BPI Bank', 'bank', 'asset', true, t9.id('levi')),
  (t9.id('atome'), t9.id('hh'), 'Atome', 'credit_card', 'liability', false, t9.id('levi'));
insert into public.categories (id, household_id, kind, name) values
  (t9.id('Food'), t9.id('hh'), 'expense', 'Food'), (t9.id('Groceries'), t9.id('hh'), 'expense', 'Groceries'),
  (t9.id('Electricity'), t9.id('hh'), 'expense', 'Electricity'), (t9.id('Transport'), t9.id('hh'), 'expense', 'Transport'),
  (t9.id('Salary'), t9.id('hh'), 'income', 'Salary');

set role authenticated; select t9.as_user(t9.id('levi'));
do $$ begin
  perform public.post_transaction(t9.id('hh'), 'opening_balance', t9.mon(4), jsonb_build_array(jsonb_build_object('account_id', t9.id('cash'), 'amount', 10000000)));
  -- Food: 3,000 / 4,000 / 5,000 over the last three months  -> average 4,000
  perform t9.spend('Food', 300000, t9.mon(3) + 4);
  perform t9.spend('Food', 400000, t9.mon(2) + 9);
  perform t9.spend('Food', 250000, t9.mon(1) + 2);
  perform t9.spend('Food', 250000, t9.mon(1) + 20, 'atome');                -- card purchases count as spending
  -- Groceries only last month, 6,050                         -> 6,050 / 3 = 2,016.67, suggested 2,100
  perform t9.spend('Groceries', 605000, t9.mon(1) + 5);
  -- this month: Food 1,500 then a 200 refund
  perform t9.spend('Food', 150000, current_date);
  perform public.post_transaction(t9.id('hh'), 'refund', current_date,
    jsonb_build_array(jsonb_build_object('account_id', t9.id('cash'), 'amount', 20000)), t9.id('Food'));
  -- things that must NOT count: a transfer, a card payment, a correction, a voided expense, an older month (4 months ago)
  perform public.post_transaction(t9.id('hh'), 'transfer', current_date, jsonb_build_array(
    jsonb_build_object('account_id', t9.id('cash'), 'amount', -100000), jsonb_build_object('account_id', t9.id('bpi'), 'amount', 100000)));
  perform public.post_transaction(t9.id('hh'), 'transfer', current_date, jsonb_build_array(
    jsonb_build_object('account_id', t9.id('bpi'), 'amount', -250000), jsonb_build_object('account_id', t9.id('atome'), 'amount', 250000)));
  perform public.post_transaction(t9.id('hh'), 'adjustment', current_date, jsonb_build_array(jsonb_build_object('account_id', t9.id('cash'), 'amount', -5000)));
  perform public.void_transaction(public.post_transaction(t9.id('hh'), 'expense', current_date,
    jsonb_build_array(jsonb_build_object('account_id', t9.id('cash'), 'amount', -999900)), t9.id('Food')), 'test');
  perform t9.spend('Food', 999900, t9.mon(4) + 3);
end $$;

-- ---------- spending and history
select t9.eq((t9.row('Food')->>'spent')::bigint, 130000::bigint, 'Food this month = 1,500 - 200 refund (transfers, card payment, void ignored)');
select t9.eq((t9.row('Food')->>'months_of_history')::int, 3, 'three months of history');
select t9.eq((t9.row('Food')->>'avg_spent')::bigint, 400000::bigint, 'Food averages 4,000 a month (older month ignored)');
select t9.eq((t9.row('Food')->>'suggested')::bigint, 400000::bigint, 'Food suggestion 4,000');
select t9.eq((t9.row('Groceries')->>'avg_spent')::bigint, 201667::bigint, 'Groceries averaged over all 3 months');
select t9.eq((t9.row('Groceries')->>'suggested')::bigint, 210000::bigint, 'Groceries suggestion rounded up to 2,100');
select t9.eq((t9.row('Electricity')->>'suggested')::bigint, null::bigint, 'no spending, no suggestion');
select t9.eq((t9.row('Food')->>'budget')::bigint, null::bigint, 'no budget yet');

-- ---------- setting budgets; they carry forward
select public.set_budget(t9.id('hh'), t9.id('Food'), 450000, t9.mon(1));
select t9.eq((t9.row('Food')->>'budget')::bigint, 450000::bigint, 'last month''s budget carries into this month');
select public.set_budget(t9.id('hh'), t9.id('Food'), 500000);
select t9.eq((t9.row('Food')->>'budget')::bigint, 500000::bigint, 'this month''s change wins');
select t9.eq((select budget from public.budget_status(t9.id('hh'), t9.mon(1)) where category = 'Food'), 450000::bigint, 'last month keeps its own budget');
select public.set_budgets(t9.id('hh'), jsonb_build_array(
  jsonb_build_object('category_id', t9.id('Groceries'), 'amount', 210000),
  jsonb_build_object('category_id', t9.id('Transport'), 'amount', 150000)));
select t9.eq((select count(*) from public.budget_status(t9.id('hh'), current_date) where budget is not null), 3::bigint, 'applied several suggestions at once');
select public.set_budget(t9.id('hh'), t9.id('Transport'), 0);
select t9.eq((t9.row('Transport')->>'budget')::bigint, null::bigint, 'setting 0 removes the budget');
select t9.expect_error($$ select public.set_budget(t9.id('hh'), t9.id('Food'), -1) $$, 'zero or more');
select t9.expect_error($$ select public.set_budget(t9.id('hh'), t9.id('Salary'), 100) $$, 'category not available');
select t9.expect_error($$ select public.set_budgets(t9.id('hh'), '[{"category_id":"00000000-0000-0000-0000-000000000000","amount":1}]') $$, 'category not available');

-- ---------- permissions
select t9.as_user(t9.id('viewer'));
select t9.eq((t9.row('Food')->>'budget')::bigint, 500000::bigint, 'viewer can read the budget');
select t9.expect_error($$ select public.set_budget(t9.id('hh'), t9.id('Food'), 1) $$, 'not allowed to write');
reset role; set role anon;
select t9.expect_error($$ select * from public.budget_status(t9.id('hh'), current_date) $$, 'permission denied');

\echo '=== 0009 BUDGET TESTS PASSED ==='
