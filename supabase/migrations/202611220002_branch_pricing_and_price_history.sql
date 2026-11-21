-- StockPilot Milestone 2, Phase 3B.
-- Branch-specific selling prices with transactional history and idempotency.
-- Apply only after isolated migration and pgTAP review.

begin;

-- The current-price table already has the shop/branch/variant uniqueness and
-- foreign keys. Add only the version column; do not add a duplicate lookup
-- index for the existing unique key.
do $migration$
declare
  invalid_price_ids text;
begin
  select string_agg(price.id::text, ', ' order by price.id)
    into invalid_price_ids
  from public.branch_variant_prices as price
  join public.shop_settings as settings
    on settings.shop_id = price.shop_id
  join public.currency_codes as currency
    on currency.code = price.price_currency_code
  where price.price_currency_code is distinct from settings.operating_currency_code
     or price.selling_price_shop < 0
     or price.selling_price_shop >= 'Infinity'::numeric
     or price.selling_price_shop <> round(
       price.selling_price_shop,
       currency.minor_units
     );

  if invalid_price_ids is not null then
    raise exception
      'Branch price migration stopped: rows % have a currency mismatch, invalid amount, or precision beyond the configured currency minor units. Review these rows; this migration will not round existing prices.',
      invalid_price_ids
      using errcode = '23514';
  end if;
end;
$migration$;

-- Do not introduce the new archival invariant on top of catalog rows that
-- were already archived while still owning stock. Stop without changing data
-- so those rows can be reviewed explicitly first.
do $migration$
declare
  affected_variant_ids text;
begin
  select string_agg(variant.id::text, ', ' order by variant.id)
    into affected_variant_ids
  from public.product_variants as variant
  join public.products as product
    on product.shop_id = variant.shop_id
   and product.id = variant.product_id
  where (product.archived_at is not null or variant.archived_at is not null)
    and (
      exists (
        select 1
        from public.inventory_balances as balance
        where balance.shop_id = variant.shop_id
          and balance.variant_id = variant.id
          and balance.on_hand_qty > 0
      )
      or exists (
        select 1
        from public.serialized_inventory as device
        where device.shop_id = variant.shop_id
          and device.variant_id = variant.id
          and device.availability_status not in ('sold', 'written_off')
      )
    );

  if affected_variant_ids is not null then
    raise exception
      'Stock-aware archival migration stopped: archived product/variant rows still own inventory for variants %. Review or restore these catalog rows before retrying; no records were changed.',
      affected_variant_ids
      using errcode = '23514';
  end if;
end;
$migration$;

alter table public.branch_variant_prices
  add column version bigint not null default 1,
  add constraint branch_variant_prices_version_positive
    check (version > 0);

create table public.branch_variant_price_operations (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  branch_id uuid not null,
  variant_id uuid not null,
  actor_id uuid not null references auth.users (id) on delete restrict,
  idempotency_key text not null,
  operation_type text not null,
  request_payload jsonb not null,
  result_price_id uuid not null,
  result_event_id uuid not null,
  result_version bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  unique (shop_id, id),
  unique (shop_id, actor_id, idempotency_key),
  foreign key (shop_id, branch_id)
    references public.branches (shop_id, id) on delete restrict,
  foreign key (shop_id, variant_id)
    references public.product_variants (shop_id, id) on delete restrict,
  foreign key (shop_id, result_price_id)
    references public.branch_variant_prices (shop_id, id)
    on delete restrict deferrable initially deferred,
  constraint branch_variant_price_operations_key_length
    check (char_length(btrim(idempotency_key)) between 8 and 120),
  constraint branch_variant_price_operations_type
    check (operation_type = 'set_branch_variant_price'),
  constraint branch_variant_price_operations_request_object
    check (jsonb_typeof(request_payload) = 'object'),
  constraint branch_variant_price_operations_version_positive
    check (result_version > 0)
);

