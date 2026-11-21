begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

-- All identifiers, users, shops, branches, and inventory below are synthetic.
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('98000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'phase3c-owner-a@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('98000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'phase3c-manager-source@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('98000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'phase3c-manager-both@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('98000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'phase3c-inventory-staff@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('98000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'phase3c-sales-staff@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('98000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'phase3c-suspended@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('98000000-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'phase3c-owner-b@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.shops (id, name, created_by) values
  ('98100000-0000-4000-8000-000000000001', 'Fictional Transfer Shop A', '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000002', 'Fictional Transfer Shop B', '98000000-0000-4000-8000-000000000007');

insert into public.shop_memberships (shop_id, user_id, role, status, created_by) values
  ('98100000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000001', 'owner', 'active', '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000002', 'manager', 'active', '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000003', 'manager', 'active', '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000004', 'inventory_staff', 'active', '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000005', 'sales_staff', 'active', '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000006', 'inventory_staff', 'suspended', '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000002', '98000000-0000-4000-8000-000000000007', 'owner', 'active', '98000000-0000-4000-8000-000000000007');

insert into public.branches (id, shop_id, name, is_primary, is_active, created_by) values
  ('98200000-0000-4000-8000-000000000001', '98100000-0000-4000-8000-000000000001', 'A Main', true, true, '98000000-0000-4000-8000-000000000001'),
  ('98200000-0000-4000-8000-000000000002', '98100000-0000-4000-8000-000000000001', 'A Destination', false, true, '98000000-0000-4000-8000-000000000001'),
  ('98200000-0000-4000-8000-000000000003', '98100000-0000-4000-8000-000000000001', 'A Inactive', false, false, '98000000-0000-4000-8000-000000000001'),
  ('98200000-0000-4000-8000-000000000004', '98100000-0000-4000-8000-000000000002', 'B Main', true, true, '98000000-0000-4000-8000-000000000007');

insert into public.branch_memberships (shop_id, branch_id, user_id, created_by) values
  ('98100000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000002', '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000003', '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000002', '98000000-0000-4000-8000-000000000003', '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000004', '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000002', '98000000-0000-4000-8000-000000000004', '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000005', '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000002', '98000000-0000-4000-8000-000000000005', '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000006', '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000002', '98000000-0000-4000-8000-000000000006', '98000000-0000-4000-8000-000000000001');

insert into public.shop_settings (
  shop_id, operating_currency_code, configured_by, updated_by
) values
  ('98100000-0000-4000-8000-000000000001', 'USD', '98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000002', 'USD', '98000000-0000-4000-8000-000000000007', '98000000-0000-4000-8000-000000000007');

insert into public.products (
  id, shop_id, product_type, tracking_mode, name, created_by, updated_by
) values
  ('98300000-0000-4000-8000-000000000001', '98100000-0000-4000-8000-000000000001', 'accessory', 'quantity', 'Fictional quantity goods', '98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000001'),
  ('98300000-0000-4000-8000-000000000002', '98100000-0000-4000-8000-000000000001', 'smartphone', 'serialized', 'Fictional serialized devices', '98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000001'),
  ('98300000-0000-4000-8000-000000000003', '98100000-0000-4000-8000-000000000001', 'spare_part', 'quantity', 'Fictional transit-only goods', '98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000001'),
  ('98300000-0000-4000-8000-000000000004', '98100000-0000-4000-8000-000000000002', 'smartphone', 'serialized', 'Fictional other-shop goods', '98000000-0000-4000-8000-000000000007', '98000000-0000-4000-8000-000000000007');

insert into public.product_variants (
  id, shop_id, product_id, attributes, created_by, updated_by
) values
  ('98400000-0000-4000-8000-000000000001', '98100000-0000-4000-8000-000000000001', '98300000-0000-4000-8000-000000000001', '{"phase3c":"known-cost"}'::jsonb, '98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000001'),
  ('98400000-0000-4000-8000-000000000002', '98100000-0000-4000-8000-000000000001', '98300000-0000-4000-8000-000000000001', '{"phase3c":"unknown-cost"}'::jsonb, '98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000001'),
  ('98400000-0000-4000-8000-000000000003', '98100000-0000-4000-8000-000000000001', '98300000-0000-4000-8000-000000000001', '{"phase3c":"zero-cost"}'::jsonb, '98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000001'),
  ('98400000-0000-4000-8000-000000000004', '98100000-0000-4000-8000-000000000001', '98300000-0000-4000-8000-000000000001', '{"phase3c":"pending-fx"}'::jsonb, '98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000001'),
  ('98400000-0000-4000-8000-000000000005', '98100000-0000-4000-8000-000000000001', '98300000-0000-4000-8000-000000000002', '{"phase3c":"serialized"}'::jsonb, '98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000001'),
  ('98400000-0000-4000-8000-000000000006', '98100000-0000-4000-8000-000000000001', '98300000-0000-4000-8000-000000000003', '{"phase3c":"transit-only"}'::jsonb, '98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000001'),
  ('98400000-0000-4000-8000-000000000007', '98100000-0000-4000-8000-000000000002', '98300000-0000-4000-8000-000000000004', '{"phase3c":"other-shop"}'::jsonb, '98000000-0000-4000-8000-000000000007', '98000000-0000-4000-8000-000000000007'),
  ('98400000-0000-4000-8000-000000000008', '98100000-0000-4000-8000-000000000001', '98300000-0000-4000-8000-000000000001', '{"phase3c":"rounding-residual"}'::jsonb, '98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000001');

insert into public.inventory_balances (
  shop_id, branch_id, variant_id, valuation_status, valuation_currency_code,
  on_hand_qty, available_qty, carrying_value_shop, average_unit_cost_shop, updated_by
) values
  ('98100000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000001', '98400000-0000-4000-8000-000000000001', 'known_cost', 'USD', 10, 10, 100, 10, '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000001', '98400000-0000-4000-8000-000000000002', 'unknown_cost', 'USD', 6, 6, null, null, '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000001', '98400000-0000-4000-8000-000000000003', 'known_cost', 'USD', 2, 2, 0, 0, '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000001', '98400000-0000-4000-8000-000000000004', 'pending_fx', 'USD', 2, 0, null, null, '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000001', '98400000-0000-4000-8000-000000000005', 'known_cost', 'USD', 2, 2, 50, 25, '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000001', '98400000-0000-4000-8000-000000000006', 'known_cost', 'USD', 2, 2, 8, 4, '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000001', '98400000-0000-4000-8000-000000000008', 'known_cost', 'USD', 3, 3, 1, 0.3333333333, '98000000-0000-4000-8000-000000000001');

insert into public.serialized_inventory (
  id, shop_id, branch_id, variant_id, availability_status,
  valuation_status, valuation_currency_code, unit_cost_shop,
  created_by, updated_by
) values
  ('98500000-0000-4000-8000-000000000001', '98100000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000001', '98400000-0000-4000-8000-000000000005', 'available', 'known_cost', 'USD', 25, '98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000001'),
  ('98500000-0000-4000-8000-000000000002', '98100000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000001', '98400000-0000-4000-8000-000000000005', 'available', 'known_cost', 'USD', 25, '98000000-0000-4000-8000-000000000001', '98000000-0000-4000-8000-000000000001');

insert into public.serialized_identifiers (
  shop_id, branch_id, serialized_inventory_id, identifier_type,
  raw_value, is_primary, created_by
) values
  ('98100000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000001', '98500000-0000-4000-8000-000000000001', 'imei1', '000000000000001', true, '98000000-0000-4000-8000-000000000001'),
  ('98100000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000001', '98500000-0000-4000-8000-000000000002', 'imei1', '000000000000002', true, '98000000-0000-4000-8000-000000000001');

create temporary table phase3c_transfer_results (
  name text primary key,
  transfer_id uuid not null
) on commit drop;
grant select, insert, update on phase3c_transfer_results to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$ select public.request_inventory_transfer(
       '98100000-0000-4000-8000-000000000001',
       '98200000-0000-4000-8000-000000000001',
       '98200000-0000-4000-8000-000000000002',
       '[{"serialized_inventory_id":"98500000-0000-4000-8000-000000000001","extra":true}]'::jsonb,
       'Reject extra serialized line keys', 'phase3c-extra-serialized-key'
     ) $$,
  '22023', null,
  'serialized transfer lines reject unrecognized keys'
);
select throws_ok(
  $$ select public.request_inventory_transfer(
       '98100000-0000-4000-8000-000000000001',
       '98200000-0000-4000-8000-000000000001',
       '98200000-0000-4000-8000-000000000002',
       '[{"variant_id":"98400000-0000-4000-8000-000000000001","valuation_status":"known_cost","quantity":1,"extra":true}]'::jsonb,
       'Reject extra quantity line keys', 'phase3c-extra-quantity-key'
     ) $$,
  '22023', null,
  'quantity transfer lines reject unrecognized keys'
);
select lives_ok(
  $$ insert into phase3c_transfer_results values (
       'known-cost', public.request_inventory_transfer(
         '98100000-0000-4000-8000-000000000001',
         '98200000-0000-4000-8000-000000000001',
         '98200000-0000-4000-8000-000000000002',
         '[{"variant_id":"98400000-0000-4000-8000-000000000001","valuation_status":"known_cost","quantity":4}]'::jsonb,
         'Fictional transfer for reconciliation', 'phase3c-known-request-01'
       )
     ) $$,
  'an assigned Manager may request a same-shop quantity transfer from their branch'
);
select throws_ok(
  $$ select public.approve_inventory_transfer(
       '98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'known-cost'),
       1, 'phase3c-manager-source-approve'
     ) $$,
  '42501', null,
  'a Manager assigned only to the source cannot approve the transfer'
);
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$ select public.approve_inventory_transfer(
       '98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'known-cost'),
       1, 'phase3c-staff-approve-0001'
     ) $$,
  '42501', null,
  'Inventory Staff cannot approve transfers'
);
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000003', true);
select lives_ok(
  $$ select public.approve_inventory_transfer(
       '98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'known-cost'),
       1, 'phase3c-known-approve-01'
     ) $$,
  'a Manager assigned to both active endpoints may approve and reserve stock'
);
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$ insert into phase3c_transfer_results values (
       'over-reservation', public.request_inventory_transfer(
         '98100000-0000-4000-8000-000000000001',
         '98200000-0000-4000-8000-000000000001',
         '98200000-0000-4000-8000-000000000002',
         '[{"variant_id":"98400000-0000-4000-8000-000000000001","valuation_status":"known_cost","quantity":7}]'::jsonb,
         'Competing reservation must see reduced availability', 'phase3c-overreserve-request'
       )
     ) $$,
  'a second request may be recorded while the first reservation is pending'
);
select throws_ok(
  $$ select public.approve_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'over-reservation'),
       1, 'phase3c-overreserve-approve') $$,
  '23514', null,
  'a second approval cannot reserve stock already reserved by another transfer'
);
select lives_ok(
  $$ select public.cancel_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'over-reservation'),
       1, 'Close competing reservation request', 'phase3c-overreserve-cancel') $$,
  'the rejected competing request can be cancelled without changing stock'
);
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000002', true);
select throws_ok(
  $$ select public.receive_inventory_transfer(
       '98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'known-cost'),
       3, '[]'::jsonb, 'phase3c-manager-source-receive-denied'
     ) $$,
  '42501', null,
  'a Manager assigned only to the source cannot receive at the destination'
);
select is(
  (select available_qty from public.inventory_balances
   where variant_id = '98400000-0000-4000-8000-000000000001'
     and branch_id = '98200000-0000-4000-8000-000000000001'),
  6,
  'approval reduces source availability'
);
select is(
  (select on_hand_qty from public.inventory_balances
   where variant_id = '98400000-0000-4000-8000-000000000001'
     and branch_id = '98200000-0000-4000-8000-000000000001'),
  10,
  'approval preserves source on-hand quantity'
);
select is(
  (select reserved_transfer_qty from public.inventory_balances
   where variant_id = '98400000-0000-4000-8000-000000000001'
     and branch_id = '98200000-0000-4000-8000-000000000001'),
  4,
  'approval accounts for the reserved transfer quantity'
);
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000004', true);
select lives_ok(
  $$ select public.dispatch_inventory_transfer(
       '98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'known-cost'),
       2, 'phase3c-known-dispatch-01'
     ) $$,
  'assigned Inventory Staff may dispatch the full approved quantity from source'
);
select lives_ok(
  $$ select public.receive_inventory_transfer(
       '98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'known-cost'),
       3,
       jsonb_build_array(jsonb_build_object(
         'line_id', (select id from public.inventory_transfer_lines
                     where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'known-cost')),
         'quantity', 2
       )),
       'phase3c-known-receive-01'
     ) $$,
  'assigned destination Inventory Staff may partially receive dispatched quantity'
);
reset role;

