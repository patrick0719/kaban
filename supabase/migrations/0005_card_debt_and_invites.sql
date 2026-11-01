-- =====================================================================
-- KABAN 0005: household decisions
--
-- 1. card_debt_mode per household:
--      'statement' (default) - card debt reduces "available" only through its bill
--      'full'                - all unpaid card debt is subtracted immediately
--    In 'full' mode a bill that SETTLES a card (bills.settles_account_id) is
--    not reserved again, so the same debt is never subtracted twice.
-- 2. available_to_spend() gains a card_debt column.
-- 3. Household invites: an owner/admin invites an email; that person signs
--    up with the same email and accepts. No email is sent by the database.
-- =====================================================================

-- 0 -------------------------------------------------------------------
-- Hardening: for a NON-member, role_in() is NULL, so `x in (...)` was NULL,
-- and `if not <NULL>` does not fire. Every permission helper now returns a
-- real false. (Earlier functions were saved by their other checks; this
-- removes the trap for all current and future callers.)
create or replace function kaban_private.can_write(p_household uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(kaban_private.role_in(p_household, p_user) in ('owner', 'admin', 'member'), false)
$$;

create or replace function kaban_private.is_admin(p_household uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(kaban_private.role_in(p_household) in ('owner', 'admin'), false)
$$;

create or replace function kaban_private.can_see(p_household uuid, p_owner uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(kaban_private.role_in(p_household, p_user) is not null
                  and (p_owner is null or p_owner = p_user), false)
$$;

-- 1 -------------------------------------------------------------------
create type public.card_debt_mode as enum ('statement', 'full');
alter table public.households add column card_debt_mode public.card_debt_mode not null default 'statement';

alter table public.bills add column settles_account_id uuid;
alter table public.bills add constraint bills_settles_account_fk
  foreign key (settles_account_id, household_id) references public.accounts(id, household_id);

create function kaban_private.trg_bill_settles_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.settles_account_id is not null and not exists (
       select 1 from public.accounts where id = new.settles_account_id and class = 'liability') then
    raise exception 'KABAN: settles_account_id must be a credit card or loan' using errcode = 'check_violation';
  end if;
  return new;
end $$;
create trigger bills_settles_guard before insert or update of settles_account_id on public.bills
  for each row execute function kaban_private.trg_bill_settles_guard();

-- 2 -------------------------------------------------------------------
drop function public.available_to_spend(uuid, text);
drop function kaban_private.available_to_spend(uuid, text);

create function kaban_private.available_to_spend(p_household uuid, p_scope text default 'shared')
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
         coalesce((select bool_or(raw > balance) from marks), false);
end $$;

create function public.available_to_spend(p_household uuid, p_scope text default 'shared')
returns table (spendable_balance bigint, earmarked bigint, bills_reserved bigint, card_debt bigint,
               available bigint, horizon date, over_earmarked boolean)
language sql stable security invoker set search_path = '' as $$
  select * from kaban_private.available_to_spend(p_household, p_scope)
$$;

revoke execute on function kaban_private.available_to_spend(uuid, text) from public, anon;
revoke execute on function public.available_to_spend(uuid, text)        from public, anon;
grant  execute on function kaban_private.available_to_spend(uuid, text) to authenticated;
grant  execute on function public.available_to_spend(uuid, text)        to authenticated;

-- 3 -------------------------------------------------------------------
create table public.household_invites (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references public.households(id) on delete cascade,
  email         text not null check (email = lower(btrim(email)) and email like '%_@_%'),
  role          public.household_role not null default 'member' check (role <> 'owner'),
  invited_by    uuid not null references auth.users(id),
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null default now() + interval '7 days',
  accepted_at   timestamptz,
  accepted_by   uuid references auth.users(id),
  revoked_at    timestamptz
);
create unique index household_invites_one_pending
  on public.household_invites (household_id, email) where accepted_at is null and revoked_at is null;

create function kaban_private.my_email()
returns text language sql stable security definer set search_path = '' as $$
  select lower(email) from auth.users where id = auth.uid()
$$;

alter table public.household_invites enable row level security;
create policy inv_select on public.household_invites for select to authenticated
  using (kaban_private.is_admin(household_id) or email = kaban_private.my_email());
revoke insert, update, delete on public.household_invites from anon, authenticated;
revoke all on public.household_invites from anon;

-- Owner/admin invites someone by email.
create function kaban_private.invite_member(p_household uuid, p_email text,
                                            p_role public.household_role default 'member')
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_email text := lower(btrim(p_email)); v_id uuid;
begin
  if not kaban_private.is_admin(p_household) then
    raise exception 'KABAN: only owners and admins can invite' using errcode = 'insufficient_privilege';
  end if;
  if p_role = 'owner' then
    raise exception 'KABAN: invite as admin, member or viewer' using errcode = 'invalid_parameter_value';
  end if;
  if exists (select 1 from public.household_members m join auth.users u on u.id = m.user_id
              where m.household_id = p_household and lower(u.email) = v_email) then
    raise exception 'KABAN: % is already a member', v_email using errcode = 'unique_violation';
  end if;
  -- a fresh invite replaces any older pending one for the same email
  update public.household_invites set revoked_at = now()
   where household_id = p_household and email = v_email and accepted_at is null and revoked_at is null;
  insert into public.household_invites (household_id, email, role, invited_by)
  values (p_household, v_email, p_role, auth.uid()) returning id into v_id;
  return v_id;
end $$;

-- The invited person, signed in with the SAME email, accepts.
create function kaban_private.accept_invite(p_invite uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare i public.household_invites%rowtype;
begin
  select * into i from public.household_invites where id = p_invite for update;
  if not found or i.email <> kaban_private.my_email()
     or i.accepted_at is not null or i.revoked_at is not null or i.expires_at <= now() then
    raise exception 'KABAN: invite not valid for this account' using errcode = 'insufficient_privilege';
  end if;
  insert into public.household_members (household_id, user_id, role)
  values (i.household_id, auth.uid(), i.role)
  on conflict (household_id, user_id) do nothing;
  update public.household_invites set accepted_at = now(), accepted_by = auth.uid() where id = p_invite;
  insert into public.audit_log (household_id, actor, action, entity, entity_id, after)
  values (i.household_id, auth.uid(), 'join', 'household_member', auth.uid(), jsonb_build_object('role', i.role));
  return i.household_id;
end $$;

create function kaban_private.revoke_invite(p_invite uuid)
returns void language sql security definer set search_path = '' as $$
  update public.household_invites set revoked_at = now()
   where id = p_invite and accepted_at is null and revoked_at is null
     and kaban_private.is_admin(household_id);
$$;

-- Invites waiting for the signed-in user (shown after sign-up).
create function kaban_private.my_pending_invites()
returns table (invite_id uuid, household_name text, role public.household_role, expires_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select i.id, h.name, i.role, i.expires_at
    from public.household_invites i join public.households h on h.id = i.household_id
   where i.email = kaban_private.my_email()
     and i.accepted_at is null and i.revoked_at is null and i.expires_at > now()
   order by i.created_at desc;
$$;

-- Public wrappers (SECURITY INVOKER), same pattern as 0002.
create function public.invite_member(p_household uuid, p_email text, p_role public.household_role default 'member')
returns uuid language sql security invoker set search_path = '' as $$
  select kaban_private.invite_member(p_household, p_email, p_role)
$$;
create function public.accept_invite(p_invite uuid)
returns uuid language sql security invoker set search_path = '' as $$
  select kaban_private.accept_invite(p_invite)
$$;
create function public.revoke_invite(p_invite uuid)
returns void language sql security invoker set search_path = '' as $$
  select kaban_private.revoke_invite(p_invite)
$$;
create function public.my_pending_invites()
returns table (invite_id uuid, household_name text, role public.household_role, expires_at timestamptz)
language sql stable security invoker set search_path = '' as $$
  select * from kaban_private.my_pending_invites()
$$;

revoke execute on function
  kaban_private.invite_member(uuid, text, public.household_role), kaban_private.accept_invite(uuid),
  kaban_private.revoke_invite(uuid), kaban_private.my_pending_invites(), kaban_private.my_email(),
  public.invite_member(uuid, text, public.household_role), public.accept_invite(uuid),
  public.revoke_invite(uuid), public.my_pending_invites()
from public, anon;
grant execute on function
  kaban_private.invite_member(uuid, text, public.household_role), kaban_private.accept_invite(uuid),
  kaban_private.revoke_invite(uuid), kaban_private.my_pending_invites(), kaban_private.my_email(),
  public.invite_member(uuid, text, public.household_role), public.accept_invite(uuid),
  public.revoke_invite(uuid), public.my_pending_invites()
to authenticated;
