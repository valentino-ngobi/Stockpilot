begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

-- Fictional test identities, receipts, and exchange-rate evidence.
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('99500000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'fx-owner@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('99500000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'fx-manager@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('99500000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'fx-inventory-staff@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('99500000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'fx-sales-staff@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('99500000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'fx-suspended-staff@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('99500000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'fx-other-owner@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.shops (id, name, created_by) values
  ('99600000-0000-4000-8000-000000000001', 'Fictional FX Shop', '99500000-0000-4000-8000-000000000001'),
  ('99600000-0000-4000-8000-000000000002', 'Fictional Other FX Shop', '99500000-0000-4000-8000-000000000006');

insert into public.shop_memberships (shop_id, user_id, role, status, created_by) values
  ('99600000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000001', 'owner', 'active', '99500000-0000-4000-8000-000000000001'),
  ('99600000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000002', 'manager', 'active', '99500000-0000-4000-8000-000000000001'),
  ('99600000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000003', 'inventory_staff', 'active', '99500000-0000-4000-8000-000000000001'),
  ('99600000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000004', 'sales_staff', 'active', '99500000-0000-4000-8000-000000000001'),
  ('99600000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000005', 'inventory_staff', 'suspended', '99500000-0000-4000-8000-000000000001'),
  ('99600000-0000-4000-8000-000000000002', '99500000-0000-4000-8000-000000000006', 'owner', 'active', '99500000-0000-4000-8000-000000000006');

insert into public.branches (id, shop_id, name, is_primary, is_active, created_by) values
  ('99700000-0000-4000-8000-000000000001', '99600000-0000-4000-8000-000000000001', 'FX Main', true, true, '99500000-0000-4000-8000-000000000001'),
  ('99700000-0000-4000-8000-000000000002', '99600000-0000-4000-8000-000000000001', 'FX Restricted', false, true, '99500000-0000-4000-8000-000000000001'),
  ('99700000-0000-4000-8000-000000000003', '99600000-0000-4000-8000-000000000002', 'Other FX Main', true, true, '99500000-0000-4000-8000-000000000006');

insert into public.branch_memberships (shop_id, branch_id, user_id, created_by) values
  ('99600000-0000-4000-8000-000000000001', '99700000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000002', '99500000-0000-4000-8000-000000000001'),
  ('99600000-0000-4000-8000-000000000001', '99700000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000003', '99500000-0000-4000-8000-000000000001');

insert into public.products (
  id, shop_id, product_type, tracking_mode, name, created_by, updated_by
) values
  ('99800000-0000-4000-8000-000000000001', '99600000-0000-4000-8000-000000000001', 'smartphone', 'serialized', 'Fictional FX phone', '99500000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000001'),
  ('99800000-0000-4000-8000-000000000002', '99600000-0000-4000-8000-000000000001', 'accessory', 'quantity', 'Fictional FX quantity item', '99500000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000001');

insert into public.product_variants (
  id, shop_id, product_id, created_by, updated_by
) values
  ('99900000-0000-4000-8000-000000000001', '99600000-0000-4000-8000-000000000001', '99800000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000001'),
  ('99900000-0000-4000-8000-000000000002', '99600000-0000-4000-8000-000000000001', '99800000-0000-4000-8000-000000000002', '99500000-0000-4000-8000-000000000001', '99500000-0000-4000-8000-000000000001');

create temporary table phase2_fx_results (
  test_name text primary key,
  receipt_id uuid not null
) on commit drop;
grant select, insert on phase2_fx_results to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '99500000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$ select public.configure_shop_operating_currency('99600000-0000-4000-8000-000000000001', 'USD') $$,
  'Owner explicitly configures the valuation currency'
);
reset role;

insert into public.exchange_rate_snapshots (
  id, from_currency_code, to_currency_code, rate_to_currency,
  rate_source, observed_at, fetched_at, valid_until
) values
  ('99910000-0000-4000-8000-000000000001', 'CAD', 'USD', 0.5,
   'fictional system source', now() - interval '1 minute', now(), now() + interval '1 day'),
  ('99910000-0000-4000-8000-000000000002', 'CAD', 'EUR', 0.7,
   'fictional wrong direction', now() - interval '1 minute', now(), now() + interval '1 day'),
  ('99910000-0000-4000-8000-000000000003', 'CAD', 'USD', 0.6,
   'fictional expired source', now() - interval '2 days', now() - interval '2 days', now() - interval '1 day');

set local role authenticated;
select set_config('request.jwt.claim.sub', '99500000-0000-4000-8000-000000000003', true);
insert into phase2_fx_results
select 'rounding_receipt',
  public.receive_serialized_inventory(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000001',
    'fx-pending-round-01',
    'supplier_invoice',
    'Fictional supplier',
    'TEST-FX-ROUNDING',
    'CAD',
    0.03,
    '[
      {"line_number":3,"variant_id":"99900000-0000-4000-8000-000000000001","original_line_amount":0.01,"identifiers":[{"identifier_type":"imei1","raw_value":"777777777777771","is_primary":true}]},
      {"line_number":1,"variant_id":"99900000-0000-4000-8000-000000000001","original_line_amount":0.01,"identifiers":[{"identifier_type":"imei1","raw_value":"777777777777772","is_primary":true}]},
      {"line_number":2,"variant_id":"99900000-0000-4000-8000-000000000001","original_line_amount":0.01,"identifiers":[{"identifier_type":"imei1","raw_value":"777777777777773","is_primary":true}]}
    ]'::jsonb,
    null, null, null, null, null, true
  );
reset role;

create temporary table phase2_fx_release_results (
  test_name text primary key,
  operation_id uuid not null
) on commit drop;
grant select, insert on phase2_fx_release_results to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '99500000-0000-4000-8000-000000000002', true);
insert into phase2_fx_release_results
select 'rounding_release',
  public.release_pending_fx_receipt(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000001',
    (select receipt_id from phase2_fx_results where test_name = 'rounding_receipt'),
    'fx-release-system-01',
    '99910000-0000-4000-8000-000000000001'
  );
select is(
  (select count(*)::integer
   from public.inventory_fx_resolutions as resolution
   join phase2_fx_results as result
     on result.receipt_id = (
       select line.receipt_id
       from public.inventory_receipt_lines as line
       where line.id = resolution.receipt_line_id
     )
   where result.test_name = 'rounding_receipt'
     and resolution.accepted_fx_rate = 0.5
     and resolution.rate_snapshot_id = '99910000-0000-4000-8000-000000000001'
     and resolution.accepted_by = '99500000-0000-4000-8000-000000000002'),
  3,
  'Manager accepts a valid system rate for every pending receipt line'
);
select is(
  (select converted_invoice_amount_shop
   from public.inventory_receipts as receipt
   join phase2_fx_results as result on result.receipt_id = receipt.id
   where result.test_name = 'rounding_receipt'),
  null::numeric,
  'immutable receipt evidence does not rewrite the original pending conversion field'
);
select is(
  (select sum(resolution.converted_line_amount_shop)
   from public.inventory_fx_resolutions as resolution
   join public.inventory_receipt_lines as line
     on line.shop_id = resolution.shop_id
    and line.branch_id = resolution.branch_id
    and line.id = resolution.receipt_line_id
   join phase2_fx_results as result on result.receipt_id = line.receipt_id
   where result.test_name = 'rounding_receipt'),
  0.02::numeric,
  'released line amounts exactly reconcile to the rounded shop-currency invoice total'
);
select is(
  (select string_agg(
      line.line_number::text || ':' || round(resolution.converted_line_amount_shop, 2)::text,
      ',' order by line.line_number
    )
   from public.inventory_fx_resolutions as resolution
   join public.inventory_receipt_lines as line
     on line.shop_id = resolution.shop_id
    and line.branch_id = resolution.branch_id
    and line.id = resolution.receipt_line_id
   join phase2_fx_results as result on result.receipt_id = line.receipt_id
   where result.test_name = 'rounding_receipt'),
  '1:0.01,2:0.01,3:0.00',
  'largest-remainder rounding is deterministic by ascending receipt line'
);
select is(
  (select count(*)::integer
   from public.inventory_balances
   where shop_id = '99600000-0000-4000-8000-000000000001'
     and branch_id = '99700000-0000-4000-8000-000000000001'
     and variant_id = '99900000-0000-4000-8000-000000000001'
     and valuation_status = 'pending_fx'
     and on_hand_qty = 0 and available_qty = 0),
  1,
  'release removes all received units from the pending balance'
);
select is(
  (select count(*)::integer
   from public.inventory_balances
   where shop_id = '99600000-0000-4000-8000-000000000001'
     and branch_id = '99700000-0000-4000-8000-000000000001'
     and variant_id = '99900000-0000-4000-8000-000000000001'
     and valuation_status = 'known_cost'
     and on_hand_qty = 3 and available_qty = 3
     and carrying_value_shop = 0.02
     and average_unit_cost_shop = 0.0066666667),
  1,
  'known aggregate balance has exact value and ten-place weighted-average cost'
);
select is(
  (select count(*)::integer
   from public.serialized_inventory as item
   join public.inventory_receipt_lines as line
     on line.shop_id = item.shop_id
    and line.variant_id = item.variant_id
    and line.serialized_inventory_id = item.id
   join phase2_fx_results as result on result.receipt_id = line.receipt_id
   where result.test_name = 'rounding_receipt'
     and item.valuation_status = 'known_cost'
     and item.availability_status = 'available'
     and item.unit_cost_shop is not null),
  3,
  'released serialized devices become available and receive known unit costs'
);
select is(
  (select count(*)::integer
   from public.inventory_movements as movement
   join phase2_fx_release_results as release
     on release.operation_id = movement.operation_id
   where release.test_name = 'rounding_release'
     and movement.fx_resolution_id is not null
     and movement.movement_type = 'fx_release'),
  6,
  'each resolved line has paired pending-out and known-in movements'
);
select is(
  (select sum(movement.on_hand_delta)::integer
   from public.inventory_movements as movement
   join phase2_fx_release_results as release
     on release.operation_id = movement.operation_id
   where release.test_name = 'rounding_release'
     and movement.valuation_status = 'pending_fx'),
  -3,
  'pending release movements remove the exact physical quantity'
);
select is(
  (select sum(movement.on_hand_delta)::integer
   from public.inventory_movements as movement
   join phase2_fx_release_results as release
     on release.operation_id = movement.operation_id
   where release.test_name = 'rounding_release'
     and movement.valuation_status = 'known_cost'),
  3,
  'known-cost release movements add the exact physical quantity'
);
select is(
  (select sum(movement.extended_cost_shop)
   from public.inventory_movements as movement
   join phase2_fx_release_results as release
     on release.operation_id = movement.operation_id
   where release.test_name = 'rounding_release'
     and movement.valuation_status = 'known_cost'),
  0.02::numeric,
  'known-cost movement value reconciles to the accepted invoice conversion'
);

insert into phase2_fx_results
select 'quantity_pending',
  public.receive_quantity_inventory(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000001',
    'fx-pending-quantity1',
    'supplier_invoice',
    'Fictional supplier',
    'TEST-FX-QUANTITY',
    'CAD',
    0.03,
    '[{"line_number":1,"variant_id":"99900000-0000-4000-8000-000000000002","quantity":2,"original_line_amount":0.03}]'::jsonb,
    null, null, null, null, null, true
  );
insert into phase2_fx_release_results
select 'quantity_release',
  public.release_pending_fx_receipt(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000001',
    (select receipt_id from phase2_fx_results where test_name = 'quantity_pending'),
    'fx-release-quantity-01',
    '99910000-0000-4000-8000-000000000001'
  );
select is(
  (select count(*)::integer
   from public.inventory_receipt_lines as line
   join phase2_fx_results as result on result.receipt_id = line.receipt_id
   where result.test_name = 'quantity_pending'
     and line.serialized_inventory_id is null and line.quantity = 2),
  1,
  'whole-receipt release also supports existing quantity-tracked pending receipts'
);
select is(
  (select count(*)::integer
   from public.inventory_balances
   where shop_id = '99600000-0000-4000-8000-000000000001'
     and branch_id = '99700000-0000-4000-8000-000000000001'
     and variant_id = '99900000-0000-4000-8000-000000000002'
     and valuation_status = 'known_cost'
     and on_hand_qty = 2 and available_qty = 2
     and carrying_value_shop = 0.02 and average_unit_cost_shop = 0.01),
  1,
  'quantity-tracked release reconciles its aggregate value and quantity'
);
select is(
  (select count(*)::integer
   from public.inventory_movements as movement
   join phase2_fx_release_results as release
     on release.operation_id = movement.operation_id
   where release.test_name = 'quantity_release'
     and movement.valuation_status = 'known_cost'
     and movement.on_hand_delta = 2
     and movement.extended_cost_shop = 0.02),
  1,
  'quantity release movement records the complete converted line amount'
);

select is(
  public.release_pending_fx_receipt(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000001',
    (select receipt_id from phase2_fx_results where test_name = 'rounding_receipt'),
    'fx-release-system-01',
    '99910000-0000-4000-8000-000000000001'
  ),
  (select operation_id from phase2_fx_release_results where test_name = 'rounding_release'),
  'same release key and evidence return the original release operation'
);
select throws_ok(
  $$ select public.release_pending_fx_receipt(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000001',
    (select receipt_id from phase2_fx_results where test_name = 'rounding_receipt'),
    'fx-release-different-key1',
    '99910000-0000-4000-8000-000000000001'
  ) $$,
  '22023', null,
  'a second release with a different key cannot resolve the same receipt again'
);

select set_config('request.jwt.claim.sub', '99500000-0000-4000-8000-000000000003', true);
insert into phase2_fx_results
select 'manual_manager',
  public.receive_serialized_inventory(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000001',
    'fx-pending-manual-mgr1',
    'supplier_invoice',
    'Fictional supplier',
    'TEST-FX-MANUAL-MANAGER',
    'CAD',
    1,
    '[{"line_number":1,"variant_id":"99900000-0000-4000-8000-000000000001","original_line_amount":1,"identifiers":[{"identifier_type":"serial","raw_value":"FX-MANUAL-MGR-TEST","is_primary":true}]}]'::jsonb,
    null, null, null, null, null, true
  );
select set_config('request.jwt.claim.sub', '99500000-0000-4000-8000-000000000002', true);
insert into phase2_fx_release_results
select 'manual_manager',
  public.release_pending_fx_receipt(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000001',
    (select receipt_id from phase2_fx_results where test_name = 'manual_manager'),
    'fx-release-manager-manual1',
    null,
    0.75,
    'fictional manager quote',
    now() - interval '1 minute',
    'Manager documented the synthetic supplier quote',
    null
  );
select is(
  (select count(*)::integer
   from public.inventory_fx_resolutions as resolution
   join public.inventory_receipt_lines as line
     on line.shop_id = resolution.shop_id
    and line.branch_id = resolution.branch_id
    and line.id = resolution.receipt_line_id
   join phase2_fx_results as result on result.receipt_id = line.receipt_id
   where result.test_name = 'manual_manager'
     and resolution.accepted_fx_rate = 0.75
     and resolution.rate_source = 'manual_override: fictional manager quote'
     and resolution.override_approved_by = '99500000-0000-4000-8000-000000000002'
     and resolution.override_reason = 'Manager documented the synthetic supplier quote'
     and resolution.suggested_fx_rate = 0.5
     and resolution.suggested_rate_snapshot_id = '99910000-0000-4000-8000-000000000001'
     and resolution.accepted_by = '99500000-0000-4000-8000-000000000002'
     and resolution.rate_accepted_at is not null),
  1,
  'Manager override records accepted and available suggested rate evidence'
);

insert into phase2_fx_results
select 'staff_manual_denied',
  public.receive_serialized_inventory(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000001',
    'fx-pending-staff-deny1',
    'supplier_invoice',
    'Fictional supplier',
    'TEST-FX-STAFF-DENIED',
    'CAD',
    1,
    '[{"line_number":1,"variant_id":"99900000-0000-4000-8000-000000000001","original_line_amount":1,"identifiers":[{"identifier_type":"serial","raw_value":"FX-STAFF-DENY-TEST","is_primary":true}]}]'::jsonb,
    null, null, null, null, null, true
  );
select set_config('request.jwt.claim.sub', '99500000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$ select public.release_pending_fx_receipt(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000001',
    (select receipt_id from phase2_fx_results where test_name = 'staff_manual_denied'),
    'fx-release-staff-manual1',
    null,
    0.8,
    'fictional staff quote',
    now() - interval '1 minute',
    'Inventory staff may not approve manual FX',
    null
  ) $$,
  '42501', null,
  'ordinary inventory staff cannot approve manual FX overrides'
);

select set_config('request.jwt.claim.sub', '99500000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$ select public.release_pending_fx_receipt(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000001',
    (select receipt_id from phase2_fx_results where test_name = 'staff_manual_denied'),
    'fx-release-missing-rate1'
  ) $$,
  '22023', null,
  'release rejects a missing exchange rate'
);
select throws_ok(
  $$ select public.release_pending_fx_receipt(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000001',
    (select receipt_id from phase2_fx_results where test_name = 'staff_manual_denied'),
    'fx-release-wrong-direction1',
    '99910000-0000-4000-8000-000000000002'
  ) $$,
  '22023', null,
  'release rejects a rate with the wrong currency direction'
);
select throws_ok(
  $$ select public.release_pending_fx_receipt(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000001',
    (select receipt_id from phase2_fx_results where test_name = 'staff_manual_denied'),
    'fx-release-expired-rate1',
    '99910000-0000-4000-8000-000000000003'
  ) $$,
  '22023', null,
  'release rejects an expired system rate'
);
select throws_ok(
  $$ select public.release_pending_fx_receipt(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000001',
    (select receipt_id from phase2_fx_results where test_name = 'staff_manual_denied'),
    'fx-release-bad-manual1',
    null,
    0.80000000000000001,
    'fictional source',
    now() - interval '1 minute',
    'Manual rate precision must be exact',
    null
  ) $$,
  '22023', null,
  'manual rates beyond sixteen decimal places are rejected'
);

select set_config('request.jwt.claim.sub', '99500000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$ select public.release_pending_fx_receipt(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000001',
    (select receipt_id from phase2_fx_results where test_name = 'staff_manual_denied'),
    'fx-release-sales-deny1',
    '99910000-0000-4000-8000-000000000001'
  ) $$,
  '42501', null,
  'sales staff cannot release pending FX'
);
select set_config('request.jwt.claim.sub', '99500000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$ select public.release_pending_fx_receipt(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000001',
    (select receipt_id from phase2_fx_results where test_name = 'staff_manual_denied'),
    'fx-release-suspended1',
    '99910000-0000-4000-8000-000000000001'
  ) $$,
  '42501', null,
  'suspended members cannot release pending FX'
);
select set_config('request.jwt.claim.sub', '99500000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$ select public.release_pending_fx_receipt(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000002',
    (select receipt_id from phase2_fx_results where test_name = 'staff_manual_denied'),
    'fx-release-branch-deny1',
    '99910000-0000-4000-8000-000000000001'
  ) $$,
  '42501', null,
  'a Manager without branch assignment cannot release stock in another branch'
);
select throws_ok(
  $$ select public.release_pending_fx_receipt(
    '99600000-0000-4000-8000-000000000002',
    '99700000-0000-4000-8000-000000000003',
    (select receipt_id from phase2_fx_results where test_name = 'staff_manual_denied'),
    'fx-release-cross-shop1',
    '99910000-0000-4000-8000-000000000001'
  ) $$,
  '42501', null,
  'a Manager cannot release a receipt through another shop tenant'
);