create table public.branch_variant_price_events (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  branch_id uuid not null,
  variant_id uuid not null,
  price_id uuid not null,
  event_type text not null,
  previous_price numeric(38, 8),
  previous_currency_code char(3),
  new_price numeric(38, 8) not null,
  new_currency_code char(3) not null,
  actor_id uuid references auth.users (id) on delete restrict,
  captured_at timestamptz not null default clock_timestamp(),
  change_reason text,
  operation_id uuid,
  version_before bigint,
  version_after bigint not null,
  baseline_source_created_at timestamptz,
  baseline_source_created_by uuid references auth.users (id) on delete restrict,
  baseline_source_updated_at timestamptz,
  baseline_source_updated_by uuid references auth.users (id) on delete restrict,
  unique (shop_id, id),
  foreign key (shop_id, branch_id)
    references public.branches (shop_id, id) on delete restrict,
  foreign key (shop_id, variant_id)
    references public.product_variants (shop_id, id) on delete restrict,
  foreign key (shop_id, price_id)
    references public.branch_variant_prices (shop_id, id) on delete restrict,
  foreign key (previous_currency_code)
    references public.currency_codes (code) on update restrict on delete restrict,
  foreign key (new_currency_code)
    references public.currency_codes (code) on update restrict on delete restrict,
  foreign key (shop_id, operation_id)
    references public.branch_variant_price_operations (shop_id, id)
    on delete restrict,
  constraint branch_variant_price_events_type
    check (event_type in ('baseline', 'price_set', 'price_updated')),
  constraint branch_variant_price_events_prices_finite
    check (
      new_price >= 0 and new_price < 'Infinity'::numeric
      and (
        previous_price is null
        or (previous_price >= 0 and previous_price < 'Infinity'::numeric)
      )
    ),
  constraint branch_variant_price_events_version_positive
    check (version_after > 0),
  constraint branch_variant_price_events_shape
    check (
      (
        event_type = 'baseline'
        and previous_price is null
        and previous_currency_code is null
        and actor_id is null
        and change_reason is null
        and operation_id is null
        and version_before is null
        and version_after = 1
        and baseline_source_created_at is not null
        and baseline_source_created_by is not null
        and baseline_source_updated_at is not null
        and baseline_source_updated_by is not null
      )
      or
      (
        event_type = 'price_set'
        and previous_price is null
        and previous_currency_code is null
        and actor_id is not null
        and change_reason is not null
        and char_length(btrim(change_reason)) between 1 and 500
        and operation_id is not null
        and version_before = 0
        and version_after = 1
        and baseline_source_created_at is null
        and baseline_source_created_by is null
        and baseline_source_updated_at is null
        and baseline_source_updated_by is null
      )
      or
      (
        event_type = 'price_updated'
        and previous_price is not null
        and previous_currency_code is not null
        and actor_id is not null
        and change_reason is not null
        and char_length(btrim(change_reason)) between 1 and 500
        and operation_id is not null
        and version_before > 0
        and version_after = version_before + 1
        and baseline_source_created_at is null
        and baseline_source_created_by is null
        and baseline_source_updated_at is null
        and baseline_source_updated_by is null
      )
    )
);

-- Keep only post-migration assignment evidence. Existing branch memberships
-- are deliberately not backfilled because their historical authorization
-- intervals cannot be reconstructed from the current assignment rows.
create table private.branch_membership_price_access_events (
  history_id bigint generated always as identity primary key,
  shop_id uuid not null,
  branch_id uuid not null,
  user_id uuid not null,
  event_type text not null,
  membership_role public.shop_role,
  membership_status public.membership_status,
  recorded_at timestamptz not null default clock_timestamp(),
  recorded_by uuid references auth.users (id) on delete set null,
  foreign key (shop_id, branch_id)
    references public.branches (shop_id, id) on delete restrict,
  constraint branch_membership_price_access_events_type
    check (event_type in ('assigned', 'revoked')),
  constraint branch_membership_price_access_events_shape
    check (
      (event_type = 'assigned'
        and membership_role is not null
        and membership_status is not null)
      or
      (event_type = 'revoked'
        and membership_role is null
        and membership_status is null)
    )
);

create index branch_membership_price_access_events_scope_idx
  on private.branch_membership_price_access_events (
    shop_id, branch_id, user_id, recorded_at desc, history_id desc
  );

comment on table private.branch_membership_price_access_events is
  'Private append-only evidence for branch price-history authorization. No legacy assignment evidence is fabricated.';

alter table private.branch_membership_price_access_events
  enable row level security;
revoke all on private.branch_membership_price_access_events
  from public, anon, authenticated, service_role;

alter table public.branch_variant_price_operations
  add constraint branch_variant_price_operations_result_event_fkey
    foreign key (shop_id, result_event_id)
    references public.branch_variant_price_events (shop_id, id)
    on delete restrict deferrable initially deferred;

