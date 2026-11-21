begin;

-- Disposable database only. Every identity, branch, product, and price below
-- is fictional. This suite is transactional and rolls its fixtures back.
--
-- Two-session cases remain separate from pgTAP and must be run only in the
-- isolated project: (1) competing first-price creates; (2) updates with the
-- same expected version; (3) identical and conflicting idempotency retries;
-- (4) assignment revocation racing a Manager price write; and (5) product or
-- variant archival racing quantity or serialized receiving. Expected outcomes:
-- one first-price/version winner; identical key requests replay the same result
-- and conflicting payloads fail; either the authorized price write commits
-- before revocation or it is denied after revocation; and for archive/receive,
-- either receipt commits first and archival is rejected for owned stock, or
-- archival commits first and receipt rejects the archived catalog row. These
-- are documented scenarios, not tests claimed as executed by this suite.
--
-- Populated-upgrade fixture (run separately, not as this post-migration suite):
-- after migrations 202611190001, 202611190002, 202611190003, 202611200001,
-- 202611210001, and 202611220001 are applied to the disposable database, but
-- before 202611220002 is applied, run the following synthetic setup and COMMIT:
--
-- begin;
-- insert into auth.users (
--   id, aud, role, email, encrypted_password, email_confirmed_at,
--   raw_app_meta_data, raw_user_meta_data, created_at, updated_at
-- ) values (
--   'b8100000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
--   'legacy-price-owner@example.test', '', now(), '{}'::jsonb, '{}'::jsonb,
--   now(), now()
-- );
-- insert into public.shops (id, name, created_by) values (
--   'b8200000-0000-4000-8000-000000000001', 'Fictional Legacy Price Shop',
--   'b8100000-0000-4000-8000-000000000001'
-- );
-- insert into public.shop_memberships (
--   shop_id, user_id, role, status, created_by
-- ) values (
--   'b8200000-0000-4000-8000-000000000001',
--   'b8100000-0000-4000-8000-000000000001', 'owner', 'active',
--   'b8100000-0000-4000-8000-000000000001'
-- );
-- insert into public.branches (
--   id, shop_id, name, is_primary, is_active, created_by
-- ) values (
--   'b8300000-0000-4000-8000-000000000001',
--   'b8200000-0000-4000-8000-000000000001', 'Legacy Main', true, true,
--   'b8100000-0000-4000-8000-000000000001'
-- );
-- insert into public.shop_settings (
--   shop_id, operating_currency_code, configured_by, updated_by
-- ) values (
--   'b8200000-0000-4000-8000-000000000001', 'USD',
--   'b8100000-0000-4000-8000-000000000001',
--   'b8100000-0000-4000-8000-000000000001'
-- );
-- insert into public.products (
--   id, shop_id, product_type, tracking_mode, name, created_by, updated_by
-- ) values (
--   'b8400000-0000-4000-8000-000000000001',
--   'b8200000-0000-4000-8000-000000000001', 'accessory', 'quantity',
--   'Fictional Legacy Price Product', 'b8100000-0000-4000-8000-000000000001',
--   'b8100000-0000-4000-8000-000000000001'
-- );
-- insert into public.product_variants (
--   id, shop_id, product_id, colour, created_by, updated_by
-- ) values (
--   'b8500000-0000-4000-8000-000000000001',
--   'b8200000-0000-4000-8000-000000000001',
--   'b8400000-0000-4000-8000-000000000001', 'Blue',
--   'b8100000-0000-4000-8000-000000000001',
--   'b8100000-0000-4000-8000-000000000001'
-- );
-- insert into public.branch_variant_prices (
--   id, shop_id, branch_id, variant_id, price_currency_code,
--   selling_price_shop, created_at, created_by, updated_at, updated_by
-- ) values (
--   'b8600000-0000-4000-8000-000000000001',
--   'b8200000-0000-4000-8000-000000000001',
--   'b8300000-0000-4000-8000-000000000001',
--   'b8500000-0000-4000-8000-000000000001', 'USD', 45.67,
--   '2026-01-02 03:04:05+00', 'b8100000-0000-4000-8000-000000000001',
--   '2026-02-03 04:05:06+00', 'b8100000-0000-4000-8000-000000000001'
-- );
-- commit;
-- Apply only migration 202611220002 in the disposable project, then run the
-- following exact post-migration assertion block before this pgTAP suite. It
-- verifies the pre-existing row and its baseline event without treating
-- migration-time state as an executed test. Do not report it as passed until
-- the fixture is actually run.
--
-- do $verify$
-- declare
--   price_row public.branch_variant_prices%rowtype;
--   event_row public.branch_variant_price_events%rowtype;
--   event_count bigint;
-- begin
--   select price.* into price_row
--   from public.branch_variant_prices as price
--   where price.id = 'b8600000-0000-4000-8000-000000000001';
--
--   if not found
--     or price_row.shop_id is distinct from
--       'b8200000-0000-4000-8000-000000000001'::uuid
--     or price_row.branch_id is distinct from
--       'b8300000-0000-4000-8000-000000000001'::uuid
--     or price_row.variant_id is distinct from
--       'b8500000-0000-4000-8000-000000000001'::uuid
--     or price_row.selling_price_shop is distinct from 45.67::numeric
--     or price_row.price_currency_code is distinct from 'USD'::char(3)
--     or price_row.created_at is distinct from
--       '2026-01-02 03:04:05+00'::timestamptz
--     or price_row.created_by is distinct from
--       'b8100000-0000-4000-8000-000000000001'::uuid
--     or price_row.updated_at is distinct from
--       '2026-02-03 04:05:06+00'::timestamptz
--     or price_row.updated_by is distinct from
--       'b8100000-0000-4000-8000-000000000001'::uuid
--     or price_row.version is distinct from 1::bigint
--   then
--     raise exception 'The populated branch price row was changed or not initialized at version 1.';
--   end if;
--
--   select count(*) into event_count
--   from public.branch_variant_price_events as event
--   where event.price_id = price_row.id;
--   if event_count is distinct from 1::bigint then
--     raise exception
--       'Expected exactly one baseline event for the pre-existing price; found %.',
--       event_count;
--   end if;
--
--   select event.* into event_row
--   from public.branch_variant_price_events as event
--   where event.price_id = price_row.id;
--   if event_row.event_type is distinct from 'baseline'
--     or event_row.previous_price is not null
--     or event_row.previous_currency_code is not null
--     or event_row.new_price is distinct from 45.67::numeric
--     or event_row.new_currency_code is distinct from 'USD'::char(3)
--     or event_row.actor_id is not null
--     or event_row.change_reason is not null
--     or event_row.operation_id is not null
--     or event_row.version_before is not null
--     or event_row.version_after is distinct from 1::bigint
--     or event_row.baseline_source_created_at is distinct from
--       '2026-01-02 03:04:05+00'::timestamptz
--     or event_row.baseline_source_created_by is distinct from
--       'b8100000-0000-4000-8000-000000000001'::uuid
--     or event_row.baseline_source_updated_at is distinct from
--       '2026-02-03 04:05:06+00'::timestamptz
--     or event_row.baseline_source_updated_by is distinct from
--       'b8100000-0000-4000-8000-000000000001'::uuid
--     or event_row.captured_at <= event_row.baseline_source_updated_at
--   then
--     raise exception
--       'The baseline event is missing source evidence, invents a prior change, or has an invalid capture time.';
--   end if;
-- end
-- $verify$;
create extension if not exists pgtap with schema extensions;
select no_plan();

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e7100000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'price-owner-a@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e7100000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'price-manager-a@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e7100000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'price-staff-a@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e7100000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'price-suspended-a@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e7100000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'price-owner-b@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
  ('e7100000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'price-owner-c@example.test', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

insert into public.shops (id, name, created_by) values
  ('e7200000-0000-4000-8000-000000000001', 'Fictional Price Shop A', 'e7100000-0000-4000-8000-000000000001'),
  ('e7200000-0000-4000-8000-000000000002', 'Fictional Price Shop B', 'e7100000-0000-4000-8000-000000000005'),
  ('e7200000-0000-4000-8000-000000000003', 'Fictional Price Shop C', 'e7100000-0000-4000-8000-000000000006');

insert into public.shop_memberships (shop_id, user_id, role, status, created_by) values
  ('e7200000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000001', 'owner', 'active', 'e7100000-0000-4000-8000-000000000001'),
  ('e7200000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000002', 'manager', 'active', 'e7100000-0000-4000-8000-000000000001'),
  ('e7200000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000003', 'inventory_staff', 'active', 'e7100000-0000-4000-8000-000000000001'),
  ('e7200000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000004', 'manager', 'suspended', 'e7100000-0000-4000-8000-000000000001'),
  ('e7200000-0000-4000-8000-000000000002', 'e7100000-0000-4000-8000-000000000005', 'owner', 'active', 'e7100000-0000-4000-8000-000000000005'),
  ('e7200000-0000-4000-8000-000000000003', 'e7100000-0000-4000-8000-000000000006', 'owner', 'active', 'e7100000-0000-4000-8000-000000000006');

insert into public.branches (id, shop_id, name, is_primary, is_active, created_by) values
  ('e7300000-0000-4000-8000-000000000001', 'e7200000-0000-4000-8000-000000000001', 'A Main', true, true, 'e7100000-0000-4000-8000-000000000001'),
  ('e7300000-0000-4000-8000-000000000002', 'e7200000-0000-4000-8000-000000000001', 'A East', false, true, 'e7100000-0000-4000-8000-000000000001'),
  ('e7300000-0000-4000-8000-000000000003', 'e7200000-0000-4000-8000-000000000001', 'A Inactive', false, false, 'e7100000-0000-4000-8000-000000000001'),
  ('e7300000-0000-4000-8000-000000000004', 'e7200000-0000-4000-8000-000000000002', 'B Main', true, true, 'e7100000-0000-4000-8000-000000000005'),
  ('e7300000-0000-4000-8000-000000000005', 'e7200000-0000-4000-8000-000000000003', 'C Main', true, true, 'e7100000-0000-4000-8000-000000000006');

insert into public.branch_memberships (shop_id, branch_id, user_id, created_by) values
  ('e7200000-0000-4000-8000-000000000001', 'e7300000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000002', 'e7100000-0000-4000-8000-000000000001'),
  ('e7200000-0000-4000-8000-000000000001', 'e7300000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000003', 'e7100000-0000-4000-8000-000000000001'),
  ('e7200000-0000-4000-8000-000000000001', 'e7300000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000004', 'e7100000-0000-4000-8000-000000000001');

-- Model a legacy assignment that predates the new evidence mechanism. Do not
-- backfill or infer historical authorization from this current row.
alter table public.branch_memberships
  disable trigger branch_memberships_price_access_history;
insert into public.branch_memberships (shop_id, branch_id, user_id, created_by)
values (
  'e7200000-0000-4000-8000-000000000001',
  'e7300000-0000-4000-8000-000000000003',
  'e7100000-0000-4000-8000-000000000002',
  'e7100000-0000-4000-8000-000000000001'
);
alter table public.branch_memberships
  enable trigger branch_memberships_price_access_history;

insert into public.shop_settings (
  shop_id, operating_currency_code, configured_by, updated_by
) values
  ('e7200000-0000-4000-8000-000000000001', 'USD', 'e7100000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000001'),
  ('e7200000-0000-4000-8000-000000000002', 'KWD', 'e7100000-0000-4000-8000-000000000005', 'e7100000-0000-4000-8000-000000000005'),
  ('e7200000-0000-4000-8000-000000000003', 'JPY', 'e7100000-0000-4000-8000-000000000006', 'e7100000-0000-4000-8000-000000000006');

insert into public.products (
  id, shop_id, product_type, tracking_mode, name, created_by, updated_by
) values
  ('e7400000-0000-4000-8000-000000000001', 'e7200000-0000-4000-8000-000000000001', 'accessory', 'quantity', 'Fictional Price Accessory', 'e7100000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000001'),
  ('e7400000-0000-4000-8000-000000000002', 'e7200000-0000-4000-8000-000000000001', 'accessory', 'quantity', 'Fictional Archived Product', 'e7100000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000001'),
  ('e7400000-0000-4000-8000-000000000003', 'e7200000-0000-4000-8000-000000000002', 'accessory', 'quantity', 'Fictional KWD Accessory', 'e7100000-0000-4000-8000-000000000005', 'e7100000-0000-4000-8000-000000000005'),
  ('e7400000-0000-4000-8000-000000000004', 'e7200000-0000-4000-8000-000000000003', 'accessory', 'quantity', 'Fictional JPY Accessory', 'e7100000-0000-4000-8000-000000000006', 'e7100000-0000-4000-8000-000000000006'),
  ('e7400000-0000-4000-8000-000000000005', 'e7200000-0000-4000-8000-000000000001', 'smartphone', 'serialized', 'Fictional Serialized Device', 'e7100000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000001');

update public.products
set archived_at = now()
where id = 'e7400000-0000-4000-8000-000000000002';

insert into public.product_variants (
  id, shop_id, product_id, colour, created_by, updated_by, archived_at
) values
  ('e7500000-0000-4000-8000-000000000001', 'e7200000-0000-4000-8000-000000000001', 'e7400000-0000-4000-8000-000000000001', 'Blue', 'e7100000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000001', null),
  ('e7500000-0000-4000-8000-000000000002', 'e7200000-0000-4000-8000-000000000001', 'e7400000-0000-4000-8000-000000000001', 'Black', 'e7100000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000001', null),
  ('e7500000-0000-4000-8000-000000000003', 'e7200000-0000-4000-8000-000000000001', 'e7400000-0000-4000-8000-000000000001', 'Red', 'e7100000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000001', now()),
  ('e7500000-0000-4000-8000-000000000004', 'e7200000-0000-4000-8000-000000000001', 'e7400000-0000-4000-8000-000000000002', 'Silver', 'e7100000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000001', null),
  ('e7500000-0000-4000-8000-000000000005', 'e7200000-0000-4000-8000-000000000002', 'e7400000-0000-4000-8000-000000000003', 'Green', 'e7100000-0000-4000-8000-000000000005', 'e7100000-0000-4000-8000-000000000005', null),
  ('e7500000-0000-4000-8000-000000000006', 'e7200000-0000-4000-8000-000000000003', 'e7400000-0000-4000-8000-000000000004', 'White', 'e7100000-0000-4000-8000-000000000006', 'e7100000-0000-4000-8000-000000000006', null),
  ('e7500000-0000-4000-8000-000000000007', 'e7200000-0000-4000-8000-000000000001', 'e7400000-0000-4000-8000-000000000005', 'Black', 'e7100000-0000-4000-8000-000000000001', 'e7100000-0000-4000-8000-000000000001', null);

-- Owned quantity buckets prove archival blocks known-zero, unknown-cost, and
-- Pending-FX stock. Pending-FX has no available quantity but remains owned.
insert into public.inventory_balances (
  shop_id, branch_id, variant_id, valuation_status,
  valuation_currency_code, on_hand_qty, available_qty,
  carrying_value_shop, average_unit_cost_shop, updated_by
) values
  ('e7200000-0000-4000-8000-000000000001', 'e7300000-0000-4000-8000-000000000001', 'e7500000-0000-4000-8000-000000000001', 'known_cost', 'USD', 1, 1, 0, 0, 'e7100000-0000-4000-8000-000000000001'),
  ('e7200000-0000-4000-8000-000000000001', 'e7300000-0000-4000-8000-000000000001', 'e7500000-0000-4000-8000-000000000001', 'unknown_cost', 'USD', 2, 2, null, null, 'e7100000-0000-4000-8000-000000000001'),
  ('e7200000-0000-4000-8000-000000000001', 'e7300000-0000-4000-8000-000000000001', 'e7500000-0000-4000-8000-000000000002', 'pending_fx', 'USD', 1, 0, null, null, 'e7100000-0000-4000-8000-000000000001');

insert into public.serialized_inventory (
  id, shop_id, branch_id, variant_id, availability_status,
  valuation_status, valuation_currency_code, unit_cost_shop,
  created_by, updated_by
) values (
  'e7700000-0000-4000-8000-000000000001',
  'e7200000-0000-4000-8000-000000000001',
  'e7300000-0000-4000-8000-000000000001',
  'e7500000-0000-4000-8000-000000000007',
  'available', 'unknown_cost', 'USD', null,
  'e7100000-0000-4000-8000-000000000001',
  'e7100000-0000-4000-8000-000000000001'
);

-- Owner creates the first current price. The price currency is taken from the
-- shop configuration; callers cannot supply an alternative currency.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000001', true);

select lives_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000001',
    'e7500000-0000-4000-8000-000000000001',
    12.34, 0, 'Initial fictional branch price', 'price-owner-create-01'
  ) $$,
  'active Owner creates a branch price'
);

