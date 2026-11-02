-- Tests for migration 0007 (fresh DB after stubs + 0001..0007).
\set ON_ERROR_STOP on
set client_min_messages = notice;

create schema t7;
create function t7.as_user(p uuid) returns void language sql as $$ select set_config('request.jwt.claim.sub', coalesce(p::text, ''), false) $$;
create function t7.eq(g anyelement, w anyelement, what text) returns void language plpgsql as $$
begin if g is distinct from w then raise exception 'FAIL %: got %, want %', what, g, w; end if; raise notice 'ok: % = %', what, g; end $$;
create function t7.expect_error(p_sql text, p_pat text) returns void language plpgsql as $$
begin begin execute p_sql; exception when others then
  if sqlerrm !~* p_pat then raise exception 'expected /%/, got: %', p_pat, sqlerrm; end if;
  raise notice 'ok (rejected): %', left(sqlerrm, 80); return; end;
  raise exception 'expected /%/ but succeeded: %', p_pat, left(p_sql, 120); end $$;
create table t7.ids (k text primary key, v uuid);
create function t7.id(p text) returns uuid language sql stable as $$ select v from t7.ids where k = p $$;
create function t7.occ(p_bill uuid, p_nth int default 1) returns uuid language sql stable as $$
  select id from public.bill_occurrences where bill_id = p_bill order by due_on offset p_nth - 1 limit 1 $$;
grant execute on function t7.occ(uuid, int) to public;
grant usage on schema t7 to public; grant select on t7.ids to public; grant execute on all functions in schema t7 to public;

insert into auth.users values ('00000000-0000-0000-0000-0000000000a1', 'levi@example.com'),
                              ('00000000-0000-0000-0000-0000000000b2', 'partner@example.com'),
                              ('00000000-0000-0000-0000-0000000000c3', 'viewer@example.com');
insert into t7.ids values ('levi','00000000-0000-0000-0000-0000000000a1'), ('partner','00000000-0000-0000-0000-0000000000b2'),
  ('viewer','00000000-0000-0000-0000-0000000000c3'),
  ('hh', gen_random_uuid()), ('bpi', gen_random_uuid()), ('cash', gen_random_uuid()), ('atome', gen_random_uuid()),
  ('util', gen_random_uuid()), ('food', gen_random_uuid()), ('sahod', gen_random_uuid());
insert into public.households (id, name, created_by, reserve_horizon, reserve_days, card_debt_mode)
values (t7.id('hh'), 'Test', t7.id('levi'), 'days', 15, 'full');
insert into public.household_members values (t7.id('hh'), t7.id('levi'), 'owner', now()),
  (t7.id('hh'), t7.id('partner'), 'member', now()), (t7.id('hh'), t7.id('viewer'), 'viewer', now());
insert into public.accounts (id, household_id, name, kind, class, is_spendable, created_by) values
  (t7.id('bpi'),   t7.id('hh'), 'BPI Bank', 'bank',        'asset',     true,  t7.id('levi')),
  (t7.id('cash'),  t7.id('hh'), 'Cash',     'cash',        'asset',     true,  t7.id('levi')),
  (t7.id('atome'), t7.id('hh'), 'Atome',    'credit_card', 'liability', false, t7.id('levi'));
insert into public.categories (id, household_id, kind, name) values
  (t7.id('util'), t7.id('hh'), 'expense', 'Electricity'), (t7.id('food'), t7.id('hh'), 'expense', 'Food'),
  (t7.id('sahod'), t7.id('hh'), 'income', 'Salary');

set role authenticated; select t7.as_user(t7.id('levi'));
do $$ begin
  perform public.post_transaction(t7.id('hh'), 'income', current_date,
    jsonb_build_array(jsonb_build_object('account_id', t7.id('bpi'), 'amount', 3000000)), t7.id('sahod'));
end $$;

-- ---------- creating bills
create temp table b as select
  public.save_bill(t7.id('hh'), null, 'Meralco', t7.id('util'), 320000, current_date + 3, 1) as meralco,
  public.save_bill(t7.id('hh'), null, 'Insurance', t7.id('util'), 1500000, current_date + 150, 12) as insurance,
  public.save_bill(t7.id('hh'), null, 'Atome bill', t7.id('util'), 120000, current_date + 10, 1, null, t7.id('atome')) as atome_bill;
