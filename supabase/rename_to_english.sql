-- =====================================================================
-- KABAN: rename your categories and household to English.
-- Only names change; every past entry keeps its category.
-- The Back Tap menu picks up the new names on its next tap.
-- Safe to run again.
-- =====================================================================

with mine as (
  select m.household_id from public.household_members m
    join auth.users u on u.id = m.user_id
   where u.email = 'levisenseisagebulacan@gmail.com' and m.role = 'owner'
), names(old_name, new_name) as (values
  ('Sahod',              'Salary'),
  ('Iba pang kita',      'Other income'),
  ('Pagkain',            'Food'),
  ('Grocery',            'Groceries'),
  ('Transportasyon',     'Transportation'),
  ('Load at Internet',   'Load & Internet'),
  ('Kuryente',           'Electricity'),
  ('Tubig',              'Water'),
  ('Upa at Bahay',       'Rent & Housing'),
  ('Gamot at Kalusugan', 'Health & Medicine'),
  ('Eskwela',            'School'),
  ('Iba pa',             'Other')
)
update public.categories c
   set name = n.new_name
  from names n
 where c.name = n.old_name
   and c.household_id = (select household_id from mine);

update public.households
   set name = 'Our Household'
 where name = 'Aming Household'
   and id = (select m.household_id from public.household_members m
               join auth.users u on u.id = m.user_id
              where u.email = 'levisenseisagebulacan@gmail.com' and m.role = 'owner');

select kind, name from public.categories c
 where c.household_id = (select m.household_id from public.household_members m
                           join auth.users u on u.id = m.user_id
                          where u.email = 'levisenseisagebulacan@gmail.com' and m.role = 'owner')
 order by kind, name;