select is(
  (select price.selling_price_shop
   from public.branch_variant_prices as price
   where price.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and price.branch_id = 'e7300000-0000-4000-8000-000000000001'
     and price.variant_id = 'e7500000-0000-4000-8000-000000000001'),
  12.34::numeric,
  'the stored amount is unchanged and denominated in shop currency'
);
select is(
  (select price.version
   from public.branch_variant_prices as price
   where price.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and price.branch_id = 'e7300000-0000-4000-8000-000000000001'
     and price.variant_id = 'e7500000-0000-4000-8000-000000000001'),
  1::bigint,
  'a new price starts at version one'
);
select is(
  (select price.price_currency_code::text
   from public.branch_variant_prices as price
   where price.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and price.branch_id = 'e7300000-0000-4000-8000-000000000001'
     and price.variant_id = 'e7500000-0000-4000-8000-000000000001'),
  'USD',
  'the shop operating currency is stored instead of a caller-selected currency'
);

select is(
  (select count(*)::integer
   from public.branch_variant_price_events as event
   where event.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and event.branch_id = 'e7300000-0000-4000-8000-000000000001'
     and event.variant_id = 'e7500000-0000-4000-8000-000000000001'
     and event.event_type = 'price_set'
     and event.previous_price is null
     and event.previous_currency_code is null
     and event.new_price = 12.34
     and event.new_currency_code = 'USD'
     and event.actor_id = 'e7100000-0000-4000-8000-000000000001'
     and event.change_reason = 'Initial fictional branch price'
     and event.version_before = 0
     and event.version_after = 1),
  1,
  'the initial event records actor, reason, currency, and version without inventing a previous price'
);