select set_config('request.jwt.claim.sub', '99500000-0000-4000-8000-000000000001', true);
insert into phase2_fx_results
select 'manual_owner',
  public.receive_serialized_inventory(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000001',
    'fx-pending-manual-owner1',
    'supplier_invoice',
    'Fictional supplier',
    'TEST-FX-MANUAL-OWNER',
    'CAD',
    0,
    '[{"line_number":1,"variant_id":"99900000-0000-4000-8000-000000000001","original_line_amount":0,"identifiers":[{"identifier_type":"serial","raw_value":"FX-MANUAL-OWNER-TEST","is_primary":true}]}]'::jsonb,
    null, null, null, null, null, true
  );
insert into phase2_fx_release_results
select 'manual_owner',
  public.release_pending_fx_receipt(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000001',
    (select receipt_id from phase2_fx_results where test_name = 'manual_owner'),
    'fx-release-owner-manual1',
    null,
    1,
    'fictional owner quote',
    now(),
    'Owner approved a synthetic zero-cost conversion',
    null
  );
select is(
  (select count(*)::integer
   from public.inventory_fx_resolutions as resolution
   join public.inventory_receipt_lines as line
     on line.shop_id = resolution.shop_id
    and line.branch_id = resolution.branch_id
    and line.id = resolution.receipt_line_id
   join phase2_fx_results as result on result.receipt_id = line.receipt_id
   where result.test_name = 'manual_owner'
     and resolution.accepted_fx_rate = 1
     and resolution.converted_line_amount_shop = 0
     and resolution.override_approved_by = '99500000-0000-4000-8000-000000000001'),
  1,
  'Owner may release an explicitly known zero-cost pending invoice'
);
select is(
  (select count(*)::integer
   from public.inventory_balances
   where shop_id = '99600000-0000-4000-8000-000000000001'
     and branch_id = '99700000-0000-4000-8000-000000000001'
     and variant_id = '99900000-0000-4000-8000-000000000001'
     and valuation_status = 'known_cost'
     and carrying_value_shop >= 0
     and average_unit_cost_shop >= 0),
  1,
  'Pending-FX release preserves known zero as a known-cost value'
);

