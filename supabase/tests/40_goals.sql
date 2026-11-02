-- Tests for migration 0008 (fresh DB after stubs + 0001..0008).
\set ON_ERROR_STOP on
set client_min_messages = notice;

create schema t8;
create function t8.as_user(p uuid) returns void language sql as $$ select set_config('request.jwt.claim.sub', coalesce(p::text, ''), false) $$;
create function t8.eq(g anyelement, w anyelement, what text) returns void language plpgsql as $$
begin if g is distinct from w then raise exception 'FAIL %: got %, want %', what, g, w; end if; raise notice 'ok: % = %', what, g; end $$;
create function t8.expect_error(p_sql text, p_pat text) returns void language plpgsql as $$
begin begin execute p_sql; exception when others then
  if sqlerrm !~* p_pat then raise exception 'expected /%/, got: %', p_pat, sqlerrm; end if;
  raise notice 'ok (rejected): %', left(sqlerrm, 80); return; end;
  raise exception 'expected /%/ but succeeded: %', p_pat, left(p_sql, 120); end $$;
create table t8.ids (k text primary key, v uuid);
create function t8.id(p text) returns uuid language sql stable as $$ select v from t8.ids where k = p $$;
create function t8.avail() returns bigint language sql stable as $$ select available from public.available_to_spend(t8.id('hh')) $$;
create function t8.saved(p_goal uuid) returns bigint language sql stable as $$ select saved from public.goal_progress where goal_id = p_goal $$;
grant usage on schema t8 to public; grant select on t8.ids to public; grant execute on all functions in schema t8 to public;

insert into auth.users values ('00000000-0000-0000-0000-0000000000a1', 'levi@example.com'),
  ('00000000-0000-0000-0000-0000000000b2', 'partner@example.com'), ('00000000-0000-0000-0000-0000000000c3', 'viewer@example.com');
insert into t8.ids values ('levi','00000000-0000-0000-0000-0000000000a1'), ('partner','00000000-0000-0000-0000-0000000000b2'),
  ('viewer','00000000-0000-0000-0000-0000000000c3'), ('hh', gen_random_uuid()), ('bpi', gen_random_uuid()),
  ('gcash', gen_random_uuid()), ('gotyme', gen_random_uuid()), ('atome', gen_random_uuid()), ('sahod', gen_random_uuid());
insert into public.households (id, name, created_by) values (t8.id('hh'), 'Test', t8.id('levi'));
insert into public.household_members values (t8.id('hh'), t8.id('levi'), 'owner', now()),
  (t8.id('hh'), t8.id('partner'), 'member', now()), (t8.id('hh'), t8.id('viewer'), 'viewer', now());
insert into public.accounts (id, household_id, name, kind, class, is_spendable, created_by) values
  (t8.id('bpi'),    t8.id('hh'), 'BPI Bank',       'bank',        'asset',     true,  t8.id('levi')),
  (t8.id('gcash'),  t8.id('hh'), 'GCash',          'ewallet',     'asset',     true,  t8.id('levi')),
  (t8.id('gotyme'), t8.id('hh'), 'GoTyme Savings', 'savings',     'asset',     false, t8.id('levi')),
  (t8.id('atome'),  t8.id('hh'), 'Atome',          'credit_card', 'liability', false, t8.id('levi'));
insert into public.categories (id, household_id, kind, name) values (t8.id('sahod'), t8.id('hh'), 'income', 'Salary');

set role authenticated; select t8.as_user(t8.id('levi'));
do $$ begin
  perform public.post_transaction(t8.id('hh'), 'income', current_date, jsonb_build_array(jsonb_build_object('account_id', t8.id('bpi'), 'amount', 3000000)), t8.id('sahod'));
  perform public.post_transaction(t8.id('hh'), 'opening_balance', current_date, jsonb_build_array(jsonb_build_object('account_id', t8.id('gcash'), 'amount', 500000)));
end $$;
select t8.eq(t8.avail(), 3500000::bigint, 'start: 30,000 BPI + 5,000 GCash');

-- ---------- account-mode goal in the existing GoTyme Savings
create temp table g as select
  public.save_goal(t8.id('hh'), null, 'Emergency fund', 5000000, current_date + 300, 'account', t8.id('gotyme')) as emergency,
  public.save_goal(t8.id('hh'), null, 'Baguio trip', 1500000, null, 'earmark') as trip;
