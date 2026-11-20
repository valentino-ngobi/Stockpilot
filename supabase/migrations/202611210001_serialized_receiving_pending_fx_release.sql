-- Stable device identity is shop + variant + serialized item ID. Branches on
-- receipts, identifiers, and movements are historical operation context.
--
-- Deployment sizing: this migration is intended for an early deployment with
-- a small inventory catalog. Adding UNIQUE constraints, creating the partial
-- unique identifier index, and validating replacement foreign keys scan their
-- tables while DDL locks block competing writes (and some ALTER TABLE steps
-- take ACCESS EXCLUSIVE locks). For a large populated deployment, stage these
-- changes: build indexes CONCURRENTLY, add foreign keys NOT VALID, validate
-- them separately, and schedule the remaining metadata changes in a maintenance
-- window. Do not run this single migration during busy production traffic.

-- The baseline schema has no primary-identifier marker. Any pre-existing
-- serialized device is therefore ambiguous; stop before any DDL rather than
-- guessing that imei1, the first row, or another identifier is primary.
do $migration$
declare
  unresolved_records text;
begin
  select pg_catalog.string_agg(
    pg_catalog.format(
      'shop_id=%s serialized_inventory_id=%s identifier_count=%s identifiers=%s',
      legacy_device.shop_id,
      legacy_device.id,
      legacy_device.identifier_count,
      legacy_device.identifier_refs
    ),
    E'\n' order by legacy_device.shop_id, legacy_device.id
  )
  into unresolved_records
  from (
    select item.shop_id,
           item.id,
           pg_catalog.count(identifier.id) as identifier_count,
           coalesce(
             pg_catalog.string_agg(
               pg_catalog.format('%s:%s', identifier.id, identifier.identifier_type),
               ', ' order by identifier.id
             ),
             '(none)'
           ) as identifier_refs
    from public.serialized_inventory as item
    left join public.serialized_identifiers as identifier
      on identifier.shop_id = item.shop_id
     and identifier.serialized_inventory_id = item.id
    group by item.shop_id, item.id
  ) as legacy_device;

  if unresolved_records is not null then
    raise exception using
      errcode = '55000',
      message = pg_catalog.format(
        'Cannot safely add primary-identifier metadata because the baseline has no authoritative primary marker. Unresolved devices and identifier IDs/types: %s. No records were changed. Provide an explicitly reviewed primary mapping for each listed device before rerunning this migration.',
        unresolved_records
      );
  end if;
end;
$migration$;

alter table public.serialized_inventory
  add constraint serialized_inventory_shop_id_key unique (shop_id, id),
  add constraint serialized_inventory_shop_variant_id_key
    unique (shop_id, variant_id, id);

alter table public.serialized_identifiers
  add column is_primary boolean not null default false;

-- The baseline schema has no reliable primary-identifier metadata. Do not
-- infer that imei1 or any other identifier is primary. Existing rows without
-- exactly one explicit primary designation must be resolved by an operator
-- before this migration can complete.
create or replace function private.assert_serialized_identifier_primary_ready(
  p_shop_id uuid default null,
  p_serialized_inventory_id uuid default null
)
returns void
language plpgsql
set search_path = ''
as $function$
declare
  unresolved_records text;
begin
  select pg_catalog.string_agg(
    pg_catalog.format(
      'shop_id=%s serialized_inventory_id=%s identifier_count=%s primary_count=%s identifiers=%s',
      unresolved_device.shop_id,
      unresolved_device.id,
      unresolved_device.identifier_count,
      unresolved_device.primary_count,
      unresolved_device.identifier_refs
    ),
    E'\n' order by unresolved_device.shop_id, unresolved_device.id
  )
  into unresolved_records
  from (
    select item.shop_id,
           item.id,
           pg_catalog.count(identifier.id) as identifier_count,
           pg_catalog.count(identifier.id) filter (where identifier.is_primary) as primary_count,
           coalesce(
             pg_catalog.string_agg(
               pg_catalog.format('%s:%s', identifier.id, identifier.identifier_type),
               ', ' order by identifier.id
             ),
             '(none)'
           ) as identifier_refs
    from public.serialized_inventory as item
    left join public.serialized_identifiers as identifier
      on identifier.shop_id = item.shop_id
     and identifier.serialized_inventory_id = item.id
    where (p_shop_id is null or item.shop_id = p_shop_id)
      and (p_serialized_inventory_id is null or item.id = p_serialized_inventory_id)
    group by item.shop_id, item.id
    having pg_catalog.count(identifier.id) filter (where identifier.is_primary) <> 1
  ) as unresolved_device;

  if unresolved_records is not null then
    raise exception using
      errcode = '55000',
      message = pg_catalog.format(
        'Cannot safely assign primary identifiers to existing serialized devices: %s. No identifier or history rows were changed. Explicitly map the primary identifier for each listed device, then rerun this migration.',
        unresolved_records
      );
  end if;
end;
$function$;

revoke all on function private.assert_serialized_identifier_primary_ready(uuid, uuid)
  from public, anon, authenticated, service_role;

do $migration$
begin
  perform private.assert_serialized_identifier_primary_ready();
end;
$migration$;

create unique index serialized_identifiers_one_primary_per_device_idx
  on public.serialized_identifiers (shop_id, serialized_inventory_id)
  where is_primary;

-- Verify the exact baseline foreign keys and their column order before
-- replacing them. This deliberately fails if the baseline schema has drifted.
do $migration$
declare
  expected_fk record;
  actual_fk pg_catalog.pg_constraint%rowtype;
  actual_child_columns name[];
  actual_parent_columns name[];
  unexpected_foreign_keys text;
