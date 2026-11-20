begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

-- Synthetic, fictional test fixtures only. Device identifiers are fabricated.
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('99000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'phase2-owner-a@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('99000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'phase2-manager-main@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('99000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'phase2-inventory-staff@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('99000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'phase2-sales-staff@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('99000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'phase2-suspended-staff@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('99000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'phase2-owner-b@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('99000000-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'phase2-manager-secondary@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.shops (id, name, created_by) values
  ('99100000-0000-4000-8000-000000000001', 'Fictional Serialized Shop A', '99000000-0000-4000-8000-000000000001'),
  ('99100000-0000-4000-8000-000000000002', 'Fictional Serialized Shop B', '99000000-0000-4000-8000-000000000006');

insert into public.shop_memberships (shop_id, user_id, role, status, created_by) values
  ('99100000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000001', 'owner', 'active', '99000000-0000-4000-8000-000000000001'),
  ('99100000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000002', 'manager', 'active', '99000000-0000-4000-8000-000000000001'),
  ('99100000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000003', 'inventory_staff', 'active', '99000000-0000-4000-8000-000000000001'),
  ('99100000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000004', 'sales_staff', 'active', '99000000-0000-4000-8000-000000000001'),
  ('99100000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000005', 'inventory_staff', 'suspended', '99000000-0000-4000-8000-000000000001'),
  ('99100000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000007', 'manager', 'active', '99000000-0000-4000-8000-000000000001'),
  ('99100000-0000-4000-8000-000000000002', '99000000-0000-4000-8000-000000000006', 'owner', 'active', '99000000-0000-4000-8000-000000000006');

insert into public.branches (id, shop_id, name, is_primary, is_active, created_by) values
  ('99200000-0000-4000-8000-000000000001', '99100000-0000-4000-8000-000000000001', 'A Main', true, true, '99000000-0000-4000-8000-000000000001'),
  ('99200000-0000-4000-8000-000000000002', '99100000-0000-4000-8000-000000000001', 'A Secondary', false, true, '99000000-0000-4000-8000-000000000001'),
  ('99200000-0000-4000-8000-000000000004', '99100000-0000-4000-8000-000000000001', 'A Inactive', false, false, '99000000-0000-4000-8000-000000000001'),
  ('99200000-0000-4000-8000-000000000003', '99100000-0000-4000-8000-000000000002', 'B Main', true, true, '99000000-0000-4000-8000-000000000006');

insert into public.branch_memberships (shop_id, branch_id, user_id, created_by) values
  ('99100000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000002', '99000000-0000-4000-8000-000000000001'),
  ('99100000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000003', '99000000-0000-4000-8000-000000000001'),
  ('99100000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000002', '99000000-0000-4000-8000-000000000007', '99000000-0000-4000-8000-000000000001');

insert into public.products (
  id, shop_id, product_type, tracking_mode, name, created_by, updated_by
) values
  ('99300000-0000-4000-8000-000000000001', '99100000-0000-4000-8000-000000000001', 'smartphone', 'serialized', 'Fictional serialized phone', '99000000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000001'),
  ('99300000-0000-4000-8000-000000000002', '99100000-0000-4000-8000-000000000001', 'accessory', 'quantity', 'Fictional quantity item', '99000000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000001'),
  ('99300000-0000-4000-8000-000000000003', '99100000-0000-4000-8000-000000000002', 'smartphone', 'serialized', 'Fictional Shop B phone', '99000000-0000-4000-8000-000000000006', '99000000-0000-4000-8000-000000000006');

insert into public.product_variants (
  id, shop_id, product_id, created_by, updated_by
) values
  ('99400000-0000-4000-8000-000000000001', '99100000-0000-4000-8000-000000000001', '99300000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000001'),
  ('99400000-0000-4000-8000-000000000002', '99100000-0000-4000-8000-000000000001', '99300000-0000-4000-8000-000000000002', '99000000-0000-4000-8000-000000000001', '99000000-0000-4000-8000-000000000001'),
  ('99400000-0000-4000-8000-000000000003', '99100000-0000-4000-8000-000000000002', '99300000-0000-4000-8000-000000000003', '99000000-0000-4000-8000-000000000006', '99000000-0000-4000-8000-000000000006');

create temporary table phase2_receiving_results (
  test_name text primary key,
  receipt_id uuid not null
) on commit drop;
grant select, insert on phase2_receiving_results to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '99000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$ select public.configure_shop_operating_currency('99100000-0000-4000-8000-000000000001', 'USD') $$,
  'Owner configures Shop A currency before inventory is received'
);
select set_config('request.jwt.claim.sub', '99000000-0000-4000-8000-000000000006', true);
select lives_ok(
  $$ select public.configure_shop_operating_currency('99100000-0000-4000-8000-000000000002', 'USD') $$,
  'Owner configures Shop B currency before inventory is received'
);
reset role;

-- A legacy device has no reliable primary-identifier marker. The migration
-- preflight must name the unresolved device and leave its identifiers intact.
insert into public.serialized_inventory (
  id, shop_id, branch_id, variant_id, valuation_status,
  valuation_currency_code, unit_cost_shop, created_by, updated_by
) values (
  '99500000-0000-4000-8000-000000000001',
  '99100000-0000-4000-8000-000000000001',
  '99200000-0000-4000-8000-000000000001',
  '99400000-0000-4000-8000-000000000001',
  'known_cost', 'USD', 0,
  '99000000-0000-4000-8000-000000000001',
  '99000000-0000-4000-8000-000000000001'
);
insert into public.serialized_identifiers (
  id, shop_id, branch_id, serialized_inventory_id, identifier_type,
  raw_value, created_by
) values
  ('99600000-0000-4000-8000-000000000001', '99100000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000001', 'imei1', '987654321098765', '99000000-0000-4000-8000-000000000001'),
  ('99600000-0000-4000-8000-000000000002', '99100000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000001', 'serial', 'LEGACY-SERIAL-PRIMARY-UNKNOWN', '99000000-0000-4000-8000-000000000001');

select throws_ok(
  $$ select private.assert_serialized_identifier_primary_ready(
       '99100000-0000-4000-8000-000000000001',
       '99500000-0000-4000-8000-000000000001'
     ) $$,
  '55000',
  'Cannot safely assign primary identifiers to existing serialized devices: shop_id=99100000-0000-4000-8000-000000000001 serialized_inventory_id=99500000-0000-4000-8000-000000000001 identifier_count=2 primary_count=0 identifiers=99600000-0000-4000-8000-000000000001:imei1, 99600000-0000-4000-8000-000000000002:serial. No identifier or history rows were changed. Explicitly map the primary identifier for each listed device, then rerun this migration.',
  'legacy devices without an explicit primary marker are rejected instead of guessed'
);
select is(
  (select count(*)::integer
   from public.serialized_identifiers
   where serialized_inventory_id = '99500000-0000-4000-8000-000000000001'
     and not is_primary),
  2,
  'legacy compatibility check preserves every identifier without promoting one'
);
delete from public.serialized_identifiers
where serialized_inventory_id = '99500000-0000-4000-8000-000000000001';
delete from public.serialized_inventory
where id = '99500000-0000-4000-8000-000000000001';

create temporary table phase2_expected_device_fks (
  child_table regclass not null,
  constraint_name name not null,
  child_columns name[] not null,
  parent_table regclass not null,
  parent_columns name[] not null,
  primary key (child_table, constraint_name)
) on commit drop;
insert into phase2_expected_device_fks values
  ('public.serialized_identifiers'::regclass, 'serialized_identifiers_branch_snapshot_fk', array['shop_id', 'branch_id']::name[], 'public.branches'::regclass, array['shop_id', 'id']::name[]),
  ('public.serialized_identifiers'::regclass, 'serialized_identifiers_device_identity_fk', array['shop_id', 'serialized_inventory_id']::name[], 'public.serialized_inventory'::regclass, array['shop_id', 'id']::name[]),
  ('public.inventory_receipt_lines'::regclass, 'inventory_receipt_lines_device_identity_fk', array['shop_id', 'variant_id', 'serialized_inventory_id']::name[], 'public.serialized_inventory'::regclass, array['shop_id', 'variant_id', 'id']::name[]),
  ('public.inventory_movements'::regclass, 'inventory_movements_device_identity_fk', array['shop_id', 'variant_id', 'serialized_inventory_id']::name[], 'public.serialized_inventory'::regclass, array['shop_id', 'variant_id', 'id']::name[]);

select ok(
  (select count(*) = 4
   from phase2_expected_device_fks as expected
   where exists (
     select 1
     from pg_catalog.pg_constraint as constraint_row
     where constraint_row.conrelid = expected.child_table
       and constraint_row.conname = expected.constraint_name
       and constraint_row.contype = 'f'
       and constraint_row.confrelid = expected.parent_table
       and constraint_row.confdeltype = 'r'
       and constraint_row.convalidated
       and (select pg_catalog.array_agg(attribute.attname::name order by key_column.ordinality)
            from pg_catalog.unnest(constraint_row.conkey) with ordinality as key_column(attnum, ordinality)
            join pg_catalog.pg_attribute as attribute
              on attribute.attrelid = constraint_row.conrelid
             and attribute.attnum = key_column.attnum) = expected.child_columns
       and (select pg_catalog.array_agg(attribute.attname::name order by key_column.ordinality)
            from pg_catalog.unnest(constraint_row.confkey) with ordinality as key_column(attnum, ordinality)
            join pg_catalog.pg_attribute as attribute
              on attribute.attrelid = constraint_row.confrelid
             and attribute.attnum = key_column.attnum) = expected.parent_columns
   ))
  and (select count(*) = 3
       from pg_catalog.pg_constraint as constraint_row
       where constraint_row.contype = 'f'
         and constraint_row.confrelid = 'public.serialized_inventory'::regclass
         and constraint_row.conrelid = any (array[
           'public.serialized_identifiers'::regclass,
           'public.inventory_receipt_lines'::regclass,
           'public.inventory_movements'::regclass
         ])),
  'device identity and historical branch foreign keys match the approved stable-key definitions'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '99000000-0000-4000-8000-000000000002', true);
insert into phase2_receiving_results
select 'known_devices',
  public.receive_serialized_inventory(
    '99100000-0000-4000-8000-000000000001',
    '99200000-0000-4000-8000-000000000001',
    'serialized-positive-01',
    'supplier_invoice',
    'Fictional supplier',
    'TEST-SERIAL-POSITIVE',
    'USD',
    0.02,
    '[
      {"line_number":2,"variant_id":"99400000-0000-4000-8000-000000000001","original_line_amount":0.01,"identifiers":[{"identifier_type":"imei1","raw_value":"222222222222222","is_primary":true},{"identifier_type":"imei2","raw_value":"444444444444444","is_primary":false},{"identifier_type":"serial","raw_value":"DEVICE-TEST-2","is_primary":false}]},
      {"line_number":1,"variant_id":"99400000-0000-4000-8000-000000000001","original_line_amount":0.01,"identifiers":[{"identifier_type":"imei1","raw_value":"111111111111111","is_primary":true},{"identifier_type":"imei2","raw_value":"333333333333333","is_primary":false},{"identifier_type":"imei2","raw_value":"555555555555555","is_primary":false},{"identifier_type":"serial","raw_value":"DEVICE-TEST-1","is_primary":false}]}
    ]'::jsonb
  );

select is(
  (select count(*)::integer
   from public.inventory_receipt_lines as line
   join phase2_receiving_results as result on result.receipt_id = line.receipt_id
   where result.test_name = 'known_devices' and line.quantity = 1
     and line.serialized_inventory_id is not null),
  2,
  'each serialized receipt line contains exactly one device'
);
select is(
  (select count(*)::integer
   from public.serialized_identifiers as identifier
   join public.inventory_receipt_lines as line
     on line.shop_id = identifier.shop_id
    and line.serialized_inventory_id = identifier.serialized_inventory_id
   join phase2_receiving_results as result on result.receipt_id = line.receipt_id
   where result.test_name = 'known_devices'),
  7,
  'receiving stores primary and multiple secondary identifiers, including multiple IMEIs'
);
select is(
  (select count(*)::integer
   from public.serialized_identifiers as identifier
   join public.inventory_receipt_lines as line
     on line.shop_id = identifier.shop_id
    and line.serialized_inventory_id = identifier.serialized_inventory_id
   join phase2_receiving_results as result on result.receipt_id = line.receipt_id
   where result.test_name = 'known_devices' and identifier.is_primary),
  2,
  'each newly received device has exactly one designated primary identifier'
);
select is(
  (select count(*)::integer
   from public.inventory_balances
   where shop_id = '99100000-0000-4000-8000-000000000001'
     and branch_id = '99200000-0000-4000-8000-000000000001'
     and variant_id = '99400000-0000-4000-8000-000000000001'
     and valuation_status = 'known_cost'
     and on_hand_qty = 2 and available_qty = 2
     and carrying_value_shop = 0.02 and average_unit_cost_shop = 0.01),
  1,
  'positive-cost device balances reconcile in shop currency'
);
select is(
  (select count(*)::integer
   from public.inventory_movements as movement
   join public.inventory_receipt_lines as line
     on line.shop_id = movement.shop_id
    and line.branch_id = movement.branch_id
    and line.variant_id = movement.variant_id
    and line.id = movement.receipt_line_id
   join phase2_receiving_results as result
     on result.receipt_id = line.receipt_id
   where result.test_name = 'known_devices'
     and movement.serialized_inventory_id is not null),
  2,
  'receipt movements link each device to its immutable receipt line'
);
select is(
  (select count(*)::integer
   from public.inventory_movements as movement
   join public.inventory_receipts as receipt
     on receipt.shop_id = movement.shop_id
    and receipt.branch_id = movement.branch_id
    and receipt.operation_id = movement.operation_id
   join phase2_receiving_results as result on result.receipt_id = receipt.id
   where result.test_name = 'known_devices'
     and movement.movement_type = 'receipt'
     and movement.on_hand_delta = 1 and movement.available_delta = 1),
  2,
  'each receipt movement is auditable and increases stock exactly once'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '99000000-0000-4000-8000-000000000002', true);
select is(
  public.receive_serialized_inventory(
    '99100000-0000-4000-8000-000000000001',
    '99200000-0000-4000-8000-000000000001',
    'serialized-positive-01',
    'supplier_invoice',
    'Fictional supplier',
    'TEST-SERIAL-POSITIVE',
    'USD',
    0.02,
    '[
      {"line_number":2,"variant_id":"99400000-0000-4000-8000-000000000001","original_line_amount":0.01,"identifiers":[{"identifier_type":"imei1","raw_value":"222222222222222","is_primary":true},{"identifier_type":"imei2","raw_value":"444444444444444","is_primary":false},{"identifier_type":"serial","raw_value":"DEVICE-TEST-2","is_primary":false}]},
      {"line_number":1,"variant_id":"99400000-0000-4000-8000-000000000001","original_line_amount":0.01,"identifiers":[{"identifier_type":"imei1","raw_value":"111111111111111","is_primary":true},{"identifier_type":"imei2","raw_value":"333333333333333","is_primary":false},{"identifier_type":"imei2","raw_value":"555555555555555","is_primary":false},{"identifier_type":"serial","raw_value":"DEVICE-TEST-1","is_primary":false}]}
    ]'::jsonb
  ),
  (select receipt_id from phase2_receiving_results where test_name = 'known_devices'),
  'retrying the same request returns its original receipt'
);
select throws_ok(
  $$ select public.receive_serialized_inventory(
    '99100000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000001',
    'serialized-positive-01', 'supplier_invoice', 'Fictional supplier',
    'TEST-SERIAL-CHANGED', 'USD', 0.02,
    '[{"line_number":1,"variant_id":"99400000-0000-4000-8000-000000000001","original_line_amount":0.02,"identifiers":[{"identifier_type":"imei1","raw_value":"666666666666666","is_primary":true}]}]'::jsonb
  ) $$,
  '22023', null,
  'the same idempotency key cannot accept changed serialized receipt contents'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '99000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$ select public.receive_serialized_inventory(
    '99100000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000001',
    'serialized-duplicate-01', 'supplier_invoice', 'Fictional supplier',
    'TEST-SERIAL-DUPLICATE', 'USD', 0.01,
    '[{"line_number":1,"variant_id":"99400000-0000-4000-8000-000000000001","original_line_amount":0.01,"identifiers":[{"identifier_type":"imei1","raw_value":"111111111111111","is_primary":true}]}]'::jsonb
  ) $$,
  '23505', null,
  'normalized primary or secondary identifiers cannot collide within a shop'
);
select throws_ok(
  $$ select public.receive_serialized_inventory(
    '99100000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000001',
    'serialized-secondary-collision1', 'supplier_invoice', 'Fictional supplier',
    'TEST-SECONDARY-COLLISION', 'USD', 0.01,
    '[{"line_number":1,"variant_id":"99400000-0000-4000-8000-000000000001","original_line_amount":0.01,"identifiers":[{"identifier_type":"serial","raw_value":"111111111111111","is_primary":true}]}]'::jsonb
  ) $$,
  '23505', null,
  'shop-wide uniqueness spans primary IMEIs and secondary serial identifiers'
);
select set_config('request.jwt.claim.sub', '99000000-0000-4000-8000-000000000006', true);
select lives_ok(
  $$ select public.receive_serialized_inventory(
    '99100000-0000-4000-8000-000000000002', '99200000-0000-4000-8000-000000000003',
    'serialized-other-shop1', 'supplier_invoice', 'Fictional supplier',
    'TEST-SHOP-B-SERIAL', 'USD', 0,
    '[{"line_number":1,"variant_id":"99400000-0000-4000-8000-000000000003","original_line_amount":0,"identifiers":[{"identifier_type":"imei1","raw_value":"111111111111111","is_primary":true}]}]'::jsonb
  ) $$,
  'the same normalized identifier may exist in a separate shop tenant'
);

select set_config('request.jwt.claim.sub', '99000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$ select public.receive_serialized_inventory(
    '99100000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000001',
    'serialized-no-primary1', 'supplier_invoice', 'Fictional supplier',
    'TEST-NO-PRIMARY', 'USD', 0,
    '[{"line_number":1,"variant_id":"99400000-0000-4000-8000-000000000001","original_line_amount":0,"identifiers":[{"identifier_type":"serial","raw_value":"NO-PRIMARY-TEST","is_primary":false}]}]'::jsonb
  ) $$,
  '22023', null,
  'serialized receiving rejects a device without exactly one primary identifier'
);
select throws_ok(
  $$ select public.receive_serialized_inventory(
    '99100000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000001',
    'serialized-two-primary1', 'supplier_invoice', 'Fictional supplier',
    'TEST-TWO-PRIMARY', 'USD', 0,
    '[{"line_number":1,"variant_id":"99400000-0000-4000-8000-000000000001","original_line_amount":0,"identifiers":[{"identifier_type":"serial","raw_value":"PRIMARY-A-TEST","is_primary":true},{"identifier_type":"serial","raw_value":"PRIMARY-B-TEST","is_primary":true}]}]'::jsonb
  ) $$,
  '22023', null,
  'serialized receiving rejects more than one primary identifier'
);
select throws_ok(
  $$ select public.receive_serialized_inventory(
    '99100000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000001',
    'serialized-bad-imei01', 'supplier_invoice', 'Fictional supplier',
    'TEST-BAD-IMEI', 'USD', 0,
    '[{"line_number":1,"variant_id":"99400000-0000-4000-8000-000000000001","original_line_amount":0,"identifiers":[{"identifier_type":"imei1","raw_value":"12345","is_primary":true}]}]'::jsonb
  ) $$,
  '22023', null,
  'IMEI identifiers must contain exactly fifteen normalized digits'
);
select throws_ok(
  $$ select public.receive_serialized_inventory(
    '99100000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000001',
    'serialized-quantity1', 'supplier_invoice', 'Fictional supplier',
    'TEST-QUANTITY-TRACKED', 'USD', 0,
    '[{"line_number":1,"variant_id":"99400000-0000-4000-8000-000000000002","original_line_amount":0,"identifiers":[{"identifier_type":"serial","raw_value":"WRONG-TRACKING-MODE","is_primary":true}]}]'::jsonb
  ) $$,
  '22023', null,
  'serialized receiving rejects quantity-tracked variants'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '99000000-0000-4000-8000-000000000003', true);
insert into phase2_receiving_results
select 'unknown_cost',
  public.receive_serialized_inventory(
    '99100000-0000-4000-8000-000000000001',
    '99200000-0000-4000-8000-000000000001',
    'serialized-unknown-01',
    'manual_unknown_cost',
    null, null, null, null,
    '[{"line_number":1,"variant_id":"99400000-0000-4000-8000-000000000001","identifiers":[{"identifier_type":"serial","raw_value":"UNKNOWN-COST-TEST-01","is_primary":true}]}]'::jsonb
  );
select is(
  (select count(*)::integer
   from public.inventory_balances
   where shop_id = '99100000-0000-4000-8000-000000000001'
     and branch_id = '99200000-0000-4000-8000-000000000001'
     and variant_id = '99400000-0000-4000-8000-000000000001'
     and valuation_status = 'unknown_cost'
     and on_hand_qty = 1 and available_qty = 1
     and carrying_value_shop is null and average_unit_cost_shop is null),
  1,
  'unknown-cost serialized stock remains separate and unvalued'
);
select set_config('request.jwt.claim.sub', '99000000-0000-4000-8000-000000000002', true);
insert into phase2_receiving_results
select 'known_zero',
  public.receive_serialized_inventory(
    '99100000-0000-4000-8000-000000000001',
    '99200000-0000-4000-8000-000000000001',
    'serialized-zero-cost1',
    'supplier_invoice',
    'Fictional supplier',
    'TEST-SERIAL-ZERO',
    'USD',
    0,
    '[{"line_number":1,"variant_id":"99400000-0000-4000-8000-000000000001","original_line_amount":0,"identifiers":[{"identifier_type":"serial","raw_value":"KNOWN-ZERO-TEST-01","is_primary":true}]}]'::jsonb
  );
select is(
  (select count(*)::integer
   from public.serialized_inventory as item
   join public.inventory_receipt_lines as line
     on line.shop_id = item.shop_id
    and line.variant_id = item.variant_id
    and line.serialized_inventory_id = item.id
   join phase2_receiving_results as result on result.receipt_id = line.receipt_id
   where result.test_name = 'known_zero'
     and item.valuation_status = 'known_cost'
     and item.unit_cost_shop = 0),
  1,
  'explicit zero remains a known-cost serialized device'
);

insert into phase2_receiving_results
select 'pending_fx',
  public.receive_serialized_inventory(
    '99100000-0000-4000-8000-000000000001',
    '99200000-0000-4000-8000-000000000001',
    'serialized-pending-fx1',
    'supplier_invoice',
    'Fictional supplier',
    'TEST-SERIAL-PENDING',
    'CAD',
    1,
    '[{"line_number":1,"variant_id":"99400000-0000-4000-8000-000000000001","original_line_amount":1,"identifiers":[{"identifier_type":"serial","raw_value":"PENDING-FX-TEST-01","is_primary":true}]}]'::jsonb,
    null, null, null, null, null, true
  );
select is(
  (select count(*)::integer
   from public.serialized_inventory as item
   join public.inventory_receipt_lines as line
     on line.shop_id = item.shop_id
    and line.variant_id = item.variant_id
    and line.serialized_inventory_id = item.id
   join phase2_receiving_results as result on result.receipt_id = line.receipt_id
   where result.test_name = 'pending_fx'
     and item.valuation_status = 'pending_fx'
     and item.availability_status = 'pending_fx'
     and item.unit_cost_shop is null),
  1,
  'Pending-FX devices remain unavailable and unvalued'
);
select is(
  (select count(*)::integer
   from public.inventory_balances
   where shop_id = '99100000-0000-4000-8000-000000000001'
     and branch_id = '99200000-0000-4000-8000-000000000001'
     and variant_id = '99400000-0000-4000-8000-000000000001'
     and valuation_status = 'pending_fx'
     and on_hand_qty = 1 and available_qty = 0
     and carrying_value_shop is null),
  1,
  'Pending-FX devices are excluded from available valued stock'
);

select set_config('request.jwt.claim.sub', '99000000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$ select public.receive_serialized_inventory(
    '99100000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000001',
    'serialized-sales-deny1', 'manual_unknown_cost', null, null, null, null,
    '[{"line_number":1,"variant_id":"99400000-0000-4000-8000-000000000001","identifiers":[{"identifier_type":"serial","raw_value":"SALES-DENIED-TEST","is_primary":true}]}]'::jsonb
  ) $$,
  '42501', null,
  'sales staff cannot receive serialized inventory'
);
select set_config('request.jwt.claim.sub', '99000000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$ select public.receive_serialized_inventory(
    '99100000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000001',
    'serialized-suspended1', 'manual_unknown_cost', null, null, null, null,
    '[{"line_number":1,"variant_id":"99400000-0000-4000-8000-000000000001","identifiers":[{"identifier_type":"serial","raw_value":"SUSPENDED-DENY-TEST","is_primary":true}]}]'::jsonb
  ) $$,
  '42501', null,
  'suspended inventory staff cannot receive serialized inventory'
);
select set_config('request.jwt.claim.sub', '99000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$ select public.receive_serialized_inventory(
    '99100000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000002',
    'serialized-branch-deny1', 'manual_unknown_cost', null, null, null, null,
    '[{"line_number":1,"variant_id":"99400000-0000-4000-8000-000000000001","identifiers":[{"identifier_type":"serial","raw_value":"BRANCH-DENY-TEST","is_primary":true}]}]'::jsonb
  ) $$,
  '42501', null,
  'a Manager without assignment cannot receive in a different branch'
);
select set_config('request.jwt.claim.sub', '99000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$ select public.receive_serialized_inventory(
    '99100000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000003',
    'serialized-cross-shop1', 'manual_unknown_cost', null, null, null, null,
    '[{"line_number":1,"variant_id":"99400000-0000-4000-8000-000000000001","identifiers":[{"identifier_type":"serial","raw_value":"CROSS-SHOP-DENY-TEST","is_primary":true}]}]'::jsonb
  ) $$,
  '42501', null,
  'authorized staff cannot receive into another shop branch'
);
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$ select public.receive_serialized_inventory(
    '99100000-0000-4000-8000-000000000001', '99200000-0000-4000-8000-000000000001',
    'serialized-anonymous1', 'manual_unknown_cost', null, null, null, null,
    '[{"line_number":1,"variant_id":"99400000-0000-4000-8000-000000000001","identifiers":[{"identifier_type":"serial","raw_value":"ANONYMOUS-DENY-TEST","is_primary":true}]}]'::jsonb
  ) $$,
  '42501', null,
  'anonymous sessions cannot receive serialized inventory'
);

