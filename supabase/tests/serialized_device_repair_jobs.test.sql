begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

-- Fictional tenants, identities, and stock used only by this transaction.
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('d9000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'repair-owner-a@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d9000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'repair-manager-assigned@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d9000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'repair-manager-unassigned@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d9000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'repair-inventory-staff@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d9000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'repair-sales-staff@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d9000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'repair-suspended@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('d9000000-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'repair-owner-b@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.shops (id, name, created_by) values
  ('d9100000-0000-4000-8000-000000000001', 'Fictional Repair Shop A', 'd9000000-0000-4000-8000-000000000001'),
  ('d9100000-0000-4000-8000-000000000002', 'Fictional Repair Shop B', 'd9000000-0000-4000-8000-000000000007');

insert into public.shop_memberships (shop_id, user_id, role, status, created_by) values
  ('d9100000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000001', 'owner', 'active', 'd9000000-0000-4000-8000-000000000001'),
  ('d9100000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000002', 'manager', 'active', 'd9000000-0000-4000-8000-000000000001'),
  ('d9100000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000003', 'manager', 'active', 'd9000000-0000-4000-8000-000000000001'),
  ('d9100000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000004', 'inventory_staff', 'active', 'd9000000-0000-4000-8000-000000000001'),
  ('d9100000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000005', 'sales_staff', 'active', 'd9000000-0000-4000-8000-000000000001'),
  ('d9100000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000006', 'inventory_staff', 'suspended', 'd9000000-0000-4000-8000-000000000001'),
  ('d9100000-0000-4000-8000-000000000002', 'd9000000-0000-4000-8000-000000000007', 'owner', 'active', 'd9000000-0000-4000-8000-000000000007');

insert into public.branches (id, shop_id, name, is_primary, is_active, created_by) values
  ('d9200000-0000-4000-8000-000000000001', 'd9100000-0000-4000-8000-000000000001', 'Repair Main', true, true, 'd9000000-0000-4000-8000-000000000001'),
  ('d9200000-0000-4000-8000-000000000002', 'd9100000-0000-4000-8000-000000000001', 'Repair Restricted', false, true, 'd9000000-0000-4000-8000-000000000001'),
  ('d9200000-0000-4000-8000-000000000003', 'd9100000-0000-4000-8000-000000000001', 'Repair Inactive', false, false, 'd9000000-0000-4000-8000-000000000001'),
  ('d9200000-0000-4000-8000-000000000004', 'd9100000-0000-4000-8000-000000000002', 'Other Shop Repair Main', true, true, 'd9000000-0000-4000-8000-000000000007');

insert into public.branch_memberships (shop_id, branch_id, user_id, created_by) values
  ('d9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000002', 'd9000000-0000-4000-8000-000000000001'),
  ('d9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000004', 'd9000000-0000-4000-8000-000000000001'),
  ('d9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000005', 'd9000000-0000-4000-8000-000000000001'),
  ('d9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000006', 'd9000000-0000-4000-8000-000000000001');

insert into public.shop_settings (shop_id, operating_currency_code, configured_by, updated_by) values
  ('d9100000-0000-4000-8000-000000000001', 'USD', 'd9000000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000001'),
  ('d9100000-0000-4000-8000-000000000002', 'USD', 'd9000000-0000-4000-8000-000000000007', 'd9000000-0000-4000-8000-000000000007');

insert into public.products (id, shop_id, product_type, tracking_mode, name, created_by, updated_by) values
  ('d9300000-0000-4000-8000-000000000001', 'd9100000-0000-4000-8000-000000000001', 'smartphone', 'serialized', 'Fictional repair phones A', 'd9000000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000001'),
  ('d9300000-0000-4000-8000-000000000002', 'd9100000-0000-4000-8000-000000000002', 'smartphone', 'serialized', 'Fictional repair phones B', 'd9000000-0000-4000-8000-000000000007', 'd9000000-0000-4000-8000-000000000007');

insert into public.product_variants (id, shop_id, product_id, attributes, created_by, updated_by) values
  ('d9400000-0000-4000-8000-000000000001', 'd9100000-0000-4000-8000-000000000001', 'd9300000-0000-4000-8000-000000000001', '{"repair_fixture":"known_zero"}'::jsonb, 'd9000000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000001'),
  ('d9400000-0000-4000-8000-000000000002', 'd9100000-0000-4000-8000-000000000001', 'd9300000-0000-4000-8000-000000000001', '{"repair_fixture":"unknown"}'::jsonb, 'd9000000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000001'),
  ('d9400000-0000-4000-8000-000000000003', 'd9100000-0000-4000-8000-000000000001', 'd9300000-0000-4000-8000-000000000001', '{"repair_fixture":"pending_fx"}'::jsonb, 'd9000000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000001'),
  ('d9400000-0000-4000-8000-000000000004', 'd9100000-0000-4000-8000-000000000001', 'd9300000-0000-4000-8000-000000000001', '{"repair_fixture":"restricted_branch"}'::jsonb, 'd9000000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000001'),
  ('d9400000-0000-4000-8000-000000000005', 'd9100000-0000-4000-8000-000000000002', 'd9300000-0000-4000-8000-000000000002', '{"repair_fixture":"other_shop"}'::jsonb, 'd9000000-0000-4000-8000-000000000007', 'd9000000-0000-4000-8000-000000000007');

insert into public.serialized_inventory (
  id, shop_id, branch_id, variant_id, availability_status,
  valuation_status, valuation_currency_code, unit_cost_shop, created_by, updated_by
) values
  ('d9500000-0000-4000-8000-000000000001', 'd9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001', 'd9400000-0000-4000-8000-000000000001', 'available', 'known_cost', 'USD', 0, 'd9000000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000001'),
  ('d9500000-0000-4000-8000-000000000002', 'd9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001', 'd9400000-0000-4000-8000-000000000001', 'available', 'known_cost', 'USD', 0, 'd9000000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000001'),
  ('d9500000-0000-4000-8000-000000000003', 'd9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001', 'd9400000-0000-4000-8000-000000000002', 'available', 'unknown_cost', 'USD', null, 'd9000000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000001'),
  ('d9500000-0000-4000-8000-000000000004', 'd9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001', 'd9400000-0000-4000-8000-000000000003', 'pending_fx', 'pending_fx', 'USD', null, 'd9000000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000001'),
  ('d9500000-0000-4000-8000-000000000005', 'd9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000002', 'd9400000-0000-4000-8000-000000000004', 'available', 'known_cost', 'USD', 5, 'd9000000-0000-4000-8000-000000000001', 'd9000000-0000-4000-8000-000000000001'),
  ('d9500000-0000-4000-8000-000000000006', 'd9100000-0000-4000-8000-000000000002', 'd9200000-0000-4000-8000-000000000004', 'd9400000-0000-4000-8000-000000000005', 'available', 'known_cost', 'USD', 5, 'd9000000-0000-4000-8000-000000000007', 'd9000000-0000-4000-8000-000000000007');

insert into public.serialized_identifiers (
  shop_id, branch_id, serialized_inventory_id, identifier_type,
  raw_value, is_primary, created_by
) values
  ('d9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001', 'd9500000-0000-4000-8000-000000000001', 'imei1', '111111111111111', true, 'd9000000-0000-4000-8000-000000000001'),
  ('d9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001', 'd9500000-0000-4000-8000-000000000002', 'imei1', '111111111111112', true, 'd9000000-0000-4000-8000-000000000001'),
  ('d9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001', 'd9500000-0000-4000-8000-000000000003', 'imei1', '111111111111113', true, 'd9000000-0000-4000-8000-000000000001'),
  ('d9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001', 'd9500000-0000-4000-8000-000000000004', 'imei1', '111111111111114', true, 'd9000000-0000-4000-8000-000000000001'),
  ('d9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000002', 'd9500000-0000-4000-8000-000000000005', 'imei1', '111111111111115', true, 'd9000000-0000-4000-8000-000000000001'),
  ('d9100000-0000-4000-8000-000000000002', 'd9200000-0000-4000-8000-000000000004', 'd9500000-0000-4000-8000-000000000006', 'imei1', '111111111111116', true, 'd9000000-0000-4000-8000-000000000007');

insert into public.inventory_balances (
  shop_id, branch_id, variant_id, valuation_status, valuation_currency_code,
  on_hand_qty, available_qty, carrying_value_shop, average_unit_cost_shop, updated_by
) values
  ('d9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001', 'd9400000-0000-4000-8000-000000000001', 'known_cost', 'USD', 2, 2, 0, 0, 'd9000000-0000-4000-8000-000000000001'),
  ('d9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001', 'd9400000-0000-4000-8000-000000000002', 'unknown_cost', 'USD', 1, 1, null, null, 'd9000000-0000-4000-8000-000000000001'),
  ('d9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001', 'd9400000-0000-4000-8000-000000000003', 'pending_fx', 'USD', 1, 0, null, null, 'd9000000-0000-4000-8000-000000000001'),
  ('d9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000002', 'd9400000-0000-4000-8000-000000000004', 'known_cost', 'USD', 1, 1, 5, 5, 'd9000000-0000-4000-8000-000000000001'),
  ('d9100000-0000-4000-8000-000000000002', 'd9200000-0000-4000-8000-000000000004', 'd9400000-0000-4000-8000-000000000005', 'known_cost', 'USD', 1, 1, 5, 5, 'd9000000-0000-4000-8000-000000000007');

insert into public.exchange_rate_snapshots (
  id, from_currency_code, to_currency_code, rate_to_currency,
  rate_source, observed_at, fetched_at, valid_until
) values (
  'd9910000-0000-4000-8000-000000000001', 'EUR', 'USD', 1.2,
  'fictional repair FX source', now() - interval '1 minute', now(), now() + interval '1 day'
), (
  'd9910000-0000-4000-8000-000000000002', 'EUR', 'USD', 1.3,
  'fictional expired repair FX source', now() - interval '2 days',
  now() - interval '2 days', now() - interval '1 day'
);

create temporary table repair_test_results (
  name text primary key,
  job_id uuid,
  case_id uuid,
  incident_id uuid,
  expected_version bigint
) on commit drop;
grant select, insert, update on repair_test_results to authenticated;

select ok(
  not has_function_privilege('anon', 'public.create_repair_job(uuid,uuid,uuid,text,text,text,timestamptz,jsonb,text)', 'EXECUTE'),
  'anonymous users cannot execute repair creation'
);
select ok(
  has_function_privilege('authenticated', 'public.create_repair_job(uuid,uuid,uuid,text,text,text,timestamptz,jsonb,text)', 'EXECUTE'),
  'authenticated users can reach repair RPC authorization checks'
);
select ok(
  not has_function_privilege('service_role', 'public.create_repair_job(uuid,uuid,uuid,text,text,text,timestamptz,jsonb,text)', 'EXECUTE'),
  'service_role cannot execute end-user repair RPCs'
);
select ok(
  not has_table_privilege('authenticated', 'public.repair_jobs', 'INSERT')
  and not has_table_privilege('authenticated', 'public.repair_jobs', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.repair_jobs', 'DELETE')
  and not has_table_privilege('authenticated', 'public.repair_jobs', 'TRUNCATE'),
  'authenticated users have no direct repair-job write or truncate privileges'
);
select ok(
  not has_table_privilege('service_role', 'public.repair_jobs', 'INSERT')
  and not has_table_privilege('service_role', 'public.repair_jobs', 'UPDATE')
  and not has_table_privilege('service_role', 'public.repair_jobs', 'DELETE')
  and not has_table_privilege('service_role', 'public.repair_jobs', 'TRUNCATE'),
  'service_role has no direct repair-job write or truncate privileges'
);
select ok(
  not has_table_privilege('authenticated', 'public.repair_job_events', 'INSERT')
  and not has_table_privilege('authenticated', 'public.repair_cost_entries', 'INSERT')
  and not has_table_privilege('service_role', 'public.repair_job_events', 'TRUNCATE')
  and not has_table_privilege('service_role', 'public.repair_cost_entries', 'TRUNCATE'),
  'repair and financial histories cannot be directly written or truncated'
);
select ok(
  not exists (
    select 1 from unnest(array[
      'public.repair_jobs', 'public.repair_operations',
      'public.repair_job_events', 'public.repair_job_custody_episodes',
      'public.repair_cost_entries'
    ]) as protected_table(table_name)
    where has_table_privilege('authenticated', table_name, 'INSERT')
      or has_table_privilege('authenticated', table_name, 'UPDATE')
      or has_table_privilege('authenticated', table_name, 'DELETE')
      or has_table_privilege('authenticated', table_name, 'TRUNCATE')
  ),
  'authenticated users have no direct mutation or truncate privilege on any repair table'
);
select ok(
  not exists (
    select 1 from unnest(array[
      'public.repair_jobs', 'public.repair_operations',
      'public.repair_job_events', 'public.repair_job_custody_episodes',
      'public.repair_cost_entries'
    ]) as protected_table(table_name)
    where has_table_privilege('service_role', table_name, 'INSERT')
      or has_table_privilege('service_role', table_name, 'UPDATE')
      or has_table_privilege('service_role', table_name, 'DELETE')
      or has_table_privilege('service_role', table_name, 'TRUNCATE')
  ),
  'service_role has no direct mutation or truncate privilege on any repair table'
);
select ok(
  (select position('pg_advisory_xact_lock' in lower(function_definition)) > 0
      and position('for update' in lower(function_definition))
        > position('pg_advisory_xact_lock' in lower(function_definition))
      and position('repair_gross_authorization_consumed' in lower(function_definition))
        > position('for update' in lower(function_definition))
   from (
     select pg_get_functiondef(function_row.oid) as function_definition
     from pg_proc as function_row
     join pg_namespace as function_schema
       on function_schema.oid = function_row.pronamespace
     where function_schema.nspname = 'public'
       and function_row.proname = 'record_repair_expense'
   ) as repair_expense_function),
  'expense RPC serializes the repair job before checking gross authorization'
);

-- Owner creates a zero-cost repair; retries return one durable job and reserve once.
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$ insert into repair_test_results (name, job_id) values ('zero', public.create_repair_job(
       'd9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001',
       'd9500000-0000-4000-8000-000000000001', null,
       'Synthetic screen repair', 'Synthetic intake condition', null, '{}'::jsonb,
       'repair-zero-create-01'
     )) $$,
  'Owner can create a repair for an available known-zero device'
);
select is(
  public.create_repair_job(
    'd9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001',
    'd9500000-0000-4000-8000-000000000001', null,
    'Synthetic screen repair', 'Synthetic intake condition', null, '{}'::jsonb,
    'repair-zero-create-01'
  ),
  (select job_id from repair_test_results where name = 'zero'),
  'identical repair creation retry returns the original job'
);
select throws_ok(
  $$ select public.create_repair_job(
       'd9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001',
       'd9500000-0000-4000-8000-000000000001', null,
       'Conflicting fault', 'Synthetic intake condition', null, '{}'::jsonb,
       'repair-zero-create-01'
     ) $$,
  '23505', null, 'a conflicting repair-create retry is rejected'
);
select is(
  (select count(*) from public.repair_jobs where serialized_inventory_id = 'd9500000-0000-4000-8000-000000000001'),
  1::bigint, 'idempotent repair creation creates one job for the device'
);
select is(
  (select (on_hand_qty, available_qty, reserved_repair_qty, carrying_value_shop)
   from public.inventory_balances where branch_id = 'd9200000-0000-4000-8000-000000000001'
     and variant_id = 'd9400000-0000-4000-8000-000000000001'),
  (2, 1, 1, 0::numeric), 'repair reservation reduces availability only and preserves on-hand quantity and zero value'
);
select is(
  (select unit_cost_shop from public.serialized_inventory where id = 'd9500000-0000-4000-8000-000000000001'),
  0::numeric, 'repair reservation preserves a known zero device cost'
);
select is(
  (select count(*) from public.inventory_movements where serialized_inventory_id = 'd9500000-0000-4000-8000-000000000001'),
  0::bigint, 'in-shop repair creation creates no on-hand inventory movement'
);
select throws_ok(
  $$ select public.create_repair_job(
       'd9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001',
       'd9500000-0000-4000-8000-000000000001', null,
       'Second repair claim', 'Synthetic condition', null, '{}'::jsonb,
       'repair-zero-duplicate-01'
     ) $$,
  '23514', null, 'an already reserved device cannot receive a second active repair claim'
);

select lives_ok(
  $$ insert into repair_test_results (name, job_id) values ('followup_parent', public.create_repair_job(
       'd9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001',
       'd9500000-0000-4000-8000-000000000002', 'REPAIR-FOLLOWUP-PARENT',
       'Synthetic intermittent fault', 'Synthetic intake condition', null, '{}'::jsonb,
       'repair-followup-parent-01'
     )) $$,
  'Owner can create a second repair while reserving its own device'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000004', true);
select lives_ok(
  $$ insert into repair_test_results (name, job_id) values ('unknown', public.create_repair_job(
       'd9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001',
       'd9500000-0000-4000-8000-000000000003', 'REPAIR-UNKNOWN-COST',
       'Synthetic unknown-cost repair', 'Synthetic intake condition', null, '{}'::jsonb,
       'repair-unknown-create-01'
     )) $$,
  'assigned Inventory Staff may create a repair for unknown-cost stock'
);
select throws_ok(
  $$ select public.create_repair_job(
       'd9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001',
       'd9500000-0000-4000-8000-000000000004', 'REPAIR-PENDING-FX',
       'Synthetic pending-FX repair', 'Synthetic intake condition', null, '{}'::jsonb,
       'repair-pending-create-01'
     ) $$,
  '23514', null, 'pending-FX inventory cannot enter a repair job'
);
select is(
  (select unit_cost_shop is null from public.serialized_inventory where id = 'd9500000-0000-4000-8000-000000000003'),
  true, 'unknown cost remains NULL after repair reservation'
);
select is(
  (select (on_hand_qty, available_qty, reserved_repair_qty, carrying_value_shop)
   from public.inventory_balances where branch_id = 'd9200000-0000-4000-8000-000000000001'
     and variant_id = 'd9400000-0000-4000-8000-000000000002'),
  (1, 0, 1, null::numeric), 'unknown-cost reservation preserves NULL carrying value'
);

-- Role, branch, tenant, inactive-branch, and suspension denial.
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$ select public.create_repair_job(
       'd9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000002',
       'd9500000-0000-4000-8000-000000000005', null,
       'Unauthorized branch attempt', 'Synthetic condition', null, '{}'::jsonb,
       'repair-unassigned-branch-01'
     ) $$,
  '42501', null, 'a Manager without branch assignment cannot create a repair there'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$ select public.create_repair_job(
       'd9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001',
       'd9500000-0000-4000-8000-000000000005', null,
       'Sales staff attempt', 'Synthetic condition', null, '{}'::jsonb,
       'repair-sales-denial-01'
     ) $$,
  '42501', null, 'Sales Staff cannot mutate repair jobs'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000006', true);
select throws_ok(
  $$ select public.create_repair_job(
       'd9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001',
       'd9500000-0000-4000-8000-000000000005', null,
       'Suspended staff attempt', 'Synthetic condition', null, '{}'::jsonb,
       'repair-suspended-denial-01'
     ) $$,
  '42501', null, 'suspended members cannot mutate repair jobs'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$ select public.create_repair_job(
       'd9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000003',
       'd9500000-0000-4000-8000-000000000005', null,
       'Inactive branch attempt', 'Synthetic condition', null, '{}'::jsonb,
       'repair-inactive-branch-01'
     ) $$,
  '42501', null, 'even Owners cannot create repairs at inactive branches'
);
select throws_ok(
  $$ select public.create_repair_job(
       'd9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000004',
       'd9500000-0000-4000-8000-000000000006', null,
       'Cross-shop branch attempt', 'Synthetic condition', null, '{}'::jsonb,
       'repair-cross-shop-branch-01'
     ) $$,
  '42501', null, 'a branch belonging to another shop is rejected'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000007', true);
select throws_ok(
  $$ select public.create_repair_job(
       'd9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000001',
       'd9500000-0000-4000-8000-000000000001', null,
       'Cross-tenant attempt', 'Synthetic condition', null, '{}'::jsonb,
       'repair-cross-tenant-01'
     ) $$,
  '42501', null, 'an Owner in another shop cannot create a repair'
);

-- Branch-scoped read policies hide other branches and tenants.
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000001', true);
insert into repair_test_results (name, job_id) values ('restricted', public.create_repair_job(
  'd9100000-0000-4000-8000-000000000001', 'd9200000-0000-4000-8000-000000000002',
  'd9500000-0000-4000-8000-000000000005', 'REPAIR-RESTRICTED-BRANCH',
  'Synthetic restricted branch fault', 'Synthetic intake', null, '{}'::jsonb,
  'repair-restricted-owner-01'
));
reset role;
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000002', true);
set local role authenticated;
select is(
  (select count(*) from public.repair_jobs where id = (select job_id from repair_test_results where name = 'restricted')),
  0::bigint, 'a Manager cannot read repair jobs outside assigned branches'
);
select is(
  (select count(*) from public.repair_jobs where id = (select job_id from repair_test_results where name = 'zero')),
  1::bigint, 'an assigned Manager can read repair jobs in an authorized branch'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000007', true);
select is(
  (select count(*) from public.repair_jobs where shop_id = 'd9100000-0000-4000-8000-000000000001'),
  0::bigint, 'another shop Owner cannot read repair jobs across tenants'
);
reset role;

-- Technician history, stale/null version rejection, FX, approval, and expenses.
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$ select public.assign_repair_technician(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 1,
       'internal', 'd9000000-0000-4000-8000-000000000004', null, null,
       'Synthetic internal technician assignment', 'repair-tech-internal-01'
     ) $$,
  'Owner can assign an active staff technician authorized for the branch'
);
select throws_ok(
  $$ select public.assign_repair_technician(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 2,
       'internal', 'd9000000-0000-4000-8000-000000000003', null, null,
       'Synthetic unassigned internal technician', 'repair-tech-unassigned-01'
     ) $$,
  '42501', null, 'an internal technician must be assigned to the repair branch'
);
select throws_ok(
  $$ select public.assign_repair_technician(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 2,
       'internal', 'd9000000-0000-4000-8000-000000000006', null, null,
       'Synthetic suspended internal technician', 'repair-tech-suspended-01'
     ) $$,
  '42501', null, 'a suspended member cannot be assigned as an internal technician'
);
select lives_ok(
  $$ select public.assign_repair_technician(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 2,
       'external', null, 'Synthetic external technician', '555-0199',
       'Synthetic reassignment', 'repair-tech-external-01'
     ) $$,
  'Owner can reassign an external technician with a reason'
);
select is(
  (select count(*) from public.repair_job_events where repair_job_id = (select job_id from repair_test_results where name = 'zero') and event_type = 'technician_assigned'),
  2::bigint, 'technician reassignment appends history instead of overwriting prior evidence'
);
select is(
  public.assign_repair_technician(
    'd9100000-0000-4000-8000-000000000001',
    (select job_id from repair_test_results where name = 'zero'), 1,
    'internal', 'd9000000-0000-4000-8000-000000000004', null, null,
    'Synthetic internal technician assignment', 'repair-tech-internal-01'
  ),
  (select job_id from repair_test_results where name = 'zero'),
  'identical technician assignment retry returns the original job without another event'
);
select throws_ok(
  $$ select public.assign_repair_technician(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 1,
       'internal', 'd9000000-0000-4000-8000-000000000004', null, null,
       'Conflicting technician reason', 'repair-tech-internal-01'
     ) $$,
  '23505', null, 'a conflicting technician retry is rejected'
);
select throws_ok(
  $$ select public.update_repair_diagnosis(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), null,
       'Synthetic diagnosis', null, '{}'::jsonb, 'repair-null-version-01'
     ) $$,
  '40001', null, 'a NULL expected version cannot bypass optimistic concurrency'
);
select throws_ok(
  $$ select public.update_repair_diagnosis(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 1,
       'Synthetic diagnosis', 'completed', '{}'::jsonb, 'repair-invalid-transition-01'
     ) $$,
  '23514', null, 'diagnosis cannot silently complete a repair'
);
select throws_ok(
  $$ select public.update_repair_diagnosis(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 3,
       'Synthetic diagnosis', 'returned_pending_inspection', '{}'::jsonb,
       'repair-fake-return-transition-01'
     ) $$,
  '23514', null, 'diagnosis cannot claim a physical custody return'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000004', true);
select lives_ok(
  $$ select public.update_repair_diagnosis(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 3,
       'Synthetic board diagnosis', 'diagnosing', '{"evidence":"synthetic-test"}'::jsonb,
       'repair-diagnosis-01'
     ) $$,
  'assigned Inventory Staff can record diagnosis and progress state'
);
select throws_ok(
  $$ select public.submit_repair_estimate(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 4,
       10.001, 'USD', '{}'::jsonb, null, null, null, null, null, null,
       'repair-invalid-precision-01'
     ) $$,
  '22023', null, 'repair amounts must respect the original currency minor units'
);
select throws_ok(
  $$ select public.submit_repair_estimate(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 4,
       10, 'EUR', '{}'::jsonb, null, null, 1.2, 'unapproved staff override',
       now(), 'Synthetic reason long enough', 'repair-staff-manual-fx-01'
     ) $$,
  '42501', null, 'Inventory Staff cannot accept a manual FX override'
);
select lives_ok(
  $$ select public.submit_repair_estimate(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 4,
       10, 'EUR', '{"quote":"synthetic"}'::jsonb, 'SYNTHETIC-QUOTE-1',
       null, null, null, null, null, 'repair-estimate-pending-fx-01'
     ) $$,
  'Inventory Staff may submit foreign-currency estimates without inventing FX'
);
reset role;
select is(
  (select (fx_status, converted_shop_amount) from public.repair_cost_entries where repair_job_id = (select job_id from repair_test_results where name = 'zero') and entry_type = 'estimate'),
  ('pending'::text, null::numeric), 'missing estimate FX leaves the shop equivalent unavailable'
);
select is(
  (select count(*) from public.repair_cost_entries where repair_job_id = (select job_id from repair_test_results where name = 'zero')),
  1::bigint, 'failed precision and manual-FX writes leave no partial financial entries'
);
set local role authenticated;
select is(
  (select count(*) from public.repair_cost_entries where repair_job_id = (select job_id from repair_test_results where name = 'zero')),
  0::bigint, 'Inventory Staff cannot read Owner/Manager-only repair financial details'
);
reset role;

select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000004', true);
set local role authenticated;
select throws_ok(
  $$ select public.approve_repair_spend(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 5,
       10, 'EUR', 'Synthetic approval', '{}'::jsonb,
       'd9910000-0000-4000-8000-000000000001', null, null, null, null,
       'repair-staff-spend-approval-01'
     ) $$,
  '42501', null, 'Inventory Staff cannot approve repair spending'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000002', true);
select lives_ok(
  $$ select public.approve_repair_spend(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 5,
       10, 'EUR', 'Synthetic approved limit', '{"quote":"synthetic"}'::jsonb,
       'd9910000-0000-4000-8000-000000000001', null, null, null, null,
       'repair-manager-approve-system-fx-01'
     ) $$,
  'assigned Manager can approve shop spending using a current system rate'
);
select is(
  (select (fx_status, converted_shop_amount, rate_source, rate_snapshot_id)
   from public.repair_cost_entries where repair_job_id = (select job_id from repair_test_results where name = 'zero')
     and entry_type = 'approved_limit'),
  ('accepted'::text, 12::numeric, 'fictional repair FX source'::text, 'd9910000-0000-4000-8000-000000000001'::uuid),
  'approved limit stores exact shop-currency conversion and system-rate evidence'
);
select is(
  (select count(*) from public.repair_cost_entries where repair_job_id = (select job_id from repair_test_results where name = 'zero')),
  2::bigint, 'approval adds one durable financial evidence entry'
);

select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$ select public.record_repair_expense(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 6,
       13, 'USD', 'shop', '{}'::jsonb, null, null, null, null, null,
       null, null, null, 'repair-expense-over-limit-01'
     ) $$,
  '23514', null, 'shop-borne actual expense above the approved limit is rejected'
);
select lives_ok(
  $$ select public.record_repair_expense(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 6,
       2.50, 'USD', 'shop', '{"invoice":"SYNTHETIC-REPAIR-1"}'::jsonb,
       'SYNTHETIC-REPAIR-1', null, null, null, null, null,
       null, null, 'repair-expense-actual-01'
     ) $$,
  'assigned Inventory Staff may submit an actual expense within an approved limit'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$ select public.record_repair_expense(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 7,
        -1, 'USD', 'other', '{}'::jsonb, null, null, null, null, null,
        null,
        (select id from public.repair_cost_entries where repair_job_id = (select job_id from repair_test_results where name = 'zero') and entry_type = 'actual'),
       'Synthetic mismatched correction', 'repair-expense-mismatch-correction-01'
     ) $$,
  '23514', null, 'expense corrections must retain the original cost bearer and currency'
);
select lives_ok(
  $$ select public.record_repair_expense(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 7,
       -1, 'USD', 'shop', '{"reversal":"synthetic"}'::jsonb, 'SYNTHETIC-REPAIR-1',
       null, null, null, null, null,
       (select id from public.repair_cost_entries where repair_job_id = (select job_id from repair_test_results where name = 'zero') and entry_type = 'actual' and invoice_reference = 'SYNTHETIC-REPAIR-1'),
       'Synthetic partial reversal', 'repair-expense-correction-01'
     ) $$,
  'a correction is appended with an explicit reason and links to the replaced expense'
);
select is(
  public.record_repair_expense(
    'd9100000-0000-4000-8000-000000000001',
    (select job_id from repair_test_results where name = 'zero'), 7,
    -1, 'USD', 'shop', '{"reversal":"synthetic"}'::jsonb, 'SYNTHETIC-REPAIR-1',
    null, null, null, null, null,
    (select id from public.repair_cost_entries where repair_job_id = (select job_id from repair_test_results where name = 'zero') and entry_type = 'actual'),
    'Synthetic partial reversal', 'repair-expense-correction-01'
  ),
  (select job_id from repair_test_results where name = 'zero'),
  'identical correction retry returns the original job without appending another correction'
);
select is(
  (select count(*) from public.repair_cost_entries
   where repair_job_id = (select job_id from repair_test_results where name = 'zero')
     and entry_type = 'correction'),
  1::bigint, 'idempotent correction retry leaves exactly one correction record'
);
reset role;
select is(
  (select sum(converted_shop_amount) from public.repair_cost_entries
   where repair_job_id = (select job_id from repair_test_results where name = 'zero')
     and cost_bearer = 'shop' and entry_type in ('actual', 'correction')),
  1.50::numeric, 'signed correction reconciles the net shop-borne expense'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000004', true);
set local role authenticated;
select throws_ok(
  $$ select public.record_repair_expense(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 8,
       10, 'USD', 'shop', '{"invoice":"SYNTHETIC-REPAIR-2"}'::jsonb,
       'SYNTHETIC-REPAIR-2', null, null, null, null, null,
       null, null, 'repair-expense-over-gross-after-correction-01'
     ) $$,
  '23514', null,
  'a negative correction reduces net cost but does not restore gross spending authorization'
);
reset role;
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000002', true);
set local role authenticated;
select lives_ok(
  $$ select public.submit_repair_estimate(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 8,
       15, 'USD', '{"quote":"SYNTHETIC-REPAIR-2"}'::jsonb,
       'SYNTHETIC-REPAIR-2', null, null, null, null, null,
       'repair-expense-additional-estimate-01'
     ) $$,
  'Manager may submit a revised estimate for additional gross authorization'
);
select lives_ok(
  $$ select public.approve_repair_spend(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'),
       (select version from public.repair_jobs where id = (select job_id from repair_test_results where name = 'zero')),
       15, 'USD', 'Synthetic additional gross authorization',
       '{"approval":"SYNTHETIC-REPAIR-2"}'::jsonb,
       null, null, null, null, null,
       'repair-expense-additional-approval-01'
     ) $$,
  'Manager can explicitly increase the cumulative gross spending authorization'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000004', true);
select lives_ok(
  $$ select public.record_repair_expense(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 10,
       12.50, 'USD', 'shop', '{"invoice":"SYNTHETIC-REPAIR-2"}'::jsonb,
       'SYNTHETIC-REPAIR-2', null, null, null, null, null,
       null, null, 'repair-expense-additional-actual-01'
     ) $$,
  'additional spending succeeds only after Owner or Manager approval increases the gross authorization'
);
reset role;
select is(
  private.repair_gross_authorization_consumed(
    'd9100000-0000-4000-8000-000000000001',
    (select job_id from repair_test_results where name = 'zero')
  ),
  15::numeric, 'gross authorization consumption includes actual spend and ignores negative corrections'
);
select is(
  (select sum(converted_shop_amount) from public.repair_cost_entries
   where repair_job_id = (select job_id from repair_test_results where name = 'zero')
     and cost_bearer = 'shop' and entry_type in ('actual', 'correction')),
  14::numeric, 'net financial evidence still includes the signed correction'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000004', true);
set local role authenticated;
select is(
  (select count(*) from public.repair_cost_entries
   where repair_job_id = (select job_id from repair_test_results where name = 'zero')),
  0::bigint, 'Inventory Staff cannot read repair cost entries after financial records exist'
);
reset role;
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000002', true);
set local role authenticated;
select throws_ok(
  $$ select public.record_repair_expense(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 11,
       -15, 'USD', 'shop', '{}'::jsonb, null, null, null, null, null,
       null, (select id from public.repair_cost_entries where repair_job_id = (select job_id from repair_test_results where name = 'zero') and entry_type = 'correction'),
       'Synthetic excessive reversal', 'repair-expense-over-reversal-01'
     ) $$,
  '23514', null, 'a correction cannot reduce total shop-borne expenses below zero'
);
select throws_ok(
  $$ select public.record_repair_expense(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 11,
       -1, 'USD', 'shop', '{}'::jsonb, null, null, null, null, null,
       null, (select id from public.repair_cost_entries where repair_job_id = (select job_id from repair_test_results where name = 'zero') and entry_type = 'actual' and invoice_reference = 'SYNTHETIC-REPAIR-1'),
       'Duplicate correction', 'repair-expense-correction-duplicate-01'
     ) $$,
  '23514', null, 'one expense entry cannot be superseded by multiple corrections'
);
reset role;
select is(
  (select count(*) from public.repair_job_events where repair_job_id = (select job_id from repair_test_results where name = 'zero') and event_type = 'expense_recorded'),
  3::bigint, 'successful expense and correction writes each have one audit event'
);
select is(
  (select count(*) from public.repair_operations
   where idempotency_key = any(array[
       'repair-expense-over-limit-01',
       'repair-expense-mismatch-correction-01',
       'repair-expense-over-gross-after-correction-01',
       'repair-expense-over-reversal-01',
       'repair-expense-correction-duplicate-01',
       'repair-staff-completion-financial-key-01',
       'repair-staff-completion-nested-financial-01'
     ]::text[])),
  0::bigint, 'rejected expense and correction requests leave no repair_operations residue'
);
set local role authenticated;
select throws_ok(
  $$ select public.update_repair_progress(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 10,
       'Stale progress attempt', 'in_progress', '{}'::jsonb,
       'repair-stale-version-01'
     ) $$,
  '40001', null, 'a stale repair version cannot overwrite newer state'
);
select lives_ok(
  $$ select public.update_repair_progress(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 11,
       'Synthetic repair work started', 'in_progress', '{}'::jsonb,
       'repair-progress-01'
     ) $$,
  'assigned Inventory Staff can record repair progress'
);
select is(
  (select status from public.repair_jobs where id = (select job_id from repair_test_results where name = 'zero')),
  'in_progress', 'valid progress records the requested workflow state'
);
select is(
  (select count(*) from public.inventory_movements where serialized_inventory_id = 'd9500000-0000-4000-8000-000000000001'),
  0::bigint, 'diagnosis, estimates, approvals, and progress create no inventory movements'
);
reset role;

-- Manual FX must be accepted by an Owner/Manager and must retain its evidence.
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000002', true);
set local role authenticated;
select lives_ok(
  $$ select public.update_repair_diagnosis(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'followup_parent'), 1,
       'Synthetic follow-up diagnosis', 'diagnosing', '{}'::jsonb,
       'repair-followup-diagnosis-01'
     ) $$,
  'assigned Manager can diagnose a second repair'
);
select throws_ok(
  $$ select public.submit_repair_estimate(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'followup_parent'), 2,
       5, 'EUR', '{}'::jsonb, null, null, 1.25, 'fictional manual source',
       now() + interval '1 day', 'Future observation rejected safely',
       'repair-manual-fx-future-01'
     ) $$,
  '42501', null, 'future manual FX observations are rejected'
);
select throws_ok(
  $$ select public.submit_repair_estimate(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'followup_parent'), 2,
       5, 'EUR', '{}'::jsonb, null,
       'd9910000-0000-4000-8000-000000000002', null, null, null, null,
       'repair-expired-system-fx-01'
     ) $$,
  '23514', null, 'an expired system FX snapshot cannot price a repair estimate'
);
select lives_ok(
  $$ select public.submit_repair_estimate(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'followup_parent'), 2,
       5, 'EUR', '{"quote":"synthetic"}'::jsonb, null, null, 1.25,
       'fictional manual source', now() - interval '1 minute',
       'Synthetic manual rate approval evidence', 'repair-manual-fx-estimate-01'
     ) $$,
  'Manager may accept a documented manual FX rate for an estimate'
);
select is(
  (select (converted_shop_amount, rate_source, manual_rate_approved_by)
   from public.repair_cost_entries where repair_job_id = (select job_id from repair_test_results where name = 'followup_parent') and entry_type = 'estimate'),
  (6.25::numeric, 'fictional manual source'::text, 'd9000000-0000-4000-8000-000000000002'::uuid),
  'manual FX estimate records the accepted shop equivalent, source, and approver'
);
select lives_ok(
  $$ select public.approve_repair_spend(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'followup_parent'), 3,
       5, 'EUR', 'Synthetic follow-up spending approval', '{}'::jsonb,
       null, 1.25, 'fictional manual source', now() - interval '1 minute',
       'Synthetic approval evidence for manual FX', 'repair-manual-fx-approval-01'
     ) $$,
  'Owner or Manager can explicitly approve a manual-FX shop spending limit'
);
select lives_ok(
  $$ select public.update_repair_progress(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'followup_parent'), 4,
       'Synthetic repair work started', 'in_progress', '{}'::jsonb,
       'repair-followup-parent-progress-01'
     ) $$,
  'the approved repair may enter progress'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$ select public.mark_repair_unrepairable(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'followup_parent'), 5,
       'Synthetic unrepairable outcome', '{"inspection_result":"synthetic"}'::jsonb,
       'repair-staff-unrepairable-denied-01'
     ) $$,
  '42501', null, 'Inventory Staff cannot authorize an unrepairable disposition'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000002', true);
