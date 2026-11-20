begin;

-- Deferred until migration 202611200001 is approved and applied to a test
-- database. This file is intentionally not run against the existing database.
create extension if not exists pgtap with schema extensions;
select no_plan();

-- All people, shops, device identifiers, and invoice values below are
-- fictional test fixtures. IMEI-shaped values are synthetic all-zero sequences.
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('90000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'inv-owner-a@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('90000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'inv-manager-a@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('90000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'inv-staff-a@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('90000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'sales-staff-a@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('90000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'suspended-staff-a@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('90000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'inv-owner-b@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('90000000-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'unassigned-manager-a@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.shops (id, name, created_by) values
  ('91000000-0000-4000-8000-000000000001', 'Fictional Inventory Shop A', '90000000-0000-4000-8000-000000000001'),
  ('91000000-0000-4000-8000-000000000002', 'Fictional Inventory Shop B', '90000000-0000-4000-8000-000000000006');

insert into public.shop_memberships (shop_id, user_id, role, status, created_by) values
  ('91000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000001', 'owner', 'active', '90000000-0000-4000-8000-000000000001'),
  ('91000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000002', 'manager', 'active', '90000000-0000-4000-8000-000000000001'),
  ('91000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000003', 'inventory_staff', 'active', '90000000-0000-4000-8000-000000000001'),
  ('91000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000004', 'sales_staff', 'active', '90000000-0000-4000-8000-000000000001'),
  ('91000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000005', 'inventory_staff', 'suspended', '90000000-0000-4000-8000-000000000001'),
  ('91000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000007', 'manager', 'active', '90000000-0000-4000-8000-000000000001'),
  ('91000000-0000-4000-8000-000000000002', '90000000-0000-4000-8000-000000000006', 'owner', 'active', '90000000-0000-4000-8000-000000000006');

insert into public.branches (id, shop_id, name, is_primary, is_active, created_by) values
  ('92000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001', 'A Main', true, true, '90000000-0000-4000-8000-000000000001'),
  ('92000000-0000-4000-8000-000000000002', '91000000-0000-4000-8000-000000000001', 'A Restricted', false, true, '90000000-0000-4000-8000-000000000001'),
  ('92000000-0000-4000-8000-000000000003', '91000000-0000-4000-8000-000000000002', 'B Main', true, true, '90000000-0000-4000-8000-000000000006');

insert into public.branch_memberships (shop_id, branch_id, user_id, created_by) values
  ('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000002', '90000000-0000-4000-8000-000000000001'),
  ('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000003', '90000000-0000-4000-8000-000000000001'),
  ('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000004', '90000000-0000-4000-8000-000000000001'),
  ('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000005', '90000000-0000-4000-8000-000000000001');

insert into public.products (
  id, shop_id, product_type, tracking_mode, name, created_by, updated_by
) values
  ('93000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001', 'accessory', 'quantity', 'Test item one', '90000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000001'),
  ('93000000-0000-4000-8000-000000000002', '91000000-0000-4000-8000-000000000001', 'accessory', 'quantity', 'Test item two', '90000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000001'),
  ('93000000-0000-4000-8000-000000000003', '91000000-0000-4000-8000-000000000001', 'accessory', 'quantity', 'Test item three', '90000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000001'),
  ('93000000-0000-4000-8000-000000000004', '91000000-0000-4000-8000-000000000001', 'smartphone', 'serialized', 'Fictional device', '90000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000001'),
  ('93000000-0000-4000-8000-000000000005', '91000000-0000-4000-8000-000000000002', 'accessory', 'quantity', 'Shop B test item', '90000000-0000-4000-8000-000000000006', '90000000-0000-4000-8000-000000000006');

insert into public.product_variants (
  id, shop_id, product_id, created_by, updated_by
) values
  ('94000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001', '93000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000001'),
  ('94000000-0000-4000-8000-000000000002', '91000000-0000-4000-8000-000000000001', '93000000-0000-4000-8000-000000000002', '90000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000001'),
  ('94000000-0000-4000-8000-000000000003', '91000000-0000-4000-8000-000000000001', '93000000-0000-4000-8000-000000000003', '90000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000001'),
  ('94000000-0000-4000-8000-000000000004', '91000000-0000-4000-8000-000000000001', '93000000-0000-4000-8000-000000000004', '90000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000001'),
  ('94000000-0000-4000-8000-000000000005', '91000000-0000-4000-8000-000000000002', '93000000-0000-4000-8000-000000000005', '90000000-0000-4000-8000-000000000006', '90000000-0000-4000-8000-000000000006');

select is(
  (select count(*)::integer from public.shop_settings where shop_id = '91000000-0000-4000-8000-000000000001'),
  0,
  'existing shops do not receive an implicit operating currency'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$ select public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'unconfigured-shop1', 'manual_unknown_cost', null, null, null, null, '[{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000001","quantity":1}]'::jsonb, null, null, null, null, null, false) $$,
  '22023', null,
  'receiving is blocked until the Owner explicitly selects a shop currency'
);
select lives_ok(
  $$ select public.configure_shop_operating_currency('91000000-0000-4000-8000-000000000001', 'USD') $$,
  'Owner can explicitly configure the shop operating currency'
);
select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000006', true);
select lives_ok(
  $$ select public.configure_shop_operating_currency('91000000-0000-4000-8000-000000000002', 'USD') $$,
  'second shop Owner can configure an independent currency'
);
reset role;

insert into public.exchange_rate_snapshots (
  id, from_currency_code, to_currency_code, rate_to_currency,
  rate_source, observed_at, fetched_at, valid_until
) values
  ('95000000-0000-4000-8000-000000000001', 'CAD', 'USD', 0.5,
   'fictional test source', now() - interval '1 minute', now(), now() + interval '1 day'),
  ('95000000-0000-4000-8000-000000000002', 'CAD', 'EUR', 0.5,
   'fictional wrong-direction source', now() - interval '1 minute', now(), now() + interval '1 day'),
  ('95000000-0000-4000-8000-000000000003', 'CAD', 'USD', 0.5,
   'fictional expired source', now() - interval '2 days', now() - interval '2 days', now() - interval '1 day');

insert into public.inventory_balances (
  shop_id, branch_id, variant_id, valuation_status,
  valuation_currency_code, on_hand_qty, available_qty,
  carrying_value_shop, average_unit_cost_shop, updated_by
) values
  ('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000002', '94000000-0000-4000-8000-000000000002', 'known_cost', 'USD', 1, 1, 2.00, 2.00, '90000000-0000-4000-8000-000000000001'),
  ('91000000-0000-4000-8000-000000000002', '92000000-0000-4000-8000-000000000003', '94000000-0000-4000-8000-000000000005', 'known_cost', 'USD', 1, 1, 3.00, 3.00, '90000000-0000-4000-8000-000000000006');

insert into public.serialized_inventory (
  id, shop_id, branch_id, variant_id, availability_status,
  valuation_status, valuation_currency_code, unit_cost_shop,
  created_by, updated_by
) values
  ('96000000-0000-4000-8000-000000000001', '91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', '94000000-0000-4000-8000-000000000004', 'available', 'known_cost', 'USD', 0, '90000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000001'),
  ('96000000-0000-4000-8000-000000000002', '91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', '94000000-0000-4000-8000-000000000004', 'available', 'known_cost', 'USD', 0, '90000000-0000-4000-8000-000000000001', '90000000-0000-4000-8000-000000000001');

insert into public.serialized_identifiers (
  shop_id, branch_id, serialized_inventory_id,
  identifier_type, raw_value, created_by
) values
  ('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', '96000000-0000-4000-8000-000000000001', 'imei1', '000000000000000', '90000000-0000-4000-8000-000000000001'),
  ('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', '96000000-0000-4000-8000-000000000001', 'imei2', '000000000000001', '90000000-0000-4000-8000-000000000001'),
  ('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', '96000000-0000-4000-8000-000000000001', 'serial', 'TEST-DEVICE-SERIAL-1', '90000000-0000-4000-8000-000000000001');

select is(
  (select count(*)::integer from public.serialized_identifiers where serialized_inventory_id = '96000000-0000-4000-8000-000000000001' and identifier_type in ('imei1', 'imei2')),
  2,
  'one device can retain both distinct synthetic IMEI identifiers'
);
select throws_ok(
  $$ insert into public.serialized_identifiers (shop_id, branch_id, serialized_inventory_id, identifier_type, raw_value, created_by) values ('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', '96000000-0000-4000-8000-000000000002', 'imei1', '000000000000000', '90000000-0000-4000-8000-000000000001') $$,
  '23505', null,
  'a duplicate synthetic IMEI is rejected shop-wide'
);
select throws_ok(
  $$ delete from public.serialized_inventory where id = '96000000-0000-4000-8000-000000000001' $$,
  '23503', null,
  'serialized inventory cannot be deleted while durable identifiers refer to it'
);
select lives_ok(
  $$ insert into public.product_identifiers (shop_id, variant_id, identifier_type, raw_value, created_by) values ('91000000-0000-4000-8000-000000000001', '94000000-0000-4000-8000-000000000001', 'barcode', '000000000000000', '90000000-0000-4000-8000-000000000001') $$,
  'a product barcode is not placed in the device IMEI uniqueness namespace'
);

select throws_ok(
  $$ insert into public.inventory_balances (shop_id, branch_id, variant_id, valuation_status, valuation_currency_code, on_hand_qty, available_qty, carrying_value_shop, average_unit_cost_shop, updated_by) values ('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000003', '94000000-0000-4000-8000-000000000001', 'known_cost', 'USD', 1, 1, 1, 1, '90000000-0000-4000-8000-000000000001') $$,
  '23503', null,
  'composite shop and branch constraints reject cross-shop inventory rows'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$ select public.configure_shop_operating_currency('91000000-0000-4000-8000-000000000001', 'EUR') $$,
  '42501', null,
  'non-Owner staff cannot configure the shop operating currency'
);
select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$ select public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'sales-denied-0001', 'manual_unknown_cost', null, null, null, null, '[{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000001","quantity":1}]'::jsonb, null, null, null, null, null, false) $$,
  '42501', null,
  'sales staff cannot receive inventory'
);
select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$ select public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'suspended-denied-01', 'manual_unknown_cost', null, null, null, null, '[{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000001","quantity":1}]'::jsonb, null, null, null, null, null, false) $$,
  '42501', null,
  'suspended inventory staff cannot receive inventory'
);
select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000007', true);
select throws_ok(
  $$ select public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'unassigned-denied1', 'manual_unknown_cost', null, null, null, null, '[{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000001","quantity":1}]'::jsonb, null, null, null, null, null, false) $$,
  '42501', null,
  'a manager without branch assignment cannot receive there'
);
select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$ select public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000003', 'cross-shop-denied1', 'manual_unknown_cost', null, null, null, null, '[{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000001","quantity":1}]'::jsonb, null, null, null, null, null, false) $$,
  '42501', null,
  'an Owner cannot receive into another shop branch'
);
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$ select public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'anonymous-denied01', 'manual_unknown_cost', null, null, null, null, '[{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000001","quantity":1}]'::jsonb, null, null, null, null, null, false) $$,
  '42501', null,
  'a database session without an authenticated identity cannot receive stock'
);
select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000001', true);