select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000002',
    'e7500000-0000-4000-8000-000000000001',
    14.00, 1, 'Incorrect first-price version', 'price-create-wrong-version'
  ) $$,
  '40001', null,
  'a missing branch price cannot be created with a nonzero expected version'
);

select is(
  (select replay.replayed
   from public.set_branch_variant_price(
     'e7200000-0000-4000-8000-000000000001',
     'e7300000-0000-4000-8000-000000000001',
     'e7500000-0000-4000-8000-000000000001',
     12.34, 0, 'Initial fictional branch price', 'price-owner-create-01'
   ) as replay),
  true,
  'an identical retry returns the original result as a replay'
);
select is(
  (select replay.price_id
   from public.set_branch_variant_price(
     'e7200000-0000-4000-8000-000000000001',
     'e7300000-0000-4000-8000-000000000001',
     'e7500000-0000-4000-8000-000000000001',
     12.34, 0, 'Initial fictional branch price', 'price-owner-create-01'
   ) as replay),
  (select price.id
   from public.branch_variant_prices as price
   where price.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and price.branch_id = 'e7300000-0000-4000-8000-000000000001'
     and price.variant_id = 'e7500000-0000-4000-8000-000000000001'),
  'an identical retry returns the original price ID'
);
select is(
  (select replay.version
   from public.set_branch_variant_price(
     'e7200000-0000-4000-8000-000000000001',
     'e7300000-0000-4000-8000-000000000001',
     'e7500000-0000-4000-8000-000000000001',
     12.34, 0, 'Initial fictional branch price', 'price-owner-create-01'
   ) as replay),
  1::bigint,
  'an identical retry returns the original version'
);
select is(
  (select count(*)::integer
   from public.branch_variant_price_events as event
   where event.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and event.branch_id = 'e7300000-0000-4000-8000-000000000001'
     and event.variant_id = 'e7500000-0000-4000-8000-000000000001'
     and event.event_type = 'price_set'),
  1,
  'an idempotent retry does not create a second event'
);
reset role;
select is(
  (select count(*)::integer
   from public.branch_variant_price_operations as operation
   where operation.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and operation.actor_id = 'e7100000-0000-4000-8000-000000000001'
     and operation.idempotency_key = 'price-owner-create-01'),
  1,
  'repeated identical retries do not create another operation'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000001', true);

select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000001',
    'e7500000-0000-4000-8000-000000000001',
    13.00, 0, 'Conflicting fictional price', 'price-owner-create-01'
  ) $$,
  '22023', null,
  'reusing a key with a changed price or reason is rejected'
);
select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000001',
    'e7500000-0000-4000-8000-000000000001',
    12.34, 1, 'Initial fictional branch price', 'price-owner-create-01'
  ) $$,
  '22023', null,
  'reusing a key with a changed expected version is rejected'
);
select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000001',
    'e7500000-0000-4000-8000-000000000001',
    12.34, 0, 'Changed reason', 'price-owner-create-01'
  ) $$,
  '22023', null,
  'reusing a key with a changed reason is rejected'
);