begin
  for expected_fk in
    select *
    from (values
      (
        'public.serialized_identifiers'::regclass,
        'serialized_identifiers_shop_id_branch_id_serialized_invent_fkey',
        array['shop_id', 'branch_id', 'serialized_inventory_id']::name[],
        'public.serialized_inventory'::regclass,
        array['shop_id', 'branch_id', 'id']::name[]
      ),
      (
        'public.inventory_receipt_lines'::regclass,
        'inventory_receipt_lines_shop_id_branch_id_variant_id_seria_fkey',
        array['shop_id', 'branch_id', 'variant_id', 'serialized_inventory_id']::name[],
        'public.serialized_inventory'::regclass,
        array['shop_id', 'branch_id', 'variant_id', 'id']::name[]
      ),
      (
        'public.inventory_movements'::regclass,
        'inventory_movements_shop_id_branch_id_variant_id_serialize_fkey',
        array['shop_id', 'branch_id', 'variant_id', 'serialized_inventory_id']::name[],
        'public.serialized_inventory'::regclass,
        array['shop_id', 'branch_id', 'variant_id', 'id']::name[]
      )
    ) as expected(
      child_table, constraint_name, child_columns, parent_table, parent_columns
    )
  loop
    select constraint_row.*
      into actual_fk
    from pg_catalog.pg_constraint as constraint_row
    where constraint_row.conrelid = expected_fk.child_table
      and constraint_row.conname = expected_fk.constraint_name
      and constraint_row.contype = 'f';

    if not found then
      raise exception 'Expected baseline foreign key %.% is missing; no foreign keys were replaced.',
        expected_fk.child_table::text, expected_fk.constraint_name
        using errcode = '55000';
    end if;

    select pg_catalog.array_agg(attribute.attname::name order by key_column.ordinality)
      into actual_child_columns
    from pg_catalog.unnest(actual_fk.conkey) with ordinality as key_column(attnum, ordinality)
    join pg_catalog.pg_attribute as attribute
      on attribute.attrelid = actual_fk.conrelid
     and attribute.attnum = key_column.attnum;

    select pg_catalog.array_agg(attribute.attname::name order by key_column.ordinality)
      into actual_parent_columns
    from pg_catalog.unnest(actual_fk.confkey) with ordinality as key_column(attnum, ordinality)
    join pg_catalog.pg_attribute as attribute
      on attribute.attrelid = actual_fk.confrelid
     and attribute.attnum = key_column.attnum;

    if actual_fk.confrelid <> expected_fk.parent_table
      or actual_child_columns is distinct from expected_fk.child_columns
      or actual_parent_columns is distinct from expected_fk.parent_columns
      or actual_fk.confdeltype <> 'r'
      or not actual_fk.convalidated
      or actual_fk.condeferrable
    then
      raise exception 'Baseline foreign key %.% does not match the expected validated, nondeferrable column definition; no foreign keys were replaced.',
        expected_fk.child_table::text, expected_fk.constraint_name
        using errcode = '55000';
    end if;
  end loop;

  select pg_catalog.string_agg(
    constraint_row.conrelid::regclass::text || '.' || constraint_row.conname,
    ', ' order by constraint_row.conrelid::regclass::text, constraint_row.conname
  )
  into unexpected_foreign_keys
  from pg_catalog.pg_constraint as constraint_row
  where constraint_row.contype = 'f'
    and constraint_row.confrelid = 'public.serialized_inventory'::regclass
    and constraint_row.conrelid = any (array[
      'public.serialized_identifiers'::regclass,
      'public.inventory_receipt_lines'::regclass,
      'public.inventory_movements'::regclass
    ])
    and constraint_row.conname not in (
      'serialized_identifiers_shop_id_branch_id_serialized_invent_fkey',
      'inventory_receipt_lines_shop_id_branch_id_variant_id_seria_fkey',
      'inventory_movements_shop_id_branch_id_variant_id_serialize_fkey'
    );

  if unexpected_foreign_keys is not null then
    raise exception 'Unexpected foreign keys reference serialized_inventory: %. No foreign keys were replaced.',
      unexpected_foreign_keys
      using errcode = '55000';
  end if;

  execute 'alter table public.serialized_identifiers drop constraint serialized_identifiers_shop_id_branch_id_serialized_invent_fkey';
  execute 'alter table public.inventory_receipt_lines drop constraint inventory_receipt_lines_shop_id_branch_id_variant_id_seria_fkey';
  execute 'alter table public.inventory_movements drop constraint inventory_movements_shop_id_branch_id_variant_id_serialize_fkey';
end;
$migration$;

alter table public.serialized_identifiers
  add constraint serialized_identifiers_branch_snapshot_fk
    foreign key (shop_id, branch_id)
    references public.branches (shop_id, id) on delete restrict,
  add constraint serialized_identifiers_device_identity_fk
    foreign key (shop_id, serialized_inventory_id)
    references public.serialized_inventory (shop_id, id) on delete restrict;

alter table public.inventory_receipt_lines
  add constraint inventory_receipt_lines_device_identity_fk
    foreign key (shop_id, variant_id, serialized_inventory_id)
    references public.serialized_inventory (shop_id, variant_id, id)
    on delete restrict;

alter table public.inventory_movements
  add constraint inventory_movements_device_identity_fk
    foreign key (shop_id, variant_id, serialized_inventory_id)
    references public.serialized_inventory (shop_id, variant_id, id)
    on delete restrict,
  add column fx_resolution_id uuid;

alter table public.inventory_fx_resolutions
  add constraint inventory_fx_resolutions_shop_branch_id_key
    unique (shop_id, branch_id, id),
  add column suggested_fx_rate numeric(38, 16),
  add column suggested_rate_snapshot_id uuid
    references public.exchange_rate_snapshots (id) on delete restrict,
  add column suggested_rate_source text,
  add column suggested_rate_observed_at timestamptz,
  add constraint inventory_fx_resolutions_suggested_evidence_check check (
    (suggested_fx_rate is null
      and suggested_rate_snapshot_id is null
      and suggested_rate_source is null
      and suggested_rate_observed_at is null)
    or
    (suggested_fx_rate is not null
      and suggested_fx_rate > 0
      and suggested_fx_rate < 'Infinity'::numeric
      and suggested_rate_source is not null
      and char_length(btrim(suggested_rate_source)) between 1 and 120
      and suggested_rate_observed_at is not null)
  );

alter table public.inventory_movements
  add constraint inventory_movements_fx_resolution_fk
    foreign key (shop_id, branch_id, fx_resolution_id)
    references public.inventory_fx_resolutions (shop_id, branch_id, id)
    on delete restrict;

comment on column public.serialized_identifiers.branch_id is
  'Branch where this identifier was first recorded; authorization follows the device current branch.';
comment on column public.inventory_movements.fx_resolution_id is
  'Links both Pending-FX release movements to their immutable rate-resolution evidence.';
comment on column public.inventory_fx_resolutions.suggested_fx_rate is
  'The valid system rate available when a Manager or Owner accepted a manual override, when available.';

alter table public.inventory_operations
  drop constraint inventory_operations_type;

alter table public.inventory_operations
  add constraint inventory_operations_type check (
    operation_type in (
      'quantity_receipt',
      'serialized_receipt',
      'pending_fx_release'
    )
  );

drop policy if exists serialized_identifiers_read_authorized_branch
  on public.serialized_identifiers;
create policy serialized_identifiers_read_authorized_branch
  on public.serialized_identifiers for select to authenticated
  using (
    exists (
      select 1
      from public.serialized_inventory as item
      where item.shop_id = serialized_identifiers.shop_id
        and item.id = serialized_identifiers.serialized_inventory_id
        and (select private.can_access_branch(item.shop_id, item.branch_id))
    )
  );