create unique index branch_variant_price_events_one_baseline_idx
  on public.branch_variant_price_events (price_id)
  where event_type = 'baseline';

create unique index branch_variant_price_events_one_operation_idx
  on public.branch_variant_price_events (operation_id)
  where operation_id is not null;

create index branch_variant_price_events_branch_history_idx
  on public.branch_variant_price_events (
    shop_id, branch_id, variant_id, captured_at desc
  );

comment on column public.branch_variant_prices.version is
  'Optimistic version incremented by the authorized branch price RPC.';
comment on table public.branch_variant_price_operations is
  'Append-only idempotency ledger for authorized branch price changes.';
comment on table public.branch_variant_price_events is
  'Append-only price history. Baseline events capture existing state without inventing prior changes.';
comment on column public.branch_variant_price_events.captured_at is
  'Migration capture time for baseline rows and transaction event time for user changes.';

-- A baseline is a migration-time snapshot, not a fabricated user operation.
-- Keep the existing price row's creator/updater evidence in separate source
-- columns and leave previous price, actor, reason, and operation NULL.
insert into public.branch_variant_price_events (
  shop_id, branch_id, variant_id, price_id, event_type,
  previous_price, previous_currency_code,
  new_price, new_currency_code, actor_id, captured_at,
  change_reason, operation_id, version_before, version_after,
  baseline_source_created_at, baseline_source_created_by,
  baseline_source_updated_at, baseline_source_updated_by
)
select
  price.shop_id, price.branch_id, price.variant_id, price.id, 'baseline',
  null, null,
  price.selling_price_shop, price.price_currency_code, null, clock_timestamp(),
  null, null, null, price.version,
  price.created_at, price.created_by, price.updated_at, price.updated_by
from public.branch_variant_prices as price
on conflict (price_id) where event_type = 'baseline' do nothing;

