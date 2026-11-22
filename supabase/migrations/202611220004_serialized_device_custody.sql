-- Phase 3D-A: secure custody for shop-owned serialized devices.
-- Custody never creates a device, sale, receipt, COGS entry, or write-off.

create table public.inventory_custody_cases (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  branch_id uuid not null,
  case_reference text not null,
  purpose text not null,
  reason text not null,
  status text not null default 'requested',
  version bigint not null default 1,
  requested_by uuid not null references auth.users (id) on delete restrict,
  requested_at timestamptz not null default clock_timestamp(),
  approved_by uuid references auth.users (id) on delete restrict,
  approved_at timestamptz,
  handed_over_by uuid references auth.users (id) on delete restrict,
  handed_over_at timestamptz,
  cancelled_by uuid references auth.users (id) on delete restrict,
  cancelled_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (shop_id, id),
  unique (shop_id, branch_id, id),
  unique (shop_id, case_reference),
  foreign key (shop_id, branch_id)
    references public.branches (shop_id, id) on delete restrict,
  constraint inventory_custody_case_reference_length check (
    char_length(btrim(case_reference)) between 8 and 40
  ),
  constraint inventory_custody_case_purpose_length check (
    char_length(btrim(purpose)) between 1 and 300
  ),
  constraint inventory_custody_case_reason_length check (
    char_length(btrim(reason)) between 1 and 1000
  ),
  constraint inventory_custody_case_version check (version > 0),
  constraint inventory_custody_case_status check (
    status in (
      'requested', 'approved', 'handed_over', 'partially_returned',
      'returned', 'cancelled'
    )
  ),
  constraint inventory_custody_case_stage_evidence check (
    (status = 'requested' and approved_by is null and approved_at is null
      and handed_over_by is null and handed_over_at is null
      and cancelled_by is null and cancelled_at is null and completed_at is null)
    or (status = 'approved' and approved_by is not null and approved_at is not null
      and handed_over_by is null and handed_over_at is null
      and cancelled_by is null and cancelled_at is null and completed_at is null)
    or (status = 'handed_over' and approved_by is not null and approved_at is not null
      and handed_over_by is not null and handed_over_at is not null
      and cancelled_by is null and cancelled_at is null and completed_at is null)
    or (status = 'partially_returned'
      and approved_by is not null and approved_at is not null
      and handed_over_by is not null and handed_over_at is not null
      and cancelled_by is null and cancelled_at is null and completed_at is null)
    or (status = 'returned' and approved_by is not null and approved_at is not null
      and handed_over_by is not null and handed_over_at is not null
      and cancelled_by is null and cancelled_at is null and completed_at is not null)
    or (status = 'cancelled' and cancelled_by is not null and cancelled_at is not null
      and completed_at is not null)
  )
);

create index inventory_custody_cases_branch_status_idx
  on public.inventory_custody_cases (shop_id, branch_id, status, requested_at desc);

create table public.inventory_custody_items (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  branch_id uuid not null,
  case_id uuid not null,
  line_number integer not null,
  serialized_inventory_id uuid not null,
  custodian_type text not null,
  custodian_user_id uuid references auth.users (id) on delete restrict,
  custodian_name_snapshot text,
  custodian_contact_snapshot text,
  expected_return_at timestamptz,
  state text not null default 'requested',
  claim_active boolean not null default true,
  handover_condition text,
  return_condition text,
  approved_by uuid references auth.users (id) on delete restrict,
  approved_at timestamptz,
  handed_over_by uuid references auth.users (id) on delete restrict,
  handed_over_at timestamptz,
  returned_by uuid references auth.users (id) on delete restrict,
  returned_at timestamptz,
  cancelled_by uuid references auth.users (id) on delete restrict,
  cancelled_at timestamptz,
  version bigint not null default 1,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (shop_id, id),
  unique (shop_id, branch_id, case_id, id),
  unique (shop_id, case_id, id),
  unique (shop_id, case_id, line_number),
  foreign key (shop_id, branch_id, case_id)
    references public.inventory_custody_cases (shop_id, branch_id, id)
    on delete restrict,
  -- The custody row keeps its source branch as historical context, while the
  -- device may later move branches. Reference stable shop/device identity only.
  foreign key (shop_id, serialized_inventory_id)
    references public.serialized_inventory (shop_id, id)
    on delete restrict,
  constraint inventory_custody_item_line_number check (line_number > 0),
  constraint inventory_custody_item_version check (version > 0),
  constraint inventory_custody_item_state check (
    state in ('requested', 'approved', 'handed_over', 'returned', 'cancelled')
  ),
  constraint inventory_custody_item_custodian check (
    (custodian_type = 'employee' and custodian_user_id is not null
      and custodian_name_snapshot is null and custodian_contact_snapshot is null)
    or (custodian_type = 'external' and custodian_user_id is null
      and custodian_name_snapshot is not null
      and char_length(btrim(custodian_name_snapshot)) between 1 and 200
      and (custodian_contact_snapshot is null
        or char_length(custodian_contact_snapshot) <= 300))
  ),
  constraint inventory_custody_item_stage_evidence check (
    (state = 'requested' and claim_active and approved_by is null and approved_at is null
      and handed_over_by is null and handed_over_at is null
      and returned_by is null and returned_at is null
      and cancelled_by is null and cancelled_at is null)
    or (state = 'approved' and claim_active and approved_by is not null and approved_at is not null
      and handed_over_by is null and handed_over_at is null
      and returned_by is null and returned_at is null
      and cancelled_by is null and cancelled_at is null)
    or (state = 'handed_over' and claim_active and approved_by is not null and approved_at is not null
      and handed_over_by is not null and handed_over_at is not null
      and returned_by is null and returned_at is null
      and cancelled_by is null and cancelled_at is null)
    or (state = 'returned' and not claim_active and approved_by is not null and approved_at is not null
      and handed_over_by is not null and handed_over_at is not null
      and returned_by is not null and returned_at is not null
      and cancelled_by is null and cancelled_at is null)
    or (state = 'cancelled' and not claim_active and handed_over_by is null
      and handed_over_at is null and returned_by is null and returned_at is null
      and cancelled_by is not null and cancelled_at is not null)
  ),
  constraint inventory_custody_item_condition_lengths check (
    (handover_condition is null or char_length(handover_condition) <= 2000)
    and (return_condition is null or char_length(return_condition) <= 2000)
  )
);

create unique index inventory_custody_items_active_device_uidx
  on public.inventory_custody_items (shop_id, serialized_inventory_id)
  where claim_active;
create index inventory_custody_items_case_state_idx
  on public.inventory_custody_items (shop_id, case_id, state, line_number);
create index inventory_custody_items_overdue_idx
  on public.inventory_custody_items (shop_id, branch_id, expected_return_at)
  where claim_active and state = 'handed_over';

create table public.inventory_custody_incidents (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  branch_id uuid not null,
  case_id uuid not null,
  item_id uuid not null,
  incident_type text not null,
  status text not null default 'open',
  report text not null,
  evidence jsonb not null,
  reported_by uuid not null references auth.users (id) on delete restrict,
  reported_at timestamptz not null default clock_timestamp(),
  resolved_by uuid references auth.users (id) on delete restrict,
  resolved_at timestamptz,
  resolution text,
  resolution_evidence jsonb,
  version bigint not null default 1,
  unique (shop_id, id),
  unique (shop_id, branch_id, id),
  unique (shop_id, branch_id, case_id, item_id, id),
  foreign key (shop_id, branch_id, case_id, item_id)
    references public.inventory_custody_items (shop_id, branch_id, case_id, id)
    on delete restrict,
  constraint inventory_custody_incident_type check (
    incident_type in ('missing', 'damage', 'dispute')
  ),
  constraint inventory_custody_incident_status check (
    status in ('open', 'resolved')
  ),
  constraint inventory_custody_incident_report check (
    char_length(btrim(report)) between 1 and 2000
    and jsonb_typeof(evidence) = 'object'
    and evidence <> '{}'::jsonb
  ),
  constraint inventory_custody_incident_resolution check (
    (status = 'open' and resolved_by is null and resolved_at is null
      and resolution is null and resolution_evidence is null)
    or (status = 'resolved' and resolved_by is not null and resolved_at is not null
      and char_length(btrim(resolution)) between 1 and 500
      and jsonb_typeof(resolution_evidence) = 'object'
      and resolution_evidence <> '{}'::jsonb)
  ),
  constraint inventory_custody_incident_version check (version > 0)
);

create index inventory_custody_incidents_open_item_idx
  on public.inventory_custody_incidents (shop_id, item_id, reported_at)
  where status = 'open';

create table public.inventory_custody_events (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  branch_id uuid not null,
  case_id uuid not null,
  item_id uuid,
  incident_id uuid,
  operation_id uuid not null,
  line_number integer not null,
  event_type text not null,
  prior_state text,
  new_state text,
  actor_id uuid not null references auth.users (id) on delete restrict,
  occurred_at timestamptz not null default clock_timestamp(),
  event_data jsonb not null default '{}'::jsonb,
  unique (shop_id, id),
  unique (shop_id, operation_id, line_number),
  foreign key (shop_id, branch_id, case_id)
    references public.inventory_custody_cases (shop_id, branch_id, id)
    on delete restrict,
  foreign key (shop_id, case_id, item_id)
    references public.inventory_custody_items (shop_id, case_id, id)
    on delete restrict,
  foreign key (shop_id, branch_id, case_id, item_id, incident_id)
    references public.inventory_custody_incidents
      (shop_id, branch_id, case_id, item_id, id)
    on delete restrict,
  foreign key (shop_id, branch_id, operation_id)
    references public.inventory_operations (shop_id, branch_id, id)
    on delete restrict,
  constraint inventory_custody_event_line_number check (line_number >= 0),
  constraint inventory_custody_event_type check (
    event_type in (
      'requested', 'item_requested', 'approved', 'item_approved',
      'cancelled', 'item_cancelled', 'handed_over', 'item_handed_over',
      'partially_returned', 'item_returned', 'returned',
      'missing_reported', 'damage_reported', 'dispute_reported',
      'incident_reviewed', 'incident_resolved'
    )
  ),
  constraint inventory_custody_event_payload_object check (
    jsonb_typeof(event_data) = 'object'
  ),
  constraint inventory_custody_event_incident_pair check (
    (incident_id is null and event_type not in (
      'missing_reported', 'damage_reported', 'dispute_reported',
      'incident_reviewed', 'incident_resolved'
    ))
    or (incident_id is not null and event_type in (
      'missing_reported', 'damage_reported', 'dispute_reported',
      'incident_reviewed', 'incident_resolved'
    ))
  )
);

create index inventory_custody_events_case_history_idx
  on public.inventory_custody_events (shop_id, case_id, occurred_at, line_number);
create index inventory_custody_events_item_history_idx
  on public.inventory_custody_events (shop_id, item_id, occurred_at, line_number)
  where item_id is not null;

alter table public.inventory_balances
  add column reserved_custody_qty integer not null default 0;

alter table public.inventory_balances
  drop constraint inventory_balances_transfer_qty,
  add constraint inventory_balances_transfer_qty check (
    reserved_transfer_qty >= 0
    and reserved_custody_qty >= 0
    and available_qty + reserved_transfer_qty + reserved_custody_qty <= on_hand_qty
    and (valuation_status <> 'pending_fx'
      or (reserved_transfer_qty = 0 and reserved_custody_qty = 0))
  );

alter table public.serialized_inventory
  add column custody_state text not null default 'none',
  add constraint serialized_inventory_custody_state_check check (
    custody_state in (
      'none', 'requested', 'approved', 'handed_over', 'returned_quarantine'
    )
    and (
      (custody_state in ('none', 'requested')
        and availability_status in ('available', 'reserved', 'pending_fx', 'sold', 'written_off'))
      or (custody_state in ('approved', 'handed_over', 'returned_quarantine')
        and availability_status = 'reserved'
        and transfer_state is null
        and valuation_status <> 'pending_fx')
    )
    and (custody_state <> 'requested'
      or (availability_status = 'available' and transfer_state is null
        and valuation_status <> 'pending_fx'))
    and (custody_state <> 'none' or transfer_state is null
      or (availability_status = 'reserved' and transfer_state = 'in_transit'))
  );

create index serialized_inventory_custody_state_idx
  on public.serialized_inventory (shop_id, branch_id, custody_state)
  where custody_state <> 'none';

alter table public.inventory_operations
  add column result_custody_case_id uuid,
  add column result_custody_incident_id uuid;

