begin;

create extension if not exists pgtap with schema extensions;
select plan(59);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('10000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'owner-a@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('10000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'staff-a@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('10000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'owner-b@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('10000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'new-member@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('10000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'new-owner@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('10000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'manager-a@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.shops (id, name, created_by) values
  ('20000000-0000-4000-8000-000000000001', 'Fictional Shop A', '10000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000002', 'Fictional Shop B', '10000000-0000-4000-8000-000000000003');

insert into public.shop_memberships (shop_id, user_id, role, created_by) values
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'owner', '10000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', 'sales_staff', '10000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000006', 'manager', '10000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000003', 'owner', '10000000-0000-4000-8000-000000000003');

insert into public.branches (id, shop_id, name, is_primary, created_by) values
  ('30000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'A Main', true, '10000000-0000-4000-8000-000000000001'),
  ('30000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000001', 'A Restricted', false, '10000000-0000-4000-8000-000000000001'),
  ('30000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000002', 'B Main', true, '10000000-0000-4000-8000-000000000003');

insert into public.branch_memberships (shop_id, branch_id, user_id, created_by) values
  ('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000006', '10000000-0000-4000-8000-000000000001');

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000002', true);

select is(
  (select count(*)::integer from public.shops where id = '20000000-0000-4000-8000-000000000001'),
  1,
  'active member can read their shop'
);
select is(
  (select count(*)::integer from public.shops where id = '20000000-0000-4000-8000-000000000002'),
  0,
  'Shop A member cannot read Shop B'
);
select is(
  (select count(*)::integer from public.shop_memberships where shop_id = '20000000-0000-4000-8000-000000000001' and user_id = '10000000-0000-4000-8000-000000000001'),
  0,
  'staff cannot read another member record'
);
select results_eq(
  $$ with changed as (
    update public.shops set name = 'Unauthorized change'
    where id = '20000000-0000-4000-8000-000000000002'
    returning id
  ) select id from changed $$,
  $$ select null::uuid where false $$,
  'staff cannot update another shop'
);
select results_eq(
  $$ with changed as (
    update public.branches set is_active = false
    where id = '30000000-0000-4000-8000-000000000001'
    returning id
  ) select id from changed $$,
  $$ select null::uuid where false $$,
  'staff cannot update a branch even when it is assigned'
);
select results_eq(
  $$ with changed as (
    update public.user_profiles set display_name = 'Unauthorized change'
    where user_id = '10000000-0000-4000-8000-000000000001'
    returning user_id
  ) select user_id from changed $$,
  $$ select null::uuid where false $$,
  'users cannot update another profile'
);
select throws_ok(
  $$ insert into public.shops (name, created_by) values ('Unauthorized shop', '10000000-0000-4000-8000-000000000002') $$,
  '42501', null,
  'staff cannot insert shops directly'
);
select throws_ok(
  $$ delete from public.shops where id = '20000000-0000-4000-8000-000000000001' $$,
  '42501', null,
  'staff cannot delete shops'
);
select throws_ok(
  $$ insert into public.branch_memberships (shop_id, branch_id, user_id, created_by) values ('20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002') $$,
  '42501', null,
  'staff cannot insert branch assignments directly'
);
select throws_ok(
  $$ delete from public.branch_memberships where shop_id = '20000000-0000-4000-8000-000000000001' and user_id = '10000000-0000-4000-8000-000000000002' $$,
  '42501', null,
  'staff cannot delete branch assignments directly'
);
select throws_ok(
  $$ delete from public.shop_memberships where shop_id = '20000000-0000-4000-8000-000000000001' and user_id = '10000000-0000-4000-8000-000000000002' $$,
  '42501', null,
  'staff cannot delete memberships directly'
);
select is(
  (select count(*)::integer from public.branches where id = '30000000-0000-4000-8000-000000000001'),
  1,
  'staff can read an assigned branch'
);
select is(
  (select count(*)::integer from public.branches where id = '30000000-0000-4000-8000-000000000002'),
  0,
  'staff cannot read an unassigned branch in their shop'
);
select is(
  (select count(*)::integer from public.branches where id = '30000000-0000-4000-8000-000000000003'),
  0,
  'staff cannot read a branch in another shop'
);
select throws_ok(
  $$ update public.shop_memberships set role = 'owner' where shop_id = '20000000-0000-4000-8000-000000000001' and user_id = '10000000-0000-4000-8000-000000000002' $$,
  '42501', null,
  'staff cannot change their own membership role directly'
);
select throws_ok(
  $$ insert into public.shop_memberships (shop_id, user_id, role, created_by) values ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', 'owner', '10000000-0000-4000-8000-000000000002') $$,
  '42501', null,
  'staff cannot insert a membership into another shop'
);
select throws_ok(
  $$ select public.owner_set_member_access('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000004', 'inventory_staff', array['30000000-0000-4000-8000-000000000001']::uuid[]) $$,
  '42501', null,
  'staff cannot use the owner membership function'
);

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000006', true);
select is(
  (select count(*)::integer from public.branches where id = '30000000-0000-4000-8000-000000000001'),
  1,
  'manager can read an explicitly assigned branch'
);
select is(
  (select count(*)::integer from public.branches where id = '30000000-0000-4000-8000-000000000002'),
  0,
  'manager cannot read an unassigned branch'
);
select throws_ok(
  $$ select public.create_branch('20000000-0000-4000-8000-000000000001', 'Unauthorized branch') $$,
  '42501', null,
  'manager cannot create a branch under the owner-only default'
);
select throws_ok(
  $$ select public.owner_suspend_shop_member('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000002') $$,
  '42501', null,
  'manager cannot use the owner membership suspension function'
);

select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$ select public.create_shop_for_current_user('Unauthenticated shop') $$,
  '42501', null,
  'shop onboarding rejects an authenticated database role without an identity'
);
set local role anon;
select throws_ok(
  $$ select * from public.shops $$,
  '42501', null,
  'anonymous users have no shop table access'
);
select throws_ok(
  $$ select public.create_shop_for_current_user('Anonymous shop') $$,
  '42501', null,
  'anonymous users cannot execute shop onboarding'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
select is(
  (select count(*)::integer from public.branches where shop_id = '20000000-0000-4000-8000-000000000001'),
  2,
  'owner can read all active branches in their shop'
);
select results_eq(
  $$ with changed as (
    update public.shops set name = 'Fictional Shop A Updated'
    where id = '20000000-0000-4000-8000-000000000001'
    returning id
  ) select id from changed $$,
  $$ select '20000000-0000-4000-8000-000000000001'::uuid $$,
  'owner can update their own shop'
);
select ok(
  public.create_branch('20000000-0000-4000-8000-000000000001', 'Owner Branch') is not null,
  'owner can create a branch for their shop'
);
select lives_ok(
  $$ select public.owner_set_member_access(
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000004',
    'manager',
    array['30000000-0000-4000-8000-000000000002']::uuid[]
  ) $$,
  'shop owner can assign a registered member to a branch'
);
select is(
  (select count(*)::integer from public.shop_memberships where shop_id = '20000000-0000-4000-8000-000000000001' and user_id = '10000000-0000-4000-8000-000000000004' and role = 'manager' and status = 'active'),
  1,
  'owner assignment creates the selected role'
);
select is(
  (select count(*)::integer from public.branch_memberships where shop_id = '20000000-0000-4000-8000-000000000001' and user_id = '10000000-0000-4000-8000-000000000004' and branch_id = '30000000-0000-4000-8000-000000000002'),
  1,
  'owner assignment creates the selected branch scope'
);
select throws_ok(
  $$ select public.owner_set_member_access('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'manager', array['30000000-0000-4000-8000-000000000001']::uuid[]) $$,
  '42501', null,
  'owner cannot promote or alter their own membership through staff assignment'
);
select throws_ok(
  $$ select public.owner_set_member_access('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000004', 'owner', array['30000000-0000-4000-8000-000000000001']::uuid[]) $$,
  '42501', null,
  'staff assignment function cannot create another owner'
);
select throws_ok(
  $$ select public.owner_set_member_access('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000004', 'manager', array['30000000-0000-4000-8000-000000000003']::uuid[]) $$,
  '22023', null,
  'owner cannot assign a branch from another shop'
);
select lives_ok(
  $$ select public.owner_suspend_shop_member(
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000004'
  ) $$,
  'owner can suspend a non-owner membership'
);
select is(
  (select count(*)::integer from public.shop_memberships where shop_id = '20000000-0000-4000-8000-000000000001' and user_id = '10000000-0000-4000-8000-000000000004' and status = 'suspended'),
  1,
  'suspension is retained in the membership record'
);
select is(
  (select count(*)::integer from public.branch_memberships where shop_id = '20000000-0000-4000-8000-000000000001' and user_id = '10000000-0000-4000-8000-000000000004'),
  1,
  'suspension preserves the member branch assignment'
);
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000004', true);
select is(
  (select count(*)::integer from public.shops where id = '20000000-0000-4000-8000-000000000001'),
  0,
  'suspended member cannot read their shop'
);
select is(
  (select count(*)::integer from public.branches where id = '30000000-0000-4000-8000-000000000002'),
  0,
  'suspended member cannot read their previously assigned branch'
);
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
select is(
  (select count(*)::integer from public.shop_memberships where shop_id = '20000000-0000-4000-8000-000000000001' and user_id = '10000000-0000-4000-8000-000000000004' and status = 'suspended'),
  1,
  'owner can still read the suspended member record'
);
select lives_ok(
  $$ select public.owner_reactivate_shop_member(
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000004'
  ) $$,
  'shop owner can reactivate a suspended manager'
);
select is(
  (select count(*)::integer from public.shop_memberships where shop_id = '20000000-0000-4000-8000-000000000001' and user_id = '10000000-0000-4000-8000-000000000004' and role = 'manager' and status = 'active'),
  1,
  'reactivation preserves the member manager role'
);
select is(
  (select count(*)::integer from public.branch_memberships where shop_id = '20000000-0000-4000-8000-000000000001' and user_id = '10000000-0000-4000-8000-000000000004' and branch_id = '30000000-0000-4000-8000-000000000002'),
  1,
  'reactivation preserves the existing branch assignment'
);
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000004', true);
select is(
  (select count(*)::integer from public.branches where id = '30000000-0000-4000-8000-000000000002'),
  1,
  'reactivated manager can read the same assigned branch'
);
select throws_ok(
  $$ select public.owner_reactivate_shop_member('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000004') $$,
  '42501', null,
  'member cannot reactivate their own membership'
);
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$ select public.owner_reactivate_shop_member('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000004') $$,
  '42501', null,
  'non-owner cannot reactivate a member'
);
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$ select public.owner_reactivate_shop_member('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000004') $$,
  '42501', null,
  'owner cannot reactivate membership in another shop'
);
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$ select public.owner_suspend_shop_member('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000004') $$,
  'owner can suspend the reactivated member again'
);
reset role;
delete from public.branch_memberships
where shop_id = '20000000-0000-4000-8000-000000000001'
  and user_id = '10000000-0000-4000-8000-000000000004';
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$ select public.owner_reactivate_shop_member('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000004') $$,
  '22023', null,
  'reactivation refuses to guess when a legacy member has no saved branch assignments'
);
select throws_ok(
  $$ select public.owner_reactivate_shop_member('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000004', array['30000000-0000-4000-8000-000000000003']::uuid[]) $$,
  '22023', null,
  'owner cannot restore a branch from another shop'
);
select is(
  (select count(*)::integer from public.shop_memberships where shop_id = '20000000-0000-4000-8000-000000000001' and user_id = '10000000-0000-4000-8000-000000000004' and status = 'suspended'),
  1,
  'member stays suspended when no prior branch assignment can be restored'
);
select lives_ok(
  $$ select public.owner_reactivate_shop_member(
    '20000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000004',
    array['30000000-0000-4000-8000-000000000002']::uuid[]
  ) $$,
  'owner can explicitly restore a legacy branch assignment without changing the role'
);
select is(
  (select count(*)::integer from public.shop_memberships where shop_id = '20000000-0000-4000-8000-000000000001' and user_id = '10000000-0000-4000-8000-000000000004' and role = 'manager' and status = 'active'),
  1,
  'legacy reactivation preserves the manager role'
);
select is(
  (select count(*)::integer from public.branch_memberships where shop_id = '20000000-0000-4000-8000-000000000001' and user_id = '10000000-0000-4000-8000-000000000004' and branch_id = '30000000-0000-4000-8000-000000000002'),
  1,
  'legacy reactivation restores only the owner-selected branch assignment'
);
select throws_ok(
  $$ select public.owner_suspend_shop_member('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001') $$,
  '42501', null,
  'owner cannot suspend their own membership'
);
select throws_ok(
  $$ select public.owner_set_member_access('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000099', 'manager', array['30000000-0000-4000-8000-000000000001']::uuid[]) $$,
  '22023', null,
  'owner cannot assign access to an unregistered account'
);
select throws_ok(
  $$ select public.owner_suspend_shop_member('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000003') $$,
  '42501', null,
  'owner cannot suspend a membership in another shop'
);

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000005', true);
select ok(
  public.create_shop_for_current_user('Fictional New Shop') is not null,
  'authenticated user can create a shop through onboarding'
);
select is(
  (select count(*)::integer from public.shop_memberships where user_id = '10000000-0000-4000-8000-000000000005' and role = 'owner' and status = 'active'),
  1,
  'shop onboarding creates an owner membership for the caller'
);
select is(
  (select count(*)::integer from public.branches where shop_id = (select id from public.shops where created_by = '10000000-0000-4000-8000-000000000005') and is_primary),
  1,
  'shop onboarding creates one primary branch'
);

select * from finish();
rollback;
