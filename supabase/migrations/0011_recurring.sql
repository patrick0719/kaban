-- =====================================================================
-- KABAN 0011: repeating entries, and entries dated ahead finally post
--
-- 1. FIX: an entry saved with a future date stayed "scheduled" forever
--    and never reached the balances. A daily job now posts it on its date.
-- 2. Repeating entries: income, expenses or transfers that come back on a
--    schedule (salary on the 15th and the last day, Netflix monthly, the
--    weekly allowance). Each one either:
--      - asks first (default): shows on Home when due; you confirm the
--        actual amount and date, or skip. Good for pay with no fixed date.
--      - records itself: posted automatically on its date.
--    Bills you pay yourself stay in Bills (reminders, set-aside money).
-- 3. run_daily_entries(): the daily job for 1 and 2 (pg_cron, 00:10 Manila).
--
-- Safe order: run after 0001-0010. The cron job is created here when
-- pg_cron is installed (it is, if you ran setup_reminders.sql).
-- =====================================================================

-- 2a. Table -------------------------------------------------------------
create table public.recurring_entries (
  id             uuid primary key default gen_random_uuid(),
  household_id   uuid not null references public.households(id) on delete cascade,
  owner_user_id  uuid references auth.users(id),          -- set when a personal account is involved
  name           text not null check (length(btrim(name)) between 1 and 60),
  kind           text not null check (kind in ('income', 'expense', 'transfer')),
  amount         bigint not null check (amount > 0 and amount <= 100000000000),
  category_id    uuid,
  account_id     uuid not null,                           -- income: into; expense/transfer: from
  to_account_id  uuid,                                    -- transfer only
  frequency      text not null check (frequency in ('weekly', 'every_2_weeks', 'monthly', 'twice_a_month')),
  day1           smallint,                                -- monthly / twice a month: day of month (31 = last day)
  day2           smallint,                                -- twice a month: the later day
  next_due       date not null,
  auto_post      boolean not null default false,
  is_active      boolean not null default true,
  last_error     text,                                    -- why the last automatic post failed
  created_by     uuid not null references auth.users(id),
  created_at     timestamptz not null default now(),
  unique (id, household_id),
  foreign key (category_id, household_id)   references public.categories(id, household_id),
  foreign key (account_id, household_id)    references public.accounts(id, household_id),
  foreign key (to_account_id, household_id) references public.accounts(id, household_id),
  constraint recurring_kind_fields check (
    (kind = 'transfer' and to_account_id is not null and category_id is null and to_account_id <> account_id) or
    (kind <> 'transfer' and to_account_id is null and category_id is not null)),
  constraint recurring_days check (
    (frequency in ('weekly', 'every_2_weeks') and day1 is null and day2 is null) or
    (frequency = 'monthly' and day1 between 1 and 31 and day2 is null) or
    (frequency = 'twice_a_month' and day1 between 1 and 27 and day2 > day1 and day2 <= 31))
);
create index on public.recurring_entries (household_id, next_due) where is_active;

alter table public.recurring_entries enable row level security;
create policy rec_select on public.recurring_entries for select to authenticated
  using (kaban_private.can_see(household_id, owner_user_id));
revoke all on public.recurring_entries from anon;
revoke insert, update, delete, truncate on public.recurring_entries from authenticated;   -- writes via functions
grant select on public.recurring_entries to authenticated;

-- Which repeating entry (and which due date) a transaction came from.
alter table public.transactions add column recurring_id  uuid;
alter table public.transactions add column recurring_due date;
alter table public.transactions
  add foreign key (recurring_id, household_id) references public.recurring_entries(id, household_id)
  on delete set null (recurring_id);
create index on public.transactions (recurring_id) where recurring_id is not null;

-- 2b. Schedule math -------------------------------------------------------
-- Day d of the month that starts at p_month, clamped to the month's end (31 -> 30 / 28).
create function kaban_private.day_in_month(p_month date, p_day int)
returns date language sql immutable set search_path = '' as $$
  select least(date_trunc('month', p_month)::date + (p_day - 1),
               (date_trunc('month', p_month) + interval '1 month - 1 day')::date)
