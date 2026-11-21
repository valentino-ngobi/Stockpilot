-- Secure, same-shop inventory transfers between active branches.
-- Transfers preserve the original valuation basis and never create supplier
-- receipts, payables, sales, or FX records.
-- Deployment sizing: transfer tables are new and empty, but the additive
-- ALTER TABLE work locks populated balances, devices, operations, and movements;
-- the indexes scan source tables. This is suitable for the current early
-- deployment. A large deployment should measure lock duration and stage any
-- future large-table index/constraint validation separately.

alter table public.inventory_balances
  add column reserved_transfer_qty integer not null default 0;

alter table public.inventory_balances
  drop constraint inventory_balances_nonnegative_qty,
  add constraint inventory_balances_transfer_qty check (
    reserved_transfer_qty >= 0
    and available_qty + reserved_transfer_qty <= on_hand_qty
    and (valuation_status <> 'pending_fx' or reserved_transfer_qty = 0)
  );

-- Keep a dispatched serialized device unavailable while retaining its last
-- physically confirmed branch. The transfer header carries the route; this
-- additive marker distinguishes in-transit from an undispatched reservation.
alter table public.serialized_inventory
  add column transfer_state text,
  add constraint serialized_inventory_transfer_state_check check (
    transfer_state is null
    or (transfer_state = 'in_transit'
      and availability_status = 'reserved'
      and valuation_status <> 'pending_fx')
  );

create index serialized_inventory_transfer_state_idx
  on public.serialized_inventory (shop_id, branch_id, transfer_state)
  where transfer_state is not null;

create table public.inventory_transfers (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  source_branch_id uuid not null,
  destination_branch_id uuid not null,
  status text not null default 'requested',
  version bigint not null default 1,
  reason text not null,
  shop_currency_code char(3) not null,
  currency_version integer not null,
  requested_by uuid not null references auth.users (id) on delete restrict,
  requested_at timestamptz not null default clock_timestamp(),
  approved_by uuid references auth.users (id) on delete restrict,
  approved_at timestamptz,
  dispatched_by uuid references auth.users (id) on delete restrict,
  dispatched_at timestamptz,
  received_at timestamptz,
  cancelled_by uuid references auth.users (id) on delete restrict,
  cancelled_at timestamptz,
  unique (shop_id, id),
  foreign key (shop_id, source_branch_id)
    references public.branches (shop_id, id) on delete restrict,
  foreign key (shop_id, destination_branch_id)
    references public.branches (shop_id, id) on delete restrict,
  foreign key (shop_id, shop_currency_code)
    references public.shop_settings (shop_id, operating_currency_code)
    on update restrict on delete restrict,
  constraint inventory_transfers_distinct_branches check (
    source_branch_id <> destination_branch_id
  ),
  constraint inventory_transfers_status check (
    status in (
      'requested', 'approved', 'dispatched', 'partially_received',
      'received', 'cancelled'
    )
  ),
  constraint inventory_transfers_version_positive check (version > 0),
  constraint inventory_transfers_reason_length check (
    char_length(btrim(reason)) between 1 and 500
  ),
  constraint inventory_transfers_currency_version check (currency_version > 0),
  constraint inventory_transfers_stage_evidence check (
    (status = 'requested'
      and approved_by is null and approved_at is null
      and dispatched_by is null and dispatched_at is null
      and received_at is null and cancelled_by is null and cancelled_at is null)
    or (status = 'approved'
      and approved_by is not null and approved_at is not null
      and dispatched_by is null and dispatched_at is null
      and received_at is null and cancelled_by is null and cancelled_at is null)
    or (status in ('dispatched', 'partially_received')
      and approved_by is not null and approved_at is not null
      and dispatched_by is not null and dispatched_at is not null
      and received_at is null and cancelled_by is null and cancelled_at is null)
    or (status = 'received'
      and approved_by is not null and approved_at is not null
      and dispatched_by is not null and dispatched_at is not null
      and received_at is not null and cancelled_by is null and cancelled_at is null)
    or (status = 'cancelled'
      and cancelled_by is not null and cancelled_at is not null
      and received_at is null)
  )
);

create index inventory_transfers_source_status_idx
  on public.inventory_transfers (shop_id, source_branch_id, status, requested_at desc);
create index inventory_transfers_destination_status_idx
  on public.inventory_transfers (shop_id, destination_branch_id, status, requested_at desc);

create table public.inventory_transfer_lines (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  transfer_id uuid not null,
  line_number integer not null,
  variant_id uuid not null,
  tracking_mode text not null,
  valuation_status public.inventory_valuation_status not null,
  serialized_inventory_id uuid,
  requested_qty integer not null,
  approved_qty integer not null default 0,
  dispatched_qty integer not null default 0,
  received_qty integer not null default 0,
  claim_active boolean not null default false,
  unit_cost_shop numeric(38, 10),
  dispatched_value_shop numeric(38, 8),
  received_value_shop numeric(38, 8),
  created_at timestamptz not null default clock_timestamp(),
  unique (shop_id, id),
  unique (shop_id, transfer_id, id),
  unique (shop_id, transfer_id, line_number),
  foreign key (shop_id, transfer_id)
    references public.inventory_transfers (shop_id, id) on delete restrict,
  foreign key (shop_id, variant_id)
    references public.product_variants (shop_id, id) on delete restrict,
  foreign key (shop_id, variant_id, serialized_inventory_id)
    references public.serialized_inventory (shop_id, variant_id, id)
    on delete restrict,
  constraint inventory_transfer_lines_positive_qty check (
    line_number > 0 and requested_qty > 0
  ),
  constraint inventory_transfer_lines_progress check (
    approved_qty between 0 and requested_qty
    and dispatched_qty between 0 and approved_qty
    and received_qty between 0 and dispatched_qty
  ),
  constraint inventory_transfer_lines_mode check (
    (tracking_mode = 'quantity' and serialized_inventory_id is null
      and valuation_status in ('known_cost', 'unknown_cost'))
    or (tracking_mode = 'serialized' and serialized_inventory_id is not null
      and requested_qty = 1 and valuation_status in ('known_cost', 'unknown_cost'))
  ),
  constraint inventory_transfer_lines_claim check (
    not claim_active or serialized_inventory_id is not null
  ),
  constraint inventory_transfer_lines_value_state check (
    (valuation_status = 'unknown_cost'
      and unit_cost_shop is null
      and dispatched_value_shop is null
      and received_value_shop is null)
    or (valuation_status = 'known_cost'
      and (
        (dispatched_qty = 0 and unit_cost_shop is null
          and dispatched_value_shop is null and received_value_shop is null)
        or (dispatched_qty > 0 and unit_cost_shop is not null
          and unit_cost_shop >= 0 and unit_cost_shop < 'Infinity'::numeric
          and dispatched_value_shop is not null and dispatched_value_shop >= 0
          and dispatched_value_shop < 'Infinity'::numeric
          and received_value_shop is not null and received_value_shop >= 0
          and received_value_shop <= dispatched_value_shop)
      ))
  )
);

create unique index inventory_transfer_lines_one_active_device_idx
  on public.inventory_transfer_lines (shop_id, serialized_inventory_id)
  where serialized_inventory_id is not null and claim_active;
create unique index inventory_transfer_lines_one_quantity_bucket_idx
  on public.inventory_transfer_lines (
    shop_id, transfer_id, variant_id, valuation_status
  )
  where serialized_inventory_id is null;
create index inventory_transfer_lines_variant_idx
  on public.inventory_transfer_lines (shop_id, variant_id, transfer_id);

create table public.inventory_transfer_events (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  transfer_id uuid not null,
  line_id uuid,
  operation_id uuid not null,
  line_number integer not null,
  event_type text not null,
  prior_status text,
  new_status text,
  on_hand_delta integer not null default 0,
  available_delta integer not null default 0,
  reserved_transfer_delta integer not null default 0,
  value_shop numeric(38, 8),
  actor_id uuid not null references auth.users (id) on delete restrict,
  occurred_at timestamptz not null default clock_timestamp(),
  event_payload jsonb not null default '{}'::jsonb,
  unique (shop_id, id),
  unique (shop_id, operation_id, line_number),
  foreign key (shop_id, transfer_id)
    references public.inventory_transfers (shop_id, id) on delete restrict,
  foreign key (shop_id, transfer_id, line_id)
    references public.inventory_transfer_lines (shop_id, transfer_id, id)
    on delete restrict,
  foreign key (shop_id, operation_id)
    references public.inventory_operations (shop_id, id) on delete restrict,
  constraint inventory_transfer_events_line_number check (line_number >= 0),
  constraint inventory_transfer_events_type check (
    event_type in (
      'requested', 'line_requested', 'approved', 'line_reserved',
      'dispatched', 'line_dispatched', 'partially_received', 'received',
      'line_received', 'cancelled', 'line_reservation_released'
    )
  ),
  constraint inventory_transfer_events_payload_object check (
    jsonb_typeof(event_payload) = 'object'
  ),
  constraint inventory_transfer_events_finite_value check (
    value_shop is null or (value_shop >= 0 and value_shop < 'Infinity'::numeric)
  )
);

create index inventory_transfer_events_history_idx
  on public.inventory_transfer_events (shop_id, transfer_id, occurred_at, line_number);

