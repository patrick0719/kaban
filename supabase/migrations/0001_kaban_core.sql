-- =====================================================================
-- KABAN core schema: real-money ledger, bills, goals, budgets,
-- available-to-spend, RLS, and scoped quick-entry tokens.
--
-- Target: Supabase (Postgres 15+). Uses auth.uid(), auth.users,
-- roles anon / authenticated / service_role, and pgcrypto.
--
-- Money: bigint centavos everywhere (PHP 1.00 = 100).
-- Clients never INSERT/UPDATE/DELETE ledger rows directly; they call
-- the SECURITY DEFINER functions in section 6.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

create schema if not exists kaban_private;   -- helpers not exposed via the API
revoke all on schema kaban_private from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 1. Types
-- ---------------------------------------------------------------------
create type public.household_role as enum ('owner', 'admin', 'member', 'viewer');
create type public.account_kind   as enum ('cash', 'bank', 'ewallet', 'savings', 'credit_card', 'loan', 'other');
create type public.account_class  as enum ('asset', 'liability');
create type public.category_kind  as enum ('income', 'expense');
create type public.txn_type as enum (
  'income', 'expense', 'bill_payment', 'refund',
  'transfer', 'savings_contribution',
  'opening_balance', 'adjustment'
);
create type public.txn_status  as enum ('posted', 'scheduled', 'void');
create type public.txn_source  as enum ('app', 'quick_entry', 'import', 'system');
create type public.goal_mode   as enum ('account', 'earmark');
create type public.reserve_horizon as enum ('month_end', 'next_payday', 'days');

-- ---------------------------------------------------------------------
-- 2. Households and members
-- ---------------------------------------------------------------------
create table public.households (
  id               uuid primary key default gen_random_uuid(),
  name             text not null check (length(name) between 1 and 80),
  currency         char(3) not null default 'PHP',
  timezone         text not null default 'Asia/Manila',
  reserve_horizon  public.reserve_horizon not null default 'month_end',
  next_payday      date,
  reserve_days     int not null default 30 check (reserve_days between 1 and 120),
  created_by       uuid not null references auth.users(id),
  created_at       timestamptz not null default now()
);

create table public.household_members (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  role         public.household_role not null default 'member',
  joined_at    timestamptz not null default now(),
  primary key (household_id, user_id)
);
create index on public.household_members (user_id);

-- ---------------------------------------------------------------------
-- 3. Accounts and categories
-- ---------------------------------------------------------------------
create table public.accounts (
  id             uuid primary key default gen_random_uuid(),
  household_id   uuid not null references public.households(id) on delete cascade,
  owner_user_id  uuid references auth.users(id),          -- null = shared household account
  name           text not null check (length(name) between 1 and 60),
  kind           public.account_kind not null,
  class          public.account_class not null,
  is_spendable   boolean not null,
  is_archived    boolean not null default false,
  created_by     uuid not null references auth.users(id),
  created_at     timestamptz not null default now(),
  unique (id, household_id),
  -- liabilities are never part of the spending pool
  constraint liability_not_spendable check (class = 'asset' or not is_spendable),
  constraint kind_matches_class check (
    (kind in ('credit_card', 'loan') and class = 'liability') or
    (kind not in ('credit_card', 'loan') and class = 'asset')
  )
);
create index on public.accounts (household_id);

create table public.categories (
  id             uuid primary key default gen_random_uuid(),
  household_id   uuid not null references public.households(id) on delete cascade,
  owner_user_id  uuid references auth.users(id),          -- null = shared category
  kind           public.category_kind not null,
  name           text not null check (length(name) between 1 and 40),
  parent_id      uuid references public.categories(id),
  is_archived    boolean not null default false,
  unique (id, household_id),
  unique nulls not distinct (household_id, owner_user_id, kind, name)
);

-- ---------------------------------------------------------------------
-- 4. Bills, goals, earmarks, budgets
-- ---------------------------------------------------------------------
create table public.bills (
  id                   uuid primary key default gen_random_uuid(),
  household_id         uuid not null references public.households(id) on delete cascade,
  owner_user_id        uuid references auth.users(id),     -- null = shared bill
  name                 text not null,
  category_id          uuid not null,
  estimated_amount     bigint not null check (estimated_amount > 0),
  pay_from_account_id  uuid,                               -- null = paid from the spending pool
  starts_on            date not null,
  recurrence_months    int check (recurrence_months in (1, 2, 3, 6, 12)),  -- null = one-time
  is_active            boolean not null default true,
  created_at           timestamptz not null default now(),
  unique (id, household_id),
  foreign key (category_id, household_id) references public.categories(id, household_id),
  foreign key (pay_from_account_id, household_id) references public.accounts(id, household_id)
);

-- One row per due date. A bill row itself never touches the ledger.
create table public.bill_occurrences (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null,
  bill_id       uuid not null,
  due_on        date not null,
  amount_due    bigint not null check (amount_due > 0),
  is_skipped    boolean not null default false,
  unique (bill_id, due_on),
  unique (id, household_id),
  foreign key (bill_id, household_id) references public.bills(id, household_id) on delete cascade
);
create index on public.bill_occurrences (household_id, due_on);