select is(
  (select outstanding_qty from public.inventory_transfer_in_transit
   where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'known-cost')),
  2,
  'partial receipt leaves the exact quantity in the in-transit position'
);
select is(
  (select outstanding_value_shop from public.inventory_transfer_in_transit
   where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'known-cost')),
  20::numeric,
  'partial receipt leaves the exact unreceived carrying value in transit'
);
select is(
  (select carrying_value_shop from public.inventory_balances
   where variant_id = '98400000-0000-4000-8000-000000000001'
     and branch_id = '98200000-0000-4000-8000-000000000001'),
  60::numeric,
  'dispatch removes the proportional carrying value from the source'
);
select is(
  (select carrying_value_shop from public.inventory_balances
   where variant_id = '98400000-0000-4000-8000-000000000001'
     and branch_id = '98200000-0000-4000-8000-000000000002'),
  20::numeric,
  'partial receipt adds only the received carrying value to destination'
);
select is(
  (select sum(carrying_value_shop) from public.inventory_balances
   where shop_id = '98100000-0000-4000-8000-000000000001'
     and variant_id = '98400000-0000-4000-8000-000000000001')
   + (select sum(outstanding_value_shop) from public.inventory_transfer_in_transit
      where shop_id = '98100000-0000-4000-8000-000000000001'
        and variant_id = '98400000-0000-4000-8000-000000000001'),
  100::numeric,
  'source, transit, and destination known-cost value reconcile to the original shop value'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000004', true);
select lives_ok(
  $$ select public.receive_inventory_transfer(
       '98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'known-cost'),
       4,
       jsonb_build_array(jsonb_build_object(
         'line_id', (select id from public.inventory_transfer_lines
                     where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'known-cost')),
         'quantity', 2
       )),
       'phase3c-known-receive-02'
     ) $$,
  'the remaining quantity can be received exactly once'
);
select lives_ok(
  $$ select public.receive_inventory_transfer(
       '98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'known-cost'),
       3,
       jsonb_build_array(jsonb_build_object(
         'line_id', (select id from public.inventory_transfer_lines
                     where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'known-cost')),
         'quantity', 2
       )),
       'phase3c-known-receive-01'
     ) $$,
  'an authorized identical retry replays even after later transfer progress'
);
reset role;
select is(
  (select status from public.inventory_transfers
   where id = (select transfer_id from phase3c_transfer_results where name = 'known-cost')),
  'received',
  'fully received transfers reach the received state'
);
select is(
  (select count(*)::integer from public.inventory_transfer_in_transit
   where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'known-cost')),
  0,
  'completed transfer has no outstanding in-transit position'
);
select is(
  (select sum(carrying_value_shop) from public.inventory_balances
   where shop_id = '98100000-0000-4000-8000-000000000001'
     and variant_id = '98400000-0000-4000-8000-000000000001'),
  100::numeric,
  'final residual allocation preserves total carrying value after complete receipt'
);
select ok(
  (select sum(on_hand_delta) = 0
          and sum(available_delta) = 0
          and sum(reserved_transfer_delta) = 0
   from public.inventory_transfer_events
   where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'known-cost')),
  'immutable transfer events reconcile on-hand, available, and reserved quantity deltas'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$ insert into phase3c_transfer_results values (
       'unknown-cost', public.request_inventory_transfer(
         '98100000-0000-4000-8000-000000000001',
         '98200000-0000-4000-8000-000000000001',
         '98200000-0000-4000-8000-000000000002',
         '[{"variant_id":"98400000-0000-4000-8000-000000000002","valuation_status":"unknown_cost","quantity":2}]'::jsonb,
         'Unknown-cost transfer', 'phase3c-unknown-request-01'
       )
     ) $$,
  'Owner can request a transfer from the unknown-cost bucket'
);
select lives_ok(
  $$ select public.approve_inventory_transfer(
       '98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'unknown-cost'),
       1, 'phase3c-unknown-approve-01'
     ) $$,
  'unknown-cost stock can be reserved without assigning a value'
);
select lives_ok(
  $$ select public.dispatch_inventory_transfer(
       '98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'unknown-cost'),
       2, 'phase3c-unknown-dispatch-01'
     ) $$,
  'unknown-cost stock can be dispatched while remaining unvalued'
);
select lives_ok(
  $$ select public.receive_inventory_transfer(
       '98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'unknown-cost'),
       3,
       jsonb_build_array(jsonb_build_object(
         'line_id', (select id from public.inventory_transfer_lines
                     where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'unknown-cost')),
         'quantity', 1
       )),
       'phase3c-unknown-receive-01'
     ) $$,
  'unknown-cost stock supports partial receipt'
);
select throws_ok(
  $$ select public.receive_inventory_transfer(
       '98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'unknown-cost'),
       4,
       jsonb_build_array(jsonb_build_object(
         'line_id', (select id from public.inventory_transfer_lines
                     where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'unknown-cost')),
         'quantity', 2
       )),
       'phase3c-unknown-overreceive'
     ) $$,
  '23514', null,
  'over-receiving is rejected'
);
reset role;
select is(
  (select outstanding_value_shop from public.inventory_transfer_in_transit
   where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'unknown-cost')),
  null::numeric,
  'unknown-cost in-transit stock has no invented carrying value'
);
select is(
  (select carrying_value_shop from public.inventory_balances
   where variant_id = '98400000-0000-4000-8000-000000000002'
     and branch_id = '98200000-0000-4000-8000-000000000002'),
  null::numeric,
  'receiving unknown-cost stock preserves NULL carrying value'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$ select public.request_inventory_transfer(
       '98100000-0000-4000-8000-000000000001',
       '98200000-0000-4000-8000-000000000001',
       '98200000-0000-4000-8000-000000000002',
       '[{"variant_id":"98400000-0000-4000-8000-000000000004","valuation_status":"pending_fx","quantity":1}]'::jsonb,
       'Pending FX must remain blocked', 'phase3c-pending-fx-01'
     ) $$,
  '23514', null,
  'Pending-FX stock cannot be transferred'
);
select lives_ok(
  $$ insert into phase3c_transfer_results values (
       'known-zero', public.request_inventory_transfer(
         '98100000-0000-4000-8000-000000000001',
         '98200000-0000-4000-8000-000000000001',
         '98200000-0000-4000-8000-000000000002',
         '[{"variant_id":"98400000-0000-4000-8000-000000000003","valuation_status":"known_cost","quantity":1}]'::jsonb,
         'Transfer known-zero cost goods', 'phase3c-known-zero-request'
       )
     ) $$,
  'known-zero stock can be requested'
);
select lives_ok(
  $$ select public.approve_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'known-zero'),
       1, 'phase3c-known-zero-approve') $$,
  'known-zero stock can be approved'
);
select lives_ok(
  $$ select public.dispatch_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'known-zero'),
       2, 'phase3c-known-zero-dispatch') $$,
  'known-zero stock can be dispatched'
);
select lives_ok(
  $$ select public.receive_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'known-zero'),
       3, jsonb_build_array(jsonb_build_object(
         'line_id', (select id from public.inventory_transfer_lines
                    where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'known-zero')),
         'quantity', 1)), 'phase3c-known-zero-receive') $$,
  'known-zero stock can be received'
);
reset role;
select ok(
  (select valuation_status = 'known_cost'
          and carrying_value_shop = 0
          and average_unit_cost_shop = 0
   from public.inventory_balances
   where variant_id = '98400000-0000-4000-8000-000000000003'
     and branch_id = '98200000-0000-4000-8000-000000000002'),
  'known-zero receipt remains known_cost with explicit zero value'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$ insert into phase3c_transfer_results values (
       'rounding-residual', public.request_inventory_transfer(
         '98100000-0000-4000-8000-000000000001',
         '98200000-0000-4000-8000-000000000001',
         '98200000-0000-4000-8000-000000000002',
         '[{"variant_id":"98400000-0000-4000-8000-000000000008","valuation_status":"known_cost","quantity":3}]'::jsonb,
         'Deterministic rounding fixture', 'phase3c-rounding-request-01'
       )
     ) $$,
  'rounding fixture transfer can be requested'
);
select lives_ok(
  $$ select public.approve_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'rounding-residual'),
       1, 'phase3c-rounding-approve-01') $$,
  'rounding fixture can be approved'
);
select lives_ok(
  $$ select public.dispatch_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'rounding-residual'),
       2, 'phase3c-rounding-dispatch-01') $$,
  'rounding fixture can be dispatched'
);
select lives_ok(
  $$ select public.receive_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'rounding-residual'),
       3, jsonb_build_array(jsonb_build_object(
         'line_id', (select id from public.inventory_transfer_lines
                    where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'rounding-residual')),
         'quantity', 1)), 'phase3c-rounding-receive-01') $$,
  'rounding fixture supports partial receipt'
);
reset role;
select is(
  (select outstanding_value_shop from public.inventory_transfer_in_transit
   where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'rounding-residual')),
  0.66666667::numeric,
  'partial receipt carries the deterministic eight-decimal rounding residual in transit'
);
select is(
  (select carrying_value_shop from public.inventory_balances
   where variant_id = '98400000-0000-4000-8000-000000000008'
     and branch_id = '98200000-0000-4000-8000-000000000002'),
  0.33333333::numeric,
  'first partial receipt receives its rounded carrying-value share'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000004', true);
select lives_ok(
  $$ select public.receive_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'rounding-residual'),
       4, jsonb_build_array(jsonb_build_object(
         'line_id', (select id from public.inventory_transfer_lines
                    where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'rounding-residual')),
         'quantity', 2)), 'phase3c-rounding-receive-02') $$,
  'final receipt receives the outstanding value residual'
);
reset role;
select is(
  (select sum(carrying_value_shop) from public.inventory_balances
   where shop_id = '98100000-0000-4000-8000-000000000001'
     and variant_id = '98400000-0000-4000-8000-000000000008'),
  1::numeric,
  'rounding residual allocation conserves the original shop-level carrying value exactly'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$ insert into phase3c_transfer_results values (
       'serialized', public.request_inventory_transfer(
         '98100000-0000-4000-8000-000000000001',
         '98200000-0000-4000-8000-000000000001',
         '98200000-0000-4000-8000-000000000002',
         '[{"serialized_inventory_id":"98500000-0000-4000-8000-000000000001"},{"serialized_inventory_id":"98500000-0000-4000-8000-000000000002"}]'::jsonb,
         'Transfer two synthetic devices', 'phase3c-serialized-request'
       )
     ) $$,
  'Owner can request serialized stock without duplicating device identifiers'
);
select throws_ok(
  $$ select public.request_inventory_transfer(
       '98100000-0000-4000-8000-000000000001',
       '98200000-0000-4000-8000-000000000001',
       '98200000-0000-4000-8000-000000000002',
       '[{"serialized_inventory_id":"98500000-0000-4000-8000-000000000001"}]'::jsonb,
       'Competing device claim', 'phase3c-device-claim-duplicate'
     ) $$,
  '23505', null,
  'a serialized device cannot be claimed by two active transfers'
);
select lives_ok(
  $$ select public.approve_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'serialized'),
       1, 'phase3c-serialized-approve') $$,
  'Owner can approve serialized transfer'
);
select lives_ok(
  $$ select public.dispatch_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'serialized'),
       2, 'phase3c-serialized-dispatch') $$,
  'Owner can dispatch the approved serialized devices'
);
select throws_ok(
  $$ select public.receive_inventory_transfer(
       '98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'serialized'),
       3,
       jsonb_build_array(jsonb_build_object(
         'line_id', (select id from public.inventory_transfer_lines
                    where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'serialized')
                      and line_number = 1),
         'quantity', 1,
         'extra', true
       )),
       'phase3c-extra-receipt-key'
     ) $$,
  '22023', null,
  'transfer receipt lines reject unrecognized keys'
);
select ok(
  (select count(*) = 2 and bool_and(availability_status = 'reserved'
      and transfer_state = 'in_transit'
      and branch_id = '98200000-0000-4000-8000-000000000001')
   from public.serialized_inventory
   where id in ('98500000-0000-4000-8000-000000000001', '98500000-0000-4000-8000-000000000002')),
  'dispatched devices remain unavailable and retain their last confirmed source branch'
);
reset role;
select throws_ok(
  $$ update public.serialized_inventory
     set availability_status = 'available'
     where id = '98500000-0000-4000-8000-000000000001' $$,
  '42501', null,
  'an in-transit device cannot be made available before destination receipt'
);
select throws_ok(
  $$ update public.serialized_inventory
     set availability_status = 'sold'
     where id = '98500000-0000-4000-8000-000000000001' $$,
  '42501', null,
  'an in-transit device cannot be sold at its source before destination receipt'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$ select public.receive_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'serialized'),
       3, jsonb_build_array(jsonb_build_object(
         'line_id', (select id from public.inventory_transfer_lines
                    where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'serialized')
                      and line_number = 1), 'quantity', 1)),
       'phase3c-serialized-receive-01') $$,
  'serialized transfers support receiving one device at a time'
);
select throws_ok(
  $$ select public.receive_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'serialized'),
       4, jsonb_build_array(jsonb_build_object(
         'line_id', (select id from public.inventory_transfer_lines
                    where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'serialized')
                      and line_number = 1), 'quantity', 1)),
       'phase3c-serialized-duplicate-receipt') $$,
  '23514', null,
  'a serialized device already received cannot be received a second time'
);
reset role;
select ok(
  (select branch_id = '98200000-0000-4000-8000-000000000002'
          and availability_status = 'available' and transfer_state is null
   from public.serialized_inventory
   where id = '98500000-0000-4000-8000-000000000001'),
  'received serialized device keeps its permanent ID and moves to destination availability'
);
select ok(
  (select branch_id = '98200000-0000-4000-8000-000000000001'
          and transfer_state = 'in_transit'
   from public.serialized_inventory
   where id = '98500000-0000-4000-8000-000000000002'),
  'unreceived serialized device remains separately accountable in transit'
);
select is(
  (select count(*)::integer from public.serialized_identifiers
   where serialized_inventory_id in ('98500000-0000-4000-8000-000000000001', '98500000-0000-4000-8000-000000000002')),
  2,
  'serialized transfer preserves all original identifiers without duplication'
);
select is(
  (select count(*)::integer from public.serialized_inventory
   where id in ('98500000-0000-4000-8000-000000000001', '98500000-0000-4000-8000-000000000002')),
  2,
  'serialized transfer reuses the original device records rather than creating duplicates'
);
select ok(
  (select count(*) = 3
      and count(*) filter (where movement_type = 'transfer_out'
        and branch_id = '98200000-0000-4000-8000-000000000001') = 2
      and count(*) filter (where movement_type = 'transfer_in'
        and branch_id = '98200000-0000-4000-8000-000000000002') = 1
   from public.inventory_movements
   where transfer_line_id in (
     select id from public.inventory_transfer_lines
     where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'serialized')
   )),
  'serialized movement history retains both branch contexts and transfer-line identity'
);
select is(
  (select count(*)::integer from public.inventory_transfer_in_transit
   where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'serialized')),
  1,
  'partially received serialized transfer exposes one outstanding device'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000003', true);
