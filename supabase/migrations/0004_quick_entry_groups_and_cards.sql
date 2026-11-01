-- =====================================================================
-- KABAN 0004: grouped "Saan galing?" menu + credit cards in quick entry
--
-- 1. accounts.display_order: your own order inside each menu group.
-- 2. Account names are unique per household/owner (case-insensitive), so a
--    name picked in the Shortcut always means exactly one account.
-- 3. Quick-entry tokens may use spendable assets (cash, e-wallets, banks) and
--    credit cards, NEVER non-spendable savings. Enforced by a trigger on the
--    token row (any write path) and again at submit time.
-- 4. quick_entry_accounts() also returns kind + menu group
--    (Cash / E-wallet / Bank / Credit Card) and display order.
-- =====================================================================

-- 1 -------------------------------------------------------------------
alter table public.accounts add column display_order smallint not null default 100;

-- 2 -------------------------------------------------------------------
create unique index accounts_unique_active_name
  on public.accounts (household_id, coalesce(owner_user_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(name))
  where not is_archived;

-- 3 -------------------------------------------------------------------
create function kaban_private.account_usable_for_quick_entry(p_account uuid, p_household uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.accounts a
     where a.id = p_account and a.household_id = p_household and not a.is_archived
       and (a.is_spendable or a.class = 'liability')           -- never savings
       and kaban_private.can_see(a.household_id, a.owner_user_id, p_user))
$$;

create function kaban_private.trg_token_accounts_guard()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_bad text;
begin
  select coalesce(a.name, x.id::text) into v_bad
    from unnest(array[new.default_account_id] || new.allowed_account_ids) x(id)
    left join public.accounts a on a.id = x.id
   where not kaban_private.account_usable_for_quick_entry(x.id, new.household_id, new.user_id)
   limit 1;
  if v_bad is not null then
    raise exception 'KABAN: "%" cannot be used for quick entry (savings, archived, or not yours)', v_bad
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

create trigger quick_entry_tokens_accounts_guard
  before insert or update of default_account_id, allowed_account_ids on public.quick_entry_tokens
  for each row execute function kaban_private.trg_token_accounts_guard();

-- Token creation: credit cards allowed now (the trigger does the account checks).
create or replace function kaban_private.create_quick_entry_token(
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

-- Submit: same as 0001, plus the use-time savings check.
create or replace function public.quick_entry_submit(
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
  if not kaban_private.account_usable_for_quick_entry(v_acct, k.household_id, k.user_id) then
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

-- 4 -------------------------------------------------------------------
drop function public.quick_entry_accounts(text);

create function public.quick_entry_accounts(p_token text)
returns table (id uuid, name text, is_default boolean, kind public.account_kind,
               menu_group text, group_order int, display_order smallint)
language plpgsql security definer set search_path = '' as $$
declare k public.quick_entry_tokens%rowtype;
begin
  k := kaban_private.resolve_token(p_token);
  return query
    select a.id, a.name, a.id = k.default_account_id, a.kind,
           case a.kind when 'cash' then 'Cash' when 'ewallet' then 'E-wallet' when 'bank' then 'Bank'
                       when 'credit_card' then 'Credit Card' when 'loan' then 'Credit Card' else 'Iba pa' end,
           case a.kind when 'cash' then 1 when 'ewallet' then 2 when 'bank' then 3
                       when 'credit_card' then 4 when 'loan' then 4 else 5 end,
           a.display_order
      from public.accounts a
     where (a.id = k.default_account_id or a.id = any (k.allowed_account_ids))
       and kaban_private.account_usable_for_quick_entry(a.id, k.household_id, k.user_id)
     order by 6, 7, a.name;
end $$;

revoke execute on function public.quick_entry_accounts(text) from public, anon, authenticated;
grant  execute on function public.quick_entry_accounts(text) to service_role;
revoke execute on function kaban_private.account_usable_for_quick_entry(uuid, uuid, uuid) from public, anon;
