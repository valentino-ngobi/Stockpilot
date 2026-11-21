begin;

-- This pgTAP suite is for the disposable Milestone 2 database only.
-- All identities and product values are fictional.
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('a1000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'catalog-owner-a@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('a1000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'catalog-manager-a@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('a1000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'catalog-staff-a@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('a1000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'catalog-suspended-a@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('a1000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'catalog-owner-b@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.shops (id, name, created_by) values
  ('a2000000-0000-4000-8000-000000000001', 'Fictional Catalog Shop A', 'a1000000-0000-4000-8000-000000000001'),
  ('a2000000-0000-4000-8000-000000000002', 'Fictional Catalog Shop B', 'a1000000-0000-4000-8000-000000000005');

insert into public.shop_memberships (shop_id, user_id, role, status, created_by) values
  ('a2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 'owner', 'active', 'a1000000-0000-4000-8000-000000000001'),
  ('a2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000002', 'manager', 'active', 'a1000000-0000-4000-8000-000000000001'),
  ('a2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000003', 'inventory_staff', 'active', 'a1000000-0000-4000-8000-000000000001'),
  ('a2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000004', 'inventory_staff', 'suspended', 'a1000000-0000-4000-8000-000000000001'),
  ('a2000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000005', 'owner', 'active', 'a1000000-0000-4000-8000-000000000005');

insert into public.branches (id, shop_id, name, is_primary, is_active, created_by) values
  ('a3000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001', 'A Main', true, true, 'a1000000-0000-4000-8000-000000000001'),
  ('a3000000-0000-4000-8000-000000000002', 'a2000000-0000-4000-8000-000000000002', 'B Main', true, true, 'a1000000-0000-4000-8000-000000000005');

insert into public.shop_settings (
  shop_id, operating_currency_code, configured_by, updated_by
) values (
  'a2000000-0000-4000-8000-000000000001', 'USD',
  'a1000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000001', true);

select lives_ok(
  $$ select public.create_product(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_idempotency_key => 'catalog-product-0001',
    p_name => 'Fictional Phone',
    p_product_type => 'smartphone',
    p_tracking_mode => 'serialized',
    p_brand => 'Example Labs',
    p_model => 'F-1',
    p_manufacturer_model_number => 'SHARED-FAMILY-MODEL'
  ) $$,
  'Owner creates a product without external lookups'
);

select is(
  public.create_product(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_idempotency_key => 'catalog-product-0001',
    p_name => 'Fictional Phone',
    p_product_type => 'smartphone',
    p_tracking_mode => 'serialized',
    p_brand => 'Example Labs',
    p_model => 'F-1',
    p_manufacturer_model_number => 'SHARED-FAMILY-MODEL'
  ),
  (select product.id from public.products as product
   where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
     and product.name = 'Fictional Phone'),
  'an exact product retry returns the original product'
);

select throws_ok(
  $$ select public.create_product(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_idempotency_key => 'catalog-product-0001',
    p_name => 'Changed Fictional Phone',
    p_product_type => 'smartphone',
    p_tracking_mode => 'serialized'
  ) $$,
  '22023', null,
  'reusing a product idempotency key with a changed request is rejected'
);

select throws_ok(
  $$ select public.create_product(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_idempotency_key => 'catalog-product-duplicate',
    p_name => '  fictional phone  ',
    p_product_type => 'smartphone',
    p_tracking_mode => 'serialized'
  ) $$,
  '23505', null,
  'normalized exact product-name duplicates are rejected'
);

select lives_ok(
  $$ select public.create_product(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_idempotency_key => 'catalog-product-0002',
    p_name => 'Fictional Phone Plus',
    p_product_type => 'smartphone',
    p_tracking_mode => 'serialized',
    p_manufacturer_model_number => 'SHARED-FAMILY-MODEL'
  ) $$,
  'similar product names and a shared family model number are allowed'
);

select is(
  (select count(*)::integer from public.products as product
   where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
     and product.manufacturer_model_number = 'SHARED-FAMILY-MODEL'),
  2,
  'manufacturer model numbers are not treated as globally unique'
);

select throws_ok(
  $$ select public.create_product(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_idempotency_key => 'catalog-invalid-mode',
    p_name => 'Invalid Tracking Product',
    p_product_type => 'smartphone',
    p_tracking_mode => 'guess'
  ) $$,
  '22023', null,
  'unsupported tracking modes are rejected'
);

select throws_ok(
  $$ select public.create_product(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_idempotency_key => 'catalog-invalid-attrs',
    p_name => 'Invalid Attributes Product',
    p_product_type => 'other',
    p_tracking_mode => 'quantity',
    p_attributes => '[]'::jsonb
  ) $$,
  '22023', null,
  'product attributes must be a JSON object'
);

select lives_ok(
  $$ select public.create_product_variant(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_product_id => (select product.id from public.products as product
      where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and product.name = 'Fictional Phone'),
    p_idempotency_key => 'catalog-variant-0001',
    p_colour => 'Midnight',
    p_storage_capacity => '256 GB'
  ) $$,
  'Owner adds a variant to an existing product'
);

select is(
  public.create_product_variant(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_product_id => (select product.id from public.products as product
      where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and product.name = 'Fictional Phone'),
    p_idempotency_key => 'catalog-variant-0001',
    p_colour => 'Midnight',
    p_storage_capacity => '256 GB'
  ),
  (select variant.id from public.product_variants as variant
   join public.products as product
     on product.shop_id = variant.shop_id and product.id = variant.product_id
   where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
     and product.name = 'Fictional Phone'
     and variant.colour = 'Midnight'
     and variant.storage_capacity = '256 GB'),
  'an exact variant retry returns the original variant'
);

select throws_ok(
  $$ select public.create_product_variant(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_product_id => (select product.id from public.products as product
      where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and product.name = 'Fictional Phone'),
    p_idempotency_key => 'catalog-variant-duplicate',
    p_colour => 'midnight',
    p_storage_capacity => '256 gb'
  ) $$,
  '23505', null,
  'normalized duplicate active variant signatures are rejected'
);

select lives_ok(
  $$ select public.update_product_variant(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_variant_id => (select variant.id from public.product_variants as variant
      join public.products as product
        on product.shop_id = variant.shop_id and product.id = variant.product_id
      where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and product.name = 'Fictional Phone'
        and variant.colour = 'Midnight'),
    p_expected_version => 1,
    p_idempotency_key => 'catalog-variant-update-01',
    p_colour => 'Midnight',
    p_storage_capacity => '256 GB',
    p_network_lock_status => null,
    p_attributes => '{"grade":"retail"}'::jsonb
  ) $$,
  'Owner updates a variant using its optimistic version'
);

select throws_ok(
  $$ select public.update_product_variant(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_variant_id => (select variant.id from public.product_variants as variant
      join public.products as product
        on product.shop_id = variant.shop_id and product.id = variant.product_id
      where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and product.name = 'Fictional Phone'
        and variant.colour = 'Midnight'),
    p_expected_version => 1,
    p_idempotency_key => 'catalog-variant-stale-01',
    p_colour => 'Midnight Stale',
    p_storage_capacity => '256 GB',
    p_network_lock_status => null,
    p_attributes => '{"grade":"retail"}'::jsonb
  ) $$,
  '40001', null,
  'stale variant edits are rejected'
);

select lives_ok(
  $$ select public.add_product_identifier(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_product_id => (select product.id from public.products as product
      where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and product.name = 'Fictional Phone'),
    p_variant_id => null,
    p_identifier_type => 'barcode',
    p_raw_value => 'CATALOG-BARCODE-001',
    p_idempotency_key => 'catalog-id-product-01'
  ) $$,
  'a product-level barcode is stored independently of device identifiers'
);

select lives_ok(
  $$ select public.add_product_identifier(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_product_id => null,
    p_variant_id => (select variant.id from public.product_variants as variant
      join public.products as product
        on product.shop_id = variant.shop_id and product.id = variant.product_id
      where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and product.name = 'Fictional Phone'
        and variant.colour = 'Midnight'),
    p_identifier_type => 'sku',
    p_raw_value => 'CATALOG-SKU-001',
    p_idempotency_key => 'catalog-id-variant-01'
  ) $$,
  'a variant-level SKU is associated with its parent product'
);

select is(
  (select count(*)::integer from public.product_identifiers as identifier
   where identifier.shop_id = 'a2000000-0000-4000-8000-000000000001'
     and identifier.product_id = (
       select product.id from public.products as product
       where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
         and product.name = 'Fictional Phone'
     )
     and identifier.variant_id is null),
  1,
  'product-level identifiers have no variant target'
);

select throws_ok(
  $$ select public.add_product_identifier(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_product_id => null,
    p_variant_id => (select variant.id from public.product_variants as variant
      join public.products as product
        on product.shop_id = variant.shop_id and product.id = variant.product_id
      where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and product.name = 'Fictional Phone'
        and variant.colour = 'Midnight'),
    p_identifier_type => 'sku',
    p_raw_value => 'catalog-sku-001',
    p_idempotency_key => 'catalog-id-duplicate-01'
  ) $$,
  '23505', null,
  'normalized identifier uniqueness is shop-wide and case-insensitive'
);

select throws_ok(
  $$ select public.add_product_identifier(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_product_id => (select product.id from public.products as product
      where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and product.name = 'Fictional Phone'),
    p_variant_id => null,
    p_identifier_type => 'imei1',
    p_raw_value => '000000000000000',
    p_idempotency_key => 'catalog-id-invalid-type'
  ) $$,
  '22023', null,
  'device IMEI identifiers cannot be entered as product catalog identifiers'
);

select lives_ok(
  $$ select public.retire_product_identifier(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_identifier_id => (select identifier.id from public.product_identifiers as identifier
      where identifier.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and identifier.raw_value = 'CATALOG-BARCODE-001'),
    p_idempotency_key => 'catalog-id-retire-01'
  ) $$,
  'a product identifier can be retired without deleting its history'
);

select is(
  (select count(*)::integer from public.product_identifiers as identifier
   where identifier.shop_id = 'a2000000-0000-4000-8000-000000000001'
     and identifier.raw_value = 'CATALOG-BARCODE-001'
     and identifier.retired_at is not null
     and identifier.retired_by = 'a1000000-0000-4000-8000-000000000001'),
  1,
  'identifier retirement records the actor and timestamp'
);

select throws_ok(
  $$ select public.add_product_identifier(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_product_id => (select product.id from public.products as product
      where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and product.name = 'Fictional Phone Plus'),
    p_variant_id => null,
    p_identifier_type => 'barcode',
    p_raw_value => 'catalog-barcode-001',
    p_idempotency_key => 'catalog-id-reuse-01'
  ) $$,
  '23505', null,
  'retired identifiers remain reserved and cannot be silently reused'
);

select lives_ok(
  $$ select public.update_product(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_product_id => (select product.id from public.products as product
      where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and product.name = 'Fictional Phone'),
    p_expected_version => (
      select product.catalog_version from public.products as product
      where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and product.name = 'Fictional Phone'
    ),
    p_idempotency_key => 'catalog-product-update-01',
    p_name => 'Fictional Phone Updated',
    p_product_type => 'smartphone',
    p_tracking_mode => 'serialized',
    p_brand => 'Example Labs',
    p_model => 'F-1',
    p_manufacturer_model_number => 'SHARED-FAMILY-MODEL',
    p_description => null,
    p_attributes => '{}'::jsonb
  ) $$,
  'Owner updates a product using its current optimistic version'
);

select throws_ok(
  $$ select public.update_product(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_product_id => (select product.id from public.products as product
      where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and product.name = 'Fictional Phone Updated'),
    p_expected_version => 1,
    p_idempotency_key => 'catalog-product-stale-01',
    p_name => 'Stale Overwrite',
    p_product_type => 'smartphone',
    p_tracking_mode => 'serialized',
    p_brand => 'Example Labs',
    p_model => 'F-1',
    p_manufacturer_model_number => 'SHARED-FAMILY-MODEL',
    p_description => null,
    p_attributes => '{}'::jsonb
  ) $$,
  '40001', null,
  'stale product edits are rejected'
);

select is(
  (select count(*)::integer from public.product_catalog_events as event
   where event.shop_id = 'a2000000-0000-4000-8000-000000000001'
     and event.event_type in ('product_created', 'product_updated',
       'variant_created', 'variant_updated', 'identifier_added',
       'identifier_retired')),
  8,
  'successful product, variant, and identifier changes produce audit events'
);

select is(
  (select count(*)::integer from public.catalog_operations as operation
   where operation.shop_id = 'a2000000-0000-4000-8000-000000000001'
     and operation.idempotency_key = 'catalog-product-0001'
     and operation.operation_type = 'product_created'),
  1,
  'an exact retry creates only one catalog operation'
);

select lives_ok(
  $$ select public.create_product(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_idempotency_key => 'catalog-mode-change-before',
    p_name => 'Mode Change Before Stock',
    p_product_type => 'other',
    p_tracking_mode => 'quantity'
  ) $$,
  'Owner creates an unused product before a tracking-mode change'
);

select lives_ok(
  $$ select public.update_product(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_product_id => (select product.id from public.products as product
      where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and product.name = 'Mode Change Before Stock'),
    p_expected_version => 1,
    p_idempotency_key => 'catalog-mode-change-before-update',
    p_name => 'Mode Change Before Stock',
    p_product_type => 'other',
    p_tracking_mode => 'serialized',
    p_brand => null,
    p_model => null,
    p_manufacturer_model_number => null,
    p_description => null,
    p_attributes => '{}'::jsonb
  ) $$,
  'tracking mode can change before stock or history exists'
);

select set_config('request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000002', true);
select lives_ok(
  $$ select public.create_product(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_idempotency_key => 'catalog-manager-create',
    p_name => 'Manager Created Accessory',
    p_product_type => 'accessory',
    p_tracking_mode => 'quantity'
  ) $$,
  'an active Manager can create a catalog product'
);

select throws_ok(
  $$ select public.create_product(
    p_shop_id => 'a2000000-0000-4000-8000-000000000002',
    p_idempotency_key => 'catalog-cross-shop-01',
    p_name => 'Unauthorized Cross Shop Product',
    p_product_type => 'other',
    p_tracking_mode => 'quantity'
  ) $$,
  '42501', null,
  'a Manager cannot write another shop catalog'
);

select set_config('request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$ select public.create_product(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_idempotency_key => 'catalog-staff-denied',
    p_name => 'Staff Cannot Create',
    p_product_type => 'other',
    p_tracking_mode => 'quantity'
  ) $$,
  '42501', null,
  'Inventory Staff can read but cannot mutate the catalog'
);

select set_config('request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$ select public.archive_product(
    'a2000000-0000-4000-8000-000000000001',
    (select product.id from public.products as product
      where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and product.name = 'Fictional Phone Updated'),
    2,
    'catalog-suspended-01'
  ) $$,
  '42501', null,
  'suspended members cannot archive a product'
);
select is(
  (select count(*)::integer from public.products as product
   where product.shop_id = 'a2000000-0000-4000-8000-000000000001'),
  0,
  'suspended members cannot read the catalog'
);
reset role;
select is(
  (select count(*)::integer from public.products as product
   where product.shop_id = 'a2000000-0000-4000-8000-000000000001'),
  4,
  'suspended membership cannot change catalog rows'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$ select public.create_product(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_idempotency_key => 'catalog-anon-denied',
    p_name => 'Anonymous Cannot Create',
    p_product_type => 'other',
    p_tracking_mode => 'quantity'
  ) $$,
  '42501', null,
  'anonymous callers cannot create catalog records'
);

reset role;

-- A quantity receipt is created after the catalog migration. The trigger
-- captures the contemporaneous catalog description; prior receipt rows were
-- not backfilled by this migration.
select set_config('request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000001', true);
set local role authenticated;

select lives_ok(
  $$ select public.create_product(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_idempotency_key => 'catalog-receipt-product',
    p_name => 'Receipt Label Before Edit',
    p_product_type => 'accessory',
    p_tracking_mode => 'quantity'
  ) $$,
  'Owner creates a quantity product for receipt snapshot testing'
);

select lives_ok(
  $$ select public.create_product_variant(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_product_id => (select product.id from public.products as product
      where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and product.name = 'Receipt Label Before Edit'),
    p_idempotency_key => 'catalog-receipt-variant'
  ) $$,
  'Owner creates a default quantity variant'
);

select lives_ok(
  $$ select public.receive_quantity_inventory(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_branch_id => 'a3000000-0000-4000-8000-000000000001',
    p_idempotency_key => 'catalog-snapshot-receipt',
    p_receipt_kind => 'manual_unknown_cost',
    p_supplier_name => null,
    p_supplier_invoice_reference => null,
    p_original_currency_code => null,
    p_original_invoice_amount => null,
    p_lines => jsonb_build_array(jsonb_build_object(
      'line_number', 1,
      'variant_id', (
        select variant.id from public.product_variants as variant
        join public.products as product
          on product.shop_id = variant.shop_id and product.id = variant.product_id
        where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
          and product.name = 'Receipt Label Before Edit'
      ),
      'quantity', 1
    )),
    p_rate_snapshot_id => null,
    p_manual_rate => null,
    p_manual_rate_source => null,
    p_manual_rate_observed_at => null,
    p_override_reason => null,
    p_accept_pending_fx => false
  ) $$,
  'authorized receiving still works with the automatic catalog snapshot trigger'
);

select is(
  (select line.catalog_snapshot ->> 'product_name'
   from public.inventory_receipt_lines as line
   join public.inventory_receipts as receipt
     on receipt.shop_id = line.shop_id
    and receipt.branch_id = line.branch_id
    and receipt.id = line.receipt_id
   join public.inventory_operations as operation
     on operation.shop_id = receipt.shop_id
    and operation.branch_id = receipt.branch_id
    and operation.id = receipt.operation_id
   where receipt.shop_id = 'a2000000-0000-4000-8000-000000000001'
     and operation.idempotency_key = 'catalog-snapshot-receipt'
     and line.line_number = 1),
  'Receipt Label Before Edit',
  'new receipt lines capture product label and variant context'
);

select lives_ok(
  $$ select public.update_product(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_product_id => (select product.id from public.products as product
      where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and product.name = 'Receipt Label Before Edit'),
    p_expected_version => 2,
    p_idempotency_key => 'catalog-receipt-product-update',
    p_name => 'Receipt Label After Edit',
    p_product_type => 'accessory',
    p_tracking_mode => 'quantity',
    p_brand => null,
    p_model => null,
    p_manufacturer_model_number => null,
    p_description => null,
    p_attributes => '{}'::jsonb
  ) $$,
  'catalog labels can change after receiving without rewriting history'
);

select is(
  (select line.catalog_snapshot ->> 'product_name'
   from public.inventory_receipt_lines as line
   join public.inventory_receipts as receipt
     on receipt.shop_id = line.shop_id
    and receipt.branch_id = line.branch_id
    and receipt.id = line.receipt_id
   join public.inventory_operations as operation
     on operation.shop_id = receipt.shop_id
    and operation.branch_id = receipt.branch_id
    and operation.id = receipt.operation_id
   where receipt.shop_id = 'a2000000-0000-4000-8000-000000000001'
     and operation.idempotency_key = 'catalog-snapshot-receipt'
     and line.line_number = 1),
  'Receipt Label Before Edit',
  'later catalog edits leave receipt snapshots unchanged'
);

select throws_ok(
  $$ select public.update_product(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_product_id => (select product.id from public.products as product
      where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and product.name = 'Receipt Label After Edit'),
    p_expected_version => 3,
    p_idempotency_key => 'catalog-mode-change-blocked',
    p_name => 'Receipt Label After Edit',
    p_product_type => 'accessory',
    p_tracking_mode => 'serialized',
    p_brand => null,
    p_model => null,
    p_manufacturer_model_number => null,
    p_description => null,
    p_attributes => '{}'::jsonb
  ) $$,
  '23514', null,
  'tracking mode cannot change after inventory or receipt history exists'
);

select is(
  (select count(*)::integer from public.inventory_receipt_lines as line
   join public.product_variants as variant
     on variant.shop_id = line.shop_id and variant.id = line.variant_id
   join public.products as product
     on product.shop_id = variant.shop_id and product.id = variant.product_id
   where line.shop_id = 'a2000000-0000-4000-8000-000000000001'
     and product.name = 'Receipt Label After Edit'),
  1,
  'receipt and movement references remain linked to the stable catalog identity'
);

select is(
  (select is_nullable::text from information_schema.columns
   where table_schema = 'public'
     and table_name = 'inventory_receipt_lines'
     and column_name = 'catalog_snapshot'),
  'YES',
  'catalog snapshots are nullable so existing receipt rows remain unmodified'
);

select is(
  (select column_default::text from information_schema.columns
   where table_schema = 'public'
     and table_name = 'inventory_receipt_lines'
     and column_name = 'catalog_snapshot'),
  null::text,
  'catalog snapshots have no fabricated default for existing receipt rows'
);

select lives_ok(
  $$ select public.archive_product(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_product_id => (select product.id from public.products as product
      where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and product.name = 'Manager Created Accessory'),
    p_expected_version => 1,
    p_idempotency_key => 'catalog-manager-product-archive'
  ) $$,
  'Owner can archive a product through the catalog RPC'
);

select is(
  (select count(*)::integer from public.products as product
   where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
     and product.name = 'Manager Created Accessory'
     and product.archived_at is not null),
  1,
  'archived products remain stored for historical references'
);

select lives_ok(
  $$ select public.create_product_variant(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_product_id => (select product.id from public.products as product
      where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and product.name = 'Fictional Phone Plus'),
    p_idempotency_key => 'catalog-variant-archive-create'
  ) $$,
  'Owner creates a variant for archive testing'
);

select lives_ok(
  $$ select public.archive_product_variant(
    p_shop_id => 'a2000000-0000-4000-8000-000000000001',
    p_variant_id => (select variant.id from public.product_variants as variant
      join public.products as product
        on product.shop_id = variant.shop_id and product.id = variant.product_id
      where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
        and product.name = 'Fictional Phone Plus'),
    p_expected_version => 1,
    p_idempotency_key => 'catalog-variant-archive'
  ) $$,
  'Owner can archive a variant without deleting its identity'
);

select is(
  (select count(*)::integer from public.product_variants as variant
   join public.products as product
     on product.shop_id = variant.shop_id and product.id = variant.product_id
   where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
     and product.name = 'Fictional Phone Plus'
     and variant.archived_at is not null),
  1,
  'archived variants remain stored'
);

select set_config('request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000005', true);
select lives_ok(
  $$ select public.create_product(
    p_shop_id => 'a2000000-0000-4000-8000-000000000002',
    p_idempotency_key => 'catalog-owner-b-create',
    p_name => 'Shop B Private Product',
    p_product_type => 'other',
    p_tracking_mode => 'quantity'
  ) $$,
  'Shop B Owner can manage their own catalog'
);

select set_config('request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000003', true);
select is(
  (select count(*)::integer from public.products as product
   where product.shop_id = 'a2000000-0000-4000-8000-000000000002'),
  0,
  'active staff reads remain tenant-isolated'
);
select is(
  (select count(*)::integer from public.catalog_operations as operation
   where operation.shop_id = 'a2000000-0000-4000-8000-000000000002'),
  0,
  'catalog operation history is tenant-isolated'
);

select throws_ok(
  $$ update public.products
     set name = 'Staff Direct Mutation'
     where shop_id = 'a2000000-0000-4000-8000-000000000001' $$,
  '42501', null,
  'authenticated staff cannot bypass the catalog RPCs with direct table writes'
);

select throws_ok(
  $$ update public.product_catalog_events
     set event_type = 'product_created'
     where shop_id = 'a2000000-0000-4000-8000-000000000001' $$,
  '42501', null,
  'authenticated users cannot update catalog audit events'
);
select throws_ok(
  $$ truncate table public.product_catalog_events $$,
  '42501', null,
  'authenticated users cannot truncate catalog audit history'
);

reset role;

select lives_ok(
  $$ insert into public.product_identifiers (
    shop_id, variant_id, identifier_type, raw_value, created_by
  ) values (
    'a2000000-0000-4000-8000-000000000001',
    (select variant.id from public.product_variants as variant
     join public.products as product
       on product.shop_id = variant.shop_id and product.id = variant.product_id
     where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
       and product.name = 'Fictional Phone Updated'),
    'manufacturer_part_number', 'LEGACY-SHAPE-PART-01',
    'a1000000-0000-4000-8000-000000000001'
  ) $$,
  'legacy trusted inserts that only provide variant_id remain compatible'
);
select is(
  (select identifier.product_id from public.product_identifiers as identifier
   where identifier.shop_id = 'a2000000-0000-4000-8000-000000000001'
     and identifier.raw_value = 'LEGACY-SHAPE-PART-01'),
  (select product.id from public.products as product
   where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
     and product.name = 'Fictional Phone Updated'),
  'the compatibility trigger derives product_id from the same-shop variant'
);

select throws_ok(
  $$ insert into public.product_identifiers (
    shop_id, product_id, variant_id, identifier_type, raw_value, created_by
  ) values (
    'a2000000-0000-4000-8000-000000000001',
    (select product.id from public.products as product
     where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
       and product.name = 'Fictional Phone Updated'),
    (select variant.id from public.product_variants as variant
     join public.products as product
       on product.shop_id = variant.shop_id and product.id = variant.product_id
     where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
       and product.name = 'Fictional Phone Plus'),
    'sku', 'BAD-SAME-SHOP-CROSS-PRODUCT',
    'a1000000-0000-4000-8000-000000000001'
  ) $$,
  '23503', null,
  'composite catalog identifier foreign keys reject another product variant'
);

select throws_ok(
  $$ insert into public.product_identifiers (
    shop_id, product_id, variant_id, identifier_type, raw_value, created_by
  ) values (
    'a2000000-0000-4000-8000-000000000001',
    (select product.id from public.products as product
     where product.shop_id = 'a2000000-0000-4000-8000-000000000002'
       and product.name = 'Shop B Private Product'),
    (select variant.id from public.product_variants as variant
     join public.products as product
       on product.shop_id = variant.shop_id and product.id = variant.product_id
     where product.shop_id = 'a2000000-0000-4000-8000-000000000001'
       and product.name = 'Fictional Phone Updated'),
    'sku', 'BAD-CROSS-SHOP-IDENTIFIER',
    'a1000000-0000-4000-8000-000000000001'
  ) $$,
  '23503', null,
  'composite catalog identifier foreign keys reject cross-shop product references'
);

select throws_ok(
  $$ update public.product_catalog_events
     set event_type = 'product_created' $$,
  '42501', null,
  'catalog event append-only trigger rejects owner updates'
);
set constraints all immediate;
select throws_ok(
  $$ truncate table public.product_catalog_events $$,
  '42501', null,
  'catalog event append-only trigger rejects owner truncation'
);

select ok(
  not has_table_privilege('anon', 'public.catalog_operations', 'INSERT')
  and not has_table_privilege('anon', 'public.product_catalog_events', 'INSERT')
  and not has_table_privilege('authenticated', 'public.catalog_operations', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.product_catalog_events', 'DELETE')
  and not has_table_privilege('service_role', 'public.catalog_operations', 'INSERT')
  and not has_table_privilege('service_role', 'public.catalog_operations', 'TRUNCATE')
  and not has_table_privilege('service_role', 'public.product_catalog_events', 'UPDATE')
  and not has_table_privilege('service_role', 'public.product_catalog_events', 'TRUNCATE'),
  'anon, authenticated, and service_role lack direct catalog audit write and truncate privileges'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.create_product(uuid,text,text,text,text,text,text,text,text,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.create_product(uuid,text,text,text,text,text,text,text,text,jsonb)',
    'EXECUTE'
  ),
  'catalog mutation RPCs are not executable by anon or service_role'
);

select ok(
  (select count(*) = 8
     and bool_and(
       procedure.prosecdef
       and coalesce(procedure.proconfig @> array['search_path=""']::text[], false)
     )
   from pg_catalog.pg_proc as procedure
   where procedure.oid = any(array[
     'public.create_product(uuid,text,text,text,text,text,text,text,text,jsonb)'::regprocedure,
     'public.create_product_variant(uuid,uuid,text,text,text,text,jsonb)'::regprocedure,
     'public.update_product(uuid,uuid,bigint,text,text,text,text,text,text,text,text,jsonb)'::regprocedure,
     'public.update_product_variant(uuid,uuid,bigint,text,text,text,text,jsonb)'::regprocedure,
     'public.archive_product(uuid,uuid,bigint,text)'::regprocedure,
     'public.archive_product_variant(uuid,uuid,bigint,text)'::regprocedure,
     'public.add_product_identifier(uuid,uuid,uuid,text,text,text)'::regprocedure,
     'public.retire_product_identifier(uuid,uuid,text)'::regprocedure
   ]::oid[])),
  'all catalog mutation RPCs are SECURITY DEFINER with an empty search_path'
);

select * from finish();
rollback;