select lives_ok(
  $$ select public.receive_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'serialized'),
       4, jsonb_build_array(jsonb_build_object(
         'line_id', (select id from public.inventory_transfer_lines
                    where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'serialized')
                      and line_number = 2), 'quantity', 1)),
       'phase3c-serialized-receive-02') $$,
  'an assigned Manager at the destination may receive the remaining device'
);
reset role;
select ok(
  (select count(*) = 4
      and count(*) filter (where movement_type = 'transfer_out'
        and branch_id = '98200000-0000-4000-8000-000000000001') = 2
      and count(*) filter (where movement_type = 'transfer_in'
        and branch_id = '98200000-0000-4000-8000-000000000002') = 2
   from public.inventory_movements
   where transfer_line_id in (
     select id from public.inventory_transfer_lines
     where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'serialized')
   )),
  'final serialized receipt records both source and destination movements'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$ insert into phase3c_transfer_results values (
       'transit-only', public.request_inventory_transfer(
         '98100000-0000-4000-8000-000000000001',
         '98200000-0000-4000-8000-000000000001',
         '98200000-0000-4000-8000-000000000002',
         '[{"variant_id":"98400000-0000-4000-8000-000000000006","valuation_status":"known_cost","quantity":2}]'::jsonb,
         'Create an in-transit-only archival guard fixture', 'phase3c-transit-only-request'
       )
     ) $$,
  'a transfer can be requested for the transit-only archival fixture'
);
select lives_ok(
  $$ select public.approve_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'transit-only'),
       1, 'phase3c-transit-only-approve') $$,
  'transit-only fixture can be approved'
);
select lives_ok(
  $$ select public.dispatch_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'transit-only'),
       2, 'phase3c-transit-only-dispatch') $$,
  'transit-only fixture can be dispatched'
);
reset role;
select is(
  (select on_hand_qty from public.inventory_balances
   where variant_id = '98400000-0000-4000-8000-000000000006'
     and branch_id = '98200000-0000-4000-8000-000000000001'),
  0,
  'transit-only fixture has no source on-hand stock after dispatch'
);
select is(
  (select outstanding_qty from public.inventory_transfer_in_transit
   where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'transit-only')),
  2,
  'in-transit-only quantity remains in a durable transfer position'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$ select public.archive_product_variant(
       '98100000-0000-4000-8000-000000000001',
       '98400000-0000-4000-8000-000000000006',
       1, 'phase3c-archive-transit-variant'
     ) $$,
  '23514', null,
  'variant archival is blocked while its only owned stock is in transit'
);
select throws_ok(
  $$ select public.cancel_inventory_transfer(
       '98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'transit-only'),
       3, 'Cannot cancel after dispatch', 'phase3c-cancel-after-dispatch'
     ) $$,
  '40001', null,
  'a dispatched transfer cannot be cancelled or silently restocked'
);
reset role;