grant select on g to public;
select public.add_to_goal((select emergency from g), t8.id('bpi'), 800000);
select t8.eq(t8.saved((select emergency from g)), 800000::bigint, 'emergency fund saved 8,000');
select t8.eq(t8.avail(), 2700000::bigint, 'moving money to savings lowers Safe to spend once');
select t8.eq((select expense from public.monthly_summary(t8.id('hh'), current_date)), 0::bigint, 'saving is not spending');
select public.take_from_goal((select emergency from g), t8.id('gcash'), 100000);
select t8.eq(t8.saved((select emergency from g)), 700000::bigint, 'took 1,000 back out');
select t8.eq(t8.avail(), 2800000::bigint, 'money taken out is spendable again');
select t8.expect_error($$ select public.take_from_goal((select emergency from g), t8.id('bpi'), 999999999) $$, 'more than the goal has saved');
select t8.expect_error($$ select public.add_to_goal((select emergency from g), t8.id('gotyme'), 100) $$, 'account the money comes from');
select t8.expect_error($$ select public.add_to_goal((select emergency from g), t8.id('atome'), 100) $$, 'cash, a bank or an e-wallet');
select t8.expect_error($$ select public.save_goal(t8.id('hh'), null, 'Second', 100, null, 'account', t8.id('gotyme')) $$, 'already belongs to another goal');
select t8.expect_error($$ select public.save_goal(t8.id('hh'), null, 'Bad', 100, null, 'account', t8.id('gcash')) $$, 'not used for spending');

-- ---------- earmark-mode goal: money stays in GCash
select public.add_to_goal((select trip from g), t8.id('gcash'), 200000);
select t8.eq(t8.saved((select trip from g)), 200000::bigint, 'trip has 2,000 set aside in GCash');
select t8.eq(t8.avail(), 2600000::bigint, 'set-aside money is out of Safe to spend once');
select t8.eq((select balance from public.account_balances where account_id = t8.id('gcash')), 600000::bigint, 'GCash balance itself unchanged');
select t8.expect_error($$ select public.add_to_goal((select trip from g), t8.id('gcash'), 500000) $$, 'exceed the account balance');
select t8.expect_error($$ select public.add_to_goal((select trip from g), t8.id('gotyme'), 100) $$, 'spending account');
select public.take_from_goal((select trip from g), t8.id('gcash'), 50000);
select t8.eq(t8.saved((select trip from g)), 150000::bigint, 'released 500 from the trip');
select t8.expect_error($$ select public.take_from_goal((select trip from g), t8.id('gcash'), 999999) $$, 'more than the goal has saved');

-- ---------- a goal with a brand-new savings account
create temp table g2 as select public.save_goal(t8.id('hh'), null, 'New phone', 3000000, null, 'account', null, 'Phone fund') as id;
grant select on g2 to public;
select t8.eq((select is_spendable::text || ' ' || kind from public.accounts where name = 'Phone fund'), 'false savings', 'new savings account created, not spendable');
select public.add_to_goal((select id from g2), t8.id('bpi'), 300000);
select t8.eq(t8.saved((select id from g2)), 300000::bigint, 'new phone goal saved 3,000');

-- ---------- editing and finishing
select public.save_goal(t8.id('hh'), (select trip from g), 'Baguio trip (May)', 2000000, current_date + 180);
select t8.eq((select name || ' ' || target_amount from public.goal_progress where goal_id = (select trip from g)), 'Baguio trip (May) 2000000', 'goal renamed and target raised');
select t8.expect_error($$ select public.save_goal(t8.id('hh'), null, 'Old', 100, current_date - 1) $$, 'today or later');
create temp table before_archive as select t8.avail() as a; grant select on before_archive to public;
select public.archive_goal((select trip from g));
select t8.eq(t8.avail(), (select a from before_archive) + 150000, 'finishing an earmark goal makes its money spendable again');
select t8.eq((select count(*) from public.goal_progress where goal_id = (select trip from g)), 0::bigint, 'finished goal leaves the list');
select t8.expect_error($$ select public.add_to_goal((select trip from g), t8.id('gcash'), 100) $$, 'goal not available');

-- ---------- permissions and privacy
select t8.as_user(t8.id('viewer'));
select t8.expect_error($$ select public.save_goal(t8.id('hh'), null, 'x', 100) $$, 'not allowed to write');
select t8.expect_error($$ select public.add_to_goal((select emergency from g), t8.id('bpi'), 100) $$, 'goal not available');
select t8.as_user(t8.id('partner'));
create temp table pg8 as select public.save_goal(t8.id('hh'), null, 'Partner surprise', 1000000, null, 'earmark', p_personal => true) as id;
grant select on pg8 to public;
select t8.as_user(t8.id('levi'));
select t8.eq((select count(*) from public.goal_progress where goal_id = (select id from pg8)), 0::bigint, 'partner''s personal goal is private');
select t8.expect_error($$ select public.archive_goal((select id from pg8)) $$, 'goal not available');

\echo '=== 0008 GOAL TESTS PASSED ==='