select ok(
  public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'owner-zero-cost-01', 'supplier_invoice', 'Fictional supplier', 'TEST-ZERO-1', 'USD', 0, '[{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000001","quantity":1,"original_line_amount":0}]'::jsonb, null, null, null, null, null, false) is not null,
  'Owner can receive a known zero-cost invoice'
);
select is(
  (select count(*)::integer from public.inventory_balances where shop_id = '91000000-0000-4000-8000-000000000001' and branch_id = '92000000-0000-4000-8000-000000000001' and variant_id = '94000000-0000-4000-8000-000000000001' and valuation_status = 'known_cost' and on_hand_qty = 1 and carrying_value_shop = 0 and average_unit_cost_shop = 0),
  1,
  'known zero cost remains a valued known-cost balance'
);
select throws_ok(
  $$ select public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'negative-cost-0001', 'supplier_invoice', 'Fictional supplier', 'TEST-NEGATIVE', 'USD', -1.00, '[{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000001","quantity":1,"original_line_amount":-1.00}]'::jsonb, null, null, null, null, null, false) $$,
  '22023', null,
  'negative invoice and line costs are rejected'
);
select throws_ok(
  $$ select public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'negative-quantity1', 'supplier_invoice', 'Fictional supplier', 'TEST-NEGATIVE-QTY', 'USD', 0, '[{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000001","quantity":-1,"original_line_amount":0}]'::jsonb, null, null, null, null, null, false) $$,
  '22023', null,
  'negative inventory quantities are rejected'
);
select throws_ok(
  $$ select public.configure_shop_operating_currency('91000000-0000-4000-8000-000000000001', 'EUR') $$,
  '42501', null,
  'currency cannot change after the first inventory receipt'
);
select ok(
  public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'wac-precision-0001', 'supplier_invoice', 'Fictional supplier', 'TEST-WAC-PRECISION', 'USD', 0.02, '[{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000002","quantity":3,"original_line_amount":0.02}]'::jsonb, null, null, null, null, null, false) is not null,
  'same-currency fractional unit cost receipt is accepted'
);
select is(
  (select average_unit_cost_shop from public.inventory_balances where shop_id = '91000000-0000-4000-8000-000000000001' and branch_id = '92000000-0000-4000-8000-000000000001' and variant_id = '94000000-0000-4000-8000-000000000002' and valuation_status = 'known_cost'),
  0.0066666667::numeric,
  'weighted-average unit cost retains ten decimal places'
);