select lives_ok(
  $$ select public.mark_repair_unrepairable(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'followup_parent'), 5,
       'Synthetic unrepairable outcome', '{"inspection_result":"synthetic"}'::jsonb,
       'repair-followup-unrepairable-01'
     ) $$,
  'Manager can mark a physically returned repair unrepairable with evidence'
);
select is(
  (select (status, device_claim_active) from public.repair_jobs where id = (select job_id from repair_test_results where name = 'followup_parent')),
  ('unrepairable'::text, true), 'unrepairable device remains shop-owned and actively reserved'
);
select throws_ok(
  $$ select public.cancel_repair_job(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'followup_parent'), 6,
       'Attempt to release unrepairable hold', 'repair-unrepairable-cancel-denied-01'
     ) $$,
  '40001', null, 'an unrepairable repair cannot be cancelled to release stock'
);
select lives_ok(
  $$ insert into repair_test_results (name, job_id) values ('followup_child', public.create_follow_up_repair(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'followup_parent'), 6,
       'REPAIR-FOLLOWUP-CHILD', 'Synthetic follow-up fault',
       'Synthetic follow-up intake', null, 'Explicit follow-up after inspection',
       'repair-followup-handoff-01'
     )) $$,
  'authorized Manager atomically hands the same repair reservation to a linked follow-up job'
);
select is(
  (select (status, device_claim_active, follow_up_from_job_id)
   from public.repair_jobs where id = (select job_id from repair_test_results where name = 'followup_child')),
  ('open'::text, true, (select job_id from repair_test_results where name = 'followup_parent')),
  'follow-up keeps original device identity and links the prior job'
);
select is(
  (select (status, device_claim_active) from public.repair_jobs where id = (select job_id from repair_test_results where name = 'followup_parent')),
  ('closed'::text, false), 'prior unrepairable job remains as immutable closed history'
);
select is(
  (select (on_hand_qty, available_qty, reserved_repair_qty, carrying_value_shop)
   from public.inventory_balances where branch_id = 'd9200000-0000-4000-8000-000000000001'
     and variant_id = 'd9400000-0000-4000-8000-000000000001'),
  (2, 0, 2, 0::numeric), 'follow-up handoff preserves both active repair holds without changing on-hand quantity or value'
);
select is(
  public.create_follow_up_repair(
    'd9100000-0000-4000-8000-000000000001',
    (select job_id from repair_test_results where name = 'followup_parent'), 6,
    'REPAIR-FOLLOWUP-CHILD', 'Synthetic follow-up fault',
    'Synthetic follow-up intake', null, 'Explicit follow-up after inspection',
    'repair-followup-handoff-01'
  ),
  (select job_id from repair_test_results where name = 'followup_child'),
  'identical follow-up retry returns the existing child after parent closure'
);
select throws_ok(
  $$ select public.create_follow_up_repair(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'followup_parent'), 6,
       'REPAIR-FOLLOWUP-CHILD', 'Changed follow-up fault',
       'Synthetic follow-up intake', null, 'Explicit follow-up after inspection',
       'repair-followup-handoff-01'
     ) $$,
  '23505', null, 'conflicting follow-up idempotency payload is rejected'
);
reset role;