create or replace function public.receive_serialized_inventory(
  p_shop_id uuid,
  p_branch_id uuid,
  p_idempotency_key text,
  p_receipt_kind text,
  p_supplier_name text,
  p_supplier_invoice_reference text,
  p_original_currency_code text,
  p_original_invoice_amount numeric,
  p_devices jsonb,
  p_rate_snapshot_id uuid default null,
  p_manual_rate numeric default null,
  p_manual_rate_source text default null,
  p_manual_rate_observed_at timestamptz default null,
  p_override_reason text default null,
  p_accept_pending_fx boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  current_user_id uuid := (select auth.uid());
  locked_member_id uuid;
  locked_branch_id uuid;
  locked_assignment_user_id uuid;
  shop_currency char(3);
  shop_currency_version integer;
  shop_minor_units smallint;
  original_currency char(3);
  original_minor_units smallint;
  source_amount_total numeric(38, 8);
  accepted_rate numeric(38, 16);
  accepted_rate_source text;
  accepted_rate_observed_at timestamptz;
  accepted_rate_at timestamptz;
  accepted_rate_snapshot_id uuid;
  accepted_by_user uuid;
  override_approved_by_user uuid;
  override_reason_value text;
  valuation_status_value public.inventory_valuation_status;
  v_factor numeric;
  request_value jsonb;
  operation_id_value uuid := gen_random_uuid();
  receipt_id_value uuid := gen_random_uuid();
  existing_payload jsonb;
  existing_receipt_id uuid;
  insert_count integer;
  target_minor numeric;
  converted_by_line jsonb := '{}'::jsonb;
  converted_total numeric(38, 8);
  device_value record;
  identifier_value record;
  device_identifiers jsonb;
  variant_id_value uuid;
  line_number_value integer;
  original_line_amount_value numeric(38, 8);
  converted_line_amount_value numeric(38, 8);
  unit_cost_value numeric(38, 10);
  serialized_inventory_id_value uuid;
  receipt_line_id_value uuid;
  tracking_mode_value text;
  current_balance public.inventory_balances%rowtype;
  new_quantity integer;
  new_carrying_value numeric(38, 8);
  new_average_unit_cost numeric(38, 10);
begin
  if current_user_id is null
    or not private.has_shop_role(
      p_shop_id,
      array['owner', 'manager', 'inventory_staff']::public.shop_role[]
    )
    or not private.can_access_branch(p_shop_id, p_branch_id)
  then
    raise exception 'You are not authorized to receive serialized stock in this branch.'
      using errcode = '42501';
  end if;

  select membership.user_id into locked_member_id
  from public.shop_memberships as membership
  where membership.shop_id = p_shop_id
    and membership.user_id = current_user_id
    and membership.status = 'active'
  for share;

  if not found then
    raise exception 'You are not authorized to receive serialized stock in this branch.'
      using errcode = '42501';
  end if;

  select branch.id into locked_branch_id
  from public.branches as branch
  where branch.shop_id = p_shop_id
    and branch.id = p_branch_id
    and branch.is_active
  for share;

  if not found then
    raise exception 'You are not authorized to receive serialized stock in this branch.'
      using errcode = '42501';
  end if;

  if not private.has_shop_role(p_shop_id, array['owner']::public.shop_role[]) then
    select assignment.user_id into locked_assignment_user_id
    from public.branch_memberships as assignment
    where assignment.shop_id = p_shop_id
      and assignment.branch_id = p_branch_id
      and assignment.user_id = current_user_id
    for share;

    if not found then
      raise exception 'You are not authorized to receive serialized stock in this branch.'
        using errcode = '42501';
    end if;
  end if;

  if not private.has_shop_role(
    p_shop_id,
    array['owner', 'manager', 'inventory_staff']::public.shop_role[]
  ) or not private.can_access_branch(p_shop_id, p_branch_id) then
    raise exception 'You are not authorized to receive serialized stock in this branch.'
      using errcode = '42501';
  end if;

  if p_idempotency_key is null
    or char_length(btrim(p_idempotency_key)) not between 8 and 120
  then
    raise exception 'A valid idempotency key is required.'
      using errcode = '22023';
  end if;

  if p_receipt_kind is null
    or p_receipt_kind not in ('supplier_invoice', 'manual_unknown_cost')
  then
    raise exception 'Unsupported inventory receipt kind.'
      using errcode = '22023';
  end if;

  if p_devices is null
    or pg_catalog.jsonb_typeof(p_devices) is distinct from 'array'
  then
    raise exception 'Devices must be a JSON array.'
      using errcode = '22023';
  end if;

  if pg_catalog.jsonb_array_length(p_devices) = 0
    or pg_catalog.jsonb_array_length(p_devices) > 500
  then
    raise exception 'Devices must be a nonempty array of at most 500 serialized items.'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(p_devices) as device(value)
    where pg_catalog.jsonb_typeof(device.value) is distinct from 'object'
      or pg_catalog.jsonb_typeof(device.value -> 'line_number') is distinct from 'number'
      or (device.value ->> 'line_number') !~ '^[1-9][0-9]*$'
      or (device.value ->> 'line_number')::numeric > 2147483647
      or pg_catalog.jsonb_typeof(device.value -> 'variant_id') is distinct from 'string'
      or (device.value ->> 'variant_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or pg_catalog.jsonb_typeof(device.value -> 'identifiers') is distinct from 'array'
  ) then
    raise exception 'Each device needs a positive line number, a valid variant, and one or more identifiers.'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(p_devices) as device(value)
    where case
      when pg_catalog.jsonb_typeof(device.value -> 'identifiers') = 'array'
        then pg_catalog.jsonb_array_length(device.value -> 'identifiers') = 0
          or pg_catalog.jsonb_array_length(device.value -> 'identifiers') > 32
      else false
    end
  ) then
    raise exception 'Each serialized device must have between one and 32 identifiers.'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(p_devices) as device(value)
    where exists (
      select 1
      from pg_catalog.jsonb_array_elements(device.value -> 'identifiers') as identifier(value)
      where pg_catalog.jsonb_typeof(identifier.value) is distinct from 'object'
        or pg_catalog.jsonb_typeof(identifier.value -> 'identifier_type') is distinct from 'string'
        or identifier.value ->> 'identifier_type' not in ('imei1', 'imei2', 'serial')
        or pg_catalog.jsonb_typeof(identifier.value -> 'raw_value') is distinct from 'string'
        or char_length(btrim(identifier.value ->> 'raw_value')) not between 1 and 160
        or pg_catalog.jsonb_typeof(identifier.value -> 'is_primary') is distinct from 'boolean'
        or (
          identifier.value ->> 'identifier_type' in ('imei1', 'imei2')
          and upper(normalize(btrim(identifier.value ->> 'raw_value'), NFKC))
            !~ '^[0-9]{15}$'
        )
    )
    or (
      select count(*)
      from pg_catalog.jsonb_array_elements(device.value -> 'identifiers') as identifier(value)
      where case
        when pg_catalog.jsonb_typeof(identifier.value -> 'is_primary') = 'boolean'
          then (identifier.value ->> 'is_primary')::boolean
        else false
      end
    ) <> 1
  ) then
    raise exception 'Every serialized device requires exactly one valid primary identifier.'
      using errcode = '22023';
  end if;

  if (
    select count(*) from pg_catalog.jsonb_array_elements(p_devices)
  ) <> (
    select count(distinct (device.value ->> 'line_number')::integer)
    from pg_catalog.jsonb_array_elements(p_devices) as device(value)
  ) then
    raise exception 'Serialized receipt line numbers must be unique.'
      using errcode = '22023';
  end if;

  if exists (
    select normalized_value
    from (
      select upper(normalize(btrim(identifier.value ->> 'raw_value'), NFKC)) as normalized_value
      from pg_catalog.jsonb_array_elements(p_devices) as device(value)
      cross join lateral pg_catalog.jsonb_array_elements(device.value -> 'identifiers') as identifier(value)
    ) as submitted
    group by normalized_value
    having count(*) > 1
  ) then
    raise exception 'A serialized identifier may appear only once in a receipt.'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(p_devices) as device(value)
    where not exists (
      select 1
      from public.product_variants as variant
      join public.products as product
        on product.shop_id = variant.shop_id
       and product.id = variant.product_id
      where variant.shop_id = p_shop_id
        and variant.id = (device.value ->> 'variant_id')::uuid
        and variant.archived_at is null
        and product.archived_at is null
        and product.tracking_mode = 'serialized'
    )
  ) then
    raise exception 'Every serialized receipt line must reference an active serialized variant in this shop.'
      using errcode = '22023';
  end if;

  select settings.operating_currency_code, settings.currency_version
    into shop_currency, shop_currency_version
  from public.shop_settings as settings
  where settings.shop_id = p_shop_id
  for update;

  if not found then
    raise exception 'Configure this shop currency before receiving inventory.'
      using errcode = '22023';
  end if;

  select currency.minor_units into shop_minor_units
  from public.currency_codes as currency
  where currency.code = shop_currency and currency.enabled;

  if shop_minor_units is null then
    raise exception 'The configured shop currency is unavailable.'
      using errcode = '22023';
  end if;

  if p_receipt_kind = 'supplier_invoice' then
    if p_original_currency_code is null
      or upper(btrim(p_original_currency_code)) !~ '^[A-Z]{3}$'
      or p_original_invoice_amount is null
      or p_original_invoice_amount < 0
      or p_original_invoice_amount >= 'Infinity'::numeric
    then
      raise exception 'Supplier invoice currency and amount must be valid.'
        using errcode = '22023';
    end if;

    original_currency := upper(btrim(p_original_currency_code))::char(3);

    select currency.minor_units into original_minor_units
    from public.currency_codes as currency
    where currency.code = original_currency and currency.enabled;

    if original_minor_units is null
      or p_original_invoice_amount <> round(p_original_invoice_amount, original_minor_units)
    then
      raise exception 'Supplier invoice amount must use a supported currency and its exact precision.'
        using errcode = '22023';
    end if;

    if exists (
      select 1
      from pg_catalog.jsonb_array_elements(p_devices) as device(value)
      where pg_catalog.jsonb_typeof(device.value -> 'original_line_amount') is distinct from 'number'
        or (device.value ->> 'original_line_amount')::numeric < 0
        or (device.value ->> 'original_line_amount')::numeric >= 'Infinity'::numeric
        or (device.value ->> 'original_line_amount')::numeric <> round(
          (device.value ->> 'original_line_amount')::numeric,
          original_minor_units
        )
    ) then
      raise exception 'Every invoice device needs a nonnegative line amount at the original currency precision.'
        using errcode = '22023';
    end if;

    select sum((device.value ->> 'original_line_amount')::numeric)
      into source_amount_total
    from pg_catalog.jsonb_array_elements(p_devices) as device(value);

    if source_amount_total is distinct from p_original_invoice_amount then
      raise exception 'Serialized line amounts must reconcile exactly to the supplier invoice.'
        using errcode = '22023';
    end if;
    valuation_status_value := 'known_cost';
  else
    if p_original_currency_code is not null
      or p_original_invoice_amount is not null
      or exists (
        select 1
        from pg_catalog.jsonb_array_elements(p_devices) as device(value)
        where device.value ? 'original_line_amount'
          and pg_catalog.jsonb_typeof(device.value -> 'original_line_amount') is distinct from 'null'
      )
    then
      raise exception 'Unknown-cost serialized receipts cannot claim invoice or line amounts.'
        using errcode = '22023';
    end if;
  end if;

  request_value := pg_catalog.jsonb_build_object(
    'shop_id', p_shop_id,
    'branch_id', p_branch_id,
    'receipt_kind', p_receipt_kind,
    'supplier_name', p_supplier_name,
    'supplier_invoice_reference', p_supplier_invoice_reference,
    'original_currency_code', original_currency,
    'original_invoice_amount', p_original_invoice_amount,
    'devices', p_devices,
    'rate_snapshot_id', p_rate_snapshot_id,
    'manual_rate', p_manual_rate,
    'manual_rate_source', p_manual_rate_source,
    'manual_rate_observed_at', p_manual_rate_observed_at,
    'override_reason', p_override_reason,
    'accept_pending_fx', p_accept_pending_fx
  );

  insert into public.inventory_operations (
    id, shop_id, branch_id, operation_type, actor_id, idempotency_key,
    request_payload, result_receipt_id, valuation_currency_code,
    currency_version
  ) values (
    operation_id_value, p_shop_id, p_branch_id, 'serialized_receipt',
    current_user_id, btrim(p_idempotency_key), request_value,
    receipt_id_value, shop_currency, shop_currency_version
  )
  on conflict (shop_id, actor_id, idempotency_key) do nothing;

  get diagnostics insert_count = row_count;
  if insert_count = 0 then
    select operation.request_payload, operation.result_receipt_id
      into existing_payload, existing_receipt_id
    from public.inventory_operations as operation
    where operation.shop_id = p_shop_id
      and operation.actor_id = current_user_id
      and operation.idempotency_key = btrim(p_idempotency_key)
    for update;

    if existing_payload is distinct from request_value then
      raise exception 'The idempotency key was already used for different serialized receipt contents.'
        using errcode = '22023';
    end if;

    return existing_receipt_id;
  end if;

  -- Use wall-clock time only after the shop-settings lock and the
  -- idempotency conflict/replay path have completed. A transaction may have
  -- waited long enough for a previously valid FX snapshot to expire.
  accepted_rate_at := clock_timestamp();

  if p_receipt_kind = 'supplier_invoice' then
    if original_currency = shop_currency then
      if p_rate_snapshot_id is not null or p_manual_rate is not null
        or p_manual_rate_source is not null
        or p_manual_rate_observed_at is not null
        or p_override_reason is not null
        or p_accept_pending_fx
      then
        raise exception 'Same-currency serialized receipts use the identity rate.'
          using errcode = '22023';
      end if;
      accepted_rate := 1;
      accepted_rate_source := 'identity';
      accepted_rate_observed_at := accepted_rate_at;
      accepted_by_user := current_user_id;
    elsif p_rate_snapshot_id is not null then
      if p_manual_rate is not null or p_manual_rate_source is not null
        or p_manual_rate_observed_at is not null or p_override_reason is not null
        or p_accept_pending_fx
      then
        raise exception 'Choose either a system rate, an Owner manual override, or explicit Pending FX.'
          using errcode = '22023';
      end if;

      select snapshot.rate_to_currency, snapshot.rate_source,
             snapshot.observed_at, snapshot.id
        into accepted_rate, accepted_rate_source,
             accepted_rate_observed_at, accepted_rate_snapshot_id
      from public.exchange_rate_snapshots as snapshot
      where snapshot.id = p_rate_snapshot_id
        and snapshot.from_currency_code = original_currency
        and snapshot.to_currency_code = shop_currency
        and snapshot.observed_at <= accepted_rate_at
        and snapshot.fetched_at <= accepted_rate_at
        and snapshot.valid_until > accepted_rate_at;

      if not found then
        raise exception 'The exchange-rate snapshot is missing, expired, or has the wrong currency direction.'
          using errcode = '22023';
      end if;
      accepted_by_user := current_user_id;
    elsif p_manual_rate is not null then
      if not private.has_shop_role(p_shop_id, array['owner']::public.shop_role[]) then
        raise exception 'Only an active shop owner may approve a manual exchange-rate override during receipt.'
          using errcode = '42501';
      end if;

      if p_accept_pending_fx
        or p_manual_rate <= 0 or p_manual_rate >= 'Infinity'::numeric
        or p_manual_rate <> round(p_manual_rate, 16)
        or p_manual_rate_source is null
        or char_length(btrim(p_manual_rate_source)) not between 1 and 120
        or p_manual_rate_observed_at is null
        or p_manual_rate_observed_at > accepted_rate_at
        or p_override_reason is null
        or char_length(btrim(p_override_reason)) not between 10 and 1000
      then
        raise exception 'Manual overrides require a valid rate, source, observation time, and reason.'
          using errcode = '22023';
      end if;

      accepted_rate := p_manual_rate;
      accepted_rate_source := 'manual_override: ' || btrim(p_manual_rate_source);
      accepted_rate_observed_at := p_manual_rate_observed_at;
      accepted_by_user := current_user_id;
      override_approved_by_user := current_user_id;
      override_reason_value := btrim(p_override_reason);
    elsif p_accept_pending_fx then
      if p_manual_rate_source is not null
        or p_manual_rate_observed_at is not null
        or p_override_reason is not null
      then
        raise exception 'Pending FX receipts cannot include unaccepted rate evidence.'
          using errcode = '22023';
      end if;
      valuation_status_value := 'pending_fx';
    else
      raise exception 'A valid system rate, authorized override, or explicit Pending FX receipt is required.'
        using errcode = '22023';
    end if;
  else
    if p_rate_snapshot_id is not null or p_manual_rate is not null
      or p_manual_rate_source is not null or p_manual_rate_observed_at is not null
      or p_override_reason is not null or p_accept_pending_fx
    then
      raise exception 'Unknown-cost serialized receipts do not accept exchange-rate evidence.'
        using errcode = '22023';
    end if;
    valuation_status_value := 'unknown_cost';
  end if;

  if valuation_status_value = 'known_cost' then
    v_factor := power(10::numeric, shop_minor_units::numeric);
    target_minor := round(
      p_original_invoice_amount * accepted_rate,
      shop_minor_units
    ) * v_factor;

    with raw_lines as (
      select
        (device.value ->> 'line_number')::integer as line_number,
        (device.value ->> 'original_line_amount')::numeric as original_line_amount
      from pg_catalog.jsonb_array_elements(p_devices) as device(value)
    ), exact_minor as (
      select raw_lines.*,
             original_line_amount * accepted_rate * v_factor as exact_minor_units
      from raw_lines
    ), base_minor as (
      select exact_minor.*,
             trunc(exact_minor_units) as base_minor_units,
             exact_minor_units - trunc(exact_minor_units) as fractional_remainder
      from exact_minor
    ), residual as (
      select target_minor - sum(base_minor_units) as residual_units
      from base_minor
    ), ranked as (
      select base_minor.*,
             pg_catalog.row_number() over (
               order by fractional_remainder desc, line_number asc
             ) as remainder_rank,
             residual.residual_units
      from base_minor cross join residual
    ), allocated as (
      select ranked.*,
             (base_minor_units +
               case when remainder_rank <= residual_units then 1 else 0 end
             ) / v_factor as converted_line_amount_shop
      from ranked
    )
    select pg_catalog.jsonb_object_agg(
      line_number::text, converted_line_amount_shop
    ), sum(converted_line_amount_shop)
      into converted_by_line, converted_total
    from allocated;

    if converted_total is distinct from target_minor / v_factor then
      raise exception 'Converted serialized invoice lines did not reconcile exactly.'
        using errcode = '22003';
    end if;
  else
    converted_by_line := '{}'::jsonb;
    converted_total := null;
  end if;

  insert into public.inventory_receipts (
    id, shop_id, branch_id, operation_id, receipt_kind,
    supplier_name_snapshot, supplier_invoice_reference,
    original_currency_code, original_invoice_amount,
    valuation_currency_code, accepted_fx_rate, rate_snapshot_id,
    rate_source, rate_observed_at, rate_accepted_at, accepted_by,
    override_approved_by, override_reason,
    converted_invoice_amount_shop, valuation_status, created_by
  ) values (
    receipt_id_value, p_shop_id, p_branch_id, operation_id_value,
    p_receipt_kind, nullif(btrim(p_supplier_name), ''),
    nullif(btrim(p_supplier_invoice_reference), ''),
    original_currency, p_original_invoice_amount,
    shop_currency, accepted_rate, accepted_rate_snapshot_id,
    accepted_rate_source, accepted_rate_observed_at,
    case when accepted_rate is null then null else accepted_rate_at end,
    accepted_by_user, override_approved_by_user, override_reason_value,
    converted_total, valuation_status_value, current_user_id
  );

  for device_value in
    select device.value
    from pg_catalog.jsonb_array_elements(p_devices) as device(value)
    order by (device.value ->> 'line_number')::integer
  loop
    line_number_value := (device_value.value ->> 'line_number')::integer;
    variant_id_value := (device_value.value ->> 'variant_id')::uuid;
    original_line_amount_value := nullif(
      device_value.value ->> 'original_line_amount', ''
    )::numeric;
    converted_line_amount_value := nullif(
      converted_by_line ->> line_number_value::text, ''
    )::numeric;

    if valuation_status_value = 'known_cost' then
      unit_cost_value := round(converted_line_amount_value, 10);
    else
      unit_cost_value := null;
    end if;

    insert into public.serialized_inventory (
      shop_id, branch_id, variant_id, availability_status,
      valuation_status, valuation_currency_code, unit_cost_shop,
      created_by, updated_by
    ) values (
      p_shop_id, p_branch_id, variant_id_value,
      case when valuation_status_value = 'pending_fx'
           then 'pending_fx'::public.inventory_availability_status
           else 'available'::public.inventory_availability_status end,
      valuation_status_value, shop_currency, unit_cost_value,
      current_user_id, current_user_id
    ) returning id into serialized_inventory_id_value;

    device_identifiers := device_value.value -> 'identifiers';
    for identifier_value in
      select identifier.value
      from pg_catalog.jsonb_array_elements(device_identifiers) as identifier(value)
    loop
      insert into public.serialized_identifiers (
        shop_id, branch_id, serialized_inventory_id,
        identifier_type, raw_value, is_primary, created_by
      ) values (
        p_shop_id, p_branch_id, serialized_inventory_id_value,
        identifier_value.value ->> 'identifier_type',
        btrim(identifier_value.value ->> 'raw_value'),
        (identifier_value.value ->> 'is_primary')::boolean,
        current_user_id
      );
    end loop;

    insert into public.inventory_receipt_lines (
      shop_id, branch_id, receipt_id, line_number, variant_id,
      serialized_inventory_id, quantity, original_line_amount,
      converted_line_amount_shop, unit_cost_shop, valuation_status,
      created_by
    ) values (
      p_shop_id, p_branch_id, receipt_id_value, line_number_value,
      variant_id_value, serialized_inventory_id_value, 1,
      original_line_amount_value, converted_line_amount_value,
      unit_cost_value, valuation_status_value, current_user_id
    ) returning id into receipt_line_id_value;

    insert into public.inventory_balances (
      shop_id, branch_id, variant_id, valuation_status,
      valuation_currency_code, on_hand_qty, available_qty,
      carrying_value_shop, average_unit_cost_shop, updated_by
    ) values (
      p_shop_id, p_branch_id, variant_id_value, valuation_status_value,
      shop_currency, 0, 0,
      case when valuation_status_value = 'known_cost' then 0 else null end,
      case when valuation_status_value = 'known_cost' then 0 else null end,
      current_user_id
    )
    on conflict (shop_id, branch_id, variant_id, valuation_status) do nothing;

    select balance.* into current_balance
    from public.inventory_balances as balance
    where balance.shop_id = p_shop_id
      and balance.branch_id = p_branch_id
      and balance.variant_id = variant_id_value
      and balance.valuation_status = valuation_status_value
    for update;

    new_quantity := current_balance.on_hand_qty + 1;
    if new_quantity < current_balance.on_hand_qty then
      raise exception 'Inventory quantity exceeds the supported range.'
        using errcode = '22003';
    end if;

    if valuation_status_value = 'known_cost' then
      new_carrying_value := current_balance.carrying_value_shop
        + converted_line_amount_value;
      if new_carrying_value >= 'Infinity'::numeric then
        raise exception 'Inventory carrying value exceeds the supported range.'
          using errcode = '22003';
      end if;
      new_average_unit_cost := round(new_carrying_value / new_quantity, 10);

      update public.inventory_balances as balance
      set on_hand_qty = new_quantity,
          available_qty = balance.available_qty + 1,
          carrying_value_shop = new_carrying_value,
          average_unit_cost_shop = new_average_unit_cost,
          updated_at = clock_timestamp(),
          updated_by = current_user_id
      where balance.id = current_balance.id;
    else
      update public.inventory_balances as balance
      set on_hand_qty = new_quantity,
          available_qty = balance.available_qty
            + case when valuation_status_value = 'unknown_cost' then 1 else 0 end,
          updated_at = clock_timestamp(),
          updated_by = current_user_id
      where balance.id = current_balance.id;
    end if;

    insert into public.inventory_movements (
      shop_id, branch_id, operation_id, receipt_line_id, variant_id,
      serialized_inventory_id, movement_type, valuation_status,
      valuation_currency_code, on_hand_delta, available_delta,
      unit_cost_shop, extended_cost_shop, actor_id, line_number
    ) values (
      p_shop_id, p_branch_id, operation_id_value, receipt_line_id_value,
      variant_id_value, serialized_inventory_id_value,
      case when valuation_status_value = 'pending_fx'
           then 'pending_fx_receipt'::public.inventory_movement_kind
           else 'receipt'::public.inventory_movement_kind end,
      valuation_status_value, shop_currency, 1,
      case when valuation_status_value = 'pending_fx' then 0 else 1 end,
      unit_cost_value, converted_line_amount_value,
      current_user_id, line_number_value
    );
  end loop;

  update public.shop_settings as settings
  set currency_locked_at = coalesce(settings.currency_locked_at, clock_timestamp()),
      updated_at = clock_timestamp(),
      updated_by = current_user_id
  where settings.shop_id = p_shop_id;

  return receipt_id_value;