select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000002', true);
select ok(
  public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'manager-receive-001', 'manual_unknown_cost', null, null, null, null, '[{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000002","quantity":1}]'::jsonb, null, null, null, null, null, false) is not null,
  'an authorized Manager can receive at an assigned branch'
);
select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000003', true);
select ok(
  public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'staff-receive-001', 'manual_unknown_cost', null, null, null, null, '[{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000003","quantity":2}]'::jsonb, null, null, null, null, null, false) is not null,
  'authorized inventory staff can receive at an assigned branch'
);
select is(
  (select count(*)::integer from public.inventory_balances where shop_id = '91000000-0000-4000-8000-000000000001' and variant_id = '94000000-0000-4000-8000-000000000003' and valuation_status = 'unknown_cost' and on_hand_qty = 2 and available_qty = 2 and carrying_value_shop is null and average_unit_cost_shop is null),
  1,
  'unknown-cost stock remains distinct from known-zero stock'
);

select throws_ok(
  $$ select public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'fx-no-rate-0001', 'supplier_invoice', 'Fictional supplier', 'TEST-NO-RATE', 'CAD', 1.00, '[{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000001","quantity":1,"original_line_amount":1.00}]'::jsonb, null, null, null, null, null, false) $$,
  '22023', null,
  'foreign receipts reject missing rates unless Pending FX is explicit'
);
select ok(
  public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'pending-fx-000001', 'supplier_invoice', 'Fictional supplier', 'TEST-PENDING-1', 'CAD', 2.00, '[{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000001","quantity":2,"original_line_amount":2.00}]'::jsonb, null, null, null, null, null, true) is not null,
  'authorized inventory staff can physically receive stock as Pending FX'
);
select is(
  (select original_line_amount from public.inventory_receipt_lines line join public.inventory_receipts receipt on receipt.shop_id = line.shop_id and receipt.branch_id = line.branch_id and receipt.id = line.receipt_id where receipt.supplier_invoice_reference = 'TEST-PENDING-1'),
  2.00::numeric,
  'Pending FX receipt preserves the original invoice line amount'
);
select is(
  (select count(*)::integer from public.inventory_balances where shop_id = '91000000-0000-4000-8000-000000000001' and variant_id = '94000000-0000-4000-8000-000000000001' and valuation_status = 'pending_fx' and on_hand_qty = 2 and available_qty = 0 and carrying_value_shop is null),
  1,
  'Pending FX stock is on hand but unavailable and unvalued'
);