-- External technician custody uses the existing custody movements and retains the repair hold.
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000004', true);
set local role authenticated;
select lives_ok(
  $$ insert into repair_test_results (name, case_id) values ('custody', public.request_repair_custody(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 12,
       'Synthetic repair technician', '555-0123', '2099-01-01T00:00:00Z',
       'Synthetic external repair work', 'repair-custody-request-01'
     )) $$,
  'assigned staff can request external custody without releasing the repair reservation'
);
select is(
  (select (available_qty, reserved_repair_qty, reserved_custody_qty)
   from public.inventory_balances where branch_id = 'd9200000-0000-4000-8000-000000000001'
     and variant_id = 'd9400000-0000-4000-8000-000000000001'),
  (0, 2, 0), 'a requested custody episode does not release either active repair hold'
);
select is(
  public.request_repair_custody(
    'd9100000-0000-4000-8000-000000000001',
    (select job_id from repair_test_results where name = 'zero'),
    12,
    'Synthetic repair technician', '555-0123', '2099-01-01T00:00:00Z',
    'Synthetic external repair work', 'repair-custody-request-01'
  ),
  (select case_id from repair_test_results where name = 'custody'),
  'identical repair-custody retry returns the original case'
);
select throws_ok(
  $$ select public.request_repair_custody(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'),
       12,
       'Synthetic repair technician', '555-0123', '2099-01-01T00:00:00Z',
       'Conflicting custody reason', 'repair-custody-request-01'
     ) $$,
  '23505', null, 'conflicting repair-custody retry payload is rejected'
);
select is(
  (select count(*) from public.repair_job_custody_episodes
   where repair_job_id = (select job_id from repair_test_results where name = 'zero')),
  1::bigint, 'repair-custody retries do not create duplicate custody episodes'
);
reset role;
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000002', true);
set local role authenticated;
select lives_ok(
  $$ select public.approve_inventory_custody(
       'd9100000-0000-4000-8000-000000000001',
       (select case_id from repair_test_results where name = 'custody'), 1,
       'repair-custody-approve-01'
     ) $$,
  'authorized Manager approves repair-linked custody through the protected custody RPC'
);
select is(
  (select (reserved_repair_qty, reserved_custody_qty)
   from public.inventory_balances where branch_id = 'd9200000-0000-4000-8000-000000000001'
     and variant_id = 'd9400000-0000-4000-8000-000000000001'),
  (1, 1), 'custody approval transfers this device hold atomically while retaining the other repair hold'
);
reset role;
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000004', true);
set local role authenticated;
select lives_ok(
  $$ select public.handover_inventory_custody(
       'd9100000-0000-4000-8000-000000000001',
       (select case_id from repair_test_results where name = 'custody'), 2,
       jsonb_build_array(jsonb_build_object(
         'item_id', (select id from public.inventory_custody_items where case_id = (select case_id from repair_test_results where name = 'custody')),
         'condition', 'Synthetic device condition before repair'
       )), 'repair-custody-handover-01'
     ) $$,
  'external repair technician handover uses existing authorized custody controls'
);
select is(
  (select custody_state from public.serialized_inventory where id = 'd9500000-0000-4000-8000-000000000001'),
  'handed_over', 'external handover changes custody state but retains original device identity'
);
select lives_ok(
  $$ insert into repair_test_results (name, incident_id) values ('incident', public.report_custody_incident(
       'd9100000-0000-4000-8000-000000000001',
       (select case_id from repair_test_results where name = 'custody'),
       (select id from public.inventory_custody_items where case_id = (select case_id from repair_test_results where name = 'custody')),
       (select version from public.inventory_custody_cases where id = (select case_id from repair_test_results where name = 'custody')),
       'damage', 'Synthetic return damage observation', '{"inspection":"synthetic"}'::jsonb,
       'repair-custody-incident-01'
     )) $$,
  'staff can report a repair custody incident with synthetic evidence'
);
insert into repair_test_results (name, case_id, expected_version)
select 'return_version', case_row.id, case_row.version
from public.inventory_custody_cases as case_row
where case_row.id = (select case_id from repair_test_results where name = 'custody');
select lives_ok(
  $$ select public.return_inventory_custody(
       'd9100000-0000-4000-8000-000000000001',
       (select case_id from repair_test_results where name = 'custody'),
       (select expected_version from repair_test_results where name = 'return_version'),
       jsonb_build_array(jsonb_build_object(
         'item_id', (select id from public.inventory_custody_items where case_id = (select case_id from repair_test_results where name = 'custody')),
         'condition', 'Synthetic returned device awaiting repair inspection'
       )), 'repair-custody-return-01'
     ) $$,
  'returned repair device is physically restored and remains quarantined while its incident is open'
);
select is(
  public.return_inventory_custody(
    'd9100000-0000-4000-8000-000000000001',
    (select case_id from repair_test_results where name = 'custody'),
    (select expected_version from repair_test_results where name = 'return_version'),
    jsonb_build_array(jsonb_build_object(
      'item_id', (select id from public.inventory_custody_items where case_id = (select case_id from repair_test_results where name = 'custody')),
      'condition', 'Synthetic returned device awaiting repair inspection'
    )), 'repair-custody-return-01'
  ),
  (select case_id from repair_test_results where name = 'custody'),
  'identical custody-return retry replays the original return after retaining the repair hold'
);
select is(
  (select (availability_status::text, custody_state::text) from public.serialized_inventory where id = 'd9500000-0000-4000-8000-000000000001'),
  ('reserved'::text, 'returned_quarantine'::text), 'an unresolved incident keeps a returned device unavailable'
);
select is(
  (select status from public.repair_jobs where id = (select job_id from repair_test_results where name = 'zero')),
  'returned_pending_inspection', 'custody return does not complete the repair'
);
select is(
  (select (reserved_custody_qty, reserved_repair_qty, available_qty)
   from public.inventory_balances where branch_id = 'd9200000-0000-4000-8000-000000000001'
     and variant_id = 'd9400000-0000-4000-8000-000000000001'),
  (1, 1, 0), 'quarantined return remains reserved alongside the other repair hold and unavailable pending incident resolution'
);
select throws_ok(
  $$ select public.complete_repair_job(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'),
       (select version from public.repair_jobs where id = (select job_id from repair_test_results where name = 'zero')),
       '{"inspection_result":"premature"}'::jsonb, 'repair-premature-complete-01'
     ) $$,
  '23514', null, 'an unresolved custody incident prevents repair completion'
);
reset role;