select lives_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000001',
    'e7500000-0000-4000-8000-000000000001',
    0, 1, 'Fictional zero-price promotion', 'price-owner-update-01'
  ) $$,
  'an explicit zero selling price is accepted with a reason'
);
select is(
  (select price.version
   from public.branch_variant_prices as price
   where price.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and price.branch_id = 'e7300000-0000-4000-8000-000000000001'
     and price.variant_id = 'e7500000-0000-4000-8000-000000000001'),
  2::bigint,
  'a successful update increments the version'
);
select is(
  (select event.previous_price
   from public.branch_variant_price_events as event
   where event.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and event.branch_id = 'e7300000-0000-4000-8000-000000000001'
     and event.variant_id = 'e7500000-0000-4000-8000-000000000001'
     and event.event_type = 'price_updated'),
  12.34::numeric,
  'the update event records the actual previous price'
);
select is(
  (select event.version_before
   from public.branch_variant_price_events as event
   where event.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and event.branch_id = 'e7300000-0000-4000-8000-000000000001'
     and event.variant_id = 'e7500000-0000-4000-8000-000000000001'
     and event.event_type = 'price_updated'),
  1::bigint,
  'the update event records the previous version'
);

select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000001',
    'e7500000-0000-4000-8000-000000000001',
    -0.01, 2, 'Negative is invalid', 'price-negative-01'
  ) $$,
  '22023', null,
  'negative prices are rejected'
);
select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000001',
    'e7500000-0000-4000-8000-000000000001',
    1.001, 2, 'Too precise for USD', 'price-usd-precision-01'
  ) $$,
  '22023', null,
  'USD precision beyond two minor units is rejected before storage'
);
select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000001',
    'e7500000-0000-4000-8000-000000000001',
    1.000000001, 2, 'Subscale precision is invalid', 'price-subscale-precision'
  ) $$,
  '22023', null,
  'precision beyond numeric(38,8) storage scale is rejected before column rounding'
);
select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000001',
    'e7500000-0000-4000-8000-000000000001',
    'Infinity'::numeric, 2, 'Infinite is invalid', 'price-infinity-01'
  ) $$,
  '22023', null,
  'infinite prices are rejected'
);
select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000001',
    'e7500000-0000-4000-8000-000000000001',
    'NaN'::numeric, 2, 'NaN is invalid', 'price-nan-01'
  ) $$,
  '22023', null,
  'NaN prices are rejected'
);
select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000001',
    'e7500000-0000-4000-8000-000000000001',
    4.00, 1, 'Stale version attempt', 'price-stale-01'
  ) $$,
  '40001', null,
  'stale versions are rejected'
);
reset role;
select is(
  (select count(*)::integer
   from public.branch_variant_price_operations as operation
   where operation.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and operation.idempotency_key in (
       'price-create-wrong-version',
       'price-negative-01', 'price-usd-precision-01',
       'price-subscale-precision',
       'price-infinity-01', 'price-nan-01', 'price-stale-01'
     )),
  0,
  'failed requests leave no operation records'
);
set local role authenticated;
select is(
  (select count(*)::integer
   from public.branch_variant_price_events as event
   where event.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and event.variant_id = 'e7500000-0000-4000-8000-000000000001'),
  2,
  'failed requests leave no price events'
);

select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000001',
    'e7500000-0000-4000-8000-000000000001',
    1.00, 2, '   ', 'price-blank-reason'
  ) $$,
  '22023', null,
  'blank reasons are rejected'
);
select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000001',
    'e7500000-0000-4000-8000-000000000001',
    1.00, 2, 'Valid reason', 'short'
  ) $$,
  '22023', null,
  'short idempotency keys are rejected'
);

-- Manager is allowed only on the assigned active branch. An assignment alone
-- is insufficient for Inventory Staff or suspended members.
select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000002', true);
select lives_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000001',
    'e7500000-0000-4000-8000-000000000002',
    8.75, 0, 'Assigned Manager fictional price', 'price-manager-assigned'
  ) $$,
  'an active assigned Manager can set a branch price'
);
select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000002',
    'e7500000-0000-4000-8000-000000000001',
    9.00, 0, 'Unassigned branch attempt', 'price-manager-unassigned'
  ) $$,
  '42501', null,
  'a Manager cannot set a price for an unassigned branch'
);

select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000003', true);
select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000001',
    'e7500000-0000-4000-8000-000000000001',
    10.00, 2, 'Staff denied', 'price-staff-denied'
  ) $$,
  '42501', null,
  'assigned Inventory Staff cannot mutate branch prices'
);

select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000004', true);
select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000001',
    'e7500000-0000-4000-8000-000000000001',
    10.00, 2, 'Suspended denied', 'price-suspended-denied'
  ) $$,
  '42501', null,
  'suspended Managers cannot mutate prices despite a retained assignment row'
);

select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000004',
    'e7500000-0000-4000-8000-000000000001',
    10.00, 0, 'Cross-shop branch attempt', 'price-cross-shop-branch'
  ) $$,
  '42501', null,
  'cross-shop branch identifiers are rejected'
);
select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000003',
    'e7500000-0000-4000-8000-000000000001',
    10.00, 0, 'Inactive branch attempt', 'price-inactive-branch'
  ) $$,
  '42501', null,
  'inactive branches cannot receive prices'
);
select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000001',
    'e7500000-0000-4000-8000-000000000003',
    3.00, 0, 'Archived variant attempt', 'price-archived-variant'
  ) $$,
  '22023', null,
  'archived variants cannot receive a new or updated price'
);
select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000001',
    'e7500000-0000-4000-8000-000000000004',
    3.00, 0, 'Archived product attempt', 'price-archived-product'
  ) $$,
  '22023', null,
  'variants of archived products cannot receive a price'
);

-- RLS exposes current prices and history only on branches accessible to the
-- current active member. Managers do not inherit Owner-wide branch visibility.
select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000002',
    'e7500000-0000-4000-8000-000000000001',
    14.00, 0, 'Owner East branch price', 'price-owner-east'
  ) $$,
  'Owner can set price in another active branch of the shop'
);
select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000002', true);
select is(
  (select count(*)::integer from public.branch_variant_prices as price
   where price.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and price.branch_id = 'e7300000-0000-4000-8000-000000000002'),
  0,
  'Manager cannot read a price for an unassigned branch'
);
select is(
  (select count(*)::integer from public.branch_variant_price_events as event
   where event.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and event.branch_id = 'e7300000-0000-4000-8000-000000000002'),
  0,
  'Manager cannot read price history for an unassigned branch'
);
select is(
  (select count(*)::integer from public.branch_variant_prices as price
   where price.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and price.branch_id = 'e7300000-0000-4000-8000-000000000001'),
  2,
  'Manager can read current prices in the assigned branch'
);

