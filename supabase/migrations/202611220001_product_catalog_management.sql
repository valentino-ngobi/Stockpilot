-- StockPilot Milestone 2, Phase 3A.
-- Controlled product catalog management on the existing inventory foundation.
-- Apply only after review and approval; this migration does not import or
-- rewrite financial records.

begin;

alter table public.products
  add column catalog_version bigint not null default 1,
  add constraint products_catalog_version_positive
    check (catalog_version > 0);

alter table public.product_variants
  add column catalog_version bigint not null default 1,
  add constraint product_variants_catalog_version_positive
    check (catalog_version > 0);

-- A composite key lets later audit rows prove that a variant belongs to the
-- recorded product, not merely to the same shop.
alter table public.product_variants
  add constraint product_variants_shop_product_id_id_key
    unique (shop_id, product_id, id);

-- Existing identifiers are variant-scoped. Their product parent is derived
-- from that existing, tenant-safe relationship; no identifier is discarded.
alter table public.product_identifiers
  add column product_id uuid;

update public.product_identifiers as identifier
set product_id = variant.product_id
from public.product_variants as variant
where variant.shop_id = identifier.shop_id
  and variant.id = identifier.variant_id;

do $migration$
declare
  unresolved_ids text;
begin
  if exists (
    select 1
    from public.product_identifiers
    where product_id is null
  ) then
    select string_agg(identifier.id::text, ', ' order by identifier.id)
      into unresolved_ids
    from public.product_identifiers as identifier
    where identifier.product_id is null;

    raise exception
      'Product identifier migration stopped: identifiers % have no matching tenant-safe variant. Resolve these product_identifiers rows before retrying.',
      unresolved_ids
      using errcode = '23503';
  end if;
end;
$migration$;

alter table public.product_identifiers
  add column retired_at timestamptz,
  add column retired_by uuid references auth.users (id) on delete restrict;

alter table public.product_identifiers
  alter column product_id set not null,
  alter column variant_id drop not null,
  add constraint product_identifiers_shop_product_fkey
    foreign key (shop_id, product_id)
    references public.products (shop_id, id) on delete restrict,
  add constraint product_identifiers_shop_product_variant_fkey
    foreign key (shop_id, product_id, variant_id)
    references public.product_variants (shop_id, product_id, id)
    on delete restrict,
  add constraint product_identifiers_retirement_pair_check
    check ((retired_at is null) = (retired_by is null));

alter table public.product_identifiers
  add constraint product_identifiers_shop_product_id_id_key
    unique (shop_id, product_id, id);

-- Older trusted SQL callers only supplied variant_id. Preserve that shape by
-- deriving its parent product from the authoritative tenant-safe variant row.
-- Product-level identifiers have no variant and must supply product_id.
create or replace function private.set_product_identifier_parent()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  variant_product_id uuid;
begin
  if new.variant_id is not null then
    select variant.product_id into variant_product_id
    from public.product_variants as variant
    where variant.shop_id = new.shop_id
      and variant.id = new.variant_id;

    if not found then
      raise exception 'The identifier variant does not exist in this shop.'
        using errcode = '23503';
    end if;

    if new.product_id is null then
      new.product_id := variant_product_id;
    elsif new.product_id is distinct from variant_product_id then
      raise exception 'The identifier product must own its referenced variant.'
        using errcode = '23503';
    end if;
  elsif new.product_id is null then
    raise exception 'A product-level identifier requires a product_id.'
      using errcode = '23502';
  end if;

  return new;
end;
$function$;

revoke all on function private.set_product_identifier_parent()
  from public, anon, authenticated, service_role;

create trigger product_identifiers_set_parent_before_insert
  before insert on public.product_identifiers
  for each row execute function private.set_product_identifier_parent();

-- Fail with an actionable diagnostic rather than silently allowing duplicate
-- active variants that would make catalog selection ambiguous.
do $migration$
begin
  if exists (
    select 1
    from public.product_variants as variant
    where variant.archived_at is null
    group by
      variant.shop_id,
      variant.product_id,
      lower(btrim(coalesce(variant.colour, ''))),
      lower(btrim(coalesce(variant.storage_capacity, ''))),
      lower(btrim(coalesce(variant.network_lock_status, ''))),
      variant.attributes
    having count(*) > 1
  ) then
    raise exception
      'Product catalog migration stopped: duplicate active variant signatures exist. Review product_variants by shop_id, product_id, normalized colour, storage_capacity, network_lock_status, and attributes before retrying.'
      using errcode = '23505';
  end if;
end;
$migration$;

create unique index product_variants_shop_signature_active_idx
  on public.product_variants (
    shop_id,
    product_id,
    lower(btrim(coalesce(colour, ''))),
    lower(btrim(coalesce(storage_capacity, ''))),
    lower(btrim(coalesce(network_lock_status, ''))),
    attributes
  )
  where archived_at is null;

create index product_identifiers_product_active_idx
  on public.product_identifiers (shop_id, product_id, retired_at);

