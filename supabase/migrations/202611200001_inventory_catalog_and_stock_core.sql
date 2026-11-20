-- StockPilot Milestone 2, Phase 1.
-- Creates an inventory foundation without assigning currencies to existing
-- shops, importing LocalStorage records, or depending on the future Purchases
-- module. Apply only after explicit approval.

create type public.inventory_valuation_status as enum (
  'known_cost',
  'unknown_cost',
  'pending_fx'
);

create type public.inventory_availability_status as enum (
  'available',
  'reserved',
  'pending_fx',
  'sold',
  'written_off'
);

create type public.inventory_movement_kind as enum (
  'receipt',
  'pending_fx_receipt',
  'fx_release',
  'adjustment_in',
  'adjustment_out',
  'sale',
  'transfer_out',
  'transfer_in',
  'custody_out',
  'custody_return'
);

create table public.currency_codes (
  code char(3) primary key,
  minor_units smallint not null,
  enabled boolean not null default true,
  constraint currency_codes_uppercase check (code::text ~ '^[A-Z]{3}$'),
  constraint currency_codes_minor_units check (minor_units between 0 and 4)
);

insert into public.currency_codes (code, minor_units) values
  ('AED', 2), ('AUD', 2), ('BDT', 2), ('BHD', 3), ('BIF', 0),
  ('BRL', 2), ('CAD', 2), ('CHF', 2), ('CNY', 2), ('DKK', 2),
  ('EGP', 2), ('EUR', 2), ('GBP', 2), ('GHS', 2), ('HKD', 2),
  ('IDR', 2), ('INR', 2), ('IQD', 3), ('JOD', 3), ('JPY', 0),
  ('KES', 2), ('KRW', 0), ('KWD', 3), ('LKR', 2), ('MUR', 2),
  ('MWK', 2), ('MYR', 2), ('NGN', 2), ('NOK', 2), ('NPR', 2),
  ('NZD', 2), ('OMR', 3), ('PHP', 2), ('PKR', 2), ('QAR', 2),
  ('RUB', 2), ('SAR', 2), ('SEK', 2), ('SGD', 2), ('SOS', 2),
  ('TZS', 2), ('UGX', 0), ('USD', 2), ('VND', 0), ('ZAR', 2),
  ('ZMW', 2);