-- Cancellation returns only pre-dispatch reservations.
set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$ insert into phase3c_transfer_results values (
       'cancel-approved', public.request_inventory_transfer(
         '98100000-0000-4000-8000-000000000001',
         '98200000-0000-4000-8000-000000000001',
         '98200000-0000-4000-8000-000000000002',
         '[{"variant_id":"98400000-0000-4000-8000-000000000003","valuation_status":"known_cost","quantity":1}]'::jsonb,
         'Pre-dispatch cancellation test', 'phase3c-cancel-approved-request'
       )
     ) $$,
  'pre-dispatch cancellation fixture is requested'
);
select lives_ok(
  $$ select public.approve_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'cancel-approved'),
       1, 'phase3c-cancel-approved-approve') $$,
  'pre-dispatch cancellation fixture can reserve stock'
);
select lives_ok(
  $$ select public.cancel_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'cancel-approved'),
       2, 'Owner cancelled before dispatch', 'phase3c-cancel-approved-cancel') $$,
  'an Owner may cancel before dispatch and release its reservation'
);
reset role;
select ok(
  (select available_qty = 1 and reserved_transfer_qty = 0
   from public.inventory_balances
   where variant_id = '98400000-0000-4000-8000-000000000003'
     and branch_id = '98200000-0000-4000-8000-000000000001'),
  'pre-dispatch cancellation restores available quantity without changing carrying value'
);