create or replace function private.assert_branch_price_editor(
  p_shop_id uuid,
  p_branch_id uuid
)
returns table (
  actor_id uuid,
  actor_role public.shop_role
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid := (select auth.uid());
  actor_role_value public.shop_role;
begin
  if actor_id_value is null or p_shop_id is null or p_branch_id is null then
    raise exception 'An active Owner or assigned Manager is required.'
      using errcode = '42501';
  end if;

  -- Lock the branch first: the branch-status trigger updates memberships.
  -- This order avoids a branch-status update waiting on a membership lock held
  -- by a price operation that is itself waiting for the branch row.
  perform 1
  from public.branches as branch
  where branch.shop_id = p_shop_id
    and branch.id = p_branch_id
    and branch.is_active
  for share;

  if not found then
    raise exception 'The branch is inactive or does not belong to this shop.'
      using errcode = '42501';
  end if;

  select membership.role
    into actor_role_value
  from public.shop_memberships as membership
  where membership.shop_id = p_shop_id
    and membership.user_id = actor_id_value
    and membership.status = 'active'
    and membership.role in (
      'owner'::public.shop_role,
      'manager'::public.shop_role
    )
  for share;

  if not found then
    raise exception 'An active Owner or assigned Manager is required.'
      using errcode = '42501';
  end if;

  if actor_role_value = 'manager'::public.shop_role then
    perform 1
    from public.branch_memberships as branch_membership
    where branch_membership.shop_id = p_shop_id
      and branch_membership.branch_id = p_branch_id
      and branch_membership.user_id = actor_id_value
    for share;

    if not found then
      raise exception 'Managers may set prices only for branches assigned to them.'
        using errcode = '42501';
    end if;
  end if;

  actor_id := actor_id_value;
  actor_role := actor_role_value;
  return next;
end;
$function$;

revoke all on function private.assert_branch_price_editor(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function private.record_branch_membership_price_access_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  member_role_value public.shop_role;
  member_status_value public.membership_status;
begin
  if tg_op = 'INSERT' then
    select membership.role, membership.status
      into member_role_value, member_status_value
    from public.shop_memberships as membership
    where membership.shop_id = new.shop_id
      and membership.user_id = new.user_id;

    if not found then
      raise exception 'Branch assignment history requires a shop membership.'
        using errcode = '23503';
    end if;

    insert into private.branch_membership_price_access_events (
      shop_id, branch_id, user_id, event_type,
      membership_role, membership_status, recorded_by
    ) values (
      new.shop_id, new.branch_id, new.user_id, 'assigned',
      member_role_value, member_status_value, (select auth.uid())
    );
    return new;
  end if;

  insert into private.branch_membership_price_access_events (
    shop_id, branch_id, user_id, event_type,
    membership_role, membership_status, recorded_by
  ) values (
    old.shop_id, old.branch_id, old.user_id, 'revoked',
    null, null, (select auth.uid())
  );
  return old;
end;
$function$;

revoke all on function private.record_branch_membership_price_access_event()
  from public, anon, authenticated, service_role;

create trigger branch_memberships_price_access_history
  after insert or delete on public.branch_memberships
  for each row execute function private.record_branch_membership_price_access_event();

create or replace function private.can_read_inactive_branch_price_event(
  p_shop_id uuid,
  p_branch_id uuid,
  p_event_at timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  -- A Manager must be actively assigned now and have post-migration evidence
  -- that the same uninterrupted assignment was active at the price-event
  -- timestamp. Revocation/reassignment ends this interval; a suspended shop
  -- membership fails the active-membership predicate above. Legacy rows with
  -- no evidence remain denied rather than being inferred from current access.
  select coalesce(
    p_event_at is not null
    and exists (
      select 1
      from public.branches as branch
      join public.shop_memberships as membership
        on membership.shop_id = branch.shop_id
      where branch.shop_id = p_shop_id
        and branch.id = p_branch_id
        and not branch.is_active
        and membership.user_id = (select auth.uid())
        and membership.status = 'active'
        and (
          membership.role = 'owner'::public.shop_role
          or (
            membership.role = 'manager'::public.shop_role
            and exists (
              select 1
              from public.branch_memberships as current_assignment
              where current_assignment.shop_id = p_shop_id
                and current_assignment.branch_id = p_branch_id
                and current_assignment.user_id = membership.user_id
            )
            and exists (
              select 1
              from private.branch_membership_price_access_events as assignment
              where assignment.shop_id = p_shop_id
                and assignment.branch_id = p_branch_id
                and assignment.user_id = membership.user_id
                and assignment.event_type = 'assigned'
                and assignment.membership_role = 'manager'::public.shop_role
                and assignment.membership_status = 'active'::public.membership_status
                and assignment.recorded_at <= p_event_at
                -- Access is limited to the current, uninterrupted assignment
                -- interval. Revocation or reassignment ends that interval.
                and not exists (
                  select 1
                  from private.branch_membership_price_access_events as later
                  where later.shop_id = assignment.shop_id
                    and later.branch_id = assignment.branch_id
                    and later.user_id = assignment.user_id
                    and (later.recorded_at, later.history_id)
                      > (assignment.recorded_at, assignment.history_id)
                )
            )
          )
        )
    ),
    false
  );
$function$;

revoke all on function private.can_read_inactive_branch_price_event(
  uuid, uuid, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function private.can_read_inactive_branch_price_event(
  uuid, uuid, timestamptz
) to authenticated;

create or replace function private.validate_branch_variant_price_event()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  current_price public.branch_variant_prices%rowtype;
  operation_row public.branch_variant_price_operations%rowtype;
begin
  select price.*
    into current_price
  from public.branch_variant_prices as price
  where price.shop_id = new.shop_id
    and price.id = new.price_id;

  if not found
    or current_price.branch_id is distinct from new.branch_id
    or current_price.variant_id is distinct from new.variant_id
    or current_price.selling_price_shop is distinct from new.new_price
    or current_price.price_currency_code is distinct from new.new_currency_code
    or current_price.version is distinct from new.version_after
  then
    raise exception 'Price history must match its tenant-scoped current price row.'
      using errcode = '23514';
  end if;

  if new.operation_id is not null then
    select operation.*
      into operation_row
    from public.branch_variant_price_operations as operation
    where operation.shop_id = new.shop_id
      and operation.id = new.operation_id;

    if not found
      or operation_row.branch_id is distinct from new.branch_id
      or operation_row.variant_id is distinct from new.variant_id
      or operation_row.actor_id is distinct from new.actor_id
      or operation_row.result_price_id is distinct from new.price_id
      or operation_row.result_event_id is distinct from new.id
      or operation_row.result_version is distinct from new.version_after
    then
      raise exception 'Price history does not match its idempotent operation.'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$function$;

revoke all on function private.validate_branch_variant_price_event()
  from public, anon, authenticated, service_role;

create trigger branch_variant_price_events_validate_before_insert
  before insert on public.branch_variant_price_events
  for each row execute function private.validate_branch_variant_price_event();

create or replace function private.reject_branch_price_history_mutation()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception 'Branch price operations and history are append-only.'
    using errcode = '42501';
end;
$function$;

revoke all on function private.reject_branch_price_history_mutation()
  from public, anon, authenticated, service_role;

create trigger branch_variant_price_operations_append_only
  before update or delete on public.branch_variant_price_operations
  for each row execute function private.reject_branch_price_history_mutation();
create trigger branch_variant_price_operations_no_truncate
  before truncate on public.branch_variant_price_operations
  for each statement execute function private.reject_branch_price_history_mutation();
create trigger branch_membership_price_access_events_append_only
  before update or delete on private.branch_membership_price_access_events
  for each row execute function private.reject_branch_price_history_mutation();
create trigger branch_membership_price_access_events_no_truncate
  before truncate on private.branch_membership_price_access_events
  for each statement execute function private.reject_branch_price_history_mutation();
create trigger branch_variant_price_events_append_only
  before update or delete on public.branch_variant_price_events
  for each row execute function private.reject_branch_price_history_mutation();
create trigger branch_variant_price_events_no_truncate
  before truncate on public.branch_variant_price_events
  for each statement execute function private.reject_branch_price_history_mutation();

-- Current owned-stock sources are quantity on-hand balances and every
-- serialized availability state except sold/written_off (including reserved
-- and Pending-FX). When custody or transfer tables are introduced, their
-- source-of-truth ownership rows must be included here, and their state-change
-- RPCs must participate in the products-table lock protocol below so archive
-- cannot race a new owned-stock state.
create or replace function private.variant_has_owned_stock(
  p_shop_id uuid,
  p_variant_id uuid
)
returns boolean
language sql
stable
set search_path = ''
as $function$
  select exists (
    select 1
    from public.inventory_balances as balance
    where balance.shop_id = p_shop_id
      and balance.variant_id = p_variant_id
      and balance.on_hand_qty > 0
  )
  or exists (
    select 1
    from public.serialized_inventory as device
    where device.shop_id = p_shop_id
      and device.variant_id = p_variant_id
      and device.availability_status not in ('sold', 'written_off')
  );
$function$;

revoke all on function private.variant_has_owned_stock(uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.set_branch_variant_price(
  p_shop_id uuid,
  p_branch_id uuid,
  p_variant_id uuid,
  p_price numeric,
  p_expected_version bigint,
  p_reason text,
  p_idempotency_key text
)
returns table (
  price_id uuid,
  version bigint,
  replayed boolean
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_id_value uuid;
  actor_role_value public.shop_role;
  currency_code_value char(3);
  currency_version_value integer;
  currency_minor_units smallint;
  normalized_reason text := nullif(btrim(p_reason), '');
  normalized_idempotency_key text := nullif(btrim(p_idempotency_key), '');
  request_value jsonb;
  existing_operation public.branch_variant_price_operations%rowtype;
  inserted_operation_id uuid;
  price_row public.branch_variant_prices%rowtype;
  price_exists boolean := false;
  previous_price_value numeric(38, 8);
  previous_currency_value char(3);
  price_id_value uuid;
  event_id_value uuid := gen_random_uuid();
  operation_id_value uuid := gen_random_uuid();
  result_version_value bigint;
  event_type_value text;
begin
  select editor.actor_id, editor.actor_role
    into actor_id_value, actor_role_value
  from private.assert_branch_price_editor(p_shop_id, p_branch_id)
    as editor;

  if p_variant_id is null
    or p_price is null
    or p_price < 0
    or p_price >= 'Infinity'::numeric
    or p_price >= 1000000000000000000000000000000::numeric
    or p_expected_version is null
    or p_expected_version < 0
    or normalized_reason is null
    or char_length(normalized_reason) > 500
    or normalized_idempotency_key is null
    or char_length(normalized_idempotency_key) not between 8 and 120
  then
    raise exception 'A finite nonnegative price, nonnegative version, reason, and valid idempotency key are required.'
      using errcode = '22023';
  end if;

  select settings.operating_currency_code,
         settings.currency_version,
         currency.minor_units
    into currency_code_value, currency_version_value, currency_minor_units
  from public.shop_settings as settings
  join public.currency_codes as currency
    on currency.code = settings.operating_currency_code
  where settings.shop_id = p_shop_id
    and currency.enabled
  for share of settings;

  if not found then
    raise exception 'Configure an enabled shop operating currency before setting prices.'
      using errcode = '22023';
  end if;

  if p_price <> round(p_price, currency_minor_units) then
    raise exception 'The price exceeds the shop currency minor-unit precision.'
      using errcode = '22023';
  end if;

  request_value := jsonb_build_object(
    'shop_id', p_shop_id,
    'branch_id', p_branch_id,
    'variant_id', p_variant_id,
    'price', p_price,
    'expected_version', p_expected_version,
    'reason', normalized_reason,
    'price_currency_code', btrim(currency_code_value::text),
    'currency_version', currency_version_value
  );

  -- Check completed operations before comparing the current version. A retry
  -- must return its original success even if a later price change has occurred.
  select operation.*
    into existing_operation
  from public.branch_variant_price_operations as operation
  where operation.shop_id = p_shop_id
    and operation.actor_id = actor_id_value
    and operation.idempotency_key = normalized_idempotency_key
  for update;

  if found then
    if existing_operation.operation_type is distinct from 'set_branch_variant_price'
      or existing_operation.request_payload is distinct from request_value
    then
      raise exception 'This idempotency key was already used for a different price request.'
        using errcode = '22023';
    end if;

    price_id := existing_operation.result_price_id;
    version := existing_operation.result_version;
    replayed := true;
    return next;
    return;
  end if;

  -- Archived catalog rows block new prices, but a completed authorized
  -- operation remains replayable. This check is therefore after the initial
  -- idempotency lookup and before any new operation or price write.
  perform 1
  from public.products as product
  join public.product_variants as variant
    on variant.shop_id = product.shop_id
   and variant.product_id = product.id
  where product.shop_id = p_shop_id
    and product.archived_at is null
    and variant.shop_id = p_shop_id
    and variant.id = p_variant_id
    and variant.archived_at is null
  for share of product, variant;

  if not found then
    raise exception 'The product or variant is archived or does not belong to this shop.'
      using errcode = '22023';
  end if;

  select price.*
    into price_row
  from public.branch_variant_prices as price
  where price.shop_id = p_shop_id
    and price.branch_id = p_branch_id
    and price.variant_id = p_variant_id
  for update;
  price_exists := found;

  if price_exists then
    if price_row.version = 9223372036854775807 then
      raise exception 'The branch price version cannot be incremented further.'
        using errcode = '22003';
    end if;
    price_id_value := price_row.id;
    previous_price_value := price_row.selling_price_shop;
    previous_currency_value := price_row.price_currency_code;
    result_version_value := price_row.version + 1;
    event_type_value := 'price_updated';
  else
    price_id_value := gen_random_uuid();
    result_version_value := 1;
    event_type_value := 'price_set';
  end if;

  insert into public.branch_variant_price_operations (
    id, shop_id, branch_id, variant_id, actor_id, idempotency_key,
    operation_type, request_payload, result_price_id, result_event_id,
    result_version
  ) values (
    operation_id_value, p_shop_id, p_branch_id, p_variant_id,
    actor_id_value, normalized_idempotency_key,
    'set_branch_variant_price', request_value, price_id_value,
    event_id_value, result_version_value
  )
  on conflict (shop_id, actor_id, idempotency_key) do nothing
  returning id into inserted_operation_id;

  if inserted_operation_id is null then
    select operation.*
      into existing_operation
    from public.branch_variant_price_operations as operation
    where operation.shop_id = p_shop_id
      and operation.actor_id = actor_id_value
      and operation.idempotency_key = normalized_idempotency_key
    for update;

    if not found then
      raise exception 'Price operation could not be resolved after an idempotency conflict.'
        using errcode = '40001';
    end if;

    if existing_operation.operation_type is distinct from 'set_branch_variant_price'
      or existing_operation.request_payload is distinct from request_value
    then
      raise exception 'This idempotency key was already used for a different price request.'
        using errcode = '22023';
    end if;

    price_id := existing_operation.result_price_id;
    version := existing_operation.result_version;
    replayed := true;
    return next;
    return;
  end if;

  if price_exists then
    if p_expected_version = 0
      or price_row.version is distinct from p_expected_version
    then
      raise exception 'Branch price changed since it was loaded; refresh and retry.'
        using errcode = '40001';
    end if;

    update public.branch_variant_prices as price
    set selling_price_shop = p_price,
        updated_at = clock_timestamp(),
        updated_by = actor_id_value,
        version = price.version + 1
    where price.shop_id = p_shop_id
      and price.branch_id = p_branch_id
      and price.variant_id = p_variant_id
      and price.version = p_expected_version
    returning price.* into price_row;

    if not found then
      raise exception 'Branch price changed since it was loaded; refresh and retry.'
        using errcode = '40001';
    end if;
  else
    if p_expected_version <> 0 then
      raise exception 'No branch price exists at the expected version; refresh and retry.'
        using errcode = '40001';
    end if;

    insert into public.branch_variant_prices (
      id, shop_id, branch_id, variant_id, price_currency_code,
      selling_price_shop, created_at, created_by,
      updated_at, updated_by, version
    ) values (
      price_id_value, p_shop_id, p_branch_id, p_variant_id,
      currency_code_value, p_price, clock_timestamp(), actor_id_value,
      clock_timestamp(), actor_id_value, 1
    )
    on conflict (shop_id, branch_id, variant_id) do nothing
    returning * into price_row;

    if not found then
      raise exception 'A branch price was created concurrently; refresh and retry.'
        using errcode = '40001';
    end if;
  end if;

  insert into public.branch_variant_price_events (
    id, shop_id, branch_id, variant_id, price_id, event_type,
    previous_price, previous_currency_code,
    new_price, new_currency_code, actor_id, captured_at,
    change_reason, operation_id, version_before, version_after
  ) values (
    event_id_value, p_shop_id, p_branch_id, p_variant_id, price_id_value,
    event_type_value,
    previous_price_value,
    previous_currency_value,
    p_price, currency_code_value, actor_id_value, clock_timestamp(),
    normalized_reason, operation_id_value,
    case when price_exists then p_expected_version else 0 end,
    result_version_value
  );

  price_id := price_id_value;
  version := result_version_value;
  replayed := false;
  return next;
end;
$function$;

-- Reinstall the catalog archival RPCs with stock checks. Existing inventory
-- receiving transactions read `products` before writing stock and hold their
-- relation lock until commit. The ACCESS EXCLUSIVE lock waits for those
-- transactions, then blocks new receivers until the stock check and archive
-- commit atomically. Future custody/transfer tables must join this protocol.
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
  -- Acquire the table lock before any product-row lock. Price and receiving
  -- RPCs read/lock product rows before writing, so taking this lock later can
  -- deadlock with a transaction waiting on one of those rows.
  lock table public.products in access exclusive mode;

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

  if exists (
    select 1
    from public.product_variants as variant
    where variant.shop_id = p_shop_id
      and variant.product_id = p_product_id
      and private.variant_has_owned_stock(variant.shop_id, variant.id)
  ) then
    raise exception 'A product cannot be archived while any variant still owns inventory.'
      using errcode = '23514';
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
  -- Match archive_product's lock order so stock/pricing transactions cannot
  -- hold a product relation lock while waiting on a row locked by this call.
  lock table public.products in access exclusive mode;

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

  if not found or product_row.id is null then
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

  if private.variant_has_owned_stock(p_shop_id, p_variant_id) then
    raise exception 'A variant cannot be archived while it still owns inventory.'
      using errcode = '23514';
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

revoke all on function public.set_branch_variant_price(
  uuid, uuid, uuid, numeric, bigint, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.set_branch_variant_price(
  uuid, uuid, uuid, numeric, bigint, text, text
) to authenticated;

alter table public.branch_variant_price_operations enable row level security;
alter table public.branch_variant_price_events enable row level security;

-- Preserve existing read access to current prices. Operations are private to
-- the RPC; authenticated history reads are branch-scoped by active access.
revoke all on public.branch_variant_prices,
  public.branch_variant_price_operations,
  public.branch_variant_price_events
  from public, anon, authenticated, service_role;
grant select on public.branch_variant_prices to authenticated, service_role;
grant select on public.branch_variant_price_events to authenticated;

create policy branch_variant_price_events_read_authorized_branch
  on public.branch_variant_price_events for select to authenticated
  using (
    (select private.can_access_branch(shop_id, branch_id))
    or (select private.can_read_inactive_branch_price_event(
      shop_id,
      branch_id,
      case
        when event_type = 'baseline'
          then coalesce(baseline_source_updated_at, captured_at)
        else captured_at
      end
    ))
  );

commit;