grant select on b to public;
select t7.eq((select count(*) >= 13 from public.bill_occurrences where bill_id = (select meralco from b)), true, 'monthly bill gets 13+ months of due dates');
select t7.eq((select count(*) from public.bill_occurrences where bill_id = (select insurance from b)), 1::bigint, 'yearly bill 5 months out is listed');
select t7.expect_error($$ select public.save_bill(t7.id('hh'), null, 'x', t7.id('util'), 0, current_date, 1) $$, 'more than zero');
select t7.expect_error($$ select public.save_bill(t7.id('hh'), null, 'x', t7.id('util'), 100, current_date, 4) $$, 'every 1, 2, 3, 6 or 12');
select t7.expect_error($$ select public.save_bill(t7.id('hh'), null, 'x', t7.id('sahod'), 100, current_date, 1) $$, 'category not available');
select t7.expect_error($$ select public.save_bill(t7.id('hh'), null, 'x', t7.id('util'), 100, current_date, 1, null, t7.id('cash')) $$, 'credit card not available');
select t7.expect_error($$ select public.save_bill(t7.id('hh'), null, 'x', t7.id('util'), 100, current_date - 60, 1) $$, 'within the last month');


-- ---------- paying an ordinary bill
select t7.eq((select bills_reserved from public.available_to_spend(t7.id('hh'))), 320000::bigint, 'Meralco reserved (Atome bill not, card mode full)');
do $$ begin perform public.post_transaction(t7.id('hh'), 'bill_payment', current_date,
  jsonb_build_array(jsonb_build_object('account_id', t7.id('bpi'), 'amount', -320000)),
  p_bill_occurrence => t7.occ((select meralco from b))); end $$;
select t7.eq((select remaining from public.bill_occurrence_status where id = t7.occ((select meralco from b))), 0::bigint, 'Meralco paid');
select t7.eq((select expense from public.monthly_summary(t7.id('hh'), current_date)), 320000::bigint, 'bill payment counted once as spending');
select t7.expect_error(format($$ select public.post_transaction(%L, 'bill_payment', current_date,
  jsonb_build_array(jsonb_build_object('account_id', %L, 'amount', -1)), p_bill_occurrence => %L) $$,
  t7.id('hh'), t7.id('bpi'), t7.occ((select meralco from b))), 'exceeds remaining');

-- ---------- credit card bill: purchases are the spending, paying the bill is a transfer
do $$ begin perform public.post_transaction(t7.id('hh'), 'expense', current_date,
  jsonb_build_array(jsonb_build_object('account_id', t7.id('atome'), 'amount', -120000)), t7.id('food')); end $$;
select t7.eq((select expense from public.monthly_summary(t7.id('hh'), current_date)), 440000::bigint, 'card purchase is spending');
create temp table before_pay as select available from public.available_to_spend(t7.id('hh'));
grant select on before_pay to public;
select t7.expect_error(format($$ select public.post_transaction(%L, 'bill_payment', current_date,
  jsonb_build_array(jsonb_build_object('account_id', %L, 'amount', -120000)), p_bill_occurrence => %L) $$,
  t7.id('hh'), t7.id('bpi'), t7.occ((select atome_bill from b))), 'transfer into the card');
select t7.expect_error(format($$ select public.post_transaction(%L, 'transfer', current_date,
  jsonb_build_array(jsonb_build_object('account_id', %L, 'amount', -1000), jsonb_build_object('account_id', %L, 'amount', 1000)),
  p_bill_occurrence => %L) $$, t7.id('hh'), t7.id('bpi'), t7.id('cash'), t7.occ((select meralco from b), 2)), 'only pay a credit card bill');
select t7.expect_error(format($$ select public.post_transaction(%L, 'transfer', current_date,
  jsonb_build_array(jsonb_build_object('account_id', %L, 'amount', -200000), jsonb_build_object('account_id', %L, 'amount', 200000)),
  p_bill_occurrence => %L) $$, t7.id('hh'), t7.id('bpi'), t7.id('atome'), t7.occ((select atome_bill from b))), 'exceeds remaining');