$$;

-- The next scheduled date strictly after p_after.
create function kaban_private.recurring_after(p_frequency text, p_day1 int, p_day2 int, p_after date)
returns date language sql immutable set search_path = '' as $$
  select case p_frequency
    when 'weekly'        then p_after + 7
    when 'every_2_weeks' then p_after + 14
    else (select min(d) from (values
            (kaban_private.day_in_month(p_after, p_day1)),
            (kaban_private.day_in_month(p_after, coalesce(p_day2, p_day1))),
            (kaban_private.day_in_month((p_after + interval '1 month')::date, p_day1))) v(d)
          where d > p_after)
  end
$$;

-- The first scheduled date on or after p_from.
create function kaban_private.recurring_first(p_frequency text, p_day1 int, p_day2 int, p_from date)
returns date language sql immutable set search_path = '' as $$
  select case when p_frequency in ('weekly', 'every_2_weeks') then p_from
              else kaban_private.recurring_after(p_frequency, p_day1, p_day2, p_from - 1) end
$$;

-- The ledger lines for one occurrence.
create function kaban_private.recurring_lines(r public.recurring_entries, p_amount bigint)
returns jsonb language sql immutable set search_path = '' as $$
  select case r.kind
    when 'income'  then jsonb_build_array(jsonb_build_object('account_id', r.account_id, 'amount', p_amount))
    when 'expense' then jsonb_build_array(jsonb_build_object('account_id', r.account_id, 'amount', -p_amount))
    else jsonb_build_array(jsonb_build_object('account_id', r.account_id,    'amount', -p_amount),
                           jsonb_build_object('account_id', r.to_account_id, 'amount',  p_amount))
  end
$$;