-- Serialized cancellation releases the active device claim and preserves identity.
set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$ insert into phase3c_transfer_results values (
       'serialized-cancel', public.request_inventory_transfer(
         '98100000-0000-4000-8000-000000000001',
         '98200000-0000-4000-8000-000000000002',
         '98200000-0000-4000-8000-000000000001',
         '[{"serialized_inventory_id":"98500000-0000-4000-8000-000000000001"}]'::jsonb,
         'Cancel a serialized reservation before dispatch', 'phase3c-serialized-cancel-request'
       )
     ) $$,
  'a received device can be requested for a new transfer without duplicating its identity'
);
select lives_ok(
  $$ select public.approve_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'serialized-cancel'),
       1, 'phase3c-serialized-cancel-approve') $$,
  'serialized cancellation fixture reserves its device'
);
select lives_ok(
  $$ select public.cancel_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'serialized-cancel'),
       2, 'Release the serialized device before dispatch', 'phase3c-serialized-cancel-cancel') $$,
  'pre-dispatch cancellation releases a serialized reservation'
);
reset role;
select ok(
  (select branch_id = '98200000-0000-4000-8000-000000000002'
      and availability_status = 'available' and transfer_state is null
   from public.serialized_inventory
   where id = '98500000-0000-4000-8000-000000000001'),
  'cancelled serialized device remains available at its last confirmed branch'
);
select ok(
  (select not claim_active and approved_qty = 1 and dispatched_qty = 0
   from public.inventory_transfer_lines
   where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'serialized-cancel')),
  'serialized cancellation deactivates the identifier claim without erasing line history'
);

