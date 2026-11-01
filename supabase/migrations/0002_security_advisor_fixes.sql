-- =====================================================================
-- KABAN 0002: Security Advisor fixes
--
-- 1. Function Search Path Mutable  -> pin search_path on the trigger function.
-- 2. Public (anon) can execute SECURITY DEFINER functions
--    -> logged-out callers lose EXECUTE on everything.
-- 3. Signed-in users can execute SECURITY DEFINER functions in `public`
--    -> the privileged bodies move to kaban_private (not exposed by the API);
--       `public` keeps same-named SECURITY INVOKER wrappers, so the app's
--       supabase.rpc('post_transaction', ...) calls do not change.
--
-- Security is unchanged where it matters: every private function still
-- re-checks auth.uid(), membership, role and account visibility.
-- =====================================================================

-- 1 -------------------------------------------------------------------
alter function kaban_private.trg_entries_immutable() set search_path = '';

-- 2 -------------------------------------------------------------------
-- Stop Postgres/Supabase from granting EXECUTE on future functions to
-- PUBLIC and anon. Grants are made explicitly per function instead.
alter default privileges revoke execute on functions from public;
alter default privileges in schema public revoke execute on functions from anon;

-- 3 -------------------------------------------------------------------
-- Move the SECURITY DEFINER bodies out of the exposed schema.
alter function public.post_transaction(uuid, public.txn_type, date, jsonb, uuid, text, uuid, uuid, uuid, text)
  set schema kaban_private;
alter function public.void_transaction(uuid, text)                          set schema kaban_private;
alter function public.edit_transaction(uuid, date, jsonb, uuid, text)       set schema kaban_private;
alter function public.set_earmark(uuid, uuid, bigint)                       set schema kaban_private;
alter function public.available_to_spend(uuid, text)                        set schema kaban_private;
alter function public.create_quick_entry_token(uuid, text, uuid, public.txn_type[], bigint, int, int)
  set schema kaban_private;
alter function public.revoke_quick_entry_token(uuid)                        set schema kaban_private;

-- edit_transaction called public.void_transaction; point it at the private body.
create or replace function kaban_private.edit_transaction(
  p_txn uuid, p_occurred_on date, p_entries jsonb,
  p_category_id uuid default null, p_description text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare t public.transactions%rowtype; v_new uuid;
begin
  select * into t from public.transactions where id = p_txn;
  perform kaban_private.void_transaction(p_txn, 'edited');
  v_new := kaban_private.post_transaction_as(auth.uid(), t.household_id, t.type, p_occurred_on, p_entries,
             coalesce(p_category_id, t.category_id), coalesce(p_description, t.description),
             t.bill_occurrence_id, t.goal_id, t.parent_id, null, 'app', null, p_txn);
  return v_new;
end $$;

-- Thin public wrappers: SECURITY INVOKER, signed-in users only.
create function public.post_transaction(
  p_household uuid, p_type public.txn_type, p_occurred_on date, p_entries jsonb,
  p_category_id uuid default null, p_description text default null,
  p_bill_occurrence uuid default null, p_goal_id uuid default null,
  p_parent_id uuid default null, p_idempotency_key text default null
) returns uuid language sql security invoker set search_path = '' as $$
  select kaban_private.post_transaction(p_household, p_type, p_occurred_on, p_entries, p_category_id,
           p_description, p_bill_occurrence, p_goal_id, p_parent_id, p_idempotency_key)
$$;

create function public.void_transaction(p_txn uuid, p_reason text default null)
returns void language sql security invoker set search_path = '' as $$
  select kaban_private.void_transaction(p_txn, p_reason)
$$;

create function public.edit_transaction(
  p_txn uuid, p_occurred_on date, p_entries jsonb,
  p_category_id uuid default null, p_description text default null
) returns uuid language sql security invoker set search_path = '' as $$
  select kaban_private.edit_transaction(p_txn, p_occurred_on, p_entries, p_category_id, p_description)
$$;

create function public.set_earmark(p_goal uuid, p_account uuid, p_amount bigint)
returns void language sql security invoker set search_path = '' as $$
  select kaban_private.set_earmark(p_goal, p_account, p_amount)
$$;

create function public.available_to_spend(p_household uuid, p_scope text default 'shared')
returns table (spendable_balance bigint, earmarked bigint, bills_reserved bigint,
               available bigint, horizon date, over_earmarked boolean)
language sql stable security invoker set search_path = '' as $$
  select * from kaban_private.available_to_spend(p_household, p_scope)
$$;

create function public.create_quick_entry_token(
  p_household uuid, p_label text, p_default_account uuid,
  p_allowed_types public.txn_type[] default '{expense}',
  p_max_amount bigint default 2000000, p_daily_limit int default 30,
  p_valid_days int default 90
) returns table (token_id uuid, token text, expires_at timestamptz)
language sql security invoker set search_path = '' as $$
  select * from kaban_private.create_quick_entry_token(p_household, p_label, p_default_account,
           p_allowed_types, p_max_amount, p_daily_limit, p_valid_days)
$$;

create function public.revoke_quick_entry_token(p_token_id uuid)
returns void language sql security invoker set search_path = '' as $$
  select kaban_private.revoke_quick_entry_token(p_token_id)
$$;

-- Grants: nothing for PUBLIC/anon; signed-in users call wrappers -> private bodies.
revoke execute on all functions in schema kaban_private from public, anon;
revoke execute on all functions in schema public       from public, anon;

grant execute on function
  kaban_private.post_transaction(uuid, public.txn_type, date, jsonb, uuid, text, uuid, uuid, uuid, text),
  kaban_private.void_transaction(uuid, text),
  kaban_private.edit_transaction(uuid, date, jsonb, uuid, text),
  kaban_private.set_earmark(uuid, uuid, bigint),
  kaban_private.available_to_spend(uuid, text),
  kaban_private.create_quick_entry_token(uuid, text, uuid, public.txn_type[], bigint, int, int),
  kaban_private.revoke_quick_entry_token(uuid)
to authenticated;

grant execute on function
  public.post_transaction(uuid, public.txn_type, date, jsonb, uuid, text, uuid, uuid, uuid, text),
  public.void_transaction(uuid, text),
  public.edit_transaction(uuid, date, jsonb, uuid, text),
  public.set_earmark(uuid, uuid, bigint),
  public.available_to_spend(uuid, text),
  public.create_quick_entry_token(uuid, text, uuid, public.txn_type[], bigint, int, int),
  public.revoke_quick_entry_token(uuid),
  public.monthly_summary(uuid, date)
to authenticated;

-- Quick entry stays service_role only (the Edge Function).
grant execute on function
  public.quick_entry_submit(text, bigint, uuid, public.txn_type, uuid, text, text),
  public.quick_entry_categories(text)
to service_role;