select throws_ok(
  $$ select public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'fx-direction-bad1', 'supplier_invoice', 'Fictional supplier', 'TEST-WRONG-DIR', 'CAD', 1.00, '[{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000001","quantity":1,"original_line_amount":1.00}]'::jsonb, '95000000-0000-4000-8000-000000000002', null, null, null, null, false) $$,
  '22023', null,
  'receipt rejects a rate snapshot with the wrong currency direction'
);
select throws_ok(
  $$ select public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'fx-expired-rate1', 'supplier_invoice', 'Fictional supplier', 'TEST-EXPIRED', 'CAD', 1.00, '[{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000001","quantity":1,"original_line_amount":1.00}]'::jsonb, '95000000-0000-4000-8000-000000000003', null, null, null, null, false) $$,
  '22023', null,
  'receipt rejects an expired rate snapshot'
);

select ok(
  public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'fx-reconcile-0001', 'supplier_invoice', 'Fictional supplier', 'TEST-ROUNDING-1', 'CAD', 0.03, '[{"line_number":3,"variant_id":"94000000-0000-4000-8000-000000000001","quantity":1,"original_line_amount":0.01},{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000001","quantity":1,"original_line_amount":0.01},{"line_number":2,"variant_id":"94000000-0000-4000-8000-000000000001","quantity":1,"original_line_amount":0.01}]'::jsonb, '95000000-0000-4000-8000-000000000001', null, null, null, null, false) is not null,
  'valid system rate converts and receives a foreign invoice'
);
select is(
  (select receipt.converted_invoice_amount_shop from public.inventory_receipts receipt where receipt.supplier_invoice_reference = 'TEST-ROUNDING-1'),
  0.02::numeric,
  'converted invoice total rounds in the shop currency'
);
select is(
  (select receipt.original_currency_code::text from public.inventory_receipts receipt where receipt.supplier_invoice_reference = 'TEST-ROUNDING-1'),
  'CAD',
  'receipt retains the supplier invoice currency'
);
select is(
  (select receipt.original_invoice_amount from public.inventory_receipts receipt where receipt.supplier_invoice_reference = 'TEST-ROUNDING-1'),
  0.03::numeric,
  'receipt retains the exact original invoice total'
);
select is(
  (select receipt.accepted_fx_rate from public.inventory_receipts receipt where receipt.supplier_invoice_reference = 'TEST-ROUNDING-1'),
  0.5::numeric,
  'receipt records the accepted shop-currency-per-original-currency rate'
);
select is(
  (select receipt.rate_source from public.inventory_receipts receipt where receipt.supplier_invoice_reference = 'TEST-ROUNDING-1'),
  'fictional test source',
  'receipt preserves the accepted system rate source'
);
select is(
  (select receipt.accepted_by from public.inventory_receipts receipt where receipt.supplier_invoice_reference = 'TEST-ROUNDING-1'),
  '90000000-0000-4000-8000-000000000003'::uuid,
  'receipt records the user who accepted the system rate'
);
select ok(
  (select receipt.rate_observed_at is not null and receipt.rate_accepted_at is not null and receipt.rate_accepted_at >= receipt.rate_observed_at from public.inventory_receipts receipt where receipt.supplier_invoice_reference = 'TEST-ROUNDING-1'),
  'receipt records rate observation and acceptance timestamps'
);
select is(
  (select line.converted_line_amount_shop from public.inventory_receipt_lines line join public.inventory_receipts receipt on receipt.shop_id = line.shop_id and receipt.branch_id = line.branch_id and receipt.id = line.receipt_id where receipt.supplier_invoice_reference = 'TEST-ROUNDING-1' and line.line_number = 1),
  0.01::numeric,
  'largest-remainder allocation assigns the first tied cent by line number'
);
select is(
  (select line.converted_line_amount_shop from public.inventory_receipt_lines line join public.inventory_receipts receipt on receipt.shop_id = line.shop_id and receipt.branch_id = line.branch_id and receipt.id = line.receipt_id where receipt.supplier_invoice_reference = 'TEST-ROUNDING-1' and line.line_number = 2),
  0.01::numeric,
  'largest-remainder allocation assigns the second tied cent by line number'
);
select is(
  (select line.converted_line_amount_shop from public.inventory_receipt_lines line join public.inventory_receipts receipt on receipt.shop_id = line.shop_id and receipt.branch_id = line.branch_id and receipt.id = line.receipt_id where receipt.supplier_invoice_reference = 'TEST-ROUNDING-1' and line.line_number = 3),
  0::numeric,
  'largest-remainder allocation is deterministic after total reconciliation'
);
select is(
  (select sum(line.converted_line_amount_shop) from public.inventory_receipt_lines line join public.inventory_receipts receipt on receipt.shop_id = line.shop_id and receipt.branch_id = line.branch_id and receipt.id = line.receipt_id where receipt.supplier_invoice_reference = 'TEST-ROUNDING-1'),
  (select converted_invoice_amount_shop from public.inventory_receipts where supplier_invoice_reference = 'TEST-ROUNDING-1'),
  'allocated receipt lines exactly reconcile to the converted invoice total'
);
select is(
  (select average_unit_cost_shop from public.inventory_balances where shop_id = '91000000-0000-4000-8000-000000000001' and branch_id = '92000000-0000-4000-8000-000000000001' and variant_id = '94000000-0000-4000-8000-000000000001' and valuation_status = 'known_cost'),
  0.005::numeric,
  'weighted-average cost uses authoritative carrying value and ten-place precision'
);
select is(
  public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'fx-reconcile-0001', 'supplier_invoice', 'Fictional supplier', 'TEST-ROUNDING-1', 'CAD', 0.03, '[{"line_number":3,"variant_id":"94000000-0000-4000-8000-000000000001","quantity":1,"original_line_amount":0.01},{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000001","quantity":1,"original_line_amount":0.01},{"line_number":2,"variant_id":"94000000-0000-4000-8000-000000000001","quantity":1,"original_line_amount":0.01}]'::jsonb, '95000000-0000-4000-8000-000000000001', null, null, null, null, false),
  (select receipt.id from public.inventory_receipts receipt where receipt.supplier_invoice_reference = 'TEST-ROUNDING-1'),
  'same idempotency key and payload return the original receipt'
);
select throws_ok(
  $$ select public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'fx-reconcile-0001', 'supplier_invoice', 'Fictional supplier', 'TEST-ROUNDING-CHANGED', 'CAD', 0.03, '[{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000001","quantity":1,"original_line_amount":0.03}]'::jsonb, '95000000-0000-4000-8000-000000000001', null, null, null, null, false) $$,
  '22023', null,
  'same idempotency key with different receipt contents is rejected'
);