select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000002', true);
set local role authenticated;
select lives_ok(
  $$ select public.resolve_custody_incident(
       'd9100000-0000-4000-8000-000000000001',
       (select incident_id from repair_test_results where name = 'incident'),
       (select version from public.inventory_custody_cases where id = (select case_id from repair_test_results where name = 'custody')),
       (select version from public.inventory_custody_incidents where id = (select incident_id from repair_test_results where name = 'incident')),
       'cleared_no_value_change', '{"review":"synthetic"}'::jsonb,
       'repair-custody-incident-resolve-01'
     ) $$,
  'authorized Manager resolves a nonfinancial custody incident after physical return'
);
select is(
  (select (custody_state::text, availability_status::text) from public.serialized_inventory where id = 'd9500000-0000-4000-8000-000000000001'),
  ('none'::text, 'reserved'::text), 'incident resolution restores the device to the active repair hold, not availability'
);
select is(
  (select (reserved_custody_qty, reserved_repair_qty, available_qty)
   from public.inventory_balances where branch_id = 'd9200000-0000-4000-8000-000000000001'
     and variant_id = 'd9400000-0000-4000-8000-000000000001'),
  (0, 2, 0), 'incident resolution transfers quarantine back to repair without an available-stock interval'
);
select is(
  (select count(*) from public.inventory_movements where custody_item_id = (select id from public.inventory_custody_items where case_id = (select case_id from repair_test_results where name = 'custody')) and movement_type in ('custody_out', 'custody_return')),
  2::bigint, 'external handover and return use exactly one movement each'
);
select is(
  (select count(*) from public.inventory_movements where serialized_inventory_id = 'd9500000-0000-4000-8000-000000000001' and movement_type = 'sale'),
  0::bigint, 'repair custody and incident resolution create no sale or COGS movement'
);
select is(
  (select count(*) from public.repair_job_events where repair_job_id = (select job_id from repair_test_results where name = 'zero') and event_type = 'repair_hold_retained'),
  2::bigint, 'custody return and incident resolution append repair-hold evidence'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$ select public.complete_repair_job(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'),
       (select version from public.repair_jobs where id = (select job_id from repair_test_results where name = 'zero')),
       '{"expense_amount":"100.00"}'::jsonb,
       'repair-staff-completion-financial-key-01'
     ) $$,
  '23514', null, 'completion evidence rejects unapproved financial keys'
);
select throws_ok(
  $$ select public.complete_repair_job(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'),
       (select version from public.repair_jobs where id = (select job_id from repair_test_results where name = 'zero')),
       '{"technician_notes":{"supplier_invoice":{"total":100,"currency":"USD"}}}'::jsonb,
       'repair-staff-completion-nested-financial-01'
     ) $$,
  '23514', null, 'completion evidence rejects nested financial structures'
);
select lives_ok(
  $$ select public.complete_repair_job(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'),
       (select version from public.repair_jobs where id = (select job_id from repair_test_results where name = 'zero')),
       '{"work_performed":"Replaced test component","inspection_result":"Passed synthetic inspection","functional_testing":"Synthetic power-on test passed","technician_notes":"Fictional test notes","device_condition":"Returned in working condition"}'::jsonb,
       'repair-staff-completion-submit-01'
     ) $$,
  'Inventory Staff can submit completion evidence for Owner/Manager review'
);
select is(
  (select (status, completion_submitted_at is not null, completed_at is null)
   from public.repair_jobs where id = (select job_id from repair_test_results where name = 'zero')),
  ('returned_pending_inspection'::text, true, true), 'staff evidence submission does not itself mark a repair complete'
);
select ok(
  not ((select completion_evidence ?| array['expense_amount', 'payment_information', 'supplier_invoice', 'fx_rate']
        from public.repair_jobs where id = (select job_id from repair_test_results where name = 'zero'))),
  'stored completion evidence contains no recognized financial fields'
);
reset role;
select throws_ok(
  $$ update public.repair_jobs
     set completion_evidence = '{"payment_information":"synthetic"}'::jsonb,
         version = version + 1,
         updated_at = clock_timestamp(),
         updated_by = 'd9000000-0000-4000-8000-000000000001'
     where id = (select job_id from repair_test_results where name = 'zero') $$,
  '23514', null, 'the table constraint independently rejects financial completion evidence'
);