-- Explicit, queryable position for stock owned by the shop while it is between
-- branches. The line's dispatched/received counters and value snapshots are
-- authoritative; final receipt consumes the exact residual.
create view public.inventory_transfer_in_transit
  with (security_invoker = true)
as
select line.shop_id,
       transfer.id as transfer_id,
       line.id as transfer_line_id,
       transfer.source_branch_id,
       transfer.destination_branch_id,
       line.variant_id,
       line.serialized_inventory_id,
       line.valuation_status,
       transfer.shop_currency_code as valuation_currency_code,
       line.dispatched_qty - line.received_qty as outstanding_qty,
       case when line.valuation_status = 'known_cost'
         then line.dispatched_value_shop - line.received_value_shop
         else null end as outstanding_value_shop,
       line.unit_cost_shop,
       transfer.status,
       transfer.version
from public.inventory_transfer_lines as line
join public.inventory_transfers as transfer
  on transfer.shop_id = line.shop_id and transfer.id = line.transfer_id
where line.dispatched_qty > line.received_qty;

-- A transfer result is an alternative to a receipt result. Existing receipt
-- operation rows retain their result_receipt_id unchanged.
alter table public.inventory_operations
  alter column result_receipt_id drop not null,
  add column result_transfer_id uuid;

alter table public.inventory_operations
  drop constraint inventory_operations_type,
  add constraint inventory_operations_type check (
    operation_type in (
      'quantity_receipt', 'serialized_receipt', 'pending_fx_release',
      'transfer_request', 'transfer_approval', 'transfer_dispatch',
      'transfer_receipt', 'transfer_cancellation'
    )
  ),
  add constraint inventory_operations_result_target check (
    (result_receipt_id is not null and result_transfer_id is null)
    or (result_receipt_id is null and result_transfer_id is not null)
  ),
  add constraint inventory_operations_result_transfer_fk
    foreign key (shop_id, result_transfer_id)
    references public.inventory_transfers (shop_id, id)
    on delete restrict deferrable initially deferred;

alter table public.inventory_movements
  add column transfer_line_id uuid,
  add constraint inventory_movements_receipt_transfer_line_exclusive check (
    receipt_line_id is null or transfer_line_id is null
  ),
  add constraint inventory_movements_transfer_line_fk
    foreign key (shop_id, transfer_line_id)
    references public.inventory_transfer_lines (shop_id, id) on delete restrict;

create index inventory_movements_transfer_line_idx
  on public.inventory_movements (shop_id, transfer_line_id)
  where transfer_line_id is not null;

create trigger inventory_transfer_events_append_only
  before update or delete on public.inventory_transfer_events
  for each row execute function private.reject_inventory_audit_mutation();
create trigger inventory_transfer_events_no_truncate
  before truncate on public.inventory_transfer_events
  for each statement execute function private.reject_inventory_audit_mutation();

create or replace function private.guard_serialized_transfer_state_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  line_row public.inventory_transfer_lines%rowtype;
  transfer_row public.inventory_transfers%rowtype;
begin
  if new.branch_id is not distinct from old.branch_id
    and new.availability_status is not distinct from old.availability_status
    and new.transfer_state is not distinct from old.transfer_state
  then
    return new;
  end if;

  select line.* into line_row
  from public.inventory_transfer_lines as line
  join public.inventory_transfers as transfer
    on transfer.shop_id = line.shop_id and transfer.id = line.transfer_id
  where line.shop_id = new.shop_id
    and line.serialized_inventory_id = new.id
    and transfer.status in (
      'requested', 'approved', 'dispatched', 'partially_received'
    )
  order by transfer.requested_at desc, line.id
  limit 1;

  if found then
    select transfer.* into transfer_row
    from public.inventory_transfers as transfer
    where transfer.shop_id = line_row.shop_id
      and transfer.id = line_row.transfer_id;
  end if;

  if old.transfer_state = 'in_transit' then
    if found
      and new.branch_id = transfer_row.destination_branch_id
      and new.availability_status = 'available'
      and new.transfer_state is null
      and line_row.dispatched_qty = 1
      and line_row.received_qty = 1
      and not line_row.claim_active
    then
      return new;
    end if;
    raise exception 'An in-transit device can only become available at its transfer destination after recorded receipt.'
      using errcode = '42501';
  end if;

  if new.transfer_state = 'in_transit' then
    if found
      and old.availability_status = 'reserved'
      and new.availability_status = 'reserved'
      and new.branch_id = transfer_row.source_branch_id
      and transfer_row.status = 'approved'
      and line_row.claim_active
      and line_row.approved_qty = 1
      and line_row.dispatched_qty = 1
      and line_row.received_qty = 0
    then
      return new;
    end if;
    raise exception 'Only a dispatched transfer device may enter the in-transit state.'
      using errcode = '42501';
  end if;

  if new.availability_status = 'reserved'
    and old.availability_status is distinct from 'reserved'
  then
    if found
      and old.availability_status = 'available'
      and old.transfer_state is null
      and new.transfer_state is null
      and new.branch_id = transfer_row.source_branch_id
      and transfer_row.status = 'requested'
      and line_row.claim_active
      and line_row.approved_qty = 1
      and line_row.dispatched_qty = 0
    then
      return new;
    end if;
    raise exception 'A serialized device may be reserved only by an approved transfer operation.'
      using errcode = '42501';
  end if;

  if old.availability_status = 'reserved'
    and old.transfer_state is null
    and found
  then
    if new.availability_status = 'available'
      and new.transfer_state is null
      and new.branch_id = transfer_row.source_branch_id
      and transfer_row.status = 'approved'
      and line_row.approved_qty = 1
      and line_row.dispatched_qty = 0
      and not line_row.claim_active
    then
      return new;
    end if;
    raise exception 'A transfer-reserved device may only be dispatched or released by pre-dispatch cancellation.'
      using errcode = '42501';
  end if;

  if old.transfer_state is null
    and new.transfer_state is not null
  then
    raise exception 'Unsupported serialized transfer state transition.'
      using errcode = '42501';
  end if;

  return new;
end;
$function$;

revoke all on function private.guard_serialized_transfer_state_update()
  from public, anon, authenticated, service_role;

create trigger serialized_inventory_guard_transfer_state
  before update of branch_id, availability_status, transfer_state
  on public.serialized_inventory
  for each row execute function private.guard_serialized_transfer_state_update();

create or replace function private.assert_inventory_transfer_access(
  p_shop_id uuid,
  p_source_branch_id uuid,
  p_destination_branch_id uuid,
  p_action text
)
returns table (actor_id uuid, actor_role public.shop_role)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_value uuid := (select auth.uid());
  role_value public.shop_role;
  branch_row record;
  branch_count integer := 0;
  assignment_count integer := 0;
begin
  if actor_value is null or p_shop_id is null
    or p_source_branch_id is null or p_destination_branch_id is null
    or p_source_branch_id = p_destination_branch_id
    or p_action is null
    or p_action not in ('request', 'approve', 'dispatch', 'receive', 'cancel')
  then
    raise exception 'Transfer authorization or branch parameters are invalid.'
      using errcode = '42501';
  end if;

  -- Branch rows are locked in a stable order. This prevents deactivation while
  -- an operation is authorized and follows the branch-first price RPC pattern.
  for branch_row in
    select branch.id
    from public.branches as branch
    where branch.shop_id = p_shop_id
      and branch.is_active
      and branch.id in (p_source_branch_id, p_destination_branch_id)
    order by branch.id
    for share
  loop
    branch_count := branch_count + 1;
  end loop;

  if branch_count <> 2 then
    raise exception 'Both transfer branches must be active and belong to this shop.'
      using errcode = '42501';
  end if;

  select membership.role into role_value
  from public.shop_memberships as membership
  where membership.shop_id = p_shop_id
    and membership.user_id = actor_value
    and membership.status = 'active'
  for share;

  if not found then
    raise exception 'An active shop membership is required for this transfer.'
      using errcode = '42501';
  end if;

  if (p_action = 'approve' and role_value not in ('owner', 'manager'))
    or (p_action in ('request', 'dispatch', 'receive', 'cancel')
      and role_value not in ('owner', 'manager', 'inventory_staff'))
  then
    raise exception 'This shop role cannot perform the requested transfer action.'
      using errcode = '42501';
  end if;

  if role_value <> 'owner' then
    perform assignment.branch_id
    from public.branch_memberships as assignment
    where assignment.shop_id = p_shop_id
      and assignment.user_id = actor_value
      and assignment.branch_id in (p_source_branch_id, p_destination_branch_id)
    order by assignment.branch_id
    for share;

    select count(*)::integer into assignment_count
    from public.branch_memberships as assignment
    where assignment.shop_id = p_shop_id
      and assignment.user_id = actor_value
      and assignment.branch_id in (p_source_branch_id, p_destination_branch_id);

    if (p_action = 'approve' and assignment_count <> 2)
      or (p_action in ('request', 'dispatch', 'cancel')
        and not exists (
          select 1 from public.branch_memberships as assignment
          where assignment.shop_id = p_shop_id
            and assignment.branch_id = p_source_branch_id
            and assignment.user_id = actor_value
        ))
      or (p_action = 'receive'
        and not exists (
          select 1 from public.branch_memberships as assignment
          where assignment.shop_id = p_shop_id
            and assignment.branch_id = p_destination_branch_id
            and assignment.user_id = actor_value
        ))
    then
      raise exception 'The member is not assigned to the branch required for this transfer action.'
        using errcode = '42501';
    end if;
  end if;

  actor_id := actor_value;
  actor_role := role_value;
  return next;