alter table public.inventory_operations
  drop constraint inventory_operations_type,
  drop constraint inventory_operations_result_target,
  add constraint inventory_operations_type check (
    operation_type in (
      'quantity_receipt', 'serialized_receipt', 'pending_fx_release',
      'transfer_request', 'transfer_approval', 'transfer_dispatch',
      'transfer_receipt', 'transfer_cancellation',
      'custody_request', 'custody_approval', 'custody_handover',
      'custody_return', 'custody_cancellation', 'custody_incident_report',
      'custody_incident_resolution'
    )
  ),
  add constraint inventory_operations_result_target check (
    num_nonnulls(result_receipt_id, result_transfer_id, result_custody_case_id) = 1
  ),
  add constraint inventory_operations_result_custody_fk
    foreign key (shop_id, branch_id, result_custody_case_id)
    references public.inventory_custody_cases (shop_id, branch_id, id)
    on delete restrict deferrable initially deferred,
  add constraint inventory_operations_result_custody_incident_fk
    foreign key (shop_id, branch_id, result_custody_incident_id)
    references public.inventory_custody_incidents (shop_id, branch_id, id)
    on delete restrict deferrable initially deferred,
  add constraint inventory_operations_custody_incident_result check (
    (operation_type in ('custody_incident_report', 'custody_incident_resolution'))
      = (result_custody_incident_id is not null)
  );

alter table public.inventory_movements
  add column custody_item_id uuid,
  add constraint inventory_movements_transfer_custody_exclusive check (
    transfer_line_id is null or custody_item_id is null
  ),
  add constraint inventory_movements_receipt_custody_exclusive check (
    receipt_line_id is null or custody_item_id is null
  ),
  add constraint inventory_movements_custody_kind_pair check (
    (custody_item_id is null and movement_type not in ('custody_out', 'custody_return'))
    or (custody_item_id is not null and movement_type in ('custody_out', 'custody_return'))
  ),
  add constraint inventory_movements_custody_item_fk
    foreign key (shop_id, custody_item_id)
    references public.inventory_custody_items (shop_id, id) on delete restrict;

create index inventory_movements_custody_item_idx
  on public.inventory_movements (shop_id, custody_item_id)
  where custody_item_id is not null;

create or replace function private.reject_custody_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  raise exception 'Custody records are durable and cannot be deleted or truncated.'
    using errcode = '42501';
end;
$function$;

revoke all on function private.reject_custody_delete()
  from public, anon, authenticated, service_role;

create trigger inventory_custody_cases_no_delete
  before delete on public.inventory_custody_cases
  for each row execute function private.reject_custody_delete();
create trigger inventory_custody_cases_no_truncate
  before truncate on public.inventory_custody_cases
  for each statement execute function private.reject_custody_delete();
create trigger inventory_custody_items_no_delete
  before delete on public.inventory_custody_items
  for each row execute function private.reject_custody_delete();
create trigger inventory_custody_items_no_truncate
  before truncate on public.inventory_custody_items
  for each statement execute function private.reject_custody_delete();
create trigger inventory_custody_incidents_no_delete
  before delete on public.inventory_custody_incidents
  for each row execute function private.reject_custody_delete();
create trigger inventory_custody_incidents_no_truncate
  before truncate on public.inventory_custody_incidents
  for each statement execute function private.reject_custody_delete();
create trigger inventory_custody_events_append_only
  before update or delete on public.inventory_custody_events
  for each row execute function private.reject_inventory_audit_mutation();
create trigger inventory_custody_events_no_truncate
  before truncate on public.inventory_custody_events
  for each statement execute function private.reject_inventory_audit_mutation();

create or replace function private.guard_custody_case_update()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.id is distinct from old.id
    or new.shop_id is distinct from old.shop_id
    or new.branch_id is distinct from old.branch_id
    or new.case_reference is distinct from old.case_reference
    or new.purpose is distinct from old.purpose
    or new.reason is distinct from old.reason
    or new.requested_by is distinct from old.requested_by
    or new.requested_at is distinct from old.requested_at
    or new.created_at is distinct from old.created_at
    or new.version <> old.version + 1
  then
    raise exception 'Custody case identity and request evidence are immutable.'
      using errcode = '42501';
  end if;
  if not (
    new.status = old.status
    or (old.status = 'requested' and new.status in ('approved', 'cancelled'))
    or (old.status = 'approved' and new.status in ('handed_over', 'cancelled'))
    or (old.status = 'handed_over' and new.status in ('partially_returned', 'returned'))
    or (old.status = 'partially_returned' and new.status in ('partially_returned', 'returned'))
  ) then
    raise exception 'The custody case state transition is invalid.'
      using errcode = '23514';
  end if;
  return new;
end;
$function$;

create trigger inventory_custody_cases_state_guard
  before update on public.inventory_custody_cases
  for each row execute function private.guard_custody_case_update();

create or replace function private.guard_custody_item_update()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.id is distinct from old.id
    or new.shop_id is distinct from old.shop_id
    or new.branch_id is distinct from old.branch_id
    or new.case_id is distinct from old.case_id
    or new.line_number is distinct from old.line_number
    or new.serialized_inventory_id is distinct from old.serialized_inventory_id
    or new.custodian_type is distinct from old.custodian_type
    or new.custodian_user_id is distinct from old.custodian_user_id
    or new.custodian_name_snapshot is distinct from old.custodian_name_snapshot
    or new.custodian_contact_snapshot is distinct from old.custodian_contact_snapshot
    or new.expected_return_at is distinct from old.expected_return_at
    or (old.handover_condition is not null
      and new.handover_condition is distinct from old.handover_condition)
    or (old.return_condition is not null
      and new.return_condition is distinct from old.return_condition)
    or new.created_at is distinct from old.created_at
    or new.version <> old.version + 1
  then
    raise exception 'Custody item identity and custodian evidence are immutable.'
      using errcode = '42501';
  end if;
  if not (
    (old.state = 'requested' and new.state in ('approved', 'cancelled'))
    or (old.state = 'approved' and new.state in ('handed_over', 'cancelled'))
    or (old.state = 'handed_over' and new.state = 'returned')
  ) then
    raise exception 'The custody item state transition is invalid.'
      using errcode = '23514';
  end if;
  return new;
end;
$function$;

create trigger inventory_custody_items_state_guard
  before update on public.inventory_custody_items
  for each row execute function private.guard_custody_item_update();

create or replace function private.guard_custody_incident_update()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.id is distinct from old.id
    or new.shop_id is distinct from old.shop_id
    or new.branch_id is distinct from old.branch_id
    or new.case_id is distinct from old.case_id
    or new.item_id is distinct from old.item_id
    or new.incident_type is distinct from old.incident_type
    or new.report is distinct from old.report
    or new.evidence is distinct from old.evidence
    or new.reported_by is distinct from old.reported_by
    or new.reported_at is distinct from old.reported_at
    or new.version <> old.version + 1
    or old.status <> 'open'
    or new.status <> 'resolved'
  then
    raise exception 'Incident report evidence is immutable; only an open incident may be resolved.'
      using errcode = '42501';
  end if;
  return new;
end;
$function$;

create trigger inventory_custody_incidents_state_guard
  before update on public.inventory_custody_incidents
  for each row execute function private.guard_custody_incident_update();

revoke all on function private.guard_custody_case_update()
  from public, anon, authenticated, service_role;
revoke all on function private.guard_custody_item_update()
  from public, anon, authenticated, service_role;
revoke all on function private.guard_custody_incident_update()
  from public, anon, authenticated, service_role;