create table public.shop_settings (
  shop_id uuid primary key references public.shops (id) on delete restrict,
  operating_currency_code char(3) not null
    references public.currency_codes (code) on update restrict on delete restrict,
  currency_version integer not null default 1,
  currency_locked_at timestamptz,
  configured_at timestamptz not null default now(),
  configured_by uuid not null references auth.users (id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users (id) on delete restrict,
  constraint shop_settings_version_positive check (currency_version > 0),
  unique (shop_id, operating_currency_code)
);

comment on column public.shop_settings.operating_currency_code is
  'Explicit shop valuation and normal selling-price currency; no default is assigned.';

create table public.products (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id) on delete restrict,
  product_type text not null,
  tracking_mode text not null,
  name text not null,
  brand text,
  model text,
  manufacturer_model_number text,
  description text,
  attributes jsonb not null default '{}'::jsonb,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users (id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users (id) on delete restrict,
  unique (shop_id, id),
  constraint products_product_type check (
    product_type in ('smartphone', 'tablet', 'laptop', 'accessory', 'spare_part', 'other')
  ),
  constraint products_tracking_mode check (
    tracking_mode in ('serialized', 'quantity')
  ),
  constraint products_name_length check (
    char_length(btrim(name)) between 1 and 160
  ),
  constraint products_attributes_object check (
    jsonb_typeof(attributes) = 'object'
  )
);

create index products_shop_type_active_idx
  on public.products (shop_id, product_type, archived_at);

create unique index products_shop_normalized_name_idx
  on public.products (shop_id, lower(btrim(name)))
  where archived_at is null;

create table public.product_variants (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  product_id uuid not null,
  colour text,
  storage_capacity text,
  network_lock_status text,
  attributes jsonb not null default '{}'::jsonb,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users (id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users (id) on delete restrict,
  unique (shop_id, id),
  foreign key (shop_id, product_id)
    references public.products (shop_id, id) on delete restrict,
  constraint product_variants_attributes_object check (
    jsonb_typeof(attributes) = 'object'
  )
);

create index product_variants_shop_product_idx
  on public.product_variants (shop_id, product_id, archived_at);

create table public.product_identifiers (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  variant_id uuid not null,
  identifier_type text not null,
  raw_value text not null,
  normalized_value text generated always as (
    upper(normalize(btrim(raw_value), NFKC))
  ) stored,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users (id) on delete restrict,
  foreign key (shop_id, variant_id)
    references public.product_variants (shop_id, id) on delete restrict,
  constraint product_identifiers_type check (
    identifier_type in ('sku', 'barcode', 'manufacturer_part_number')
  ),
  constraint product_identifiers_value check (
    char_length(btrim(raw_value)) between 1 and 160
  ),
  unique (shop_id, identifier_type, normalized_value)
);

create index product_identifiers_shop_normalized_idx
  on public.product_identifiers (shop_id, normalized_value);

create table public.serialized_inventory (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  branch_id uuid not null,
  variant_id uuid not null,
  availability_status public.inventory_availability_status not null default 'available',
  valuation_status public.inventory_valuation_status not null,
  valuation_currency_code char(3) not null,
  unit_cost_shop numeric(38, 10),
  condition text,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users (id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users (id) on delete restrict,
  unique (shop_id, branch_id, id),
  unique (shop_id, branch_id, variant_id, id),
  foreign key (shop_id, branch_id)
    references public.branches (shop_id, id) on delete restrict,
  foreign key (shop_id, variant_id)
    references public.product_variants (shop_id, id) on delete restrict,
  foreign key (shop_id, valuation_currency_code)
    references public.shop_settings (shop_id, operating_currency_code)
    on update restrict on delete restrict,
  constraint serialized_inventory_cost_state check (
    (valuation_status = 'known_cost' and unit_cost_shop is not null
      and unit_cost_shop >= 0 and unit_cost_shop < 'Infinity'::numeric)
    or
    (valuation_status in ('unknown_cost', 'pending_fx')
      and unit_cost_shop is null)
  ),
  constraint serialized_inventory_pending_not_sellable check (
    valuation_status <> 'pending_fx'
    or availability_status = 'pending_fx'
  )
);

create index serialized_inventory_branch_status_idx
  on public.serialized_inventory (shop_id, branch_id, availability_status);
create index serialized_inventory_variant_idx
  on public.serialized_inventory (shop_id, variant_id);

create table public.serialized_identifiers (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  branch_id uuid not null,
  serialized_inventory_id uuid not null,
  identifier_type text not null,
  raw_value text not null,
  normalized_value text generated always as (
    upper(normalize(btrim(raw_value), NFKC))
  ) stored,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users (id) on delete restrict,
  foreign key (shop_id, branch_id, serialized_inventory_id)
    references public.serialized_inventory (shop_id, branch_id, id)
    on delete restrict,
  constraint serialized_identifiers_type check (
    identifier_type in ('imei1', 'imei2', 'serial')
  ),
  constraint serialized_identifiers_nonblank check (
    char_length(btrim(raw_value)) between 1 and 160
  ),
  constraint serialized_identifiers_imei_format check (
    identifier_type not in ('imei1', 'imei2')
    or normalized_value ~ '^[0-9]{15}$'
  ),
  unique (shop_id, normalized_value)
);

create index serialized_identifiers_branch_idx
  on public.serialized_identifiers (shop_id, branch_id, serialized_inventory_id);

create table public.exchange_rate_snapshots (
  id uuid primary key default gen_random_uuid(),
  from_currency_code char(3) not null
    references public.currency_codes (code) on update restrict on delete restrict,
  to_currency_code char(3) not null
    references public.currency_codes (code) on update restrict on delete restrict,
  rate_to_currency numeric(38, 16) not null,
  rate_source text not null,
  observed_at timestamptz not null,
  fetched_at timestamptz not null default now(),
  valid_until timestamptz not null,
  created_at timestamptz not null default now(),
  constraint exchange_rate_pair_distinct check (
    from_currency_code <> to_currency_code
  ),
  constraint exchange_rate_positive_finite check (
    rate_to_currency > 0 and rate_to_currency < 'Infinity'::numeric
  ),
  constraint exchange_rate_source_nonblank check (
    char_length(btrim(rate_source)) between 1 and 120
  ),
  constraint exchange_rate_timestamps check (
    observed_at <= fetched_at and valid_until > observed_at
  ),
  unique (from_currency_code, to_currency_code, rate_source, observed_at)
);

comment on column public.exchange_rate_snapshots.rate_to_currency is
  'Units of to_currency_code per one unit of from_currency_code.';

create index exchange_rate_pair_validity_idx
  on public.exchange_rate_snapshots (
    from_currency_code, to_currency_code, valid_until desc
  );

create table public.inventory_operations (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  branch_id uuid not null,
  operation_type text not null,
  actor_id uuid not null references auth.users (id) on delete restrict,
  idempotency_key text not null,
  request_payload jsonb not null,
  result_receipt_id uuid not null,
  valuation_currency_code char(3) not null,
  currency_version integer not null,
  created_at timestamptz not null default now(),
  unique (shop_id, id),
  unique (shop_id, branch_id, id),
  unique (shop_id, actor_id, idempotency_key),
  foreign key (shop_id, branch_id)
    references public.branches (shop_id, id) on delete restrict,
  foreign key (shop_id, valuation_currency_code)
    references public.shop_settings (shop_id, operating_currency_code)
    on update restrict on delete restrict,
  constraint inventory_operations_type check (
    operation_type in ('quantity_receipt')
  ),
  constraint inventory_operations_key_length check (
    char_length(btrim(idempotency_key)) between 8 and 120
  ),
  constraint inventory_operations_payload_object check (
    jsonb_typeof(request_payload) = 'object'
  ),
  constraint inventory_operations_currency_version check (currency_version > 0)
);

create index inventory_operations_branch_created_idx
  on public.inventory_operations (shop_id, branch_id, created_at desc);

create table public.inventory_receipts (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  branch_id uuid not null,
  operation_id uuid not null,
  receipt_kind text not null,
  supplier_name_snapshot text,
  supplier_invoice_reference text,
  received_at timestamptz not null default now(),
  original_currency_code char(3),
  original_invoice_amount numeric(38, 8),
  valuation_currency_code char(3) not null,
  rate_direction text not null default 'shop_currency_per_original_currency',
  accepted_fx_rate numeric(38, 16),
  rate_snapshot_id uuid references public.exchange_rate_snapshots (id) on delete restrict,
  rate_source text,
  rate_observed_at timestamptz,
  rate_accepted_at timestamptz,
  accepted_by uuid references auth.users (id) on delete restrict,
  override_approved_by uuid references auth.users (id) on delete restrict,
  override_reason text,
  converted_invoice_amount_shop numeric(38, 8),
  valuation_status public.inventory_valuation_status not null,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users (id) on delete restrict,
  unique (shop_id, id),
  unique (shop_id, branch_id, id),
  unique (shop_id, operation_id),
  foreign key (shop_id, branch_id)
    references public.branches (shop_id, id) on delete restrict,
  foreign key (shop_id, branch_id, operation_id)
    references public.inventory_operations (shop_id, branch_id, id) on delete restrict,
  foreign key (shop_id, valuation_currency_code)
    references public.shop_settings (shop_id, operating_currency_code)
    on update restrict on delete restrict,
  foreign key (original_currency_code)
    references public.currency_codes (code) on update restrict on delete restrict,
  constraint inventory_receipts_kind check (
    receipt_kind in ('supplier_invoice', 'manual_unknown_cost')
  ),
  constraint inventory_receipts_rate_direction check (
    rate_direction = 'shop_currency_per_original_currency'
  ),
  constraint inventory_receipts_original_amount check (
    original_invoice_amount is null
    or (original_invoice_amount >= 0
      and original_invoice_amount < 'Infinity'::numeric)
  ),
  constraint inventory_receipts_converted_amount check (
    converted_invoice_amount_shop is null
    or (converted_invoice_amount_shop >= 0
      and converted_invoice_amount_shop < 'Infinity'::numeric)
  ),
  constraint inventory_receipts_rate_evidence check (
    (accepted_fx_rate is null and rate_snapshot_id is null
      and rate_source is null and rate_observed_at is null
      and rate_accepted_at is null and accepted_by is null)
    or
    (accepted_fx_rate is not null
      and accepted_fx_rate > 0 and accepted_fx_rate < 'Infinity'::numeric
      and rate_source is not null and rate_observed_at is not null
      and rate_accepted_at is not null and accepted_by is not null)
  ),
  constraint inventory_receipts_override_evidence check (
    (override_approved_by is null and override_reason is null)
    or
    (override_approved_by is not null
      and override_reason is not null
      and char_length(btrim(override_reason)) between 10 and 1000)
  ),
  constraint inventory_receipts_known_currency check (
    receipt_kind <> 'supplier_invoice'
    or (original_currency_code is not null and original_invoice_amount is not null)
  ),
  constraint inventory_receipts_unknown_cost check (
    receipt_kind <> 'manual_unknown_cost'
    or (original_invoice_amount is null
      and converted_invoice_amount_shop is null
      and accepted_fx_rate is null
      and valuation_status = 'unknown_cost')
  ),
  constraint inventory_receipts_pending_fx check (
    valuation_status <> 'pending_fx'
    or (receipt_kind = 'supplier_invoice'
      and original_currency_code is not null
      and original_invoice_amount is not null
      and accepted_fx_rate is null
      and converted_invoice_amount_shop is null)
  ),
  constraint inventory_receipts_valuation_evidence check (
    (valuation_status = 'known_cost'
      and receipt_kind = 'supplier_invoice'
      and original_currency_code is not null
      and original_invoice_amount is not null
      and accepted_fx_rate is not null
      and converted_invoice_amount_shop is not null)
    or
    (valuation_status = 'pending_fx'
      and receipt_kind = 'supplier_invoice'
      and original_currency_code is not null
      and original_invoice_amount is not null
      and accepted_fx_rate is null
      and converted_invoice_amount_shop is null)
    or
    (valuation_status = 'unknown_cost'
      and receipt_kind = 'manual_unknown_cost'
      and original_invoice_amount is null
      and accepted_fx_rate is null
      and converted_invoice_amount_shop is null)
  )
);

comment on column public.inventory_receipts.accepted_fx_rate is
  'Units of valuation_currency_code per one unit of original_currency_code.';

create index inventory_receipts_branch_received_idx
  on public.inventory_receipts (shop_id, branch_id, received_at desc);

create table public.inventory_receipt_lines (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  branch_id uuid not null,
  receipt_id uuid not null,
  line_number integer not null,
  variant_id uuid not null,
  serialized_inventory_id uuid,
  quantity integer not null,
  original_line_amount numeric(38, 8),
  converted_line_amount_shop numeric(38, 8),
  unit_cost_shop numeric(38, 10),
  valuation_status public.inventory_valuation_status not null,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users (id) on delete restrict,
  unique (shop_id, id),
  unique (shop_id, branch_id, id),
  unique (shop_id, branch_id, variant_id, id),
  unique (shop_id, receipt_id, line_number),
  foreign key (shop_id, branch_id, receipt_id)
    references public.inventory_receipts (shop_id, branch_id, id)
    on delete restrict,
  foreign key (shop_id, variant_id)
    references public.product_variants (shop_id, id) on delete restrict,
  foreign key (shop_id, branch_id, variant_id, serialized_inventory_id)
    references public.serialized_inventory (shop_id, branch_id, variant_id, id)
    on delete restrict,
  constraint inventory_receipt_lines_positive_qty check (quantity > 0),
  constraint inventory_receipt_lines_number check (line_number > 0),
  constraint inventory_receipt_lines_serial_qty check (
    serialized_inventory_id is null or quantity = 1
  ),
  constraint inventory_receipt_lines_original_nonnegative check (
    original_line_amount is null
    or (original_line_amount >= 0 and original_line_amount < 'Infinity'::numeric)
  ),
  constraint inventory_receipt_lines_converted_nonnegative check (
    converted_line_amount_shop is null
    or (converted_line_amount_shop >= 0
      and converted_line_amount_shop < 'Infinity'::numeric)
  ),
  constraint inventory_receipt_lines_cost_state check (
    (valuation_status = 'known_cost'
      and original_line_amount is not null
      and converted_line_amount_shop is not null
      and unit_cost_shop is not null
      and unit_cost_shop >= 0 and unit_cost_shop < 'Infinity'::numeric)
    or
    (valuation_status = 'unknown_cost'
      and original_line_amount is null
      and converted_line_amount_shop is null
      and unit_cost_shop is null)
    or
    (valuation_status = 'pending_fx'
      and original_line_amount is not null
      and converted_line_amount_shop is null
      and unit_cost_shop is null)
  )
);

create index inventory_receipt_lines_branch_variant_idx
  on public.inventory_receipt_lines (shop_id, branch_id, variant_id);

alter table public.inventory_operations
  add constraint inventory_operations_result_receipt_fk
  foreign key (shop_id, branch_id, result_receipt_id)
  references public.inventory_receipts (shop_id, branch_id, id)
  on delete restrict
  deferrable initially deferred;

create table public.inventory_balances (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  branch_id uuid not null,
  variant_id uuid not null,
  valuation_status public.inventory_valuation_status not null,
  valuation_currency_code char(3) not null,
  on_hand_qty integer not null default 0,
  available_qty integer not null default 0,
  carrying_value_shop numeric(38, 8),
  average_unit_cost_shop numeric(38, 10),
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users (id) on delete restrict,
  unique (shop_id, id),
  unique (shop_id, branch_id, variant_id, valuation_status),
  foreign key (shop_id, branch_id)
    references public.branches (shop_id, id) on delete restrict,
  foreign key (shop_id, variant_id)
    references public.product_variants (shop_id, id) on delete restrict,
  foreign key (shop_id, valuation_currency_code)
    references public.shop_settings (shop_id, operating_currency_code)
    on update restrict on delete restrict,
  constraint inventory_balances_nonnegative_qty check (
    on_hand_qty >= 0 and available_qty >= 0 and available_qty <= on_hand_qty
  ),
  constraint inventory_balances_pending_unavailable check (
    valuation_status <> 'pending_fx' or available_qty = 0
  ),
  constraint inventory_balances_value_state check (
    (valuation_status = 'known_cost'
      and carrying_value_shop is not null
      and carrying_value_shop >= 0
      and carrying_value_shop < 'Infinity'::numeric
      and average_unit_cost_shop is not null
      and average_unit_cost_shop >= 0
      and average_unit_cost_shop < 'Infinity'::numeric)
    or
    (valuation_status in ('unknown_cost', 'pending_fx')
      and carrying_value_shop is null
      and average_unit_cost_shop is null)
  )
);

comment on column public.inventory_balances.carrying_value_shop is
  'Authoritative carrying value in shop currency; averages are display/issue precision only.';
comment on column public.inventory_balances.average_unit_cost_shop is
  'Weighted-average shop-currency unit cost rounded to ten decimal places.';

create index inventory_balances_branch_variant_idx
  on public.inventory_balances (shop_id, branch_id, variant_id);

create table public.branch_variant_prices (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  branch_id uuid not null,
  variant_id uuid not null,
  price_currency_code char(3) not null,
  selling_price_shop numeric(38, 8) not null,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users (id) on delete restrict,
  updated_at timestamptz not null default now(),
  updated_by uuid not null references auth.users (id) on delete restrict,
  unique (shop_id, id),
  unique (shop_id, branch_id, variant_id),
  foreign key (shop_id, branch_id)
    references public.branches (shop_id, id) on delete restrict,
  foreign key (shop_id, variant_id)
    references public.product_variants (shop_id, id) on delete restrict,
  foreign key (shop_id, price_currency_code)
    references public.shop_settings (shop_id, operating_currency_code)
    on update restrict on delete restrict,
  constraint branch_variant_prices_nonnegative check (
    selling_price_shop >= 0 and selling_price_shop < 'Infinity'::numeric
  )
);

create index branch_variant_prices_branch_idx
  on public.branch_variant_prices (shop_id, branch_id, variant_id);

-- This immutable resolution ledger is the evidence target for a future
-- Owner/authorized-staff Pending-FX release RPC. That RPC must lock the
-- pending line and balance, validate the same FX evidence rules as receiving,
-- append the resolution and an fx_release movement, and update the balance in
-- one transaction. Clients have no write path to this table.
create table public.inventory_fx_resolutions (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  branch_id uuid not null,
  receipt_line_id uuid not null,
  operation_id uuid not null,
  original_currency_code char(3) not null
    references public.currency_codes (code) on update restrict on delete restrict,
  original_line_amount numeric(38, 8) not null,
  valuation_currency_code char(3) not null,
  rate_direction text not null default 'shop_currency_per_original_currency',
  accepted_fx_rate numeric(38, 16) not null,
  rate_snapshot_id uuid references public.exchange_rate_snapshots (id) on delete restrict,
  rate_source text not null,
  rate_observed_at timestamptz not null,
  rate_accepted_at timestamptz not null,
  accepted_by uuid not null references auth.users (id) on delete restrict,
  override_approved_by uuid references auth.users (id) on delete restrict,
  override_reason text,
  converted_line_amount_shop numeric(38, 8) not null,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users (id) on delete restrict,
  unique (shop_id, id),
  unique (shop_id, receipt_line_id),
  foreign key (shop_id, branch_id)
    references public.branches (shop_id, id) on delete restrict,
  foreign key (shop_id, branch_id, receipt_line_id)
    references public.inventory_receipt_lines (shop_id, branch_id, id) on delete restrict,
  foreign key (shop_id, branch_id, operation_id)
    references public.inventory_operations (shop_id, branch_id, id) on delete restrict,
  foreign key (shop_id, valuation_currency_code)
    references public.shop_settings (shop_id, operating_currency_code)
    on update restrict on delete restrict,
  constraint inventory_fx_resolutions_rate_direction check (
    rate_direction = 'shop_currency_per_original_currency'
  ),
  constraint inventory_fx_resolutions_positive_rate check (
    accepted_fx_rate > 0 and accepted_fx_rate < 'Infinity'::numeric
  ),
  constraint inventory_fx_resolutions_amounts check (
    original_line_amount >= 0
    and original_line_amount < 'Infinity'::numeric
    and converted_line_amount_shop >= 0
    and converted_line_amount_shop < 'Infinity'::numeric
  ),
  constraint inventory_fx_resolutions_override check (
    (override_approved_by is null and override_reason is null)
    or
    (override_approved_by is not null
      and override_reason is not null
      and char_length(btrim(override_reason)) between 10 and 1000)
  )
);

create index inventory_fx_resolutions_branch_idx
  on public.inventory_fx_resolutions (shop_id, branch_id, created_at desc);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  branch_id uuid not null,
  operation_id uuid not null,
  receipt_line_id uuid,
  variant_id uuid not null,
  serialized_inventory_id uuid,
  movement_type public.inventory_movement_kind not null,
  valuation_status public.inventory_valuation_status not null,
  valuation_currency_code char(3) not null,
  on_hand_delta integer not null,
  available_delta integer not null,
  unit_cost_shop numeric(38, 10),
  extended_cost_shop numeric(38, 8),
  reason text,
  actor_id uuid not null references auth.users (id) on delete restrict,
  occurred_at timestamptz not null default now(),
  line_number integer not null,
  unique (shop_id, id),
  unique (shop_id, operation_id, line_number),
  foreign key (shop_id, branch_id)
    references public.branches (shop_id, id) on delete restrict,
  foreign key (shop_id, branch_id, operation_id)
    references public.inventory_operations (shop_id, branch_id, id) on delete restrict,
  foreign key (shop_id, branch_id, variant_id, receipt_line_id)
    references public.inventory_receipt_lines (shop_id, branch_id, variant_id, id) on delete restrict,
  foreign key (shop_id, variant_id)
    references public.product_variants (shop_id, id) on delete restrict,
  foreign key (shop_id, branch_id, variant_id, serialized_inventory_id)
    references public.serialized_inventory (shop_id, branch_id, variant_id, id)
    on delete restrict,
  foreign key (shop_id, valuation_currency_code)
    references public.shop_settings (shop_id, operating_currency_code)
    on update restrict on delete restrict,
  constraint inventory_movements_nonzero check (on_hand_delta <> 0),
  constraint inventory_movements_line_number check (line_number > 0),
  constraint inventory_movements_serial_delta check (
    serialized_inventory_id is null or abs(on_hand_delta) = 1
  ),
  constraint inventory_movements_pending_unavailable check (
    valuation_status <> 'pending_fx' or available_delta = 0
  ),
  constraint inventory_movements_value_state check (
    (valuation_status = 'known_cost'
      and unit_cost_shop is not null and unit_cost_shop >= 0
      and extended_cost_shop is not null and extended_cost_shop >= 0
      and unit_cost_shop < 'Infinity'::numeric
      and extended_cost_shop < 'Infinity'::numeric)
    or
    (valuation_status in ('unknown_cost', 'pending_fx')
      and unit_cost_shop is null and extended_cost_shop is null)
  )
);

create index inventory_movements_branch_time_idx
  on public.inventory_movements (shop_id, branch_id, occurred_at desc);
create index inventory_movements_variant_time_idx
  on public.inventory_movements (shop_id, variant_id, occurred_at desc);

-- Append-only audit rows. Corrections are represented by new operations and
-- movements, never by changing historical receipt or movement records.
create or replace function private.reject_inventory_audit_mutation()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception 'Inventory audit records are append-only.'
    using errcode = '42501';
end;
$function$;

revoke all on function private.reject_inventory_audit_mutation()
  from public, anon, authenticated;

create trigger inventory_operations_append_only
  before update or delete on public.inventory_operations
  for each row execute function private.reject_inventory_audit_mutation();
create trigger inventory_receipts_append_only
  before update or delete on public.inventory_receipts
  for each row execute function private.reject_inventory_audit_mutation();
create trigger inventory_receipt_lines_append_only
  before update or delete on public.inventory_receipt_lines
  for each row execute function private.reject_inventory_audit_mutation();
create trigger inventory_fx_resolutions_append_only
  before update or delete on public.inventory_fx_resolutions
  for each row execute function private.reject_inventory_audit_mutation();
create trigger inventory_movements_append_only
  before update or delete on public.inventory_movements
  for each row execute function private.reject_inventory_audit_mutation();
create trigger exchange_rate_snapshots_append_only
  before update or delete on public.exchange_rate_snapshots
  for each row execute function private.reject_inventory_audit_mutation();

create or replace function private.guard_shop_currency_lock()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if old.currency_locked_at is not null
    and new.operating_currency_code is distinct from old.operating_currency_code
  then
    raise exception 'The shop currency is locked after its first inventory operation.'
      using errcode = '42501';
  end if;

  if old.currency_locked_at is not null
    and new.currency_locked_at is distinct from old.currency_locked_at
  then
    raise exception 'The shop currency lock cannot be changed.'
      using errcode = '42501';
  end if;

  if new.operating_currency_code is distinct from old.operating_currency_code then
    new.currency_version := old.currency_version + 1;
  end if;

  return new;
end;
$function$;

revoke all on function private.guard_shop_currency_lock()
  from public, anon, authenticated;

create trigger shop_settings_currency_lock_guard
  before update on public.shop_settings
  for each row execute function private.guard_shop_currency_lock();

create trigger shop_settings_touch_updated_at
  before update on public.shop_settings
  for each row execute function private.touch_updated_at();

create or replace function public.configure_shop_operating_currency(
  p_shop_id uuid,
  p_currency_code text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  current_user_id uuid := (select auth.uid());
  locked_member_id uuid;
  normalized_code text := upper(btrim(p_currency_code));
  existing_currency char(3);
  existing_lock timestamptz;
begin
  if current_user_id is null
    or not private.has_shop_role(
      p_shop_id,
      array['owner']::public.shop_role[]
    )
  then
    raise exception 'Only an active shop owner can configure its currency.'
      using errcode = '42501';
  end if;

  select membership.user_id into locked_member_id
  from public.shop_memberships as membership
  where membership.shop_id = p_shop_id
    and membership.user_id = current_user_id
    and membership.status = 'active'
  for share;

  if not found or not private.has_shop_role(
    p_shop_id,
    array['owner']::public.shop_role[]
  ) then
    raise exception 'Only an active shop owner can configure its currency.'
      using errcode = '42501';
  end if;

  -- Lock the parent row too so two first-time currency selections cannot race
  -- while shop_settings has no row to lock yet.
  perform shop.id
  from public.shops as shop
  where shop.id = p_shop_id
  for update;

  if normalized_code is null or normalized_code !~ '^[A-Z]{3}$'
    or not exists (
      select 1 from public.currency_codes
      where code = normalized_code::char(3) and enabled
    )
  then
    raise exception 'Select a supported currency code.'
      using errcode = '22023';
  end if;

  select settings.operating_currency_code, settings.currency_locked_at
    into existing_currency, existing_lock
  from public.shop_settings as settings
  where settings.shop_id = p_shop_id
  for update;

  if found and existing_lock is not null
    and existing_currency is distinct from normalized_code::char(3)
  then
    raise exception 'The shop currency cannot change after inventory is posted.'
      using errcode = '42501';
  end if;

  insert into public.shop_settings (
    shop_id, operating_currency_code, currency_version,
    configured_at, configured_by, updated_at, updated_by
  ) values (
    p_shop_id, normalized_code::char(3), 1,
    clock_timestamp(), current_user_id, clock_timestamp(), current_user_id
  )
  on conflict (shop_id) do update
  set operating_currency_code = excluded.operating_currency_code,
      configured_at = clock_timestamp(),
      configured_by = current_user_id,
      updated_by = current_user_id;
end;
$function$;

revoke all on function public.configure_shop_operating_currency(uuid, text)
  from public, anon;
grant execute on function public.configure_shop_operating_currency(uuid, text)
  to authenticated;

-- The initial transactional receiver handles quantity-tracked variants. A
-- separate serialized receiver must preserve the same authorization, currency,
-- idempotency, and audit rules before serialized stock is writable.
create or replace function public.receive_quantity_inventory(
  p_shop_id uuid,
  p_branch_id uuid,
  p_idempotency_key text,
  p_receipt_kind text,
  p_supplier_name text,
  p_supplier_invoice_reference text,
  p_original_currency_code text,
  p_original_invoice_amount numeric,
  p_lines jsonb,
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
  accepted_rate_at timestamptz := clock_timestamp();
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
  allocated_lines jsonb;
  converted_total numeric(38, 8);
  line_value record;
  line_number_value integer;
  quantity_value integer;
  variant_id_value uuid;
  original_line_amount_value numeric(38, 8);
  converted_line_amount_value numeric(38, 8);
  unit_cost_value numeric(38, 10);
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
    raise exception 'You are not authorized to receive stock in this branch.'
      using errcode = '42501';
  end if;

  select membership.user_id into locked_member_id
  from public.shop_memberships as membership
  where membership.shop_id = p_shop_id
    and membership.user_id = current_user_id
    and membership.status = 'active'
  for share;

  if not found then
    raise exception 'You are not authorized to receive stock in this branch.'
      using errcode = '42501';
  end if;

  select branch.id into locked_branch_id
  from public.branches as branch
  where branch.shop_id = p_shop_id
    and branch.id = p_branch_id
    and branch.is_active
  for share;

  if not found then
    raise exception 'You are not authorized to receive stock in this branch.'
      using errcode = '42501';
  end if;

  if not private.has_shop_role(
    p_shop_id,
    array['owner']::public.shop_role[]
  ) then
    select assignment.user_id into locked_assignment_user_id
    from public.branch_memberships as assignment
    where assignment.shop_id = p_shop_id
      and assignment.branch_id = p_branch_id
      and assignment.user_id = current_user_id
    for share;

    if not found then
      raise exception 'You are not authorized to receive stock in this branch.'
        using errcode = '42501';
    end if;
  end if;

  if not private.has_shop_role(
    p_shop_id,
    array['owner', 'manager', 'inventory_staff']::public.shop_role[]
  ) or not private.can_access_branch(p_shop_id, p_branch_id) then
    raise exception 'You are not authorized to receive stock in this branch.'
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

  if p_lines is null or jsonb_typeof(p_lines) is distinct from 'array'
    or jsonb_array_length(p_lines) = 0
    or jsonb_array_length(p_lines) > 500
  then
    raise exception 'Receipt lines must be a nonempty array of at most 500 lines.'
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

  if p_original_currency_code is not null then
    if upper(btrim(p_original_currency_code)) !~ '^[A-Z]{3}$'
      or not exists (
        select 1 from public.currency_codes as currency
        where currency.code = upper(btrim(p_original_currency_code))::char(3)
          and currency.enabled
      )
    then
      raise exception 'Select a supported original currency.'
        using errcode = '22023';
    end if;
    original_currency := upper(btrim(p_original_currency_code))::char(3);
  end if;

  if p_receipt_kind = 'supplier_invoice' then
    if original_currency is null
      or p_original_invoice_amount is null
      or p_original_invoice_amount < 0
      or p_original_invoice_amount >= 'Infinity'::numeric
      or p_original_invoice_amount <> round(
        p_original_invoice_amount,
        (select currency.minor_units
         from public.currency_codes as currency
         where currency.code = original_currency)
      )
    then
      raise exception 'Supplier invoice currency and amount must be valid.'
        using errcode = '22023';
    end if;

    if exists (
      select 1
      from pg_catalog.jsonb_array_elements(p_lines) as entry(value)
      where pg_catalog.jsonb_typeof(entry.value) is distinct from 'object'
        or pg_catalog.jsonb_typeof(entry.value -> 'original_line_amount') is distinct from 'number'
    ) then
      raise exception 'Every supplier invoice line needs an exact original amount.'
        using errcode = '22023';
    end if;

    select sum((entry.value ->> 'original_line_amount')::numeric)
      into source_amount_total
    from pg_catalog.jsonb_array_elements(p_lines) as entry(value);

    if source_amount_total is distinct from p_original_invoice_amount then
      raise exception 'Invoice line amounts must reconcile exactly to the invoice total.'
        using errcode = '22023';
    end if;

    select currency.minor_units into original_minor_units
    from public.currency_codes as currency
    where currency.code = original_currency;

    if exists (
      select 1
      from pg_catalog.jsonb_array_elements(p_lines) as entry(value)
      where (entry.value ->> 'original_line_amount')::numeric < 0
        or (entry.value ->> 'original_line_amount')::numeric >= 'Infinity'::numeric
        or (entry.value ->> 'original_line_amount')::numeric <> round(
          (entry.value ->> 'original_line_amount')::numeric,
          original_minor_units
        )
    ) then
      raise exception 'Invoice line amounts must be nonnegative and use the currency precision.'
        using errcode = '22023';
    end if;

    valuation_status_value := 'known_cost';
  else
    if p_original_invoice_amount is not null
      or exists (
        select 1
        from pg_catalog.jsonb_array_elements(p_lines) as entry(value)
        where pg_catalog.jsonb_typeof(entry.value) is distinct from 'object'
          or entry.value ? 'original_line_amount'
             and pg_catalog.jsonb_typeof(entry.value -> 'original_line_amount') is distinct from 'null'
      )
    then
      raise exception 'Unknown-cost receipts cannot claim invoice or line amounts.'
        using errcode = '22023';
    end if;
    valuation_status_value := 'unknown_cost';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(p_lines) as entry(value)
    where pg_catalog.jsonb_typeof(entry.value) is distinct from 'object'
      or pg_catalog.jsonb_typeof(entry.value -> 'line_number') is distinct from 'number'
      or (entry.value ->> 'line_number') !~ '^[1-9][0-9]*$'
      or (entry.value ->> 'line_number')::numeric > 2147483647
      or pg_catalog.jsonb_typeof(entry.value -> 'variant_id') is distinct from 'string'
      or pg_catalog.jsonb_typeof(entry.value -> 'quantity') is distinct from 'number'
      or (entry.value ->> 'quantity') !~ '^[1-9][0-9]*$'
      or (entry.value ->> 'quantity')::numeric > 2147483647
  ) then
    raise exception 'Receipt lines require positive line numbers, quantities, and variant IDs.'
      using errcode = '22023';
  end if;

  if (
    select count(*) from pg_catalog.jsonb_array_elements(p_lines)
  ) <> (
    select count(distinct (entry.value ->> 'line_number')::integer)
    from pg_catalog.jsonb_array_elements(p_lines) as entry(value)
  ) then
    raise exception 'Receipt line numbers must be unique.'
      using errcode = '22023';
  end if;

  request_value := pg_catalog.jsonb_build_object(
    'shop_id', p_shop_id,
    'branch_id', p_branch_id,
    'receipt_kind', p_receipt_kind,
    'supplier_name', p_supplier_name,
    'supplier_invoice_reference', p_supplier_invoice_reference,
    'original_currency_code', original_currency,
    'original_invoice_amount', p_original_invoice_amount,
    'lines', p_lines,
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
    operation_id_value, p_shop_id, p_branch_id, 'quantity_receipt',
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
      raise exception 'The idempotency key was already used for different receipt contents.'
        using errcode = '22023';
    end if;

    return existing_receipt_id;
  end if;

  if p_receipt_kind = 'supplier_invoice' then
    if original_currency = shop_currency then
      if p_rate_snapshot_id is not null or p_manual_rate is not null
        or p_manual_rate_source is not null
        or p_manual_rate_observed_at is not null
        or p_override_reason is not null
        or p_accept_pending_fx
      then
        raise exception 'Same-currency receipts use the identity rate.'
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
        raise exception 'Choose either a system rate or a manual override.'
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
      if not private.has_shop_role(
        p_shop_id,
        array['owner']::public.shop_role[]
      ) then
        raise exception 'Only an active shop owner may approve a manual exchange-rate override.'
          using errcode = '42501';
      end if;

      if p_accept_pending_fx or p_rate_snapshot_id is not null
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
      raise exception 'Unknown-cost receipts do not accept exchange-rate evidence.'
        using errcode = '22023';
    end if;
  end if;

  if valuation_status_value = 'known_cost' then
    v_factor := power(10::numeric, shop_minor_units::numeric);
    target_minor := round(
      p_original_invoice_amount * accepted_rate,
      shop_minor_units
    ) * v_factor;

    -- Largest-remainder allocation. The invoice target is rounded using
    -- PostgreSQL numeric round (half away from zero for these nonnegative
    -- amounts); residual minor units go to the largest fractional remainder,
    -- with ascending line_number as the deterministic tie-breaker.
    with raw_lines as (
      select
        (entry.value ->> 'line_number')::integer as line_number,
        (entry.value ->> 'variant_id')::uuid as variant_id,
        (entry.value ->> 'quantity')::integer as quantity,
        (entry.value ->> 'original_line_amount')::numeric as original_line_amount
      from pg_catalog.jsonb_array_elements(p_lines) as entry(value)
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
        'line_number', line_number,
        'variant_id', variant_id,
        'quantity', quantity,
        'original_line_amount', original_line_amount,
        'converted_line_amount_shop', converted_line_amount_shop
      ) order by line_number
    )
      into allocated_lines
    from allocated;

    select sum((line.value ->> 'converted_line_amount_shop')::numeric)
      into converted_total
    from pg_catalog.jsonb_array_elements(allocated_lines) as line(value);

    if converted_total is distinct from target_minor / v_factor then
      raise exception 'Converted invoice lines did not reconcile exactly.'
        using errcode = '22003';
    end if;
  else
    select pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'line_number', (entry.value ->> 'line_number')::integer,
        'variant_id', (entry.value ->> 'variant_id')::uuid,
        'quantity', (entry.value ->> 'quantity')::integer,
        'original_line_amount', case
          when valuation_status_value = 'pending_fx'
            then (entry.value ->> 'original_line_amount')::numeric
          else null
        end,
        'converted_line_amount_shop', null
      ) order by (entry.value ->> 'line_number')::integer
    )
      into allocated_lines
    from pg_catalog.jsonb_array_elements(p_lines) as entry(value);
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

  for line_value in
    select item.value
    from pg_catalog.jsonb_array_elements(allocated_lines) as item(value)
    order by (item.value ->> 'line_number')::integer
  loop
    line_number_value := (line_value.value ->> 'line_number')::integer;
    variant_id_value := (line_value.value ->> 'variant_id')::uuid;
    quantity_value := (line_value.value ->> 'quantity')::integer;
    original_line_amount_value := nullif(
      line_value.value ->> 'original_line_amount', ''
    )::numeric;
    converted_line_amount_value := nullif(
      line_value.value ->> 'converted_line_amount_shop', ''
    )::numeric;

    select product.tracking_mode into tracking_mode_value
    from public.product_variants as variant
    join public.products as product
      on product.shop_id = variant.shop_id
     and product.id = variant.product_id
    where variant.shop_id = p_shop_id
      and variant.id = variant_id_value
      and variant.archived_at is null
      and product.archived_at is null;

    if not found or tracking_mode_value <> 'quantity' then
      raise exception 'Every receipt line must reference an active quantity-tracked variant in this shop.'
        using errcode = '22023';
    end if;

    if valuation_status_value = 'known_cost' then
      unit_cost_value := round(
        converted_line_amount_value / quantity_value,
        10
      );
    else
      unit_cost_value := null;
    end if;

    insert into public.inventory_receipt_lines (
      shop_id, branch_id, receipt_id, line_number, variant_id,
      quantity, original_line_amount, converted_line_amount_shop,
      unit_cost_shop, valuation_status, created_by
    ) values (
      p_shop_id, p_branch_id, receipt_id_value, line_number_value,
      variant_id_value, quantity_value, original_line_amount_value,
      converted_line_amount_value, unit_cost_value,
      valuation_status_value, current_user_id
    ) returning id into existing_receipt_id;

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

    new_quantity := current_balance.on_hand_qty + quantity_value;
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
          available_qty = balance.available_qty + quantity_value,
          carrying_value_shop = new_carrying_value,
          average_unit_cost_shop = new_average_unit_cost,
          updated_at = clock_timestamp(),
          updated_by = current_user_id
      where balance.id = current_balance.id;
    else
      update public.inventory_balances as balance
      set on_hand_qty = new_quantity,
          available_qty = balance.available_qty
            + case when valuation_status_value = 'unknown_cost'
                   then quantity_value else 0 end,
          updated_at = clock_timestamp(),
          updated_by = current_user_id
      where balance.id = current_balance.id;
    end if;

    insert into public.inventory_movements (
      shop_id, branch_id, operation_id, receipt_line_id, variant_id,
      movement_type, valuation_status, valuation_currency_code,
      on_hand_delta, available_delta, unit_cost_shop,
      extended_cost_shop, actor_id, line_number
    ) values (
      p_shop_id, p_branch_id, operation_id_value, existing_receipt_id,
      variant_id_value,
      case when valuation_status_value = 'pending_fx'
           then 'pending_fx_receipt'::public.inventory_movement_kind
           else 'receipt'::public.inventory_movement_kind end,
      valuation_status_value, shop_currency,
      quantity_value,
      case when valuation_status_value = 'pending_fx'
           then 0 else quantity_value end,
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

revoke all on function public.receive_quantity_inventory(
  uuid, uuid, text, text, text, text, text, numeric, jsonb,
  uuid, numeric, text, timestamptz, text, boolean
) from public, anon;
grant execute on function public.receive_quantity_inventory(
  uuid, uuid, text, text, text, text, text, numeric, jsonb,
  uuid, numeric, text, timestamptz, text, boolean
) to authenticated;

alter table public.currency_codes enable row level security;
alter table public.shop_settings enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.product_identifiers enable row level security;
alter table public.serialized_inventory enable row level security;
alter table public.serialized_identifiers enable row level security;
alter table public.exchange_rate_snapshots enable row level security;
alter table public.inventory_operations enable row level security;
alter table public.inventory_receipts enable row level security;
alter table public.inventory_receipt_lines enable row level security;
alter table public.inventory_balances enable row level security;
alter table public.branch_variant_prices enable row level security;
alter table public.inventory_fx_resolutions enable row level security;
alter table public.inventory_movements enable row level security;

revoke all on public.currency_codes, public.shop_settings, public.products,
  public.product_variants, public.product_identifiers,
  public.serialized_inventory, public.serialized_identifiers,
  public.exchange_rate_snapshots, public.inventory_operations,
  public.inventory_receipts, public.inventory_receipt_lines,
  public.inventory_balances, public.branch_variant_prices,
  public.inventory_fx_resolutions, public.inventory_movements
  from public, anon, authenticated, service_role;

grant select on public.currency_codes,
  public.exchange_rate_snapshots to authenticated;
grant select on public.shop_settings, public.products,
  public.product_variants, public.product_identifiers,
  public.serialized_inventory, public.serialized_identifiers,
  public.inventory_operations, public.inventory_receipts,
  public.inventory_receipt_lines, public.inventory_balances,
  public.branch_variant_prices, public.inventory_fx_resolutions,
  public.inventory_movements to authenticated;

-- Trusted server processes retain read access but cannot mutate inventory or
-- audit tables directly. The SECURITY DEFINER receiver writes as its postgres
-- owner; future rate ingestion must use a narrowly scoped RPC as well.
grant select on public.currency_codes, public.shop_settings, public.products,
  public.product_variants, public.product_identifiers,
  public.serialized_inventory, public.serialized_identifiers,
  public.exchange_rate_snapshots, public.inventory_operations,
  public.inventory_receipts, public.inventory_receipt_lines,
  public.inventory_balances, public.branch_variant_prices,
  public.inventory_fx_resolutions, public.inventory_movements to service_role;

create policy currency_codes_read_authenticated
  on public.currency_codes for select to authenticated
  using (enabled);

create policy exchange_rate_snapshots_read_authenticated
  on public.exchange_rate_snapshots for select to authenticated
  using (true);

create policy shop_settings_read_active_member
  on public.shop_settings for select to authenticated
  using (private.is_active_shop_member(shop_id));

create policy products_read_active_member
  on public.products for select to authenticated
  using (private.is_active_shop_member(shop_id));

create policy product_variants_read_active_member
  on public.product_variants for select to authenticated
  using (private.is_active_shop_member(shop_id));

create policy product_identifiers_read_active_member
  on public.product_identifiers for select to authenticated
  using (private.is_active_shop_member(shop_id));

create policy serialized_inventory_read_authorized_branch
  on public.serialized_inventory for select to authenticated
  using ((select private.can_access_branch(shop_id, branch_id)));

create policy serialized_identifiers_read_authorized_branch
  on public.serialized_identifiers for select to authenticated
  using ((select private.can_access_branch(shop_id, branch_id)));

create policy inventory_operations_read_authorized_branch
  on public.inventory_operations for select to authenticated
  using ((select private.can_access_branch(shop_id, branch_id)));

create policy inventory_receipts_read_authorized_branch
  on public.inventory_receipts for select to authenticated
  using ((select private.can_access_branch(shop_id, branch_id)));

create policy inventory_receipt_lines_read_authorized_branch
  on public.inventory_receipt_lines for select to authenticated
  using ((select private.can_access_branch(shop_id, branch_id)));

create policy inventory_balances_read_authorized_branch
  on public.inventory_balances for select to authenticated
  using ((select private.can_access_branch(shop_id, branch_id)));

create policy branch_variant_prices_read_authorized_branch
  on public.branch_variant_prices for select to authenticated
  using ((select private.can_access_branch(shop_id, branch_id)));

create policy inventory_fx_resolutions_read_authorized_branch
  on public.inventory_fx_resolutions for select to authenticated
  using ((select private.can_access_branch(shop_id, branch_id)));

create policy inventory_movements_read_authorized_branch
  on public.inventory_movements for select to authenticated
  using ((select private.can_access_branch(shop_id, branch_id)));