select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$ select public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'staff-manual-fx-01', 'supplier_invoice', 'Fictional supplier', 'TEST-STAFF-OVERRIDE', 'CAD', 1.00, '[{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000003","quantity":1,"original_line_amount":1.00}]'::jsonb, null, 1.5, 'fictional owner quote', now() - interval '1 minute', 'Not authorized for a staff override', false) $$,
  '42501', null,
  'inventory staff cannot approve a manual rate override'
);
select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$ select public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'staff-rate-precise1', 'supplier_invoice', 'Fictional supplier', 'TEST-RATE-PRECISION', 'CAD', 1.00, '[{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000003","quantity":1,"original_line_amount":1.00}]'::jsonb, null, 1.12345678901234567, 'fictional source', now() - interval '1 minute', 'Rate precision must not be rounded silently', false) $$,
  '22023', null,
  'manual FX precision beyond sixteen places is rejected rather than rounded'
);
select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000001', true);
select ok(
  public.receive_quantity_inventory('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', 'owner-manual-fx-01', 'supplier_invoice', 'Fictional supplier', 'TEST-OWNER-OVERRIDE', 'CAD', 1.00, '[{"line_number":1,"variant_id":"94000000-0000-4000-8000-000000000003","quantity":1,"original_line_amount":1.00}]'::jsonb, null, 1.5, 'fictional owner quote', now() - interval '1 minute', 'Owner approved the explicitly sourced test rate', false) is not null,
  'active Owner can approve a sourced manual FX override with a reason'
);
select is(
  (select receipt.override_approved_by from public.inventory_receipts receipt where receipt.supplier_invoice_reference = 'TEST-OWNER-OVERRIDE'),
  '90000000-0000-4000-8000-000000000001'::uuid,
  'manual override records the approving Owner'
);
select is(
  (select receipt.rate_source from public.inventory_receipts receipt where receipt.supplier_invoice_reference = 'TEST-OWNER-OVERRIDE'),
  'manual_override: fictional owner quote',
  'manual override preserves its rate source'
);
select is(
  (select receipt.override_reason from public.inventory_receipts receipt where receipt.supplier_invoice_reference = 'TEST-OWNER-OVERRIDE'),
  'Owner approved the explicitly sourced test rate',
  'manual override preserves its required approval reason'
);
select is(
  (select receipt.converted_invoice_amount_shop from public.inventory_receipts receipt where receipt.supplier_invoice_reference = 'TEST-OWNER-OVERRIDE'),
  1.50::numeric,
  'manual override converted amount is recorded in shop currency'
);