create or replace function private.assert_inventory_custody_access(
  p_shop_id uuid,
  p_branch_id uuid,
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
begin
  if actor_value is null or p_shop_id is null or p_branch_id is null
    or p_action is null
    or p_action not in (
      'request', 'approve', 'handover', 'return', 'cancel', 'report', 'resolve'
    )
  then
    raise exception 'Custody authorization or branch parameters are invalid.'
      using errcode = '42501';
  end if;

  -- Keep the existing branch-first authorization lock order. It prevents a
  -- concurrent branch deactivation or membership revocation from racing a
  -- protected custody transition.
  perform 1
  from public.branches as branch
  where branch.shop_id = p_shop_id
    and branch.id = p_branch_id
    and branch.is_active
  for share;
  if not found then
    raise exception 'The custody branch is inactive or does not belong to this shop.'
      using errcode = '42501';
  end if;

  select membership.role into role_value
  from public.shop_memberships as membership
  where membership.shop_id = p_shop_id
    and membership.user_id = actor_value
    and membership.status = 'active'
  for share;
  if not found then
    raise exception 'An active shop membership is required for custody.'
      using errcode = '42501';
  end if;

  if p_action in ('approve', 'resolve') then
    if role_value not in ('owner', 'manager') then
      raise exception 'Only an Owner or Manager may approve custody or resolve incidents.'
        using errcode = '42501';
    end if;
  elsif role_value not in ('owner', 'manager', 'inventory_staff') then
    raise exception 'This shop role cannot perform the requested custody action.'
      using errcode = '42501';
  end if;

  if role_value = 'manager' or role_value = 'inventory_staff' then
    perform 1
    from public.branch_memberships as assignment
    where assignment.shop_id = p_shop_id
      and assignment.branch_id = p_branch_id
      and assignment.user_id = actor_value
    for share;
    if not found then
      raise exception 'The member is not assigned to this active branch.'
        using errcode = '42501';
    end if;
  end if;

  actor_id := actor_value;
  actor_role := role_value;
  return next;
end;
$function$;

revoke all on function private.assert_inventory_custody_access(uuid, uuid, text)
  from public, anon, authenticated, service_role;

create or replace function private.claim_inventory_custody_operation(
  p_shop_id uuid,
  p_branch_id uuid,
  p_actor_id uuid,
  p_idempotency_key text,
  p_operation_type text,
  p_request_payload jsonb,
  p_result_case_id uuid,
  p_result_incident_id uuid,
  p_currency_code char(3),
  p_currency_version integer
)
returns table (
  operation_id uuid,
  replayed boolean,
  result_case_id uuid,
  result_incident_id uuid
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  inserted_id uuid;
  existing_row public.inventory_operations%rowtype;
begin
  if p_actor_id is null
    or p_idempotency_key is null
    or char_length(btrim(p_idempotency_key)) not between 8 and 120
    or p_request_payload is null
    or jsonb_typeof(p_request_payload) is distinct from 'object'
    or p_operation_type not in (
      'custody_request', 'custody_approval', 'custody_handover',
      'custody_return', 'custody_cancellation', 'custody_incident_report',
      'custody_incident_resolution'
    )
  then
    raise exception 'A valid custody idempotency key and request are required.'
      using errcode = '22023';
  end if;

  insert into public.inventory_operations (
    shop_id, branch_id, operation_type, actor_id, idempotency_key,
    request_payload, result_receipt_id, result_transfer_id,
    result_custody_case_id, result_custody_incident_id,
    valuation_currency_code, currency_version
  ) values (
    p_shop_id, p_branch_id, p_operation_type, p_actor_id,
    btrim(p_idempotency_key), p_request_payload, null, null,
    p_result_case_id, p_result_incident_id, p_currency_code, p_currency_version
  )
  on conflict (shop_id, actor_id, idempotency_key) do nothing
  returning id into inserted_id;

  if inserted_id is not null then
    operation_id := inserted_id;
    replayed := false;
    result_case_id := p_result_case_id;
    result_incident_id := p_result_incident_id;
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
    raise exception 'Custody operation could not be resolved after an idempotency conflict.'
      using errcode = '40001';
  end if;

  if existing_row.operation_type is distinct from p_operation_type
    or existing_row.request_payload is distinct from p_request_payload
    or existing_row.result_custody_case_id is null
    or (p_operation_type <> 'custody_request'
      and existing_row.result_custody_case_id is distinct from p_result_case_id)
    or (p_operation_type <> 'custody_incident_report'
      and existing_row.result_custody_incident_id is distinct from p_result_incident_id)
    or (p_operation_type = 'custody_incident_report'
      and existing_row.result_custody_incident_id is null)
  then
    raise exception 'This idempotency key was already used for a different custody request.'
      using errcode = '23505';
  end if;

  operation_id := existing_row.id;
  replayed := true;
  result_case_id := existing_row.result_custody_case_id;
  result_incident_id := existing_row.result_custody_incident_id;
  return next;
end;
$function$;

revoke all on function private.claim_inventory_custody_operation(
  uuid, uuid, uuid, text, text, jsonb, uuid, uuid, char, integer
) from public, anon, authenticated, service_role;

create or replace function private.record_inventory_custody_event(
  p_shop_id uuid,
  p_branch_id uuid,
  p_case_id uuid,
  p_item_id uuid,
  p_incident_id uuid,
  p_operation_id uuid,
  p_line_number integer,
  p_event_type text,
  p_prior_state text,
  p_new_state text,
  p_actor_id uuid,
  p_event_data jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  event_id_value uuid;
begin
  insert into public.inventory_custody_events (
    shop_id, branch_id, case_id, item_id, incident_id, operation_id,
    line_number, event_type, prior_state, new_state, actor_id, event_data
  ) values (
    p_shop_id, p_branch_id, p_case_id, p_item_id, p_incident_id, p_operation_id,
    p_line_number, p_event_type, p_prior_state, p_new_state, p_actor_id,
    coalesce(p_event_data, '{}'::jsonb)
  ) returning id into event_id_value;
  return event_id_value;
end;
$function$;

revoke all on function private.record_inventory_custody_event(
  uuid, uuid, uuid, uuid, uuid, uuid, integer, text, text, text, uuid, jsonb
) from public, anon, authenticated, service_role;

-- Replace the Phase 3C state guard with the same transfer checks plus the
-- custody transitions. Transfer reservations, dispatch, receipt and cancel
-- retain their prior state-machine requirements.
create or replace function private.guard_serialized_transfer_state_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  line_row public.inventory_transfer_lines%rowtype;
  transfer_row public.inventory_transfers%rowtype;
  custody_item_row public.inventory_custody_items%rowtype;
  open_custody_incident boolean;
begin
  if new.branch_id is not distinct from old.branch_id
    and new.availability_status is not distinct from old.availability_status
    and new.transfer_state is not distinct from old.transfer_state
    and new.custody_state is not distinct from old.custody_state
  then
    return new;
  end if;

  if new.custody_state is distinct from old.custody_state then
    select item.* into custody_item_row
    from public.inventory_custody_items as item
    where item.shop_id = new.shop_id
      and item.serialized_inventory_id = new.id
      and item.branch_id = new.branch_id
      and (
        (new.custody_state = 'requested' and item.state = 'requested')
        or (new.custody_state = 'approved' and item.state = 'approved')
        or (new.custody_state = 'handed_over' and item.state = 'handed_over')
        or (new.custody_state = 'returned_quarantine' and item.state = 'returned')
        or (new.custody_state = 'none' and item.state in ('returned', 'cancelled'))
      )
    order by item.updated_at desc, item.created_at desc, item.id desc
    limit 1;

    if not found then
      raise exception 'A custody state transition requires a matching custody item.'
        using errcode = '42501';
    end if;

    if old.custody_state = 'none' and new.custody_state = 'requested'
      and new.availability_status = 'available'
      and old.availability_status = 'available'
      and new.transfer_state is null and old.transfer_state is null
      and custody_item_row.state = 'requested' and custody_item_row.claim_active
      and new.valuation_status in ('known_cost', 'unknown_cost')
      and not exists (
        select 1 from public.inventory_transfer_lines as active_line
        where active_line.shop_id = new.shop_id
          and active_line.serialized_inventory_id = new.id
          and active_line.claim_active
      )
    then
      return new;
    end if;

    if old.custody_state = 'requested' and new.custody_state = 'approved'
      and old.availability_status = 'available'
      and new.availability_status = 'reserved'
      and new.branch_id = old.branch_id
      and new.transfer_state is null and old.transfer_state is null
      and custody_item_row.state = 'approved' and custody_item_row.claim_active
    then
      return new;
    end if;

    if old.custody_state = 'approved' and new.custody_state = 'handed_over'
      and old.availability_status = 'reserved'
      and new.availability_status = 'reserved'
      and new.branch_id = old.branch_id
      and new.transfer_state is null and old.transfer_state is null
      and custody_item_row.state = 'handed_over' and custody_item_row.claim_active
    then
      return new;
    end if;

    if old.custody_state = 'handed_over'
      and new.custody_state in ('none', 'returned_quarantine')
      and old.availability_status = 'reserved'
      and new.availability_status in ('available', 'reserved')
      and new.branch_id = old.branch_id
      and new.transfer_state is null and old.transfer_state is null
      and custody_item_row.state = 'returned' and not custody_item_row.claim_active
    then
      select exists (
        select 1 from public.inventory_custody_incidents as incident
        where incident.shop_id = custody_item_row.shop_id
          and incident.item_id = custody_item_row.id
          and incident.status = 'open'
      ) into open_custody_incident;
      if (new.custody_state = 'returned_quarantine' and open_custody_incident
            and new.availability_status = 'reserved')
        or (new.custody_state = 'none' and not open_custody_incident
            and new.availability_status = 'available')
      then
        return new;
      end if;
    end if;

    if old.custody_state in ('requested', 'approved')
      and new.custody_state = 'none'
      and new.availability_status = 'available'
      and new.branch_id = old.branch_id
      and new.transfer_state is null and old.transfer_state is null
      and custody_item_row.state = 'cancelled' and not custody_item_row.claim_active
    then
      return new;
    end if;

    if old.custody_state = 'returned_quarantine'
      and new.custody_state = 'none'
      and old.availability_status = 'reserved'
      and new.availability_status = 'available'
      and new.branch_id = old.branch_id
      and new.transfer_state is null
      and custody_item_row.state = 'returned' and not custody_item_row.claim_active
      and not exists (
        select 1 from public.inventory_custody_incidents as incident
        where incident.shop_id = custody_item_row.shop_id
          and incident.item_id = custody_item_row.id
          and incident.status = 'open'
      )
    then
      return new;
    end if;

    raise exception 'The requested serialized custody state transition is invalid.'
      using errcode = '42501';
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
    if found and old.custody_state = 'none' and new.custody_state = 'none'
      and new.branch_id = transfer_row.destination_branch_id
      and new.availability_status = 'available'
      and new.transfer_state is null
      and line_row.dispatched_qty = 1 and line_row.received_qty = 1
      and not line_row.claim_active
    then return new; end if;
    raise exception 'An in-transit device can only become available at its transfer destination after recorded receipt.'
      using errcode = '42501';
  end if;

  if new.transfer_state = 'in_transit' then
    if found and old.custody_state = 'none' and new.custody_state = 'none'
      and old.availability_status = 'reserved'
      and new.availability_status = 'reserved'
      and new.branch_id = transfer_row.source_branch_id
      and transfer_row.status = 'approved' and line_row.claim_active
      and line_row.approved_qty = 1 and line_row.dispatched_qty = 1
      and line_row.received_qty = 0
    then return new; end if;
    raise exception 'Only a dispatched transfer device may enter the in-transit state.'
      using errcode = '42501';
  end if;

  if new.availability_status = 'reserved'
    and old.availability_status is distinct from 'reserved'
  then
    if found and old.custody_state = 'none' and new.custody_state = 'none'
      and old.availability_status = 'available'
      and old.transfer_state is null and new.transfer_state is null
      and new.branch_id = transfer_row.source_branch_id
      and transfer_row.status = 'requested' and line_row.claim_active
      and line_row.approved_qty = 1 and line_row.dispatched_qty = 0
    then return new; end if;
    raise exception 'A serialized device may be reserved only by a transfer or custody approval.'
      using errcode = '42501';
  end if;

  if old.availability_status = 'reserved'
    and old.transfer_state is null and found
    and old.custody_state = 'none' and new.custody_state = 'none'
  then
    if new.availability_status = 'available'
      and new.transfer_state is null
      and new.branch_id = transfer_row.source_branch_id
      and transfer_row.status = 'approved'
      and line_row.approved_qty = 1 and line_row.dispatched_qty = 0
      and not line_row.claim_active
    then return new; end if;
    raise exception 'A transfer-reserved device may only be dispatched or released by pre-dispatch cancellation.'
      using errcode = '42501';
  end if;

  if old.transfer_state is null and new.transfer_state is not null then
    raise exception 'Unsupported serialized transfer state transition.'
      using errcode = '42501';
  end if;
  if (new.availability_status = 'reserved'
      and old.availability_status is distinct from 'reserved')
    or (old.availability_status = 'reserved'
      and (new.availability_status is distinct from old.availability_status
        or new.branch_id is distinct from old.branch_id
        or new.transfer_state is distinct from old.transfer_state))
  then
    raise exception 'A reserved serialized device requires an authorized transfer or custody transition.'
      using errcode = '42501';
  end if;
  return new;
end;
$function$;

revoke all on function private.guard_serialized_transfer_state_update()
  from public, anon, authenticated, service_role;

drop trigger serialized_inventory_guard_transfer_state on public.serialized_inventory;
create trigger serialized_inventory_guard_transfer_state
  before update of branch_id, availability_status, transfer_state, custody_state
  on public.serialized_inventory
  for each row execute function private.guard_serialized_transfer_state_update();

create or replace function private.guard_transfer_line_custody_claim()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  device_row public.serialized_inventory%rowtype;
begin
  if new.tracking_mode <> 'serialized' then
    return new;
  end if;
  -- The transfer RPC inserts lines in caller order. Serialize this claim phase
  -- per shop so multi-device requests cannot deadlock against sorted custody
  -- requests that contain the same devices in a different order.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stockpilot:device-claim:' || new.shop_id::text, 0)
  );
  select device.* into device_row
  from public.serialized_inventory as device
  where device.shop_id = new.shop_id
    and device.variant_id = new.variant_id
    and device.id = new.serialized_inventory_id
  for update;
  if not found
    or device_row.availability_status <> 'available'
    or device_row.transfer_state is not null
    or device_row.custody_state <> 'none'
    or device_row.valuation_status is distinct from new.valuation_status
    or new.claim_active is not true
    or exists (
      select 1 from public.inventory_custody_items as custody_item
      where custody_item.shop_id = new.shop_id
        and custody_item.serialized_inventory_id = new.serialized_inventory_id
        and custody_item.claim_active
    )
  then
    raise exception 'A serialized device with a custody claim is unavailable for transfer.'
      using errcode = '23514';
  end if;
  return new;
end;
$function$;

revoke all on function private.guard_transfer_line_custody_claim()
  from public, anon, authenticated, service_role;
create trigger inventory_transfer_lines_guard_custody_claim
  before insert on public.inventory_transfer_lines
  for each row execute function private.guard_transfer_line_custody_claim();

create or replace function public.request_inventory_custody(
  p_shop_id uuid,
  p_branch_id uuid,
  p_purpose text,
  p_reason text,
  p_items jsonb,
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
  new_case_id uuid := gen_random_uuid();
  case_reference_value text;
  purpose_value text := nullif(btrim(p_purpose), '');
  reason_value text := nullif(btrim(p_reason), '');
  canonical_items jsonb;
  item_value record;
  device_row public.serialized_inventory%rowtype;
  member_role public.shop_role;
  line_number_value integer;
  item_id_value uuid;
  expected_at_value timestamptz;
  request_payload_value jsonb;
begin
  select * into actor_record
  from private.assert_inventory_custody_access(p_shop_id, p_branch_id, 'request');
  select * into currency_record
  from private.lock_inventory_transfer_currency(p_shop_id);

  if purpose_value is null or char_length(purpose_value) > 300
    or reason_value is null or char_length(reason_value) > 1000
    or p_items is null or jsonb_typeof(p_items) is distinct from 'array'
    or jsonb_array_length(p_items) not between 1 and 100
  then
    raise exception 'Custody requires a purpose, reason, and 1 to 100 device entries.'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_items) as entry(value)
    where jsonb_typeof(entry.value) is distinct from 'object'
      or (select count(*) from jsonb_object_keys(entry.value)) <> 6
      or not (entry.value ?& array[
        'serialized_inventory_id', 'custodian_type', 'custodian_user_id',
        'custodian_name', 'custodian_contact', 'expected_return_at'
      ])
      or jsonb_typeof(entry.value -> 'serialized_inventory_id') is distinct from 'string'
      or (entry.value ->> 'serialized_inventory_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or jsonb_typeof(entry.value -> 'custodian_type') is distinct from 'string'
      or entry.value ->> 'custodian_type' not in ('employee', 'external')
      or jsonb_typeof(entry.value -> 'expected_return_at') not in ('string', 'null')
      or (
        entry.value ->> 'custodian_type' = 'employee'
        and (
          jsonb_typeof(entry.value -> 'custodian_user_id') is distinct from 'string'
          or (entry.value ->> 'custodian_user_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          or jsonb_typeof(entry.value -> 'custodian_name') is distinct from 'null'
          or jsonb_typeof(entry.value -> 'custodian_contact') is distinct from 'null'
        )
      )
      or (
        entry.value ->> 'custodian_type' = 'external'
        and (
          jsonb_typeof(entry.value -> 'custodian_user_id') is distinct from 'null'
          or jsonb_typeof(entry.value -> 'custodian_name') is distinct from 'string'
          or char_length(btrim(entry.value ->> 'custodian_name')) not between 1 and 200
          or jsonb_typeof(entry.value -> 'custodian_contact') not in ('string', 'null')
          or char_length(coalesce(entry.value ->> 'custodian_contact', '')) > 300
        )
      )
  ) then
    raise exception 'Custody device entries have invalid or unrecognized fields.'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_items) as entry(value)
    group by (entry.value ->> 'serialized_inventory_id')::uuid
    having count(*) > 1
  ) then
    raise exception 'A device may appear only once in a custody case.'
      using errcode = '22023';
  end if;

  begin
    if exists (
      select 1
      from jsonb_array_elements(p_items) as entry(value)
      where entry.value ->> 'expected_return_at' is not null
        and (entry.value ->> 'expected_return_at')::timestamptz <= clock_timestamp()
    ) then
      raise exception 'Expected return dates must be in the future.' using errcode = '22023';
    end if;
  exception when invalid_datetime_format or datetime_field_overflow then
    raise exception 'Expected return dates must be valid timestamps.'
      using errcode = '22023';
  end;

  select jsonb_agg(
    jsonb_build_object(
      'serialized_inventory_id', (entry.value ->> 'serialized_inventory_id')::uuid::text,
      'custodian_type', entry.value ->> 'custodian_type',
      'custodian_user_id', entry.value -> 'custodian_user_id',
      'custodian_name', case when entry.value ->> 'custodian_type' = 'external'
        then to_jsonb(btrim(entry.value ->> 'custodian_name')) else 'null'::jsonb end,
      'custodian_contact', case when entry.value ->> 'custodian_contact' is null
        then 'null'::jsonb else to_jsonb(btrim(entry.value ->> 'custodian_contact')) end,
      'expected_return_at', entry.value -> 'expected_return_at'
    ) order by (entry.value ->> 'serialized_inventory_id')::uuid
  ) into canonical_items
  from jsonb_array_elements(p_items) as entry(value);

  request_payload_value := jsonb_build_object(
    'shop_id', p_shop_id,
    'branch_id', p_branch_id,
    'purpose', purpose_value,
    'reason', reason_value,
    'items', canonical_items
  );

  select * into operation_record
  from private.claim_inventory_custody_operation(
    p_shop_id, p_branch_id, actor_record.actor_id, p_idempotency_key,
    'custody_request', request_payload_value, new_case_id, null,
    currency_record.currency_code, currency_record.currency_version
  );
  if operation_record.replayed then
    return operation_record.result_case_id;
  end if;

  -- Match catalog archive and transfer request lock order before locking any
  -- serialized device. The device rows below are always locked by UUID order.
  lock table public.products in row share mode;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stockpilot:device-claim:' || p_shop_id::text, 0)
  );
  for item_value in
    select entry.value
    from jsonb_array_elements(canonical_items) as entry(value)
    order by (entry.value ->> 'serialized_inventory_id')::uuid
  loop
    item_id_value := (item_value.value ->> 'serialized_inventory_id')::uuid;
    select device.* into device_row
    from public.serialized_inventory as device
    join public.product_variants as variant
      on variant.shop_id = device.shop_id and variant.id = device.variant_id
    join public.products as product
      on product.shop_id = variant.shop_id and product.id = variant.product_id
    where device.shop_id = p_shop_id
      and device.branch_id = p_branch_id
      and device.id = item_id_value
      and device.availability_status = 'available'
      and device.transfer_state is null
      and device.custody_state = 'none'
      and device.valuation_status in ('known_cost', 'unknown_cost')
      and product.tracking_mode = 'serialized'
      and product.archived_at is null and variant.archived_at is null
    for update of device;
    if not found then
      raise exception 'A device is unavailable, pending FX, archived, or not at the source branch.'
        using errcode = '23514';
    end if;

    if exists (
      select 1 from public.inventory_transfer_lines as transfer_line
      where transfer_line.shop_id = p_shop_id
        and transfer_line.serialized_inventory_id = item_id_value
        and transfer_line.claim_active
    ) then
      raise exception 'A device already claimed by a branch transfer cannot enter custody.'
        using errcode = '23514';
    end if;

    if item_value.value ->> 'custodian_type' = 'employee' then
      select membership.role into member_role
      from public.shop_memberships as membership
      where membership.shop_id = p_shop_id
        and membership.user_id = (item_value.value ->> 'custodian_user_id')::uuid
        and membership.status = 'active'
      for share;
      if not found then
        raise exception 'An employee custodian must be an active member of this shop.'
          using errcode = '23514';
      end if;
      if member_role <> 'owner' and not exists (
        select 1 from public.branch_memberships as assignment
        where assignment.shop_id = p_shop_id
          and assignment.branch_id = p_branch_id
          and assignment.user_id = (item_value.value ->> 'custodian_user_id')::uuid
      ) then
        raise exception 'An employee custodian must be assigned to the source branch.'
          using errcode = '23514';
      end if;
    end if;
  end loop;

  case_reference_value := 'CUS-' || upper(substr(replace(new_case_id::text, '-', ''), 1, 12));
  insert into public.inventory_custody_cases (
    id, shop_id, branch_id, case_reference, purpose, reason, status, version,
    requested_by, requested_at
  ) values (
    new_case_id, p_shop_id, p_branch_id, case_reference_value,
    purpose_value, reason_value, 'requested', 1,
    actor_record.actor_id, clock_timestamp()
  );

  line_number_value := 0;
  for item_value in
    select entry.value
    from jsonb_array_elements(canonical_items) as entry(value)
    order by (entry.value ->> 'serialized_inventory_id')::uuid
  loop
    line_number_value := line_number_value + 1;
    item_id_value := (item_value.value ->> 'serialized_inventory_id')::uuid;
    expected_at_value := nullif(item_value.value ->> 'expected_return_at', '')::timestamptz;
    insert into public.inventory_custody_items (
      shop_id, branch_id, case_id, line_number, serialized_inventory_id,
      custodian_type, custodian_user_id, custodian_name_snapshot,
      custodian_contact_snapshot, expected_return_at, state, claim_active
    ) values (
      p_shop_id, p_branch_id, new_case_id, line_number_value, item_id_value,
      item_value.value ->> 'custodian_type',
      nullif(item_value.value ->> 'custodian_user_id', '')::uuid,
      nullif(item_value.value ->> 'custodian_name', ''),
      nullif(item_value.value ->> 'custodian_contact', ''),
      expected_at_value, 'requested', true
    ) returning id into item_id_value;

    update public.serialized_inventory
    set custody_state = 'requested', updated_at = clock_timestamp(),
        updated_by = actor_record.actor_id
    where shop_id = p_shop_id
      and id = (item_value.value ->> 'serialized_inventory_id')::uuid;

    perform private.record_inventory_custody_event(
      p_shop_id, p_branch_id, new_case_id, item_id_value, null,
      operation_record.operation_id, line_number_value, 'item_requested',
      null, 'requested', actor_record.actor_id,
      jsonb_build_object(
        'serialized_inventory_id', item_value.value ->> 'serialized_inventory_id',
        'custodian_type', item_value.value ->> 'custodian_type',
        'custodian_user_id', item_value.value -> 'custodian_user_id',
        'custodian_name', item_value.value -> 'custodian_name',
        'custodian_contact', item_value.value -> 'custodian_contact',
        'expected_return_at', item_value.value -> 'expected_return_at'
      )
    );
  end loop;

  perform private.record_inventory_custody_event(
    p_shop_id, p_branch_id, new_case_id, null, null,
    operation_record.operation_id, 0, 'requested', null, 'requested',
    actor_record.actor_id, jsonb_build_object(
      'case_reference', case_reference_value,
      'purpose', purpose_value,
      'reason', reason_value,
      'item_count', jsonb_array_length(canonical_items)
    )
  );
  return new_case_id;
