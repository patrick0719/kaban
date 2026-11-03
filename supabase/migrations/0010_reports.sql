-- =====================================================================
-- KABAN 0010: reports
--
-- Spending = expenses + bill payments - refunds (same rule as budgets).
-- Income   = income transactions.
-- Saved    = money moved into goal savings accounts (savings contributions).
-- Transfers, card payments, openings and corrections never count.
-- Both functions run as the caller, so Row Level Security decides what
-- each person sees (shared money, plus their own personal accounts).
-- =====================================================================

-- Spending per category this month and last month.
create function public.report_categories(p_household uuid, p_month date)
returns table (category_id uuid, category text, spent bigint, prev_spent bigint)
language sql stable security invoker set search_path = '' as $$
  with m as (
    select date_trunc('month', p_month)::date as s,
           (date_trunc('month', p_month) + interval '1 month')::date as n,
           (date_trunc('month', p_month) - interval '1 month')::date as p
  ),
  x as (
    select t.category_id,
           sum(-e.amount) filter (where t.occurred_on >= (select s from m)) as cur,
           sum(-e.amount) filter (where t.occurred_on <  (select s from m)) as prev
      from public.transactions t
      join public.ledger_entries e on e.transaction_id = t.id
     where t.household_id = p_household and t.status = 'posted'
       and t.type in ('expense', 'bill_payment', 'refund')
       and t.occurred_on >= (select p from m) and t.occurred_on < (select n from m)
     group by 1
  )
  select c.id, c.name, coalesce(x.cur, 0)::bigint, coalesce(x.prev, 0)::bigint
    from x join public.categories c on c.id = x.category_id
   where coalesce(x.cur, 0) <> 0 or coalesce(x.prev, 0) <> 0
   order by 3 desc, 4 desc, 2;
$$;

-- Income, spending and savings for each of the last p_months months, ending at p_month.
create function public.report_trend(p_household uuid, p_month date, p_months int default 6)
returns table (month date, income bigint, spent bigint, saved bigint)
language sql stable security invoker set search_path = '' as $$
  with months as (
    select (date_trunc('month', p_month) - make_interval(months => k))::date as mon
      from generate_series(0, least(greatest(coalesce(p_months, 6), 1), 24) - 1) k
  ),
  x as (
    select date_trunc('month', t.occurred_on)::date as mon, t.type, e.amount
      from public.transactions t
      join public.ledger_entries e on e.transaction_id = t.id
     where t.household_id = p_household and t.status = 'posted'
       and t.type in ('income', 'expense', 'bill_payment', 'refund', 'savings_contribution')
       and t.occurred_on >= (select min(mon) from months)
       and t.occurred_on <  (date_trunc('month', p_month) + interval '1 month')::date
  )
  select m.mon,
         coalesce(sum(x.amount) filter (where x.type = 'income'), 0)::bigint,
         coalesce(-sum(x.amount) filter (where x.type in ('expense', 'bill_payment', 'refund')), 0)::bigint,
         coalesce(sum(x.amount) filter (where x.type = 'savings_contribution' and x.amount > 0), 0)::bigint
    from months m left join x on x.mon = m.mon
   group by m.mon
   order by m.mon;
$$;

revoke execute on function public.report_categories(uuid, date), public.report_trend(uuid, date, int) from public, anon;
grant  execute on function public.report_categories(uuid, date), public.report_trend(uuid, date, int) to authenticated;