set local role service_role;
select throws_ok(
  $$ insert into public.serialized_inventory default values $$,
  '42501', null,
  'service_role cannot directly create serialized inventory'
);
select throws_ok(
  $$ truncate table public.serialized_identifiers $$,
  '42501', null,
  'service_role cannot truncate serialized identifiers'
);
reset role;

-- Prove historical references stay valid when only the current item branch
-- changes. This is a synthetic schema invariant check, not a transfer RPC.
update public.serialized_inventory as item
set branch_id = '99200000-0000-4000-8000-000000000002'
where item.id = (
  select line.serialized_inventory_id
  from public.inventory_receipt_lines as line
  join phase2_receiving_results as result on result.receipt_id = line.receipt_id
  where result.test_name = 'known_devices'
  order by line.line_number
  limit 1
);
select is(
  (select count(*)::integer
   from public.inventory_receipt_lines as line
   join phase2_receiving_results as result on result.receipt_id = line.receipt_id
   where result.test_name = 'known_devices'
     and line.branch_id = '99200000-0000-4000-8000-000000000001'
     and line.serialized_inventory_id is not null),
  2,
  'receipt history keeps its original branch while device identity remains stable'
);
select is(
  (select count(*)::integer
   from public.inventory_movements as movement
   join public.inventory_receipts as receipt
     on receipt.shop_id = movement.shop_id
    and receipt.branch_id = movement.branch_id
    and receipt.operation_id = movement.operation_id
   join phase2_receiving_results as result on result.receipt_id = receipt.id
   where result.test_name = 'known_devices'
     and movement.branch_id = '99200000-0000-4000-8000-000000000001'
     and movement.serialized_inventory_id is not null),
  2,
  'movement history keeps its original branch after the device branch changes'
);
select set_config('request.jwt.claim.sub', '99000000-0000-4000-8000-000000000007', true);
set local role authenticated;
select is(
  (select count(*)::integer
   from public.serialized_identifiers
   where normalized_value = '111111111111111'),
  1,
  'identifier access follows the device current authorized branch'
);
select set_config('request.jwt.claim.sub', '99000000-0000-4000-8000-000000000003', true);
select is(
  (select count(*)::integer
   from public.serialized_identifiers
   where normalized_value = '111111111111111'),
  0,
  'the former branch assignee no longer sees identifiers after the device moves'
);

select ok(
  (select count(*) = 15 and bool_and(
    not pg_catalog.has_table_privilege('service_role', relation.oid, 'INSERT')
    and not pg_catalog.has_table_privilege('service_role', relation.oid, 'UPDATE')
    and not pg_catalog.has_table_privilege('service_role', relation.oid, 'DELETE')
    and not pg_catalog.has_table_privilege('service_role', relation.oid, 'TRUNCATE')
  )
   from pg_catalog.pg_class as relation
   join pg_catalog.pg_namespace as namespace on namespace.oid = relation.relnamespace
   where namespace.nspname = 'public'
     and relation.relkind = 'r'
     and relation.relname = any(array[
       'currency_codes', 'shop_settings', 'products', 'product_variants',
       'product_identifiers', 'serialized_inventory', 'serialized_identifiers',
       'exchange_rate_snapshots', 'inventory_operations', 'inventory_receipts',
       'inventory_receipt_lines', 'inventory_balances', 'branch_variant_prices',
       'inventory_fx_resolutions', 'inventory_movements'
     ])),
  'service_role retains no direct write or TRUNCATE privileges on protected inventory tables'
);

select * from finish();
rollback;