-- Post one occurrence as p_actor and link it. Returns the transaction id.
create function kaban_private.post_recurring(
  r public.recurring_entries, p_actor uuid, p_due date, p_on date, p_amount bigint,
  p_key text, p_source public.txn_source
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  v_id := kaban_private.post_transaction_as(
            p_actor, r.household_id, r.kind::public.txn_type, p_on, kaban_private.recurring_lines(r, p_amount),
            r.category_id, r.name, null, null, null, p_key, p_source);
  update public.transactions set recurring_id = r.id, recurring_due = p_due
   where id = v_id and recurring_id is null;
  return v_id;
end $$;

-- 2c. Write API -----------------------------------------------------------
create function kaban_private.save_recurring(
  p_household   uuid,
  p_id          uuid,          -- null = new
  p_name        text,
  p_kind        text,
  p_amount      bigint,
  p_category    uuid,
  p_account     uuid,
  p_to_account  uuid,
  p_frequency   text,
  p_day1        int,
  p_day2        int,
  p_next        date,          -- first date to use; snapped to the schedule
  p_auto_post   boolean
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_today  date;
  v_id     uuid := p_id;
  v_owner  uuid;
  v_next   date;
  a_from   public.accounts%rowtype;
  a_to     public.accounts%rowtype;
  r        public.recurring_entries%rowtype;
begin
  if not kaban_private.can_write(p_household) then
    raise exception 'KABAN: not allowed to write in this household' using errcode = 'insufficient_privilege';
  end if;
  v_today := kaban_private.household_today(p_household);

  if length(btrim(coalesce(p_name, ''))) not between 1 and 60 then
    raise exception 'KABAN: name must be 1-60 characters' using errcode = 'check_violation';
  end if;
  if p_kind not in ('income', 'expense', 'transfer') then
    raise exception 'KABAN: type must be income, expense or transfer' using errcode = 'invalid_parameter_value';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'KABAN: amount must be more than zero' using errcode = 'check_violation';
  end if;
  if p_frequency not in ('weekly', 'every_2_weeks', 'monthly', 'twice_a_month') then
    raise exception 'KABAN: repeat must be weekly, every 2 weeks, monthly or twice a month'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_frequency in ('weekly', 'every_2_weeks') then
    p_day1 := null; p_day2 := null;
  elsif p_frequency = 'monthly' then
    p_day2 := null;
    if p_day1 is null or p_day1 not between 1 and 31 then
      raise exception 'KABAN: choose the day of the month' using errcode = 'check_violation';
    end if;
  elsif p_day1 is null or p_day2 is null or p_day1 not between 1 and 27 or p_day2 <= p_day1 or p_day2 > 31 then
    raise exception 'KABAN: choose two different days of the month' using errcode = 'check_violation';
  end if;
  if p_next is null or p_next < v_today - 31 or p_next > v_today + 366 then
    raise exception 'KABAN: next date must be within the last month or the coming year' using errcode = 'check_violation';
  end if;

  select * into a_from from public.accounts a
   where a.id = p_account and a.household_id = p_household and not a.is_archived
     and kaban_private.can_see(a.household_id, a.owner_user_id);
  if not found then raise exception 'KABAN: account not available' using errcode = 'insufficient_privilege'; end if;
  if p_kind = 'income' and a_from.class <> 'asset' then
    raise exception 'KABAN: income must go into a money account, not a card' using errcode = 'check_violation';
  end if;
  if p_kind = 'transfer' then
    select * into a_to from public.accounts a
     where a.id = p_to_account and a.household_id = p_household and not a.is_archived
       and kaban_private.can_see(a.household_id, a.owner_user_id);
    if not found then raise exception 'KABAN: account not available' using errcode = 'insufficient_privilege'; end if;
    if a_to.id = a_from.id then
      raise exception 'KABAN: From and To must be different accounts' using errcode = 'check_violation';
    end if;
    p_category := null;
  else
    p_to_account := null;
    if not exists (select 1 from public.categories c where c.id = p_category and c.household_id = p_household
                      and not c.is_archived and c.kind::text = p_kind
                      and kaban_private.can_see(c.household_id, c.owner_user_id)) then
      raise exception 'KABAN: category not available' using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- personal if it touches a personal account (always the caller's: others' are invisible)
  v_owner := coalesce(a_from.owner_user_id, a_to.owner_user_id);
  v_next  := kaban_private.recurring_first(p_frequency, p_day1, p_day2, p_next);

  if v_id is null then
    insert into public.recurring_entries (household_id, owner_user_id, name, kind, amount, category_id,
                                          account_id, to_account_id, frequency, day1, day2, next_due,
                                          auto_post, created_by)
    values (p_household, v_owner, btrim(p_name), p_kind, p_amount, p_category, p_account, p_to_account,
            p_frequency, p_day1, p_day2, v_next, coalesce(p_auto_post, false), auth.uid())
    returning id into v_id;
  else
    select * into r from public.recurring_entries
     where id = v_id and household_id = p_household for update;
    if not found or not kaban_private.can_see(r.household_id, r.owner_user_id) then
      raise exception 'KABAN: repeating entry not available' using errcode = 'insufficient_privilege';
    end if;
    update public.recurring_entries
       set owner_user_id = v_owner, name = btrim(p_name), kind = p_kind, amount = p_amount,
           category_id = p_category, account_id = p_account, to_account_id = p_to_account,
           frequency = p_frequency, day1 = p_day1, day2 = p_day2, next_due = v_next,
           auto_post = coalesce(p_auto_post, false), is_active = true, last_error = null,
           -- automatic posts run as the person who last set them up
           created_by = case when coalesce(p_auto_post, false) then auth.uid() else created_by end
     where id = v_id;
  end if;
  return v_id;
end $$;

-- Record the occurrence due on p_due (normally next_due), with the real amount and date.
-- A repeat of the same request (same p_key) returns the same transaction.
create function kaban_private.record_recurring(
  p_id uuid, p_due date, p_amount bigint, p_on date, p_key text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare r public.recurring_entries%rowtype; v_id uuid; v_today date;
begin
  select * into r from public.recurring_entries where id = p_id for update;
  if not found or not kaban_private.can_write(r.household_id)
     or not kaban_private.can_see(r.household_id, r.owner_user_id) then
    raise exception 'KABAN: repeating entry not available' using errcode = 'insufficient_privilege';
  end if;
  if p_key is not null then
    select id into v_id from public.transactions
     where household_id = r.household_id and created_by = auth.uid() and idempotency_key = p_key;
    if found then return v_id; end if;
  end if;
  if not r.is_active then
    raise exception 'KABAN: this repeating entry was stopped' using errcode = 'check_violation';
  end if;
  if p_due is distinct from r.next_due then
    raise exception 'KABAN: this one was already recorded or skipped' using errcode = 'check_violation';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'KABAN: amount must be more than zero' using errcode = 'check_violation';
  end if;
  v_today := kaban_private.household_today(r.household_id);
  if p_on is null or p_on < v_today - 366 or p_on > v_today + 366 then
    raise exception 'KABAN: choose a date within a year of today' using errcode = 'check_violation';
  end if;

  v_id := kaban_private.post_recurring(r, auth.uid(), p_due, p_on, p_amount, p_key, 'app');
  update public.recurring_entries
     set next_due = kaban_private.recurring_after(frequency, day1, day2, next_due), last_error = null
   where id = p_id;
  return v_id;
end $$;

-- Skip the occurrence due on p_due. Skipping one that is already gone does nothing.
create function kaban_private.skip_recurring(p_id uuid, p_due date)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.recurring_entries%rowtype;
begin
  select * into r from public.recurring_entries where id = p_id for update;
  if not found or not kaban_private.can_write(r.household_id)
     or not kaban_private.can_see(r.household_id, r.owner_user_id) then
    raise exception 'KABAN: repeating entry not available' using errcode = 'insufficient_privilege';
  end if;
  if r.is_active and p_due = r.next_due then
    update public.recurring_entries
       set next_due = kaban_private.recurring_after(frequency, day1, day2, next_due), last_error = null
     where id = p_id;
  end if;
end $$;

-- Stop: nothing more is recorded or asked. Entries already recorded stay.
create function kaban_private.stop_recurring(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.recurring_entries%rowtype;
begin
  select * into r from public.recurring_entries where id = p_id for update;
  if not found or not kaban_private.can_write(r.household_id)
     or not kaban_private.can_see(r.household_id, r.owner_user_id) then
    raise exception 'KABAN: repeating entry not available' using errcode = 'insufficient_privilege';
  end if;
  update public.recurring_entries set is_active = false where id = p_id;
end $$;

-- 3. Daily job ------------------------------------------------------------
-- Posts entries whose date has arrived, then records automatic repeating
-- entries that are due (catching up on missed days, at most 62 each run).
-- Safe to run more than once a day: every automatic post has a fixed key.
create function public.run_daily_entries()
returns table (posted_scheduled int, recorded int, failed int)
language plpgsql security definer set search_path = '' as $$
declare
  r       public.recurring_entries%rowtype;
  v_today date;
  v_due   date;
  n_sched int := 0;
  n_rec   int := 0;
  n_fail  int := 0;
  i       int;
begin
  update public.transactions t
     set status = 'posted'
    from public.households h
   where h.id = t.household_id and t.status = 'scheduled'
     and t.occurred_on <= (now() at time zone h.timezone)::date;
  get diagnostics n_sched = row_count;

  for r in
    select x.* from public.recurring_entries x join public.households h on h.id = x.household_id
     where x.is_active and x.auto_post and x.next_due <= (now() at time zone h.timezone)::date
     order by x.next_due
  loop
    v_today := kaban_private.household_today(r.household_id);
    v_due := r.next_due;
    i := 0;
    begin
      while v_due <= v_today and i < 62 loop
        perform kaban_private.post_recurring(r, r.created_by, v_due, v_due, r.amount,
                                             'recurring:' || r.id || ':' || v_due, 'system');
        v_due := kaban_private.recurring_after(r.frequency, r.day1, r.day2, v_due);
        i := i + 1;
      end loop;
      update public.recurring_entries set next_due = v_due, last_error = null where id = r.id;
      n_rec := n_rec + i;
    exception when others then
      -- nothing for this one is kept; it is retried tomorrow and shown in the app
      update public.recurring_entries set last_error = left(sqlerrm, 200) where id = r.id;
      n_fail := n_fail + 1;
    end;
  end loop;

  return query select n_sched, n_rec, n_fail;
end $$;

-- Invoker wrappers ----------------------------------------------------------
create function public.save_recurring(
  p_household uuid, p_id uuid, p_name text, p_kind text, p_amount bigint, p_category uuid,
  p_account uuid, p_to_account uuid, p_frequency text, p_day1 int, p_day2 int, p_next date, p_auto_post boolean
) returns uuid language sql security invoker set search_path = '' as $$
  select kaban_private.save_recurring(p_household, p_id, p_name, p_kind, p_amount, p_category,
                                      p_account, p_to_account, p_frequency, p_day1, p_day2, p_next, p_auto_post)
$$;
create function public.record_recurring(p_id uuid, p_due date, p_amount bigint, p_on date, p_key text default null)
returns uuid language sql security invoker set search_path = '' as $$
  select kaban_private.record_recurring(p_id, p_due, p_amount, p_on, p_key)
$$;
create function public.skip_recurring(p_id uuid, p_due date)
returns void language sql security invoker set search_path = '' as $$
  select kaban_private.skip_recurring(p_id, p_due)
$$;
create function public.stop_recurring(p_id uuid)
returns void language sql security invoker set search_path = '' as $$
  select kaban_private.stop_recurring(p_id)
$$;

revoke execute on function
  kaban_private.day_in_month(date, int), kaban_private.recurring_after(text, int, int, date),
  kaban_private.recurring_first(text, int, int, date),
  kaban_private.recurring_lines(public.recurring_entries, bigint),
  kaban_private.post_recurring(public.recurring_entries, uuid, date, date, bigint, text, public.txn_source),
  kaban_private.save_recurring(uuid, uuid, text, text, bigint, uuid, uuid, uuid, text, int, int, date, boolean),
  kaban_private.record_recurring(uuid, date, bigint, date, text),
  kaban_private.skip_recurring(uuid, date), kaban_private.stop_recurring(uuid),
  public.save_recurring(uuid, uuid, text, text, bigint, uuid, uuid, uuid, text, int, int, date, boolean),
  public.record_recurring(uuid, date, bigint, date, text),
  public.skip_recurring(uuid, date), public.stop_recurring(uuid),
  public.run_daily_entries()
from public, anon;
revoke execute on function public.run_daily_entries() from authenticated;

grant execute on function
  kaban_private.save_recurring(uuid, uuid, text, text, bigint, uuid, uuid, uuid, text, int, int, date, boolean),
  kaban_private.record_recurring(uuid, date, bigint, date, text),
  kaban_private.skip_recurring(uuid, date), kaban_private.stop_recurring(uuid),
  public.save_recurring(uuid, uuid, text, text, bigint, uuid, uuid, uuid, text, int, int, date, boolean),
  public.record_recurring(uuid, date, bigint, date, text),
  public.skip_recurring(uuid, date), public.stop_recurring(uuid)
to authenticated;
grant execute on function public.run_daily_entries() to service_role;

-- Post anything already overdue right now, then every day at 00:10 Manila.
select * from public.run_daily_entries();

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobname) from cron.job where jobname = 'kaban-daily-entries';
    perform cron.schedule('kaban-daily-entries', '10 16 * * *',      -- 16:10 UTC = 00:10 in Manila
                          'select public.run_daily_entries()');
  else
    raise notice 'pg_cron is not installed yet: after setup_reminders.sql, run the daily job lines in setup_daily_entries.sql';
  end if;
end $$;