end;
$function$;

create or replace function public.approve_inventory_custody(
  p_shop_id uuid,
  p_case_id uuid,
  p_expected_version bigint,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  case_row public.inventory_custody_cases%rowtype;
  actor_record record;
  currency_record record;
  operation_record record;
  item_row public.inventory_custody_items%rowtype;
  device_row public.serialized_inventory%rowtype;
  balance_row public.inventory_balances%rowtype;
  line_number_value integer;
  request_payload_value jsonb;
begin
  select custody_case.* into case_row
  from public.inventory_custody_cases as custody_case
  where custody_case.shop_id = p_shop_id and custody_case.id = p_case_id;
  if not found then
    raise exception 'The custody case does not exist in this shop.' using errcode = '22023';
  end if;
  select * into actor_record
  from private.assert_inventory_custody_access(p_shop_id, case_row.branch_id, 'approve');
  select * into currency_record
  from private.lock_inventory_transfer_currency(p_shop_id);
  if p_expected_version is null or p_expected_version < 1 then
    raise exception 'A positive custody case version is required.' using errcode = '22023';
  end if;
  request_payload_value := jsonb_build_object(
    'case_id', p_case_id, 'expected_version', p_expected_version
  );
  select * into operation_record
  from private.claim_inventory_custody_operation(
    p_shop_id, case_row.branch_id, actor_record.actor_id, p_idempotency_key,
    'custody_approval', request_payload_value, p_case_id, null,
    currency_record.currency_code, currency_record.currency_version
  );
  if operation_record.replayed then return operation_record.result_case_id; end if;

  lock table public.products in row share mode;
  select custody_case.* into case_row
  from public.inventory_custody_cases as custody_case
  where custody_case.shop_id = p_shop_id and custody_case.id = p_case_id
  for update;
  if case_row.status <> 'requested' or case_row.version <> p_expected_version then
    raise exception 'The custody case is not requestable at the supplied version.'
      using errcode = '40001';
  end if;

  line_number_value := 0;
  for item_row in
    select item.* from public.inventory_custody_items as item
    where item.shop_id = p_shop_id and item.case_id = p_case_id
    order by item.serialized_inventory_id, item.id
    for update
  loop
    line_number_value := line_number_value + 1;
    if item_row.state <> 'requested' or not item_row.claim_active then
      raise exception 'Every custody item must remain requested before approval.'
        using errcode = '23514';
    end if;
    select device.* into device_row
    from public.serialized_inventory as device
    where device.shop_id = p_shop_id
      and device.branch_id = case_row.branch_id
      and device.id = item_row.serialized_inventory_id
      and device.availability_status = 'available'
      and device.transfer_state is null
      and device.custody_state = 'requested'
      and device.valuation_status in ('known_cost', 'unknown_cost')
    for update;
    if not found then
      raise exception 'A requested device is no longer available for custody approval.'
        using errcode = '23514';
    end if;
    if exists (
      select 1 from public.inventory_transfer_lines as transfer_line
      where transfer_line.shop_id = p_shop_id
        and transfer_line.serialized_inventory_id = item_row.serialized_inventory_id
        and transfer_line.claim_active
    ) then
      raise exception 'A device claimed by a transfer cannot be reserved for custody.'
        using errcode = '23514';
    end if;
    if item_row.custodian_type = 'employee' and not exists (
      select 1 from public.shop_memberships as membership
      where membership.shop_id = p_shop_id
        and membership.user_id = item_row.custodian_user_id
        and membership.status = 'active'
        and (membership.role = 'owner' or exists (
          select 1 from public.branch_memberships as assignment
          where assignment.shop_id = p_shop_id
            and assignment.branch_id = case_row.branch_id
            and assignment.user_id = membership.user_id
        ))
    ) then
      raise exception 'The employee custodian is no longer active or assigned to this branch.'
        using errcode = '23514';
    end if;
    select balance.* into balance_row
    from public.inventory_balances as balance
    where balance.shop_id = p_shop_id
      and balance.branch_id = case_row.branch_id
      and balance.variant_id = device_row.variant_id
      and balance.valuation_status = device_row.valuation_status
    for update;
    if not found or balance_row.on_hand_qty < 1 or balance_row.available_qty < 1
      or balance_row.valuation_currency_code is distinct from device_row.valuation_currency_code
    then
      raise exception 'The source branch balance cannot reserve this device.'
        using errcode = '23514';
    end if;
    update public.inventory_balances
    set available_qty = available_qty - 1,
        reserved_custody_qty = reserved_custody_qty + 1,
        updated_at = clock_timestamp(), updated_by = actor_record.actor_id
    where shop_id = p_shop_id and id = balance_row.id;
    update public.inventory_custody_items
    set state = 'approved', approved_by = actor_record.actor_id,
        approved_at = clock_timestamp(), version = version + 1,
        updated_at = clock_timestamp()
    where shop_id = p_shop_id and id = item_row.id;
    update public.serialized_inventory
    set availability_status = 'reserved', custody_state = 'approved',
        updated_at = clock_timestamp(), updated_by = actor_record.actor_id
    where shop_id = p_shop_id and id = item_row.serialized_inventory_id;
    perform private.record_inventory_custody_event(
      p_shop_id, case_row.branch_id, p_case_id, item_row.id, null,
      operation_record.operation_id, line_number_value, 'item_approved',
      'requested', 'approved', actor_record.actor_id,
      jsonb_build_object('serialized_inventory_id', item_row.serialized_inventory_id,
        'reserved_qty', 1, 'on_hand_delta', 0,
        'valuation_status', device_row.valuation_status)
    );
  end loop;

  update public.inventory_custody_cases
  set status = 'approved', version = version + 1,
      approved_by = actor_record.actor_id, approved_at = clock_timestamp(),
      updated_at = clock_timestamp()
  where shop_id = p_shop_id and id = p_case_id;
  perform private.record_inventory_custody_event(
    p_shop_id, case_row.branch_id, p_case_id, null, null,
    operation_record.operation_id, 0, 'approved', 'requested', 'approved',
    actor_record.actor_id, jsonb_build_object('item_count', line_number_value)
  );
  return p_case_id;
end;
$function$;

create or replace function public.handover_inventory_custody(
  p_shop_id uuid,
  p_case_id uuid,
  p_expected_version bigint,
  p_conditions jsonb,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  case_row public.inventory_custody_cases%rowtype;
  actor_record record;
  currency_record record;
  operation_record record;
  item_row public.inventory_custody_items%rowtype;
  device_row public.serialized_inventory%rowtype;
  balance_row public.inventory_balances%rowtype;
  input_value record;
  canonical_conditions jsonb;
  item_condition text;
  line_number_value integer := 0;
  moved_value numeric(38, 8);
  remaining_value numeric(38, 8);
  remaining_qty integer;
  request_payload_value jsonb;
begin
  select custody_case.* into case_row
  from public.inventory_custody_cases as custody_case
  where custody_case.shop_id = p_shop_id and custody_case.id = p_case_id;
  if not found then
    raise exception 'The custody case does not exist in this shop.' using errcode = '22023';
  end if;
  select * into actor_record
  from private.assert_inventory_custody_access(p_shop_id, case_row.branch_id, 'handover');
  select * into currency_record
  from private.lock_inventory_transfer_currency(p_shop_id);
  if p_expected_version is null or p_expected_version < 1
    or p_conditions is null or jsonb_typeof(p_conditions) is distinct from 'array'
    or jsonb_array_length(p_conditions) not between 1 and 100
  then
    raise exception 'A current case version and condition evidence for every device are required.'
      using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_conditions) as entry(value)
    where jsonb_typeof(entry.value) is distinct from 'object'
      or (select count(*) from jsonb_object_keys(entry.value)) <> 2
      or not (entry.value ?& array['item_id', 'condition'])
      or jsonb_typeof(entry.value -> 'item_id') is distinct from 'string'
      or (entry.value ->> 'item_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or jsonb_typeof(entry.value -> 'condition') is distinct from 'string'
      or char_length(btrim(entry.value ->> 'condition')) not between 1 and 2000
  ) then
    raise exception 'Each handover condition must identify one item and contain a description.'
      using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_conditions) as entry(value)
    group by (entry.value ->> 'item_id')::uuid having count(*) > 1
  ) then
    raise exception 'A custody item may appear only once in the handover.'
      using errcode = '22023';
  end if;
  select jsonb_agg(jsonb_build_object(
    'item_id', (entry.value ->> 'item_id')::uuid::text,
    'condition', btrim(entry.value ->> 'condition')
  ) order by (entry.value ->> 'item_id')::uuid)
  into canonical_conditions
  from jsonb_array_elements(p_conditions) as entry(value);
  request_payload_value := jsonb_build_object(
    'case_id', p_case_id, 'expected_version', p_expected_version,
    'conditions', canonical_conditions
  );
  select * into operation_record
  from private.claim_inventory_custody_operation(
    p_shop_id, case_row.branch_id, actor_record.actor_id, p_idempotency_key,
    'custody_handover', request_payload_value, p_case_id, null,
    currency_record.currency_code, currency_record.currency_version
  );
  if operation_record.replayed then return operation_record.result_case_id; end if;

  lock table public.products in row share mode;
  select custody_case.* into case_row
  from public.inventory_custody_cases as custody_case
  where custody_case.shop_id = p_shop_id and custody_case.id = p_case_id
  for update;
  if case_row.status <> 'approved' or case_row.version <> p_expected_version then
    raise exception 'Only the current approved custody case can be handed over.'
      using errcode = '40001';
  end if;
  if jsonb_array_length(canonical_conditions) <> (
    select count(*) from public.inventory_custody_items as item
    where item.shop_id = p_shop_id and item.case_id = p_case_id
  ) or exists (
    select 1 from jsonb_array_elements(canonical_conditions) as condition(value)
    where not exists (
      select 1 from public.inventory_custody_items as item
      where item.shop_id = p_shop_id and item.case_id = p_case_id
        and item.id = (condition.value ->> 'item_id')::uuid
    )
  ) then
    raise exception 'Handover condition evidence must cover exactly the items in this case.'
      using errcode = '23514';
  end if;

  for input_value in
    select condition.value
    from jsonb_array_elements(canonical_conditions) as condition(value)
    join public.inventory_custody_items as sort_item
      on sort_item.shop_id = p_shop_id
     and sort_item.case_id = p_case_id
     and sort_item.id = (condition.value ->> 'item_id')::uuid
    order by sort_item.serialized_inventory_id, sort_item.id
  loop
    line_number_value := line_number_value + 1;
    select item.* into item_row
    from public.inventory_custody_items as item
    where item.shop_id = p_shop_id and item.id = (input_value.value ->> 'item_id')::uuid
    for update;
    if not found or item_row.state <> 'approved' or not item_row.claim_active then
      raise exception 'Every item must be approved and actively claimed before handover.'
        using errcode = '23514';
    end if;
    select device.* into device_row
    from public.serialized_inventory as device
    where device.shop_id = p_shop_id
      and device.branch_id = case_row.branch_id
      and device.id = item_row.serialized_inventory_id
      and device.availability_status = 'reserved'
      and device.transfer_state is null
      and device.custody_state = 'approved'
      and device.valuation_status in ('known_cost', 'unknown_cost')
    for update;
    if not found then
      raise exception 'An approved device is no longer held for this custody case.'
        using errcode = '23514';
    end if;
    if item_row.custodian_type = 'employee' and not exists (
      select 1 from public.shop_memberships as membership
      where membership.shop_id = p_shop_id
        and membership.user_id = item_row.custodian_user_id
        and membership.status = 'active'
        and (membership.role = 'owner' or exists (
          select 1 from public.branch_memberships as assignment
          where assignment.shop_id = p_shop_id
            and assignment.branch_id = case_row.branch_id
            and assignment.user_id = membership.user_id
        ))
    ) then
      raise exception 'The employee custodian is no longer active or assigned to this branch.'
        using errcode = '23514';
    end if;
    select balance.* into balance_row
    from public.inventory_balances as balance
    where balance.shop_id = p_shop_id
      and balance.branch_id = case_row.branch_id
      and balance.variant_id = device_row.variant_id
      and balance.valuation_status = device_row.valuation_status
    for update;
    if not found or balance_row.on_hand_qty < 1
      or balance_row.reserved_custody_qty < 1
      or balance_row.valuation_currency_code is distinct from device_row.valuation_currency_code
    then
      raise exception 'The approved custody reservation is missing from the source balance.'
        using errcode = '23514';
    end if;

    remaining_qty := balance_row.on_hand_qty - 1;
    if device_row.valuation_status = 'known_cost' then
      moved_value := round(device_row.unit_cost_shop, 8);
      if moved_value > balance_row.carrying_value_shop then
        raise exception 'The device cost exceeds the source balance carrying value.'
          using errcode = '23514';
      end if;
      remaining_value := balance_row.carrying_value_shop - moved_value;
    else
      moved_value := null;
      remaining_value := null;
    end if;
    update public.inventory_balances
    set on_hand_qty = remaining_qty,
        reserved_custody_qty = reserved_custody_qty - 1,
        carrying_value_shop = case when valuation_status = 'known_cost'
          then remaining_value else null end,
        average_unit_cost_shop = case when valuation_status = 'known_cost'
          then case when remaining_qty = 0 then 0::numeric
            else round(remaining_value / remaining_qty, 10) end else null end,
        updated_at = clock_timestamp(), updated_by = actor_record.actor_id
    where shop_id = p_shop_id and id = balance_row.id;

    item_condition := btrim(input_value.value ->> 'condition');
    update public.inventory_custody_items
    set state = 'handed_over', handover_condition = item_condition,
        handed_over_by = actor_record.actor_id, handed_over_at = clock_timestamp(),
        version = version + 1, updated_at = clock_timestamp()
    where shop_id = p_shop_id and id = item_row.id;
    update public.serialized_inventory
    set custody_state = 'handed_over', updated_at = clock_timestamp(),
        updated_by = actor_record.actor_id
    where shop_id = p_shop_id and id = item_row.serialized_inventory_id;

    insert into public.inventory_movements (
      shop_id, branch_id, operation_id, receipt_line_id, transfer_line_id,
      custody_item_id, variant_id, serialized_inventory_id, movement_type,
      valuation_status, valuation_currency_code, on_hand_delta, available_delta,
      unit_cost_shop, extended_cost_shop, reason, actor_id, line_number
    ) values (
      p_shop_id, case_row.branch_id, operation_record.operation_id,
      null, null, item_row.id, device_row.variant_id, device_row.id, 'custody_out',
      device_row.valuation_status, currency_record.currency_code,
      -1, 0, device_row.unit_cost_shop, moved_value,
      case_row.reason, actor_record.actor_id, line_number_value
    );
    perform private.record_inventory_custody_event(
      p_shop_id, case_row.branch_id, p_case_id, item_row.id, null,
      operation_record.operation_id, line_number_value, 'item_handed_over',
      'approved', 'handed_over', actor_record.actor_id,
      jsonb_build_object(
        'serialized_inventory_id', device_row.id,
        'condition', item_condition,
        'valuation_status', device_row.valuation_status,
        'valuation_currency_code', device_row.valuation_currency_code,
        'unit_cost_shop', device_row.unit_cost_shop,
        'extended_cost_shop', moved_value,
        'on_hand_delta', -1
      )
    );
  end loop;

  update public.inventory_custody_cases
  set status = 'handed_over', version = version + 1,
      handed_over_by = actor_record.actor_id, handed_over_at = clock_timestamp(),
      updated_at = clock_timestamp()
  where shop_id = p_shop_id and id = p_case_id;
  perform private.record_inventory_custody_event(
    p_shop_id, case_row.branch_id, p_case_id, null, null,
    operation_record.operation_id, 0, 'handed_over', 'approved', 'handed_over',
    actor_record.actor_id, jsonb_build_object('item_count', line_number_value)
  );
  return p_case_id;