select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$ select public.complete_repair_job(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'),
       (select version from public.repair_jobs where id = (select job_id from repair_test_results where name = 'zero')),
       '{"inspection_result":"Owner review passed"}'::jsonb,
       'repair-owner-completion-01'
     ) $$,
  'Owner completes a returned repair after inspection and incident resolution'
);
select is(
  (select (status, device_claim_active) from public.repair_jobs where id = (select job_id from repair_test_results where name = 'zero')),
  ('completed'::text, false), 'completed job releases its active device claim'
);
select is(
  (select (on_hand_qty, available_qty, reserved_repair_qty, carrying_value_shop)
   from public.inventory_balances where branch_id = 'd9200000-0000-4000-8000-000000000001'
     and variant_id = 'd9400000-0000-4000-8000-000000000001'),
  (2, 1, 1, 0::numeric), 'completion releases only its repair reservation and preserves zero carrying value'
);
select is(
  (select unit_cost_shop from public.serialized_inventory where id = 'd9500000-0000-4000-8000-000000000001'),
  0::numeric, 'completion preserves the original known-zero device cost'
);
select is(
  (select count(*) from public.inventory_movements where serialized_inventory_id = 'd9500000-0000-4000-8000-000000000001'),
  2::bigint, 'only custody handover and return add movements; repair progress and completion add none'
);
reset role;

