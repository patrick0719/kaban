-- =====================================================================
-- KABAN 0008: savings goals you can manage from the app
--
-- Two ways to save, both kept out of "Safe to spend" exactly once:
--   account  - the goal has its own non-spendable savings account
--              (e.g. GoTyme Savings). Adding money is a savings_contribution
--              transfer into it; taking money out is a transfer back.
--   earmark  - the money stays in a spending account (e.g. GCash) but is
--              set aside. Adding/taking changes the earmark only.
-- =====================================================================

-- goal_progress also exposes the target date and the goal's account
create or replace view public.goal_progress with (security_invoker = true) as
select g.id as goal_id, g.household_id, g.owner_user_id, g.name, g.mode, g.target_amount,
       case g.mode
         when 'account' then coalesce((select balance from public.account_balances b
                                        where b.account_id = g.linked_account_id), 0)
         else coalesce((select sum(amount) from public.goal_earmarks m where m.goal_id = g.id), 0)
       end::bigint as saved,
       g.target_date, g.linked_account_id
  from public.savings_goals g
 where not g.is_archived;

create function kaban_private.save_goal(
  p_household        uuid,
  p_goal             uuid,          -- null = new goal
  p_name             text,
  p_target           bigint,
  p_target_date      date default null,
  p_mode             public.goal_mode default 'earmark',
  p_account          uuid default null,   -- account mode: an existing savings account
  p_new_account_name text default null,   -- account mode: or create one with this name
  p_personal         boolean default false
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id    uuid := p_goal;
  v_acct  uuid := p_account;
  v_owner uuid := case when p_personal then auth.uid() end;
  g       public.savings_goals%rowtype;
begin
  if not kaban_private.can_write(p_household) then
    raise exception 'KABAN: not allowed to write in this household' using errcode = 'insufficient_privilege';
  end if;
  if length(btrim(coalesce(p_name, ''))) not between 1 and 60 then
    raise exception 'KABAN: goal name must be 1-60 characters' using errcode = 'check_violation';
  end if;
  if p_target is null or p_target <= 0 then
    raise exception 'KABAN: goal target must be more than zero' using errcode = 'check_violation';
  end if;
  if p_target_date is not null and p_target_date < kaban_private.household_today(p_household) then
    raise exception 'KABAN: target date must be today or later' using errcode = 'check_violation';
  end if;

  if v_id is not null then
    -- editing: name, target and date only; where the money lives does not change
    select * into g from public.savings_goals where id = v_id and household_id = p_household for update;
    if not found or not kaban_private.can_see(g.household_id, g.owner_user_id) then
      raise exception 'KABAN: goal not available' using errcode = 'insufficient_privilege';
    end if;
    update public.savings_goals
       set name = btrim(p_name), target_amount = p_target, target_date = p_target_date
     where id = v_id;
    return v_id;
  end if;

  if p_mode = 'account' then
    if v_acct is null then
      if length(btrim(coalesce(p_new_account_name, ''))) not between 1 and 60 then
        raise exception 'KABAN: name the new savings account' using errcode = 'check_violation';
      end if;
      insert into public.accounts (household_id, owner_user_id, name, kind, class, is_spendable, display_order, created_by)
      values (p_household, v_owner, btrim(p_new_account_name), 'savings', 'asset', false, 100, auth.uid())
      returning id into v_acct;
    elsif not exists (select 1 from public.accounts a
                       where a.id = v_acct and a.household_id = p_household and not a.is_archived
                         and a.class = 'asset' and not a.is_spendable
                         and kaban_private.can_see(a.household_id, a.owner_user_id)) then
      raise exception 'KABAN: choose a savings account that is not used for spending' using errcode = 'check_violation';
    elsif exists (select 1 from public.savings_goals where linked_account_id = v_acct and not is_archived) then
      raise exception 'KABAN: that savings account already belongs to another goal' using errcode = 'check_violation';
    end if;
    -- an archived goal may still hold the link; free it for the new goal
    update public.savings_goals set linked_account_id = null, mode = 'earmark'
     where linked_account_id = v_acct and is_archived;
  else
    v_acct := null;
  end if;

  insert into public.savings_goals (household_id, owner_user_id, name, target_amount, target_date, mode, linked_account_id)
  values (p_household, v_owner, btrim(p_name), p_target, p_target_date, p_mode, v_acct)
  returning id into v_id;
  return v_id;
end $$;

-- Put money toward a goal.
--   account mode: moves p_amount from p_account into the goal's savings account
--   earmark mode: sets aside p_amount more inside p_account (a spending account)
create function kaban_private.add_to_goal(
  p_goal uuid, p_account uuid, p_amount bigint, p_date date default null, p_key text default null
) returns void language plpgsql security definer set search_path = '' as $$
declare g public.savings_goals%rowtype; v_now bigint;
begin
  select * into g from public.savings_goals where id = p_goal and not is_archived;
  if not found or not kaban_private.can_write(g.household_id) or not kaban_private.can_see(g.household_id, g.owner_user_id) then
    raise exception 'KABAN: goal not available' using errcode = 'insufficient_privilege';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'KABAN: amount must be more than zero' using errcode = 'check_violation';
  end if;

  if g.mode = 'account' then
    if p_account = g.linked_account_id then
      raise exception 'KABAN: choose the account the money comes from' using errcode = 'check_violation';
    end if;
    if not exists (select 1 from public.accounts where id = p_account and class = 'asset') then
      raise exception 'KABAN: money can only come from cash, a bank or an e-wallet' using errcode = 'check_violation';
    end if;
    perform kaban_private.post_transaction_as(
      auth.uid(), g.household_id, 'savings_contribution',
      coalesce(p_date, kaban_private.household_today(g.household_id)),
      jsonb_build_array(jsonb_build_object('account_id', p_account, 'amount', -p_amount),
                        jsonb_build_object('account_id', g.linked_account_id, 'amount', p_amount)),
      null, g.name, null, p_goal, null, p_key);
  else
    if not exists (select 1 from public.accounts where id = p_account and is_spendable) then
      raise exception 'KABAN: set money aside in a spending account (cash, bank or e-wallet)' using errcode = 'check_violation';
    end if;
    select coalesce(sum(amount), 0) into v_now from public.goal_earmarks where goal_id = p_goal and account_id = p_account;
    perform kaban_private.set_earmark(p_goal, p_account, v_now + p_amount);
  end if;
end $$;

-- Take money out of a goal.
--   account mode: moves p_amount from the goal's savings account to p_account
--   earmark mode: releases p_amount of what was set aside in p_account
create function kaban_private.take_from_goal(
  p_goal uuid, p_account uuid, p_amount bigint, p_date date default null, p_key text default null
) returns void language plpgsql security definer set search_path = '' as $$
declare g public.savings_goals%rowtype; v_now bigint; v_bal bigint;
begin
  select * into g from public.savings_goals where id = p_goal and not is_archived;
  if not found or not kaban_private.can_write(g.household_id) or not kaban_private.can_see(g.household_id, g.owner_user_id) then
    raise exception 'KABAN: goal not available' using errcode = 'insufficient_privilege';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'KABAN: amount must be more than zero' using errcode = 'check_violation';
  end if;

  if g.mode = 'account' then
    select balance into v_bal from public.account_balances where account_id = g.linked_account_id;
    if p_amount > coalesce(v_bal, 0) then
      raise exception 'KABAN: that is more than the goal has saved' using errcode = 'check_violation';
    end if;
    if p_account = g.linked_account_id then
      raise exception 'KABAN: choose where the money goes' using errcode = 'check_violation';
    end if;
    perform kaban_private.post_transaction_as(
      auth.uid(), g.household_id, 'transfer',
      coalesce(p_date, kaban_private.household_today(g.household_id)),
      jsonb_build_array(jsonb_build_object('account_id', g.linked_account_id, 'amount', -p_amount),
                        jsonb_build_object('account_id', p_account, 'amount', p_amount)),
      null, 'From goal: ' || g.name, null, null, null, p_key);
  else
    select coalesce(sum(amount), 0) into v_now from public.goal_earmarks where goal_id = p_goal and account_id = p_account;
    if p_amount > v_now then
      raise exception 'KABAN: that is more than the goal has saved' using errcode = 'check_violation';
    end if;
    perform kaban_private.set_earmark(p_goal, p_account, v_now - p_amount);
  end if;
end $$;

-- Finish or remove a goal. Earmarks are released (the money becomes spendable
-- again); a goal's own savings account and its money stay where they are.
create function kaban_private.archive_goal(p_goal uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare g public.savings_goals%rowtype;
begin
  select * into g from public.savings_goals where id = p_goal;
  if not found or not kaban_private.can_write(g.household_id) or not kaban_private.can_see(g.household_id, g.owner_user_id) then
    raise exception 'KABAN: goal not available' using errcode = 'insufficient_privilege';
  end if;
  delete from public.goal_earmarks where goal_id = p_goal;
  update public.savings_goals set is_archived = true where id = p_goal;
end $$;

-- Wrappers + grants (same pattern as 0002)
create function public.save_goal(
  p_household uuid, p_goal uuid, p_name text, p_target bigint, p_target_date date default null,
  p_mode public.goal_mode default 'earmark', p_account uuid default null,
  p_new_account_name text default null, p_personal boolean default false
) returns uuid language sql security invoker set search_path = '' as $$
  select kaban_private.save_goal(p_household, p_goal, p_name, p_target, p_target_date, p_mode,
                                 p_account, p_new_account_name, p_personal)
$$;
create function public.add_to_goal(p_goal uuid, p_account uuid, p_amount bigint, p_date date default null, p_key text default null)
returns void language sql security invoker set search_path = '' as $$
  select kaban_private.add_to_goal(p_goal, p_account, p_amount, p_date, p_key)
$$;
create function public.take_from_goal(p_goal uuid, p_account uuid, p_amount bigint, p_date date default null, p_key text default null)
returns void language sql security invoker set search_path = '' as $$
  select kaban_private.take_from_goal(p_goal, p_account, p_amount, p_date, p_key)
$$;
create function public.archive_goal(p_goal uuid)
returns void language sql security invoker set search_path = '' as $$
  select kaban_private.archive_goal(p_goal)
$$;

revoke execute on function
  kaban_private.save_goal(uuid, uuid, text, bigint, date, public.goal_mode, uuid, text, boolean),
  kaban_private.add_to_goal(uuid, uuid, bigint, date, text),
  kaban_private.take_from_goal(uuid, uuid, bigint, date, text),
  kaban_private.archive_goal(uuid),
  public.save_goal(uuid, uuid, text, bigint, date, public.goal_mode, uuid, text, boolean),
  public.add_to_goal(uuid, uuid, bigint, date, text),
  public.take_from_goal(uuid, uuid, bigint, date, text),
  public.archive_goal(uuid)
from public, anon;
grant execute on function
  kaban_private.save_goal(uuid, uuid, text, bigint, date, public.goal_mode, uuid, text, boolean),
  kaban_private.add_to_goal(uuid, uuid, bigint, date, text),
  kaban_private.take_from_goal(uuid, uuid, bigint, date, text),
  kaban_private.archive_goal(uuid),
  public.save_goal(uuid, uuid, text, bigint, date, public.goal_mode, uuid, text, boolean),
  public.add_to_goal(uuid, uuid, bigint, date, text),
  public.take_from_goal(uuid, uuid, bigint, date, text),
  public.archive_goal(uuid)
to authenticated;