end;
$function$;

revoke all on function public.receive_serialized_inventory(
  uuid, uuid, text, text, text, text, text, numeric, jsonb,
  uuid, numeric, text, timestamptz, text, boolean
) from public, anon, service_role;
grant execute on function public.receive_serialized_inventory(
  uuid, uuid, text, text, text, text, text, numeric, jsonb,
  uuid, numeric, text, timestamptz, text, boolean
) to authenticated;

create or replace function public.release_pending_fx_receipt(
  p_shop_id uuid,
  p_branch_id uuid,
  p_receipt_id uuid,
  p_idempotency_key text,
  p_rate_snapshot_id uuid default null,
  p_manual_rate numeric default null,
  p_manual_rate_source text default null,
  p_manual_rate_observed_at timestamptz default null,
  p_override_reason text default null,
  p_suggested_rate_snapshot_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  current_user_id uuid := (select auth.uid());
  locked_member_id uuid;
  locked_branch_id uuid;
  locked_assignment_user_id uuid;
  receipt_row public.inventory_receipts%rowtype;
  shop_currency char(3);
  shop_currency_version integer;
  shop_minor_units smallint;
  accepted_rate numeric(38, 16);
  accepted_rate_source text;
  accepted_rate_observed_at timestamptz;
  accepted_rate_at timestamptz := clock_timestamp();
  accepted_rate_snapshot_id uuid;
  accepted_by_user uuid;
  override_approved_by_user uuid;
  override_reason_value text;
  suggested_rate numeric(38, 16);
  suggested_snapshot_id uuid;
  suggested_source text;
  suggested_observed_at timestamptz;
  request_value jsonb;
  operation_id_value uuid := gen_random_uuid();
  existing_operation_id uuid;
  existing_payload jsonb;
  existing_receipt_id uuid;
  insert_count integer;
  source_amount_total numeric(38, 8);
  target_minor numeric;
  v_factor numeric;
  allocated_lines jsonb;
  converted_total numeric(38, 8);
  line_value record;
  current_balance public.inventory_balances%rowtype;
  resolution_id_value uuid;
  line_number_value integer;
  movement_index integer := 0;
  converted_line_amount_value numeric(38, 8);
  unit_cost_value numeric(38, 10);
  new_quantity integer;
  new_carrying_value numeric(38, 8);
  new_average_unit_cost numeric(38, 10);
begin
  if current_user_id is null
    or not private.has_shop_role(
      p_shop_id,
      array['owner', 'manager', 'inventory_staff']::public.shop_role[]
    )
    or not private.can_access_branch(p_shop_id, p_branch_id)
  then
    raise exception 'You are not authorized to release Pending-FX inventory in this branch.'
      using errcode = '42501';
  end if;

  select membership.user_id into locked_member_id
  from public.shop_memberships as membership
  where membership.shop_id = p_shop_id
    and membership.user_id = current_user_id
    and membership.status = 'active'
  for share;

  if not found then
    raise exception 'You are not authorized to release Pending-FX inventory in this branch.'
      using errcode = '42501';
  end if;

  select branch.id into locked_branch_id
  from public.branches as branch
  where branch.shop_id = p_shop_id
    and branch.id = p_branch_id
    and branch.is_active
  for share;

  if not found then
    raise exception 'You are not authorized to release Pending-FX inventory in this branch.'
      using errcode = '42501';
  end if;

  if not private.has_shop_role(p_shop_id, array['owner']::public.shop_role[]) then
    select assignment.user_id into locked_assignment_user_id
    from public.branch_memberships as assignment
    where assignment.shop_id = p_shop_id
      and assignment.branch_id = p_branch_id
      and assignment.user_id = current_user_id
    for share;

    if not found then
      raise exception 'You are not authorized to release Pending-FX inventory in this branch.'
        using errcode = '42501';
    end if;
  end if;

  if not private.has_shop_role(
    p_shop_id,
    array['owner', 'manager', 'inventory_staff']::public.shop_role[]
  ) or not private.can_access_branch(p_shop_id, p_branch_id) then
    raise exception 'You are not authorized to release Pending-FX inventory in this branch.'
      using errcode = '42501';
  end if;

  if p_idempotency_key is null
    or char_length(btrim(p_idempotency_key)) not between 8 and 120
  then
    raise exception 'A valid idempotency key is required.'
      using errcode = '22023';
  end if;

  select settings.operating_currency_code, settings.currency_version
    into shop_currency, shop_currency_version
  from public.shop_settings as settings
  where settings.shop_id = p_shop_id
  for update;

  if not found then
    raise exception 'The shop operating currency is unavailable.'
      using errcode = '22023';
  end if;

  select receipt.* into receipt_row
  from public.inventory_receipts as receipt
  where receipt.shop_id = p_shop_id
    and receipt.branch_id = p_branch_id
    and receipt.id = p_receipt_id
  for update;

  if not found then
    raise exception 'The receipt is unavailable in this authorized branch.'
      using errcode = '42501';
  end if;

  request_value := pg_catalog.jsonb_build_object(
    'shop_id', p_shop_id,
    'branch_id', p_branch_id,
    'receipt_id', p_receipt_id,
    'rate_snapshot_id', p_rate_snapshot_id,
    'manual_rate', p_manual_rate,
    'manual_rate_source', p_manual_rate_source,
    'manual_rate_observed_at', p_manual_rate_observed_at,
    'override_reason', p_override_reason,
    'suggested_rate_snapshot_id', p_suggested_rate_snapshot_id
  );

  insert into public.inventory_operations (
    id, shop_id, branch_id, operation_type, actor_id, idempotency_key,
    request_payload, result_receipt_id, valuation_currency_code,
    currency_version
  ) values (
    operation_id_value, p_shop_id, p_branch_id, 'pending_fx_release',
    current_user_id, btrim(p_idempotency_key), request_value,
    p_receipt_id, shop_currency, shop_currency_version
  )
  on conflict (shop_id, actor_id, idempotency_key) do nothing;

  get diagnostics insert_count = row_count;
  if insert_count = 0 then
    select operation.id, operation.request_payload, operation.result_receipt_id
      into existing_operation_id, existing_payload, existing_receipt_id
    from public.inventory_operations as operation
    where operation.shop_id = p_shop_id
      and operation.actor_id = current_user_id
      and operation.idempotency_key = btrim(p_idempotency_key)
    for update;

    if existing_payload is distinct from request_value then
      raise exception 'The idempotency key was already used for different Pending-FX release contents.'
        using errcode = '22023';
    end if;

    return existing_operation_id;
  end if;

  if receipt_row.receipt_kind <> 'supplier_invoice'
    or receipt_row.valuation_status <> 'pending_fx'
    or receipt_row.original_currency_code is null
    or receipt_row.original_invoice_amount is null
    or receipt_row.valuation_currency_code <> shop_currency
    or receipt_row.original_currency_code = shop_currency
  then
    raise exception 'Only an unreleased foreign-currency Pending-FX supplier receipt can be released.'
      using errcode = '22023';
  end if;

  select count(*)::integer,
         sum(line.original_line_amount)
    into insert_count, source_amount_total
  from public.inventory_receipt_lines as line
  where line.shop_id = p_shop_id
    and line.branch_id = p_branch_id
    and line.receipt_id = p_receipt_id
    and line.valuation_status = 'pending_fx'
    and line.original_line_amount is not null
    and line.converted_line_amount_shop is null
    and line.unit_cost_shop is null;

  if insert_count = 0
    or source_amount_total is distinct from receipt_row.original_invoice_amount
  then
    raise exception 'Pending-FX receipt lines are incomplete or do not reconcile to the invoice.'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.inventory_receipt_lines as line
    where line.shop_id = p_shop_id
      and line.branch_id = p_branch_id
      and line.receipt_id = p_receipt_id
      and line.valuation_status <> 'pending_fx'
  ) or exists (
    select 1
    from public.inventory_fx_resolutions as resolution
    join public.inventory_receipt_lines as line
      on line.shop_id = resolution.shop_id
     and line.branch_id = resolution.branch_id
     and line.id = resolution.receipt_line_id
    where line.shop_id = p_shop_id
      and line.branch_id = p_branch_id
      and line.receipt_id = p_receipt_id
  ) then
    raise exception 'The Pending-FX receipt is partially or already resolved.'
      using errcode = '22023';
  end if;

  -- Acceptance is timed after the receipt and branch locks, so rate freshness
  -- is evaluated at the actual release decision rather than before lock waits.
  accepted_rate_at := clock_timestamp();

  select currency.minor_units into shop_minor_units
  from public.currency_codes as currency
  where currency.code = shop_currency and currency.enabled;

  if shop_minor_units is null then
    raise exception 'The configured shop currency is unavailable.'
      using errcode = '22023';
  end if;

  if p_rate_snapshot_id is not null then
    if p_manual_rate is not null or p_manual_rate_source is not null
      or p_manual_rate_observed_at is not null or p_override_reason is not null
      or p_suggested_rate_snapshot_id is not null
    then
      raise exception 'Choose either a system rate snapshot or a manual override.'
        using errcode = '22023';
    end if;

    select snapshot.rate_to_currency, snapshot.rate_source,
           snapshot.observed_at, snapshot.id
      into accepted_rate, accepted_rate_source,
           accepted_rate_observed_at, accepted_rate_snapshot_id
    from public.exchange_rate_snapshots as snapshot
    where snapshot.id = p_rate_snapshot_id
      and snapshot.from_currency_code = receipt_row.original_currency_code
      and snapshot.to_currency_code = shop_currency
      and snapshot.observed_at <= accepted_rate_at
      and snapshot.fetched_at <= accepted_rate_at
      and snapshot.valid_until > accepted_rate_at;

    if not found then
      raise exception 'The exchange-rate snapshot is missing, expired, or has the wrong currency direction.'
        using errcode = '22023';
    end if;
    accepted_by_user := current_user_id;
  elsif p_manual_rate is not null then
    if not private.has_shop_role(
      p_shop_id,
      array['owner', 'manager']::public.shop_role[]
    ) then
      raise exception 'Only an active Manager or Owner may approve a manual Pending-FX override.'
        using errcode = '42501';
    end if;

    if p_manual_rate <= 0 or p_manual_rate >= 'Infinity'::numeric
      or p_manual_rate <> round(p_manual_rate, 16)
      or p_manual_rate_source is null
      or char_length(btrim(p_manual_rate_source)) not between 1 and 120
      or p_manual_rate_observed_at is null
      or p_manual_rate_observed_at > accepted_rate_at
      or p_override_reason is null
      or char_length(btrim(p_override_reason)) not between 10 and 1000
    then
      raise exception 'Manual Pending-FX overrides require an exact accepted rate, source, observation time, and reason.'
        using errcode = '22023';
    end if;

    accepted_rate := p_manual_rate;
    accepted_rate_source := 'manual_override: ' || btrim(p_manual_rate_source);
    accepted_rate_observed_at := p_manual_rate_observed_at;
    accepted_by_user := current_user_id;
    override_approved_by_user := current_user_id;
    override_reason_value := btrim(p_override_reason);

    if p_suggested_rate_snapshot_id is not null then
      select snapshot.rate_to_currency, snapshot.rate_source,
             snapshot.observed_at, snapshot.id
        into suggested_rate, suggested_source,
             suggested_observed_at, suggested_snapshot_id
      from public.exchange_rate_snapshots as snapshot
      where snapshot.id = p_suggested_rate_snapshot_id
        and snapshot.from_currency_code = receipt_row.original_currency_code
        and snapshot.to_currency_code = shop_currency
        and snapshot.observed_at <= accepted_rate_at
        and snapshot.fetched_at <= accepted_rate_at
        and snapshot.valid_until > accepted_rate_at;

      if not found then
        raise exception 'The suggested exchange-rate snapshot is missing, expired, or has the wrong currency direction.'
          using errcode = '22023';
      end if;
    else
      select snapshot.rate_to_currency, snapshot.rate_source,
             snapshot.observed_at, snapshot.id
        into suggested_rate, suggested_source,
             suggested_observed_at, suggested_snapshot_id
      from public.exchange_rate_snapshots as snapshot
      where snapshot.from_currency_code = receipt_row.original_currency_code
        and snapshot.to_currency_code = shop_currency
        and snapshot.observed_at <= accepted_rate_at
        and snapshot.fetched_at <= accepted_rate_at
        and snapshot.valid_until > accepted_rate_at
      order by snapshot.fetched_at desc, snapshot.observed_at desc, snapshot.id
      limit 1;
    end if;
  else
    raise exception 'A valid system rate or authorized Manager/Owner manual override is required.'
      using errcode = '22023';
  end if;

  v_factor := power(10::numeric, shop_minor_units::numeric);
  target_minor := round(
    receipt_row.original_invoice_amount * accepted_rate,
    shop_minor_units
  ) * v_factor;

  with raw_lines as (
    select line.id as receipt_line_id,
           line.serialized_inventory_id,
           line.variant_id,
           line.line_number,
           line.quantity,
           line.original_line_amount
    from public.inventory_receipt_lines as line
    where line.shop_id = p_shop_id
      and line.branch_id = p_branch_id
      and line.receipt_id = p_receipt_id
      and line.valuation_status = 'pending_fx'
  ), exact_minor as (
    select raw_lines.*,
           original_line_amount * accepted_rate * v_factor as exact_minor_units
    from raw_lines
  ), base_minor as (
    select exact_minor.*,
           trunc(exact_minor_units) as base_minor_units,
           exact_minor_units - trunc(exact_minor_units) as fractional_remainder
    from exact_minor
  ), residual as (
    select target_minor - sum(base_minor_units) as residual_units
    from base_minor
  ), ranked as (
    select base_minor.*,
           pg_catalog.row_number() over (
             order by fractional_remainder desc, line_number asc
           ) as remainder_rank,
           residual.residual_units
    from base_minor cross join residual
  ), allocated as (
    select ranked.*,
           (base_minor_units +
             case when remainder_rank <= residual_units then 1 else 0 end
           ) / v_factor as converted_line_amount_shop
    from ranked
  )
  select pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'receipt_line_id', receipt_line_id,
      'serialized_inventory_id', serialized_inventory_id,
      'variant_id', variant_id,
      'line_number', line_number,
      'quantity', quantity,
      'original_line_amount', original_line_amount,
      'converted_line_amount_shop', converted_line_amount_shop
    ) order by line_number
  ), sum(converted_line_amount_shop)
    into allocated_lines, converted_total
  from allocated;

  if converted_total is distinct from target_minor / v_factor then
    raise exception 'Pending-FX line allocations did not reconcile exactly to the invoice.'
      using errcode = '22003';
  end if;

  for line_value in
    select item.value
    from pg_catalog.jsonb_array_elements(allocated_lines) as item(value)
    order by (item.value ->> 'line_number')::integer
  loop
    line_number_value := (line_value.value ->> 'line_number')::integer;
    converted_line_amount_value :=
      (line_value.value ->> 'converted_line_amount_shop')::numeric;
    unit_cost_value := round(
      converted_line_amount_value / (line_value.value ->> 'quantity')::integer,
      10
    );
    movement_index := movement_index + 1;

    if line_value.value ->> 'serialized_inventory_id' is not null then
      update public.serialized_inventory as item
      set availability_status = 'available',
          valuation_status = 'known_cost',
          unit_cost_shop = unit_cost_value,
          updated_at = clock_timestamp(),
          updated_by = current_user_id
      where item.shop_id = p_shop_id
        and item.branch_id = p_branch_id
        and item.variant_id = (line_value.value ->> 'variant_id')::uuid
        and item.id = (line_value.value ->> 'serialized_inventory_id')::uuid
        and item.availability_status = 'pending_fx'
        and item.valuation_status = 'pending_fx';

      if not found then
        raise exception 'A serialized device is no longer in the expected Pending-FX state.'
          using errcode = '22023';
      end if;
    end if;

    update public.inventory_balances as balance
    set on_hand_qty = balance.on_hand_qty - (line_value.value ->> 'quantity')::integer,
        updated_at = clock_timestamp(),
        updated_by = current_user_id
    where balance.shop_id = p_shop_id
      and balance.branch_id = p_branch_id
      and balance.variant_id = (line_value.value ->> 'variant_id')::uuid
      and balance.valuation_status = 'pending_fx'
      and balance.on_hand_qty >= (line_value.value ->> 'quantity')::integer;

    if not found then
      raise exception 'Pending-FX balance is missing or smaller than the receipt line.'
        using errcode = '22023';
    end if;

    insert into public.inventory_balances (
      shop_id, branch_id, variant_id, valuation_status,
      valuation_currency_code, on_hand_qty, available_qty,
      carrying_value_shop, average_unit_cost_shop, updated_by
    ) values (
      p_shop_id, p_branch_id,
      (line_value.value ->> 'variant_id')::uuid,
      'known_cost', shop_currency, 0, 0, 0, 0, current_user_id
    )
    on conflict (shop_id, branch_id, variant_id, valuation_status) do nothing;

    select balance.* into current_balance
    from public.inventory_balances as balance
    where balance.shop_id = p_shop_id
      and balance.branch_id = p_branch_id
      and balance.variant_id = (line_value.value ->> 'variant_id')::uuid
      and balance.valuation_status = 'known_cost'
    for update;

    new_quantity := current_balance.on_hand_qty
      + (line_value.value ->> 'quantity')::integer;
    if new_quantity < current_balance.on_hand_qty then
      raise exception 'Inventory quantity exceeds the supported range.'
        using errcode = '22003';
    end if;

    new_carrying_value := current_balance.carrying_value_shop
      + converted_line_amount_value;
    if new_carrying_value >= 'Infinity'::numeric then
      raise exception 'Inventory carrying value exceeds the supported range.'
        using errcode = '22003';
    end if;
    new_average_unit_cost := round(new_carrying_value / new_quantity, 10);

    update public.inventory_balances as balance
    set on_hand_qty = new_quantity,
        available_qty = balance.available_qty
          + (line_value.value ->> 'quantity')::integer,
        carrying_value_shop = new_carrying_value,
        average_unit_cost_shop = new_average_unit_cost,
        updated_at = clock_timestamp(),
        updated_by = current_user_id
    where balance.id = current_balance.id;

    insert into public.inventory_fx_resolutions (
      shop_id, branch_id, receipt_line_id, operation_id,
      original_currency_code, original_line_amount,
      valuation_currency_code, accepted_fx_rate,
      rate_snapshot_id, rate_source, rate_observed_at,
      rate_accepted_at, accepted_by,
      override_approved_by, override_reason,
      converted_line_amount_shop, created_by,
      suggested_fx_rate, suggested_rate_snapshot_id,
      suggested_rate_source, suggested_rate_observed_at
    ) values (
      p_shop_id, p_branch_id,
      (line_value.value ->> 'receipt_line_id')::uuid,
      operation_id_value, receipt_row.original_currency_code,
      (line_value.value ->> 'original_line_amount')::numeric,
      shop_currency, accepted_rate,
      accepted_rate_snapshot_id, accepted_rate_source,
      accepted_rate_observed_at, accepted_rate_at, accepted_by_user,
      override_approved_by_user, override_reason_value,
      converted_line_amount_value, current_user_id,
      suggested_rate, suggested_snapshot_id,
      suggested_source, suggested_observed_at
    ) returning id into resolution_id_value;

    insert into public.inventory_movements (
      shop_id, branch_id, operation_id, receipt_line_id, variant_id,
      serialized_inventory_id, fx_resolution_id, movement_type,
      valuation_status, valuation_currency_code, on_hand_delta,
      available_delta, actor_id, line_number
    ) values (
      p_shop_id, p_branch_id, operation_id_value,
      (line_value.value ->> 'receipt_line_id')::uuid,
      (line_value.value ->> 'variant_id')::uuid,
      nullif(line_value.value ->> 'serialized_inventory_id', '')::uuid,
      resolution_id_value, 'fx_release'::public.inventory_movement_kind,
      'pending_fx', shop_currency,
      -((line_value.value ->> 'quantity')::integer), 0,
      current_user_id, movement_index * 2 - 1
    );

    insert into public.inventory_movements (
      shop_id, branch_id, operation_id, receipt_line_id, variant_id,
      serialized_inventory_id, fx_resolution_id, movement_type,
      valuation_status, valuation_currency_code, on_hand_delta,
      available_delta, unit_cost_shop, extended_cost_shop,
      actor_id, line_number
    ) values (
      p_shop_id, p_branch_id, operation_id_value,
      (line_value.value ->> 'receipt_line_id')::uuid,
      (line_value.value ->> 'variant_id')::uuid,
      nullif(line_value.value ->> 'serialized_inventory_id', '')::uuid,
      resolution_id_value, 'fx_release'::public.inventory_movement_kind,
      'known_cost', shop_currency,
      (line_value.value ->> 'quantity')::integer,
      (line_value.value ->> 'quantity')::integer,
      unit_cost_value, converted_line_amount_value,
      current_user_id, movement_index * 2
    );
  end loop;

  return operation_id_value;
end;
$function$;

revoke all on function public.release_pending_fx_receipt(
  uuid, uuid, uuid, text, uuid, numeric, text, timestamptz, text, uuid
) from public, anon, service_role;
grant execute on function public.release_pending_fx_receipt(
  uuid, uuid, uuid, text, uuid, numeric, text, timestamptz, text, uuid
) to authenticated;