-- Idempotency, version checks, and insufficient stock.
set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$ insert into phase3c_transfer_results values (
       'idempotent-request', public.request_inventory_transfer(
         '98100000-0000-4000-8000-000000000001',
         '98200000-0000-4000-8000-000000000001',
         '98200000-0000-4000-8000-000000000002',
         '[{"variant_id":"98400000-0000-4000-8000-000000000003","valuation_status":"known_cost","quantity":1}]'::jsonb,
         'Idempotency test', 'phase3c-request-idempotent-01'
       )
     ) $$,
  'new idempotent transfer request is recorded'
);
select is(
  (select public.request_inventory_transfer(
     '98100000-0000-4000-8000-000000000001',
     '98200000-0000-4000-8000-000000000001',
     '98200000-0000-4000-8000-000000000002',
     '[{"variant_id":"98400000-0000-4000-8000-000000000003","valuation_status":"known_cost","quantity":1}]'::jsonb,
     'Idempotency test', 'phase3c-request-idempotent-01'
   )::text),
  (select transfer_id::text from phase3c_transfer_results where name = 'idempotent-request'),
  'same key and same payload returns the original transfer exactly once'
);
select throws_ok(
  $$ select public.request_inventory_transfer(
       '98100000-0000-4000-8000-000000000001',
       '98200000-0000-4000-8000-000000000001',
       '98200000-0000-4000-8000-000000000002',
       '[{"variant_id":"98400000-0000-4000-8000-000000000003","valuation_status":"known_cost","quantity":2}]'::jsonb,
       'Different payload', 'phase3c-request-idempotent-01'
     ) $$,
  '23505', null,
  'reusing an idempotency key with a conflicting payload fails'
);
select throws_ok(
  $$ select public.approve_inventory_transfer(
       '98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'idempotent-request'),
       99, 'phase3c-stale-version-01'
     ) $$,
  '40001', null,
  'stale optimistic versions are rejected'
);
select lives_ok(
  $$ insert into phase3c_transfer_results values (
       'insufficient', public.request_inventory_transfer(
         '98100000-0000-4000-8000-000000000001',
         '98200000-0000-4000-8000-000000000001',
         '98200000-0000-4000-8000-000000000002',
         '[{"variant_id":"98400000-0000-4000-8000-000000000001","valuation_status":"known_cost","quantity":99}]'::jsonb,
         'Insufficient stock request', 'phase3c-insufficient-request'
       )
     ) $$,
  'request may be recorded before stock is approved'
);
select throws_ok(
  $$ select public.approve_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'insufficient'),
       1, 'phase3c-insufficient-approve') $$,
  '23514', null,
  'approval atomically rejects insufficient source availability'
);
select lives_ok(
  $$ select public.cancel_inventory_transfer('98100000-0000-4000-8000-000000000001',
       (select transfer_id from phase3c_transfer_results where name = 'insufficient'),
       1, 'Close insufficient request', 'phase3c-insufficient-cancel') $$,
  'an unapproved insufficient request can be cancelled safely'
);
reset role;

