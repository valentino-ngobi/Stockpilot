begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

-- Synthetic tenants, identities, inventory, receipt evidence, and identifiers.
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('a9000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'custody-owner-a@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('a9000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'custody-manager-assigned@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('a9000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'custody-manager-unassigned@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('a9000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'custody-inventory-staff@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('a9000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'custody-sales-staff@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('a9000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'custody-suspended@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('a9000000-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'custody-owner-b@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.shops (id, name, created_by) values
  ('a9100000-0000-4000-8000-000000000001', 'Synthetic Custody Shop A', 'a9000000-0000-4000-8000-000000000001'),
  ('a9100000-0000-4000-8000-000000000002', 'Synthetic Custody Shop B', 'a9000000-0000-4000-8000-000000000007');

insert into public.shop_memberships (shop_id, user_id, role, status, created_by) values
  ('a9100000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000001', 'owner', 'active', 'a9000000-0000-4000-8000-000000000001'),
  ('a9100000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000002', 'manager', 'active', 'a9000000-0000-4000-8000-000000000001'),
  ('a9100000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000003', 'manager', 'active', 'a9000000-0000-4000-8000-000000000001'),
  ('a9100000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000004', 'inventory_staff', 'active', 'a9000000-0000-4000-8000-000000000001'),
  ('a9100000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000005', 'sales_staff', 'active', 'a9000000-0000-4000-8000-000000000001'),
  ('a9100000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000006', 'inventory_staff', 'suspended', 'a9000000-0000-4000-8000-000000000001'),
  ('a9100000-0000-4000-8000-000000000002', 'a9000000-0000-4000-8000-000000000007', 'owner', 'active', 'a9000000-0000-4000-8000-000000000007');

insert into public.branches (id, shop_id, name, is_primary, is_active, created_by) values
  ('a9200000-0000-4000-8000-000000000001', 'a9100000-0000-4000-8000-000000000001', 'Synthetic Main', true, true, 'a9000000-0000-4000-8000-000000000001'),
  ('a9200000-0000-4000-8000-000000000002', 'a9100000-0000-4000-8000-000000000001', 'Synthetic Destination', false, true, 'a9000000-0000-4000-8000-000000000001'),
  ('a9200000-0000-4000-8000-000000000003', 'a9100000-0000-4000-8000-000000000001', 'Synthetic Inactive', false, false, 'a9000000-0000-4000-8000-000000000001'),
  ('a9200000-0000-4000-8000-000000000004', 'a9100000-0000-4000-8000-000000000002', 'Synthetic Shop B', true, true, 'a9000000-0000-4000-8000-000000000007');

insert into public.branch_memberships (shop_id, branch_id, user_id, created_by) values
  ('a9100000-0000-4000-8000-000000000001', 'a9200000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000002', 'a9000000-0000-4000-8000-000000000001'),
  ('a9100000-0000-4000-8000-000000000001', 'a9200000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000004', 'a9000000-0000-4000-8000-000000000001'),
  ('a9100000-0000-4000-8000-000000000001', 'a9200000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000005', 'a9000000-0000-4000-8000-000000000001'),
  ('a9100000-0000-4000-8000-000000000001', 'a9200000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000006', 'a9000000-0000-4000-8000-000000000001'),
  ('a9100000-0000-4000-8000-000000000002', 'a9200000-0000-4000-8000-000000000004', 'a9000000-0000-4000-8000-000000000007', 'a9000000-0000-4000-8000-000000000007');

insert into public.shop_settings (shop_id, operating_currency_code, configured_by, updated_by) values
  ('a9100000-0000-4000-8000-000000000001', 'USD', 'a9000000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000001'),
  ('a9100000-0000-4000-8000-000000000002', 'USD', 'a9000000-0000-4000-8000-000000000007', 'a9000000-0000-4000-8000-000000000007');

insert into public.products (
  id, shop_id, product_type, tracking_mode, name, created_by, updated_by
) values
  ('a9300000-0000-4000-8000-000000000001', 'a9100000-0000-4000-8000-000000000001', 'smartphone', 'serialized', 'Synthetic custody phones A', 'a9000000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000001'),
  ('a9300000-0000-4000-8000-000000000002', 'a9100000-0000-4000-8000-000000000002', 'smartphone', 'serialized', 'Synthetic custody phones B', 'a9000000-0000-4000-8000-000000000007', 'a9000000-0000-4000-8000-000000000007');

insert into public.product_variants (
  id, shop_id, product_id, attributes, created_by, updated_by
) values
  ('a9400000-0000-4000-8000-000000000001', 'a9100000-0000-4000-8000-000000000001', 'a9300000-0000-4000-8000-000000000001', '{"test":"custody-a"}'::jsonb, 'a9000000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000001'),
  ('a9400000-0000-4000-8000-000000000002', 'a9100000-0000-4000-8000-000000000002', 'a9300000-0000-4000-8000-000000000002', '{"test":"custody-b"}'::jsonb, 'a9000000-0000-4000-8000-000000000007', 'a9000000-0000-4000-8000-000000000007');

insert into public.serialized_inventory (
  id, shop_id, branch_id, variant_id, availability_status,
  valuation_status, valuation_currency_code, unit_cost_shop, created_by, updated_by
) values
  ('a9500000-0000-4000-8000-000000000001', 'a9100000-0000-4000-8000-000000000001', 'a9200000-0000-4000-8000-000000000001', 'a9400000-0000-4000-8000-000000000001', 'available', 'known_cost', 'USD', 25, 'a9000000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000001'),
  ('a9500000-0000-4000-8000-000000000002', 'a9100000-0000-4000-8000-000000000001', 'a9200000-0000-4000-8000-000000000001', 'a9400000-0000-4000-8000-000000000001', 'available', 'known_cost', 'USD', 0, 'a9000000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000001'),
  ('a9500000-0000-4000-8000-000000000003', 'a9100000-0000-4000-8000-000000000001', 'a9200000-0000-4000-8000-000000000001', 'a9400000-0000-4000-8000-000000000001', 'available', 'unknown_cost', 'USD', null, 'a9000000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000001'),
  ('a9500000-0000-4000-8000-000000000004', 'a9100000-0000-4000-8000-000000000001', 'a9200000-0000-4000-8000-000000000001', 'a9400000-0000-4000-8000-000000000001', 'pending_fx', 'pending_fx', 'USD', null, 'a9000000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000001'),
  ('a9500000-0000-4000-8000-000000000005', 'a9100000-0000-4000-8000-000000000001', 'a9200000-0000-4000-8000-000000000001', 'a9400000-0000-4000-8000-000000000001', 'available', 'known_cost', 'USD', 40, 'a9000000-0000-4000-8000-000000000001', 'a9000000-0000-4000-8000-000000000001'),
  ('b9500000-0000-4000-8000-000000000001', 'a9100000-0000-4000-8000-000000000002', 'a9200000-0000-4000-8000-000000000004', 'a9400000-0000-4000-8000-000000000002', 'available', 'known_cost', 'USD', 10, 'a9000000-0000-4000-8000-000000000007', 'a9000000-0000-4000-8000-000000000007');

insert into public.serialized_identifiers (
  shop_id, branch_id, serialized_inventory_id, identifier_type,
  raw_value, is_primary, created_by
) values
  ('a9100000-0000-4000-8000-000000000001', 'a9200000-0000-4000-8000-000000000001', 'a9500000-0000-4000-8000-000000000001', 'imei1', '000000000000001', true, 'a9000000-0000-4000-8000-000000000001'),
  ('a9100000-0000-4000-8000-000000000001', 'a9200000-0000-4000-8000-000000000001', 'a9500000-0000-4000-8000-000000000001', 'serial', 'TEST-SERIAL-CUSTODY-001', false, 'a9000000-0000-4000-8000-000000000001'),
  ('a9100000-0000-4000-8000-000000000001', 'a9200000-0000-4000-8000-000000000001', 'a9500000-0000-4000-8000-000000000002', 'imei1', '000000000000002', true, 'a9000000-0000-4000-8000-000000000001'),
  ('a9100000-0000-4000-8000-000000000001', 'a9200000-0000-4000-8000-000000000001', 'a9500000-0000-4000-8000-000000000003', 'imei1', '000000000000003', true, 'a9000000-0000-4000-8000-000000000001'),
  ('a9100000-0000-4000-8000-000000000001', 'a9200000-0000-4000-8000-000000000001', 'a9500000-0000-4000-8000-000000000004', 'imei1', '000000000000004', true, 'a9000000-0000-4000-8000-000000000001'),
  ('a9100000-0000-4000-8000-000000000001', 'a9200000-0000-4000-8000-000000000001', 'a9500000-0000-4000-8000-000000000005', 'imei1', '000000000000005', true, 'a9000000-0000-4000-8000-000000000001'),
  ('a9100000-0000-4000-8000-000000000002', 'a9200000-0000-4000-8000-000000000004', 'b9500000-0000-4000-8000-000000000001', 'imei1', '000000000000006', true, 'a9000000-0000-4000-8000-000000000007');

insert into public.inventory_balances (
  shop_id, branch_id, variant_id, valuation_status, valuation_currency_code,
  on_hand_qty, available_qty, carrying_value_shop, average_unit_cost_shop,
  updated_by
) values
  ('a9100000-0000-4000-8000-000000000001', 'a9200000-0000-4000-8000-000000000001', 'a9400000-0000-4000-8000-000000000001', 'known_cost', 'USD', 3, 3, 65, 21.6666666667, 'a9000000-0000-4000-8000-000000000001'),
  ('a9100000-0000-4000-8000-000000000001', 'a9200000-0000-4000-8000-000000000001', 'a9400000-0000-4000-8000-000000000001', 'unknown_cost', 'USD', 1, 1, null, null, 'a9000000-0000-4000-8000-000000000001'),
  ('a9100000-0000-4000-8000-000000000001', 'a9200000-0000-4000-8000-000000000001', 'a9400000-0000-4000-8000-000000000001', 'pending_fx', 'USD', 1, 0, null, null, 'a9000000-0000-4000-8000-000000000001'),
  ('a9100000-0000-4000-8000-000000000002', 'a9200000-0000-4000-8000-000000000004', 'a9400000-0000-4000-8000-000000000002', 'known_cost', 'USD', 1, 1, 10, 10, 'a9000000-0000-4000-8000-000000000007');

-- Preserve a synthetic historical receipt and its original movement.
set constraints all deferred;
insert into public.inventory_operations (
  id, shop_id, branch_id, operation_type, actor_id, idempotency_key,
  request_payload, result_receipt_id, valuation_currency_code,
  currency_version
) values (
  'a9700000-0000-4000-8000-000000000001',
  'a9100000-0000-4000-8000-000000000001',
  'a9200000-0000-4000-8000-000000000001', 'serialized_receipt',
  'a9000000-0000-4000-8000-000000000001', 'custody-history-seed-01',
  '{"synthetic_fixture":true}'::jsonb,
  'a9600000-0000-4000-8000-000000000001', 'USD', 1
);
insert into public.inventory_receipts (
  id, shop_id, branch_id, operation_id, receipt_kind, supplier_name_snapshot,
  supplier_invoice_reference, original_currency_code, original_invoice_amount,
  valuation_currency_code, accepted_fx_rate, rate_source, rate_observed_at,
  rate_accepted_at, accepted_by, converted_invoice_amount_shop,
  valuation_status, created_by
) values (
  'a9600000-0000-4000-8000-000000000001',
  'a9100000-0000-4000-8000-000000000001',
  'a9200000-0000-4000-8000-000000000001',
  'a9700000-0000-4000-8000-000000000001', 'supplier_invoice',
  'Synthetic supplier', 'CUSTODY-SYNTH-001', 'USD', 25,
  'USD', 1, 'synthetic-test-rate', now(), now(),
  'a9000000-0000-4000-8000-000000000001', 25, 'known_cost',
  'a9000000-0000-4000-8000-000000000001'
);
insert into public.inventory_receipt_lines (
  shop_id, branch_id, receipt_id, line_number, variant_id,
  serialized_inventory_id, quantity, original_line_amount,
  converted_line_amount_shop, unit_cost_shop, valuation_status, created_by
) values (
  'a9100000-0000-4000-8000-000000000001',
  'a9200000-0000-4000-8000-000000000001',
  'a9600000-0000-4000-8000-000000000001', 1,
  'a9400000-0000-4000-8000-000000000001',
  'a9500000-0000-4000-8000-000000000001', 1, 25, 25, 25,
  'known_cost', 'a9000000-0000-4000-8000-000000000001'
);
insert into public.inventory_movements (
  shop_id, branch_id, operation_id, receipt_line_id, variant_id,
  serialized_inventory_id, movement_type, valuation_status,
  valuation_currency_code, on_hand_delta, available_delta,
  unit_cost_shop, extended_cost_shop, actor_id, line_number
) values (
  'a9100000-0000-4000-8000-000000000001',
  'a9200000-0000-4000-8000-000000000001',
  'a9700000-0000-4000-8000-000000000001',
  (select id from public.inventory_receipt_lines
    where receipt_id = 'a9600000-0000-4000-8000-000000000001'),
  'a9400000-0000-4000-8000-000000000001',
  'a9500000-0000-4000-8000-000000000001', 'receipt', 'known_cost',
  'USD', 1, 1, 25, 25, 'a9000000-0000-4000-8000-000000000001', 1
);
set constraints all immediate;
-- Custody RPCs intentionally create operation rows before their deferred
-- result case/incident rows, matching normal initially-deferred behavior.
set constraints all deferred;

create temporary table custody_test_results (
  name text primary key,
  case_id uuid,
  incident_id uuid
) on commit drop;
create temporary table custody_test_payloads (
  name text primary key,
  payload jsonb not null
) on commit drop;
insert into custody_test_payloads values
  ('multi', jsonb_build_array(
    jsonb_build_object(
      'serialized_inventory_id', 'a9500000-0000-4000-8000-000000000001',
      'custodian_type', 'external', 'custodian_user_id', null,
      'custodian_name', 'Synthetic courier A', 'custodian_contact', '555-0101',
      'expected_return_at', '2099-01-01T00:00:00Z'
    ),
    jsonb_build_object(
      'serialized_inventory_id', 'a9500000-0000-4000-8000-000000000002',
      'custodian_type', 'employee', 'custodian_user_id', 'a9000000-0000-4000-8000-000000000004',
      'custodian_name', null, 'custodian_contact', null,
      'expected_return_at', '2099-01-02T00:00:00Z'
    )
  )),
  ('unknown', jsonb_build_array(jsonb_build_object(
    'serialized_inventory_id', 'a9500000-0000-4000-8000-000000000003',
    'custodian_type', 'external', 'custodian_user_id', null,
    'custodian_name', 'Synthetic repair technician', 'custodian_contact', '555-0102',
    'expected_return_at', '2099-01-03T00:00:00Z'
  ))),
  ('pending', jsonb_build_array(jsonb_build_object(
    'serialized_inventory_id', 'a9500000-0000-4000-8000-000000000004',
    'custodian_type', 'external', 'custodian_user_id', null,
    'custodian_name', 'Synthetic recipient', 'custodian_contact', null,
    'expected_return_at', null
  ))),
  ('transfer_first', jsonb_build_array(jsonb_build_object(
    'serialized_inventory_id', 'a9500000-0000-4000-8000-000000000005',
    'custodian_type', 'external', 'custodian_user_id', null,
    'custodian_name', 'Synthetic recipient', 'custodian_contact', null,
    'expected_return_at', null
  ))),
  ('shop_b', jsonb_build_array(jsonb_build_object(
    'serialized_inventory_id', 'b9500000-0000-4000-8000-000000000001',
    'custodian_type', 'external', 'custodian_user_id', null,
    'custodian_name', 'Synthetic Shop B recipient', 'custodian_contact', null,
    'expected_return_at', null
  )));
grant select, insert, update on custody_test_results to authenticated;
grant select on custody_test_payloads to authenticated;

select ok(
  not has_function_privilege('anon', 'public.request_inventory_custody(uuid,uuid,text,text,jsonb,text)', 'EXECUTE'),
  'anonymous users cannot execute custody request RPCs'
);
select ok(
  has_function_privilege('authenticated', 'public.request_inventory_custody(uuid,uuid,text,text,jsonb,text)', 'EXECUTE'),
  'authenticated members can reach custody RPC authorization checks'
);
select ok(
  not has_function_privilege('service_role', 'public.request_inventory_custody(uuid,uuid,text,text,jsonb,text)', 'EXECUTE'),
  'service_role cannot execute end-user custody RPCs'
);

select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select throws_ok(
  $$ select public.request_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       'a9200000-0000-4000-8000-000000000003',
       'Inactive branch attempt', 'Must fail closed',
       (select payload from custody_test_payloads where name = 'multi'),
       'custody-inactive-branch-01'
     ) $$,
  '42501', null, 'inactive branches cannot start custody'
);
select throws_ok(
  $$ select public.request_inventory_custody(
       'a9100000-0000-4000-8000-000000000002',
       'a9200000-0000-4000-8000-000000000004',
       'Cross-shop attempt', 'Must fail closed',
       (select payload from custody_test_payloads where name = 'shop_b'),
       'custody-cross-shop-01'
     ) $$,
  '42501', null, 'an Owner in one shop cannot create custody for another shop'
);
select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000007', true);
select lives_ok(
  $$ insert into custody_test_results (name, case_id)
     values ('shop-b', public.request_inventory_custody(
       'a9100000-0000-4000-8000-000000000002',
       'a9200000-0000-4000-8000-000000000004',
       'Synthetic Shop B custody', 'Tenant visibility fixture',
       (select payload from custody_test_payloads where name = 'shop_b'),
       'custody-shop-b-01'
     )) $$,
  'the active Owner can create a custody request in their own shop'
);
select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000001', true);
select is(
  (select count(*) from public.inventory_custody_cases
    where id = (select case_id from custody_test_results where name = 'shop-b')),
  0::bigint,
  'RLS hides another shop custody case'
);
select throws_ok(
  $$ insert into public.inventory_custody_cases (
       shop_id, branch_id, case_reference, purpose, reason, requested_by
     ) values (
       'a9100000-0000-4000-8000-000000000001',
       'a9200000-0000-4000-8000-000000000001',
       'CUS-UNAUTH-INSERT', 'Direct insert', 'Must be denied',
       'a9000000-0000-4000-8000-000000000001'
     ) $$,
  '42501', null, 'authenticated users cannot insert custody cases directly'
);
select throws_ok(
  $$ update public.inventory_custody_cases set reason = 'tampered'
     where id = (select case_id from custody_test_results where name = 'shop-b') $$,
  '42501', null, 'authenticated users cannot update custody cases directly'
);
select throws_ok(
  $$ delete from public.inventory_custody_cases
     where id = (select case_id from custody_test_results where name = 'shop-b') $$,
  '42501', null, 'authenticated users cannot delete custody cases directly'
);
select throws_ok(
  $$ truncate public.inventory_custody_events $$,
  '42501', null, 'authenticated users cannot truncate custody audit history'
);
reset role;

select ok(not has_table_privilege('authenticated', 'public.inventory_custody_cases', 'INSERT'), 'authenticated has no direct case INSERT privilege');
select ok(not has_table_privilege('authenticated', 'public.inventory_custody_cases', 'UPDATE'), 'authenticated has no direct case UPDATE privilege');
select ok(not has_table_privilege('authenticated', 'public.inventory_custody_cases', 'DELETE'), 'authenticated has no direct case DELETE privilege');
select ok(not has_table_privilege('authenticated', 'public.inventory_custody_cases', 'TRUNCATE'), 'authenticated has no direct case TRUNCATE privilege');
select ok(not has_table_privilege('service_role', 'public.inventory_custody_cases', 'INSERT'), 'service_role has no direct case INSERT privilege');
select ok(not has_table_privilege('service_role', 'public.inventory_custody_cases', 'UPDATE'), 'service_role has no direct case UPDATE privilege');
select ok(not has_table_privilege('service_role', 'public.inventory_custody_cases', 'DELETE'), 'service_role has no direct case DELETE privilege');
select ok(not has_table_privilege('service_role', 'public.inventory_custody_events', 'TRUNCATE'), 'service_role has no custody event TRUNCATE privilege');
select ok(not has_table_privilege('authenticated', 'public.inventory_custody_items', 'INSERT'), 'authenticated has no direct item INSERT privilege');
select ok(not has_table_privilege('authenticated', 'public.inventory_custody_incidents', 'UPDATE'), 'authenticated has no direct incident UPDATE privilege');
select ok(
  not has_table_privilege('authenticated', 'public.inventory_custody_cases', 'INSERT')
  and not has_table_privilege('authenticated', 'public.inventory_custody_cases', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.inventory_custody_cases', 'DELETE')
  and not has_table_privilege('authenticated', 'public.inventory_custody_cases', 'TRUNCATE'),
  'authenticated cannot directly mutate or truncate custody cases'
);
select ok(
  not has_table_privilege('authenticated', 'public.inventory_custody_items', 'INSERT')
  and not has_table_privilege('authenticated', 'public.inventory_custody_items', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.inventory_custody_items', 'DELETE')
  and not has_table_privilege('authenticated', 'public.inventory_custody_items', 'TRUNCATE'),
  'authenticated cannot directly mutate or truncate custody items'
);
select ok(
  not has_table_privilege('authenticated', 'public.inventory_custody_incidents', 'INSERT')
  and not has_table_privilege('authenticated', 'public.inventory_custody_incidents', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.inventory_custody_incidents', 'DELETE')
  and not has_table_privilege('authenticated', 'public.inventory_custody_incidents', 'TRUNCATE'),
  'authenticated cannot directly mutate or truncate custody incidents'
);
select ok(
  not has_table_privilege('authenticated', 'public.inventory_custody_events', 'INSERT')
  and not has_table_privilege('authenticated', 'public.inventory_custody_events', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.inventory_custody_events', 'DELETE')
  and not has_table_privilege('authenticated', 'public.inventory_custody_events', 'TRUNCATE'),
  'authenticated cannot directly mutate or truncate custody events'
);
select ok(
  not has_table_privilege('service_role', 'public.inventory_custody_cases', 'INSERT')
  and not has_table_privilege('service_role', 'public.inventory_custody_cases', 'UPDATE')
  and not has_table_privilege('service_role', 'public.inventory_custody_cases', 'DELETE')
  and not has_table_privilege('service_role', 'public.inventory_custody_cases', 'TRUNCATE'),
  'service_role cannot directly mutate or truncate custody cases'
);
select ok(
  not has_table_privilege('service_role', 'public.inventory_custody_items', 'INSERT')
  and not has_table_privilege('service_role', 'public.inventory_custody_items', 'UPDATE')
  and not has_table_privilege('service_role', 'public.inventory_custody_items', 'DELETE')
  and not has_table_privilege('service_role', 'public.inventory_custody_items', 'TRUNCATE'),
  'service_role cannot directly mutate or truncate custody items'
);
select ok(
  not has_table_privilege('service_role', 'public.inventory_custody_incidents', 'INSERT')
  and not has_table_privilege('service_role', 'public.inventory_custody_incidents', 'UPDATE')
  and not has_table_privilege('service_role', 'public.inventory_custody_incidents', 'DELETE')
  and not has_table_privilege('service_role', 'public.inventory_custody_incidents', 'TRUNCATE'),
  'service_role cannot directly mutate or truncate custody incidents'
);
select ok(
  not has_table_privilege('service_role', 'public.inventory_custody_events', 'INSERT')
  and not has_table_privilege('service_role', 'public.inventory_custody_events', 'UPDATE')
  and not has_table_privilege('service_role', 'public.inventory_custody_events', 'DELETE')
  and not has_table_privilege('service_role', 'public.inventory_custody_events', 'TRUNCATE'),
  'service_role cannot directly mutate or truncate custody events'
);

select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000003', true);
set local role authenticated;
select throws_ok(
  $$ select public.request_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       'a9200000-0000-4000-8000-000000000001',
       'Unassigned manager', 'Must be denied',
       (select payload from custody_test_payloads where name = 'unknown'),
       'custody-unassigned-manager-01'
     ) $$,
  '42501', null, 'unassigned Managers cannot mutate custody in another branch'
);
select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$ select public.request_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       'a9200000-0000-4000-8000-000000000001',
       'Sales staff attempt', 'Must be denied',
       (select payload from custody_test_payloads where name = 'unknown'),
       'custody-sales-denial-01'
     ) $$,
  '42501', null, 'Sales Staff cannot mutate custody'
);
select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000006', true);
select throws_ok(
  $$ select public.request_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       'a9200000-0000-4000-8000-000000000001',
       'Suspended member attempt', 'Must be denied',
       (select payload from custody_test_payloads where name = 'unknown'),
       'custody-suspended-denial-01'
     ) $$,
  '42501', null, 'suspended members cannot mutate custody'
);
select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$ select public.request_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       'a9200000-0000-4000-8000-000000000001',
       'Pending FX attempt', 'Must be denied',
       (select payload from custody_test_payloads where name = 'pending'),
       'custody-pending-fx-01'
     ) $$,
  '23514', null, 'Pending-FX devices cannot enter custody'
);
reset role;

-- Transfer-first and custody-first claims cannot overlap.
select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000004', true);
set local role authenticated;
create temporary table custody_transfer_result (transfer_id uuid) on commit drop;
grant insert, select on custody_transfer_result to authenticated;
select lives_ok(
  $$ insert into custody_transfer_result values (
       public.request_inventory_transfer(
         'a9100000-0000-4000-8000-000000000001',
         'a9200000-0000-4000-8000-000000000001',
         'a9200000-0000-4000-8000-000000000002',
         '[{"serialized_inventory_id":"a9500000-0000-4000-8000-000000000005"}]'::jsonb,
         'Synthetic competing transfer', 'custody-transfer-first-01'
       )
     ) $$,
  'an assigned Inventory Staff member may request a transfer before custody is claimed'
);
select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$ select public.request_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       'a9200000-0000-4000-8000-000000000001',
       'Transfer-conflict request', 'Must be denied',
       (select payload from custody_test_payloads where name = 'transfer_first'),
       'custody-transfer-conflict-01'
     ) $$,
  '23514', null, 'a device with an active transfer claim cannot be requested for custody'
);
select lives_ok(
  $$ select public.cancel_inventory_transfer(
       'a9100000-0000-4000-8000-000000000001',
       (select transfer_id from custody_transfer_result),
       1, 'Synthetic cancellation before approval', 'custody-transfer-cancel-01'
     ) $$,
  'the unapproved synthetic transfer can be cancelled without moving stock'
);
reset role;

-- A two-device case exercises known positive and known-zero costs.
select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$ insert into custody_test_results (name, case_id)
     values ('multi', public.request_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       'a9200000-0000-4000-8000-000000000001',
       'Synthetic inspection handover', 'Synthetic multiple-device case',
       (select payload from custody_test_payloads where name = 'multi'),
       'custody-multi-request-01'
     )) $$,
  'an active Owner can request custody for serialized devices'
);
select is(
  public.request_inventory_custody(
    'a9100000-0000-4000-8000-000000000001',
    'a9200000-0000-4000-8000-000000000001',
    'Synthetic inspection handover', 'Synthetic multiple-device case',
    (select payload from custody_test_payloads where name = 'multi'),
    'custody-multi-request-01'
  )::text,
  (select case_id::text from custody_test_results where name = 'multi'),
  'an identical request retry returns the original case ID'
);
select throws_ok(
  $$ select public.request_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       'a9200000-0000-4000-8000-000000000001',
       'Different payload', 'Conflicting retry',
       (select payload from custody_test_payloads where name = 'multi'),
       'custody-multi-request-01'
     ) $$,
  '23505', null, 'reusing a custody idempotency key with another payload fails'
);
select throws_ok(
  $$ select public.request_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       'a9200000-0000-4000-8000-000000000001',
       'Duplicate active claim', 'Must be denied',
       (select payload from custody_test_payloads where name = 'multi'),
       'custody-multi-duplicate-claim-01'
     ) $$,
  '23514', null, 'one serialized device cannot be actively claimed by two custody cases'
);
select throws_ok(
  $$ select public.request_inventory_transfer(
       'a9100000-0000-4000-8000-000000000001',
       'a9200000-0000-4000-8000-000000000001',
       'a9200000-0000-4000-8000-000000000002',
       '[{"serialized_inventory_id":"a9500000-0000-4000-8000-000000000001"}]'::jsonb,
       'Custody must exclude transfer', 'custody-blocks-transfer-01'
     ) $$,
  '23514', null, 'a device with an active custody claim cannot be claimed by transfer'
);
select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$ select public.approve_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       (select case_id from custody_test_results where name = 'multi'),
       1, 'custody-staff-approve-denied-01'
     ) $$,
  '42501', null, 'Inventory Staff cannot approve custody'
);
select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000002', true);
select lives_ok(
  $$ select public.approve_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       (select case_id from custody_test_results where name = 'multi'),
       1, 'custody-multi-approve-01'
     ) $$,
  'an assigned Manager may approve and reserve custody'
);
select is(
  (select status from public.inventory_custody_cases
   where id = (select case_id from custody_test_results where name = 'multi')),
  'approved', 'approval changes the case state'
);
select is(
  (select availability_status::text from public.serialized_inventory
   where id = 'a9500000-0000-4000-8000-000000000001'),
  'reserved', 'approval makes the device unavailable without changing its identity'
);
select is(
  (select custody_state from public.serialized_inventory
   where id = 'a9500000-0000-4000-8000-000000000001'),
  'approved', 'approved custody is distinguished from a transfer reservation'
);
select is(
  (select on_hand_qty from public.inventory_balances
   where shop_id = 'a9100000-0000-4000-8000-000000000001'
     and branch_id = 'a9200000-0000-4000-8000-000000000001'
     and variant_id = 'a9400000-0000-4000-8000-000000000001'
     and valuation_status = 'known_cost'),
  3, 'approval leaves branch on-hand quantity unchanged'
);
select is(
  (select available_qty from public.inventory_balances
   where shop_id = 'a9100000-0000-4000-8000-000000000001'
     and branch_id = 'a9200000-0000-4000-8000-000000000001'
     and variant_id = 'a9400000-0000-4000-8000-000000000001'
     and valuation_status = 'known_cost'),
  1, 'approval reserves both devices from available stock'
);
select is(
  (select reserved_custody_qty from public.inventory_balances
   where shop_id = 'a9100000-0000-4000-8000-000000000001'
     and branch_id = 'a9200000-0000-4000-8000-000000000001'
     and variant_id = 'a9400000-0000-4000-8000-000000000001'
     and valuation_status = 'known_cost'),
  2, 'approval increases the custody reservation bucket'
);
select is(
  (select carrying_value_shop from public.inventory_balances
   where shop_id = 'a9100000-0000-4000-8000-000000000001'
     and branch_id = 'a9200000-0000-4000-8000-000000000001'
     and variant_id = 'a9400000-0000-4000-8000-000000000001'
     and valuation_status = 'known_cost'),
  65::numeric, 'approval does not change carrying value'
);
select is(
  public.approve_inventory_custody(
    'a9100000-0000-4000-8000-000000000001',
    (select case_id from custody_test_results where name = 'multi'),
    1, 'custody-multi-approve-01'
  )::text,
  (select case_id::text from custody_test_results where name = 'multi'),
  'an identical approval retry returns its original case without a second reservation'
);
reset role;