create table public.savings_goals (
  id                 uuid primary key default gen_random_uuid(),
  household_id       uuid not null references public.households(id) on delete cascade,
  owner_user_id      uuid references auth.users(id),       -- null = shared goal
  name               text not null,
  target_amount      bigint not null check (target_amount > 0),
  target_date        date,
  mode               public.goal_mode not null,
  linked_account_id  uuid,                                  -- required for mode 'account'
  is_archived        boolean not null default false,
  created_at         timestamptz not null default now(),
  unique (id, household_id),
  unique (linked_account_id),                               -- one goal per dedicated account
  foreign key (linked_account_id, household_id) references public.accounts(id, household_id),
  constraint mode_link check (
    (mode = 'account' and linked_account_id is not null) or
    (mode = 'earmark' and linked_account_id is null)
  )
);

-- Money set aside for a goal while it stays inside a spendable account.
create table public.goal_earmarks (
  goal_id       uuid not null,
  account_id    uuid not null,
  household_id  uuid not null,
  amount        bigint not null check (amount > 0),
  updated_at    timestamptz not null default now(),
  primary key (goal_id, account_id),
  foreign key (goal_id, household_id)    references public.savings_goals(id, household_id) on delete cascade,
  foreign key (account_id, household_id) references public.accounts(id, household_id)
);

create table public.budgets (
  id             uuid primary key default gen_random_uuid(),
  household_id   uuid not null references public.households(id) on delete cascade,
  owner_user_id  uuid references auth.users(id),
  category_id    uuid not null,
  month          date not null check (month = date_trunc('month', month)::date),
  amount         bigint not null check (amount >= 0),
  unique nulls not distinct (household_id, owner_user_id, category_id, month),
  foreign key (category_id, household_id) references public.categories(id, household_id)
);

-- ---------------------------------------------------------------------
-- 5. Ledger
-- ---------------------------------------------------------------------
create table public.quick_entry_tokens (
  id                   uuid primary key default gen_random_uuid(),
  household_id         uuid not null references public.households(id) on delete cascade,
  user_id              uuid not null references auth.users(id) on delete cascade,
  label                text not null check (length(label) between 1 and 40),   -- "Ana's iPhone"
  token_prefix         text not null,                       -- first chars, shown in settings
  token_hash           bytea not null unique,               -- sha256 of the full token
  allowed_types        public.txn_type[] not null default '{expense}',
  default_account_id   uuid not null,
  allowed_account_ids  uuid[] not null default '{}',        -- empty = default account only
  max_amount           bigint not null default 2000000 check (max_amount > 0),     -- PHP 20,000
  daily_limit          int not null default 30 check (daily_limit between 1 and 200),
  expires_at           timestamptz not null default now() + interval '90 days',
  created_at           timestamptz not null default now(),
  last_used_at         timestamptz,
  revoked_at           timestamptz,
  constraint qe_types_subset check (allowed_types <@ array['expense', 'income']::public.txn_type[]),
  foreign key (default_account_id, household_id) references public.accounts(id, household_id)
);

create table public.transactions (
  id                    uuid primary key default gen_random_uuid(),
  household_id          uuid not null references public.households(id) on delete cascade,
  type                  public.txn_type not null,
  status                public.txn_status not null default 'posted',
  occurred_on           date not null,
  description           text check (length(description) <= 200),
  category_id           uuid,
  bill_occurrence_id    uuid,
  goal_id               uuid,
  parent_id             uuid references public.transactions(id),   -- e.g. a transfer fee
  replaces_id           uuid references public.transactions(id),   -- set when an edit reposts
  source                public.txn_source not null default 'app',
  quick_entry_token_id  uuid references public.quick_entry_tokens(id),
  idempotency_key       text check (length(idempotency_key) <= 80),
  created_by            uuid not null references auth.users(id),
  created_at            timestamptz not null default now(),
  voided_at             timestamptz,
  voided_by             uuid references auth.users(id),
  unique (id, household_id),
  unique (household_id, created_by, idempotency_key),
  foreign key (category_id, household_id)        references public.categories(id, household_id),
  foreign key (bill_occurrence_id, household_id) references public.bill_occurrences(id, household_id),
  foreign key (goal_id, household_id)            references public.savings_goals(id, household_id),
  constraint void_fields check ((status = 'void') = (voided_at is not null))
);
create index on public.transactions (household_id, occurred_on desc);
create index on public.transactions (bill_occurrence_id) where bill_occurrence_id is not null;
create index on public.transactions (quick_entry_token_id, created_at) where quick_entry_token_id is not null;

create table public.ledger_entries (
  id              uuid primary key default gen_random_uuid(),
  transaction_id  uuid not null,
  household_id    uuid not null,
  account_id      uuid not null,
  amount          bigint not null check (amount <> 0),
  foreign key (transaction_id, household_id) references public.transactions(id, household_id) on delete cascade,
  foreign key (account_id, household_id)     references public.accounts(id, household_id)
);
create index on public.ledger_entries (account_id);
create index on public.ledger_entries (transaction_id);