select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000003', true);
select is(
  (select count(*)::integer from public.branch_variant_price_events as event
   where event.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and event.branch_id = 'e7300000-0000-4000-8000-000000000001'),
  3,
  'assigned active staff can read branch price history'
);

select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000004', true);
select is(
  (select count(*)::integer from public.branch_variant_prices as price
   where price.shop_id = 'e7200000-0000-4000-8000-000000000001'),
  0,
  'suspended members cannot read previously assigned prices'
);

select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000005', true);
select is(
  (select count(*)::integer from public.branch_variant_prices as price
   where price.shop_id = 'e7200000-0000-4000-8000-000000000001'),
  0,
  'price rows remain isolated across shops'
);

-- Currency precision is based on the configured shop currency, not a caller
-- parameter or supplier invoice currency.
select lives_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000002',
    'e7300000-0000-4000-8000-000000000004',
    'e7500000-0000-4000-8000-000000000005',
    1.234, 0, 'Fictional KWD price', 'price-kwd-valid'
  ) $$,
  'KWD price may use three minor units'
);
select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000002',
    'e7300000-0000-4000-8000-000000000004',
    'e7500000-0000-4000-8000-000000000005',
    1.2345, 1, 'Over precise KWD price', 'price-kwd-invalid'
  ) $$,
  '22023', null,
  'KWD precision beyond three minor units is rejected'
);
select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000006', true);
select lives_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000003',
    'e7300000-0000-4000-8000-000000000005',
    'e7500000-0000-4000-8000-000000000006',
    1200, 0, 'Fictional JPY price', 'price-jpy-valid'
  ) $$,
  'JPY price with zero minor units is accepted'
);
select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000003',
    'e7300000-0000-4000-8000-000000000005',
    'e7500000-0000-4000-8000-000000000006',
    1200.5, 1, 'Fractional JPY price', 'price-jpy-invalid'
  ) $$,
  '22023', null,
  'JPY does not accept a fractional minor unit'
);

select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000005', true);
select throws_ok(
  $$ select public.configure_shop_operating_currency(
    'e7200000-0000-4000-8000-000000000002', 'USD'
  ) $$,
  '23503', null,
  'the existing composite currency foreign key prevents changing currency while prices exist'
);

-- A baseline event is a snapshot, not a user action or reconstructed price
-- change. This fixture models an existing row without claiming it predates
-- the migration; the migration's populated-upgrade behavior needs a separate
-- isolated pre-migration fixture before the migration is applied.
reset role;
insert into public.branch_variant_prices (
  id, shop_id, branch_id, variant_id, price_currency_code,
  selling_price_shop, created_at, created_by, updated_at, updated_by, version
) values (
  'e7600000-0000-4000-8000-000000000001',
  'e7200000-0000-4000-8000-000000000001',
  'e7300000-0000-4000-8000-000000000003',
  'e7500000-0000-4000-8000-000000000002',
  'USD', 4.20, now() - interval '1 day', 'e7100000-0000-4000-8000-000000000001',
  now() - interval '1 hour', 'e7100000-0000-4000-8000-000000000001', 1
);
insert into public.branch_variant_price_events (
  shop_id, branch_id, variant_id, price_id, event_type,
  previous_price, previous_currency_code, new_price, new_currency_code,
  actor_id, captured_at, change_reason, operation_id,
  version_before, version_after,
  baseline_source_created_at, baseline_source_created_by,
  baseline_source_updated_at, baseline_source_updated_by
) values (
  'e7200000-0000-4000-8000-000000000001',
  'e7300000-0000-4000-8000-000000000003',
  'e7500000-0000-4000-8000-000000000002',
  'e7600000-0000-4000-8000-000000000001', 'baseline',
  null, null, 4.20, 'USD', null, clock_timestamp(), null, null,
  null, 1,
  now() - interval '1 day', 'e7100000-0000-4000-8000-000000000001',
  now() - interval '1 hour', 'e7100000-0000-4000-8000-000000000001'
);
select is(
  (select count(*)::integer
   from public.branch_variant_price_events as event
   where event.price_id = 'e7600000-0000-4000-8000-000000000001'
     and event.event_type = 'baseline'
     and event.previous_price is null
     and event.previous_currency_code is null
     and event.actor_id is null
     and event.change_reason is null
     and event.operation_id is null
     and event.new_price = 4.20
     and event.new_currency_code = 'USD'
     and event.captured_at > event.baseline_source_updated_at),
  1,
  'baseline evidence preserves current price and source timestamps without inventing a change'
);

