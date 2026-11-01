-- =====================================================================
-- KABAN 0006: fix the "over-earmarked" warning
--
-- over_earmarked was true for any account whose balance was below its
-- earmarks, including accounts with NO earmarks and a negative balance
-- (0 > -500). Now it only flags accounts that actually have money set aside.
-- The available-to-spend number itself was already correct.
-- =====================================================================

create or replace function kaban_private.available_to_spend(p_household uuid, p_scope text default 'shared')
returns table (
  spendable_balance bigint,
  earmarked         bigint,
  bills_reserved    bigint,
  card_debt         bigint,
  available         bigint,
  horizon           date,
  over_earmarked    boolean
) language plpgsql stable security definer set search_path = '' as $$
declare
  h       public.households%rowtype;
  v_today date;
  v_eom   date;
  v_full  boolean;
begin
  if not kaban_private.is_member(p_household) then
    raise exception 'KABAN: not a member' using errcode = 'insufficient_privilege';
  end if;
  if p_scope not in ('shared', 'personal', 'all') then
    raise exception 'KABAN: scope must be shared, personal or all' using errcode = 'invalid_parameter_value';
  end if;

  select * into h from public.households where id = p_household;
  v_full  := h.card_debt_mode = 'full';
  v_today := kaban_private.household_today(p_household);
  v_eom   := (date_trunc('month', v_today) + interval '1 month - 1 day')::date;
  horizon := case h.reserve_horizon
               when 'month_end'   then v_eom
               when 'next_payday' then coalesce(h.next_payday, v_eom)
               else v_today + h.reserve_days
             end;

  return query
  with scoped as (
    select a.* from public.accounts a
     where a.household_id = p_household and not a.is_archived
       and ((p_scope in ('shared', 'all')   and a.owner_user_id is null) or
            (p_scope in ('personal', 'all') and a.owner_user_id = auth.uid()))
  ),
  pool as (                            -- spendable asset accounts only
    select b.account_id, b.balance
      from public.account_balances b join scoped a on a.id = b.account_id
     where a.is_spendable and a.class = 'asset'
  ),
  marks as (                           -- earmarks on pool accounts, capped at balance
    select p.account_id, p.balance,
           coalesce((select sum(m.amount) from public.goal_earmarks m where m.account_id = p.account_id), 0) as raw
      from pool p
  ),
  cards as (                           -- 'full' mode: everything owed on cards/loans now
    select coalesce(sum(greatest(-b.balance, 0)), 0) as debt
      from public.account_balances b join scoped a on a.id = b.account_id
     where v_full and a.class = 'liability'
  ),
  bills as (                           -- unpaid remainder, due by horizon, paid from the pool
    select coalesce(sum(s.remaining), 0) as reserved
      from public.bill_occurrence_status s
      join public.bills bl on bl.id = s.bill_id
      left join public.accounts pa on pa.id = s.pay_from_account_id
     where s.household_id = p_household
       and s.due_on <= horizon
       and s.remaining > 0
       and (pa.id is null or pa.is_spendable)
       and not (v_full and bl.settles_account_id is not null)   -- card debt already counted above
       and ((p_scope in ('shared', 'all')   and s.owner_user_id is null) or
            (p_scope in ('personal', 'all') and s.owner_user_id = auth.uid()))
  )
  select coalesce((select sum(balance) from pool), 0)::bigint,
         coalesce((select sum(least(raw, greatest(balance, 0))) from marks), 0)::bigint,
         (select reserved from bills)::bigint,
         (select debt from cards)::bigint,
         (coalesce((select sum(balance) from pool), 0)
          - coalesce((select sum(least(raw, greatest(balance, 0))) from marks), 0)
          - (select reserved from bills)
          - (select debt from cards))::bigint,
         horizon,
         coalesce((select bool_or(raw > 0 and raw > balance) from marks), false);   -- only accounts that HAVE earmarks
end $$;