select throws_ok(
  $$ select public.archive_product_variant(
       'a9100000-0000-4000-8000-000000000001',
       'a9400000-0000-4000-8000-000000000001', 1,
       'custody-archive-variant-01'
     ) $$,
  '23514', null, 'a variant with owned devices in custody cannot be archived'
);
select throws_ok(
  $$ update public.branches set is_active = false
     where id = 'a9200000-0000-4000-8000-000000000001' $$,
  '23514', null, 'a branch with an approved custody claim cannot be deactivated'
);

-- Physical handover moves carrying value from branch stock to the custody view.
select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000004', true);
set local role authenticated;
select lives_ok(
  $$ select public.handover_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       (select case_id from custody_test_results where name = 'multi'),
       2,
       jsonb_build_array(
         jsonb_build_object('item_id', (
           select id from public.inventory_custody_items
           where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000001'
         ), 'condition', 'Synthetic device condition A'),
         jsonb_build_object('item_id', (
           select id from public.inventory_custody_items
           where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000002'
         ), 'condition', 'Synthetic device condition B')
       ),
       'custody-multi-handover-01'
     ) $$,
  'assigned Inventory Staff can confirm physical handover'
);
select is(
  (select status from public.inventory_custody_cases
   where id = (select case_id from custody_test_results where name = 'multi')),
  'handed_over', 'case reflects item handover'
);
select is(
  (select on_hand_qty from public.inventory_balances
   where shop_id = 'a9100000-0000-4000-8000-000000000001'
     and branch_id = 'a9200000-0000-4000-8000-000000000001'
     and variant_id = 'a9400000-0000-4000-8000-000000000001'
     and valuation_status = 'known_cost'),
  1, 'handover reduces branch on-hand by each device exactly once'
);
select is(
  (select available_qty from public.inventory_balances
   where shop_id = 'a9100000-0000-4000-8000-000000000001'
     and branch_id = 'a9200000-0000-4000-8000-000000000001'
     and variant_id = 'a9400000-0000-4000-8000-000000000001'
     and valuation_status = 'known_cost'),
  1, 'handed-over devices remain unavailable'
);
select is(
  (select carrying_value_shop from public.inventory_balances
   where shop_id = 'a9100000-0000-4000-8000-000000000001'
     and branch_id = 'a9200000-0000-4000-8000-000000000001'
     and variant_id = 'a9400000-0000-4000-8000-000000000001'
     and valuation_status = 'known_cost'),
  40::numeric, 'handover removes only known carrying value, including zero-cost correctly'
);
select is(
  (select sum(carrying_value_shop) from public.inventory_custody_held
   where shop_id = 'a9100000-0000-4000-8000-000000000001'),
  25::numeric, 'custody-held view carries the known-cost device value and zero stays zero'
);
select is(
  (select count(*) from public.inventory_movements
   where custody_item_id in (
     select id from public.inventory_custody_items
     where case_id = (select case_id from custody_test_results where name = 'multi')
   ) and movement_type = 'custody_out'),
  2::bigint, 'one custody-out movement is recorded per handed-over device'
);
select is(
  (select count(*) from public.serialized_identifiers
   where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000001'),
  2::bigint, 'primary and secondary device identifiers remain attached to the same device'
);
select throws_ok(
  $$ select public.cancel_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       (select case_id from custody_test_results where name = 'multi'),
       3, 'Too late after handover', 'custody-cancel-after-handover-02'
     ) $$,
  '40001', null, 'a handed-over case cannot be cancelled'
);
select is(
  (select count(*) from public.inventory_receipt_lines
   where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000001'
     and receipt_id = 'a9600000-0000-4000-8000-000000000001'),
  1::bigint, 'historical receipt reference is preserved after handover'
);
select is(
  (select count(*) from public.inventory_movements
   where operation_id = 'a9700000-0000-4000-8000-000000000001'),
  1::bigint, 'historical receipt movement is not rewritten by custody'
);
select is(
  public.handover_inventory_custody(
    'a9100000-0000-4000-8000-000000000001',
    (select case_id from custody_test_results where name = 'multi'),
    2,
    jsonb_build_array(
      jsonb_build_object('item_id', (
        select id from public.inventory_custody_items
        where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000001'
      ), 'condition', 'Synthetic device condition A'),
      jsonb_build_object('item_id', (
        select id from public.inventory_custody_items
        where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000002'
      ), 'condition', 'Synthetic device condition B')
    ),
    'custody-multi-handover-01'
  )::text,
  (select case_id::text from custody_test_results where name = 'multi'),
  'an identical handover retry returns the original result'
);
select is(
  (select count(*) from public.inventory_movements
   where custody_item_id in (
     select id from public.inventory_custody_items
     where case_id = (select case_id from custody_test_results where name = 'multi')
   ) and movement_type = 'custody_out'),
  2::bigint, 'handover replay does not create duplicate movements'
);
reset role;