do $$ begin perform public.post_transaction(t7.id('hh'), 'transfer', current_date, jsonb_build_array(
  jsonb_build_object('account_id', t7.id('bpi'), 'amount', -120000), jsonb_build_object('account_id', t7.id('atome'), 'amount', 120000)),
  p_bill_occurrence => t7.occ((select atome_bill from b))); end $$;
select t7.eq((select remaining from public.bill_occurrence_status where id = t7.occ((select atome_bill from b))), 0::bigint, 'card bill marked paid by the transfer');
select t7.eq((select expense from public.monthly_summary(t7.id('hh'), current_date)), 440000::bigint, 'paying the card bill is NOT counted as spending again');
select t7.eq((select balance from public.account_balances where account_id = t7.id('atome')), 0::bigint, 'card debt cleared');
select t7.eq((select available from public.available_to_spend(t7.id('hh'))), (select available from before_pay), 'paying the card does not change Safe to spend');
-- voiding the card payment re-opens the bill
do $$ begin perform public.void_transaction((select id from public.transactions where type = 'transfer' and bill_occurrence_id is not null), 'test'); end $$;
select t7.eq((select remaining from public.bill_occurrence_status where id = t7.occ((select atome_bill from b))), 120000::bigint, 'voided card payment re-opens the bill');

-- ---------- changing, skipping, stopping
select public.set_occurrence_amount(t7.occ((select meralco from b), 2), 345000);
select t7.eq((select amount_due from public.bill_occurrences where id = t7.occ((select meralco from b), 2)), 345000::bigint, 'one month amount changed');
select t7.expect_error(format($$ select public.set_occurrence_amount(%L, 1000) $$, t7.occ((select meralco from b))), 'less than what was already paid');
select public.save_bill(t7.id('hh'), (select meralco from b), 'Meralco', t7.id('util'), 300000, (select starts_on from public.bills where id = (select meralco from b)), 1);
select t7.eq((select amount_due from public.bill_occurrences where id = t7.occ((select meralco from b))), 320000::bigint, 'paid month keeps its amount after a new estimate');
select t7.eq((select amount_due from public.bill_occurrences where id = t7.occ((select meralco from b), 3)), 300000::bigint, 'future months take the new estimate');
select public.skip_bill_occurrence(t7.occ((select meralco from b), 2), true);
select t7.eq((select remaining from public.bill_occurrence_status where id = t7.occ((select meralco from b), 2)), 0::bigint, 'skipped month owes nothing');
-- move the schedule: unpaid future dates rebuilt from the new date, the paid month stays
select public.save_bill(t7.id('hh'), (select meralco from b), 'Meralco', t7.id('util'), 300000, current_date + 20, 1);
select t7.eq((select count(*) from public.bill_occurrences where bill_id = (select meralco from b) and due_on = current_date + 3), 1::bigint, 'paid month kept after rescheduling');
select t7.eq((select min(due_on) from public.bill_occurrences o where bill_id = (select meralco from b)
              and not exists (select 1 from public.transactions t where t.bill_occurrence_id = o.id)), current_date + 20, 'unpaid months start from the new date');
select public.stop_bill((select insurance from b));
select t7.eq((select count(*) from public.bill_occurrences where bill_id = (select insurance from b)), 0::bigint, 'stopped bill has no future due dates');
reset role; select public.generate_bill_occurrences(current_date + 400); set role authenticated; select t7.as_user(t7.id('levi'));
select t7.eq((select count(*) from public.bill_occurrences where bill_id = (select insurance from b)), 0::bigint, 'daily job does not bring a stopped bill back');

-- ---------- permissions
select t7.as_user(t7.id('viewer'));
select t7.expect_error($$ select public.save_bill(t7.id('hh'), null, 'x', t7.id('util'), 100, current_date, 1) $$, 'not allowed to write');
select t7.expect_error($$ select public.skip_bill_occurrence(t7.occ((select atome_bill from b)), true) $$, 'bill not available');
select t7.as_user(t7.id('partner'));
create temp table pb as select public.save_bill(t7.id('hh'), null, 'Partner gym', t7.id('util'), 150000, current_date + 1, 1, p_personal => true) as id;
grant select on pb to public;
select t7.as_user(t7.id('levi'));
select t7.eq((select count(*) from public.bills where id = (select id from pb)), 0::bigint, 'partner''s personal bill is private');
select t7.expect_error($$ select public.stop_bill((select id from pb)) $$, 'bill not available');