-- A retry after job completion remains idempotent and cannot alter custody history.
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000004', true);
set local role authenticated;
select is(
  public.return_inventory_custody(
    'd9100000-0000-4000-8000-000000000001',
    (select case_id from repair_test_results where name = 'custody'),
    (select expected_version from repair_test_results where name = 'return_version'),
    jsonb_build_array(jsonb_build_object(
      'item_id', (select id from public.inventory_custody_items where case_id = (select case_id from repair_test_results where name = 'custody')),
      'condition', 'Synthetic returned device awaiting repair inspection'
    )), 'repair-custody-return-01'
  ),
  (select case_id from repair_test_results where name = 'custody'),
  'identical return replay still succeeds after repair completion'
);
select is(
  (select count(*) from public.inventory_movements where custody_item_id = (select id from public.inventory_custody_items where case_id = (select case_id from repair_test_results where name = 'custody')) and movement_type = 'custody_return'),
  1::bigint, 'return retry after completion does not duplicate custody movements'
);
reset role;

-- The unrepairable job remains held and a follow-up takes over that exact hold.
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000002', true);
set local role authenticated;
select is(
  (select count(*) from public.repair_cost_entries where repair_job_id = (select job_id from repair_test_results where name = 'followup_parent')),
  2::bigint, 'manual-FX estimate and approved limit remain as durable evidence'
);
select throws_ok(
  $$ select public.create_follow_up_repair(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'), 12,
       'REPAIR-INVALID-FOLLOWUP', 'Synthetic fault', 'Synthetic intake', null,
       'Must not follow a completed job', 'repair-completed-followup-denied-01'
     ) $$,
  '40001', null, 'a completed job cannot be reopened through follow-up'
);
select is(
  (select count(*) from public.repair_job_events
   where repair_job_id in (
     (select job_id from repair_test_results where name = 'followup_parent'),
     (select job_id from repair_test_results where name = 'followup_child')
   ) and event_type = 'follow_up_handoff'),
  2::bigint, 'follow-up handoff appends evidence to both prior and new repair jobs'
);
reset role;
select throws_ok(
  $$ update public.branches set is_active = false where id = 'd9200000-0000-4000-8000-000000000001' $$,
  '23514', null, 'a branch with an active repair reservation cannot be deactivated'
);
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select throws_ok(
  $$ select public.archive_product_variant(
       'd9100000-0000-4000-8000-000000000001',
       'd9400000-0000-4000-8000-000000000001', 1,
       'repair-stock-archive-denial-01'
     ) $$,
  '23514', null, 'shop-owned stock remains protected from catalog archival during repair'
);
reset role;

