-- =====================================================================
-- KABAN: set the "Saan galing?" menu to
--
--   Cash
--   E-wallet     : GoTyme, GCash, Maya
--   Credit Card  : UnionBank, BPI, MetroBank, Atome, EastWest, ChinaBank, Robinsons Bank
--
-- Run AFTER migration 0004, once, in the SQL Editor. Safe to run again.
-- To change the menu later, edit the list below and run it again.
-- =====================================================================

drop table if exists pg_temp.menu;
create temp table menu (name text, kind public.account_kind, display_order smallint);
insert into menu values
  ('Cash',           'cash',        1),
  ('GoTyme',         'ewallet',     1),
  ('GCash',          'ewallet',     2),
  ('Maya',           'ewallet',     3),
  ('UnionBank',      'credit_card', 1),
  ('BPI',            'credit_card', 2),
  ('MetroBank',      'credit_card', 3),
  ('Atome',          'credit_card', 4),
  ('EastWest',       'credit_card', 5),
  ('ChinaBank',      'credit_card', 6),
  ('Robinsons Bank', 'credit_card', 7);

do $$
declare
  v_user uuid;
  v_hh   uuid;
  m      record;
  a      public.accounts%rowtype;
  v_cls  public.account_class;
  v_has  boolean;
begin
  select id into v_user from auth.users where email = 'levisenseisagebulacan@gmail.com';
  select household_id into v_hh from public.household_members where user_id = v_user;
  if v_hh is null then raise exception 'Run setup_my_household.sql first.'; end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'accounts' and column_name = 'display_order') then
    raise exception 'I-run muna ang migration 0004_quick_entry_groups_and_cards.sql, saka ito.';
  end if;

  for m in select * from menu loop
    v_cls := case when m.kind in ('credit_card', 'loan') then 'liability' else 'asset' end;

    select * into a from public.accounts
     where household_id = v_hh and owner_user_id is null and not is_archived and lower(name) = lower(m.name);
    v_has := found;

    if v_has and a.kind <> m.kind then
      if exists (select 1 from public.ledger_entries where account_id = a.id) then
        -- has history: keep it under a clearer name, make a new account for the menu
        update public.accounts set name = a.name || ' ' || initcap(replace(a.kind::text, '_', ' '))
         where id = a.id;
        v_has := false;
      else
        -- unused: just change its type
        update public.accounts set kind = m.kind, class = v_cls,
               is_spendable = (v_cls = 'asset'), display_order = m.display_order
         where id = a.id;
        continue;
      end if;
    end if;

    if v_has then
      update public.accounts set display_order = m.display_order where id = a.id;
    else
      insert into public.accounts (household_id, name, kind, class, is_spendable, display_order, created_by)
      values (v_hh, m.name, m.kind, v_cls, v_cls = 'asset', m.display_order, v_user);
    end if;
  end loop;

  -- Point your active token(s) at exactly this list; Cash stays the default.
  update public.quick_entry_tokens q
     set default_account_id  = (select id from public.accounts where household_id = v_hh and owner_user_id is null
                                  and not is_archived and name = 'Cash'),
         allowed_account_ids = array(select a2.id from public.accounts a2 join menu mm on lower(mm.name) = lower(a2.name)
                                      where a2.household_id = v_hh and a2.owner_user_id is null
                                        and not a2.is_archived and a2.name <> 'Cash')
   where q.user_id = v_user and q.revoked_at is null;
end $$;

-- What your Shortcut menu will show:
select case a.kind when 'cash' then 'Cash' when 'ewallet' then 'E-wallet' when 'bank' then 'Bank'
                   else 'Credit Card' end as grupo,
       a.name as account
  from public.quick_entry_tokens q
  join public.accounts a on a.id = q.default_account_id or a.id = any (q.allowed_account_ids)
 where q.user_id = (select id from auth.users where email = 'levisenseisagebulacan@gmail.com')
   and q.revoked_at is null
 order by case a.kind when 'cash' then 1 when 'ewallet' then 2 when 'bank' then 3 else 4 end, a.display_order;