end;
$function$;

create or replace function public.return_inventory_custody(
  p_shop_id uuid,
  p_case_id uuid,
  p_expected_version bigint,
  p_returns jsonb,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  case_row public.inventory_custody_cases%rowtype;
  actor_record record;
  currency_record record;
  operation_record record;
  item_row public.inventory_custody_items%rowtype;
  device_row public.serialized_inventory%rowtype;
  balance_row public.inventory_balances%rowtype;
  input_value record;
  canonical_returns jsonb;
  item_condition text;
  line_number_value integer := 0;
  moved_value numeric(38, 8);
  next_carrying numeric(38, 8);
  next_average numeric(38, 10);
  open_incident boolean;
  next_case_status text;
  request_payload_value jsonb;
begin
  select custody_case.* into case_row
  from public.inventory_custody_cases as custody_case
  where custody_case.shop_id = p_shop_id and custody_case.id = p_case_id;
  if not found then
    raise exception 'The custody case does not exist in this shop.' using errcode = '22023';
  end if;
  select * into actor_record
  from private.assert_inventory_custody_access(p_shop_id, case_row.branch_id, 'return');
  select * into currency_record
  from private.lock_inventory_transfer_currency(p_shop_id);
  if p_expected_version is null or p_expected_version < 1
    or p_returns is null or jsonb_typeof(p_returns) is distinct from 'array'
    or jsonb_array_length(p_returns) not between 1 and 100
  then
    raise exception 'A current case version and one or more return conditions are required.'
      using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_returns) as entry(value)
    where jsonb_typeof(entry.value) is distinct from 'object'
      or (select count(*) from jsonb_object_keys(entry.value)) <> 2
      or not (entry.value ?& array['item_id', 'condition'])
      or jsonb_typeof(entry.value -> 'item_id') is distinct from 'string'
      or (entry.value ->> 'item_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or jsonb_typeof(entry.value -> 'condition') is distinct from 'string'
      or char_length(btrim(entry.value ->> 'condition')) not between 1 and 2000
  ) then
    raise exception 'Each return requires an item ID and a condition description.'
      using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_returns) as entry(value)
    group by (entry.value ->> 'item_id')::uuid having count(*) > 1
  ) then
    raise exception 'A custody item may appear only once in a return operation.'
      using errcode = '22023';
  end if;
  select jsonb_agg(jsonb_build_object(
    'item_id', (entry.value ->> 'item_id')::uuid::text,
    'condition', btrim(entry.value ->> 'condition')
  ) order by (entry.value ->> 'item_id')::uuid)
  into canonical_returns
  from jsonb_array_elements(p_returns) as entry(value);
  request_payload_value := jsonb_build_object(
    'case_id', p_case_id, 'expected_version', p_expected_version,
    'returns', canonical_returns
  );
  select * into operation_record
  from private.claim_inventory_custody_operation(
    p_shop_id, case_row.branch_id, actor_record.actor_id, p_idempotency_key,
    'custody_return', request_payload_value, p_case_id, null,
    currency_record.currency_code, currency_record.currency_version
  );
  if operation_record.replayed then return operation_record.result_case_id; end if;

  lock table public.products in row share mode;
  -- Coordinate claim release with request_inventory_custody and transfer-line
  -- creation before acquiring case/item/device row locks.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stockpilot:device-claim:' || p_shop_id::text, 0)
  );
  select custody_case.* into case_row
  from public.inventory_custody_cases as custody_case
  where custody_case.shop_id = p_shop_id and custody_case.id = p_case_id
  for update;
  if case_row.status not in ('handed_over', 'partially_returned')
    or case_row.version <> p_expected_version
  then
    raise exception 'Only an outstanding custody case at the current version can be returned.'
      using errcode = '40001';
  end if;
  if exists (
    select 1 from jsonb_array_elements(canonical_returns) as requested(value)
    where not exists (
      select 1 from public.inventory_custody_items as item
      where item.shop_id = p_shop_id and item.case_id = p_case_id
        and item.id = (requested.value ->> 'item_id')::uuid
    )
  ) then
    raise exception 'A return item does not belong to this custody case.'
      using errcode = '23514';
  end if;

  for input_value in
    select requested.value
    from jsonb_array_elements(canonical_returns) as requested(value)
    join public.inventory_custody_items as sort_item
      on sort_item.shop_id = p_shop_id
     and sort_item.case_id = p_case_id
     and sort_item.id = (requested.value ->> 'item_id')::uuid
    order by sort_item.serialized_inventory_id, sort_item.id
  loop
    line_number_value := line_number_value + 1;
    select item.* into item_row
    from public.inventory_custody_items as item
    where item.shop_id = p_shop_id and item.id = (input_value.value ->> 'item_id')::uuid
    for update;
    if not found or item_row.state <> 'handed_over' or not item_row.claim_active then
      raise exception 'Only an outstanding handed-over device can be returned.'
        using errcode = '23514';
    end if;
    select device.* into device_row
    from public.serialized_inventory as device
    where device.shop_id = p_shop_id
      and device.branch_id = case_row.branch_id
      and device.id = item_row.serialized_inventory_id
      and device.availability_status = 'reserved'
      and device.transfer_state is null
      and device.custody_state = 'handed_over'
    for update;
    if not found then
      raise exception 'The device is not in the expected custody-held state.'
        using errcode = '23514';
    end if;
    select exists (
      select 1 from public.inventory_custody_incidents as incident
      where incident.shop_id = p_shop_id and incident.item_id = item_row.id
        and incident.status = 'open'
    ) into open_incident;

    insert into public.inventory_balances (
      shop_id, branch_id, variant_id, valuation_status, valuation_currency_code,
      on_hand_qty, available_qty, carrying_value_shop, average_unit_cost_shop,
      updated_by
    ) values (
      p_shop_id, case_row.branch_id, device_row.variant_id,
      device_row.valuation_status, currency_record.currency_code,
      0, 0, case when device_row.valuation_status = 'known_cost' then 0 else null end,
      case when device_row.valuation_status = 'known_cost' then 0 else null end,
      actor_record.actor_id
    ) on conflict (shop_id, branch_id, variant_id, valuation_status) do nothing;
    select balance.* into balance_row
    from public.inventory_balances as balance
    where balance.shop_id = p_shop_id
      and balance.branch_id = case_row.branch_id
      and balance.variant_id = device_row.variant_id
      and balance.valuation_status = device_row.valuation_status
    for update;
    if not found or balance_row.valuation_currency_code is distinct from currency_record.currency_code then
      raise exception 'The source branch balance is unavailable for the custody return.'
        using errcode = '23514';
    end if;
    if device_row.valuation_status = 'known_cost' then
      moved_value := round(device_row.unit_cost_shop, 8);
      next_carrying := balance_row.carrying_value_shop + moved_value;
      next_average := round(next_carrying / (balance_row.on_hand_qty + 1), 10);
    else
      moved_value := null;
      next_carrying := null;
      next_average := null;
    end if;
    update public.inventory_balances
    set on_hand_qty = on_hand_qty + 1,
        available_qty = available_qty + case when open_incident then 0 else 1 end,
        reserved_custody_qty = reserved_custody_qty + case when open_incident then 1 else 0 end,
        carrying_value_shop = next_carrying,
        average_unit_cost_shop = next_average,
        updated_at = clock_timestamp(), updated_by = actor_record.actor_id
    where shop_id = p_shop_id and id = balance_row.id;

    item_condition := btrim(input_value.value ->> 'condition');
    update public.inventory_custody_items
    set state = 'returned', claim_active = false,
        returned_by = actor_record.actor_id, returned_at = clock_timestamp(),
        return_condition = item_condition, version = version + 1,
        updated_at = clock_timestamp()
    where shop_id = p_shop_id and id = item_row.id;
    update public.serialized_inventory
    set availability_status = case when open_incident
          then 'reserved'::public.inventory_availability_status
          else 'available'::public.inventory_availability_status end,
        custody_state = case when open_incident then 'returned_quarantine' else 'none' end,
        updated_at = clock_timestamp(), updated_by = actor_record.actor_id
    where shop_id = p_shop_id and id = item_row.serialized_inventory_id;
    insert into public.inventory_movements (
      shop_id, branch_id, operation_id, receipt_line_id, transfer_line_id,
      custody_item_id, variant_id, serialized_inventory_id, movement_type,
      valuation_status, valuation_currency_code, on_hand_delta, available_delta,
      unit_cost_shop, extended_cost_shop, reason, actor_id, line_number
    ) values (
      p_shop_id, case_row.branch_id, operation_record.operation_id,
      null, null, item_row.id, device_row.variant_id, device_row.id, 'custody_return',
      device_row.valuation_status, currency_record.currency_code,
      1, case when open_incident then 0 else 1 end,
      device_row.unit_cost_shop, moved_value, case_row.reason,
      actor_record.actor_id, line_number_value
    );
    perform private.record_inventory_custody_event(
      p_shop_id, case_row.branch_id, p_case_id, item_row.id, null,
      operation_record.operation_id, line_number_value, 'item_returned',
      'handed_over', case when open_incident then 'returned_quarantine' else 'returned' end,
      actor_record.actor_id, jsonb_build_object(
        'serialized_inventory_id', device_row.id,
        'condition', item_condition,
        'open_incident', open_incident,
        'valuation_status', device_row.valuation_status,
        'valuation_currency_code', device_row.valuation_currency_code,
        'unit_cost_shop', device_row.unit_cost_shop,
        'extended_cost_shop', moved_value,
        'on_hand_delta', 1,
        'available_delta', case when open_incident then 0 else 1 end
      )
    );
  end loop;

  if exists (
    select 1 from public.inventory_custody_items as item
    where item.shop_id = p_shop_id and item.case_id = p_case_id
      and item.claim_active
  ) then
    next_case_status := 'partially_returned';
  else
    next_case_status := 'returned';
  end if;
  update public.inventory_custody_cases
  set status = next_case_status,
      version = version + 1,
      completed_at = case when next_case_status = 'returned'
        then clock_timestamp() else null end,
      updated_at = clock_timestamp()
  where shop_id = p_shop_id and id = p_case_id;
  perform private.record_inventory_custody_event(
    p_shop_id, case_row.branch_id, p_case_id, null, null,
    operation_record.operation_id, 0,
    case when next_case_status = 'returned' then 'returned' else 'partially_returned' end,
    case_row.status, next_case_status, actor_record.actor_id,
    jsonb_build_object('returned_item_count', line_number_value)
  );
  return p_case_id;