select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$ select public.cancel_repair_job(
       'd9100000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'unknown'), 1,
       'Synthetic cancellation before repair work', 'repair-cancel-unknown-01'
     ) $$,
  'Owner can cancel an eligible repair with a reason'
);
select is(
  (select (status, device_claim_active) from public.repair_jobs where id = (select job_id from repair_test_results where name = 'unknown')),
  ('cancelled'::text, false), 'cancellation is terminal and releases the active claim'
);
select is(
  (select (on_hand_qty, available_qty, reserved_repair_qty, carrying_value_shop)
   from public.inventory_balances where branch_id = 'd9200000-0000-4000-8000-000000000001'
     and variant_id = 'd9400000-0000-4000-8000-000000000002'),
  (1, 1, 0, null::numeric), 'cancelling unknown-cost repair restores availability without inventing carrying value'
);
reset role;

-- Financial detail RLS and append-only protections.
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000004', true);
set local role authenticated;
select is(
  (select count(*) from public.repair_cost_entries where repair_job_id = (select job_id from repair_test_results where name = 'zero')),
  0::bigint, 'Inventory Staff cannot read detailed repair costs'
);
select is(
  (select count(*) from public.repair_job_events where repair_job_id = (select job_id from repair_test_results where name = 'zero') and event_type in ('created', 'estimate_submitted', 'spending_approved', 'expense_recorded')),
  0::bigint, 'financial event payloads are hidden from Inventory Staff'
);
reset role;
select set_config('request.jwt.claim.sub', 'd9000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select is(
  (select count(*) from public.repair_cost_entries where repair_job_id = (select job_id from repair_test_results where name = 'zero')),
  7::bigint, 'Owner can read repair financial evidence for an authorized branch'
);
reset role;
select throws_ok(
  $$ update public.repair_job_events set event_data = '{"tampered":true}'::jsonb where repair_job_id = (select job_id from repair_test_results where name = 'zero') $$,
  '42501', null, 'repair event history rejects updates'
);
select throws_ok(
  $$ delete from public.repair_cost_entries where repair_job_id = (select job_id from repair_test_results where name = 'zero') $$,
  '42501', null, 'financial repair history rejects deletes'
);
select throws_ok(
  $$ insert into public.repair_job_events (
       shop_id, branch_id, repair_job_id, operation_id,
       source_custody_event_id, event_line_number, event_type,
       actor_id, event_data
     ) values (
       'd9100000-0000-4000-8000-000000000001',
       'd9200000-0000-4000-8000-000000000001',
       (select job_id from repair_test_results where name = 'zero'),
       null, 'd9999999-0000-4000-8000-000000000099', 99,
       'custody_returned', 'd9000000-0000-4000-8000-000000000001', '{}'::jsonb
     ) $$,
  '23503', null, 'repair custody history rejects a missing source event'
);
select throws_ok(
  $$ truncate public.repair_job_events $$,
  '55006', null, 'deferred audit references prevent truncating repair event history inside this transaction'
);
select throws_ok(
  $$ truncate public.repair_cost_entries $$,
  '42501', null, 'financial repair history rejects truncation'
);
select throws_ok(
  $$ update public.repair_operations set request_payload = '{}'::jsonb
     where shop_id = 'd9100000-0000-4000-8000-000000000001'
       and idempotency_key = 'repair-zero-create-01' $$,
  '42501', null, 'repair idempotency claims reject updates'
);
select throws_ok(
  $$ delete from public.repair_job_custody_episodes
     where custody_case_id = (select case_id from repair_test_results where name = 'custody') $$,
  '42501', null, 'repair custody episode links reject deletion'
);
select throws_ok(
  $$ truncate public.repair_operations $$,
  '55006', null, 'deferred audit references prevent truncating repair idempotency history inside this transaction'
);
select throws_ok(
  $$ truncate public.repair_job_custody_episodes $$,
  '42501', null, 'repair custody link history rejects truncation'
);

select * from finish();
rollback;