-- Direct client writes are denied by ACLs. Append-only triggers provide a
-- second guard for trusted database-level callers that are not table owners.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000001', true);
select throws_ok(
  $$ insert into public.branch_variant_prices (
       shop_id, branch_id, variant_id, price_currency_code,
       selling_price_shop, created_by, updated_by
     ) values (
       'e7200000-0000-4000-8000-000000000001',
       'e7300000-0000-4000-8000-000000000001',
       'e7500000-0000-4000-8000-000000000002',
       'USD', 2.00, 'e7100000-0000-4000-8000-000000000001',
       'e7100000-0000-4000-8000-000000000001'
     ) $$,
  '42501', null,
  'authenticated clients cannot directly insert current prices'
);
select throws_ok(
  $$ update public.branch_variant_prices
     set selling_price_shop = 99.00
     where shop_id = 'e7200000-0000-4000-8000-000000000001' $$,
  '42501', null,
  'authenticated clients cannot directly update current prices'
);
select throws_ok(
  $$ delete from public.branch_variant_prices
     where shop_id = 'e7200000-0000-4000-8000-000000000001' $$,
  '42501', null,
  'authenticated clients cannot directly delete current prices'
);
select throws_ok(
  $$ truncate table public.branch_variant_prices $$,
  '42501', null,
  'authenticated clients cannot truncate current prices'
);
select throws_ok(
  $$ insert into public.branch_variant_price_events (
       shop_id, branch_id, variant_id, price_id, event_type,
       new_price, new_currency_code, version_after
     ) values (
       'e7200000-0000-4000-8000-000000000001',
       'e7300000-0000-4000-8000-000000000001',
       'e7500000-0000-4000-8000-000000000001',
       (select price.id from public.branch_variant_prices as price
        where price.shop_id = 'e7200000-0000-4000-8000-000000000001'
          and price.branch_id = 'e7300000-0000-4000-8000-000000000001'
          and price.variant_id = 'e7500000-0000-4000-8000-000000000001'),
       'price_set', 1.00, 'USD', 1
     ) $$,
  '42501', null,
  'authenticated clients cannot insert price history directly'
);
select throws_ok(
  $$ update public.branch_variant_price_events
     set change_reason = 'tampered'
     where shop_id = 'e7200000-0000-4000-8000-000000000001' $$,
  '42501', null,
  'authenticated clients cannot update price history'
);
select throws_ok(
  $$ delete from public.branch_variant_price_events
     where shop_id = 'e7200000-0000-4000-8000-000000000001' $$,
  '42501', null,
  'authenticated clients cannot delete price history'
);
select throws_ok(
  $$ truncate table public.branch_variant_price_events $$,
  '42501', null,
  'authenticated clients cannot truncate price history'
);
select throws_ok(
  $$ insert into public.branch_variant_price_operations (
       shop_id, branch_id, variant_id, actor_id, idempotency_key,
       operation_type, request_payload, result_price_id,
       result_event_id, result_version
     ) values (
       'e7200000-0000-4000-8000-000000000001',
       'e7300000-0000-4000-8000-000000000001',
       'e7500000-0000-4000-8000-000000000001',
       'e7100000-0000-4000-8000-000000000001',
       'price-forged-operation', 'set_branch_variant_price', '{}'::jsonb,
       'e7600000-0000-4000-8000-000000000001', gen_random_uuid(), 1
     ) $$,
  '42501', null,
  'authenticated clients cannot insert idempotency operations directly'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.set_branch_variant_price(uuid,uuid,uuid,numeric,bigint,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.set_branch_variant_price(uuid,uuid,uuid,numeric,bigint,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.set_branch_variant_price(uuid,uuid,uuid,numeric,bigint,text,text)',
    'EXECUTE'
  ),
  'only authenticated callers can execute the pricing RPC'
);
select ok(
  has_function_privilege(
    'authenticated',
    'private.can_read_inactive_branch_price_event(uuid,uuid,timestamptz)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'private.can_read_inactive_branch_price_event(uuid,uuid,timestamptz)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'private.can_read_inactive_branch_price_event(uuid,uuid,timestamptz)',
    'EXECUTE'
  ),
  'only authenticated policy evaluation can call the private history authorization helper'
);
select ok(
  not has_table_privilege('anon', 'public.branch_variant_price_events', 'INSERT')
  and not has_table_privilege('authenticated', 'public.branch_variant_price_operations', 'SELECT')
  and not has_table_privilege('authenticated', 'public.branch_variant_price_operations', 'INSERT')
  and not has_table_privilege('authenticated', 'public.branch_variant_price_operations', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.branch_variant_price_operations', 'DELETE')
  and not has_table_privilege('authenticated', 'public.branch_variant_price_operations', 'TRUNCATE')
  and not has_table_privilege('service_role', 'public.branch_variant_price_operations', 'SELECT')
  and not has_table_privilege('authenticated', 'private.branch_membership_price_access_events', 'SELECT')
  and not has_table_privilege('authenticated', 'private.branch_membership_price_access_events', 'INSERT')
  and not has_table_privilege('authenticated', 'private.branch_membership_price_access_events', 'UPDATE')
  and not has_table_privilege('authenticated', 'private.branch_membership_price_access_events', 'DELETE')
  and not has_table_privilege('authenticated', 'private.branch_membership_price_access_events', 'TRUNCATE')
  and not has_table_privilege('anon', 'private.branch_membership_price_access_events', 'SELECT')
  and not has_table_privilege('anon', 'private.branch_membership_price_access_events', 'INSERT')
  and not has_table_privilege('service_role', 'private.branch_membership_price_access_events', 'SELECT')
  and not has_table_privilege('service_role', 'private.branch_membership_price_access_events', 'INSERT')
  and not has_table_privilege('service_role', 'private.branch_membership_price_access_events', 'UPDATE')
  and not has_table_privilege('service_role', 'private.branch_membership_price_access_events', 'DELETE')
  and not has_table_privilege('service_role', 'private.branch_membership_price_access_events', 'TRUNCATE')
  and not has_table_privilege('authenticated', 'public.branch_variant_price_events', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.branch_variant_price_events', 'DELETE')
  and not has_table_privilege('authenticated', 'public.branch_variant_price_events', 'TRUNCATE')
  and not has_table_privilege('service_role', 'public.branch_variant_prices', 'INSERT')
  and not has_table_privilege('service_role', 'public.branch_variant_prices', 'UPDATE')
  and not has_table_privilege('service_role', 'public.branch_variant_prices', 'DELETE')
  and not has_table_privilege('service_role', 'public.branch_variant_prices', 'TRUNCATE')
  and not has_table_privilege('service_role', 'public.branch_variant_price_events', 'INSERT')
  and not has_table_privilege('service_role', 'public.branch_variant_price_events', 'UPDATE')
  and not has_table_privilege('service_role', 'public.branch_variant_price_events', 'DELETE')
  and not has_table_privilege('service_role', 'public.branch_variant_price_events', 'TRUNCATE')
  and not has_table_privilege('service_role', 'public.branch_variant_price_operations', 'INSERT')
  and not has_table_privilege('service_role', 'public.branch_variant_price_operations', 'UPDATE')
  and not has_table_privilege('service_role', 'public.branch_variant_price_operations', 'DELETE')
  and not has_table_privilege('service_role', 'public.branch_variant_price_operations', 'TRUNCATE'),
  'restricted roles have no direct price-history or price-write privileges'
);
select ok(
  (select relrowsecurity from pg_catalog.pg_class where oid = 'public.branch_variant_price_events'::regclass)
  and (select relrowsecurity from pg_catalog.pg_class where oid = 'public.branch_variant_price_operations'::regclass),
  'new price audit tables have row-level security enabled'
);
select ok(
  (select relrowsecurity
   from pg_catalog.pg_class
   where oid = 'private.branch_membership_price_access_events'::regclass),
  'private branch assignment evidence has row-level security enabled'
);
select ok(
  (select count(*) = 6
     and bool_and(
       procedure.prosecdef
       and coalesce(procedure.proconfig @> array['search_path=""']::text[], false)
     )
   from pg_catalog.pg_proc as procedure
   where procedure.oid = any(array[
     'public.set_branch_variant_price(uuid,uuid,uuid,numeric,bigint,text,text)'::regprocedure,
     'private.assert_branch_price_editor(uuid,uuid)'::regprocedure,
     'private.can_read_inactive_branch_price_event(uuid,uuid,timestamptz)'::regprocedure,
     'private.record_branch_membership_price_access_event()'::regprocedure,
     'public.archive_product(uuid,uuid,bigint,text)'::regprocedure,
     'public.archive_product_variant(uuid,uuid,bigint,text)'::regprocedure
   ]::oid[])),
  'pricing, inactive-history, and archival SECURITY DEFINER routines use an empty search_path'
);

-- Stock-aware archival uses live balance and serialized ownership state, not
-- old receipts or movements. All failures must roll back catalog operations.
select ok(
  strpos(
    lower(pg_get_functiondef(
      'public.archive_product(uuid,uuid,bigint,text)'::regprocedure
    )),
    'lock table public.products in access exclusive mode'
  ) > 0
  and strpos(
    lower(pg_get_functiondef(
      'public.archive_product(uuid,uuid,bigint,text)'::regprocedure
    )),
    'lock table public.products in access exclusive mode'
  ) < strpos(
    lower(pg_get_functiondef(
      'public.archive_product(uuid,uuid,bigint,text)'::regprocedure
    )),
    'for update'
  )
  and strpos(
    lower(pg_get_functiondef(
      'public.archive_product_variant(uuid,uuid,bigint,text)'::regprocedure
    )),
    'lock table public.products in access exclusive mode'
  ) > 0
  and strpos(
    lower(pg_get_functiondef(
      'public.archive_product_variant(uuid,uuid,bigint,text)'::regprocedure
    )),
    'lock table public.products in access exclusive mode'
  ) < strpos(
    lower(pg_get_functiondef(
      'public.archive_product_variant(uuid,uuid,bigint,text)'::regprocedure
    )),
    'for update'
  ),
  'both stock-aware archival RPCs acquire the product table lock before row locks'
);
select throws_ok(
  $$ select public.archive_product(
       'e7200000-0000-4000-8000-000000000001',
       'e7400000-0000-4000-8000-000000000001',
       (select product.catalog_version from public.products as product
        where product.shop_id = 'e7200000-0000-4000-8000-000000000001'
          and product.id = 'e7400000-0000-4000-8000-000000000001'),
       'archive-product-with-known-unknown-stock'
     ) $$,
  '23514', null,
  'a product with known-zero and unknown-cost quantity stock cannot be archived'
);
select throws_ok(
  $$ select public.archive_product_variant(
       'e7200000-0000-4000-8000-000000000001',
       'e7500000-0000-4000-8000-000000000001',
       (select variant.catalog_version from public.product_variants as variant
        where variant.shop_id = 'e7200000-0000-4000-8000-000000000001'
          and variant.id = 'e7500000-0000-4000-8000-000000000001'),
       'archive-variant-with-known-unknown-stock'
     ) $$,
  '23514', null,
  'a variant with known-zero and unknown-cost stock cannot be archived'
);
select throws_ok(
  $$ select public.archive_product_variant(
       'e7200000-0000-4000-8000-000000000001',
       'e7500000-0000-4000-8000-000000000002',
       (select variant.catalog_version from public.product_variants as variant
        where variant.shop_id = 'e7200000-0000-4000-8000-000000000001'
          and variant.id = 'e7500000-0000-4000-8000-000000000002'),
       'archive-variant-with-pending-fx-stock'
     ) $$,
  '23514', null,
  'a variant with unavailable Pending-FX stock cannot be archived'
);
select throws_ok(
  $$ select public.archive_product_variant(
       'e7200000-0000-4000-8000-000000000001',
       'e7500000-0000-4000-8000-000000000007',
       (select variant.catalog_version from public.product_variants as variant
        where variant.shop_id = 'e7200000-0000-4000-8000-000000000001'
          and variant.id = 'e7500000-0000-4000-8000-000000000007'),
       'archive-variant-with-serialized-stock'
     ) $$,
  '23514', null,
  'a variant with an owned serialized device cannot be archived'
);
select throws_ok(
  $$ select public.archive_product(
       'e7200000-0000-4000-8000-000000000001',
       'e7400000-0000-4000-8000-000000000005',
       (select product.catalog_version from public.products as product
        where product.shop_id = 'e7200000-0000-4000-8000-000000000001'
          and product.id = 'e7400000-0000-4000-8000-000000000005'),
       'archive-product-with-serialized-stock'
     ) $$,
  '23514', null,
  'a product with an owned serialized device cannot be archived'
);

reset role;
select ok(
  not exists (
    select 1 from public.products as product
    where product.shop_id = 'e7200000-0000-4000-8000-000000000001'
      and product.id in (
        'e7400000-0000-4000-8000-000000000001',
        'e7400000-0000-4000-8000-000000000005'
      )
      and product.archived_at is not null
  )
  and not exists (
    select 1 from public.product_variants as variant
    where variant.shop_id = 'e7200000-0000-4000-8000-000000000001'
      and variant.id in (
        'e7500000-0000-4000-8000-000000000001',
        'e7500000-0000-4000-8000-000000000002',
        'e7500000-0000-4000-8000-000000000007'
      )
      and variant.archived_at is not null
  ),
  'failed stock-aware archival leaves catalog rows active'
);
select is(
  (select count(*)::integer
   from public.catalog_operations as operation
   where operation.idempotency_key in (
     'archive-product-with-known-unknown-stock',
     'archive-variant-with-known-unknown-stock',
     'archive-variant-with-pending-fx-stock',
     'archive-variant-with-serialized-stock',
     'archive-product-with-serialized-stock'
   )),
  0,
  'failed stock-aware archival leaves no operation records'
);
select is(
  (select count(*)::integer
   from public.product_catalog_events as event
   where event.event_type in ('product_archived', 'variant_archived')
     and event.product_id in (
       'e7400000-0000-4000-8000-000000000001',
       'e7400000-0000-4000-8000-000000000005'
     )),
  0,
  'failed stock-aware archival leaves no audit events'
);

-- A zero-stock product can be archived. Its original price operation remains
-- replayable after both the variant and product are archived.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000006', true);
select lives_ok(
  $$ select public.archive_product_variant(
       'e7200000-0000-4000-8000-000000000003',
       'e7500000-0000-4000-8000-000000000006',
       (select variant.catalog_version from public.product_variants as variant
        where variant.shop_id = 'e7200000-0000-4000-8000-000000000003'
          and variant.id = 'e7500000-0000-4000-8000-000000000006'),
       'archive-zero-stock-variant'
     ) $$,
  'a zero-stock variant can be archived'
);
select lives_ok(
  $$ select public.archive_product(
       'e7200000-0000-4000-8000-000000000003',
       'e7400000-0000-4000-8000-000000000004',
       (select product.catalog_version from public.products as product
        where product.shop_id = 'e7200000-0000-4000-8000-000000000003'
          and product.id = 'e7400000-0000-4000-8000-000000000004'),
       'archive-zero-stock-product'
     ) $$,
  'a zero-stock product can be archived after its variant'
);
select is(
  (select replay.replayed
   from public.set_branch_variant_price(
     'e7200000-0000-4000-8000-000000000003',
     'e7300000-0000-4000-8000-000000000005',
     'e7500000-0000-4000-8000-000000000006',
     1200, 0, 'Fictional JPY price', 'price-jpy-valid'
   ) as replay),
  true,
  'a completed price request replays after variant and product archival'
);
select is(
  (select replay.price_id
   from public.set_branch_variant_price(
     'e7200000-0000-4000-8000-000000000003',
     'e7300000-0000-4000-8000-000000000005',
     'e7500000-0000-4000-8000-000000000006',
     1200, 0, 'Fictional JPY price', 'price-jpy-valid'
   ) as replay),
  (select price.id from public.branch_variant_prices as price
   where price.shop_id = 'e7200000-0000-4000-8000-000000000003'
     and price.branch_id = 'e7300000-0000-4000-8000-000000000005'
     and price.variant_id = 'e7500000-0000-4000-8000-000000000006'),
  'the post-archive replay returns the original price ID'
);
select is(
  (select replay.version
   from public.set_branch_variant_price(
     'e7200000-0000-4000-8000-000000000003',
     'e7300000-0000-4000-8000-000000000005',
     'e7500000-0000-4000-8000-000000000006',
     1200, 0, 'Fictional JPY price', 'price-jpy-valid'
   ) as replay),
  1::bigint,
  'the post-archive replay returns the original version'
);
select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000003',
    'e7300000-0000-4000-8000-000000000005',
    'e7500000-0000-4000-8000-000000000006',
    1200, 1, 'Fictional JPY price', 'price-jpy-valid'
  ) $$,
  '22023', null,
  'post-archive retry with a changed expected version conflicts'
);
select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000003',
    'e7300000-0000-4000-8000-000000000005',
    'e7500000-0000-4000-8000-000000000006',
    1200, 0, 'Changed JPY reason', 'price-jpy-valid'
  ) $$,
  '22023', null,
  'post-archive retry with a changed reason conflicts'
);
select throws_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000003',
    'e7300000-0000-4000-8000-000000000005',
    'e7500000-0000-4000-8000-000000000006',
    1201, 0, 'Fictional JPY price', 'price-jpy-valid'
  ) $$,
  '22023', null,
  'post-archive retry with a changed price conflicts'
);
select is(
  (select count(*)::integer
   from public.branch_variant_price_events as event
   where event.shop_id = 'e7200000-0000-4000-8000-000000000003'
     and event.branch_id = 'e7300000-0000-4000-8000-000000000005'
     and event.variant_id = 'e7500000-0000-4000-8000-000000000006'
     and event.event_type = 'price_set'),
  1,
  'post-archive retries and conflicts create no additional price events'
);
reset role;
select is(
  (select count(*)::integer
   from public.branch_variant_price_operations as operation
   where operation.shop_id = 'e7200000-0000-4000-8000-000000000003'
     and operation.actor_id = 'e7100000-0000-4000-8000-000000000006'
     and operation.idempotency_key = 'price-jpy-valid'),
  1,
  'post-archive retries and conflicts create no additional operation'
);