-- Partial return restores one item and preserves exact value accounting.
select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000004', true);
set local role authenticated;
select lives_ok(
  $$ select public.return_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       (select case_id from custody_test_results where name = 'multi'),
       3,
       jsonb_build_array(jsonb_build_object('item_id', (
         select id from public.inventory_custody_items
         where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000002'
       ), 'condition', 'Synthetic zero-cost device returned')),
       'custody-multi-return-01'
     ) $$,
  'a custody case can return one item before the others'
);
select is(
  (select status from public.inventory_custody_cases
   where id = (select case_id from custody_test_results where name = 'multi')),
  'partially_returned', 'case status reflects item-level partial return'
);
select is(
  (select availability_status::text from public.serialized_inventory
   where id = 'a9500000-0000-4000-8000-000000000002'),
  'available', 'a confirmed zero-cost return becomes available'
);
select is(
  (select unit_cost_shop from public.serialized_inventory
   where id = 'a9500000-0000-4000-8000-000000000002'),
  0::numeric, 'known-zero remains zero rather than becoming NULL'
);
select is(
  (select carrying_value_shop from public.inventory_balances
   where shop_id = 'a9100000-0000-4000-8000-000000000001'
     and branch_id = 'a9200000-0000-4000-8000-000000000001'
     and variant_id = 'a9400000-0000-4000-8000-000000000001'
     and valuation_status = 'known_cost'),
  40::numeric, 'returning a known-zero device does not invent or add carrying value'
);
select is(
  public.return_inventory_custody(
    'a9100000-0000-4000-8000-000000000001',
    (select case_id from custody_test_results where name = 'multi'),
    3,
    jsonb_build_array(jsonb_build_object('item_id', (
      select id from public.inventory_custody_items
      where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000002'
    ), 'condition', 'Synthetic zero-cost device returned')),
    'custody-multi-return-01'
  )::text,
  (select case_id::text from custody_test_results where name = 'multi'),
  'an identical partial-return retry returns the original case'
);
select is(
  (select count(*) from public.inventory_movements
   where custody_item_id = (select id from public.inventory_custody_items
     where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000002')
     and movement_type = 'custody_return'),
  1::bigint, 'return replay does not duplicate the return movement'
);
select lives_ok(
  $$ select public.return_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       (select case_id from custody_test_results where name = 'multi'),
       4,
       jsonb_build_array(jsonb_build_object('item_id', (
         select id from public.inventory_custody_items
         where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000001'
       ), 'condition', 'Synthetic positive-cost device returned')),
       'custody-multi-return-02'
     ) $$,
  'the remaining device can be returned in a later operation'
);
select is(
  (select status from public.inventory_custody_cases
   where id = (select case_id from custody_test_results where name = 'multi')),
  'returned', 'case closes only after every item is physically returned'
);
select is(
  (select on_hand_qty from public.inventory_balances
   where shop_id = 'a9100000-0000-4000-8000-000000000001'
     and branch_id = 'a9200000-0000-4000-8000-000000000001'
     and variant_id = 'a9400000-0000-4000-8000-000000000001'
     and valuation_status = 'known_cost'),
  3, 'full custody round trip restores branch on-hand quantity'
);
select is(
  (select carrying_value_shop from public.inventory_balances
   where shop_id = 'a9100000-0000-4000-8000-000000000001'
     and branch_id = 'a9200000-0000-4000-8000-000000000001'
     and variant_id = 'a9400000-0000-4000-8000-000000000001'
     and valuation_status = 'known_cost'),
  65::numeric, 'custody round trip exactly conserves known carrying value'
);
select is(
  (select count(*) from public.serialized_inventory
   where id = 'a9500000-0000-4000-8000-000000000001'),
  1::bigint, 'return reuses the original serialized device instead of creating a duplicate'
);
reset role;