create table public.catalog_operations (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  actor_id uuid not null references auth.users (id) on delete restrict,
  idempotency_key text not null,
  operation_type text not null,
  request_payload jsonb not null,
  result_product_id uuid not null,
  result_variant_id uuid,
  result_identifier_id uuid,
  created_at timestamptz not null default clock_timestamp(),
  unique (shop_id, id),
  unique (shop_id, actor_id, idempotency_key),
  foreign key (shop_id, result_product_id)
    references public.products (shop_id, id)
    on delete restrict deferrable initially deferred,
  foreign key (shop_id, result_product_id, result_variant_id)
    references public.product_variants (shop_id, product_id, id)
    on delete restrict deferrable initially deferred,
  foreign key (shop_id, result_product_id, result_identifier_id)
    references public.product_identifiers (shop_id, product_id, id)
    on delete restrict deferrable initially deferred,
  constraint catalog_operations_key_length
    check (char_length(btrim(idempotency_key)) between 8 and 120),
  constraint catalog_operations_type
    check (operation_type in (
      'product_created',
      'product_updated',
      'product_archived',
      'variant_created',
      'variant_updated',
      'variant_archived',
      'identifier_added',
      'identifier_retired'
    )),
  constraint catalog_operations_request_object
    check (jsonb_typeof(request_payload) = 'object')
);

create table public.product_catalog_events (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  operation_id uuid not null,
  event_sequence smallint not null default 1,
  product_id uuid not null,
  variant_id uuid,
  identifier_id uuid,
  event_type text not null,
  before_snapshot jsonb,
  after_snapshot jsonb not null,
  actor_id uuid not null references auth.users (id) on delete restrict,
  occurred_at timestamptz not null default clock_timestamp(),
  unique (shop_id, id),
  unique (shop_id, operation_id, event_sequence),
  foreign key (shop_id, operation_id)
    references public.catalog_operations (shop_id, id)
    on delete restrict,
  foreign key (shop_id, product_id)
    references public.products (shop_id, id)
    on delete restrict,
  foreign key (shop_id, product_id, variant_id)
    references public.product_variants (shop_id, product_id, id)
    on delete restrict,
  foreign key (shop_id, product_id, identifier_id)
    references public.product_identifiers (shop_id, product_id, id)
    on delete restrict,
  constraint product_catalog_events_sequence_positive
    check (event_sequence > 0),
  constraint product_catalog_events_type
    check (event_type in (
      'product_created',
      'product_updated',
      'product_archived',
      'variant_created',
      'variant_updated',
      'variant_archived',
      'identifier_added',
      'identifier_retired'
    )),
  constraint product_catalog_events_after_object
    check (jsonb_typeof(after_snapshot) = 'object'),
  constraint product_catalog_events_before_object
    check (before_snapshot is null or jsonb_typeof(before_snapshot) = 'object')
);

comment on table public.catalog_operations is
  'Append-only idempotency ledger for controlled catalog RPC operations.';
comment on table public.product_catalog_events is
  'Append-only before/after evidence for product, variant, and identifier changes.';
comment on column public.products.catalog_version is
  'Optimistic concurrency version incremented by catalog RPCs, including child catalog changes.';
comment on column public.product_variants.catalog_version is
  'Optimistic concurrency version incremented by variant catalog RPCs.';

-- New receipt lines receive a catalog description snapshot at insert time.
-- Existing rows remain NULL; no historical description is fabricated.
alter table public.inventory_receipt_lines
  add column catalog_snapshot jsonb,
  add constraint inventory_receipt_lines_catalog_snapshot_object
    check (catalog_snapshot is null or jsonb_typeof(catalog_snapshot) = 'object');

create or replace function private.snapshot_receipt_line_catalog()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  select jsonb_strip_nulls(jsonb_build_object(
    'snapshot_version', 1,
    'product_id', product.id,
    'product_type', product.product_type,
    'tracking_mode', product.tracking_mode,
    'product_name', product.name,
    'brand', product.brand,
    'model', product.model,
    'manufacturer_model_number', product.manufacturer_model_number,
    'description', product.description,
    'product_attributes', product.attributes,
    'variant_id', variant.id,
    'colour', variant.colour,
    'storage_capacity', variant.storage_capacity,
    'network_lock_status', variant.network_lock_status,
    'variant_attributes', variant.attributes
  ))
  into new.catalog_snapshot
  from public.product_variants as variant
  join public.products as product
    on product.shop_id = variant.shop_id
   and product.id = variant.product_id
  where variant.shop_id = new.shop_id
    and variant.id = new.variant_id;

  if new.catalog_snapshot is null then
    raise exception 'Receipt line catalog snapshot could not be resolved.'
      using errcode = '23503';
  end if;

  return new;
end;
$function$;

revoke all on function private.snapshot_receipt_line_catalog()
  from public, anon, authenticated, service_role;

create trigger inventory_receipt_lines_catalog_snapshot_before_insert
  before insert on public.inventory_receipt_lines
  for each row execute function private.snapshot_receipt_line_catalog();

create or replace function private.reject_catalog_history_mutation()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception 'Catalog operation and event history is append-only.'
    using errcode = '42501';
end;
$function$;

revoke all on function private.reject_catalog_history_mutation()
  from public, anon, authenticated, service_role;

create trigger catalog_operations_append_only
  before update or delete on public.catalog_operations
  for each row execute function private.reject_catalog_history_mutation();
create trigger catalog_operations_no_truncate
  before truncate on public.catalog_operations
  for each statement execute function private.reject_catalog_history_mutation();
create trigger product_catalog_events_append_only
  before update or delete on public.product_catalog_events
  for each row execute function private.reject_catalog_history_mutation();
create trigger product_catalog_events_no_truncate
  before truncate on public.product_catalog_events
  for each statement execute function private.reject_catalog_history_mutation();