select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000003', true);
select is(
  (select count(*)::integer from public.products where shop_id = '91000000-0000-4000-8000-000000000002'),
  0,
  'inventory staff cannot read another shop catalog'
);
select is(
  (select count(*)::integer from public.inventory_balances where shop_id = '91000000-0000-4000-8000-000000000001' and branch_id = '92000000-0000-4000-8000-000000000002'),
  0,
  'inventory staff cannot read an unassigned branch balance'
);
select is(
  (select count(*)::integer from public.inventory_balances where shop_id = '91000000-0000-4000-8000-000000000002'),
  0,
  'inventory staff cannot read another shop balances'
);
select is(
  (select count(*)::integer from public.exchange_rate_snapshots where id = '95000000-0000-4000-8000-000000000001'),
  1,
  'authenticated users can read non-tenant exchange-rate evidence'
);
select is(
  (select count(*)::integer from public.shop_settings where shop_id = '91000000-0000-4000-8000-000000000001'),
  1,
  'active inventory staff can read their shop settings'
);
select is(
  (select count(*)::integer from public.shop_settings where shop_id = '91000000-0000-4000-8000-000000000002'),
  0,
  'shop settings remain tenant-isolated'
);
select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000005', true);
select is(
  (select count(*)::integer from public.shop_settings where shop_id = '91000000-0000-4000-8000-000000000001'),
  0,
  'suspended members cannot read shop settings'
);
select set_config('request.jwt.claim.sub', '90000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$ insert into public.inventory_balances (shop_id, branch_id, variant_id, valuation_status, valuation_currency_code, on_hand_qty, available_qty, carrying_value_shop, average_unit_cost_shop, updated_by) values ('91000000-0000-4000-8000-000000000001', '92000000-0000-4000-8000-000000000001', '94000000-0000-4000-8000-000000000001', 'known_cost', 'USD', 1, 1, 1, 1, '90000000-0000-4000-8000-000000000003') $$,
  '42501', null,
  'authenticated clients cannot write stock balances directly'
);
select throws_ok(
  $$ update public.inventory_movements set reason = 'unauthorized change' where shop_id = '91000000-0000-4000-8000-000000000001' $$,
  '42501', null,
  'authenticated clients cannot update movement history'
);
select throws_ok(
  $$ truncate table public.inventory_movements $$,
  '42501', null,
  'authenticated clients cannot truncate movement history'
);