create table public.audit_log (
  id            bigint generated always as identity primary key,
  household_id  uuid not null,
  actor         uuid,
  action        text not null,
  entity        text not null,
  entity_id     uuid,
  before        jsonb,
  after         jsonb,
  at            timestamptz not null default now()
);
create index on public.audit_log (household_id, at desc);

-- ---------------------------------------------------------------------
-- 6a. Private helpers (membership, visibility)
-- ---------------------------------------------------------------------
create function kaban_private.role_in(p_household uuid, p_user uuid default auth.uid())
returns public.household_role language sql stable security definer set search_path = '' as $$
  select role from public.household_members where household_id = p_household and user_id = p_user
$$;

create function kaban_private.is_member(p_household uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select kaban_private.role_in(p_household) is not null
$$;

create function kaban_private.can_write(p_household uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select kaban_private.role_in(p_household, p_user) in ('owner', 'admin', 'member')
$$;

create function kaban_private.is_admin(p_household uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select kaban_private.role_in(p_household) in ('owner', 'admin')
$$;

-- Shared rows are visible to every member; personal rows only to their owner.
create function kaban_private.can_see(p_household uuid, p_owner uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select kaban_private.role_in(p_household, p_user) is not null
     and (p_owner is null or p_owner = p_user)
$$;

create function kaban_private.can_see_account(p_account uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.accounts a
    where a.id = p_account and kaban_private.can_see(a.household_id, a.owner_user_id, p_user)
  )
$$;

create function kaban_private.household_today(p_household uuid)
returns date language sql stable security definer set search_path = '' as $$
  select (now() at time zone h.timezone)::date from public.households h where h.id = p_household
$$;

-- ---------------------------------------------------------------------
-- 6b. Ledger integrity: one validator, run as a DEFERRED constraint
--     trigger so it sees the whole transaction (header + all entries)
--     at COMMIT, no matter which code path wrote it.
-- ---------------------------------------------------------------------
create function kaban_private.validate_transaction(p_txn uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  t        public.transactions%rowtype;
  n        int;
  s        bigint;
  n_acct   int;
  n_liab   int;
  cat_kind public.category_kind;
  goal     public.savings_goals%rowtype;
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

  -- fields that only belong to one type
  if t.bill_occurrence_id is not null and t.type <> 'bill_payment' then
    raise exception 'KABAN: only bill_payment may reference a bill' using errcode = 'check_violation';
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

create function kaban_private.trg_validate_from_entry()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then perform kaban_private.validate_transaction(old.transaction_id); end if;
  if tg_op in ('INSERT', 'UPDATE') then perform kaban_private.validate_transaction(new.transaction_id); end if;
  return null;
end $$;

create function kaban_private.trg_validate_from_txn()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform kaban_private.validate_transaction(new.id);
  return null;
end $$;

create constraint trigger ledger_entries_validate
  after insert or update or delete on public.ledger_entries
  deferrable initially deferred for each row execute function kaban_private.trg_validate_from_entry();

create constraint trigger transactions_validate
  after insert or update on public.transactions
  deferrable initially deferred for each row execute function kaban_private.trg_validate_from_txn();

-- Entries are append-only; corrections go through void / edit.
create function kaban_private.trg_entries_immutable()
returns trigger language plpgsql as $$
begin
  raise exception 'KABAN: ledger entries are immutable; void or edit the transaction instead'
    using errcode = 'insufficient_privilege';
end $$;
create trigger ledger_entries_no_update before update on public.ledger_entries
  for each row execute function kaban_private.trg_entries_immutable();

-- ---------------------------------------------------------------------
-- 6c. Earmark guards: the "reserved once" rule
-- ---------------------------------------------------------------------
create function kaban_private.trg_earmark_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
declare acc public.accounts%rowtype; g public.savings_goals%rowtype;
begin
  select * into acc from public.accounts where id = new.account_id;
  select * into g   from public.savings_goals where id = new.goal_id;
  if not acc.is_spendable then
    raise exception 'KABAN: earmarks only apply to spendable accounts (% is already outside the pool)', acc.name
      using errcode = 'check_violation';
  end if;
  if g.mode <> 'earmark' then
    raise exception 'KABAN: goal "%" is funded by its own account; move money with a savings_contribution', g.name
      using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger goal_earmarks_guard before insert or update on public.goal_earmarks
  for each row execute function kaban_private.trg_earmark_guard();

create function kaban_private.trg_account_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.is_spendable and not new.is_spendable
     and exists (select 1 from public.goal_earmarks where account_id = new.id) then
    raise exception 'KABAN: release this account''s earmarks before marking it non-spendable'
      using errcode = 'check_violation';
  end if;
  if new.is_spendable and exists (select 1 from public.savings_goals where linked_account_id = new.id) then
    raise exception 'KABAN: an account dedicated to a savings goal cannot be spendable'
      using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger accounts_guard before update on public.accounts
  for each row execute function kaban_private.trg_account_guard();

create function kaban_private.trg_goal_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.mode = 'account' and exists (
       select 1 from public.accounts where id = new.linked_account_id and is_spendable) then
    raise exception 'KABAN: a goal''s dedicated account must be non-spendable' using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger savings_goals_guard before insert or update on public.savings_goals
  for each row execute function kaban_private.trg_goal_guard();

-- A member who leaves loses every quick-entry token immediately.
create function kaban_private.trg_revoke_tokens_on_leave()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.quick_entry_tokens set revoked_at = now()
   where household_id = old.household_id and user_id = old.user_id and revoked_at is null;
  return old;
end $$;
create trigger household_members_revoke_tokens after delete on public.household_members
  for each row execute function kaban_private.trg_revoke_tokens_on_leave();

-- ---------------------------------------------------------------------
-- 7. Derived views (security_invoker: RLS of the caller applies)
-- ---------------------------------------------------------------------
create view public.account_balances with (security_invoker = true) as
select a.id as account_id, a.household_id, a.owner_user_id, a.name, a.kind, a.class, a.is_spendable,
       coalesce(sum(e.amount) filter (where t.status = 'posted'), 0)::bigint as balance
  from public.accounts a
  left join public.ledger_entries e on e.account_id = a.id
  left join public.transactions  t on t.id = e.transaction_id
 group by a.id;

create view public.bill_occurrence_status with (security_invoker = true) as
select o.id, o.household_id, o.bill_id, b.name, b.owner_user_id, b.pay_from_account_id,
       o.due_on, o.amount_due, o.is_skipped,
       coalesce(-sum(e.amount) filter (where t.status = 'posted'), 0)::bigint as paid,
       case when o.is_skipped then 0
            else greatest(o.amount_due + coalesce(sum(e.amount) filter (where t.status = 'posted'), 0), 0)
       end::bigint as remaining
  from public.bill_occurrences o
  join public.bills b on b.id = o.bill_id
  left join public.transactions  t on t.bill_occurrence_id = o.id and t.type = 'bill_payment'
  left join public.ledger_entries e on e.transaction_id = t.id
 group by o.id, b.id;

-- Personal vs shared is derived from the accounts a transaction touches.
create view public.transaction_list with (security_invoker = true) as
select t.*,
       case when bool_or(a.owner_user_id is null) then 'shared' else 'personal' end as scope,
       sum(e.amount)::bigint as net_amount
  from public.transactions t
  join public.ledger_entries e on e.transaction_id = t.id
  join public.accounts a on a.id = e.account_id
 group by t.id;

create view public.goal_progress with (security_invoker = true) as
select g.id as goal_id, g.household_id, g.owner_user_id, g.name, g.mode, g.target_amount,
       case g.mode
         when 'account' then coalesce((select balance from public.account_balances b
                                        where b.account_id = g.linked_account_id), 0)
         else coalesce((select sum(amount) from public.goal_earmarks m where m.goal_id = g.id), 0)
       end::bigint as saved
  from public.savings_goals g
 where not g.is_archived;

-- ---------------------------------------------------------------------
-- 8. Write API (SECURITY DEFINER, permission-checked)
-- ---------------------------------------------------------------------

-- Core poster shared by the app RPC and quick entry. Not exposed.
create function kaban_private.post_transaction_as(
  p_actor            uuid,
  p_household        uuid,
  p_type             public.txn_type,
  p_occurred_on      date,
  p_entries          jsonb,               -- [{"account_id": "...", "amount": -250000}, ...]
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
begin
  if not kaban_private.can_write(p_household, p_actor) then
    raise exception 'KABAN: not allowed to write in this household' using errcode = 'insufficient_privilege';
  end if;

  -- idempotency: a retried request returns the original transaction
  if p_idempotency_key is not null then
    select id into v_id from public.transactions
     where household_id = p_household and created_by = p_actor and idempotency_key = p_idempotency_key;
    if found then return v_id; end if;
  end if;

  if jsonb_typeof(p_entries) <> 'array' or jsonb_array_length(p_entries) = 0 then
    raise exception 'KABAN: entries must be a non-empty array' using errcode = 'invalid_parameter_value';
  end if;

  -- every account must be visible to the actor and active
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

  if p_type = 'bill_payment' then
    -- category comes from the bill; payment may not exceed what is still due
    select b.category_id into v_cat
      from public.bill_occurrences o join public.bills b on b.id = o.bill_id
     where o.id = p_bill_occurrence and o.household_id = p_household
       and kaban_private.can_see(b.household_id, b.owner_user_id, p_actor);
    if not found then raise exception 'KABAN: bill not available' using errcode = 'insufficient_privilege'; end if;
    perform 1 from public.bill_occurrences where id = p_bill_occurrence for update;   -- serialise payments
    select remaining into v_remain from public.bill_occurrence_status where id = p_bill_occurrence;
    if -(select sum((x->>'amount')::bigint) from jsonb_array_elements(p_entries) x) > v_remain then
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

  -- validate now, inside this call, so the caller gets the error immediately
  perform kaban_private.validate_transaction(v_id);
  return v_id;
end $$;

-- App-facing RPC: the actor is always the signed-in user.
create function public.post_transaction(
  p_household uuid, p_type public.txn_type, p_occurred_on date, p_entries jsonb,
  p_category_id uuid default null, p_description text default null,
  p_bill_occurrence uuid default null, p_goal_id uuid default null,
  p_parent_id uuid default null, p_idempotency_key text default null
) returns uuid language sql security definer set search_path = '' as $$
  select kaban_private.post_transaction_as(auth.uid(), p_household, p_type, p_occurred_on, p_entries,
           p_category_id, p_description, p_bill_occurrence, p_goal_id, p_parent_id, p_idempotency_key, 'app');
$$;

create function public.void_transaction(p_txn uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare t public.transactions%rowtype;
begin
  select * into t from public.transactions where id = p_txn for update;
  if not found or not kaban_private.can_write(t.household_id)
     or (t.created_by <> auth.uid() and not kaban_private.is_admin(t.household_id))
     or exists (select 1 from public.ledger_entries e where e.transaction_id = p_txn
                 and not kaban_private.can_see_account(e.account_id)) then
    raise exception 'KABAN: not allowed to void this transaction' using errcode = 'insufficient_privilege';
  end if;
  if t.status = 'void' then return; end if;
  update public.transactions set status = 'void', voided_at = now(), voided_by = auth.uid() where id = p_txn;
  insert into public.audit_log (household_id, actor, action, entity, entity_id, before, after)
  values (t.household_id, auth.uid(), 'void', 'transaction', p_txn, to_jsonb(t),
          jsonb_build_object('reason', p_reason));
end $$;

-- Edit = void the old version + post a corrected one that points back to it.
create function public.edit_transaction(
  p_txn uuid, p_occurred_on date, p_entries jsonb,
  p_category_id uuid default null, p_description text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare t public.transactions%rowtype; v_new uuid;
begin
  select * into t from public.transactions where id = p_txn;
  perform public.void_transaction(p_txn, 'edited');
  v_new := kaban_private.post_transaction_as(auth.uid(), t.household_id, t.type, p_occurred_on, p_entries,
             coalesce(p_category_id, t.category_id), coalesce(p_description, t.description),
             t.bill_occurrence_id, t.goal_id, t.parent_id, null, 'app', null, p_txn);
  return v_new;
end $$;

-- Set (or release with 0) the amount earmarked for a goal in one spendable account.
create function public.set_earmark(p_goal uuid, p_account uuid, p_amount bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare g public.savings_goals%rowtype; v_bal bigint; v_other bigint;
begin
  select * into g from public.savings_goals where id = p_goal;
  if not found or not kaban_private.can_write(g.household_id)
     or not kaban_private.can_see(g.household_id, g.owner_user_id)
     or not kaban_private.can_see_account(p_account) then
    raise exception 'KABAN: not allowed' using errcode = 'insufficient_privilege';
  end if;
  if p_amount < 0 then raise exception 'KABAN: amount must be >= 0' using errcode = 'check_violation'; end if;

  perform 1 from public.accounts where id = p_account for update;   -- serialise earmark changes per account
  select balance into v_bal from public.account_balances where account_id = p_account;
  select coalesce(sum(amount), 0) into v_other from public.goal_earmarks
   where account_id = p_account and goal_id <> p_goal;
  if v_other + p_amount > v_bal then
    raise exception 'KABAN: earmarks (%) would exceed the account balance (%)', v_other + p_amount, v_bal
      using errcode = 'check_violation';
  end if;

  if p_amount = 0 then
    delete from public.goal_earmarks where goal_id = p_goal and account_id = p_account;
  else
    insert into public.goal_earmarks (goal_id, account_id, household_id, amount)
    values (p_goal, p_account, g.household_id, p_amount)
    on conflict (goal_id, account_id) do update set amount = excluded.amount, updated_at = now();
  end if;
end $$;

-- Create the due-date rows for recurring bills up to p_until (run daily by pg_cron).
create function public.generate_bill_occurrences(p_until date)
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

-- ---------------------------------------------------------------------
-- 9. Available to spend
-- ---------------------------------------------------------------------
-- p_scope: 'shared' (household pool), 'personal' (caller's own), 'all' (both)
create function public.available_to_spend(p_household uuid, p_scope text default 'shared')
returns table (
  spendable_balance bigint,
  earmarked         bigint,
  bills_reserved    bigint,
  available         bigint,
  horizon           date,
  over_earmarked    boolean
) language plpgsql stable security definer set search_path = '' as $$
declare
  h       public.households%rowtype;
  v_today date;
  v_eom   date;
begin
  if not kaban_private.is_member(p_household) then
    raise exception 'KABAN: not a member' using errcode = 'insufficient_privilege';
  end if;
  if p_scope not in ('shared', 'personal', 'all') then
    raise exception 'KABAN: scope must be shared, personal or all' using errcode = 'invalid_parameter_value';
  end if;

  select * into h from public.households where id = p_household;
  v_today := kaban_private.household_today(p_household);
  v_eom   := (date_trunc('month', v_today) + interval '1 month - 1 day')::date;
  horizon := case h.reserve_horizon
               when 'month_end'   then v_eom
               when 'next_payday' then coalesce(h.next_payday, v_eom)
               else v_today + h.reserve_days
             end;

  return query
  with pool as (                       -- rule 1: spendable asset accounts in scope only
    select b.account_id, b.balance
      from public.account_balances b
      join public.accounts a on a.id = b.account_id
     where a.household_id = p_household and a.is_spendable and a.class = 'asset' and not a.is_archived
       and ((p_scope in ('shared', 'all')   and a.owner_user_id is null) or
            (p_scope in ('personal', 'all') and a.owner_user_id = auth.uid()))
  ),
  marks as (                           -- rules 2-3: earmarks only on pool accounts, capped at balance
    select p.account_id, p.balance,
           coalesce((select sum(m.amount) from public.goal_earmarks m where m.account_id = p.account_id), 0) as raw
      from pool p
  ),
  bills as (                           -- rules 4-6: unpaid remainder, due by horizon, paid from the pool
    select coalesce(sum(s.remaining), 0) as reserved
      from public.bill_occurrence_status s
      left join public.accounts pa on pa.id = s.pay_from_account_id
     where s.household_id = p_household
       and s.due_on <= horizon
       and s.remaining > 0
       and (pa.id is null or pa.is_spendable)
       and ((p_scope in ('shared', 'all')   and s.owner_user_id is null) or
            (p_scope in ('personal', 'all') and s.owner_user_id = auth.uid()))
  )
  select coalesce((select sum(balance) from pool), 0)::bigint,
         coalesce((select sum(least(raw, greatest(balance, 0))) from marks), 0)::bigint,
         (select reserved from bills)::bigint,
         (coalesce((select sum(balance) from pool), 0)
          - coalesce((select sum(least(raw, greatest(balance, 0))) from marks), 0)
          - (select reserved from bills))::bigint,
         horizon,
         coalesce((select bool_or(raw > balance) from marks), false);
end $$;

-- Income vs expense for a month. Transfers, savings moves, openings and adjustments never count.
create function public.monthly_summary(p_household uuid, p_month date)
returns table (income bigint, expense bigint, net bigint)
language sql stable security invoker set search_path = '' as $$
  with m as (
    select t.type, e.amount
      from public.transactions t join public.ledger_entries e on e.transaction_id = t.id
     where t.household_id = p_household and t.status = 'posted'
       and t.occurred_on >= date_trunc('month', p_month)::date
       and t.occurred_on <  (date_trunc('month', p_month) + interval '1 month')::date
  )
  select coalesce(sum(amount) filter (where type = 'income'), 0)::bigint,
         coalesce(-sum(amount) filter (where type in ('expense', 'bill_payment', 'refund')), 0)::bigint,
         (coalesce(sum(amount) filter (where type = 'income'), 0)
          + coalesce(sum(amount) filter (where type in ('expense', 'bill_payment', 'refund')), 0))::bigint
    from m;
$$;

-- ---------------------------------------------------------------------
-- 10. Quick entry (Back Tap / Shortcuts)
-- ---------------------------------------------------------------------
-- Created inside the signed-in app. Returns the plaintext token ONCE;
-- only its sha256 is stored.
create function public.create_quick_entry_token(
  p_household uuid, p_label text, p_default_account uuid,
  p_allowed_types public.txn_type[] default '{expense}',
  p_max_amount bigint default 2000000, p_daily_limit int default 30,
  p_valid_days int default 90
) returns table (token_id uuid, token text, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare v_plain text; v_id uuid; v_exp timestamptz;
begin
  if not kaban_private.can_write(p_household) or not kaban_private.can_see_account(p_default_account) then
    raise exception 'KABAN: not allowed' using errcode = 'insufficient_privilege';
  end if;
  if p_valid_days not between 1 and 365 then
    raise exception 'KABAN: validity must be 1-365 days' using errcode = 'invalid_parameter_value';
  end if;
  if (select count(*) from public.quick_entry_tokens
       where user_id = auth.uid() and revoked_at is null and quick_entry_tokens.expires_at > now()) >= 5 then
    raise exception 'KABAN: at most 5 active quick-entry tokens per user' using errcode = 'check_violation';
  end if;

  v_plain := 'kbn_qe_' || encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.quick_entry_tokens (household_id, user_id, label, token_prefix, token_hash,
                                         allowed_types, default_account_id, max_amount, daily_limit, expires_at)
  values (p_household, auth.uid(), p_label, left(v_plain, 14),
          extensions.digest(v_plain, 'sha256'), p_allowed_types, p_default_account,
          p_max_amount, p_daily_limit, now() + make_interval(days => p_valid_days))
  returning id, quick_entry_tokens.expires_at into v_id, v_exp;

  return query select v_id, v_plain, v_exp;
end $$;

create function public.revoke_quick_entry_token(p_token_id uuid)
returns void language sql security definer set search_path = '' as $$
  update public.quick_entry_tokens set revoked_at = now()
   where id = p_token_id and revoked_at is null
     and (user_id = auth.uid() or kaban_private.is_admin(household_id));
$$;

-- Resolve a presented token. Private: only the functions below call it.
create function kaban_private.resolve_token(p_token text)
returns public.quick_entry_tokens language plpgsql security definer set search_path = '' as $$
declare k public.quick_entry_tokens%rowtype;
begin
  select * into k from public.quick_entry_tokens
   where token_hash = extensions.digest(p_token, 'sha256') for update;
  if not found or k.revoked_at is not null or k.expires_at <= now()
     or not kaban_private.can_write(k.household_id, k.user_id) then
    raise exception 'KABAN: invalid token' using errcode = 'invalid_authorization_specification';
  end if;
  return k;
end $$;

-- Write-only endpoint body. Called by the quick-entry Edge Function only.
-- Returns no balances or history, so a leaked token reveals nothing.
create function public.quick_entry_submit(
  p_token text, p_amount bigint, p_category_id uuid,
  p_type public.txn_type default 'expense', p_account_id uuid default null,
  p_note text default null, p_idempotency_key text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  k       public.quick_entry_tokens%rowtype;
  v_acct  uuid;
  v_used  int;
  v_id    uuid;
  v_today date;
begin
  k := kaban_private.resolve_token(p_token);

  if not (p_type = any (k.allowed_types)) then
    raise exception 'KABAN: type not allowed for this token' using errcode = 'insufficient_privilege';
  end if;
  if p_amount is null or p_amount <= 0 or p_amount > k.max_amount then
    raise exception 'KABAN: amount must be between 1 and % centavos', k.max_amount using errcode = 'check_violation';
  end if;

  v_acct := coalesce(p_account_id, k.default_account_id);
  if v_acct <> k.default_account_id and not (v_acct = any (k.allowed_account_ids)) then
    raise exception 'KABAN: account not allowed for this token' using errcode = 'insufficient_privilege';
  end if;

  v_today := kaban_private.household_today(k.household_id);
  select count(*) into v_used from public.transactions
   where quick_entry_token_id = k.id and created_at >= (v_today::timestamp at time zone
         (select timezone from public.households where id = k.household_id));
  if v_used >= k.daily_limit then
    raise exception 'KABAN: daily quick-entry limit reached' using errcode = 'check_violation';
  end if;

  v_id := kaban_private.post_transaction_as(
            k.user_id, k.household_id, p_type, v_today,
            jsonb_build_array(jsonb_build_object('account_id', v_acct,
                              'amount', case when p_type = 'income' then p_amount else -p_amount end)),
            p_category_id, left(p_note, 200), null, null, null, p_idempotency_key,
            'quick_entry', k.id);

  update public.quick_entry_tokens set last_used_at = now() where id = k.id;

  return jsonb_build_object('ok', true, 'transaction_id', v_id, 'amount', p_amount,
                            'category', (select name from public.categories where id = p_category_id));
end $$;

-- Names only, for the Shortcut's category picker. No amounts.
create function public.quick_entry_categories(p_token text)
returns table (id uuid, name text, kind public.category_kind)
language plpgsql security definer set search_path = '' as $$
declare k public.quick_entry_tokens%rowtype;
begin
  k := kaban_private.resolve_token(p_token);
  return query
    select c.id, c.name, c.kind from public.categories c
     where c.household_id = k.household_id and not c.is_archived
       and c.kind::text = any (select unnest(k.allowed_types)::text)
       and kaban_private.can_see(c.household_id, c.owner_user_id, k.user_id)
     order by c.name;
end $$;

-- Only the Edge Function (service_role) may call the token endpoints.
revoke execute on function public.quick_entry_submit(text, bigint, uuid, public.txn_type, uuid, text, text)
  from public, anon, authenticated;
revoke execute on function public.quick_entry_categories(text) from public, anon, authenticated;
grant  execute on function public.quick_entry_submit(text, bigint, uuid, public.txn_type, uuid, text, text) to service_role;
grant  execute on function public.quick_entry_categories(text) to service_role;

-- ---------------------------------------------------------------------
-- 11. Row Level Security
-- ---------------------------------------------------------------------
alter table public.households          enable row level security;
alter table public.household_members   enable row level security;
alter table public.accounts            enable row level security;
alter table public.categories          enable row level security;
alter table public.bills               enable row level security;
alter table public.bill_occurrences    enable row level security;
alter table public.savings_goals       enable row level security;
alter table public.goal_earmarks       enable row level security;
alter table public.budgets             enable row level security;
alter table public.transactions        enable row level security;
alter table public.ledger_entries      enable row level security;
alter table public.quick_entry_tokens  enable row level security;
alter table public.audit_log           enable row level security;

-- households
create policy hh_select on public.households for select to authenticated using (kaban_private.is_member(id));
create policy hh_update on public.households for update to authenticated
  using (kaban_private.is_admin(id)) with check (kaban_private.is_admin(id));

-- members: everyone in the household sees the roster; owners/admins manage it
create policy hm_select on public.household_members for select to authenticated
  using (kaban_private.is_member(household_id));
create policy hm_write on public.household_members for all to authenticated
  using (kaban_private.is_admin(household_id)) with check (kaban_private.is_admin(household_id));

-- accounts: shared visible to members, personal only to owner.
-- shared accounts are managed by admins; personal ones by their owner.
create policy acc_select on public.accounts for select to authenticated
  using (kaban_private.can_see(household_id, owner_user_id));
create policy acc_insert on public.accounts for insert to authenticated with check (
  kaban_private.can_write(household_id) and created_by = auth.uid() and
  ((owner_user_id is null and kaban_private.is_admin(household_id)) or owner_user_id = auth.uid()));
create policy acc_update on public.accounts for update to authenticated
  using ((owner_user_id is null and kaban_private.is_admin(household_id)) or owner_user_id = auth.uid())
  with check ((owner_user_id is null and kaban_private.is_admin(household_id)) or owner_user_id = auth.uid());

-- categories, bills, goals, budgets: same shared/personal rule; writers may edit
create policy cat_select on public.categories for select to authenticated
  using (kaban_private.can_see(household_id, owner_user_id));
create policy cat_write on public.categories for all to authenticated
  using (kaban_private.can_write(household_id) and kaban_private.can_see(household_id, owner_user_id))
  with check (kaban_private.can_write(household_id) and (owner_user_id is null or owner_user_id = auth.uid()));

create policy bill_select on public.bills for select to authenticated
  using (kaban_private.can_see(household_id, owner_user_id));
create policy bill_write on public.bills for all to authenticated
  using (kaban_private.can_write(household_id) and kaban_private.can_see(household_id, owner_user_id))
  with check (kaban_private.can_write(household_id) and (owner_user_id is null or owner_user_id = auth.uid())
              and (pay_from_account_id is null or kaban_private.can_see_account(pay_from_account_id)));

create policy occ_select on public.bill_occurrences for select to authenticated
  using (exists (select 1 from public.bills b where b.id = bill_occurrences.bill_id));   -- inherits bills RLS
create policy occ_update on public.bill_occurrences for update to authenticated
  using (kaban_private.can_write(household_id)
         and exists (select 1 from public.bills b where b.id = bill_occurrences.bill_id))
  with check (kaban_private.can_write(household_id));
create policy occ_insert on public.bill_occurrences for insert to authenticated
  with check (kaban_private.can_write(household_id)
              and exists (select 1 from public.bills b where b.id = bill_occurrences.bill_id));

create policy goal_select on public.savings_goals for select to authenticated
  using (kaban_private.can_see(household_id, owner_user_id));
create policy goal_write on public.savings_goals for all to authenticated
  using (kaban_private.can_write(household_id) and kaban_private.can_see(household_id, owner_user_id))
  with check (kaban_private.can_write(household_id) and (owner_user_id is null or owner_user_id = auth.uid())
              and (linked_account_id is null or kaban_private.can_see_account(linked_account_id)));

create policy em_select on public.goal_earmarks for select to authenticated
  using (kaban_private.can_see_account(account_id));                       -- writes via set_earmark()

create policy bud_select on public.budgets for select to authenticated
  using (kaban_private.can_see(household_id, owner_user_id));
create policy bud_write on public.budgets for all to authenticated
  using (kaban_private.can_write(household_id) and kaban_private.can_see(household_id, owner_user_id))
  with check (kaban_private.can_write(household_id) and (owner_user_id is null or owner_user_id = auth.uid()));

-- ledger: read-only through RLS; visibility follows the account.
-- A member sees the shared side of a personal->shared transfer, never the personal account.
create policy le_select on public.ledger_entries for select to authenticated
  using (kaban_private.can_see_account(account_id));
create policy tx_select on public.transactions for select to authenticated
  using (kaban_private.is_member(household_id) and exists (
           select 1 from public.ledger_entries e where e.transaction_id = transactions.id));

-- tokens: owners see their own metadata (never the hash)
create policy qe_select on public.quick_entry_tokens for select to authenticated
  using (user_id = auth.uid() or kaban_private.is_admin(household_id));

create policy audit_select on public.audit_log for select to authenticated
  using (kaban_private.is_admin(household_id));

-- Table privileges: no direct ledger / token / earmark / audit writes from clients.
revoke insert, update, delete on public.transactions, public.ledger_entries,
  public.quick_entry_tokens, public.goal_earmarks, public.audit_log from anon, authenticated;
revoke all on public.quick_entry_tokens from anon, authenticated;
grant select (id, household_id, user_id, label, token_prefix, allowed_types, default_account_id,
              allowed_account_ids, max_amount, daily_limit, expires_at, created_at, last_used_at, revoked_at)
  on public.quick_entry_tokens to authenticated;
revoke all on all tables in schema public from anon;

-- Private helpers are callable by the policies above but not from the API.
grant usage on schema kaban_private to authenticated, service_role;
revoke execute on all functions in schema kaban_private from public, anon;
grant  execute on function kaban_private.role_in(uuid, uuid), kaban_private.is_member(uuid),
  kaban_private.can_write(uuid, uuid), kaban_private.is_admin(uuid),
  kaban_private.can_see(uuid, uuid, uuid), kaban_private.can_see_account(uuid, uuid)
  to authenticated;