create or replace function private.assert_catalog_editor(p_shop_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid := (select auth.uid());
  membership_role_value public.shop_role;
begin
  if actor_id_value is null or p_shop_id is null then
    raise exception 'An active Owner or Manager membership is required.'
      using errcode = '42501';
  end if;

  select membership.role
    into membership_role_value
  from public.shop_memberships as membership
  where membership.shop_id = p_shop_id
    and membership.user_id = actor_id_value
    and membership.status = 'active'
  for share;

  if not found
    or membership_role_value not in (
      'owner'::public.shop_role,
      'manager'::public.shop_role
    )
  then
    raise exception 'An active Owner or Manager membership is required.'
      using errcode = '42501';
  end if;

  return actor_id_value;
end;
$function$;

create or replace function private.claim_catalog_operation(
  p_shop_id uuid,
  p_actor_id uuid,
  p_idempotency_key text,
  p_operation_type text,
  p_request_payload jsonb,
  p_result_product_id uuid,
  p_result_variant_id uuid,
  p_result_identifier_id uuid
)
returns table (
  operation_id uuid,
  replayed boolean,
  result_product_id uuid,
  result_variant_id uuid,
  result_identifier_id uuid
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  inserted_id uuid;
  existing_row public.catalog_operations%rowtype;
begin
  if p_idempotency_key is null
    or char_length(btrim(p_idempotency_key)) not between 8 and 120
    or p_request_payload is null
    or jsonb_typeof(p_request_payload) is distinct from 'object'
  then
    raise exception 'A valid idempotency key and object request are required.'
      using errcode = '22023';
  end if;

  insert into public.catalog_operations (
    shop_id, actor_id, idempotency_key, operation_type, request_payload,
    result_product_id, result_variant_id, result_identifier_id
  ) values (
    p_shop_id, p_actor_id, btrim(p_idempotency_key), p_operation_type,
    p_request_payload, p_result_product_id, p_result_variant_id,
    p_result_identifier_id
  )
  on conflict (shop_id, actor_id, idempotency_key) do nothing
  returning id into inserted_id;

  if inserted_id is not null then
    operation_id := inserted_id;
    replayed := false;
    result_product_id := p_result_product_id;
    result_variant_id := p_result_variant_id;
    result_identifier_id := p_result_identifier_id;
    return next;
    return;
  end if;

  select operation.*
    into existing_row
  from public.catalog_operations as operation
  where operation.shop_id = p_shop_id
    and operation.actor_id = p_actor_id
    and operation.idempotency_key = btrim(p_idempotency_key)
  for update;

  if not found then
    raise exception 'Catalog operation could not be resolved after an idempotency conflict.'
      using errcode = '40001';
  end if;

  if existing_row.operation_type is distinct from p_operation_type
    or existing_row.request_payload is distinct from p_request_payload
  then
    raise exception 'This idempotency key was already used for a different catalog request.'
      using errcode = '22023';
  end if;

  operation_id := existing_row.id;
  replayed := true;
  result_product_id := existing_row.result_product_id;
  result_variant_id := existing_row.result_variant_id;
  result_identifier_id := existing_row.result_identifier_id;
  return next;
end;
$function$;

create or replace function private.catalog_product_snapshot(
  p_shop_id uuid,
  p_product_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'id', product.id,
    'shop_id', product.shop_id,
    'product_type', product.product_type,
    'tracking_mode', product.tracking_mode,
    'name', product.name,
    'brand', product.brand,
    'model', product.model,
    'manufacturer_model_number', product.manufacturer_model_number,
    'description', product.description,
    'attributes', product.attributes,
    'catalog_version', product.catalog_version,
    'archived_at', product.archived_at
  )
  from public.products as product
  where product.shop_id = p_shop_id
    and product.id = p_product_id;
$function$;

create or replace function private.catalog_variant_snapshot(
  p_shop_id uuid,
  p_variant_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'id', variant.id,
    'shop_id', variant.shop_id,
    'product_id', variant.product_id,
    'colour', variant.colour,
    'storage_capacity', variant.storage_capacity,
    'network_lock_status', variant.network_lock_status,
    'attributes', variant.attributes,
    'catalog_version', variant.catalog_version,
    'archived_at', variant.archived_at
  )
  from public.product_variants as variant
  where variant.shop_id = p_shop_id
    and variant.id = p_variant_id;
$function$;

create or replace function private.catalog_identifier_snapshot(
  p_shop_id uuid,
  p_identifier_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'id', identifier.id,
    'shop_id', identifier.shop_id,
    'product_id', identifier.product_id,
    'variant_id', identifier.variant_id,
    'identifier_type', identifier.identifier_type,
    'raw_value', identifier.raw_value,
    'normalized_value', identifier.normalized_value,
    'retired_at', identifier.retired_at,
    'retired_by', identifier.retired_by
  )
  from public.product_identifiers as identifier
  where identifier.shop_id = p_shop_id
    and identifier.id = p_identifier_id;
$function$;

revoke all on function private.assert_catalog_editor(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.claim_catalog_operation(
  uuid, uuid, text, text, jsonb, uuid, uuid, uuid
) from public, anon, authenticated, service_role;
revoke all on function private.catalog_product_snapshot(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.catalog_variant_snapshot(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.catalog_identifier_snapshot(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.create_product(
  p_shop_id uuid,
  p_idempotency_key text,
  p_name text,
  p_product_type text,
  p_tracking_mode text,
  p_brand text default null,
  p_model text default null,
  p_manufacturer_model_number text default null,
  p_description text default null,
  p_attributes jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid := private.assert_catalog_editor(p_shop_id);
  product_id_value uuid := gen_random_uuid();
  operation_row record;
  event_snapshot jsonb;
  product_name_value text := nullif(btrim(p_name), '');
  brand_value text := nullif(btrim(p_brand), '');
  model_value text := nullif(btrim(p_model), '');
  manufacturer_number_value text := nullif(btrim(p_manufacturer_model_number), '');
  description_value text := nullif(btrim(p_description), '');
begin
  if product_name_value is null
    or char_length(product_name_value) > 160
    or p_product_type is null
    or p_product_type not in (
      'smartphone', 'tablet', 'laptop', 'accessory', 'spare_part', 'other'
    )
    or p_tracking_mode is null
    or p_tracking_mode not in ('serialized', 'quantity')
    or (brand_value is not null and char_length(brand_value) > 120)
    or (model_value is not null and char_length(model_value) > 120)
    or (manufacturer_number_value is not null
      and char_length(manufacturer_number_value) > 160)
    or (description_value is not null and char_length(description_value) > 2000)
    or p_attributes is null
    or jsonb_typeof(p_attributes) is distinct from 'object'
    or pg_column_size(p_attributes) > 32768
  then
    raise exception 'Product fields are invalid.'
      using errcode = '22023';
  end if;

  select * into operation_row
  from private.claim_catalog_operation(
    p_shop_id, actor_id_value, p_idempotency_key, 'product_created',
    jsonb_build_object(
      'name', product_name_value,
      'product_type', p_product_type,
      'tracking_mode', p_tracking_mode,
      'brand', brand_value,
      'model', model_value,
      'manufacturer_model_number', manufacturer_number_value,
      'description', description_value,
      'attributes', p_attributes
    ),
    product_id_value, null, null
  );

  if operation_row.replayed then
    return operation_row.result_product_id;
  end if;

  insert into public.products (
    id, shop_id, product_type, tracking_mode, name, brand, model,
    manufacturer_model_number, description, attributes, created_by, updated_by
  ) values (
    product_id_value, p_shop_id, p_product_type, p_tracking_mode,
    product_name_value, brand_value, model_value,
    manufacturer_number_value, description_value, p_attributes,
    actor_id_value, actor_id_value
  );

  event_snapshot := private.catalog_product_snapshot(p_shop_id, product_id_value);
  insert into public.product_catalog_events (
    shop_id, operation_id, product_id, event_type, before_snapshot,
    after_snapshot, actor_id
  ) values (
    p_shop_id, operation_row.operation_id, product_id_value, 'product_created',
    null, event_snapshot, actor_id_value
  );

  return product_id_value;
end;
$function$;

create or replace function public.create_product_variant(
  p_shop_id uuid,
  p_product_id uuid,
  p_idempotency_key text,
  p_colour text default null,
  p_storage_capacity text default null,
  p_network_lock_status text default null,
  p_attributes jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid := private.assert_catalog_editor(p_shop_id);
  variant_id_value uuid := gen_random_uuid();
  operation_row record;
  product_row public.products%rowtype;
  event_snapshot jsonb;
  colour_value text := nullif(btrim(p_colour), '');
  storage_value text := nullif(btrim(p_storage_capacity), '');
  lock_status_value text := nullif(btrim(p_network_lock_status), '');
begin
  if p_attributes is null or jsonb_typeof(p_attributes) is distinct from 'object'
    or pg_column_size(p_attributes) > 16384
    or (colour_value is not null and char_length(colour_value) > 80)
    or (storage_value is not null and char_length(storage_value) > 80)
    or (lock_status_value is not null and char_length(lock_status_value) > 40)
  then
    raise exception 'Product variant fields are invalid.'
      using errcode = '22023';
  end if;

  select product.* into product_row
  from public.products as product
  where product.shop_id = p_shop_id
    and product.id = p_product_id
  for update;

  if not found then
    raise exception 'The product does not exist in this shop.'
      using errcode = '22023';
  end if;

  select * into operation_row
  from private.claim_catalog_operation(
    p_shop_id, actor_id_value, p_idempotency_key, 'variant_created',
    jsonb_build_object(
      'product_id', p_product_id,
      'colour', colour_value,
      'storage_capacity', storage_value,
      'network_lock_status', lock_status_value,
      'attributes', p_attributes
    ),
    p_product_id, variant_id_value, null
  );

  if operation_row.replayed then
    return operation_row.result_variant_id;
  end if;

  if product_row.archived_at is not null then
    raise exception 'The product is archived.'
      using errcode = '22023';
  end if;

  insert into public.product_variants (
    id, shop_id, product_id, colour, storage_capacity,
    network_lock_status, attributes, created_by, updated_by
  ) values (
    variant_id_value, p_shop_id, p_product_id, colour_value, storage_value,
    lock_status_value, p_attributes, actor_id_value, actor_id_value
  );

  update public.products
  set catalog_version = catalog_version + 1,
      updated_at = clock_timestamp(),
      updated_by = actor_id_value
  where shop_id = p_shop_id and id = p_product_id;

  event_snapshot := private.catalog_variant_snapshot(p_shop_id, variant_id_value);
  insert into public.product_catalog_events (
    shop_id, operation_id, product_id, variant_id, event_type,
    before_snapshot, after_snapshot, actor_id
  ) values (
    p_shop_id, operation_row.operation_id, p_product_id, variant_id_value,
    'variant_created', null, event_snapshot, actor_id_value
  );

  return variant_id_value;
end;
$function$;

create or replace function public.update_product(
  p_shop_id uuid,
  p_product_id uuid,
  p_expected_version bigint,
  p_idempotency_key text,
  p_name text,
  p_product_type text,
  p_tracking_mode text,
  p_brand text,
  p_model text,
  p_manufacturer_model_number text,
  p_description text,
  p_attributes jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid := private.assert_catalog_editor(p_shop_id);
  operation_row record;
  product_row public.products%rowtype;
  before_value jsonb;
  after_value jsonb;
  product_name_value text := nullif(btrim(p_name), '');
  brand_value text := nullif(btrim(p_brand), '');
  model_value text := nullif(btrim(p_model), '');
  manufacturer_number_value text := nullif(btrim(p_manufacturer_model_number), '');
  description_value text := nullif(btrim(p_description), '');
begin
  select product.* into product_row
  from public.products as product
  where product.shop_id = p_shop_id
    and product.id = p_product_id
  for update;

  if not found then
    raise exception 'The product does not exist in this shop.'
      using errcode = '22023';
  end if;

  if product_name_value is null
    or char_length(product_name_value) > 160
    or p_product_type is null
    or p_product_type not in (
      'smartphone', 'tablet', 'laptop', 'accessory', 'spare_part', 'other'
    )
    or p_tracking_mode is null
    or p_tracking_mode not in ('serialized', 'quantity')
    or (brand_value is not null and char_length(brand_value) > 120)
    or (model_value is not null and char_length(model_value) > 120)
    or (manufacturer_number_value is not null
      and char_length(manufacturer_number_value) > 160)
    or (description_value is not null and char_length(description_value) > 2000)
    or p_attributes is null
    or jsonb_typeof(p_attributes) is distinct from 'object'
    or pg_column_size(p_attributes) > 32768
    or p_expected_version is null
    or p_expected_version < 1
  then
    raise exception 'Product fields or expected version are invalid.'
      using errcode = '22023';
  end if;

  select * into operation_row
  from private.claim_catalog_operation(
    p_shop_id, actor_id_value, p_idempotency_key, 'product_updated',
    jsonb_build_object(
      'product_id', p_product_id,
      'expected_version', p_expected_version,
      'name', product_name_value,
      'product_type', p_product_type,
      'tracking_mode', p_tracking_mode,
      'brand', brand_value,
      'model', model_value,
      'manufacturer_model_number', manufacturer_number_value,
      'description', description_value,
      'attributes', p_attributes
    ),
    p_product_id, null, null
  );

  if operation_row.replayed then
    return operation_row.result_product_id;
  end if;

  if product_row.archived_at is not null then
    raise exception 'The product is archived.'
      using errcode = '22023';
  end if;

  if product_row.catalog_version <> p_expected_version then
    raise exception 'Product changed since it was loaded; refresh and retry.'
      using errcode = '40001';
  end if;

  if p_tracking_mode is distinct from product_row.tracking_mode then
    -- Receiving RPCs read product tracking mode inside their transaction.
    -- This rare conversion takes a table lock so no receipt can validate the
    -- old mode while the catalog changes it.
    lock table public.products in access exclusive mode;

    if exists (
      select 1
      from public.product_variants as variant
      where variant.shop_id = p_shop_id
        and variant.product_id = p_product_id
        and (
          exists (
            select 1 from public.inventory_balances as balance
            where balance.shop_id = variant.shop_id
              and balance.variant_id = variant.id
          )
          or exists (
            select 1 from public.serialized_inventory as device
            where device.shop_id = variant.shop_id
              and device.variant_id = variant.id
          )
          or exists (
            select 1 from public.inventory_receipt_lines as line
            where line.shop_id = variant.shop_id
              and line.variant_id = variant.id
          )
          or exists (
            select 1 from public.inventory_movements as movement
            where movement.shop_id = variant.shop_id
              and movement.variant_id = variant.id
          )
          or exists (
            select 1 from public.branch_variant_prices as price
            where price.shop_id = variant.shop_id
              and price.variant_id = variant.id
          )
        )
    ) then
      raise exception 'Tracking mode cannot change after inventory, receipt, movement, or branch-price history exists.'
        using errcode = '23514';
    end if;
  end if;

  before_value := private.catalog_product_snapshot(p_shop_id, p_product_id);
  update public.products
  set product_type = p_product_type,
      tracking_mode = p_tracking_mode,
      name = product_name_value,
      brand = brand_value,
      model = model_value,
      manufacturer_model_number = manufacturer_number_value,
      description = description_value,
      attributes = p_attributes,
      catalog_version = catalog_version + 1,
      updated_at = clock_timestamp(),
      updated_by = actor_id_value
  where shop_id = p_shop_id and id = p_product_id;
  after_value := private.catalog_product_snapshot(p_shop_id, p_product_id);

  insert into public.product_catalog_events (
    shop_id, operation_id, product_id, event_type, before_snapshot,
    after_snapshot, actor_id
  ) values (
    p_shop_id, operation_row.operation_id, p_product_id, 'product_updated',
    before_value, after_value, actor_id_value
  );

  return p_product_id;
end;
$function$;

create or replace function public.update_product_variant(
  p_shop_id uuid,
  p_variant_id uuid,
  p_expected_version bigint,
  p_idempotency_key text,
  p_colour text,
  p_storage_capacity text,
  p_network_lock_status text,
  p_attributes jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid := private.assert_catalog_editor(p_shop_id);
  operation_row record;
  product_id_value uuid;
  product_row public.products%rowtype;
  variant_row public.product_variants%rowtype;
  before_value jsonb;
  after_value jsonb;
  colour_value text := nullif(btrim(p_colour), '');
  storage_value text := nullif(btrim(p_storage_capacity), '');
  lock_status_value text := nullif(btrim(p_network_lock_status), '');
begin
  select variant.product_id into product_id_value
  from public.product_variants as variant
  where variant.shop_id = p_shop_id and variant.id = p_variant_id;

  select product.* into product_row
  from public.products as product
  where product.shop_id = p_shop_id and product.id = product_id_value
  for update;

  select variant.* into variant_row
  from public.product_variants as variant
  where variant.shop_id = p_shop_id
    and variant.id = p_variant_id
    and variant.product_id = product_id_value
  for update;

  if not found or product_row.id is null
  then
    raise exception 'The product variant does not exist in this shop.'
      using errcode = '22023';
  end if;

  if p_expected_version is null
    or p_expected_version < 1
    or p_attributes is null
    or jsonb_typeof(p_attributes) is distinct from 'object'
    or pg_column_size(p_attributes) > 16384
    or (colour_value is not null and char_length(colour_value) > 80)
    or (storage_value is not null and char_length(storage_value) > 80)
    or (lock_status_value is not null and char_length(lock_status_value) > 40)
  then
    raise exception 'Product variant fields or expected version are invalid.'
      using errcode = '22023';
  end if;

  select * into operation_row
  from private.claim_catalog_operation(
    p_shop_id, actor_id_value, p_idempotency_key, 'variant_updated',
    jsonb_build_object(
      'variant_id', p_variant_id,
      'expected_version', p_expected_version,
      'colour', colour_value,
      'storage_capacity', storage_value,
      'network_lock_status', lock_status_value,
      'attributes', p_attributes
    ),
    product_id_value, p_variant_id, null
  );

  if operation_row.replayed then
    return operation_row.result_variant_id;
  end if;

  if product_row.archived_at is not null or variant_row.archived_at is not null then
    raise exception 'The product or variant is archived.'
      using errcode = '22023';
  end if;

  if variant_row.catalog_version <> p_expected_version then
    raise exception 'Product variant changed since it was loaded; refresh and retry.'
      using errcode = '40001';
  end if;

  before_value := private.catalog_variant_snapshot(p_shop_id, p_variant_id);
  update public.product_variants
  set colour = colour_value,
      storage_capacity = storage_value,
      network_lock_status = lock_status_value,
      attributes = p_attributes,
      catalog_version = catalog_version + 1,
      updated_at = clock_timestamp(),
      updated_by = actor_id_value
  where shop_id = p_shop_id and id = p_variant_id;

  update public.products
  set catalog_version = catalog_version + 1,
      updated_at = clock_timestamp(),
      updated_by = actor_id_value
  where shop_id = p_shop_id and id = product_id_value;

  after_value := private.catalog_variant_snapshot(p_shop_id, p_variant_id);
  insert into public.product_catalog_events (
    shop_id, operation_id, product_id, variant_id, event_type,
    before_snapshot, after_snapshot, actor_id
  ) values (
    p_shop_id, operation_row.operation_id, product_id_value, p_variant_id,
    'variant_updated', before_value, after_value, actor_id_value
  );

  return p_variant_id;
end;
$function$;

create or replace function public.archive_product(
  p_shop_id uuid,
  p_product_id uuid,
  p_expected_version bigint,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid := private.assert_catalog_editor(p_shop_id);
  operation_row record;
  product_row public.products%rowtype;
  before_value jsonb;
  after_value jsonb;
begin
  select product.* into product_row
  from public.products as product
  where product.shop_id = p_shop_id and product.id = p_product_id
  for update;

  if not found then
    raise exception 'The product does not exist in this shop.'
      using errcode = '22023';
  end if;

  if p_expected_version is null or p_expected_version < 1 then
    raise exception 'A positive product version is required.'
      using errcode = '22023';
  end if;

  select * into operation_row
  from private.claim_catalog_operation(
    p_shop_id, actor_id_value, p_idempotency_key, 'product_archived',
    jsonb_build_object(
      'product_id', p_product_id,
      'expected_version', p_expected_version
    ),
    p_product_id, null, null
  );

  if operation_row.replayed then
    return operation_row.result_product_id;
  end if;

  if product_row.archived_at is not null
    or product_row.catalog_version <> p_expected_version
  then
    raise exception 'Product is archived or changed since it was loaded.'
      using errcode = '40001';
  end if;

  before_value := private.catalog_product_snapshot(p_shop_id, p_product_id);
  update public.products
  set archived_at = clock_timestamp(),
      catalog_version = catalog_version + 1,
      updated_at = clock_timestamp(),
      updated_by = actor_id_value
  where shop_id = p_shop_id and id = p_product_id;
  after_value := private.catalog_product_snapshot(p_shop_id, p_product_id);

  insert into public.product_catalog_events (
    shop_id, operation_id, product_id, event_type, before_snapshot,
    after_snapshot, actor_id
  ) values (
    p_shop_id, operation_row.operation_id, p_product_id, 'product_archived',
    before_value, after_value, actor_id_value
  );

  return p_product_id;
end;
$function$;

create or replace function public.archive_product_variant(
  p_shop_id uuid,
  p_variant_id uuid,
  p_expected_version bigint,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid := private.assert_catalog_editor(p_shop_id);
  operation_row record;
  product_id_value uuid;
  product_row public.products%rowtype;
  variant_row public.product_variants%rowtype;
  before_value jsonb;
  after_value jsonb;
begin
  select variant.product_id into product_id_value
  from public.product_variants as variant
  where variant.shop_id = p_shop_id and variant.id = p_variant_id;

  select product.* into product_row
  from public.products as product
  where product.shop_id = p_shop_id and product.id = product_id_value
  for update;

  select variant.* into variant_row
  from public.product_variants as variant
  where variant.shop_id = p_shop_id
    and variant.id = p_variant_id
    and variant.product_id = product_id_value
  for update;

  if not found or product_row.id is null
  then
    raise exception 'The product variant does not exist in this shop.'
      using errcode = '22023';
  end if;

  if p_expected_version is null or p_expected_version < 1 then
    raise exception 'A positive product variant version is required.'
      using errcode = '22023';
  end if;

  select * into operation_row
  from private.claim_catalog_operation(
    p_shop_id, actor_id_value, p_idempotency_key, 'variant_archived',
    jsonb_build_object(
      'variant_id', p_variant_id,
      'expected_version', p_expected_version
    ),
    product_id_value, p_variant_id, null
  );

  if operation_row.replayed then
    return operation_row.result_variant_id;
  end if;

  if product_row.archived_at is not null or variant_row.archived_at is not null then
    raise exception 'The product or variant is archived.'
      using errcode = '40001';
  end if;

  if variant_row.catalog_version <> p_expected_version then
    raise exception 'Product variant changed since it was loaded; refresh and retry.'
      using errcode = '40001';
  end if;

  before_value := private.catalog_variant_snapshot(p_shop_id, p_variant_id);
  update public.product_variants
  set archived_at = clock_timestamp(),
      catalog_version = catalog_version + 1,
      updated_at = clock_timestamp(),
      updated_by = actor_id_value
  where shop_id = p_shop_id and id = p_variant_id;

  update public.products
  set catalog_version = catalog_version + 1,
      updated_at = clock_timestamp(),
      updated_by = actor_id_value
  where shop_id = p_shop_id and id = product_id_value;

  after_value := private.catalog_variant_snapshot(p_shop_id, p_variant_id);
  insert into public.product_catalog_events (
    shop_id, operation_id, product_id, variant_id, event_type,
    before_snapshot, after_snapshot, actor_id
  ) values (
    p_shop_id, operation_row.operation_id, product_id_value, p_variant_id,
    'variant_archived', before_value, after_value, actor_id_value
  );

  return p_variant_id;
end;
$function$;

create or replace function public.add_product_identifier(
  p_shop_id uuid,
  p_product_id uuid,
  p_variant_id uuid,
  p_identifier_type text,
  p_raw_value text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid := private.assert_catalog_editor(p_shop_id);
  operation_row record;
  parent_product_id uuid;
  product_row public.products%rowtype;
  identifier_id_value uuid := gen_random_uuid();
  before_value jsonb := null;
  after_value jsonb;
  raw_value text := nullif(btrim(p_raw_value), '');
begin
  if (p_product_id is null) = (p_variant_id is null)
    or p_identifier_type is null
    or p_identifier_type not in ('sku', 'barcode', 'manufacturer_part_number')
    or raw_value is null
    or char_length(raw_value) > 160
  then
    raise exception 'A single product or variant target and valid catalog identifier are required.'
      using errcode = '22023';
  end if;

  if p_variant_id is not null then
    select variant.product_id into parent_product_id
    from public.product_variants as variant
    where variant.shop_id = p_shop_id
      and variant.id = p_variant_id;
  else
    parent_product_id := p_product_id;
  end if;

  if parent_product_id is null
    or (p_product_id is not null and p_product_id <> parent_product_id)
  then
    raise exception 'The active product or variant does not exist in this shop.'
      using errcode = '22023';
  end if;

  select product.* into product_row
  from public.products as product
  where product.shop_id = p_shop_id
    and product.id = parent_product_id
  for update;

  if not found then
    raise exception 'The product does not exist in this shop.'
      using errcode = '22023';
  end if;

  if p_variant_id is not null then
    perform 1
    from public.product_variants as variant
    where variant.shop_id = p_shop_id
      and variant.id = p_variant_id
      and variant.product_id = parent_product_id
    for update;
    if not found then
      raise exception 'The product variant does not exist in this shop.'
        using errcode = '22023';
    end if;
  end if;

  select * into operation_row
  from private.claim_catalog_operation(
    p_shop_id, actor_id_value, p_idempotency_key, 'identifier_added',
    jsonb_build_object(
      'product_id', parent_product_id,
      'variant_id', p_variant_id,
      'identifier_type', p_identifier_type,
      'raw_value', raw_value
    ),
    parent_product_id, p_variant_id, identifier_id_value
  );

  if operation_row.replayed then
    return operation_row.result_identifier_id;
  end if;

  if product_row.archived_at is not null then
    raise exception 'The product is archived.'
      using errcode = '22023';
  end if;

  if p_variant_id is not null then
    perform 1
    from public.product_variants as variant
    where variant.shop_id = p_shop_id
      and variant.id = p_variant_id
      and variant.product_id = parent_product_id
      and variant.archived_at is null
    for update;
    if not found then
      raise exception 'The active product variant does not exist in this shop.'
        using errcode = '22023';
    end if;
  end if;

  insert into public.product_identifiers (
    id, shop_id, product_id, variant_id, identifier_type,
    raw_value, created_by
  ) values (
    identifier_id_value, p_shop_id, parent_product_id, p_variant_id,
    p_identifier_type, raw_value, actor_id_value
  );

  update public.products
  set catalog_version = catalog_version + 1,
      updated_at = clock_timestamp(),
      updated_by = actor_id_value
  where shop_id = p_shop_id and id = parent_product_id;

  after_value := private.catalog_identifier_snapshot(p_shop_id, identifier_id_value);
  insert into public.product_catalog_events (
    shop_id, operation_id, product_id, variant_id, identifier_id,
    event_type, before_snapshot, after_snapshot, actor_id
  ) values (
    p_shop_id, operation_row.operation_id, parent_product_id, p_variant_id,
    identifier_id_value, 'identifier_added', before_value, after_value,
    actor_id_value
  );

  return identifier_id_value;
end;
$function$;

create or replace function public.retire_product_identifier(
  p_shop_id uuid,
  p_identifier_id uuid,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid := private.assert_catalog_editor(p_shop_id);
  operation_row record;
  product_id_value uuid;
  variant_id_value uuid;
  product_row public.products%rowtype;
  before_value jsonb;
  after_value jsonb;
begin
  select identifier.product_id, identifier.variant_id
    into product_id_value, variant_id_value
  from public.product_identifiers as identifier
  where identifier.shop_id = p_shop_id
    and identifier.id = p_identifier_id;

  select product.* into product_row
  from public.products as product
  where product.shop_id = p_shop_id
    and product.id = product_id_value
  for update;

  if not found then
    raise exception 'The catalog identifier does not exist in this shop.'
      using errcode = '22023';
  end if;

  select * into operation_row
  from private.claim_catalog_operation(
    p_shop_id, actor_id_value, p_idempotency_key, 'identifier_retired',
    jsonb_build_object(
      'identifier_id', p_identifier_id,
      'product_id', product_id_value,
      'variant_id', variant_id_value
    ),
    product_id_value, variant_id_value, p_identifier_id
  );

  if operation_row.replayed then
    return operation_row.result_identifier_id;
  end if;

  before_value := private.catalog_identifier_snapshot(p_shop_id, p_identifier_id);
  if product_row.archived_at is not null
    or before_value ->> 'retired_at' is not null
  then
    raise exception 'The product or identifier is already archived or retired.'
      using errcode = '40001';
  end if;

  update public.product_identifiers
  set retired_at = clock_timestamp(),
      retired_by = actor_id_value
  where shop_id = p_shop_id
    and id = p_identifier_id
    and retired_at is null;

  if not found then
    raise exception 'The catalog identifier was retired by another operation.'
      using errcode = '40001';
  end if;

  update public.products
  set catalog_version = catalog_version + 1,
      updated_at = clock_timestamp(),
      updated_by = actor_id_value
  where shop_id = p_shop_id and id = product_id_value;

  after_value := private.catalog_identifier_snapshot(p_shop_id, p_identifier_id);
  insert into public.product_catalog_events (
    shop_id, operation_id, product_id, variant_id, identifier_id,
    event_type, before_snapshot, after_snapshot, actor_id
  ) values (
    p_shop_id, operation_row.operation_id, product_id_value, variant_id_value,
    p_identifier_id, 'identifier_retired', before_value, after_value,
    actor_id_value
  );

  return p_identifier_id;
end;
$function$;

revoke all on function public.create_product(
  uuid, text, text, text, text, text, text, text, text, jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.create_product_variant(
  uuid, uuid, text, text, text, text, jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.update_product(
  uuid, uuid, bigint, text, text, text, text, text, text, text, text, jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.update_product_variant(
  uuid, uuid, bigint, text, text, text, text, jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.archive_product(uuid, uuid, bigint, text)
  from public, anon, authenticated, service_role;
revoke all on function public.archive_product_variant(uuid, uuid, bigint, text)
  from public, anon, authenticated, service_role;
revoke all on function public.add_product_identifier(
  uuid, uuid, uuid, text, text, text
) from public, anon, authenticated, service_role;
revoke all on function public.retire_product_identifier(uuid, uuid, text)
  from public, anon, authenticated, service_role;

grant execute on function public.create_product(
  uuid, text, text, text, text, text, text, text, text, jsonb
) to authenticated;
grant execute on function public.create_product_variant(
  uuid, uuid, text, text, text, text, jsonb
) to authenticated;
grant execute on function public.update_product(
  uuid, uuid, bigint, text, text, text, text, text, text, text, text, jsonb
) to authenticated;
grant execute on function public.update_product_variant(
  uuid, uuid, bigint, text, text, text, text, jsonb
) to authenticated;
grant execute on function public.archive_product(uuid, uuid, bigint, text)
  to authenticated;
grant execute on function public.archive_product_variant(uuid, uuid, bigint, text)
  to authenticated;
grant execute on function public.add_product_identifier(
  uuid, uuid, uuid, text, text, text
) to authenticated;
grant execute on function public.retire_product_identifier(uuid, uuid, text)
  to authenticated;

alter table public.catalog_operations enable row level security;
alter table public.product_catalog_events enable row level security;

revoke all on public.catalog_operations, public.product_catalog_events
  from public, anon, authenticated, service_role;
grant select on public.catalog_operations, public.product_catalog_events
  to authenticated, service_role;

create policy catalog_operations_read_active_member
  on public.catalog_operations for select to authenticated
  using (private.is_active_shop_member(shop_id));
create policy product_catalog_events_read_active_member
  on public.product_catalog_events for select to authenticated
  using (private.is_active_shop_member(shop_id));

commit;