end;
$function$;

revoke all on function private.assert_inventory_transfer_access(uuid, uuid, uuid, text)
  from public, anon, authenticated, service_role;

create or replace function private.lock_inventory_transfer_currency(p_shop_id uuid)
returns table (
  currency_code char(3),
  currency_version integer,
  currency_minor_units smallint
)
language plpgsql
security definer
set search_path = ''
as $function$
begin
  select settings.operating_currency_code,
         settings.currency_version,
         currency.minor_units
    into currency_code, currency_version, currency_minor_units
  from public.shop_settings as settings
  join public.currency_codes as currency
    on currency.code = settings.operating_currency_code
   and currency.enabled
  where settings.shop_id = p_shop_id
  for update of settings;

  if not found or currency_minor_units is null then
    raise exception 'Configure an enabled shop operating currency before transferring inventory.'
      using errcode = '22023';
  end if;
  return next;
end;
$function$;

revoke all on function private.lock_inventory_transfer_currency(uuid)
  from public, anon, authenticated, service_role;

create or replace function private.claim_inventory_transfer_operation(
  p_shop_id uuid,
  p_branch_id uuid,
  p_actor_id uuid,
  p_idempotency_key text,
  p_operation_type text,
  p_request_payload jsonb,
  p_transfer_id uuid,
  p_currency_code char(3),
  p_currency_version integer
)
returns table (operation_id uuid, replayed boolean, result_transfer_id uuid)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  inserted_id uuid;
  existing_row public.inventory_operations%rowtype;
begin
  if p_idempotency_key is null
    or char_length(btrim(p_idempotency_key)) not between 8 and 120
    or p_request_payload is null
    or jsonb_typeof(p_request_payload) is distinct from 'object'
    or p_transfer_id is null
  then
    raise exception 'A valid transfer idempotency key and request are required.'
      using errcode = '22023';
  end if;

  insert into public.inventory_operations (
    shop_id, branch_id, operation_type, actor_id, idempotency_key,
    request_payload, result_receipt_id, result_transfer_id,
    valuation_currency_code, currency_version
  ) values (
    p_shop_id, p_branch_id, p_operation_type, p_actor_id,
    btrim(p_idempotency_key), p_request_payload, null, p_transfer_id,
    p_currency_code, p_currency_version
  )
  on conflict (shop_id, actor_id, idempotency_key) do nothing
  returning id into inserted_id;

  if inserted_id is not null then
    operation_id := inserted_id;
    replayed := false;
    result_transfer_id := p_transfer_id;
    return next;
    return;
  end if;

  select operation.* into existing_row
  from public.inventory_operations as operation
  where operation.shop_id = p_shop_id
    and operation.actor_id = p_actor_id
    and operation.idempotency_key = btrim(p_idempotency_key)
  for update;

  if not found then
    raise exception 'Transfer operation could not be resolved after an idempotency conflict.'
      using errcode = '40001';
  end if;

  if existing_row.operation_type is distinct from p_operation_type
    or existing_row.request_payload is distinct from p_request_payload
    or existing_row.result_transfer_id is null
    or (p_operation_type <> 'transfer_request'
      and existing_row.result_transfer_id is distinct from p_transfer_id)
  then
    raise exception 'This idempotency key was already used for a different transfer request.'
      using errcode = '23505';
  end if;

  operation_id := existing_row.id;
  replayed := true;
  result_transfer_id := existing_row.result_transfer_id;
  return next;
end;
$function$;

revoke all on function private.claim_inventory_transfer_operation(
  uuid, uuid, uuid, text, text, jsonb, uuid, char, integer
) from public, anon, authenticated, service_role;