-- A later transfer changes the device's current branch without rewriting the
-- custody case's historical source branch or its stable device identity.
create temporary table custody_identity_transfer_result (
  transfer_id uuid not null
) on commit drop;
grant select, insert on custody_identity_transfer_result to authenticated;
select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000004', true);
set local role authenticated;
select lives_ok(
  $$ insert into custody_identity_transfer_result values (
       public.request_inventory_transfer(
         'a9100000-0000-4000-8000-000000000001',
         'a9200000-0000-4000-8000-000000000001',
         'a9200000-0000-4000-8000-000000000002',
         '[{"serialized_inventory_id":"a9500000-0000-4000-8000-000000000001"}]'::jsonb,
         'Synthetic post-custody branch move', 'custody-identity-transfer-01'
       )
     ) $$,
  'the returned original device can later be requested for branch transfer'
);
reset role;
select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000001', true);
set local role authenticated;
select lives_ok(
  $$ select public.approve_inventory_transfer(
       'a9100000-0000-4000-8000-000000000001',
       (select transfer_id from custody_identity_transfer_result),
       1, 'custody-identity-transfer-approve-01'
     ) $$,
  'Owner approval can reserve the returned device for transfer'
);
select lives_ok(
  $$ select public.dispatch_inventory_transfer(
       'a9100000-0000-4000-8000-000000000001',
       (select transfer_id from custody_identity_transfer_result),
       2, 'custody-identity-transfer-dispatch-01'
     ) $$,
  'Owner can dispatch the same serialized device after custody'
);
select lives_ok(
  $$ select public.receive_inventory_transfer(
       'a9100000-0000-4000-8000-000000000001',
       (select transfer_id from custody_identity_transfer_result),
       3,
       jsonb_build_array(jsonb_build_object(
         'line_id', (select id from public.inventory_transfer_lines
           where transfer_id = (select transfer_id from custody_identity_transfer_result)),
         'quantity', 1
       )),
       'custody-identity-transfer-receive-01'
     ) $$,
  'transfer receipt moves the original device while preserving custody history'
);
select is(
  (select branch_id from public.serialized_inventory
   where id = 'a9500000-0000-4000-8000-000000000001'),
  'a9200000-0000-4000-8000-000000000002'::uuid,
  'the original serialized device now belongs to the destination branch'
);
select is(
  (select branch_id from public.inventory_custody_items
   where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000001'),
  'a9200000-0000-4000-8000-000000000001'::uuid,
  'the completed custody row retains its historical source branch'
);
select is(
  (select count(*) from public.serialized_inventory
   where id = 'a9500000-0000-4000-8000-000000000001'),
  1::bigint,
  'later transfer does not create a duplicate serialized device'
);
select is(
  (select count(*) from public.serialized_identifiers
   where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000001'),
  2::bigint,
  'both original identifiers remain attached after the branch move'
);
reset role;

-- Unknown cost remains unknown; missing/damage/dispute never auto-write-off.
select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000004', true);
set local role authenticated;
select lives_ok(
  $$ insert into custody_test_results (name, case_id)
     values ('unknown', public.request_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       'a9200000-0000-4000-8000-000000000001',
       'Synthetic unknown-cost custody', 'No cost inference',
       (select payload from custody_test_payloads where name = 'unknown'),
       'custody-unknown-request-01'
     )) $$,
  'Inventory Staff can request custody while preserving unknown-cost status'
);
select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000002', true);
select lives_ok(
  $$ select public.approve_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       (select case_id from custody_test_results where name = 'unknown'),
       1, 'custody-unknown-approve-01'
     ) $$,
  'assigned Manager can approve an unknown-cost device without assigning a cost'
);
select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000004', true);
select lives_ok(
  $$ select public.handover_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       (select case_id from custody_test_results where name = 'unknown'), 2,
       jsonb_build_array(jsonb_build_object('item_id', (
         select id from public.inventory_custody_items
         where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000003'
       ), 'condition', 'Synthetic unknown-cost device condition')),
       'custody-unknown-handover-01'
     ) $$,
  'unknown-cost device may be handed over without a guessed cost'
);
select is(
  (select unit_cost_shop is null from public.serialized_inventory
   where id = 'a9500000-0000-4000-8000-000000000003'),
  true, 'unknown unit cost remains NULL during custody'
);
select is(
  (select extended_cost_shop is null from public.inventory_movements
   where custody_item_id = (select id from public.inventory_custody_items
     where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000003')
     and movement_type = 'custody_out'),
  true, 'unknown custody movement value remains NULL'
);
select lives_ok(
  $$ insert into custody_test_results (name, incident_id)
     values ('missing', public.report_custody_incident(
       'a9100000-0000-4000-8000-000000000001',
       (select case_id from custody_test_results where name = 'unknown'),
       (select id from public.inventory_custody_items
         where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000003'),
       (select version from public.inventory_custody_cases
         where id = (select case_id from custody_test_results where name = 'unknown')),
       'missing', 'Synthetic missing-device report',
       '{"evidence_ref":"synthetic-photo-1"}'::jsonb,
       'custody-missing-report-01'
     )) $$,
  'Inventory Staff can record a missing-device incident with evidence'
);
select is(
  (select state from public.inventory_custody_items
   where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000003'),
  'handed_over', 'missing report keeps the custody item active'
);
select is(
  (select availability_status::text from public.serialized_inventory
   where id = 'a9500000-0000-4000-8000-000000000003'),
  'reserved', 'a missing device remains unavailable for sale'
);
select is(
  (select count(*) from public.inventory_movements
   where custody_item_id = (select id from public.inventory_custody_items
     where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000003')
     and movement_type = 'sale'),
  0::bigint, 'a missing report creates no sale movement or COGS'
);
select lives_ok(
  $$ select public.report_custody_incident(
       'a9100000-0000-4000-8000-000000000001',
       (select case_id from custody_test_results where name = 'unknown'),
       (select id from public.inventory_custody_items
         where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000003'),
       (select version from public.inventory_custody_cases
         where id = (select case_id from custody_test_results where name = 'unknown')),
       'damage', 'Synthetic damage report',
       '{"evidence_ref":"synthetic-condition-2"}'::jsonb,
       'custody-damage-report-01'
     ) $$,
  'damage is recorded as an incident and does not dispose of the device'
);
select lives_ok(
  $$ select public.report_custody_incident(
       'a9100000-0000-4000-8000-000000000001',
       (select case_id from custody_test_results where name = 'unknown'),
       (select id from public.inventory_custody_items
         where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000003'),
       (select version from public.inventory_custody_cases
         where id = (select case_id from custody_test_results where name = 'unknown')),
       'dispute', 'Synthetic custody dispute',
       '{"evidence_ref":"synthetic-note-3"}'::jsonb,
       'custody-dispute-report-01'
     ) $$,
  'a dispute is separately auditable and does not write off stock'
);
select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$ select public.resolve_custody_incident(
       'a9100000-0000-4000-8000-000000000001',
       (select incident_id from custody_test_results where name = 'missing'),
       (select version from public.inventory_custody_cases
         where id = (select case_id from custody_test_results where name = 'unknown')),
       1, 'located', '{"evidence_ref":"synthetic-review"}'::jsonb,
       'custody-staff-resolve-denied-01'
     ) $$,
  '42501', null, 'Inventory Staff cannot resolve custody incidents'
);
select lives_ok(
  $$ select public.return_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       (select case_id from custody_test_results where name = 'unknown'),
       (select version from public.inventory_custody_cases
         where id = (select case_id from custody_test_results where name = 'unknown')),
       jsonb_build_array(jsonb_build_object('item_id', (
         select id from public.inventory_custody_items
         where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000003'
       ), 'condition', 'Synthetic returned for review')),
       'custody-unknown-return-01'
     ) $$,
  'physical return with open incidents is recorded and quarantined'
);
select is(
  (select custody_state from public.serialized_inventory
   where id = 'a9500000-0000-4000-8000-000000000003'),
  'returned_quarantine', 'returned device remains unavailable until incident review'
);
select is(
  (select available_qty from public.inventory_balances
   where shop_id = 'a9100000-0000-4000-8000-000000000001'
     and branch_id = 'a9200000-0000-4000-8000-000000000001'
     and variant_id = 'a9400000-0000-4000-8000-000000000001'
     and valuation_status = 'unknown_cost'),
  0, 'quarantined unknown-cost stock is not available'
);
reset role;

select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000002', true);
set local role authenticated;
select lives_ok(
  $$ select public.resolve_custody_incident(
       'a9100000-0000-4000-8000-000000000001',
       (select incident_id from custody_test_results where name = 'missing'),
       (select version from public.inventory_custody_cases
         where id = (select case_id from custody_test_results where name = 'unknown')),
       1, 'located', '{"evidence_ref":"synthetic-device-located"}'::jsonb,
       'custody-missing-resolve-01'
     ) $$,
  'an assigned Manager can resolve a missing report with evidence and no write-off'
);
select is(
  (select custody_state from public.serialized_inventory
   where id = 'a9500000-0000-4000-8000-000000000003'),
  'returned_quarantine', 'one resolved incident does not release a device with other open incidents'
);
select lives_ok(
  $$ select public.resolve_custody_incident(
       'a9100000-0000-4000-8000-000000000001',
       (select id from public.inventory_custody_incidents
        where item_id = (select id from public.inventory_custody_items
          where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000003')
          and incident_type = 'damage'),
       (select version from public.inventory_custody_cases
         where id = (select case_id from custody_test_results where name = 'unknown')),
       1, 'cleared_no_value_change', '{"evidence_ref":"synthetic-inspection"}'::jsonb,
       'custody-damage-resolve-01'
     ) $$,
  'Manager may document a nonfinancial damage resolution after return'
);
select lives_ok(
  $$ select public.resolve_custody_incident(
       'a9100000-0000-4000-8000-000000000001',
       (select id from public.inventory_custody_incidents
        where item_id = (select id from public.inventory_custody_items
          where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000003')
          and incident_type = 'dispute'),
       (select version from public.inventory_custody_cases
         where id = (select case_id from custody_test_results where name = 'unknown')),
       1, 'resolved_no_loss', '{"evidence_ref":"synthetic-review"}'::jsonb,
       'custody-dispute-resolve-01'
     ) $$,
  'Manager may resolve a dispute without financial disposal'
);
select is(
  (select custody_state from public.serialized_inventory
   where id = 'a9500000-0000-4000-8000-000000000003'),
  'none', 'returned device is released only after authorized evidence-backed review'
);
select is(
  (select availability_status::text from public.serialized_inventory
   where id = 'a9500000-0000-4000-8000-000000000003'),
  'available', 'incident resolution restores availability without creating a movement'
);
select is(
  (select unit_cost_shop is null from public.serialized_inventory
   where id = 'a9500000-0000-4000-8000-000000000003'),
  true, 'incident resolution does not convert unknown cost into zero'
);
select is(
  (select count(*) from public.inventory_movements
   where custody_item_id = (select id from public.inventory_custody_items
     where serialized_inventory_id = 'a9500000-0000-4000-8000-000000000003')
     and movement_type = 'custody_out'),
  1::bigint, 'reporting and resolving incidents do not duplicate handover movement'
);
reset role;

-- Requested cases may be cancelled before handover; post-handover cancellation is denied.
select set_config('request.jwt.claim.sub', 'a9000000-0000-4000-8000-000000000004', true);
set local role authenticated;
select lives_ok(
  $$ insert into custody_test_results (name, case_id)
     values ('cancelled', public.request_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       'a9200000-0000-4000-8000-000000000001',
       'Synthetic cancellation test', 'Pre-handover cancellation',
       (select payload from custody_test_payloads where name = 'unknown'),
       'custody-cancel-request-01'
     )) $$,
  'staff may request a separate custody episode after the prior one is returned'
);
select lives_ok(
  $$ select public.cancel_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       (select case_id from custody_test_results where name = 'cancelled'),
       1, 'Synthetic reason before handover', 'custody-cancel-before-handover-01'
     ) $$,
  'the requester may cancel an unapproved case before handover'
);
select is(
  (select custody_state from public.serialized_inventory
   where id = 'a9500000-0000-4000-8000-000000000003'),
  'none', 'pre-handover cancellation releases the device claim'
);
select throws_ok(
  $$ select public.cancel_inventory_custody(
       'a9100000-0000-4000-8000-000000000001',
       (select case_id from custody_test_results where name = 'multi'),
       5, 'Too late', 'custody-cancel-after-handover-01'
     ) $$,
  '40001', null, 'a returned or handed-over case cannot use pre-handover cancellation'
);
reset role;

-- Append-only audit protection remains effective even for a privileged SQL role.
select throws_ok(
  $$ update public.inventory_custody_events set event_data = '{"tampered":true}'::jsonb
     where case_id = (select case_id from custody_test_results where name = 'multi') $$,
  '42501', null, 'custody event history rejects updates'
);
select throws_ok(
  $$ delete from public.inventory_custody_events
     where case_id = (select case_id from custody_test_results where name = 'multi') $$,
  '42501', null, 'custody event history rejects deletes'
);
select throws_ok(
  $$ truncate public.inventory_custody_events $$,
  '42501', null, 'custody event history rejects truncation'
);
select ok(
  not exists (
    select 1 from public.inventory_movements
    where movement_type = 'sale'
      and serialized_inventory_id in (
        'a9500000-0000-4000-8000-000000000001',
        'a9500000-0000-4000-8000-000000000002',
        'a9500000-0000-4000-8000-000000000003'
      )
  ),
  'custody, incidents, and nonfinancial resolution create no sale or COGS movement'
);

select * from finish();
rollback;