-- Cross-shop, inactive, suspended, and role authorization denial.
set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$ select public.request_inventory_transfer('98100000-0000-4000-8000-000000000001',
       '98200000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000002',
       '[{"variant_id":"98400000-0000-4000-8000-000000000001","valuation_status":"known_cost","quantity":1}]'::jsonb,
       'Sales staff denied', 'phase3c-sales-denied-01') $$,
  '42501', null,
  'Sales Staff cannot mutate transfers'
);
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000006', true);
select throws_ok(
  $$ select public.request_inventory_transfer('98100000-0000-4000-8000-000000000001',
       '98200000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000002',
       '[{"variant_id":"98400000-0000-4000-8000-000000000001","valuation_status":"known_cost","quantity":1}]'::jsonb,
       'Suspended member denied', 'phase3c-suspended-denied-1') $$,
  '42501', null,
  'suspended members cannot request transfers'
);
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$ select public.request_inventory_transfer('98100000-0000-4000-8000-000000000001',
       '98200000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000004',
       '[{"variant_id":"98400000-0000-4000-8000-000000000001","valuation_status":"known_cost","quantity":1}]'::jsonb,
       'Cross-shop denied', 'phase3c-cross-shop-denied-01') $$,
  '42501', null,
  'cross-shop destination branches are rejected'
);
select throws_ok(
  $$ select public.request_inventory_transfer('98100000-0000-4000-8000-000000000001',
       '98200000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000003',
       '[{"variant_id":"98400000-0000-4000-8000-000000000001","valuation_status":"known_cost","quantity":1}]'::jsonb,
       'Inactive denied', 'phase3c-inactive-denied-01') $$,
  '42501', null,
  'inactive branches cannot be transfer endpoints'
);
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000007', true);
select is(
  (select count(*)::integer from public.inventory_transfers
   where id = (select transfer_id from phase3c_transfer_results where name = 'known-cost')),
  0,
  'a different shop Owner cannot read another shop transfer'
);
reset role;

