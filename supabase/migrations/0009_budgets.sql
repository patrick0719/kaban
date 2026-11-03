-- =====================================================================
-- KABAN 0009: monthly budgets with suggestions
--
-- A budget is set per expense category and carries forward: the most
-- recent amount set on or before a month applies to it. 0 = no budget.
--
-- Spending in a category = expenses + bill payments - refunds (posted).
-- Transfers, card payments, savings moves and corrections never count.
--
-- Suggestion = average monthly spending in the category over the last
-- 3 full months that have any spending, rounded up to the next 100 pesos.
-- =====================================================================

create function public.budget_status(p_household uuid, p_month date)
returns table (
  category_id       uuid,
  category          text,
  budget            bigint,   -- null = no budget
  spent             bigint,   -- this month so far
  avg_spent         bigint,   -- per month over the history window; null = no history
  months_of_history int,
  suggested         bigint    -- null = not enough history
)
language sql stable security invoker set search_path = '' as $$
  with m as (
    select date_trunc('month', p_month)::date as start,
           (date_trunc('month', p_month) + interval '1 month')::date as next
  ),
  spend as (
    select t.category_id, date_trunc('month', t.occurred_on)::date as mon, -sum(e.amount) as amt
      from public.transactions t
      join public.ledger_entries e on e.transaction_id = t.id
     where t.household_id = p_household and t.status = 'posted'
       and t.type in ('expense', 'bill_payment', 'refund')
       and t.occurred_on >= (select start from m) - interval '3 months'
       and t.occurred_on <  (select next from m)
     group by 1, 2
  ),
  history_months as (select count(distinct mon)::int as n from spend where mon < (select start from m)),
  history as (select category_id, sum(amt) as total from spend where mon < (select start from m) group by 1),
  this_month as (select category_id, sum(amt) as amt from spend where mon = (select start from m) group by 1),
  latest_budget as (
    select distinct on (b.category_id) b.category_id, b.amount
      from public.budgets b
     where b.household_id = p_household and b.owner_user_id is null and b.month <= (select start from m)
     order by b.category_id, b.month desc
  )
  select c.id, c.name,
         nullif(lb.amount, 0)::bigint,
         coalesce(tm.amt, 0)::bigint,
         case when hm.n > 0 then round(coalesce(h.total, 0)::numeric / hm.n)::bigint end,
         hm.n,
         case when hm.n > 0 and coalesce(h.total, 0) > 0
              then (ceil(h.total::numeric / hm.n / 10000) * 10000)::bigint end
    from public.categories c
   cross join history_months hm
    left join this_month tm   on tm.category_id = c.id
    left join history h       on h.category_id = c.id
    left join latest_budget lb on lb.category_id = c.id
   where c.household_id = p_household and c.kind = 'expense' and not c.is_archived
     and c.owner_user_id is null
   order by c.name;
$$;

create function kaban_private.set_budget(p_household uuid, p_category uuid, p_amount bigint, p_month date default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_month date;
begin
  if not kaban_private.can_write(p_household) then
    raise exception 'KABAN: not allowed to write in this household' using errcode = 'insufficient_privilege';
  end if;
  if p_amount is null or p_amount < 0 then
    raise exception 'KABAN: budget must be zero or more' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.categories c where c.id = p_category and c.household_id = p_household
                    and c.kind = 'expense' and c.owner_user_id is null and not c.is_archived) then
    raise exception 'KABAN: category not available' using errcode = 'insufficient_privilege';
  end if;
  v_month := date_trunc('month', coalesce(p_month, kaban_private.household_today(p_household)))::date;
  insert into public.budgets (household_id, owner_user_id, category_id, month, amount)
  values (p_household, null, p_category, v_month, p_amount)
  on conflict (household_id, owner_user_id, category_id, month) do update set amount = excluded.amount;
end $$;

-- Several at once, e.g. "Use these suggestions": [{"category_id": "...", "amount": 400000}, ...]
create function kaban_private.set_budgets(p_household uuid, p_items jsonb)
returns int language plpgsql security definer set search_path = '' as $$
declare x jsonb; n int := 0;
begin
  if jsonb_typeof(p_items) <> 'array' then
    raise exception 'KABAN: items must be a list' using errcode = 'invalid_parameter_value';
  end if;
  for x in select * from jsonb_array_elements(p_items) loop
    perform kaban_private.set_budget(p_household, (x->>'category_id')::uuid, (x->>'amount')::bigint);
    n := n + 1;
  end loop;
  return n;
end $$;

create function public.set_budget(p_household uuid, p_category uuid, p_amount bigint, p_month date default null)
returns void language sql security invoker set search_path = '' as $$
  select kaban_private.set_budget(p_household, p_category, p_amount, p_month)
$$;
create function public.set_budgets(p_household uuid, p_items jsonb)
returns int language sql security invoker set search_path = '' as $$
  select kaban_private.set_budgets(p_household, p_items)
$$;

revoke execute on function
  public.budget_status(uuid, date),
  kaban_private.set_budget(uuid, uuid, bigint, date), kaban_private.set_budgets(uuid, jsonb),
  public.set_budget(uuid, uuid, bigint, date), public.set_budgets(uuid, jsonb)
from public, anon;
grant execute on function
  public.budget_status(uuid, date),
  kaban_private.set_budget(uuid, uuid, bigint, date), kaban_private.set_budgets(uuid, jsonb),
  public.set_budget(uuid, uuid, bigint, date), public.set_budgets(uuid, jsonb)
to authenticated;