create or replace function private.record_inventory_transfer_event(
  p_shop_id uuid,
  p_transfer_id uuid,
  p_line_id uuid,
  p_operation_id uuid,
  p_line_number integer,
  p_event_type text,
  p_prior_status text,
  p_new_status text,
  p_on_hand_delta integer,
  p_available_delta integer,
  p_reserved_transfer_delta integer,
  p_value_shop numeric,
  p_actor_id uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  event_id_value uuid;
begin
  insert into public.inventory_transfer_events (
    shop_id, transfer_id, line_id, operation_id, line_number,
    event_type, prior_status, new_status, on_hand_delta, available_delta,
    reserved_transfer_delta, value_shop, actor_id, event_payload
  ) values (
    p_shop_id, p_transfer_id, p_line_id, p_operation_id, p_line_number,
    p_event_type, p_prior_status, p_new_status, p_on_hand_delta,
    p_available_delta, p_reserved_transfer_delta, p_value_shop, p_actor_id,
    coalesce(p_payload, '{}'::jsonb)
  ) returning id into event_id_value;
  return event_id_value;
end;
$function$;

revoke all on function private.record_inventory_transfer_event(
  uuid, uuid, uuid, uuid, integer, text, text, text, integer, integer, integer,
  numeric, uuid, jsonb
) from public, anon, authenticated, service_role;

create or replace function public.request_inventory_transfer(
  p_shop_id uuid,
  p_source_branch_id uuid,
  p_destination_branch_id uuid,
  p_lines jsonb,
  p_reason text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_record record;
  currency_record record;
  operation_record record;
  transfer_id_value uuid := gen_random_uuid();
  line_value record;
  variant_id_value uuid;
  serialized_id_value uuid;
  quantity_value integer;
  valuation_status_value public.inventory_valuation_status;
  tracking_mode_value text;
  variant_shop_id uuid;
  active_product boolean;
  line_id_value uuid;
  line_number_value integer;
  trimmed_reason text := nullif(btrim(p_reason), '');
  request_payload_value jsonb;
begin
  select * into actor_record
  from private.assert_inventory_transfer_access(
    p_shop_id, p_source_branch_id, p_destination_branch_id, 'request'
  );

  select * into currency_record
  from private.lock_inventory_transfer_currency(p_shop_id);

  if trimmed_reason is null or char_length(trimmed_reason) > 500 then
    raise exception 'A transfer reason between 1 and 500 characters is required.'
      using errcode = '22023';
  end if;

  request_payload_value := jsonb_build_object(
    'shop_id', p_shop_id,
    'source_branch_id', p_source_branch_id,
    'destination_branch_id', p_destination_branch_id,
    'lines', p_lines,
    'reason', trimmed_reason
  );

  select * into operation_record
  from private.claim_inventory_transfer_operation(
    p_shop_id, p_source_branch_id, actor_record.actor_id,
    p_idempotency_key, 'transfer_request', request_payload_value,
    transfer_id_value, currency_record.currency_code,
    currency_record.currency_version
  );

  if operation_record.replayed then
    return operation_record.result_transfer_id;
  end if;

  if p_lines is null or jsonb_typeof(p_lines) is distinct from 'array'
    or jsonb_array_length(p_lines) = 0
    or jsonb_array_length(p_lines) > 500
  then
    raise exception 'Transfer lines must be a nonempty array of at most 500 entries.'
      using errcode = '22023';
  end if;

  -- Compatible with catalog archival: take the relation lock before reading
  -- product rows, but do not row-lock them (the catalog update RPC takes its
  -- ACCESS EXCLUSIVE table lock after a product row lock).
  lock table public.products in row share mode;

  insert into public.inventory_transfers (
    id, shop_id, source_branch_id, destination_branch_id, status, version,
    reason, shop_currency_code, currency_version, requested_by
  ) values (
    transfer_id_value, p_shop_id, p_source_branch_id, p_destination_branch_id,
    'requested', 1, trimmed_reason, currency_record.currency_code,
    currency_record.currency_version, actor_record.actor_id
  );

  line_number_value := 0;
  for line_value in
    select item.value, item.ordinality::integer as line_number
    from jsonb_array_elements(p_lines) with ordinality as item(value, ordinality)
    order by item.ordinality
  loop
    line_number_value := line_value.line_number;

    if jsonb_typeof(line_value.value) is distinct from 'object' then
      raise exception 'Each transfer line must be a JSON object.'
        using errcode = '22023';
    end if;

    if line_value.value ? 'serialized_inventory_id' then
      if (select count(*) from jsonb_object_keys(line_value.value)) <> 1
        or jsonb_typeof(line_value.value -> 'serialized_inventory_id') is distinct from 'string'
        or (line_value.value ->> 'serialized_inventory_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then
        raise exception 'Serialized transfer lines must contain only a valid serialized_inventory_id.'
          using errcode = '22023';
      end if;

      serialized_id_value := (line_value.value ->> 'serialized_inventory_id')::uuid;
      select device.variant_id, device.valuation_status
        into variant_id_value, valuation_status_value
      from public.serialized_inventory as device
      join public.product_variants as variant
        on variant.shop_id = device.shop_id and variant.id = device.variant_id
      join public.products as product
        on product.shop_id = variant.shop_id and product.id = variant.product_id
      where device.shop_id = p_shop_id
        and device.branch_id = p_source_branch_id
        and device.id = serialized_id_value
        and device.availability_status = 'available'
        and device.transfer_state is null
        and device.valuation_status in ('known_cost', 'unknown_cost')
        and variant.archived_at is null
        and product.archived_at is null
        and product.tracking_mode = 'serialized';

      if not found then
        raise exception 'The serialized item is unavailable, archived, pending FX, or not at the source branch.'
          using errcode = '23514';
      end if;

      insert into public.inventory_transfer_lines (
        shop_id, transfer_id, line_number, variant_id, tracking_mode,
        valuation_status, serialized_inventory_id, requested_qty, claim_active
      ) values (
        p_shop_id, transfer_id_value, line_number_value, variant_id_value,
        'serialized', valuation_status_value, serialized_id_value, 1, true
      ) returning id into line_id_value;

      perform private.record_inventory_transfer_event(
        p_shop_id, transfer_id_value, line_id_value, operation_record.operation_id,
        line_number_value, 'line_requested', null, 'requested', 0, 0, 0, null,
        actor_record.actor_id, jsonb_build_object(
          'variant_id', variant_id_value,
          'serialized_inventory_id', serialized_id_value,
          'requested_qty', 1,
          'valuation_status', valuation_status_value
        )
      );
    else
      if (select count(*) from jsonb_object_keys(line_value.value)) <> 3
        or not (line_value.value ?& array['variant_id', 'valuation_status', 'quantity'])
        or jsonb_typeof(line_value.value -> 'variant_id') is distinct from 'string'
        or (line_value.value ->> 'variant_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        or jsonb_typeof(line_value.value -> 'valuation_status') is distinct from 'string'
        or jsonb_typeof(line_value.value -> 'quantity') is distinct from 'number'
        or (line_value.value ->> 'quantity') !~ '^[1-9][0-9]*$'
      then
        raise exception 'Quantity transfer lines require variant_id, known_cost or unknown_cost, and a positive integer quantity.'
          using errcode = '22023';
      end if;

      variant_id_value := (line_value.value ->> 'variant_id')::uuid;
      quantity_value := (line_value.value ->> 'quantity')::integer;
      valuation_status_value := (line_value.value ->> 'valuation_status')::public.inventory_valuation_status;

      if valuation_status_value not in ('known_cost', 'unknown_cost') then
        raise exception 'Pending-FX stock cannot be transferred.'
          using errcode = '23514';
      end if;

      select product.tracking_mode, variant.shop_id,
             product.archived_at is null and variant.archived_at is null
        into tracking_mode_value, variant_shop_id, active_product
      from public.product_variants as variant
      join public.products as product
        on product.shop_id = variant.shop_id and product.id = variant.product_id
      where variant.shop_id = p_shop_id and variant.id = variant_id_value;

      if not found or tracking_mode_value <> 'quantity' or not active_product then
        raise exception 'Quantity transfer lines require an active quantity-tracked variant in this shop.'
          using errcode = '23514';
      end if;

      insert into public.inventory_transfer_lines (
        shop_id, transfer_id, line_number, variant_id, tracking_mode,
        valuation_status, requested_qty
      ) values (
        p_shop_id, transfer_id_value, line_number_value, variant_id_value,
        'quantity', valuation_status_value, quantity_value
      ) returning id into line_id_value;

      perform private.record_inventory_transfer_event(
        p_shop_id, transfer_id_value, line_id_value, operation_record.operation_id,
        line_number_value, 'line_requested', null, 'requested', 0, 0, 0,
        null, actor_record.actor_id, jsonb_build_object(
          'variant_id', variant_id_value,
          'requested_qty', quantity_value,
          'valuation_status', valuation_status_value
        )
      );
    end if;
  end loop;

  perform private.record_inventory_transfer_event(
    p_shop_id, transfer_id_value, null, operation_record.operation_id, 0,
    'requested', null, 'requested', 0, 0, 0, null, actor_record.actor_id,
    jsonb_build_object('reason', trimmed_reason, 'line_count', line_number_value)
  );

  return transfer_id_value;
end;
$function$;

create or replace function public.approve_inventory_transfer(
  p_shop_id uuid,
  p_transfer_id uuid,
  p_expected_version bigint,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  transfer_row public.inventory_transfers%rowtype;
  actor_record record;
  currency_record record;
  operation_record record;
  line_row public.inventory_transfer_lines%rowtype;
  device_row public.serialized_inventory%rowtype;
  balance_row public.inventory_balances%rowtype;
  request_payload_value jsonb;
begin
  select transfer.* into transfer_row
  from public.inventory_transfers as transfer
  where transfer.shop_id = p_shop_id and transfer.id = p_transfer_id;
  if not found then
    raise exception 'The transfer does not exist in this shop.'
      using errcode = '22023';
  end if;

  select * into actor_record
  from private.assert_inventory_transfer_access(
    p_shop_id, transfer_row.source_branch_id,
    transfer_row.destination_branch_id, 'approve'
  );
  select * into currency_record
  from private.lock_inventory_transfer_currency(p_shop_id);

  request_payload_value := jsonb_build_object(
    'transfer_id', p_transfer_id,
    'expected_version', p_expected_version
  );
  select * into operation_record
  from private.claim_inventory_transfer_operation(
    p_shop_id, transfer_row.source_branch_id, actor_record.actor_id,
    p_idempotency_key, 'transfer_approval', request_payload_value,
    p_transfer_id, currency_record.currency_code,
    currency_record.currency_version
  );
  if operation_record.replayed then
    return operation_record.result_transfer_id;
  end if;

  select transfer.* into transfer_row
  from public.inventory_transfers as transfer
  where transfer.shop_id = p_shop_id and transfer.id = p_transfer_id
  for update;

  if transfer_row.status <> 'requested'
    or p_expected_version is null
    or transfer_row.version <> p_expected_version
  then
    raise exception 'The transfer is not requestable at the supplied version.'
      using errcode = '40001';
  end if;
  if transfer_row.shop_currency_code is distinct from currency_record.currency_code
    or transfer_row.currency_version <> currency_record.currency_version
  then
    raise exception 'The shop valuation currency changed after this transfer was requested.'
      using errcode = '23514';
  end if;

  lock table public.products in row share mode;

  for line_row in
    select line.*
    from public.inventory_transfer_lines as line
    where line.shop_id = p_shop_id and line.transfer_id = p_transfer_id
    order by line.variant_id, line.valuation_status, line.serialized_inventory_id nulls first
    for update
  loop
    if line_row.tracking_mode = 'serialized' then
      select device.* into device_row
      from public.serialized_inventory as device
      where device.shop_id = p_shop_id
        and device.variant_id = line_row.variant_id
        and device.id = line_row.serialized_inventory_id
        and device.branch_id = transfer_row.source_branch_id
        and device.availability_status = 'available'
        and device.transfer_state is null
        and device.valuation_status = line_row.valuation_status
      for update;
      if not found then
        raise exception 'A requested serialized item is no longer available at the source branch.'
          using errcode = '23514';
      end if;
    end if;

    select balance.* into balance_row
    from public.inventory_balances as balance
    where balance.shop_id = p_shop_id
      and balance.branch_id = transfer_row.source_branch_id
      and balance.variant_id = line_row.variant_id
      and balance.valuation_status = line_row.valuation_status
    for update;

    if not found or balance_row.available_qty < line_row.requested_qty
      or balance_row.on_hand_qty < line_row.requested_qty
    then
      raise exception 'Insufficient available stock to approve every requested transfer line.'
        using errcode = '23514';
    end if;

    update public.inventory_balances
    set available_qty = available_qty - line_row.requested_qty,
        reserved_transfer_qty = reserved_transfer_qty + line_row.requested_qty,
        updated_at = clock_timestamp(),
        updated_by = actor_record.actor_id
    where shop_id = p_shop_id and id = balance_row.id;

    update public.inventory_transfer_lines
    set approved_qty = requested_qty
    where shop_id = p_shop_id and id = line_row.id;

    if line_row.tracking_mode = 'serialized' then
      update public.serialized_inventory
      set availability_status = 'reserved',
          updated_at = clock_timestamp(),
          updated_by = actor_record.actor_id
      where shop_id = p_shop_id and id = line_row.serialized_inventory_id;
    end if;

    perform private.record_inventory_transfer_event(
      p_shop_id, p_transfer_id, line_row.id, operation_record.operation_id,
      line_row.line_number, 'line_reserved', 'requested', 'approved',
      0, -line_row.requested_qty, line_row.requested_qty, null,
      actor_record.actor_id, jsonb_build_object(
        'variant_id', line_row.variant_id,
        'requested_qty', line_row.requested_qty,
        'on_hand_delta', 0,
        'available_delta', -line_row.requested_qty,
        'reserved_transfer_delta', line_row.requested_qty,
        'valuation_status', line_row.valuation_status
      )
    );
  end loop;

  update public.inventory_transfers
  set status = 'approved', version = version + 1,
      approved_by = actor_record.actor_id, approved_at = clock_timestamp()
  where shop_id = p_shop_id and id = p_transfer_id;

  perform private.record_inventory_transfer_event(
    p_shop_id, p_transfer_id, null, operation_record.operation_id, 0,
    'approved', 'requested', 'approved', 0, 0, 0, null,
    actor_record.actor_id, jsonb_build_object('approved_line_count', (
      select count(*) from public.inventory_transfer_lines as line
      where line.shop_id = p_shop_id and line.transfer_id = p_transfer_id
    ))
  );

  return p_transfer_id;
end;
$function$;

create or replace function public.dispatch_inventory_transfer(
  p_shop_id uuid,
  p_transfer_id uuid,
  p_expected_version bigint,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  transfer_row public.inventory_transfers%rowtype;
  actor_record record;
  currency_record record;
  operation_record record;
  line_row public.inventory_transfer_lines%rowtype;
  device_row public.serialized_inventory%rowtype;
  balance_row public.inventory_balances%rowtype;
  moved_value numeric(38, 8);
  remaining_value numeric(38, 8);
  remaining_qty integer;
  unit_cost_value numeric(38, 10);
  request_payload_value jsonb;
begin
  select transfer.* into transfer_row
  from public.inventory_transfers as transfer
  where transfer.shop_id = p_shop_id and transfer.id = p_transfer_id;
  if not found then
    raise exception 'The transfer does not exist in this shop.'
      using errcode = '22023';
  end if;

  select * into actor_record
  from private.assert_inventory_transfer_access(
    p_shop_id, transfer_row.source_branch_id,
    transfer_row.destination_branch_id, 'dispatch'
  );
  select * into currency_record
  from private.lock_inventory_transfer_currency(p_shop_id);

  request_payload_value := jsonb_build_object(
    'transfer_id', p_transfer_id,
    'expected_version', p_expected_version
  );
  select * into operation_record
  from private.claim_inventory_transfer_operation(
    p_shop_id, transfer_row.source_branch_id, actor_record.actor_id,
    p_idempotency_key, 'transfer_dispatch', request_payload_value,
    p_transfer_id, currency_record.currency_code,
    currency_record.currency_version
  );
  if operation_record.replayed then
    return operation_record.result_transfer_id;
  end if;

  select transfer.* into transfer_row
  from public.inventory_transfers as transfer
  where transfer.shop_id = p_shop_id and transfer.id = p_transfer_id
  for update;

  if transfer_row.status <> 'approved'
    or p_expected_version is null
    or transfer_row.version <> p_expected_version
  then
    raise exception 'Only the current approved transfer can be dispatched.'
      using errcode = '40001';
  end if;
  if transfer_row.shop_currency_code is distinct from currency_record.currency_code
    or transfer_row.currency_version <> currency_record.currency_version
  then
    raise exception 'The shop valuation currency changed after this transfer was requested.'
      using errcode = '23514';
  end if;

  lock table public.products in row share mode;

  for line_row in
    select line.*
    from public.inventory_transfer_lines as line
    where line.shop_id = p_shop_id and line.transfer_id = p_transfer_id
    order by line.variant_id, line.valuation_status, line.serialized_inventory_id nulls first
    for update
  loop
    if line_row.tracking_mode = 'serialized' then
      select device.* into device_row
      from public.serialized_inventory as device
      where device.shop_id = p_shop_id
        and device.variant_id = line_row.variant_id
        and device.id = line_row.serialized_inventory_id
        and device.branch_id = transfer_row.source_branch_id
        and device.availability_status = 'reserved'
        and device.transfer_state is null
        and device.valuation_status = line_row.valuation_status
      for update;
      if not found then
        raise exception 'A reserved serialized item is no longer dispatchable.'
          using errcode = '23514';
      end if;
    end if;

    select balance.* into balance_row
    from public.inventory_balances as balance
    where balance.shop_id = p_shop_id
      and balance.branch_id = transfer_row.source_branch_id
      and balance.variant_id = line_row.variant_id
      and balance.valuation_status = line_row.valuation_status
    for update;

    if not found
      or balance_row.on_hand_qty < line_row.approved_qty
      or balance_row.reserved_transfer_qty < line_row.approved_qty
    then
      raise exception 'Reserved source stock is unavailable for dispatch.'
        using errcode = '23514';
    end if;

    remaining_qty := balance_row.on_hand_qty - line_row.approved_qty;
    if line_row.valuation_status = 'known_cost' then
      if line_row.tracking_mode = 'serialized' then
        -- Serialized receiving records each device's own cost. Keep that exact
        -- evidence rather than assigning the bucket's weighted average to the
        -- device being moved.
        moved_value := round(device_row.unit_cost_shop, 8);
      elsif line_row.approved_qty = balance_row.on_hand_qty then
        moved_value := balance_row.carrying_value_shop;
      else
        moved_value := round(
          balance_row.carrying_value_shop * line_row.approved_qty
            / balance_row.on_hand_qty,
          8
        );
      end if;
      remaining_value := balance_row.carrying_value_shop - moved_value;
      unit_cost_value := case when line_row.tracking_mode = 'serialized'
        then device_row.unit_cost_shop
        else balance_row.average_unit_cost_shop end;
      if moved_value > balance_row.carrying_value_shop then
        raise exception 'The serialized cost exceeds its source carrying value.'
          using errcode = '23514';
      end if;
    else
      moved_value := null;
      remaining_value := null;
      unit_cost_value := null;
    end if;

    update public.inventory_balances
    set on_hand_qty = remaining_qty,
        reserved_transfer_qty = reserved_transfer_qty - line_row.approved_qty,
        carrying_value_shop = case when valuation_status = 'known_cost'
          then remaining_value else null end,
        average_unit_cost_shop = case when valuation_status = 'known_cost'
          then case when remaining_qty = 0 then 0::numeric
            else round(remaining_value / remaining_qty, 10) end
          else null end,
        updated_at = clock_timestamp(),
        updated_by = actor_record.actor_id
    where shop_id = p_shop_id and id = balance_row.id;

    update public.inventory_transfer_lines
    set dispatched_qty = approved_qty,
        unit_cost_shop = unit_cost_value,
        dispatched_value_shop = case
          when valuation_status = 'known_cost' then moved_value else null end,
        received_value_shop = case
          when valuation_status = 'known_cost' then 0::numeric else null end
    where shop_id = p_shop_id and id = line_row.id;

    if line_row.tracking_mode = 'serialized' then
      update public.serialized_inventory
      set transfer_state = 'in_transit',
          updated_at = clock_timestamp(),
          updated_by = actor_record.actor_id
      where shop_id = p_shop_id and id = line_row.serialized_inventory_id;
    end if;

    insert into public.inventory_movements (
      shop_id, branch_id, operation_id, receipt_line_id, transfer_line_id,
      variant_id, serialized_inventory_id, movement_type, valuation_status,
      valuation_currency_code, on_hand_delta, available_delta,
      unit_cost_shop, extended_cost_shop, reason, actor_id, line_number
    ) values (
      p_shop_id, transfer_row.source_branch_id, operation_record.operation_id,
      null, line_row.id, line_row.variant_id, line_row.serialized_inventory_id,
      'transfer_out', line_row.valuation_status,
      currency_record.currency_code, -line_row.approved_qty, 0,
      unit_cost_value, moved_value, transfer_row.reason,
      actor_record.actor_id, line_row.line_number
    );

    perform private.record_inventory_transfer_event(
      p_shop_id, p_transfer_id, line_row.id, operation_record.operation_id,
      line_row.line_number, 'line_dispatched', 'approved', 'dispatched',
      -line_row.approved_qty, 0, -line_row.approved_qty, moved_value,
      actor_record.actor_id, jsonb_build_object(
        'source_branch_id', transfer_row.source_branch_id,
        'valuation_status', line_row.valuation_status,
        'outstanding_qty', line_row.approved_qty
      )
    );
  end loop;

  update public.inventory_transfers
  set status = 'dispatched', version = version + 1,
      dispatched_by = actor_record.actor_id, dispatched_at = clock_timestamp()
  where shop_id = p_shop_id and id = p_transfer_id;

  perform private.record_inventory_transfer_event(
    p_shop_id, p_transfer_id, null, operation_record.operation_id, 0,
    'dispatched', 'approved', 'dispatched', 0, 0, 0, null,
    actor_record.actor_id, jsonb_build_object('full_dispatch', true)
  );

  return p_transfer_id;
end;
$function$;

create or replace function public.receive_inventory_transfer(
  p_shop_id uuid,
  p_transfer_id uuid,
  p_expected_version bigint,
  p_received_lines jsonb,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  transfer_row public.inventory_transfers%rowtype;
  actor_record record;
  currency_record record;
  operation_record record;
  input_line record;
  line_row public.inventory_transfer_lines%rowtype;
  device_row public.serialized_inventory%rowtype;
  balance_row public.inventory_balances%rowtype;
  received_line_id uuid;
  received_ids uuid[] := '{}'::uuid[];
  receive_qty integer;
  next_received_qty integer;
  target_received_value numeric(38, 8);
  value_delta numeric(38, 8);
  next_on_hand integer;
  next_carrying numeric(38, 8);
  next_average numeric(38, 10);
  new_status text;
  request_payload_value jsonb;
begin
  select transfer.* into transfer_row
  from public.inventory_transfers as transfer
  where transfer.shop_id = p_shop_id and transfer.id = p_transfer_id;
  if not found then
    raise exception 'The transfer does not exist in this shop.'
      using errcode = '22023';
  end if;

  select * into actor_record
  from private.assert_inventory_transfer_access(
    p_shop_id, transfer_row.source_branch_id,
    transfer_row.destination_branch_id, 'receive'
  );
  select * into currency_record
  from private.lock_inventory_transfer_currency(p_shop_id);

  request_payload_value := jsonb_build_object(
    'transfer_id', p_transfer_id,
    'expected_version', p_expected_version,
    'received_lines', p_received_lines
  );
  select * into operation_record
  from private.claim_inventory_transfer_operation(
    p_shop_id, transfer_row.destination_branch_id, actor_record.actor_id,
    p_idempotency_key, 'transfer_receipt', request_payload_value,
    p_transfer_id, currency_record.currency_code,
    currency_record.currency_version
  );
  if operation_record.replayed then
    return operation_record.result_transfer_id;
  end if;

  select transfer.* into transfer_row
  from public.inventory_transfers as transfer
  where transfer.shop_id = p_shop_id and transfer.id = p_transfer_id
  for update;

  if transfer_row.status not in ('dispatched', 'partially_received')
    or p_expected_version is null
    or transfer_row.version <> p_expected_version
  then
    raise exception 'Only the current dispatched transfer can be received.'
      using errcode = '40001';
  end if;
  if transfer_row.shop_currency_code is distinct from currency_record.currency_code
    or transfer_row.currency_version <> currency_record.currency_version
  then
    raise exception 'The shop valuation currency changed after this transfer was requested.'
      using errcode = '23514';
  end if;

  if p_received_lines is null
    or jsonb_typeof(p_received_lines) is distinct from 'array'
    or jsonb_array_length(p_received_lines) = 0
    or jsonb_array_length(p_received_lines) > 500
  then
    raise exception 'A nonempty array of received transfer lines is required.'
      using errcode = '22023';
  end if;

  -- Validate the entire payload before mutating any line. Then process lines
  -- in canonical variant/valuation/device order to avoid opposite-order balance
  -- locks across concurrent receipts.
  for input_line in
    select item.value
    from jsonb_array_elements(p_received_lines) as item(value)
  loop
    if jsonb_typeof(input_line.value) is distinct from 'object'
      or (select count(*) from jsonb_object_keys(input_line.value)) <> 2
      or not (input_line.value ?& array['line_id', 'quantity'])
      or jsonb_typeof(input_line.value -> 'line_id') is distinct from 'string'
      or (input_line.value ->> 'line_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or jsonb_typeof(input_line.value -> 'quantity') is distinct from 'number'
      or (input_line.value ->> 'quantity') !~ '^[1-9][0-9]*$'
    then
      raise exception 'Received lines require a valid line_id and positive integer quantity.'
        using errcode = '22023';
    end if;

    received_line_id := (input_line.value ->> 'line_id')::uuid;
    receive_qty := (input_line.value ->> 'quantity')::integer;
    if received_line_id = any(received_ids) then
      raise exception 'A transfer line may appear only once per receipt.'
        using errcode = '22023';
    end if;
    received_ids := array_append(received_ids, received_line_id);
  end loop;

  if exists (
    select 1 from unnest(received_ids) as requested(line_id)
    where not exists (
      select 1 from public.inventory_transfer_lines as line
      where line.shop_id = p_shop_id
        and line.transfer_id = p_transfer_id
        and line.id = requested.line_id
    )
  ) then
    raise exception 'A received line does not belong to this transfer.'
      using errcode = '23514';
  end if;

  received_ids := '{}'::uuid[];
  for input_line in
    select item.value
    from jsonb_array_elements(p_received_lines) as item(value)
    join public.inventory_transfer_lines as sort_line
      on sort_line.shop_id = p_shop_id
     and sort_line.transfer_id = p_transfer_id
     and sort_line.id = (item.value ->> 'line_id')::uuid
    order by sort_line.variant_id, sort_line.valuation_status,
             sort_line.serialized_inventory_id nulls first
  loop
    received_line_id := (input_line.value ->> 'line_id')::uuid;
    receive_qty := (input_line.value ->> 'quantity')::integer;
    received_ids := array_append(received_ids, received_line_id);

    select line.* into line_row
    from public.inventory_transfer_lines as line
    where line.shop_id = p_shop_id
      and line.transfer_id = p_transfer_id
      and line.id = received_line_id
    for update;
    if not found
      or line_row.dispatched_qty <= line_row.received_qty
      or receive_qty > line_row.dispatched_qty - line_row.received_qty
      or (line_row.tracking_mode = 'serialized' and receive_qty <> 1)
    then
      raise exception 'The line is not outstanding or the received quantity exceeds the dispatched quantity.'
        using errcode = '23514';
    end if;

    next_received_qty := line_row.received_qty + receive_qty;
    if line_row.valuation_status = 'known_cost' then
      if next_received_qty = line_row.dispatched_qty then
        target_received_value := line_row.dispatched_value_shop;
      else
        target_received_value := round(
          line_row.dispatched_value_shop * next_received_qty
            / line_row.dispatched_qty,
          8
        );
      end if;
      value_delta := target_received_value - line_row.received_value_shop;
    else
      target_received_value := null;
      value_delta := null;
    end if;

    if line_row.tracking_mode = 'serialized' then
      select device.* into device_row
      from public.serialized_inventory as device
      where device.shop_id = p_shop_id
        and device.variant_id = line_row.variant_id
        and device.id = line_row.serialized_inventory_id
        and device.branch_id = transfer_row.source_branch_id
        and device.availability_status = 'reserved'
        and device.transfer_state = 'in_transit'
      for update;
      if not found then
        raise exception 'The serialized device is not in this transfer’s in-transit state.'
          using errcode = '23514';
      end if;
    end if;

    insert into public.inventory_balances (
      shop_id, branch_id, variant_id, valuation_status,
      valuation_currency_code, on_hand_qty, available_qty,
      carrying_value_shop, average_unit_cost_shop, updated_by
    ) values (
      p_shop_id, transfer_row.destination_branch_id, line_row.variant_id,
      line_row.valuation_status, currency_record.currency_code, 0, 0,
      case when line_row.valuation_status = 'known_cost' then 0 else null end,
      case when line_row.valuation_status = 'known_cost' then 0 else null end,
      actor_record.actor_id
    )
    on conflict (shop_id, branch_id, variant_id, valuation_status) do nothing;

    select balance.* into balance_row
    from public.inventory_balances as balance
    where balance.shop_id = p_shop_id
      and balance.branch_id = transfer_row.destination_branch_id
      and balance.variant_id = line_row.variant_id
      and balance.valuation_status = line_row.valuation_status
    for update;

    next_on_hand := balance_row.on_hand_qty + receive_qty;
    if line_row.valuation_status = 'known_cost' then
      next_carrying := balance_row.carrying_value_shop + value_delta;
      next_average := round(next_carrying / next_on_hand, 10);
    else
      next_carrying := null;
      next_average := null;
    end if;

    update public.inventory_balances
    set on_hand_qty = next_on_hand,
        available_qty = available_qty + receive_qty,
        carrying_value_shop = next_carrying,
        average_unit_cost_shop = next_average,
        updated_at = clock_timestamp(),
        updated_by = actor_record.actor_id
    where shop_id = p_shop_id and id = balance_row.id;

    update public.inventory_transfer_lines
    set received_qty = next_received_qty,
        received_value_shop = case
          when valuation_status = 'known_cost' then target_received_value else null end,
        claim_active = case
          when tracking_mode = 'serialized' and next_received_qty = dispatched_qty
            then false else claim_active end
    where shop_id = p_shop_id and id = line_row.id;

    if line_row.tracking_mode = 'serialized' then
      update public.serialized_inventory
      set branch_id = transfer_row.destination_branch_id,
          availability_status = 'available',
          transfer_state = null,
          updated_at = clock_timestamp(),
          updated_by = actor_record.actor_id
      where shop_id = p_shop_id and id = line_row.serialized_inventory_id;
    end if;

    insert into public.inventory_movements (
      shop_id, branch_id, operation_id, receipt_line_id, transfer_line_id,
      variant_id, serialized_inventory_id, movement_type, valuation_status,
      valuation_currency_code, on_hand_delta, available_delta,
      unit_cost_shop, extended_cost_shop, reason, actor_id, line_number
    ) values (
      p_shop_id, transfer_row.destination_branch_id, operation_record.operation_id,
      null, line_row.id, line_row.variant_id, line_row.serialized_inventory_id,
      'transfer_in', line_row.valuation_status,
      currency_record.currency_code, receive_qty, receive_qty,
      line_row.unit_cost_shop, value_delta, transfer_row.reason,
      actor_record.actor_id, line_row.line_number
    );

    perform private.record_inventory_transfer_event(
      p_shop_id, p_transfer_id, line_row.id, operation_record.operation_id,
      line_row.line_number, 'line_received', transfer_row.status, null,
      receive_qty, receive_qty, 0, value_delta, actor_record.actor_id,
      jsonb_build_object(
        'received_qty', next_received_qty,
        'dispatched_qty', line_row.dispatched_qty,
        'outstanding_qty', line_row.dispatched_qty - next_received_qty
      )
    );
  end loop;

  if exists (
    select 1 from public.inventory_transfer_lines as line
    where line.shop_id = p_shop_id and line.transfer_id = p_transfer_id
      and line.received_qty < line.dispatched_qty
  ) then
    new_status := 'partially_received';
  else
    new_status := 'received';
  end if;

  update public.inventory_transfers
  set status = new_status,
      version = version + 1,
      received_at = case when new_status = 'received'
        then clock_timestamp() else null end
  where shop_id = p_shop_id and id = p_transfer_id;

  perform private.record_inventory_transfer_event(
    p_shop_id, p_transfer_id, null, operation_record.operation_id, 0,
    case when new_status = 'received' then 'received' else 'partially_received' end,
    transfer_row.status, new_status, 0, 0, 0, null, actor_record.actor_id,
    jsonb_build_object('received_line_count', cardinality(received_ids))
  );

  return p_transfer_id;
end;
$function$;

create or replace function public.cancel_inventory_transfer(
  p_shop_id uuid,
  p_transfer_id uuid,
  p_expected_version bigint,
  p_reason text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  transfer_row public.inventory_transfers%rowtype;
  actor_record record;
  currency_record record;
  operation_record record;
  line_row public.inventory_transfer_lines%rowtype;
  device_row public.serialized_inventory%rowtype;
  balance_row public.inventory_balances%rowtype;
  cancel_reason text := nullif(btrim(p_reason), '');
  request_payload_value jsonb;
begin
  select transfer.* into transfer_row
  from public.inventory_transfers as transfer
  where transfer.shop_id = p_shop_id and transfer.id = p_transfer_id;
  if not found then
    raise exception 'The transfer does not exist in this shop.'
      using errcode = '22023';
  end if;

  select * into actor_record
  from private.assert_inventory_transfer_access(
    p_shop_id, transfer_row.source_branch_id,
    transfer_row.destination_branch_id, 'cancel'
  );
  select * into currency_record
  from private.lock_inventory_transfer_currency(p_shop_id);

  if cancel_reason is null or char_length(cancel_reason) > 500 then
    raise exception 'A cancellation reason between 1 and 500 characters is required.'
      using errcode = '22023';
  end if;

  request_payload_value := jsonb_build_object(
    'transfer_id', p_transfer_id,
    'expected_version', p_expected_version,
    'reason', cancel_reason
  );
  select * into operation_record
  from private.claim_inventory_transfer_operation(
    p_shop_id, transfer_row.source_branch_id, actor_record.actor_id,
    p_idempotency_key, 'transfer_cancellation', request_payload_value,
    p_transfer_id, currency_record.currency_code,
    currency_record.currency_version
  );
  if operation_record.replayed then
    return operation_record.result_transfer_id;
  end if;

  select transfer.* into transfer_row
  from public.inventory_transfers as transfer
  where transfer.shop_id = p_shop_id and transfer.id = p_transfer_id
  for update;

  if transfer_row.status not in ('requested', 'approved')
    or p_expected_version is null
    or transfer_row.version <> p_expected_version
  then
    raise exception 'A transfer can only be cancelled before dispatch at its current version.'
      using errcode = '40001';
  end if;

  if transfer_row.status = 'approved' then
    for line_row in
      select line.*
      from public.inventory_transfer_lines as line
      where line.shop_id = p_shop_id and line.transfer_id = p_transfer_id
      order by line.variant_id, line.valuation_status, line.serialized_inventory_id nulls first
      for update
    loop
      if line_row.tracking_mode = 'serialized' then
        select device.* into device_row
        from public.serialized_inventory as device
        where device.shop_id = p_shop_id
          and device.variant_id = line_row.variant_id
          and device.id = line_row.serialized_inventory_id
          and device.branch_id = transfer_row.source_branch_id
          and device.availability_status = 'reserved'
          and device.transfer_state is null
        for update;
        if not found then
          raise exception 'A reserved serialized device cannot be released safely.'
            using errcode = '23514';
        end if;
      end if;

      select balance.* into balance_row
      from public.inventory_balances as balance
      where balance.shop_id = p_shop_id
        and balance.branch_id = transfer_row.source_branch_id
        and balance.variant_id = line_row.variant_id
        and balance.valuation_status = line_row.valuation_status
      for update;
      if not found or balance_row.reserved_transfer_qty < line_row.approved_qty then
        raise exception 'The reserved quantity cannot be released safely.'
          using errcode = '23514';
      end if;

      update public.inventory_balances
      set available_qty = available_qty + line_row.approved_qty,
          reserved_transfer_qty = reserved_transfer_qty - line_row.approved_qty,
          updated_at = clock_timestamp(),
          updated_by = actor_record.actor_id
      where shop_id = p_shop_id and id = balance_row.id;

      if line_row.tracking_mode = 'serialized' then
        update public.inventory_transfer_lines
        set claim_active = false
        where shop_id = p_shop_id and id = line_row.id;

        update public.serialized_inventory
        set availability_status = 'available',
            updated_at = clock_timestamp(),
            updated_by = actor_record.actor_id
        where shop_id = p_shop_id and id = line_row.serialized_inventory_id;
      end if;

      perform private.record_inventory_transfer_event(
        p_shop_id, p_transfer_id, line_row.id, operation_record.operation_id,
        line_row.line_number, 'line_reservation_released', 'approved', 'cancelled',
        0, line_row.approved_qty, -line_row.approved_qty, null,
        actor_record.actor_id, jsonb_build_object(
          'reason', cancel_reason,
          'on_hand_delta', 0,
          'available_delta', line_row.approved_qty,
          'reserved_transfer_delta', -line_row.approved_qty
        )
      );
    end loop;
  else
    update public.inventory_transfer_lines
    set claim_active = false
    where shop_id = p_shop_id and transfer_id = p_transfer_id
      and serialized_inventory_id is not null;
  end if;

  update public.inventory_transfers
  set status = 'cancelled', version = version + 1,
      cancelled_by = actor_record.actor_id,
      cancelled_at = clock_timestamp()
  where shop_id = p_shop_id and id = p_transfer_id;

  perform private.record_inventory_transfer_event(
    p_shop_id, p_transfer_id, null, operation_record.operation_id, 0,
    'cancelled', transfer_row.status, 'cancelled', 0, 0, 0, null,
    actor_record.actor_id, jsonb_build_object('reason', cancel_reason)
  );

  return p_transfer_id;
end;
$function$;

create or replace function private.guard_inventory_transfer_update()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.id is distinct from old.id
    or new.shop_id is distinct from old.shop_id
    or new.source_branch_id is distinct from old.source_branch_id
    or new.destination_branch_id is distinct from old.destination_branch_id
    or new.reason is distinct from old.reason
    or new.shop_currency_code is distinct from old.shop_currency_code
    or new.currency_version is distinct from old.currency_version
    or new.requested_by is distinct from old.requested_by
    or new.requested_at is distinct from old.requested_at
    or new.version <> old.version + 1
  then
    raise exception 'Transfer identity and request evidence are immutable.'
      using errcode = '42501';
  end if;

  if not (
    (old.status = 'requested' and new.status in ('approved', 'cancelled'))
    or (old.status = 'approved' and new.status in ('dispatched', 'cancelled'))
    or (old.status = 'dispatched' and new.status in ('partially_received', 'received'))
    or (old.status = 'partially_received' and new.status in ('partially_received', 'received'))
  ) then
    raise exception 'The requested transfer state transition is invalid.'
      using errcode = '23514';
  end if;
  return new;
end;
$function$;

create trigger inventory_transfers_state_guard
  before update on public.inventory_transfers
  for each row execute function private.guard_inventory_transfer_update();

create or replace function private.guard_inventory_transfer_line_update()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.id is distinct from old.id
    or new.shop_id is distinct from old.shop_id
    or new.transfer_id is distinct from old.transfer_id
    or new.line_number is distinct from old.line_number
    or new.variant_id is distinct from old.variant_id
    or new.tracking_mode is distinct from old.tracking_mode
    or new.valuation_status is distinct from old.valuation_status
    or new.serialized_inventory_id is distinct from old.serialized_inventory_id
    or new.requested_qty is distinct from old.requested_qty
    or new.approved_qty < old.approved_qty
    or new.dispatched_qty < old.dispatched_qty
    or new.received_qty < old.received_qty
    or (old.claim_active = false and new.claim_active = true)
    or (old.unit_cost_shop is not null
      and new.unit_cost_shop is distinct from old.unit_cost_shop)
    or (old.dispatched_value_shop is not null
      and new.dispatched_value_shop is distinct from old.dispatched_value_shop)
    or (old.received_value_shop is not null
      and new.received_value_shop < old.received_value_shop)
  then
    raise exception 'Transfer line identity and accounting progress are monotonic.'
      using errcode = '42501';
  end if;
  return new;
end;
$function$;

create trigger inventory_transfer_lines_state_guard
  before update on public.inventory_transfer_lines
  for each row execute function private.guard_inventory_transfer_line_update();

create or replace function private.reject_inventory_transfer_projection_delete()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception 'Transfer records are durable and cannot be deleted or truncated.'
    using errcode = '42501';
end;
$function$;

revoke all on function private.reject_inventory_transfer_projection_delete()
  from public, anon, authenticated, service_role;

create trigger inventory_transfers_no_delete
  before delete on public.inventory_transfers
  for each row execute function private.reject_inventory_transfer_projection_delete();
create trigger inventory_transfers_no_truncate
  before truncate on public.inventory_transfers
  for each statement execute function private.reject_inventory_transfer_projection_delete();
create trigger inventory_transfer_lines_no_delete
  before delete on public.inventory_transfer_lines
  for each row execute function private.reject_inventory_transfer_projection_delete();
create trigger inventory_transfer_lines_no_truncate
  before truncate on public.inventory_transfer_lines
  for each statement execute function private.reject_inventory_transfer_projection_delete();

create or replace function private.guard_branch_transfer_deactivation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if old.is_active and not new.is_active and exists (
    select 1
    from public.inventory_transfers as transfer
    where transfer.shop_id = old.shop_id
      and old.id in (transfer.source_branch_id, transfer.destination_branch_id)
      and transfer.status in (
        'requested', 'approved', 'dispatched', 'partially_received'
      )
  ) then
    raise exception 'A branch with an open inventory transfer cannot be deactivated.'
      using errcode = '23514';
  end if;
  return new;
end;
$function$;

revoke all on function private.guard_branch_transfer_deactivation()
  from public, anon, authenticated, service_role;

create trigger branches_guard_open_inventory_transfers
  before update of is_active on public.branches
  for each row
  when (old.is_active is distinct from new.is_active)
  execute function private.guard_branch_transfer_deactivation();

create or replace function private.guard_product_tracking_mode_with_transfers()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.tracking_mode is distinct from old.tracking_mode and exists (
    select 1
    from public.product_variants as variant
    join public.inventory_transfer_lines as line
      on line.shop_id = variant.shop_id and line.variant_id = variant.id
    join public.inventory_transfers as transfer
      on transfer.shop_id = line.shop_id and transfer.id = line.transfer_id
    where variant.shop_id = old.shop_id and variant.product_id = old.id
      and transfer.status in (
        'requested', 'approved', 'dispatched', 'partially_received'
      )
  ) then
    raise exception 'Tracking mode cannot change while a transfer is open.'
      using errcode = '23514';
  end if;
  return new;
end;
$function$;

revoke all on function private.guard_product_tracking_mode_with_transfers()
  from public, anon, authenticated, service_role;

create trigger products_guard_transfer_tracking_history
  before update of tracking_mode on public.products
  for each row
  when (old.tracking_mode is distinct from new.tracking_mode)
  execute function private.guard_product_tracking_mode_with_transfers();

create or replace function private.validate_inventory_transfer_movement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  line_row public.inventory_transfer_lines%rowtype;
  transfer_row public.inventory_transfers%rowtype;
  operation_row public.inventory_operations%rowtype;
begin
  if new.transfer_line_id is null then
    return new;
  end if;

  select line.* into line_row
  from public.inventory_transfer_lines as line
  where line.shop_id = new.shop_id and line.id = new.transfer_line_id;
  if not found then
    raise exception 'The transfer movement line does not exist.'
      using errcode = '23503';
  end if;

  select transfer.* into transfer_row
  from public.inventory_transfers as transfer
  where transfer.shop_id = line_row.shop_id and transfer.id = line_row.transfer_id;
  select operation.* into operation_row
  from public.inventory_operations as operation
  where operation.shop_id = new.shop_id
    and operation.branch_id = new.branch_id
    and operation.id = new.operation_id;

  if line_row.variant_id is distinct from new.variant_id
    or line_row.serialized_inventory_id is distinct from new.serialized_inventory_id
    or line_row.valuation_status is distinct from new.valuation_status
    or transfer_row.shop_currency_code is distinct from new.valuation_currency_code
  then
    raise exception 'Transfer movement does not match its transfer line valuation and identity.'
      using errcode = '23514';
  end if;

  if new.movement_type = 'transfer_out' then
    if new.branch_id is distinct from transfer_row.source_branch_id
      or new.on_hand_delta <> -line_row.dispatched_qty
      or new.available_delta <> 0
      or operation_row.operation_type <> 'transfer_dispatch'
    then
      raise exception 'Transfer-out movement does not match source dispatch evidence.'
        using errcode = '23514';
    end if;
  elsif new.movement_type = 'transfer_in' then
    if new.branch_id is distinct from transfer_row.destination_branch_id
      or new.on_hand_delta <= 0
      or new.available_delta <> new.on_hand_delta
      or new.on_hand_delta > line_row.received_qty
      or operation_row.operation_type <> 'transfer_receipt'
    then
      raise exception 'Transfer-in movement does not match destination receipt evidence.'
        using errcode = '23514';
    end if;
  else
    raise exception 'Only transfer-out and transfer-in movements may reference transfer lines.'
      using errcode = '23514';
  end if;
  return new;
end;
$function$;

revoke all on function private.validate_inventory_transfer_movement()
  from public, anon, authenticated, service_role;

create trigger inventory_movements_validate_transfer
  before insert on public.inventory_movements
  for each row when (new.transfer_line_id is not null)
  execute function private.validate_inventory_transfer_movement();

create or replace function private.variant_has_owned_stock(
  p_shop_id uuid,
  p_variant_id uuid
)
returns boolean
language sql
stable
security definer
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
  )
  or exists (
    select 1
    from public.inventory_transfer_lines as line
    join public.inventory_transfers as transfer
      on transfer.shop_id = line.shop_id and transfer.id = line.transfer_id
    where line.shop_id = p_shop_id and line.variant_id = p_variant_id
      and transfer.status in (
        'requested', 'approved', 'dispatched', 'partially_received'
      )
  );
$function$;

revoke all on function private.variant_has_owned_stock(uuid, uuid)
  from public, anon, authenticated, service_role;

revoke all on function private.guard_inventory_transfer_update()
  from public, anon, authenticated, service_role;
revoke all on function private.guard_inventory_transfer_line_update()
  from public, anon, authenticated, service_role;

alter table public.inventory_transfers enable row level security;
alter table public.inventory_transfer_lines enable row level security;
alter table public.inventory_transfer_events enable row level security;

revoke all on public.inventory_transfers,
  public.inventory_transfer_lines,
  public.inventory_transfer_events,
  public.inventory_transfer_in_transit
  from public, anon, authenticated, service_role;

grant select on public.inventory_transfers,
  public.inventory_transfer_lines,
  public.inventory_transfer_events,
  public.inventory_transfer_in_transit
  to authenticated, service_role;

create policy inventory_transfers_read_authorized_endpoint
  on public.inventory_transfers for select to authenticated
  using (
    private.is_active_shop_member(shop_id)
    and (
      private.has_shop_role(shop_id, array['owner']::public.shop_role[])
      or
      private.can_access_branch(shop_id, source_branch_id)
      or private.can_access_branch(shop_id, destination_branch_id)
    )
  );

create policy inventory_transfer_lines_read_authorized_endpoint
  on public.inventory_transfer_lines for select to authenticated
  using (
    exists (
      select 1 from public.inventory_transfers as transfer
      where transfer.shop_id = inventory_transfer_lines.shop_id
        and transfer.id = inventory_transfer_lines.transfer_id
    )
  );

create policy inventory_transfer_events_read_authorized_endpoint
  on public.inventory_transfer_events for select to authenticated
  using (
    exists (
      select 1 from public.inventory_transfers as transfer
      where transfer.shop_id = inventory_transfer_events.shop_id
        and transfer.id = inventory_transfer_events.transfer_id
    )
  );

revoke all on function public.request_inventory_transfer(
  uuid, uuid, uuid, jsonb, text, text
) from public, anon, service_role;
revoke all on function public.approve_inventory_transfer(uuid, uuid, bigint, text)
  from public, anon, service_role;
revoke all on function public.dispatch_inventory_transfer(uuid, uuid, bigint, text)
  from public, anon, service_role;
revoke all on function public.receive_inventory_transfer(uuid, uuid, bigint, jsonb, text)
  from public, anon, service_role;
revoke all on function public.cancel_inventory_transfer(uuid, uuid, bigint, text, text)
  from public, anon, service_role;

grant execute on function public.request_inventory_transfer(
  uuid, uuid, uuid, jsonb, text, text
) to authenticated;
grant execute on function public.approve_inventory_transfer(uuid, uuid, bigint, text)
  to authenticated;
grant execute on function public.dispatch_inventory_transfer(uuid, uuid, bigint, text)
  to authenticated;
grant execute on function public.receive_inventory_transfer(uuid, uuid, bigint, jsonb, text)
  to authenticated;
grant execute on function public.cancel_inventory_transfer(uuid, uuid, bigint, text, text)
  to authenticated;

comment on table public.inventory_transfers is
  'Same-shop branch transfers; internal stock movements do not create sales, payables, or FX evidence.';
comment on table public.inventory_transfer_lines is
  'Transfer quantity/device projection and exact shop-currency carrying-value reconciliation.';
comment on table public.inventory_transfer_events is
  'Append-only evidence for requested, approved, dispatched, received, and cancelled transfer stages.';
comment on column public.inventory_transfer_lines.dispatched_value_shop is
  'Exact carrying value moved into transit at full dispatch; final receipt receives the rounding residual.';
comment on column public.serialized_inventory.transfer_state is
  'in_transit marks a dispatched device unavailable at its last confirmed branch until destination receipt.';