-- Historical evidence is recorded transactionally by trusted assignment
-- mutations. A Manager must remain assigned, active, and have an uninterrupted
-- proven Manager assignment covering the price event timestamp.
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$ select public.owner_set_member_access(
       'e7200000-0000-4000-8000-000000000001',
       'e7100000-0000-4000-8000-000000000002',
       'manager',
       array[
         'e7300000-0000-4000-8000-000000000001'::uuid,
         'e7300000-0000-4000-8000-000000000002'::uuid
       ]
     ) $$,
  'Owner assigns East before the Manager history fixture'
);
select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000002', true);
select lives_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000002',
    'e7500000-0000-4000-8000-000000000001',
    14.50, 1, 'Manager East history fixture', 'price-manager-east-history'
  ) $$,
  'assigned Manager writes an East-branch event before assignment revocation'
);
select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000001', true);
select lives_ok(
  $$ select public.owner_set_member_access(
    'e7200000-0000-4000-8000-000000000001',
    'e7100000-0000-4000-8000-000000000002',
    'manager',
    array['e7300000-0000-4000-8000-000000000001'::uuid]
  ) $$,
  'Owner transactionally revokes East and retains Manager assignment to Main'
);
select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000002', true);
select lives_ok(
  $$ select * from public.set_branch_variant_price(
    'e7200000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000001',
    'e7500000-0000-4000-8000-000000000002',
    9.25, 1, 'Manager Main history fixture', 'price-manager-main-history'
  ) $$,
  'currently assigned Manager writes a Main-branch event after assignment evidence'
);
reset role;
update public.branches
set is_active = false
where shop_id = 'e7200000-0000-4000-8000-000000000001'
  and id in (
    'e7300000-0000-4000-8000-000000000001',
    'e7300000-0000-4000-8000-000000000002'
  );
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000001', true);
select is(
  (select count(*)::integer
   from public.branch_variant_price_events as event
   where event.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and event.branch_id = 'e7300000-0000-4000-8000-000000000001'
     and event.variant_id = 'e7500000-0000-4000-8000-000000000002'
     and event.event_type = 'price_updated'),
  1,
  'active Owner can read price history for an inactive branch'
);
select is(
  (select count(*)::integer
   from public.branch_variant_price_events as event
   where event.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and event.branch_id = 'e7300000-0000-4000-8000-000000000002'
     and event.variant_id = 'e7500000-0000-4000-8000-000000000001'),
  2,
  'active Owner can read East price history for an inactive branch'
);
select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000002', true);
select is(
  (select count(*)::integer
   from public.branch_variant_price_events as event
   where event.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and event.branch_id = 'e7300000-0000-4000-8000-000000000001'
     and event.variant_id = 'e7500000-0000-4000-8000-000000000002'
     and event.event_type = 'price_updated'),
  1,
  'Manager with proven current assignment can read events during that uninterrupted assignment on an inactive branch'
);
select is(
  (select count(*)::integer
   from public.branch_variant_price_events as event
   where event.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and event.branch_id = 'e7300000-0000-4000-8000-000000000002'),
  0,
  'Manager whose East assignment was revoked cannot read its historical price events'
);
select is(
  (select count(*)::integer
   from public.branch_variant_price_events as event
   where event.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and event.branch_id = 'e7300000-0000-4000-8000-000000000003'),
  0,
  'Manager with a legacy current assignment but no trustworthy history evidence is denied inactive-branch history'
);
select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000004', true);
select is(
  (select count(*)::integer
   from public.branch_variant_price_events as event
   where event.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and event.branch_id = 'e7300000-0000-4000-8000-000000000001'),
  0,
  'suspended membership cannot read inactive-branch history despite assignment evidence'
);
select set_config('request.jwt.claim.sub', 'e7100000-0000-4000-8000-000000000005', true);
select is(
  (select count(*)::integer
   from public.branch_variant_price_events as event
   where event.shop_id = 'e7200000-0000-4000-8000-000000000001'
     and event.branch_id = 'e7300000-0000-4000-8000-000000000001'),
  0,
  'cross-shop Owners cannot read inactive-branch price history'
);

reset role;
select throws_ok(
  $$ update public.branch_variant_price_events
     set change_reason = 'owner tampering' $$,
  '42501', null,
  'append-only trigger rejects trusted owner updates'
);
select throws_ok(
  $$ delete from public.branch_variant_price_operations $$,
  '42501', null,
  'append-only trigger rejects trusted owner deletes'
);
set constraints all immediate;
select throws_ok(
  $$ truncate table public.branch_variant_price_operations,
                       public.branch_variant_price_events cascade $$,
  '42501', null,
  'append-only triggers reject truncation of price audit history'
);
select throws_ok(
  $$ update private.branch_membership_price_access_events
     set event_type = 'revoked' $$,
  '42501', null,
  'append-only trigger rejects assignment-history updates'
);
select throws_ok(
  $$ delete from private.branch_membership_price_access_events $$,
  '42501', null,
  'append-only trigger rejects assignment-history deletes'
);
select throws_ok(
  $$ truncate table private.branch_membership_price_access_events $$,
  '42501', null,
  'append-only trigger rejects assignment-history truncation'
);

select * from finish();
rollback;