-- Authorization checks also apply to replay paths; a suspended member cannot
-- use a previously valid operation key to recover a transfer result.
set local role authenticated;
select set_config('request.jwt.claim.sub', '98000000-0000-4000-8000-000000000006', true);
select throws_ok(
  $$ select public.request_inventory_transfer('98100000-0000-4000-8000-000000000001',
       '98200000-0000-4000-8000-000000000001', '98200000-0000-4000-8000-000000000002',
       '[{"variant_id":"98400000-0000-4000-8000-000000000003","valuation_status":"known_cost","quantity":1}]'::jsonb,
       'Idempotency test', 'phase3c-request-idempotent-01') $$,
  '42501', null,
  'idempotent replay still requires current active authorization'
);
select throws_ok(
  $$ insert into public.inventory_transfer_events default values $$,
  '42501', null,
  'authenticated clients cannot insert immutable transfer audit events directly'
);
select throws_ok(
  $$ insert into public.inventory_transfer_lines default values $$,
  '42501', null,
  'authenticated clients cannot add transfer lines directly'
);
select throws_ok(
  $$ insert into public.inventory_movements default values $$,
  '42501', null,
  'authenticated clients cannot write inventory movements directly'
);
select throws_ok(
  $$ update public.inventory_balances set available_qty = available_qty $$,
  '42501', null,
  'authenticated clients cannot alter stock balances directly'
);
select throws_ok(
  $$ update public.inventory_transfers set status = 'received' $$,
  '42501', null,
  'authenticated clients cannot directly change transfer state'
);
select throws_ok(
  $$ truncate table public.inventory_transfer_events $$,
  '42501', null,
  'authenticated clients cannot truncate transfer audit history'
);
reset role;

set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$ select public.request_inventory_transfer(
       '98100000-0000-4000-8000-000000000001',
       '98200000-0000-4000-8000-000000000001',
       '98200000-0000-4000-8000-000000000002',
       '[{"variant_id":"98400000-0000-4000-8000-000000000001","valuation_status":"known_cost","quantity":1}]'::jsonb,
       'Anonymous denied', 'phase3c-anonymous-denied1'
     ) $$,
  '42501', null,
  'anonymous sessions cannot execute transfer RPCs'
);
reset role;

select throws_ok(
  $$ update public.inventory_transfer_events
     set event_payload = '{}'::jsonb
     where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'known-cost')
       and event_type = 'requested' $$,
  '42501', null,
  'transfer audit events reject mutation even from a privileged SQL test session'
);
select throws_ok(
  $$ delete from public.inventory_transfer_lines
     where transfer_id = (select transfer_id from phase3c_transfer_results where name = 'known-cost') $$,
  '42501', null,
  'transfer lines cannot be deleted after their history is recorded'
);
select throws_ok(
  $$ truncate table public.inventory_transfer_events $$,
  '42501', null,
  'transfer audit history cannot be truncated by a privileged SQL session'
);
select throws_ok(
  $$ update public.branches set is_active = false
     where id = '98200000-0000-4000-8000-000000000001' $$,
  '23514', null,
  'a source or destination branch with open transfers cannot be deactivated'
);
select ok(
  (select not pg_catalog.has_table_privilege('service_role', 'public.inventory_transfers', 'INSERT')
      and not pg_catalog.has_table_privilege('service_role', 'public.inventory_transfers', 'UPDATE')
      and not pg_catalog.has_table_privilege('service_role', 'public.inventory_transfers', 'DELETE')
      and not pg_catalog.has_table_privilege('service_role', 'public.inventory_transfers', 'TRUNCATE')
      and not pg_catalog.has_table_privilege('service_role', 'public.inventory_transfer_lines', 'INSERT')
      and not pg_catalog.has_table_privilege('service_role', 'public.inventory_transfer_lines', 'UPDATE')
      and not pg_catalog.has_table_privilege('service_role', 'public.inventory_transfer_lines', 'DELETE')
      and not pg_catalog.has_table_privilege('service_role', 'public.inventory_transfer_lines', 'TRUNCATE')
      and not pg_catalog.has_table_privilege('service_role', 'public.inventory_transfer_events', 'INSERT')
      and not pg_catalog.has_table_privilege('service_role', 'public.inventory_transfer_events', 'UPDATE')
      and not pg_catalog.has_table_privilege('service_role', 'public.inventory_transfer_events', 'DELETE')
      and not pg_catalog.has_table_privilege('service_role', 'public.inventory_transfer_events', 'TRUNCATE')),
  'service_role has no direct transfer table write or TRUNCATE privileges'
);
select ok(
  (select pg_catalog.has_function_privilege('authenticated', 'public.request_inventory_transfer(uuid,uuid,uuid,jsonb,text,text)', 'EXECUTE')
      and not pg_catalog.has_function_privilege('anon', 'public.request_inventory_transfer(uuid,uuid,uuid,jsonb,text,text)', 'EXECUTE')
      and not pg_catalog.has_function_privilege('service_role', 'public.request_inventory_transfer(uuid,uuid,uuid,jsonb,text,text)', 'EXECUTE')),
  'only authenticated sessions can invoke the request RPC; authorization remains checked inside it'
);
select ok(
  (select pg_catalog.pg_get_constraintdef(constraint_row.oid) is not null
          and not attribute.attnotnull
   from pg_catalog.pg_constraint as constraint_row
   join pg_catalog.pg_attribute as attribute
     on attribute.attrelid = constraint_row.conrelid
   where constraint_row.conrelid = 'public.inventory_operations'::regclass
     and constraint_row.conname = 'inventory_operations_result_target'
     and attribute.attname = 'result_receipt_id'),
  'the transfer operation extension preserves nullable receipt results for new rows while legacy receipts remain supported'
);
select ok(
  (select pg_catalog.pg_get_functiondef('public.approve_inventory_transfer(uuid,uuid,bigint,text)'::regprocedure) ~* 'for update'
      and exists (
        select 1 from pg_catalog.pg_indexes as index_row
        where index_row.schemaname = 'public'
          and index_row.indexname = 'inventory_transfer_lines_one_active_device_idx'
      )),
  'approval serializes balance decisions and serialized requests have a unique active-device claim index'
);

select * from finish();
rollback;
