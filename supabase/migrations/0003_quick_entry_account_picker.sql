-- =====================================================================
-- KABAN 0003: account picker for quick entry
--
-- 1. create_quick_entry_token() takes an optional list of extra accounts
--    the token may spend from (besides its default account).
-- 2. quick_entry_accounts(token) returns those account NAMES for the
--    Shortcut's "Saan galing?" menu. No balances. Edge Function only.
-- =====================================================================

-- 1 -------------------------------------------------------------------
drop function public.create_quick_entry_token(uuid, text, uuid, public.txn_type[], bigint, int, int);
drop function kaban_private.create_quick_entry_token(uuid, text, uuid, public.txn_type[], bigint, int, int);

create function kaban_private.create_quick_entry_token(
  p_household uuid, p_label text, p_default_account uuid,
  p_allowed_types public.txn_type[] default '{expense}',
  p_max_amount bigint default 2000000, p_daily_limit int default 30,
  p_valid_days int default 90,
  p_allowed_accounts uuid[] default '{}'
) returns table (token_id uuid, token text, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare v_plain text; v_id uuid; v_exp timestamptz;
begin
  if not kaban_private.can_write(p_household) or not kaban_private.can_see_account(p_default_account) then
    raise exception 'KABAN: not allowed' using errcode = 'insufficient_privilege';
  end if;
  -- every extra account: same household, visible to the caller, an active asset account
  if exists (
       select 1 from unnest(coalesce(p_allowed_accounts, '{}')) x(id)
        where not exists (select 1 from public.accounts a
                           where a.id = x.id and a.household_id = p_household
                             and a.class = 'asset' and not a.is_archived
                             and kaban_private.can_see_account(a.id))) then
    raise exception 'KABAN: an allowed account is not available' using errcode = 'insufficient_privilege';
  end if;
  if p_valid_days not between 1 and 365 then
    raise exception 'KABAN: validity must be 1-365 days' using errcode = 'invalid_parameter_value';
  end if;
  if (select count(*) from public.quick_entry_tokens q
       where q.user_id = auth.uid() and q.revoked_at is null and q.expires_at > now()) >= 5 then
    raise exception 'KABAN: at most 5 active quick-entry tokens per user' using errcode = 'check_violation';
  end if;

  v_plain := 'kbn_qe_' || encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.quick_entry_tokens (household_id, user_id, label, token_prefix, token_hash,
                                         allowed_types, default_account_id, allowed_account_ids,
                                         max_amount, daily_limit, expires_at)
  values (p_household, auth.uid(), p_label, left(v_plain, 14),
          extensions.digest(v_plain, 'sha256'), p_allowed_types, p_default_account,
          array(select distinct x from unnest(coalesce(p_allowed_accounts, '{}')) x where x <> p_default_account),
          p_max_amount, p_daily_limit, now() + make_interval(days => p_valid_days))
  returning id, quick_entry_tokens.expires_at into v_id, v_exp;

  return query select v_id, v_plain, v_exp;
end $$;

create function public.create_quick_entry_token(
  p_household uuid, p_label text, p_default_account uuid,
  p_allowed_types public.txn_type[] default '{expense}',
  p_max_amount bigint default 2000000, p_daily_limit int default 30,
  p_valid_days int default 90,
  p_allowed_accounts uuid[] default '{}'
) returns table (token_id uuid, token text, expires_at timestamptz)
language sql security invoker set search_path = '' as $$
  select * from kaban_private.create_quick_entry_token(p_household, p_label, p_default_account,
           p_allowed_types, p_max_amount, p_daily_limit, p_valid_days, p_allowed_accounts)
$$;

revoke execute on function kaban_private.create_quick_entry_token(uuid, text, uuid, public.txn_type[], bigint, int, int, uuid[]) from public, anon;
revoke execute on function public.create_quick_entry_token(uuid, text, uuid, public.txn_type[], bigint, int, int, uuid[])       from public, anon;
grant  execute on function kaban_private.create_quick_entry_token(uuid, text, uuid, public.txn_type[], bigint, int, int, uuid[]) to authenticated;
grant  execute on function public.create_quick_entry_token(uuid, text, uuid, public.txn_type[], bigint, int, int, uuid[])       to authenticated;

-- 2 -------------------------------------------------------------------
-- Default account first, then the rest by name. Names only.
create function public.quick_entry_accounts(p_token text)
returns table (id uuid, name text, is_default boolean)
language plpgsql security definer set search_path = '' as $$
declare k public.quick_entry_tokens%rowtype;
begin
  k := kaban_private.resolve_token(p_token);
  return query
    select a.id, a.name, a.id = k.default_account_id
      from public.accounts a
     where (a.id = k.default_account_id or a.id = any (k.allowed_account_ids))
       and not a.is_archived
       and kaban_private.can_see(a.household_id, a.owner_user_id, k.user_id)
     order by a.id = k.default_account_id desc, a.name;
end $$;

revoke execute on function public.quick_entry_accounts(text) from public, anon, authenticated;
grant  execute on function public.quick_entry_accounts(text) to service_role;