end;
$function$;

create or replace function public.cancel_inventory_custody(
  p_shop_id uuid,
  p_case_id uuid,
  p_expected_version bigint,
  p_cancellation_reason text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  case_row public.inventory_custody_cases%rowtype;
  actor_record record;
  currency_record record;
  operation_record record;
  item_row public.inventory_custody_items%rowtype;
  device_row public.serialized_inventory%rowtype;
  balance_row public.inventory_balances%rowtype;
  cancellation_reason_value text := nullif(btrim(p_cancellation_reason), '');
  line_number_value integer := 0;
  request_payload_value jsonb;
begin
  select custody_case.* into case_row
  from public.inventory_custody_cases as custody_case
  where custody_case.shop_id = p_shop_id and custody_case.id = p_case_id;
  if not found then
    raise exception 'The custody case does not exist in this shop.' using errcode = '22023';
  end if;
  select * into actor_record
  from private.assert_inventory_custody_access(p_shop_id, case_row.branch_id, 'cancel');
  select * into currency_record
  from private.lock_inventory_transfer_currency(p_shop_id);
  if p_expected_version is null or p_expected_version < 1
    or cancellation_reason_value is null
    or char_length(cancellation_reason_value) > 1000
  then
    raise exception 'A current case version and cancellation reason are required.'
      using errcode = '22023';
  end if;
  request_payload_value := jsonb_build_object(
    'case_id', p_case_id, 'expected_version', p_expected_version,
    'reason', cancellation_reason_value
  );
  select * into operation_record
  from private.claim_inventory_custody_operation(
    p_shop_id, case_row.branch_id, actor_record.actor_id, p_idempotency_key,
    'custody_cancellation', request_payload_value, p_case_id, null,
    currency_record.currency_code, currency_record.currency_version
  );
  if operation_record.replayed then return operation_record.result_case_id; end if;

  lock table public.products in row share mode;
  -- Do not let a new claim hold a device row while waiting for this item's
  -- active-claim index entry to be released.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stockpilot:device-claim:' || p_shop_id::text, 0)
  );
  select custody_case.* into case_row
  from public.inventory_custody_cases as custody_case
  where custody_case.shop_id = p_shop_id and custody_case.id = p_case_id
  for update;
  if case_row.status not in ('requested', 'approved')
    or case_row.version <> p_expected_version
  then
    raise exception 'Custody can be cancelled only before physical handover.'
      using errcode = '40001';
  end if;
  if actor_record.actor_role = 'inventory_staff'
    and (case_row.status <> 'requested'
      or case_row.requested_by <> actor_record.actor_id)
  then
    raise exception 'Inventory Staff may cancel only their own unapproved custody request.'
      using errcode = '42501';
  end if;

  for item_row in
    select item.* from public.inventory_custody_items as item
    where item.shop_id = p_shop_id and item.case_id = p_case_id
    order by item.serialized_inventory_id, item.id
    for update
  loop
    line_number_value := line_number_value + 1;
    if item_row.state not in ('requested', 'approved') or not item_row.claim_active then
      raise exception 'A custody case with a handed-over device cannot be cancelled.'
        using errcode = '23514';
    end if;
    select device.* into device_row
    from public.serialized_inventory as device
    where device.shop_id = p_shop_id and device.id = item_row.serialized_inventory_id
      and device.branch_id = case_row.branch_id
      and device.custody_state = item_row.state
      and device.transfer_state is null
      and device.availability_status = case when item_row.state = 'requested'
        then 'available'::public.inventory_availability_status
        else 'reserved'::public.inventory_availability_status end
    for update;
    if not found then
      raise exception 'The device is not in the expected pre-handover custody state.'
        using errcode = '23514';
    end if;
    if item_row.state = 'approved' then
      select balance.* into balance_row
      from public.inventory_balances as balance
      where balance.shop_id = p_shop_id
        and balance.branch_id = case_row.branch_id
        and balance.variant_id = device_row.variant_id
        and balance.valuation_status = device_row.valuation_status
      for update;
      if not found or balance_row.reserved_custody_qty < 1 then
        raise exception 'The custody reservation is missing from the branch balance.'
          using errcode = '23514';
      end if;
      update public.inventory_balances
      set available_qty = available_qty + 1,
          reserved_custody_qty = reserved_custody_qty - 1,
          updated_at = clock_timestamp(), updated_by = actor_record.actor_id
      where shop_id = p_shop_id and id = balance_row.id;
    end if;
    update public.inventory_custody_items
    set state = 'cancelled', claim_active = false,
        cancelled_by = actor_record.actor_id, cancelled_at = clock_timestamp(),
        version = version + 1, updated_at = clock_timestamp()
    where shop_id = p_shop_id and id = item_row.id;
    update public.serialized_inventory
    set availability_status = 'available', custody_state = 'none',
        updated_at = clock_timestamp(), updated_by = actor_record.actor_id
    where shop_id = p_shop_id and id = item_row.serialized_inventory_id;
    perform private.record_inventory_custody_event(
      p_shop_id, case_row.branch_id, p_case_id, item_row.id, null,
      operation_record.operation_id, line_number_value, 'item_cancelled',
      item_row.state, 'cancelled', actor_record.actor_id,
      jsonb_build_object('reason', cancellation_reason_value,
        'reservation_released', item_row.state = 'approved')
    );
  end loop;
  update public.inventory_custody_cases
  set status = 'cancelled', version = version + 1,
      cancelled_by = actor_record.actor_id, cancelled_at = clock_timestamp(),
      completed_at = clock_timestamp(), updated_at = clock_timestamp()
  where shop_id = p_shop_id and id = p_case_id;
  perform private.record_inventory_custody_event(
    p_shop_id, case_row.branch_id, p_case_id, null, null,
    operation_record.operation_id, 0, 'cancelled', case_row.status, 'cancelled',
    actor_record.actor_id, jsonb_build_object(
      'reason', cancellation_reason_value, 'item_count', line_number_value
    )
  );
  return p_case_id;
