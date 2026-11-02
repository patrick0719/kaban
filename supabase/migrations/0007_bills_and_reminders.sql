-- =====================================================================
-- KABAN 0007: bills you can manage from the app, and push reminders
--
-- 1. Credit card bills: paying one is a TRANSFER into the card (the
--    purchases were already expenses), linked to the bill so it shows as
--    paid. Never counted as spending twice.
-- 2. Bill functions: save (create/edit), change one month's amount,
--    skip a month, stop a bill. Due dates are generated 400 days ahead,
--    so yearly bills appear too.
-- 3. Push subscriptions (one row per device) and reminder bookkeeping.
-- 4. bill_reminders_due(): which reminders to send today; called only by
--    the bill-reminders Edge Function with the service role.
-- =====================================================================

-- 1 -------------------------------------------------------------------
create or replace function kaban_private.validate_transaction(p_txn uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  t        public.transactions%rowtype;
  n        int;
  s        bigint;
  n_acct   int;
  n_liab   int;
  cat_kind public.category_kind;
  goal     public.savings_goals%rowtype;
  v_settles uuid;
begin
  select * into t from public.transactions where id = p_txn;
  if not found then return; end if;

  select count(*), coalesce(sum(e.amount), 0), count(distinct e.account_id),
         count(*) filter (where a.class = 'liability')
    into n, s, n_acct, n_liab
    from public.ledger_entries e
    join public.accounts a on a.id = e.account_id
   where e.transaction_id = p_txn;

  if n = 0 then
    raise exception 'KABAN: transaction % has no ledger entries', p_txn using errcode = 'check_violation';
  end if;

  if exists (select 1 from public.ledger_entries e join public.accounts a on a.id = e.account_id
             where e.transaction_id = p_txn and a.household_id <> t.household_id) then
    raise exception 'KABAN: entry account outside household' using errcode = 'check_violation';
  end if;

  if t.category_id is not null then
    select kind into cat_kind from public.categories where id = t.category_id;
  end if;

  -- a bill may be referenced by a bill_payment, or by a transfer that pays a credit card bill
  if t.bill_occurrence_id is not null then
    if t.type = 'transfer' then
      select b.settles_account_id into v_settles
        from public.bill_occurrences o join public.bills b on b.id = o.bill_id
       where o.id = t.bill_occurrence_id;
      if v_settles is null or not exists (
           select 1 from public.ledger_entries
            where transaction_id = p_txn and account_id = v_settles and amount > 0) then
        raise exception 'KABAN: a transfer can only pay a credit card bill, into that card'
          using errcode = 'check_violation';
      end if;
    elsif t.type <> 'bill_payment' then
      raise exception 'KABAN: only bill_payment may reference a bill' using errcode = 'check_violation';
    end if;
  end if;
  if t.goal_id is not null and t.type <> 'savings_contribution' then
    raise exception 'KABAN: only savings_contribution may reference a goal' using errcode = 'check_violation';
  end if;

  case t.type
    when 'income' then
      if n <> 1 or s <= 0 or n_liab > 0 or cat_kind is distinct from 'income' then
        raise exception 'KABAN: income = one positive entry in an asset account + an income category'
          using errcode = 'check_violation';
      end if;
    when 'expense' then
      if n <> 1 or s >= 0 or cat_kind is distinct from 'expense' then
        raise exception 'KABAN: expense = one negative entry + an expense category' using errcode = 'check_violation';
      end if;
    when 'bill_payment' then
      if n <> 1 or s >= 0 or t.bill_occurrence_id is null or cat_kind is distinct from 'expense' then
        raise exception 'KABAN: bill_payment = one negative entry linked to a bill occurrence'
          using errcode = 'check_violation';
      end if;
      if exists (select 1 from public.bill_occurrences o join public.bills b on b.id = o.bill_id
                  where o.id = t.bill_occurrence_id and b.settles_account_id is not null) then
        raise exception 'KABAN: pay a credit card bill with a transfer into the card, not as an expense'
          using errcode = 'check_violation';
      end if;
    when 'refund' then
      if n <> 1 or s <= 0 or cat_kind is distinct from 'expense' then
        raise exception 'KABAN: refund = one positive entry + the expense category it reverses'
          using errcode = 'check_violation';
      end if;
    when 'transfer' then
      if n <> 2 or s <> 0 or n_acct <> 2 or t.category_id is not null then
        raise exception 'KABAN: transfer = two entries in different accounts summing to zero, no category'
          using errcode = 'check_violation';
      end if;
    when 'savings_contribution' then
      if n <> 2 or s <> 0 or n_acct <> 2 or t.category_id is not null or t.goal_id is null then
        raise exception 'KABAN: savings_contribution = zero-sum transfer with a goal' using errcode = 'check_violation';
      end if;
      select * into goal from public.savings_goals where id = t.goal_id;
      if goal.mode <> 'account' or not exists (
           select 1 from public.ledger_entries
            where transaction_id = p_txn and account_id = goal.linked_account_id and amount > 0) then
        raise exception 'KABAN: savings_contribution must move money INTO the goal''s dedicated account'
          using errcode = 'check_violation';
      end if;
    when 'opening_balance', 'adjustment' then
      if n <> 1 or t.category_id is not null then
        raise exception 'KABAN: % = exactly one entry, no category', t.type using errcode = 'check_violation';
      end if;
  end case;
end $$;

-- Paid = bill payments, plus transfers into the card for a credit card bill.
create or replace view public.bill_occurrence_status with (security_invoker = true) as
select o.id, o.household_id, o.bill_id, b.name, b.owner_user_id, b.pay_from_account_id,
       o.due_on, o.amount_due, o.is_skipped,
       coalesce(sum(case when t.type = 'bill_payment' then -e.amount
                         when t.type = 'transfer' and e.account_id = b.settles_account_id then e.amount
                    end) filter (where t.status = 'posted'), 0)::bigint as paid,
       case when o.is_skipped then 0
            else greatest(o.amount_due
                          - coalesce(sum(case when t.type = 'bill_payment' then -e.amount
                                              when t.type = 'transfer' and e.account_id = b.settles_account_id then e.amount
                                         end) filter (where t.status = 'posted'), 0), 0)
       end::bigint as remaining
  from public.bill_occurrences o
  join public.bills b on b.id = o.bill_id
  left join public.transactions  t on t.bill_occurrence_id = o.id and t.type in ('bill_payment', 'transfer')
  left join public.ledger_entries e on e.transaction_id = t.id
 group by o.id, b.id;

create or replace function kaban_private.post_transaction_as(
  p_actor            uuid,
  p_household        uuid,
  p_type             public.txn_type,
  p_occurred_on      date,
  p_entries          jsonb,
  p_category_id      uuid default null,
  p_description      text default null,
  p_bill_occurrence  uuid default null,
  p_goal_id          uuid default null,
  p_parent_id        uuid default null,
  p_idempotency_key  text default null,
  p_source           public.txn_source default 'app',
  p_token_id         uuid default null,
  p_replaces_id      uuid default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id       uuid;
  v_cat      uuid := p_category_id;
  v_status   public.txn_status;
  v_entry    jsonb;
  v_remain   bigint;
  v_settles  uuid;
  v_paying   bigint;
begin
  if not kaban_private.can_write(p_household, p_actor) then
    raise exception 'KABAN: not allowed to write in this household' using errcode = 'insufficient_privilege';
  end if;

  if p_idempotency_key is not null then
    select id into v_id from public.transactions
     where household_id = p_household and created_by = p_actor and idempotency_key = p_idempotency_key;
    if found then return v_id; end if;
  end if;

  if jsonb_typeof(p_entries) <> 'array' or jsonb_array_length(p_entries) = 0 then
    raise exception 'KABAN: entries must be a non-empty array' using errcode = 'invalid_parameter_value';
  end if;

  for v_entry in select * from jsonb_array_elements(p_entries) loop
    if not exists (select 1 from public.accounts a
                    where a.id = (v_entry->>'account_id')::uuid
                      and a.household_id = p_household and not a.is_archived
                      and kaban_private.can_see(a.household_id, a.owner_user_id, p_actor)) then
      raise exception 'KABAN: account % not available', v_entry->>'account_id' using errcode = 'insufficient_privilege';
    end if;
  end loop;

  if v_cat is not null and not exists (
       select 1 from public.categories c where c.id = v_cat and c.household_id = p_household
          and not c.is_archived and kaban_private.can_see(c.household_id, c.owner_user_id, p_actor)) then
    raise exception 'KABAN: category not available' using errcode = 'insufficient_privilege';
  end if;

  if p_bill_occurrence is not null then
    select b.category_id, b.settles_account_id into v_cat, v_settles
      from public.bill_occurrences o join public.bills b on b.id = o.bill_id
     where o.id = p_bill_occurrence and o.household_id = p_household
       and kaban_private.can_see(b.household_id, b.owner_user_id, p_actor);
    if not found then raise exception 'KABAN: bill not available' using errcode = 'insufficient_privilege'; end if;
    if p_type = 'transfer' then
      v_cat := null;                                     -- card payments are not spending
      select (x->>'amount')::bigint into v_paying from jsonb_array_elements(p_entries) x
       where (x->>'account_id')::uuid = v_settles and (x->>'amount')::bigint > 0;
    else
      v_paying := -(select sum((x->>'amount')::bigint) from jsonb_array_elements(p_entries) x);
    end if;
    perform 1 from public.bill_occurrences where id = p_bill_occurrence for update;   -- serialise payments
    select remaining into v_remain from public.bill_occurrence_status where id = p_bill_occurrence;
    if coalesce(v_paying, 0) > v_remain then
      raise exception 'KABAN: payment exceeds remaining due (% centavos)', v_remain using errcode = 'check_violation';
    end if;
  end if;

  v_status := case when p_occurred_on > kaban_private.household_today(p_household) then 'scheduled' else 'posted' end;

  insert into public.transactions (household_id, type, status, occurred_on, description, category_id,
                                   bill_occurrence_id, goal_id, parent_id, replaces_id, source,
                                   quick_entry_token_id, idempotency_key, created_by)
  values (p_household, p_type, v_status, p_occurred_on, p_description, v_cat,
          p_bill_occurrence, p_goal_id, p_parent_id, p_replaces_id, p_source,
          p_token_id, p_idempotency_key, p_actor)
  returning id into v_id;

  insert into public.ledger_entries (transaction_id, household_id, account_id, amount)
  select v_id, p_household, (x->>'account_id')::uuid, (x->>'amount')::bigint
    from jsonb_array_elements(p_entries) x;

  perform kaban_private.validate_transaction(v_id);
  return v_id;
end $$;

-- 2 -------------------------------------------------------------------
create function kaban_private.generate_occurrences_for(p_bill uuid, p_until date)
returns void language sql security definer set search_path = '' as $$
  insert into public.bill_occurrences (household_id, bill_id, due_on, amount_due)
  select b.household_id, b.id, d.due_on, b.estimated_amount
    from public.bills b
   cross join lateral (
     select (b.starts_on + make_interval(months => k * coalesce(b.recurrence_months, 0)))::date as due_on
       from generate_series(0, case when b.recurrence_months is null then 0 else 240 end) k
   ) d
   where b.id = p_bill and b.is_active and d.due_on <= p_until
  on conflict (bill_id, due_on) do nothing;
$$;

-- Daily job: keep 400 days of due dates for every active bill.
create or replace function public.generate_bill_occurrences(p_until date)
returns int language plpgsql security definer set search_path = '' as $$
declare v_count int;
begin
  insert into public.bill_occurrences (household_id, bill_id, due_on, amount_due)
  select b.household_id, b.id, d.due_on, b.estimated_amount
    from public.bills b
   cross join lateral (
     select (b.starts_on + make_interval(months => k * coalesce(b.recurrence_months, 0)))::date as due_on
       from generate_series(0, case when b.recurrence_months is null then 0 else 240 end) k
   ) d
   where b.is_active and d.due_on <= p_until
  on conflict (bill_id, due_on) do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end $$;
revoke execute on function public.generate_bill_occurrences(date) from public, anon, authenticated;

-- Future due dates nobody has paid against (not even a voided payment) can be rebuilt.
create function kaban_private.clear_future_unpaid(p_bill uuid, p_from date)
returns void language sql security definer set search_path = '' as $$
  delete from public.bill_occurrences o
   where o.bill_id = p_bill and o.due_on >= p_from
     and not exists (select 1 from public.transactions t where t.bill_occurrence_id = o.id);
$$;

create function kaban_private.save_bill(
  p_household      uuid,
  p_bill           uuid,          -- null = new bill
  p_name           text,
  p_category       uuid,
  p_amount         bigint,
  p_next_due       date,
  p_repeat_months  int,           -- null = one time; 1, 2, 3, 6 or 12
  p_pay_from       uuid default null,
  p_settles        uuid default null,
  p_personal       boolean default false
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_today date;
  v_id    uuid := p_bill;
  b       public.bills%rowtype;
begin
  if not kaban_private.can_write(p_household) then
    raise exception 'KABAN: not allowed to write in this household' using errcode = 'insufficient_privilege';
  end if;
  v_today := kaban_private.household_today(p_household);
  if length(btrim(coalesce(p_name, ''))) not between 1 and 60 then
    raise exception 'KABAN: bill name must be 1-60 characters' using errcode = 'check_violation';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'KABAN: bill amount must be more than zero' using errcode = 'check_violation';
  end if;
  if p_repeat_months is not null and p_repeat_months not in (1, 2, 3, 6, 12) then
    raise exception 'KABAN: repeat must be every 1, 2, 3, 6 or 12 months' using errcode = 'check_violation';
  end if;
  if p_next_due is null or p_next_due < v_today - 31 then
    raise exception 'KABAN: next due date must be within the last month or later' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.categories c where c.id = p_category and c.household_id = p_household
                    and c.kind = 'expense' and not c.is_archived
                    and kaban_private.can_see(c.household_id, c.owner_user_id)) then
    raise exception 'KABAN: category not available' using errcode = 'insufficient_privilege';
  end if;
  if p_pay_from is not null and not exists (
       select 1 from public.accounts a where a.id = p_pay_from and a.household_id = p_household
          and not a.is_archived and kaban_private.can_see(a.household_id, a.owner_user_id)) then
    raise exception 'KABAN: account not available' using errcode = 'insufficient_privilege';
  end if;
  if p_settles is not null and not exists (
       select 1 from public.accounts a where a.id = p_settles and a.household_id = p_household
          and a.class = 'liability' and not a.is_archived and kaban_private.can_see(a.household_id, a.owner_user_id)) then
    raise exception 'KABAN: credit card not available' using errcode = 'insufficient_privilege';
  end if;

  if v_id is null then
    insert into public.bills (household_id, owner_user_id, name, category_id, estimated_amount,
                              pay_from_account_id, starts_on, recurrence_months, settles_account_id)
    values (p_household, case when p_personal then auth.uid() end, btrim(p_name), p_category, p_amount,
            p_pay_from, p_next_due, p_repeat_months, p_settles)
    returning id into v_id;
  else
    select * into b from public.bills where id = v_id and household_id = p_household for update;
    if not found or not kaban_private.can_see(b.household_id, b.owner_user_id) then
      raise exception 'KABAN: bill not available' using errcode = 'insufficient_privilege';
    end if;
    if b.starts_on <> p_next_due or b.recurrence_months is distinct from p_repeat_months then
      -- new schedule: drop unpaid future due dates, rebuild from the new next due date
      perform kaban_private.clear_future_unpaid(v_id, least(v_today, p_next_due));
    end if;
    update public.bills
       set name = btrim(p_name), category_id = p_category, estimated_amount = p_amount,
           pay_from_account_id = p_pay_from, settles_account_id = p_settles,
           starts_on = p_next_due, recurrence_months = p_repeat_months, is_active = true
     where id = v_id;
    -- a new estimate applies to future months nobody has paid yet
    update public.bill_occurrences o set amount_due = p_amount
     where o.bill_id = v_id and o.due_on >= v_today
       and not exists (select 1 from public.transactions t where t.bill_occurrence_id = o.id);
  end if;

  perform kaban_private.generate_occurrences_for(v_id, v_today + 400);
  return v_id;
end $$;

-- Change what is due for one month (e.g. this month's Meralco is 3,450).
create function kaban_private.set_occurrence_amount(p_occurrence uuid, p_amount bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare s public.bill_occurrence_status%rowtype;
begin
  select * into s from public.bill_occurrence_status where id = p_occurrence;
  if not found or not kaban_private.can_write(s.household_id)
     or not kaban_private.can_see(s.household_id, s.owner_user_id) then
    raise exception 'KABAN: bill not available' using errcode = 'insufficient_privilege';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'KABAN: bill amount must be more than zero' using errcode = 'check_violation';
  end if;
  if p_amount < s.paid then
    raise exception 'KABAN: amount is less than what was already paid' using errcode = 'check_violation';
  end if;
  update public.bill_occurrences set amount_due = p_amount where id = p_occurrence;
end $$;

create function kaban_private.skip_bill_occurrence(p_occurrence uuid, p_skip boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare s public.bill_occurrence_status%rowtype;
begin
  select * into s from public.bill_occurrence_status where id = p_occurrence;
  if not found or not kaban_private.can_write(s.household_id)
     or not kaban_private.can_see(s.household_id, s.owner_user_id) then
    raise exception 'KABAN: bill not available' using errcode = 'insufficient_privilege';
  end if;
  update public.bill_occurrences set is_skipped = p_skip where id = p_occurrence;
end $$;

-- Stop a bill: no more due dates or reminders. Past months and payments stay.
create function kaban_private.stop_bill(p_bill uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare b public.bills%rowtype;
begin
  select * into b from public.bills where id = p_bill;
  if not found or not kaban_private.can_write(b.household_id)
     or not kaban_private.can_see(b.household_id, b.owner_user_id) then
    raise exception 'KABAN: bill not available' using errcode = 'insufficient_privilege';
  end if;
  update public.bills set is_active = false where id = p_bill;
  perform kaban_private.clear_future_unpaid(p_bill, kaban_private.household_today(b.household_id));
end $$;

-- 3 -------------------------------------------------------------------
alter table public.households
  add column remind_days_before smallint not null default 3 check (remind_days_before between 0 and 14);

create table public.push_subscriptions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  endpoint      text not null unique check (endpoint like 'https://%' and length(endpoint) <= 1000),
  p256dh        text not null check (length(p256dh) between 20 and 200),
  auth          text not null check (length(auth) between 8 and 100),
  device        text check (length(device) <= 80),
  created_at    timestamptz not null default now(),
  last_sent_at  timestamptz
);
create index on public.push_subscriptions (user_id);

create table public.bill_reminders_sent (
  occurrence_id uuid not null references public.bill_occurrences(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  kind          text not null check (kind in ('before', 'due', 'overdue')),
  sent_at       timestamptz not null default now(),
  primary key (occurrence_id, user_id, kind)
);

alter table public.push_subscriptions  enable row level security;
alter table public.bill_reminders_sent enable row level security;
create policy push_select on public.push_subscriptions for select to authenticated using (user_id = auth.uid());
create policy reminders_select on public.bill_reminders_sent for select to authenticated using (user_id = auth.uid());
revoke all on public.push_subscriptions, public.bill_reminders_sent from anon;
revoke insert, update, delete on public.push_subscriptions, public.bill_reminders_sent from authenticated;

create function kaban_private.save_push_subscription(p_endpoint text, p_p256dh text, p_auth text, p_device text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'KABAN: sign in first' using errcode = 'insufficient_privilege';
  end if;
  -- the same device re-subscribing (or a new account on it) takes over the row
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, device)
  values (auth.uid(), p_endpoint, p_p256dh, p_auth, left(p_device, 80))
  on conflict (endpoint) do update
     set user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth,
         device = excluded.device, created_at = now();
end $$;

create function kaban_private.remove_push_subscription(p_endpoint text)
returns void language sql security definer set search_path = '' as $$
  delete from public.push_subscriptions where endpoint = p_endpoint and user_id = auth.uid();
$$;

-- 4 -------------------------------------------------------------------
-- Reminders due now: N days before (household setting), on the due date,
-- and the day after if still unpaid. Each is sent once per person.
create function public.bill_reminders_due()
returns table (user_id uuid, occurrence_id uuid, kind text, bill_name text,
               due_on date, amount_left bigint, days_left int)
language sql stable security definer set search_path = '' as $$
  with open_bills as (
    select s.id as occ, s.household_id, s.name, s.owner_user_id, s.due_on, s.remaining,
           kaban_private.household_today(s.household_id) as today, h.remind_days_before as rdb
      from public.bill_occurrence_status s
      join public.bills b on b.id = s.bill_id
      join public.households h on h.id = s.household_id
     where b.is_active and s.remaining > 0 and not s.is_skipped
  ),
  in_window as (
    select o.*,
           case when o.due_on = o.today - 1 then 'overdue'
                when o.due_on = o.today     then 'due'
                when o.due_on between o.today + 1 and o.today + o.rdb then 'before'
           end as kind
      from open_bills o
  )
  select m.user_id, w.occ, w.kind, w.name, w.due_on, w.remaining, (w.due_on - w.today)::int
    from in_window w
    join public.household_members m on m.household_id = w.household_id
   where w.kind is not null
     and (w.owner_user_id is null or w.owner_user_id = m.user_id)
     and exists (select 1 from public.push_subscriptions p where p.user_id = m.user_id)
     and not exists (select 1 from public.bill_reminders_sent r
                      where r.occurrence_id = w.occ and r.user_id = m.user_id and r.kind = w.kind)
   order by m.user_id, w.due_on;
$$;

create function public.mark_bill_reminders_sent(p_items jsonb)
returns int language plpgsql security definer set search_path = '' as $$
declare v_count int;
begin
  insert into public.bill_reminders_sent (occurrence_id, user_id, kind)
  select (x->>'occurrence_id')::uuid, (x->>'user_id')::uuid, x->>'kind'
    from jsonb_array_elements(p_items) x
  on conflict do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

-- 5. Public wrappers + grants (same pattern as 0002) -------------------
create function public.save_bill(
  p_household uuid, p_bill uuid, p_name text, p_category uuid, p_amount bigint, p_next_due date,
  p_repeat_months int, p_pay_from uuid default null, p_settles uuid default null, p_personal boolean default false
) returns uuid language sql security invoker set search_path = '' as $$
  select kaban_private.save_bill(p_household, p_bill, p_name, p_category, p_amount, p_next_due,
                                 p_repeat_months, p_pay_from, p_settles, p_personal)
$$;
create function public.set_occurrence_amount(p_occurrence uuid, p_amount bigint)
returns void language sql security invoker set search_path = '' as $$
  select kaban_private.set_occurrence_amount(p_occurrence, p_amount)
$$;
create function public.skip_bill_occurrence(p_occurrence uuid, p_skip boolean)
returns void language sql security invoker set search_path = '' as $$
  select kaban_private.skip_bill_occurrence(p_occurrence, p_skip)
$$;
create function public.stop_bill(p_bill uuid)
returns void language sql security invoker set search_path = '' as $$
  select kaban_private.stop_bill(p_bill)
$$;
create function public.save_push_subscription(p_endpoint text, p_p256dh text, p_auth text, p_device text default null)
returns void language sql security invoker set search_path = '' as $$
  select kaban_private.save_push_subscription(p_endpoint, p_p256dh, p_auth, p_device)
$$;
create function public.remove_push_subscription(p_endpoint text)
returns void language sql security invoker set search_path = '' as $$
  select kaban_private.remove_push_subscription(p_endpoint)
$$;

revoke execute on function
  kaban_private.save_bill(uuid, uuid, text, uuid, bigint, date, int, uuid, uuid, boolean),
  kaban_private.set_occurrence_amount(uuid, bigint), kaban_private.skip_bill_occurrence(uuid, boolean),
  kaban_private.stop_bill(uuid), kaban_private.save_push_subscription(text, text, text, text),
  kaban_private.remove_push_subscription(text), kaban_private.generate_occurrences_for(uuid, date),
  kaban_private.clear_future_unpaid(uuid, date),
  public.save_bill(uuid, uuid, text, uuid, bigint, date, int, uuid, uuid, boolean),
  public.set_occurrence_amount(uuid, bigint), public.skip_bill_occurrence(uuid, boolean),
  public.stop_bill(uuid), public.save_push_subscription(text, text, text, text),
  public.remove_push_subscription(text),
  public.bill_reminders_due(), public.mark_bill_reminders_sent(jsonb)
from public, anon;
revoke execute on function public.bill_reminders_due(), public.mark_bill_reminders_sent(jsonb) from authenticated;

grant execute on function
  kaban_private.save_bill(uuid, uuid, text, uuid, bigint, date, int, uuid, uuid, boolean),
  kaban_private.set_occurrence_amount(uuid, bigint), kaban_private.skip_bill_occurrence(uuid, boolean),
  kaban_private.stop_bill(uuid), kaban_private.save_push_subscription(text, text, text, text),
  kaban_private.remove_push_subscription(text),
  public.save_bill(uuid, uuid, text, uuid, bigint, date, int, uuid, uuid, boolean),
  public.set_occurrence_amount(uuid, bigint), public.skip_bill_occurrence(uuid, boolean),
  public.stop_bill(uuid), public.save_push_subscription(text, text, text, text),
  public.remove_push_subscription(text)
to authenticated;
grant execute on function public.bill_reminders_due(), public.mark_bill_reminders_sent(jsonb) to service_role;

-- Existing bills: extend due dates to 400 days so yearly bills show up.
select public.generate_bill_occurrences(current_date + 400);