-- ---------- push subscriptions
select public.save_push_subscription('https://push.example/levi-phone', repeat('p', 87), repeat('a', 22), 'iPhone');
select t7.as_user(t7.id('partner'));
select public.save_push_subscription('https://push.example/partner-phone', repeat('q', 87), repeat('b', 22), 'iPhone');
select t7.eq((select count(*) from public.push_subscriptions), 1::bigint, 'each person sees only their own devices');
select t7.expect_error($$ insert into public.push_subscriptions (user_id, endpoint, p256dh, auth) values (t7.id('partner'), 'https://x', repeat('p', 87), repeat('a', 22)) $$, 'permission denied');
select t7.expect_error($$ select * from public.bill_reminders_due() $$, 'permission denied');
select t7.expect_error($$ select public.save_push_subscription('http://insecure', repeat('p', 87), repeat('a', 22)) $$, 'check');
reset role; set role anon;
select t7.expect_error($$ select public.save_push_subscription('https://x/y', repeat('p', 87), repeat('a', 22)) $$, 'permission denied');

-- ---------- reminders (as the Edge Function: service_role)
reset role;
update public.households set remind_days_before = 3 where id = t7.id('hh');
-- shape the calendar: Meralco unpaid due in 3 days, Water due today, Internet due yesterday, Rent in 5 days
insert into public.bills (household_id, name, category_id, estimated_amount, starts_on) values
  (t7.id('hh'), 'Water',    t7.id('util'), 50000,  current_date),
  (t7.id('hh'), 'Internet', t7.id('util'), 169900, current_date - 1),
  (t7.id('hh'), 'Rent',     t7.id('util'), 900000, current_date + 5);
select public.generate_bill_occurrences(current_date + 400);
select public.save_bill(t7.id('hh'), (select meralco from b), 'Meralco', t7.id('util'), 300000, current_date + 3, 1)
  from (select set_config('request.jwt.claim.sub', t7.id('levi')::text, false)) x;   -- Meralco +3 is already PAID
insert into public.bills (household_id, name, category_id, estimated_amount, starts_on)
values (t7.id('hh'), 'Phone', t7.id('util'), 99900, current_date + 3);
select public.generate_bill_occurrences(current_date + 400);
set role service_role;
select t7.eq((select string_agg(bill_name || ':' || kind, ', ' order by bill_name)
                from public.bill_reminders_due() where user_id = t7.id('levi')),
             'Internet:overdue, Phone:before, Water:due', 'reminders for Levi (paid Meralco quiet, Rent too far, Atome bill in 10 days)');
select t7.eq((select count(*) from public.bill_reminders_due() where user_id = t7.id('viewer')), 0::bigint, 'no device, no reminders');
select t7.eq((select bool_or(bill_name = 'Partner gym') from public.bill_reminders_due() where user_id = t7.id('partner')), true, 'personal bill reminds its owner');
select t7.eq((select count(*) from public.bill_reminders_due() where user_id = t7.id('levi') and bill_name = 'Partner gym'), 0::bigint, 'personal bill never reminds others');
select public.mark_bill_reminders_sent((select jsonb_agg(jsonb_build_object('user_id', user_id, 'occurrence_id', occurrence_id, 'kind', kind))
                                          from public.bill_reminders_due() where user_id = t7.id('levi')));
select t7.eq((select count(*) from public.bill_reminders_due() where user_id = t7.id('levi')), 0::bigint, 'each reminder is sent once');
reset role; update public.bill_occurrences set is_skipped = true where bill_id = (select id from public.bills where name = 'Rent');
update public.households set remind_days_before = 10 where id = t7.id('hh');
set role service_role;
select t7.eq((select string_agg(bill_name, ', ' order by bill_name) from public.bill_reminders_due() where user_id = t7.id('levi')),
             'Atome bill', '10-day notice picks up the card bill due in 10 days; skipped Rent is quiet');

\echo '=== 0007 BILL TESTS PASSED ==='