end;
$function$;

create or replace function public.report_custody_incident(
  p_shop_id uuid,
  p_case_id uuid,
  p_item_id uuid,
  p_expected_case_version bigint,
  p_incident_type text,
  p_report text,
  p_evidence jsonb,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  case_row public.inventory_custody_cases%rowtype;
  item_row public.inventory_custody_items%rowtype;
  device_row public.serialized_inventory%rowtype;
  actor_record record;
  currency_record record;
  operation_record record;
  new_incident_id uuid := gen_random_uuid();
  event_type_value text;
  trimmed_report text := nullif(btrim(p_report), '');
  request_payload_value jsonb;
begin
  select custody_case.* into case_row
  from public.inventory_custody_cases as custody_case
  where custody_case.shop_id = p_shop_id and custody_case.id = p_case_id;
  if not found then
    raise exception 'The custody case does not exist in this shop.' using errcode = '22023';
  end if;
  select * into actor_record
  from private.assert_inventory_custody_access(p_shop_id, case_row.branch_id, 'report');
  select * into currency_record
  from private.lock_inventory_transfer_currency(p_shop_id);
  if p_expected_case_version is null or p_expected_case_version < 1
    or p_incident_type not in ('missing', 'damage', 'dispute')
    or trimmed_report is null or char_length(trimmed_report) > 2000
    or p_evidence is null or jsonb_typeof(p_evidence) is distinct from 'object'
    or p_evidence = '{}'::jsonb
  then
    raise exception 'A valid incident type, report, evidence object, and case version are required.'
      using errcode = '22023';
  end if;
  request_payload_value := jsonb_build_object(
    'case_id', p_case_id, 'item_id', p_item_id,
    'expected_case_version', p_expected_case_version,
    'incident_type', p_incident_type, 'report', trimmed_report,
    'evidence', p_evidence
  );
  select * into operation_record
  from private.claim_inventory_custody_operation(
    p_shop_id, case_row.branch_id, actor_record.actor_id, p_idempotency_key,
    'custody_incident_report', request_payload_value, p_case_id,
    new_incident_id, currency_record.currency_code, currency_record.currency_version
  );
  if operation_record.replayed then return operation_record.result_incident_id; end if;

  lock table public.products in row share mode;
  select custody_case.* into case_row
  from public.inventory_custody_cases as custody_case
  where custody_case.shop_id = p_shop_id and custody_case.id = p_case_id
  for update;
  if case_row.version <> p_expected_case_version then
    raise exception 'The custody case changed; refresh before reporting an incident.'
      using errcode = '40001';
  end if;
  select item.* into item_row
  from public.inventory_custody_items as item
  where item.shop_id = p_shop_id and item.case_id = p_case_id and item.id = p_item_id
  for update;
  if not found or item_row.state not in ('handed_over', 'returned') then
    raise exception 'An incident may be reported only for a handed-over or returned custody item.'
      using errcode = '23514';
  end if;
  if p_incident_type = 'missing'
    and (item_row.state <> 'handed_over' or not item_row.claim_active)
  then
    raise exception 'A missing-device report requires the device to remain in active custody.'
      using errcode = '23514';
  end if;
  select device.* into device_row
  from public.serialized_inventory as device
  where device.shop_id = p_shop_id and device.id = item_row.serialized_inventory_id
    and device.branch_id = case_row.branch_id
    and device.custody_state in ('handed_over', 'returned_quarantine')
    and device.availability_status = 'reserved'
  for update;
  if not found then
    raise exception 'The device is no longer in an incident-eligible custody state.'
      using errcode = '23514';
  end if;
  event_type_value := case p_incident_type
    when 'missing' then 'missing_reported'
    when 'damage' then 'damage_reported'
    else 'dispute_reported' end;
  insert into public.inventory_custody_incidents (
    id, shop_id, branch_id, case_id, item_id, incident_type, status,
    report, evidence, reported_by, reported_at
  ) values (
    new_incident_id, p_shop_id, case_row.branch_id, p_case_id, p_item_id,
    p_incident_type, 'open', trimmed_report, p_evidence,
    actor_record.actor_id, clock_timestamp()
  );
  update public.inventory_custody_cases
  set version = version + 1, updated_at = clock_timestamp()
  where shop_id = p_shop_id and id = p_case_id;
  perform private.record_inventory_custody_event(
    p_shop_id, case_row.branch_id, p_case_id, p_item_id, new_incident_id,
    operation_record.operation_id, 0, event_type_value,
    item_row.state, item_row.state, actor_record.actor_id,
    jsonb_build_object(
      'incident_type', p_incident_type, 'report', trimmed_report,
      'evidence', p_evidence, 'device_remains_shop_owned', true,
      'write_off_created', false, 'revenue_or_cogs_created', false
    )
  );
  return new_incident_id;
end;
$function$;

create or replace function public.resolve_custody_incident(
  p_shop_id uuid,
  p_incident_id uuid,
  p_expected_case_version bigint,
  p_expected_incident_version bigint,
  p_resolution text,
  p_resolution_evidence jsonb,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  incident_row public.inventory_custody_incidents%rowtype;
  case_row public.inventory_custody_cases%rowtype;
  item_row public.inventory_custody_items%rowtype;
  device_row public.serialized_inventory%rowtype;
  balance_row public.inventory_balances%rowtype;
  actor_record record;
  currency_record record;
  operation_record record;
  resolution_value text := nullif(btrim(p_resolution), '');
  request_payload_value jsonb;
begin
  select incident.* into incident_row
  from public.inventory_custody_incidents as incident
  where incident.shop_id = p_shop_id and incident.id = p_incident_id;
  if not found then
    raise exception 'The custody incident does not exist in this shop.' using errcode = '22023';
  end if;
  select custody_case.* into case_row
  from public.inventory_custody_cases as custody_case
  where custody_case.shop_id = p_shop_id and custody_case.id = incident_row.case_id;
  select * into actor_record
  from private.assert_inventory_custody_access(p_shop_id, incident_row.branch_id, 'resolve');
  select * into currency_record
  from private.lock_inventory_transfer_currency(p_shop_id);
  if p_expected_case_version is null or p_expected_case_version < 1
    or p_expected_incident_version is null or p_expected_incident_version < 1
    or resolution_value is null or char_length(resolution_value) > 500
    or p_resolution_evidence is null
    or jsonb_typeof(p_resolution_evidence) is distinct from 'object'
    or p_resolution_evidence = '{}'::jsonb
  then
    raise exception 'Incident resolution requires current versions, a reason, and evidence.'
      using errcode = '22023';
  end if;
  request_payload_value := jsonb_build_object(
    'incident_id', p_incident_id,
    'expected_case_version', p_expected_case_version,
    'expected_incident_version', p_expected_incident_version,
    'resolution', resolution_value, 'evidence', p_resolution_evidence
  );
  select * into operation_record
  from private.claim_inventory_custody_operation(
    p_shop_id, incident_row.branch_id, actor_record.actor_id, p_idempotency_key,
    'custody_incident_resolution', request_payload_value, incident_row.case_id,
    p_incident_id, currency_record.currency_code, currency_record.currency_version
  );
  if operation_record.replayed then return operation_record.result_incident_id; end if;

  lock table public.products in row share mode;
  select custody_case.* into case_row
  from public.inventory_custody_cases as custody_case
  where custody_case.shop_id = p_shop_id and custody_case.id = incident_row.case_id
  for update;
  if case_row.version <> p_expected_case_version then
    raise exception 'The custody case changed; refresh before resolving this incident.'
      using errcode = '40001';
  end if;
  select incident.* into incident_row
  from public.inventory_custody_incidents as incident
  where incident.shop_id = p_shop_id and incident.id = p_incident_id
  for update;
  if incident_row.status <> 'open'
    or incident_row.version <> p_expected_incident_version
  then
    raise exception 'The incident is already resolved or changed since review.'
      using errcode = '40001';
  end if;
  select item.* into item_row
  from public.inventory_custody_items as item
  where item.shop_id = p_shop_id and item.case_id = incident_row.case_id
    and item.id = incident_row.item_id
  for update;
  if not found then
    raise exception 'The incident custody item no longer exists.' using errcode = '23503';
  end if;
  if (incident_row.incident_type = 'missing' and resolution_value <> 'located')
    or (incident_row.incident_type = 'damage'
      and resolution_value <> 'cleared_no_value_change')
    or (incident_row.incident_type = 'dispute'
      and resolution_value <> 'resolved_no_loss')
  then
    raise exception 'This Phase 3D-A incident can be closed only with a supported nonfinancial resolution.'
      using errcode = '23514';
  end if;
  if incident_row.incident_type in ('damage', 'dispute')
    and item_row.state <> 'returned'
  then
    raise exception 'Damage or dispute incidents must be reviewed after physical return.'
      using errcode = '23514';
  end if;

  update public.inventory_custody_incidents
  set status = 'resolved', resolved_by = actor_record.actor_id,
      resolved_at = clock_timestamp(), resolution = resolution_value,
      resolution_evidence = p_resolution_evidence, version = version + 1
  where shop_id = p_shop_id and id = p_incident_id;

  select device.* into device_row
  from public.serialized_inventory as device
  where device.shop_id = p_shop_id and device.id = item_row.serialized_inventory_id
    and device.branch_id = incident_row.branch_id
  for update;
  if not found then
    raise exception 'The serialized device no longer matches the custody record.'
      using errcode = '23514';
  end if;
  if item_row.state = 'returned'
    and device_row.custody_state = 'returned_quarantine'
    and not exists (
      select 1 from public.inventory_custody_incidents as incident
      where incident.shop_id = p_shop_id and incident.item_id = item_row.id
        and incident.status = 'open'
    )
  then
    select balance.* into balance_row
    from public.inventory_balances as balance
    where balance.shop_id = p_shop_id
      and balance.branch_id = incident_row.branch_id
      and balance.variant_id = device_row.variant_id
      and balance.valuation_status = device_row.valuation_status
    for update;
    if not found or balance_row.reserved_custody_qty < 1 then
      raise exception 'The returned device quarantine reservation is missing from the balance.'
        using errcode = '23514';
    end if;
    update public.inventory_balances
    set available_qty = available_qty + 1,
        reserved_custody_qty = reserved_custody_qty - 1,
        updated_at = clock_timestamp(), updated_by = actor_record.actor_id
    where shop_id = p_shop_id and id = balance_row.id;
    update public.serialized_inventory
    set availability_status = 'available', custody_state = 'none',
        updated_at = clock_timestamp(), updated_by = actor_record.actor_id
    where shop_id = p_shop_id and id = device_row.id;
  end if;
  update public.inventory_custody_cases
  set version = version + 1, updated_at = clock_timestamp()
  where shop_id = p_shop_id and id = incident_row.case_id;
  perform private.record_inventory_custody_event(
    p_shop_id, incident_row.branch_id, incident_row.case_id, incident_row.item_id,
    p_incident_id, operation_record.operation_id, 0, 'incident_reviewed',
    'open', 'open', actor_record.actor_id,
    jsonb_build_object('resolution', resolution_value, 'evidence', p_resolution_evidence)
  );
  perform private.record_inventory_custody_event(
    p_shop_id, incident_row.branch_id, incident_row.case_id, incident_row.item_id,
    p_incident_id, operation_record.operation_id, 1, 'incident_resolved',
    'open', 'resolved', actor_record.actor_id,
    jsonb_build_object(
      'resolution', resolution_value,
      'evidence', p_resolution_evidence,
      'inventory_write_off_created', false,
      'financial_resolution_pending', false,
      'device_released_to_available',
        item_row.state = 'returned'
        and device_row.custody_state = 'returned_quarantine'
    )
  );
  return p_incident_id;
end;
$function$;

create or replace function private.validate_inventory_custody_movement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  item_row public.inventory_custody_items%rowtype;
  case_row public.inventory_custody_cases%rowtype;
  device_row public.serialized_inventory%rowtype;
  operation_row public.inventory_operations%rowtype;
  expected_value numeric(38, 8);
begin
  if new.custody_item_id is null then
    raise exception 'Custody movements must reference their custody item.'
      using errcode = '23514';
  end if;
  select item.* into item_row
  from public.inventory_custody_items as item
  where item.shop_id = new.shop_id and item.id = new.custody_item_id;
  select custody_case.* into case_row
  from public.inventory_custody_cases as custody_case
  where custody_case.shop_id = item_row.shop_id
    and custody_case.id = item_row.case_id;
  select device.* into device_row
  from public.serialized_inventory as device
  where device.shop_id = item_row.shop_id
    and device.id = item_row.serialized_inventory_id;
  select operation.* into operation_row
  from public.inventory_operations as operation
  where operation.shop_id = new.shop_id
    and operation.branch_id = new.branch_id
    and operation.id = new.operation_id;
  if item_row.id is null or case_row.id is null or device_row.id is null
    or operation_row.id is null
    or item_row.branch_id is distinct from new.branch_id
    or case_row.branch_id is distinct from new.branch_id
    or item_row.serialized_inventory_id is distinct from new.serialized_inventory_id
    or device_row.variant_id is distinct from new.variant_id
    or item_row.branch_id is distinct from device_row.branch_id
    or new.receipt_line_id is not null or new.transfer_line_id is not null
    or operation_row.actor_id is distinct from new.actor_id
    or operation_row.result_custody_case_id is distinct from item_row.case_id
    or operation_row.valuation_currency_code is distinct from new.valuation_currency_code
    or new.valuation_status is distinct from device_row.valuation_status
    or new.unit_cost_shop is distinct from device_row.unit_cost_shop
    or new.reason is distinct from case_row.reason
  then
    raise exception 'Custody movement identity or operation evidence does not match the serialized device.'
      using errcode = '23514';
  end if;

  if device_row.valuation_status = 'known_cost' then
    expected_value := round(device_row.unit_cost_shop, 8);
    if new.extended_cost_shop is distinct from expected_value then
      raise exception 'Custody movement value must equal the device cost rounded to inventory precision.'
        using errcode = '23514';
    end if;
  elsif device_row.valuation_status = 'unknown_cost'
    and (new.extended_cost_shop is not null or new.unit_cost_shop is not null)
  then
    raise exception 'Unknown custody cost must remain NULL.' using errcode = '23514';
  elsif device_row.valuation_status = 'pending_fx' then
    raise exception 'Pending-FX devices cannot create custody movements.' using errcode = '23514';
  end if;

  if new.movement_type = 'custody_out' then
    if operation_row.operation_type <> 'custody_handover'
      or item_row.state <> 'handed_over'
      or device_row.custody_state <> 'handed_over'
      or new.on_hand_delta <> -1 or new.available_delta <> 0
    then
      raise exception 'Custody-out movement does not match a physical handover.'
        using errcode = '23514';
    end if;
  elsif new.movement_type = 'custody_return' then
    if operation_row.operation_type <> 'custody_return'
      or item_row.state <> 'returned'
      or device_row.custody_state not in ('none', 'returned_quarantine')
      or new.on_hand_delta <> 1
      or new.available_delta <> (
        case when device_row.custody_state = 'none' then 1 else 0 end
      )
    then
      raise exception 'Custody-return movement does not match a confirmed physical return.'
        using errcode = '23514';
    end if;
  else
    raise exception 'Only custody-out and custody-return movements may reference custody items.'
      using errcode = '23514';
  end if;
  return new;
end;
$function$;

revoke all on function private.validate_inventory_custody_movement()
  from public, anon, authenticated, service_role;
create trigger inventory_movements_validate_custody
  before insert on public.inventory_movements
  for each row when (
    new.custody_item_id is not null
    or new.movement_type in ('custody_out', 'custody_return')
  ) execute function private.validate_inventory_custody_movement();

create unique index inventory_custody_incidents_open_type_uidx
  on public.inventory_custody_incidents (shop_id, item_id, incident_type)
  where status = 'open';

create or replace function private.guard_branch_transfer_deactivation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if old.is_active and not new.is_active and (
    exists (
      select 1 from public.inventory_transfers as transfer
      where transfer.shop_id = old.shop_id
        and old.id in (transfer.source_branch_id, transfer.destination_branch_id)
        and transfer.status in (
          'requested', 'approved', 'dispatched', 'partially_received'
        )
    )
    or exists (
      select 1 from public.serialized_inventory as device
      where device.shop_id = old.shop_id and device.branch_id = old.id
        and device.custody_state in (
          'requested', 'approved', 'handed_over', 'returned_quarantine'
        )
    )
  ) then
    raise exception 'A branch with an open transfer or custody-held device cannot be deactivated.'
      using errcode = '23514';
  end if;
  return new;
end;
$function$;

revoke all on function private.guard_branch_transfer_deactivation()
  from public, anon, authenticated, service_role;

create view public.inventory_custody_held
with (security_invoker = true)
as
select item.shop_id, item.branch_id, item.case_id, item.id as custody_item_id,
       item.serialized_inventory_id, item.state as custody_state,
       device.variant_id, device.valuation_status,
       device.valuation_currency_code, device.unit_cost_shop,
       case when device.valuation_status = 'known_cost'
         then round(device.unit_cost_shop, 8) else null end as carrying_value_shop,
       1::integer as held_qty, item.expected_return_at,
       exists (
         select 1 from public.inventory_custody_incidents as incident
         where incident.shop_id = item.shop_id
           and incident.item_id = item.id and incident.status = 'open'
       ) as has_open_incident
from public.inventory_custody_items as item
join public.serialized_inventory as device
  on device.shop_id = item.shop_id
 and device.branch_id = item.branch_id
 and device.id = item.serialized_inventory_id
where item.state = 'handed_over' and item.claim_active
  and device.custody_state = 'handed_over';

alter table public.inventory_custody_cases enable row level security;
alter table public.inventory_custody_items enable row level security;
alter table public.inventory_custody_incidents enable row level security;
alter table public.inventory_custody_events enable row level security;

revoke all on public.inventory_custody_cases,
  public.inventory_custody_items,
  public.inventory_custody_incidents,
  public.inventory_custody_events,
  public.inventory_custody_held
  from public, anon, authenticated, service_role;
grant select on public.inventory_custody_cases,
  public.inventory_custody_items,
  public.inventory_custody_incidents,
  public.inventory_custody_events,
  public.inventory_custody_held
  to authenticated, service_role;

create policy inventory_custody_cases_read_authorized
  on public.inventory_custody_cases for select to authenticated
  using (
    private.is_active_shop_member(shop_id)
    and private.has_shop_role(
      shop_id, array['owner', 'manager', 'inventory_staff']::public.shop_role[]
    )
    and (private.has_shop_role(shop_id, array['owner']::public.shop_role[])
      or private.can_access_branch(shop_id, branch_id))
  );
create policy inventory_custody_items_read_authorized
  on public.inventory_custody_items for select to authenticated
  using (
    private.is_active_shop_member(shop_id)
    and private.has_shop_role(
      shop_id, array['owner', 'manager', 'inventory_staff']::public.shop_role[]
    )
    and (private.has_shop_role(shop_id, array['owner']::public.shop_role[])
      or private.can_access_branch(shop_id, branch_id))
  );
create policy inventory_custody_incidents_read_authorized
  on public.inventory_custody_incidents for select to authenticated
  using (
    private.is_active_shop_member(shop_id)
    and private.has_shop_role(
      shop_id, array['owner', 'manager', 'inventory_staff']::public.shop_role[]
    )
    and (private.has_shop_role(shop_id, array['owner']::public.shop_role[])
      or private.can_access_branch(shop_id, branch_id))
  );
create policy inventory_custody_events_read_authorized
  on public.inventory_custody_events for select to authenticated
  using (
    private.is_active_shop_member(shop_id)
    and private.has_shop_role(
      shop_id, array['owner', 'manager', 'inventory_staff']::public.shop_role[]
    )
    and (private.has_shop_role(shop_id, array['owner']::public.shop_role[])
      or private.can_access_branch(shop_id, branch_id))
  );

revoke all on function public.request_inventory_custody(uuid, uuid, text, text, jsonb, text)
  from public, anon, service_role;
revoke all on function public.approve_inventory_custody(uuid, uuid, bigint, text)
  from public, anon, service_role;
revoke all on function public.handover_inventory_custody(uuid, uuid, bigint, jsonb, text)
  from public, anon, service_role;
revoke all on function public.return_inventory_custody(uuid, uuid, bigint, jsonb, text)
  from public, anon, service_role;
revoke all on function public.cancel_inventory_custody(uuid, uuid, bigint, text, text)
  from public, anon, service_role;
revoke all on function public.report_custody_incident(
  uuid, uuid, uuid, bigint, text, text, jsonb, text
) from public, anon, service_role;
revoke all on function public.resolve_custody_incident(
  uuid, uuid, bigint, bigint, text, jsonb, text
) from public, anon, service_role;

grant execute on function public.request_inventory_custody(uuid, uuid, text, text, jsonb, text)
  to authenticated;
grant execute on function public.approve_inventory_custody(uuid, uuid, bigint, text)
  to authenticated;
grant execute on function public.handover_inventory_custody(uuid, uuid, bigint, jsonb, text)
  to authenticated;
grant execute on function public.return_inventory_custody(uuid, uuid, bigint, jsonb, text)
  to authenticated;
grant execute on function public.cancel_inventory_custody(uuid, uuid, bigint, text, text)
  to authenticated;
grant execute on function public.report_custody_incident(
  uuid, uuid, uuid, bigint, text, text, jsonb, text
) to authenticated;
grant execute on function public.resolve_custody_incident(
  uuid, uuid, bigint, bigint, text, jsonb, text
) to authenticated;

comment on table public.inventory_custody_cases is
  'Workflow projection for temporary custody of shop-owned serialized devices; never a sale or write-off.';
comment on table public.inventory_custody_items is
  'Custody episodes reference the original serialized device and preserve its permanent identity.';
comment on table public.inventory_custody_incidents is
  'Current incident projection; an unresolved missing/damage/dispute keeps the device unavailable.';
comment on table public.inventory_custody_events is
  'Append-only request, approval, custody, return, incident, review, and resolution evidence.';
comment on column public.inventory_balances.reserved_custody_qty is
  'Approved custody reservations and returned devices quarantined pending nonfinancial incident review.';
comment on column public.serialized_inventory.custody_state is
  'Custody projection independent of permanent device identity; pending FX is never eligible.';
comment on view public.inventory_custody_held is
  'Shop-owned serialized devices physically held by custodians; carrying value remains shop property.';