reset role;
select throws_ok(
  $$ update public.inventory_movements set reason = 'audit mutation test' where operation_id = (select operation.id from public.inventory_operations operation where operation.idempotency_key = 'owner-zero-cost-01') $$,
  '42501', null,
  'movement history is immutable even for privileged SQL callers'
);

create temporary table m2_privilege_test_relations (
  relation_oid oid primary key
) on commit drop;
insert into pg_temp.m2_privilege_test_relations (relation_oid)
select relation.oid
from pg_catalog.pg_class as relation
join pg_catalog.pg_namespace as namespace
  on namespace.oid = relation.relnamespace
where namespace.nspname = 'public'
  and relation.relkind = 'r'
  and relation.relname = any(array[
    'currency_codes', 'shop_settings', 'products', 'product_variants',
    'product_identifiers', 'serialized_inventory', 'serialized_identifiers',
    'exchange_rate_snapshots', 'inventory_operations', 'inventory_receipts',
    'inventory_receipt_lines', 'inventory_balances', 'branch_variant_prices',
    'inventory_fx_resolutions', 'inventory_movements'
  ]);

select ok(
  (select count(*) = 15 and bool_and(
    pg_catalog.has_table_privilege('service_role', relation_oid, 'SELECT')
  ) from pg_temp.m2_privilege_test_relations),
  'trusted service_role retains read-only access to M2 tables'
);
select ok(
  (select count(*) = 15 and bool_and(not
    pg_catalog.has_table_privilege('service_role', relation_oid, 'INSERT')
  ) from pg_temp.m2_privilege_test_relations),
  'service_role has no direct INSERT privilege on M2 tables'
);
select ok(
  (select count(*) = 15 and bool_and(not
    pg_catalog.has_table_privilege('service_role', relation_oid, 'UPDATE')
  ) from pg_temp.m2_privilege_test_relations),
  'service_role has no direct UPDATE privilege on M2 tables'
);
select ok(
  (select count(*) = 15 and bool_and(not
    pg_catalog.has_table_privilege('service_role', relation_oid, 'DELETE')
  ) from pg_temp.m2_privilege_test_relations),
  'service_role has no direct DELETE privilege on M2 tables'
);
select ok(
  (select count(*) = 15 and bool_and(not
    pg_catalog.has_table_privilege('service_role', relation_oid, 'TRUNCATE')
  ) from pg_temp.m2_privilege_test_relations),
  'service_role has no direct TRUNCATE privilege on M2 tables'
);

set local role service_role;
select throws_ok(
  $$ insert into public.inventory_balances default values $$,
  '42501', null,
  'service_role cannot directly insert stock balances'
);
select throws_ok(
  $$ update public.inventory_movements set reason = 'direct write test' $$,
  '42501', null,
  'service_role cannot directly update movement history'
);
select throws_ok(
  $$ delete from public.inventory_receipts $$,
  '42501', null,
  'service_role cannot directly delete receipt history'
);
select throws_ok(
  $$ truncate table public.inventory_movements $$,
  '42501', null,
  'service_role cannot truncate movement history'
);
reset role;

-- A separate two-session test against the isolated project submitted the same
-- receipt concurrently; both sessions returned one receipt ID and produced
-- one operation and movement. Broader multi-key concurrency stress testing
-- remains pending.

set constraints all immediate;
select * from finish();
rollback;
