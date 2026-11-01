-- KABAN scenario tests. Run after 00_supabase_stubs.sql and the migration.
-- Every block raises (and psql stops with ON_ERROR_STOP) if an expectation fails.
\set ON_ERROR_STOP on
set client_min_messages = notice;

create schema kaban_test;
grant usage on schema kaban_test to public;

create function kaban_test.as_user(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), false);
end $$;

-- run SQL, expect it to fail with a message matching p_pattern
create function kaban_test.expect_error(p_sql text, p_pattern text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm !~* p_pattern then
      raise exception 'expected error /%/, got: %', p_pattern, sqlerrm;
    end if;
    raise notice 'ok (rejected): %', left(sqlerrm, 90);
    return;
  end;
  raise exception 'expected error /%/ but statement succeeded: %', p_pattern, p_sql;
end $$;

create function kaban_test.eq(p_got anyelement, p_want anyelement, p_what text) returns void language plpgsql as $$
begin
  if p_got is distinct from p_want then raise exception 'FAIL %: got %, want %', p_what, p_got, p_want; end if;
  raise notice 'ok: % = %', p_what, p_got;
end $$;
grant execute on all functions in schema kaban_test to public;

-- ---------------------------------------------------------------- fixtures
insert into auth.users values
  ('00000000-0000-0000-0000-00000000000a', 'ana@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'ben@example.com'),
  ('00000000-0000-0000-0000-00000000000c', 'carl@example.com'),
  ('00000000-0000-0000-0000-00000000000d', 'dan@example.com');

create temp table ids (k text primary key, v uuid);
grant select on ids to public;
create function kaban_test.id(p text) returns uuid language sql stable as $$ select v from ids where k = p $$;
grant execute on function kaban_test.id(text) to public;

insert into ids values ('ana','00000000-0000-0000-0000-00000000000a'), ('ben','00000000-0000-0000-0000-00000000000b'),
                       ('carl','00000000-0000-0000-0000-00000000000c'), ('dan','00000000-0000-0000-0000-00000000000d');

with h as (insert into public.households (name, created_by, reserve_horizon, reserve_days)
           values ('Santos Household', kaban_test.id('ana'), 'days', 30) returning id)
insert into ids select 'hh', id from h;

insert into public.household_members values
  (kaban_test.id('hh'), kaban_test.id('ana'),  'owner',  now()),
  (kaban_test.id('hh'), kaban_test.id('ben'),  'member', now()),
  (kaban_test.id('hh'), kaban_test.id('carl'), 'viewer', now());

-- accounts (shared unless owner given)
insert into ids select 'bpi',  gen_random_uuid(); insert into ids select 'gcash', gen_random_uuid();
insert into ids select 'maya', gen_random_uuid(); insert into ids select 'gotyme', gen_random_uuid();
insert into ids select 'card', gen_random_uuid(); insert into ids select 'ben_gcash', gen_random_uuid();
insert into public.accounts (id, household_id, owner_user_id, name, kind, class, is_spendable, created_by) values
  (kaban_test.id('bpi'),    kaban_test.id('hh'), null, 'BPI',             'bank',        'asset',     true,  kaban_test.id('ana')),
  (kaban_test.id('gcash'),  kaban_test.id('hh'), null, 'GCash',           'ewallet',     'asset',     true,  kaban_test.id('ana')),
  (kaban_test.id('maya'),   kaban_test.id('hh'), null, 'Maya',            'ewallet',     'asset',     true,  kaban_test.id('ana')),
  (kaban_test.id('gotyme'), kaban_test.id('hh'), null, 'GoTyme Savings',  'savings',     'asset',     false, kaban_test.id('ana')),
  (kaban_test.id('card'),   kaban_test.id('hh'), null, 'BPI Credit Card', 'credit_card', 'liability', false, kaban_test.id('ana')),
  (kaban_test.id('ben_gcash'), kaban_test.id('hh'), kaban_test.id('ben'), 'Ben GCash', 'ewallet', 'asset', true, kaban_test.id('ben'));

insert into ids select 'salary', gen_random_uuid(); insert into ids select 'groceries', gen_random_uuid();
insert into ids select 'utilities', gen_random_uuid(); insert into ids select 'dining', gen_random_uuid();
insert into public.categories (id, household_id, kind, name) values
  (kaban_test.id('salary'),    kaban_test.id('hh'), 'income',  'Salary'),
  (kaban_test.id('groceries'), kaban_test.id('hh'), 'expense', 'Groceries'),
  (kaban_test.id('utilities'), kaban_test.id('hh'), 'expense', 'Utilities'),
  (kaban_test.id('dining'),    kaban_test.id('hh'), 'expense', 'Dining');

insert into ids select 'emergency', gen_random_uuid(); insert into ids select 'trip', gen_random_uuid();
insert into public.savings_goals (id, household_id, name, target_amount, mode, linked_account_id) values
  (kaban_test.id('emergency'), kaban_test.id('hh'), 'Emergency fund', 10000000, 'account', kaban_test.id('gotyme')),
  (kaban_test.id('trip'),      kaban_test.id('hh'), 'Baguio trip',    1500000,  'earmark', null);

-- bills (relative to today so the test is date-independent; horizon = 30 days)
insert into ids select 'meralco', gen_random_uuid(); insert into ids select 'pldt', gen_random_uuid();
insert into ids select 'water', gen_random_uuid();   insert into ids select 'tuition', gen_random_uuid();
insert into ids select 'insurance', gen_random_uuid();
insert into public.bills (id, household_id, name, category_id, estimated_amount, pay_from_account_id, starts_on, recurrence_months) values
  (kaban_test.id('meralco'),   kaban_test.id('hh'), 'Meralco',   kaban_test.id('utilities'), 320000, null, current_date + 14, 1),
  (kaban_test.id('pldt'),      kaban_test.id('hh'), 'PLDT',      kaban_test.id('utilities'), 169900, null, current_date + 19, 1),
  (kaban_test.id('water'),     kaban_test.id('hh'), 'Water',     kaban_test.id('utilities'), 110000, null, current_date + 9, null),
  (kaban_test.id('tuition'),   kaban_test.id('hh'), 'Tuition',   kaban_test.id('utilities'), 2500000, null, current_date + 45, null),
  (kaban_test.id('insurance'), kaban_test.id('hh'), 'Insurance', kaban_test.id('utilities'), 200000, kaban_test.id('gotyme'), current_date + 20, null);
select public.generate_bill_occurrences(current_date + 60);


-- ================================================================ 1. LEDGER (as Ana, the owner)
set role authenticated;
select kaban_test.as_user(kaban_test.id('ana'));

do $$
declare hh uuid := kaban_test.id('hh'); w uuid;
begin
  -- opening balances
  perform public.post_transaction(hh, 'opening_balance', current_date, jsonb_build_array(jsonb_build_object('account_id', kaban_test.id('gcash'),  'amount', 500000)));
  perform public.post_transaction(hh, 'opening_balance', current_date, jsonb_build_array(jsonb_build_object('account_id', kaban_test.id('maya'),   'amount', 110000)));
  perform public.post_transaction(hh, 'opening_balance', current_date, jsonb_build_array(jsonb_build_object('account_id', kaban_test.id('gotyme'), 'amount', 4600000)));
  -- salary 30,800 into BPI
  perform public.post_transaction(hh, 'income', current_date, jsonb_build_array(jsonb_build_object('account_id', kaban_test.id('bpi'), 'amount', 3080000)), kaban_test.id('salary'), 'October salary');
  -- cash-in 5,000 BPI -> GCash
  perform public.post_transaction(hh, 'transfer', current_date, jsonb_build_array(
            jsonb_build_object('account_id', kaban_test.id('bpi'), 'amount', -500000),
            jsonb_build_object('account_id', kaban_test.id('gcash'), 'amount', 500000)));
  -- 4,000 into the emergency fund (separate GoTyme Savings account)
  perform public.post_transaction(hh, 'savings_contribution', current_date, jsonb_build_array(
            jsonb_build_object('account_id', kaban_test.id('bpi'), 'amount', -400000),
            jsonb_build_object('account_id', kaban_test.id('gotyme'), 'amount', 400000)), p_goal_id => kaban_test.id('emergency'));
  -- groceries 2,500 via GCash, then 500 refund
  perform public.post_transaction(hh, 'expense', current_date, jsonb_build_array(jsonb_build_object('account_id', kaban_test.id('gcash'), 'amount', -250000)), kaban_test.id('groceries'));
  perform public.post_transaction(hh, 'refund',  current_date, jsonb_build_array(jsonb_build_object('account_id', kaban_test.id('gcash'), 'amount', 50000)),  kaban_test.id('groceries'), 'Shopee refund');
  -- dinner 1,800 on the credit card, then pay the card from BPI (a transfer)
  perform public.post_transaction(hh, 'expense', current_date, jsonb_build_array(jsonb_build_object('account_id', kaban_test.id('card'), 'amount', -180000)), kaban_test.id('dining'));
  perform public.post_transaction(hh, 'transfer', current_date, jsonb_build_array(
            jsonb_build_object('account_id', kaban_test.id('bpi'), 'amount', -180000),
            jsonb_build_object('account_id', kaban_test.id('card'), 'amount', 180000)));
  -- pay the water bill in full from Maya
  select id into w from public.bill_occurrences where bill_id = kaban_test.id('water');
  perform public.post_transaction(hh, 'bill_payment', current_date, jsonb_build_array(jsonb_build_object('account_id', kaban_test.id('maya'), 'amount', -110000)), p_bill_occurrence => w);
  -- earmark 2,000 of GCash for the trip
  perform public.set_earmark(kaban_test.id('trip'), kaban_test.id('gcash'), 200000);
end $$;

-- balances
select kaban_test.eq((select balance from public.account_balances where account_id = kaban_test.id('bpi')),    2000000::bigint, 'BPI balance');
select kaban_test.eq((select balance from public.account_balances where account_id = kaban_test.id('gcash')),  800000::bigint,  'GCash balance');
select kaban_test.eq((select balance from public.account_balances where account_id = kaban_test.id('maya')),   0::bigint,       'Maya balance');
select kaban_test.eq((select balance from public.account_balances where account_id = kaban_test.id('gotyme')), 5000000::bigint, 'GoTyme Savings balance');
select kaban_test.eq((select balance from public.account_balances where account_id = kaban_test.id('card')),   0::bigint,       'Credit card owed');

-- reports: transfers, card payment, savings move and openings never count
select kaban_test.eq((select income  from public.monthly_summary(kaban_test.id('hh'), current_date)), 3080000::bigint, 'income this month');
select kaban_test.eq((select expense from public.monthly_summary(kaban_test.id('hh'), current_date)), 490000::bigint,  'expense this month (2,500 + 1,800 + 1,100 - 500)');

-- goals
select kaban_test.eq((select saved from public.goal_progress where goal_id = kaban_test.id('emergency')), 5000000::bigint, 'emergency fund saved');
select kaban_test.eq((select saved from public.goal_progress where goal_id = kaban_test.id('trip')),      200000::bigint,  'trip saved (earmark)');

-- bills
select kaban_test.eq((select remaining from public.bill_occurrence_status where bill_id = kaban_test.id('water')), 0::bigint, 'water remaining after payment');

-- ================================================================ 2. AVAILABLE TO SPEND
select kaban_test.eq((select spendable_balance from public.available_to_spend(kaban_test.id('hh'))), 2800000::bigint, 'pool = BPI + GCash + Maya');
select kaban_test.eq((select earmarked         from public.available_to_spend(kaban_test.id('hh'))), 200000::bigint,  'earmarks deducted (trip only, not emergency fund)');
select kaban_test.eq((select bills_reserved    from public.available_to_spend(kaban_test.id('hh'))), 489900::bigint,  'bills reserved (Meralco + PLDT; not paid water, not tuition beyond horizon, not insurance from savings)');
select kaban_test.eq((select available         from public.available_to_spend(kaban_test.id('hh'))), 2110100::bigint, 'AVAILABLE TO SPEND = 21,101');

-- partial bill payment reduces the reservation by exactly the amount paid
do $$ declare m uuid; begin
  select id into m from public.bill_occurrences where bill_id = kaban_test.id('meralco') order by due_on limit 1;
  perform public.post_transaction(kaban_test.id('hh'), 'bill_payment', current_date,
    jsonb_build_array(jsonb_build_object('account_id', kaban_test.id('bpi'), 'amount', -100000)), p_bill_occurrence => m);
end $$;
select kaban_test.eq((select bills_reserved from public.available_to_spend(kaban_test.id('hh'))), 389900::bigint, 'reservation after 1,000 partial Meralco payment');
select kaban_test.eq((select available      from public.available_to_spend(kaban_test.id('hh'))), 2110100::bigint, 'available unchanged by paying a reserved bill (no double deduction)');

-- ================================================================ 3. DOUBLE-COUNTING GUARDS
select kaban_test.expect_error($$ select public.set_earmark(kaban_test.id('trip'), kaban_test.id('gotyme'), 100000) $$, 'earmarks only apply to spendable');
select kaban_test.expect_error($$ select public.set_earmark(kaban_test.id('trip'), kaban_test.id('gcash'), 900000) $$, 'would exceed the account balance');
reset role;
select kaban_test.expect_error($$ update public.accounts set is_spendable = false where id = kaban_test.id('gcash') $$, 'release this account');
select kaban_test.expect_error($$ update public.accounts set is_spendable = true where id = kaban_test.id('gotyme') $$, 'dedicated to a savings goal');
select kaban_test.expect_error($$ insert into public.savings_goals (household_id, name, target_amount, mode, linked_account_id)
                                  values (kaban_test.id('hh'), 'Bad', 1000, 'account', kaban_test.id('bpi')) $$, 'must be non-spendable');
-- a lopsided transfer written straight into the tables is caught at commit
select kaban_test.expect_error($$
  with t as (insert into public.transactions (household_id, type, occurred_on, created_by)
             values (kaban_test.id('hh'), 'transfer', current_date, kaban_test.id('ana')) returning id, household_id)
  insert into public.ledger_entries (transaction_id, household_id, account_id, amount)
  select id, household_id, kaban_test.id('bpi'), -50000 from t union all
  select id, household_id, kaban_test.id('gcash'), 40000 from t;
  set constraints all immediate $$, 'summing to zero');
select kaban_test.expect_error($$ update public.ledger_entries set amount = 1 where account_id = kaban_test.id('bpi') $$, 'immutable');
set role authenticated;
select kaban_test.as_user(kaban_test.id('ana'));
select kaban_test.expect_error($$ select public.post_transaction(kaban_test.id('hh'), 'expense', current_date,
  '[{"account_id":"00000000-0000-0000-0000-000000000000","amount":-100}]'::jsonb, kaban_test.id('groceries')) $$, 'not available');
select kaban_test.expect_error(format($$ select public.post_transaction(%L, 'expense', current_date,
  jsonb_build_array(jsonb_build_object('account_id', %L, 'amount', -1000)), %L) $$,
  kaban_test.id('hh'), kaban_test.id('gcash'), kaban_test.id('salary')), 'expense category');
select kaban_test.expect_error(format($$ select public.post_transaction(%L, 'expense', current_date,
  jsonb_build_array(jsonb_build_object('account_id', %L, 'amount', 1000)), %L) $$,
  kaban_test.id('hh'), kaban_test.id('gcash'), kaban_test.id('groceries')), 'one negative entry');
select kaban_test.expect_error(format($$ select public.post_transaction(%L, 'bill_payment', current_date,
  jsonb_build_array(jsonb_build_object('account_id', %L, 'amount', -100)), p_bill_occurrence => (select id from public.bill_occurrences where bill_id = %L)) $$,
  kaban_test.id('hh'), kaban_test.id('maya'), kaban_test.id('water')), 'exceeds remaining due');
select kaban_test.expect_error(format($$ select public.post_transaction(%L, 'savings_contribution', current_date,
  jsonb_build_array(jsonb_build_object('account_id', %L, 'amount', -100), jsonb_build_object('account_id', %L, 'amount', 100)), p_goal_id => %L) $$,
  kaban_test.id('hh'), kaban_test.id('bpi'), kaban_test.id('gcash'), kaban_test.id('emergency')), 'INTO the goal');

-- idempotency: same key twice = one transaction
do $$ declare a uuid; b uuid; begin
  a := public.post_transaction(kaban_test.id('hh'), 'expense', current_date, jsonb_build_array(jsonb_build_object('account_id', kaban_test.id('gcash'), 'amount', -5000)), kaban_test.id('dining'), p_idempotency_key => 'k1');
  b := public.post_transaction(kaban_test.id('hh'), 'expense', current_date, jsonb_build_array(jsonb_build_object('account_id', kaban_test.id('gcash'), 'amount', -5000)), kaban_test.id('dining'), p_idempotency_key => 'k1');
  perform kaban_test.eq(a, b, 'retry with same idempotency key returns same id');
  -- edit: 50 -> 80; void + repost, reports follow
  b := public.edit_transaction(a, current_date, jsonb_build_array(jsonb_build_object('account_id', kaban_test.id('gcash'), 'amount', -8000)));
  perform kaban_test.eq((select status::text from public.transactions where id = a), 'void', 'edited original is void');
  perform kaban_test.eq((select replaces_id from public.transactions where id = b), a, 'new version points to original');
end $$;
select kaban_test.eq((select expense from public.monthly_summary(kaban_test.id('hh'), current_date)), 598000::bigint, 'expense after edit (4,900 + 1,000 Meralco + 80)');

-- over-spent earmark: deduction is capped at what the account still holds
do $$ begin
  perform public.post_transaction(kaban_test.id('hh'), 'expense', current_date,
    jsonb_build_array(jsonb_build_object('account_id', kaban_test.id('gcash'), 'amount', -692000)), kaban_test.id('groceries'));
end $$;
select kaban_test.eq((select balance from public.account_balances where account_id = kaban_test.id('gcash')), 100000::bigint, 'GCash now below its 2,000 earmark');
select kaban_test.eq((select earmarked from public.available_to_spend(kaban_test.id('hh'))), 100000::bigint, 'earmark deduction capped at GCash balance');
select kaban_test.eq((select over_earmarked from public.available_to_spend(kaban_test.id('hh'))), true, 'over-earmarked warning raised');

-- ================================================================ 4. PERMISSIONS / RLS
select kaban_test.expect_error($$ insert into public.ledger_entries (transaction_id, household_id, account_id, amount)
  values (gen_random_uuid(), kaban_test.id('hh'), kaban_test.id('bpi'), 100) $$, 'permission denied');
select kaban_test.eq((select count(*) from public.accounts where id = kaban_test.id('ben_gcash')), 0::bigint, 'Ana cannot see Ben''s personal account');

-- Ben moves 1,000 from his personal GCash into shared BPI
select kaban_test.as_user(kaban_test.id('ben'));
do $$ begin
  perform public.post_transaction(kaban_test.id('hh'), 'opening_balance', current_date,
    jsonb_build_array(jsonb_build_object('account_id', kaban_test.id('ben_gcash'), 'amount', 300000)));
  perform public.post_transaction(kaban_test.id('hh'), 'transfer', current_date, jsonb_build_array(
    jsonb_build_object('account_id', kaban_test.id('ben_gcash'), 'amount', -100000),
    jsonb_build_object('account_id', kaban_test.id('bpi'), 'amount', 100000)), p_description => 'Ben contribution');
end $$;
select kaban_test.eq((select count(*) from public.accounts), 6::bigint, 'Ben sees 5 shared + his own account');
select kaban_test.eq((select available from public.available_to_spend(kaban_test.id('hh'), 'personal')), 200000::bigint, 'Ben personal available');
select kaban_test.as_user(kaban_test.id('ana'));
select kaban_test.eq((select count(*) from public.ledger_entries e join public.transactions t on t.id = e.transaction_id
                       where t.description = 'Ben contribution'), 1::bigint, 'Ana sees only the shared side of Ben''s transfer');
select kaban_test.eq((select scope from public.transaction_list where description = 'Ben contribution'), 'shared', 'contribution scope');

select kaban_test.as_user(kaban_test.id('carl'));   -- viewer
select kaban_test.expect_error(format($$ select public.post_transaction(%L, 'expense', current_date,
  jsonb_build_array(jsonb_build_object('account_id', %L, 'amount', -100)), %L) $$,
  kaban_test.id('hh'), kaban_test.id('gcash'), kaban_test.id('groceries')), 'not allowed to write');

select kaban_test.as_user(kaban_test.id('dan'));    -- outsider
select kaban_test.eq((select count(*) from public.transactions), 0::bigint, 'outsider sees no transactions');
select kaban_test.eq((select count(*) from public.accounts), 0::bigint, 'outsider sees no accounts');
select kaban_test.expect_error($$ select * from public.available_to_spend(kaban_test.id('hh')) $$, 'not a member');

-- ================================================================ 5. QUICK ENTRY TOKENS
select kaban_test.as_user(kaban_test.id('ben'));
create temp table tok as select * from public.create_quick_entry_token(kaban_test.id('hh'), 'Ben iPhone', kaban_test.id('gcash'));
grant select on tok to public;
select kaban_test.eq((select token like 'kbn_qe_%' and length(token) = 71 from tok), true, 'token format');
select kaban_test.expect_error($$ select token_hash from public.quick_entry_tokens $$, 'permission denied');
select kaban_test.expect_error($$ select public.quick_entry_submit((select token from tok), 15000, kaban_test.id('dining')) $$, 'permission denied');

reset role; set role service_role;
select kaban_test.eq((select count(*) from public.quick_entry_categories((select token from tok))), 3::bigint, 'shortcut sees expense category names only');
do $$ declare r jsonb; r2 jsonb; begin
  r  := public.quick_entry_submit((select token from tok), 15000, kaban_test.id('dining'), p_note => 'Jollibee', p_idempotency_key => 'tap-1');
  r2 := public.quick_entry_submit((select token from tok), 15000, kaban_test.id('dining'), p_note => 'Jollibee', p_idempotency_key => 'tap-1');
  perform kaban_test.eq(r->>'transaction_id', r2->>'transaction_id', 'double tap with same key logs once');
  perform kaban_test.eq(r ? 'balance', false, 'response carries no balances');
end $$;
select kaban_test.eq((select count(*) from public.transactions where source = 'quick_entry'), 1::bigint, 'one quick-entry transaction');
select kaban_test.eq((select created_by from public.transactions where source = 'quick_entry'), kaban_test.id('ben'), 'attributed to token owner');
select kaban_test.expect_error($$ select public.quick_entry_submit('kbn_qe_' || repeat('0', 64), 100, kaban_test.id('dining')) $$, 'invalid token');
select kaban_test.expect_error($$ select public.quick_entry_submit((select token from tok), 2000001, kaban_test.id('dining')) $$, 'amount must be between');
select kaban_test.expect_error($$ select public.quick_entry_submit((select token from tok), 100, kaban_test.id('salary'), 'income') $$, 'type not allowed');
select kaban_test.expect_error($$ select public.quick_entry_submit((select token from tok), 100, kaban_test.id('dining'), p_account_id => kaban_test.id('bpi')) $$, 'account not allowed');

-- revocation is immediate
reset role; set role authenticated; select kaban_test.as_user(kaban_test.id('ben'));
select public.revoke_quick_entry_token((select token_id from tok));
reset role; set role service_role;
select kaban_test.expect_error($$ select public.quick_entry_submit((select token from tok), 100, kaban_test.id('dining')) $$, 'invalid token');

-- removing a member kills their tokens even if not revoked
reset role; set role authenticated; select kaban_test.as_user(kaban_test.id('ben'));
create temp table tok2 as select * from public.create_quick_entry_token(kaban_test.id('hh'), 'Ben iPad', kaban_test.id('gcash'));
grant select on tok2 to public;
select kaban_test.as_user(kaban_test.id('ana'));
delete from public.household_members where user_id = kaban_test.id('ben');
reset role; set role service_role;
select kaban_test.expect_error($$ select public.quick_entry_submit((select token from tok2), 100, kaban_test.id('dining')) $$, 'invalid token');
reset role;
select kaban_test.eq((select revoked_at is not null from public.quick_entry_tokens where id = (select token_id from tok2)), true, 'token auto-revoked on member removal');

\echo '=== ALL KABAN SCENARIO TESTS PASSED ==='