select set_config('request.jwt.claim.sub', '99500000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$ select public.release_pending_fx_receipt(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000001',
    (select receipt_id from phase2_fx_results where test_name = 'rounding_receipt'),
    'fx-release-truncated-owner'
  ) $$,
  '22023', null,
  'an already released receipt cannot be resolved a second time'
);

insert into phase2_fx_results
select 'unknown_cost',
  public.receive_serialized_inventory(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000001',
    'fx-unknown-cost-01',
    'manual_unknown_cost',
    null, null, null, null,
    '[{"line_number":1,"variant_id":"99900000-0000-4000-8000-000000000001","identifiers":[{"identifier_type":"serial","raw_value":"FX-UNKNOWN-COST-TEST","is_primary":true}]}]'::jsonb
  );
select throws_ok(
  $$ select public.release_pending_fx_receipt(
    '99600000-0000-4000-8000-000000000001',
    '99700000-0000-4000-8000-000000000001',
    (select receipt_id from phase2_fx_results where test_name = 'unknown_cost'),
    'fx-release-unknown-01',
    '99910000-0000-4000-8000-000000000001'
  ) $$,
  '22023', null,
  'unknown-cost inventory cannot be converted or released as a guessed zero'
);

reset role;
select throws_ok(
  $$ update public.inventory_fx_resolutions
     set override_reason = 'unauthorized audit mutation'
     where receipt_line_id = (
       select line.id
       from public.inventory_receipt_lines as line
       join phase2_fx_results as result on result.receipt_id = line.receipt_id
       where result.test_name = 'rounding_receipt'
       limit 1
     ) $$,
  '42501', null,
  'FX resolution evidence is append-only'
);
select throws_ok(
  $$ update public.inventory_movements
     set reason = 'unauthorized audit mutation'
     where fx_resolution_id is not null $$,
  '42501', null,
  'FX release movements are append-only'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '99500000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$ insert into public.inventory_fx_resolutions default values $$,
  '42501', null,
  'authenticated clients cannot insert FX resolution rows directly'
);
set local role service_role;
select throws_ok(
  $$ truncate table public.inventory_fx_resolutions $$,
  '42501', null,
  'service_role cannot truncate FX audit history'
);
reset role;

select * from finish();
rollback;
