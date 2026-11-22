-- Phase 3D-B: repair workflow for shop-owned serialized devices.
-- Repair evidence never changes original inventory cost or creates accounting
-- postings. Physical movement remains the custody workflow's responsibility.

begin;

do $preflight$
begin
  if to_regclass('public.inventory_balances') is null
    or to_regclass('public.serialized_inventory') is null
    or to_regclass('public.inventory_custody_cases') is null
    or to_regclass('public.inventory_custody_items') is null
    or to_regclass('public.inventory_custody_events') is null
    or to_regclass('public.inventory_custody_incidents') is null
    or to_regclass('public.inventory_operations') is null
  then
    raise exception 'Phase 3D-B requires the committed inventory, transfer, and custody migrations.';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.inventory_balances'::regclass
      and conname = 'inventory_balances_transfer_qty'
  ) then
    raise exception 'Expected inventory_balances_transfer_qty constraint is missing; inspect the baseline before applying Phase 3D-B.';
  end if;
  if to_regclass('public.repair_jobs') is not null
    or to_regclass('public.repair_job_events') is not null
    or to_regclass('public.repair_cost_entries') is not null
    or to_regclass('public.repair_operations') is not null
  then
    raise exception 'A Phase 3D-B object already exists; do not replay this migration over an unknown repair schema.';
  end if;
end;
$preflight$;

alter table public.inventory_balances
  add column reserved_repair_qty integer not null default 0;

alter table public.inventory_balances
  drop constraint inventory_balances_transfer_qty,
  add constraint inventory_balances_transfer_qty check (
    reserved_transfer_qty >= 0
    and reserved_custody_qty >= 0
    and reserved_repair_qty >= 0
    and available_qty + reserved_transfer_qty
      + reserved_custody_qty + reserved_repair_qty <= on_hand_qty
    and (valuation_status <> 'pending_fx'
      or (reserved_transfer_qty = 0
        and reserved_custody_qty = 0
        and reserved_repair_qty = 0))
  );

create table public.repair_jobs (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  branch_id uuid not null,
  serialized_inventory_id uuid not null,
  follow_up_from_job_id uuid,
  ticket_reference text not null,
  reported_fault text not null,
  intake_condition text not null,
  diagnosis text,
  technician_type text,
  technician_user_id uuid references auth.users (id) on delete restrict,
  external_technician_name text,
  external_technician_contact text,
  expected_completion_at timestamptz,
  status text not null default 'open',
  outcome_reason text,
  completion_evidence jsonb,
  completion_submitted_by uuid references auth.users (id) on delete restrict,
  completion_submitted_at timestamptz,
  completed_by uuid references auth.users (id) on delete restrict,
  completed_at timestamptz,
  cancellation_reason text,
  cancelled_by uuid references auth.users (id) on delete restrict,
  cancelled_at timestamptz,
  closure_reason text,
  closed_by uuid references auth.users (id) on delete restrict,
  closed_at timestamptz,
  warranty_evidence jsonb not null default '{}'::jsonb,
  device_claim_active boolean not null default true,
  version bigint not null default 1,
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_by uuid not null references auth.users (id) on delete restrict,
  updated_at timestamptz not null default clock_timestamp(),
  unique (shop_id, id),
  unique (shop_id, branch_id, id),
  unique (shop_id, ticket_reference),
  foreign key (shop_id, branch_id)
    references public.branches (shop_id, id) on delete restrict,
  -- Device identity is stable across later branch transfers. branch_id is the
  -- immutable source-branch snapshot for this repair job.
  foreign key (shop_id, serialized_inventory_id)
    references public.serialized_inventory (shop_id, id) on delete restrict,
  foreign key (shop_id, follow_up_from_job_id)
    references public.repair_jobs (shop_id, id) on delete restrict,
  constraint repair_jobs_ticket_check check (
    char_length(btrim(ticket_reference)) between 1 and 80
  ),
  constraint repair_jobs_fault_check check (
    char_length(btrim(reported_fault)) between 1 and 2000
    and char_length(btrim(intake_condition)) between 1 and 2000
  ),
  constraint repair_jobs_diagnosis_check check (
    diagnosis is null or char_length(btrim(diagnosis)) between 1 and 4000
  ),
  constraint repair_jobs_technician_check check (
    (technician_type is null and technician_user_id is null
      and external_technician_name is null and external_technician_contact is null)
    or (technician_type = 'internal' and technician_user_id is not null
      and external_technician_name is null and external_technician_contact is null)
    or (technician_type = 'external' and technician_user_id is null
      and external_technician_name is not null
      and char_length(btrim(external_technician_name)) between 1 and 200
      and (external_technician_contact is null
        or char_length(external_technician_contact) <= 300))
  ),
  constraint repair_jobs_status_check check (
    status in (
      'open', 'diagnosing', 'awaiting_approval', 'approved', 'in_progress',
      'awaiting_parts', 'returned_pending_inspection', 'completed',
      'unrepairable', 'cancelled', 'closed'
    )
  ),
  constraint repair_jobs_version_check check (version > 0),
  constraint repair_jobs_claim_state_check check (
    device_claim_active = (status not in ('completed', 'cancelled', 'closed'))
  ),
  constraint repair_jobs_evidence_check check (
    jsonb_typeof(warranty_evidence) = 'object'
    and (completion_evidence is null
      or (jsonb_typeof(completion_evidence) = 'object'
        and completion_evidence <> '{}'::jsonb))
    and (status <> 'unrepairable'
      or (outcome_reason is not null
        and char_length(btrim(outcome_reason)) between 1 and 1000))
    and (status <> 'completed'
      or (completion_evidence is not null and completed_by is not null
        and completed_at is not null))
    and (status <> 'cancelled'
      or (cancellation_reason is not null
        and cancelled_by is not null and cancelled_at is not null))
    and (status <> 'closed'
      or (closure_reason is not null and closed_by is not null and closed_at is not null))
  )
);

create unique index repair_jobs_active_device_uidx
  on public.repair_jobs (shop_id, serialized_inventory_id)
  where device_claim_active;
create unique index repair_jobs_one_follow_up_per_parent_uidx
  on public.repair_jobs (shop_id, follow_up_from_job_id)
  where follow_up_from_job_id is not null;
create index repair_jobs_branch_status_idx
  on public.repair_jobs (shop_id, branch_id, status, updated_at desc);
create index repair_jobs_device_history_idx
  on public.repair_jobs (shop_id, serialized_inventory_id, created_at desc);
create index repair_jobs_follow_up_idx
  on public.repair_jobs (shop_id, follow_up_from_job_id)
  where follow_up_from_job_id is not null;

create table public.repair_operations (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  branch_id uuid not null,
  actor_id uuid not null references auth.users (id) on delete restrict,
  idempotency_key text not null,
  operation_type text not null,
  request_payload jsonb not null,
  result_job_id uuid not null,
  result_event_id uuid not null,
  result_custody_case_id uuid,
  created_at timestamptz not null default clock_timestamp(),
  unique (shop_id, id),
  unique (shop_id, actor_id, idempotency_key),
  foreign key (shop_id, branch_id)
    references public.branches (shop_id, id) on delete restrict,
  foreign key (shop_id, result_job_id)
    references public.repair_jobs (shop_id, id)
    on delete restrict deferrable initially deferred,
  foreign key (shop_id, result_custody_case_id)
    references public.inventory_custody_cases (shop_id, id)
    on delete restrict deferrable initially deferred,
  constraint repair_operations_key_check check (
    char_length(btrim(idempotency_key)) between 8 and 120
  ),
  constraint repair_operations_payload_check check (
    jsonb_typeof(request_payload) = 'object'
  ),
  constraint repair_operations_type_check check (
    operation_type in (
      'create', 'assign_technician', 'diagnosis', 'estimate',
      'spend_approval', 'expense', 'progress', 'completion',
      'unrepairable', 'cancellation', 'closure', 'follow_up',
      'custody_request'
    )
  )
);
create index repair_operations_branch_created_idx
  on public.repair_operations (shop_id, branch_id, created_at desc);

create table public.repair_job_events (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  branch_id uuid not null,
  repair_job_id uuid not null,
  operation_id uuid,
  source_custody_event_id uuid,
  event_line_number integer not null default 0,
  event_type text not null,
  state_before text,
  state_after text,
  actor_id uuid not null references auth.users (id) on delete restrict,
  occurred_at timestamptz not null default clock_timestamp(),
  event_data jsonb not null default '{}'::jsonb,
  unique (shop_id, id),
  unique (shop_id, operation_id, event_line_number),
  unique (shop_id, source_custody_event_id, event_line_number),
  foreign key (shop_id, branch_id, repair_job_id)
    references public.repair_jobs (shop_id, branch_id, id) on delete restrict,
  foreign key (shop_id, operation_id)
    references public.repair_operations (shop_id, id)
    on delete restrict deferrable initially deferred,
  constraint repair_job_events_origin_check check (
    num_nonnulls(operation_id, source_custody_event_id) = 1
  ),
  constraint repair_job_events_line_check check (event_line_number >= 0),
  constraint repair_job_events_type_check check (
    event_type in (
      'created', 'reserved', 'diagnosis_updated', 'technician_assigned',
      'estimate_submitted', 'spending_approved', 'expense_recorded',
      'progress_updated', 'completion_evidence_submitted', 'completed',
      'unrepairable', 'cancelled', 'closed', 'follow_up_handoff',
      'custody_requested', 'custody_approved', 'custody_handed_over',
      'custody_returned', 'custody_cancelled', 'custody_incident_reported',
      'custody_incident_resolved', 'repair_hold_retained'
    )
  ),
  constraint repair_job_events_payload_check check (
    jsonb_typeof(event_data) = 'object'
  )
);
create index repair_job_events_history_idx
  on public.repair_job_events (shop_id, repair_job_id, occurred_at, event_line_number);

-- Supply the exact composite key required to bind a repair episode to the
-- same shop, branch, case, item, and serialized device in custody history.
alter table public.inventory_custody_items
  add constraint inventory_custody_items_repair_identity_uk
  unique (shop_id, branch_id, case_id, id, serialized_inventory_id);

alter table public.repair_operations
  add constraint repair_operations_result_event_fk
  foreign key (shop_id, result_event_id)
  references public.repair_job_events (shop_id, id)
  on delete restrict deferrable initially deferred;

create table public.repair_job_custody_episodes (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  branch_id uuid not null,
  repair_job_id uuid not null,
  custody_case_id uuid not null,
  custody_item_id uuid not null,
  serialized_inventory_id uuid not null,
  linked_by uuid not null references auth.users (id) on delete restrict,
  linked_at timestamptz not null default clock_timestamp(),
  unique (shop_id, id),
  unique (shop_id, custody_item_id),
  foreign key (shop_id, branch_id, repair_job_id)
    references public.repair_jobs (shop_id, branch_id, id) on delete restrict,
  foreign key (shop_id, branch_id, custody_case_id, custody_item_id, serialized_inventory_id)
    references public.inventory_custody_items
      (shop_id, branch_id, case_id, id, serialized_inventory_id)
    on delete restrict,
  foreign key (shop_id, serialized_inventory_id)
    references public.serialized_inventory (shop_id, id) on delete restrict
);
create index repair_job_custody_history_idx
  on public.repair_job_custody_episodes (shop_id, repair_job_id, linked_at desc);

create table public.repair_cost_entries (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  branch_id uuid not null,
  repair_job_id uuid not null,
  operation_id uuid not null,
  entry_type text not null,
  cost_bearer text not null,
  original_amount numeric(38, 8) not null,
  original_currency_code char(3) not null
    references public.currency_codes (code) on update restrict on delete restrict,
  shop_currency_code char(3) not null,
  fx_status text not null,
  converted_shop_amount numeric(38, 8),
  accepted_fx_rate numeric(38, 16),
  rate_direction text,
  rate_source text,
  rate_observed_at timestamptz,
  rate_accepted_at timestamptz,
  rate_snapshot_id uuid references public.exchange_rate_snapshots (id) on delete restrict,
  manual_rate_approved_by uuid references auth.users (id) on delete restrict,
  manual_rate_reason text,
  invoice_reference text,
  evidence jsonb not null default '{}'::jsonb,
  supersedes_entry_id uuid,
  correction_reason text,
  actor_id uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  unique (shop_id, id),
  unique (shop_id, operation_id),
  foreign key (shop_id, branch_id, repair_job_id)
    references public.repair_jobs (shop_id, branch_id, id) on delete restrict,
  foreign key (shop_id, operation_id)
    references public.repair_operations (shop_id, id) on delete restrict,
  foreign key (shop_id, shop_currency_code)
    references public.shop_settings (shop_id, operating_currency_code)
    on update restrict on delete restrict,
  foreign key (shop_id, supersedes_entry_id)
    references public.repair_cost_entries (shop_id, id) on delete restrict,
  constraint repair_cost_entries_type_check check (
    entry_type in ('estimate', 'approved_limit', 'actual', 'correction', 'warranty')
  ),
  constraint repair_cost_entries_bearer_check check (
    cost_bearer in (
      'shop', 'manufacturer_warranty', 'supplier_warranty',
      'technician_warranty', 'other'
    )
  ),
  constraint repair_cost_entries_amount_check check (
    original_amount > '-Infinity'::numeric
    and original_amount < 'Infinity'::numeric
    and (entry_type = 'correction' or original_amount >= 0)
  ),
  constraint repair_cost_entries_fx_check check (
    (fx_status = 'same_currency'
      and original_currency_code = shop_currency_code
      and converted_shop_amount = original_amount
      and accepted_fx_rate = 1
      and rate_direction = 'shop_currency_per_original_currency'
      and rate_source = 'same_currency'
      and rate_observed_at is not null and rate_accepted_at is not null
      and rate_snapshot_id is null and manual_rate_approved_by is null
      and manual_rate_reason is null)
    or (fx_status = 'accepted'
      and original_currency_code <> shop_currency_code
      and converted_shop_amount is not null
      and converted_shop_amount > '-Infinity'::numeric
      and accepted_fx_rate > 0 and accepted_fx_rate < 'Infinity'::numeric
      and rate_direction = 'shop_currency_per_original_currency'
      and rate_source is not null
      and rate_observed_at is not null and rate_accepted_at is not null
      and ((rate_snapshot_id is not null and manual_rate_approved_by is null
          and manual_rate_reason is null)
        or (rate_snapshot_id is null and manual_rate_approved_by is not null
          and manual_rate_reason is not null)))
    or (fx_status = 'pending'
      and original_currency_code <> shop_currency_code
      and converted_shop_amount is null and accepted_fx_rate is null
      and rate_direction is null and rate_source is null
      and rate_observed_at is null and rate_accepted_at is null
      and rate_snapshot_id is null and manual_rate_approved_by is null
      and manual_rate_reason is null)
  ),
  constraint repair_cost_entries_correction_check check (
    (entry_type = 'correction'
      and supersedes_entry_id is not null
      and correction_reason is not null
      and char_length(btrim(correction_reason)) between 1 and 1000)
    or (entry_type <> 'correction'
      and supersedes_entry_id is null and correction_reason is null)
  ),
  constraint repair_cost_entries_evidence_check check (
    jsonb_typeof(evidence) = 'object'
    and (invoice_reference is null or char_length(invoice_reference) <= 200)
  )
);
create index repair_cost_entries_job_history_idx
  on public.repair_cost_entries (shop_id, repair_job_id, created_at, id);
create unique index repair_cost_entries_one_correction_per_entry_uidx
  on public.repair_cost_entries (shop_id, supersedes_entry_id)
  where supersedes_entry_id is not null;

create or replace function private.is_valid_repair_operational_evidence(
  p_evidence jsonb
)
returns boolean
language sql
immutable
parallel safe
set search_path = ''
as $function$
  select p_evidence is not null
    and jsonb_typeof(p_evidence) = 'object'
    and p_evidence <> '{}'::jsonb
    and not exists (
      select 1
      from jsonb_object_keys(case
        when jsonb_typeof(p_evidence) = 'object' then p_evidence
        else '{}'::jsonb
      end) as evidence_key(key_name)
      where evidence_key.key_name not in (
        'work_performed', 'inspection_result', 'functional_testing',
        'technician_notes', 'device_condition'
      )
    )
    and not exists (
      select 1
      from jsonb_each(case
        when jsonb_typeof(p_evidence) = 'object' then p_evidence
        else '{}'::jsonb
      end) as evidence_entry(key_name, value)
      where jsonb_typeof(evidence_entry.value) <> 'string'
        or char_length(btrim(evidence_entry.value #>> '{}')) not between 1
          and case evidence_entry.key_name
            when 'work_performed' then 4000
            else 2000
          end
    );
$function$;

alter table public.repair_jobs
  add constraint repair_jobs_operational_evidence_check check (
    completion_evidence is null
    or private.is_valid_repair_operational_evidence(completion_evidence)
  );

create or replace function private.repair_gross_authorization_consumed(
  p_shop_id uuid,
  p_repair_job_id uuid
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(sum(case
    when entry.entry_type = 'actual' then entry.converted_shop_amount
    when entry.entry_type = 'correction'
      then greatest(entry.converted_shop_amount, 0::numeric)
    else 0::numeric
  end), 0::numeric)
  from public.repair_cost_entries as entry
  where entry.shop_id = p_shop_id
    and entry.repair_job_id = p_repair_job_id
    and entry.cost_bearer = 'shop'
    and entry.entry_type in ('actual', 'correction')
    and entry.converted_shop_amount is not null;
$function$;

revoke all on function private.is_valid_repair_operational_evidence(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.repair_gross_authorization_consumed(uuid, uuid)
  from public, anon, authenticated, service_role;

-- Extend the Phase 3D-A state guard only for transitions backed by a repair
-- episode and the corresponding repair reservation. Ordinary transfer and
-- custody paths retain their original checks.
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
      and old.availability_status = 'available' and new.availability_status = 'available'
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
      and old.availability_status = 'available' and new.availability_status = 'reserved'
      and new.branch_id = old.branch_id and new.transfer_state is null
      and old.transfer_state is null
      and custody_item_row.state = 'approved' and custody_item_row.claim_active
    then
      return new;
    end if;

    if old.custody_state = 'none' and new.custody_state = 'approved'
      and old.availability_status = 'reserved' and new.availability_status = 'reserved'
      and new.branch_id = old.branch_id and new.transfer_state is null
      and old.transfer_state is null
      and custody_item_row.state = 'approved' and custody_item_row.claim_active
      and exists (
        select 1
        from public.repair_job_custody_episodes as episode
        join public.repair_jobs as job
          on job.shop_id = episode.shop_id and job.id = episode.repair_job_id
        where episode.shop_id = new.shop_id
          and episode.custody_item_id = custody_item_row.id
          and episode.serialized_inventory_id = new.id
          and job.serialized_inventory_id = new.id
          and job.device_claim_active
      )
    then
      return new;
    end if;

    if old.custody_state = 'approved' and new.custody_state = 'handed_over'
      and old.availability_status = 'reserved' and new.availability_status = 'reserved'
      and new.branch_id = old.branch_id and new.transfer_state is null
      and old.transfer_state is null
      and custody_item_row.state = 'handed_over' and custody_item_row.claim_active
    then
      return new;
    end if;

    if old.custody_state = 'handed_over'
      and new.custody_state in ('none', 'returned_quarantine')
      and old.availability_status = 'reserved'
      and new.availability_status in ('available', 'reserved')
      and new.branch_id = old.branch_id and new.transfer_state is null
      and old.transfer_state is null
      and custody_item_row.state = 'returned' and not custody_item_row.claim_active
    then
      select exists (
        select 1 from public.inventory_custody_incidents as incident
        where incident.shop_id = custody_item_row.shop_id
          and incident.item_id = custody_item_row.id and incident.status = 'open'
      ) into open_custody_incident;
      if (new.custody_state = 'returned_quarantine'
            and open_custody_incident and new.availability_status = 'reserved')
        or (new.custody_state = 'none'
            and not open_custody_incident and new.availability_status = 'available')
      then
        return new;
      end if;
    end if;

    if old.custody_state = 'returned_quarantine'
      and new.custody_state = 'none'
      and old.availability_status = 'reserved' and new.availability_status = 'available'
      and new.branch_id = old.branch_id and new.transfer_state is null
      and custody_item_row.state = 'returned' and not custody_item_row.claim_active
      and not exists (
        select 1 from public.inventory_custody_incidents as incident
        where incident.shop_id = custody_item_row.shop_id
          and incident.item_id = custody_item_row.id and incident.status = 'open'
      )
    then
      return new;
    end if;

    if old.custody_state = 'approved' and new.custody_state = 'none'
      and old.availability_status = 'reserved' and new.availability_status = 'reserved'
      and new.branch_id = old.branch_id and new.transfer_state is null
      and old.transfer_state is null
      and custody_item_row.state = 'cancelled' and not custody_item_row.claim_active
      and exists (
        select 1
        from public.repair_job_custody_episodes as episode
        join public.repair_jobs as job
          on job.shop_id = episode.shop_id and job.id = episode.repair_job_id
        where episode.shop_id = new.shop_id
          and episode.custody_item_id = custody_item_row.id
          and episode.serialized_inventory_id = new.id
          and job.serialized_inventory_id = new.id
          and job.device_claim_active
      )
    then
      return new;
    end if;

    if old.custody_state in ('requested', 'approved')
      and new.custody_state = 'none'
      and new.availability_status = 'available'
      and new.branch_id = old.branch_id and new.transfer_state is null
      and old.transfer_state is null
      and custody_item_row.state = 'cancelled' and not custody_item_row.claim_active
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
  where line.shop_id = new.shop_id and line.serialized_inventory_id = new.id
    and transfer.status in ('requested', 'approved', 'dispatched', 'partially_received')
  order by transfer.requested_at desc, line.id
  limit 1;
  if found then
    select transfer.* into transfer_row
    from public.inventory_transfers as transfer
    where transfer.shop_id = line_row.shop_id and transfer.id = line_row.transfer_id;
  end if;

  if old.transfer_state = 'in_transit' then
    if found and old.custody_state = 'none' and new.custody_state = 'none'
      and new.branch_id = transfer_row.destination_branch_id
      and new.availability_status = 'available' and new.transfer_state is null
      and line_row.dispatched_qty = 1 and line_row.received_qty = 1
      and not line_row.claim_active
    then return new; end if;
    raise exception 'An in-transit device can only become available at its transfer destination after recorded receipt.'
      using errcode = '42501';
  end if;

  if new.transfer_state = 'in_transit' then
    if found and old.custody_state = 'none' and new.custody_state = 'none'
      and old.availability_status = 'reserved' and new.availability_status = 'reserved'
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
    -- Repair creation inserts the active job and moves its aggregate balance
    -- before reserving the serialized row. Permit only that initial, version-1
    -- claim for the same branch/device and actor.
    if old.custody_state = 'none' and new.custody_state = 'none'
      and old.availability_status = 'available'
      and new.branch_id = old.branch_id
      and old.transfer_state is null and new.transfer_state is null
      and new.valuation_status in ('known_cost', 'unknown_cost')
      and exists (
        select 1 from public.repair_jobs as job
        where job.shop_id = new.shop_id
          and job.serialized_inventory_id = new.id
          and job.branch_id = new.branch_id
          and job.status = 'open' and job.version = 1
          and job.device_claim_active
          and job.created_by = new.updated_by
      )
      and exists (
        select 1 from public.inventory_balances as balance
        where balance.shop_id = new.shop_id and balance.branch_id = new.branch_id
          and balance.variant_id = new.variant_id
          and balance.valuation_status = new.valuation_status
          and balance.reserved_repair_qty > 0
      )
    then return new; end if;

    if old.custody_state = 'none' and new.custody_state = 'none'
      and old.availability_status = 'available'
      and new.branch_id = old.branch_id
      and new.transfer_state is null and old.transfer_state is null
      and exists (
        select 1
        from public.repair_jobs as job
        join public.repair_job_custody_episodes as episode
          on episode.shop_id = job.shop_id and episode.repair_job_id = job.id
        join public.inventory_custody_items as item
          on item.shop_id = episode.shop_id and item.id = episode.custody_item_id
        where job.shop_id = new.shop_id and job.serialized_inventory_id = new.id
          and job.branch_id = new.branch_id and job.device_claim_active
          and episode.serialized_inventory_id = new.id
          and item.state = 'returned' and not item.claim_active
          and not exists (
            select 1 from public.inventory_custody_incidents as incident
            where incident.shop_id = item.shop_id and incident.item_id = item.id
              and incident.status = 'open'
          )
      )
      and exists (
        select 1 from public.inventory_balances as balance
        where balance.shop_id = new.shop_id and balance.branch_id = new.branch_id
          and balance.variant_id = new.variant_id
          and balance.valuation_status = new.valuation_status
          and balance.reserved_repair_qty > 0
      )
    then return new; end if;

    if found and old.custody_state = 'none' and new.custody_state = 'none'
      and old.availability_status = 'available'
      and old.transfer_state is null and new.transfer_state is null
      and new.branch_id = transfer_row.source_branch_id
      and transfer_row.status = 'requested' and line_row.claim_active
      and line_row.approved_qty = 1 and line_row.dispatched_qty = 0
    then return new; end if;
    raise exception 'A serialized device may be reserved only by an authorized transfer, custody approval, or active repair return.'
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

  if old.availability_status = 'reserved'
    and new.availability_status = 'available'
    and old.custody_state = 'none' and new.custody_state = 'none'
    and old.transfer_state is null and new.transfer_state is null
    and new.branch_id = old.branch_id
    and not exists (
      select 1 from public.repair_jobs as active_job
      where active_job.shop_id = new.shop_id
        and active_job.serialized_inventory_id = new.id
        and active_job.device_claim_active
    )
    and exists (
      select 1 from public.repair_jobs as terminal_job
      where terminal_job.shop_id = new.shop_id
        and terminal_job.serialized_inventory_id = new.id
        and terminal_job.status in ('completed', 'cancelled', 'closed')
        and not terminal_job.device_claim_active
    )
    and not exists (
      select 1 from public.inventory_custody_items as custody_item
      where custody_item.shop_id = new.shop_id
        and custody_item.serialized_inventory_id = new.id
        and custody_item.claim_active
    )
    and exists (
      select 1 from public.inventory_balances as balance
      where balance.shop_id = new.shop_id and balance.branch_id = new.branch_id
        and balance.variant_id = new.variant_id
        and balance.valuation_status = new.valuation_status
        and balance.available_qty > 0
    )
  then
    return new;
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
    raise exception 'A reserved serialized device requires an authorized transfer, custody, or repair transition.'
      using errcode = '42501';
  end if;
  return new;
end;
$function$;

revoke all on function private.guard_serialized_transfer_state_update()
  from public, anon, authenticated, service_role;

create or replace function private.assert_repair_access(
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
    or p_action not in ('write', 'approve', 'admin')
  then
    raise exception 'Repair authorization parameters are invalid.'
      using errcode = '42501';
  end if;
  perform 1 from public.branches as branch
  where branch.shop_id = p_shop_id and branch.id = p_branch_id
    and branch.is_active
  for share;
  if not found then
    raise exception 'The repair branch is inactive or belongs to another shop.'
      using errcode = '42501';
  end if;
  select membership.role into role_value
  from public.shop_memberships as membership
  where membership.shop_id = p_shop_id
    and membership.user_id = actor_value and membership.status = 'active'
  for share;
  if not found then
    raise exception 'An active shop membership is required for repair operations.'
      using errcode = '42501';
  end if;
  if p_action in ('approve', 'admin') then
    if role_value not in ('owner', 'manager') then
      raise exception 'Only an Owner or Manager may approve or administer repair jobs.'
        using errcode = '42501';
    end if;
  elsif role_value not in ('owner', 'manager', 'inventory_staff') then
    raise exception 'This shop role cannot mutate repair jobs.'
      using errcode = '42501';
  end if;
  if role_value in ('manager', 'inventory_staff') then
    perform 1 from public.branch_memberships as assignment
    where assignment.shop_id = p_shop_id and assignment.branch_id = p_branch_id
      and assignment.user_id = actor_value
    for share;
    if not found then
      raise exception 'The member is not assigned to this active repair branch.'
        using errcode = '42501';
    end if;
  end if;
  actor_id := actor_value;
  actor_role := role_value;
  return next;
end;
$function$;

create or replace function private.claim_repair_operation(
  p_shop_id uuid,
  p_branch_id uuid,
  p_actor_id uuid,
  p_idempotency_key text,
  p_operation_type text,
  p_request_payload jsonb,
  p_result_job_id uuid,
  p_result_event_id uuid,
  p_result_custody_case_id uuid default null
)
returns table (
  operation_id uuid,
  replayed boolean,
  result_job_id uuid,
  result_event_id uuid,
  result_custody_case_id uuid
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  inserted_id uuid;
  existing_row public.repair_operations%rowtype;
begin
  if p_actor_id is null or p_idempotency_key is null
    or char_length(btrim(p_idempotency_key)) not between 8 and 120
    or p_request_payload is null
    or jsonb_typeof(p_request_payload) is distinct from 'object'
    or p_result_job_id is null or p_result_event_id is null
  then
    raise exception 'A valid repair idempotency key, payload, and result are required.'
      using errcode = '22023';
  end if;
  insert into public.repair_operations (
    shop_id, branch_id, actor_id, idempotency_key, operation_type,
    request_payload, result_job_id, result_event_id, result_custody_case_id
  ) values (
    p_shop_id, p_branch_id, p_actor_id, btrim(p_idempotency_key), p_operation_type,
    p_request_payload, p_result_job_id, p_result_event_id, p_result_custody_case_id
  )
  on conflict (shop_id, actor_id, idempotency_key) do nothing
  returning id into inserted_id;
  if inserted_id is not null then
    operation_id := inserted_id;
    replayed := false;
    result_job_id := p_result_job_id;
    result_event_id := p_result_event_id;
    result_custody_case_id := p_result_custody_case_id;
    return next;
    return;
  end if;
  select operation.* into existing_row
  from public.repair_operations as operation
  where operation.shop_id = p_shop_id and operation.actor_id = p_actor_id
    and operation.idempotency_key = btrim(p_idempotency_key)
  for update;
  if not found then
    raise exception 'Repair operation could not be resolved after an idempotency conflict.'
      using errcode = '40001';
  end if;
  if existing_row.operation_type is distinct from p_operation_type
    or existing_row.request_payload is distinct from p_request_payload
    or existing_row.branch_id is distinct from p_branch_id
  then
    raise exception 'This repair idempotency key was already used for a different request.'
      using errcode = '23505';
  end if;
  operation_id := existing_row.id;
  replayed := true;
  result_job_id := existing_row.result_job_id;
  result_event_id := existing_row.result_event_id;
  result_custody_case_id := existing_row.result_custody_case_id;
  return next;
end;
$function$;

create or replace function private.reject_repair_history_mutation()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  raise exception 'Repair operations and history are immutable.'
    using errcode = '42501';
end;
$function$;

create trigger repair_operations_immutable
  before update or delete on public.repair_operations
  for each row execute function private.reject_repair_history_mutation();
create trigger repair_operations_no_truncate
  before truncate on public.repair_operations
  for each statement execute function private.reject_repair_history_mutation();
create trigger repair_job_events_immutable
  before update or delete on public.repair_job_events
  for each row execute function private.reject_repair_history_mutation();
create trigger repair_job_events_no_truncate
  before truncate on public.repair_job_events
  for each statement execute function private.reject_repair_history_mutation();
create trigger repair_job_custody_episodes_immutable
  before update or delete on public.repair_job_custody_episodes
  for each row execute function private.reject_repair_history_mutation();
create trigger repair_job_custody_episodes_no_truncate
  before truncate on public.repair_job_custody_episodes
  for each statement execute function private.reject_repair_history_mutation();
create trigger repair_cost_entries_immutable
  before update or delete on public.repair_cost_entries
  for each row execute function private.reject_repair_history_mutation();
create trigger repair_cost_entries_no_truncate
  before truncate on public.repair_cost_entries
  for each statement execute function private.reject_repair_history_mutation();

create or replace function private.guard_repair_job_update()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.id is distinct from old.id
    or new.shop_id is distinct from old.shop_id
    or new.branch_id is distinct from old.branch_id
    or new.serialized_inventory_id is distinct from old.serialized_inventory_id
    or new.follow_up_from_job_id is distinct from old.follow_up_from_job_id
    or new.ticket_reference is distinct from old.ticket_reference
    or new.reported_fault is distinct from old.reported_fault
    or new.intake_condition is distinct from old.intake_condition
    or new.warranty_evidence is distinct from old.warranty_evidence
    or new.created_by is distinct from old.created_by
    or new.created_at is distinct from old.created_at
    or new.version <> old.version + 1
    or new.updated_by is null or new.updated_at <= old.updated_at
  then
    raise exception 'Repair job identity and intake evidence are immutable.'
      using errcode = '42501';
  end if;
  if old.status = 'closed'
    or (old.status in ('completed', 'cancelled') and new.status <> 'closed')
  then
    raise exception 'Completed, cancelled, and closed repair jobs are terminal.'
      using errcode = '23514';
  end if;
  if new.status is distinct from old.status and not (
    (old.status = 'open' and new.status in ('diagnosing', 'awaiting_approval', 'cancelled'))
    or (old.status = 'diagnosing'
      and new.status in ('awaiting_approval', 'in_progress', 'awaiting_parts', 'unrepairable', 'cancelled'))
    or (old.status = 'awaiting_approval'
      and new.status in ('approved', 'diagnosing', 'cancelled'))
    or (old.status = 'approved'
      and new.status in ('in_progress', 'awaiting_parts', 'awaiting_approval', 'cancelled'))
    or (old.status = 'in_progress'
      and new.status in ('awaiting_parts', 'awaiting_approval', 'returned_pending_inspection', 'unrepairable', 'cancelled'))
    or (old.status = 'awaiting_parts'
      and new.status in ('in_progress', 'awaiting_approval', 'returned_pending_inspection', 'unrepairable', 'cancelled'))
    or (old.status in ('completed', 'cancelled') and new.status = 'closed')
    or (old.status = 'returned_pending_inspection'
      and new.status in ('diagnosing', 'awaiting_approval', 'completed', 'unrepairable'))
    or (old.status = 'unrepairable' and new.status = 'closed')
  ) then
    raise exception 'The requested repair status transition is invalid.'
      using errcode = '23514';
  end if;
  if new.device_claim_active is distinct from
    (new.status not in ('completed', 'cancelled', 'closed'))
  then
    raise exception 'The repair device claim must match the workflow state.'
      using errcode = '23514';
  end if;
  return new;
end;
$function$;
create trigger repair_jobs_state_guard
  before update on public.repair_jobs
  for each row execute function private.guard_repair_job_update();

create or replace function private.require_repair_follow_up_link()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.status = 'closed' and new.outcome_reason is not null
    and new.device_claim_active is false
    and not exists (
      select 1 from public.repair_jobs as next_job
      where next_job.shop_id = new.shop_id
        and next_job.follow_up_from_job_id = new.id
    )
  then
    raise exception 'An unrepairable repair hold can close only with an authorized follow-up job.'
      using errcode = '23514';
  end if;
  return null;
end;
$function$;
create constraint trigger repair_jobs_follow_up_deferred
  after update on public.repair_jobs
  deferrable initially deferred
  for each row execute function private.require_repair_follow_up_link();

create or replace function private.validate_repair_cost_entry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  original_minor smallint;
  shop_minor smallint;
  settings_currency char(3);
  decision_time timestamptz := clock_timestamp();
  snapshot_row public.exchange_rate_snapshots%rowtype;
begin
  select currency.minor_units into original_minor
  from public.currency_codes as currency
  where currency.code = new.original_currency_code and currency.enabled;
  select currency.minor_units, settings.operating_currency_code
    into shop_minor, settings_currency
  from public.shop_settings as settings
  join public.currency_codes as currency
    on currency.code = settings.operating_currency_code and currency.enabled
  where settings.shop_id = new.shop_id;
  if original_minor is null or shop_minor is null
    or settings_currency is distinct from new.shop_currency_code
  then
    raise exception 'Repair cost currencies are disabled or do not match shop settings.'
      using errcode = '23514';
  end if;
  if abs(new.original_amount * power(10::numeric, original_minor))
    <> trunc(abs(new.original_amount * power(10::numeric, original_minor)))
  then
    raise exception 'Repair amount exceeds the original currency minor-unit precision.'
      using errcode = '22023';
  end if;
  if new.fx_status = 'same_currency' then
    if abs(new.converted_shop_amount * power(10::numeric, shop_minor))
      <> trunc(abs(new.converted_shop_amount * power(10::numeric, shop_minor)))
    then
      raise exception 'Repair amount exceeds the shop currency minor-unit precision.'
        using errcode = '22023';
    end if;
  elsif new.fx_status = 'accepted' then
    if abs(new.converted_shop_amount * power(10::numeric, shop_minor))
      <> trunc(abs(new.converted_shop_amount * power(10::numeric, shop_minor)))
    then
      raise exception 'Converted repair amount exceeds the shop currency minor-unit precision.'
        using errcode = '22023';
    end if;
    if new.rate_accepted_at > decision_time
      or new.rate_observed_at > decision_time
      or new.rate_direction <> 'shop_currency_per_original_currency'
    then
      raise exception 'Repair FX evidence timestamps or direction are invalid.'
        using errcode = '23514';
    end if;
    if new.rate_snapshot_id is not null then
      select snapshot.* into snapshot_row
      from public.exchange_rate_snapshots as snapshot
      where snapshot.id = new.rate_snapshot_id;
      if not found
        or snapshot_row.from_currency_code is distinct from new.original_currency_code
        or snapshot_row.to_currency_code is distinct from new.shop_currency_code
        or snapshot_row.rate_to_currency is distinct from new.accepted_fx_rate
        or snapshot_row.rate_source is distinct from new.rate_source
        or snapshot_row.observed_at is distinct from new.rate_observed_at
        or snapshot_row.valid_until <= decision_time
        or snapshot_row.fetched_at > decision_time
      then
        raise exception 'The selected exchange-rate snapshot is invalid or expired.'
          using errcode = '23514';
      end if;
    elsif new.manual_rate_approved_by is null
      or char_length(btrim(coalesce(new.manual_rate_reason, ''))) < 10
    then
      raise exception 'Manual repair FX requires an approver and a reason.'
        using errcode = '23514';
    end if;
    if new.converted_shop_amount is distinct from
      round(new.original_amount * new.accepted_fx_rate, shop_minor)
    then
      raise exception 'Converted repair amount does not reconcile to the accepted rate.'
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$function$;
create trigger repair_cost_entries_validate
  before insert on public.repair_cost_entries
  for each row execute function private.validate_repair_cost_entry();

create or replace function private.validate_repair_custody_link()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  job_row public.repair_jobs%rowtype;
  item_row public.inventory_custody_items%rowtype;
begin
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = new.shop_id and job.id = new.repair_job_id;
  select item.* into item_row from public.inventory_custody_items as item
  where item.shop_id = new.shop_id and item.branch_id = new.branch_id
    and item.case_id = new.custody_case_id and item.id = new.custody_item_id
    and item.serialized_inventory_id = new.serialized_inventory_id;
  if not found or job_row.id is null or not job_row.device_claim_active
    or job_row.serialized_inventory_id is distinct from new.serialized_inventory_id
    or job_row.branch_id is distinct from new.branch_id
    or item_row.state <> 'requested' or not item_row.claim_active
  then
    raise exception 'Repair custody episode must reference the same active shop device and an authorized requested custody item.'
      using errcode = '23514';
  end if;
  return new;
end;
$function$;
create trigger repair_job_custody_episodes_validate
  before insert on public.repair_job_custody_episodes
  for each row execute function private.validate_repair_custody_link();

create or replace function private.validate_repair_custody_event_source()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.source_custody_event_id is not null and not exists (
    select 1 from public.inventory_custody_events as source_event
    where source_event.shop_id = new.shop_id
      and source_event.branch_id = new.branch_id
      and source_event.id = new.source_custody_event_id
  ) then
    raise exception 'Repair custody history must reference an existing event in the same shop and branch.'
      using errcode = '23503';
  end if;
  return new;
end;
$function$;
create trigger repair_job_events_custody_source_validate
  before insert on public.repair_job_events
  for each row execute function private.validate_repair_custody_event_source();

create or replace function private.mirror_repair_custody_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  episode_row record;
  mapped_type text;
begin
  mapped_type := case new.event_type
    when 'requested' then 'custody_requested'
    when 'item_requested' then 'custody_requested'
    when 'approved' then 'custody_approved'
    when 'item_approved' then 'custody_approved'
    when 'handed_over' then 'custody_handed_over'
    when 'item_handed_over' then 'custody_handed_over'
    when 'item_returned' then 'custody_returned'
    when 'returned' then 'custody_returned'
    when 'cancelled' then 'custody_cancelled'
    when 'item_cancelled' then 'custody_cancelled'
    when 'missing_reported' then 'custody_incident_reported'
    when 'damage_reported' then 'custody_incident_reported'
    when 'dispute_reported' then 'custody_incident_reported'
    when 'incident_reviewed' then 'custody_incident_resolved'
    when 'incident_resolved' then 'custody_incident_resolved'
    else null
  end;
  if mapped_type is null then return new; end if;
  for episode_row in
    select episode.repair_job_id
    from public.repair_job_custody_episodes as episode
    where episode.shop_id = new.shop_id
      and episode.custody_case_id = new.case_id
      and (new.item_id is null or episode.custody_item_id = new.item_id)
  loop
    insert into public.repair_job_events (
      shop_id, branch_id, repair_job_id, source_custody_event_id,
      event_line_number, event_type, state_before, state_after, actor_id, event_data
    ) values (
      new.shop_id, new.branch_id, episode_row.repair_job_id, new.id,
      0, mapped_type, new.prior_state, new.new_state, new.actor_id,
      jsonb_build_object(
        'custody_event_id', new.id, 'custody_operation_id', new.operation_id,
        'custody_item_id', new.item_id, 'incident_id', new.incident_id,
        'source_event_type', new.event_type, 'evidence', new.event_data
      )
    );
  end loop;
  return new;
end;
$function$;
create trigger inventory_custody_events_mirror_repair
  after insert on public.inventory_custody_events
  for each row execute function private.mirror_repair_custody_event();

create or replace function private.guard_repair_branch_deactivation()
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
        and transfer.status in ('requested', 'approved', 'dispatched', 'partially_received')
    )
    or exists (
      select 1 from public.serialized_inventory as device
      where device.shop_id = old.shop_id and device.branch_id = old.id
        and device.custody_state in (
          'requested', 'approved', 'handed_over', 'returned_quarantine'
        )
    )
    or exists (
      select 1 from public.repair_jobs as job
      where job.shop_id = old.shop_id and job.branch_id = old.id
        and job.device_claim_active
    )
  ) then
    raise exception 'A branch with an open transfer, custody claim, or repair hold cannot be deactivated.'
      using errcode = '23514';
  end if;
  return new;
end;
$function$;
create trigger branches_guard_repair_deactivation
  before update of is_active on public.branches
  for each row execute function private.guard_repair_branch_deactivation();

create or replace function private.record_repair_event(
  p_event_id uuid,
  p_shop_id uuid,
  p_branch_id uuid,
  p_job_id uuid,
  p_operation_id uuid,
  p_event_line_number integer,
  p_event_type text,
  p_state_before text,
  p_state_after text,
  p_actor_id uuid,
  p_event_data jsonb
)
returns uuid
language sql
security definer
set search_path = ''
as $function$
  insert into public.repair_job_events (
    id, shop_id, branch_id, repair_job_id, operation_id, event_line_number,
    event_type, state_before, state_after, actor_id, event_data
  ) values (
    p_event_id, p_shop_id, p_branch_id, p_job_id, p_operation_id, p_event_line_number,
    p_event_type, p_state_before, p_state_after, p_actor_id,
    coalesce(p_event_data, '{}'::jsonb)
  )
  returning id;
$function$;

create or replace function private.insert_repair_cost_entry(
  p_shop_id uuid,
  p_branch_id uuid,
  p_job_id uuid,
  p_operation_id uuid,
  p_actor_id uuid,
  p_entry_type text,
  p_amount numeric,
  p_currency char(3),
  p_cost_bearer text,
  p_evidence jsonb,
  p_invoice_reference text,
  p_rate_snapshot_id uuid,
  p_manual_rate numeric,
  p_manual_rate_source text,
  p_manual_rate_observed_at timestamptz,
  p_manual_rate_reason text,
  p_supersedes_entry_id uuid,
  p_correction_reason text
)
returns table (entry_id uuid, converted_amount numeric, fx_status text)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_role_value public.shop_role;
  shop_currency char(3);
  rate_value numeric(38, 16);
  source_value text;
  observed_value timestamptz;
  accepted_at_value timestamptz := clock_timestamp();
  snapshot_value uuid;
  manual_approver_value uuid;
  manual_reason_value text;
  converted_value numeric(38, 8);
  fx_status_value text;
  original_minor smallint;
  currency_minor smallint;
  snapshot_row public.exchange_rate_snapshots%rowtype;
begin
  select settings.operating_currency_code into shop_currency
  from public.shop_settings as settings
  where settings.shop_id = p_shop_id
  for share;
  if not found then
    raise exception 'The shop operating currency is not configured.'
      using errcode = '23514';
  end if;
  if p_amount is null or p_amount <= '-Infinity'::numeric
    or p_amount >= 'Infinity'::numeric
    or p_currency is null or p_cost_bearer is null
    or p_cost_bearer not in (
      'shop', 'manufacturer_warranty', 'supplier_warranty',
      'technician_warranty', 'other'
    )
  then
    raise exception 'Repair cost amount, currency, or cost bearer is invalid.'
      using errcode = '22023';
  end if;
  select currency.minor_units into original_minor
  from public.currency_codes as currency
  where currency.code = p_currency and currency.enabled;
  if original_minor is null then
    raise exception 'The original repair currency is disabled or unknown.'
      using errcode = '23514';
  end if;
  if abs(p_amount * power(10::numeric, original_minor))
    <> trunc(abs(p_amount * power(10::numeric, original_minor)))
  then
    raise exception 'Repair amount exceeds the original currency minor-unit precision.'
      using errcode = '22023';
  end if;
  if p_currency = shop_currency then
    if p_rate_snapshot_id is not null or p_manual_rate is not null then
      raise exception 'Same-currency repair evidence must not include an exchange rate.'
        using errcode = '22023';
    end if;
    rate_value := 1;
    source_value := 'same_currency';
    observed_value := accepted_at_value;
    converted_value := p_amount::numeric(38, 8);
    fx_status_value := 'same_currency';
  elsif p_rate_snapshot_id is not null then
    if p_manual_rate is not null then
      raise exception 'Choose either a system snapshot or a manual repair FX rate.'
        using errcode = '22023';
    end if;
    select snapshot.* into snapshot_row
    from public.exchange_rate_snapshots as snapshot
    where snapshot.id = p_rate_snapshot_id
    for share;
    if not found or snapshot_row.from_currency_code is distinct from p_currency
      or snapshot_row.to_currency_code is distinct from shop_currency
      or snapshot_row.valid_until <= accepted_at_value
      or snapshot_row.observed_at > accepted_at_value
      or snapshot_row.fetched_at > accepted_at_value
    then
      raise exception 'A valid, current shop-currency exchange-rate snapshot is required.'
        using errcode = '23514';
    end if;
    rate_value := snapshot_row.rate_to_currency;
    source_value := snapshot_row.rate_source;
    observed_value := snapshot_row.observed_at;
    snapshot_value := snapshot_row.id;
    fx_status_value := 'accepted';
  elsif p_manual_rate is not null then
    select membership.role into actor_role_value
    from public.shop_memberships as membership
    where membership.shop_id = p_shop_id and membership.user_id = p_actor_id
      and membership.status = 'active'
    for share;
    if actor_role_value not in ('owner', 'manager')
      or p_manual_rate <= 0 or p_manual_rate >= 'Infinity'::numeric
      or p_manual_rate <> round(p_manual_rate, 16)
      or char_length(btrim(coalesce(p_manual_rate_source, ''))) not between 1 and 120
      or p_manual_rate_observed_at is null
      or p_manual_rate_observed_at > accepted_at_value
      or char_length(btrim(coalesce(p_manual_rate_reason, ''))) not between 10 and 1000
    then
      raise exception 'Manual repair FX requires an active Owner or Manager, valid rate evidence, and a reason.'
        using errcode = '42501';
    end if;
    rate_value := p_manual_rate;
    source_value := btrim(p_manual_rate_source);
    observed_value := p_manual_rate_observed_at;
    manual_approver_value := p_actor_id;
    manual_reason_value := btrim(p_manual_rate_reason);
    fx_status_value := 'accepted';
  elsif p_entry_type in ('estimate', 'warranty') then
    fx_status_value := 'pending';
  else
    raise exception 'A current accepted FX rate is required before approval or actual expense recording.'
      using errcode = '23514';
  end if;

  select currency.minor_units into currency_minor
  from public.currency_codes as currency
  where currency.code = shop_currency and currency.enabled;
  if fx_status_value = 'accepted' then
    converted_value := round(p_amount * rate_value, currency_minor)::numeric(38, 8);
  end if;

  return query
  insert into public.repair_cost_entries as inserted_entry (
    shop_id, branch_id, repair_job_id, operation_id, entry_type, cost_bearer,
    original_amount, original_currency_code, shop_currency_code, fx_status,
    converted_shop_amount, accepted_fx_rate, rate_direction, rate_source,
    rate_observed_at, rate_accepted_at, rate_snapshot_id,
    manual_rate_approved_by, manual_rate_reason, invoice_reference,
    evidence, supersedes_entry_id, correction_reason, actor_id
  ) values (
    p_shop_id, p_branch_id, p_job_id, p_operation_id, p_entry_type, p_cost_bearer,
    p_amount, p_currency, shop_currency, fx_status_value,
    converted_value, rate_value,
    case when fx_status_value = 'pending' then null
      else 'shop_currency_per_original_currency' end,
    source_value, observed_value,
    case when fx_status_value = 'pending' then null else accepted_at_value end,
    snapshot_value, manual_approver_value, manual_reason_value,
    nullif(btrim(p_invoice_reference), ''), coalesce(p_evidence, '{}'::jsonb),
    p_supersedes_entry_id, p_correction_reason, p_actor_id
  )
  returning inserted_entry.id,
    inserted_entry.converted_shop_amount,
    inserted_entry.fx_status;
end;
$function$;

create or replace function private.release_repair_reservation(
  p_shop_id uuid,
  p_branch_id uuid,
  p_device_id uuid,
  p_actor_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  device_row public.serialized_inventory%rowtype;
  balance_row public.inventory_balances%rowtype;
begin
  select device.* into device_row
  from public.serialized_inventory as device
  where device.shop_id = p_shop_id and device.branch_id = p_branch_id
    and device.id = p_device_id and device.availability_status = 'reserved'
    and device.transfer_state is null and device.custody_state = 'none'
  for update;
  if not found then
    raise exception 'The repair device is not physically available at its source branch.'
      using errcode = '23514';
  end if;
  if exists (
    select 1 from public.inventory_custody_items as item
    where item.shop_id = p_shop_id and item.serialized_inventory_id = p_device_id
      and item.claim_active
  ) or exists (
    select 1 from public.inventory_custody_incidents as incident
    join public.inventory_custody_items as item
      on item.shop_id = incident.shop_id and item.id = incident.item_id
    where item.shop_id = p_shop_id and item.serialized_inventory_id = p_device_id
      and incident.status = 'open'
  ) then
    raise exception 'A custody claim or unresolved incident prevents repair release.'
      using errcode = '23514';
  end if;
  select balance.* into balance_row
  from public.inventory_balances as balance
  where balance.shop_id = p_shop_id and balance.branch_id = p_branch_id
    and balance.variant_id = device_row.variant_id
    and balance.valuation_status = device_row.valuation_status
  for update;
  if not found or balance_row.reserved_repair_qty < 1 then
    raise exception 'The repair reservation is missing from the source balance.'
      using errcode = '23514';
  end if;
  update public.inventory_balances
  set reserved_repair_qty = reserved_repair_qty - 1,
      available_qty = available_qty + 1,
      updated_at = clock_timestamp(), updated_by = p_actor_id
  where shop_id = p_shop_id and id = balance_row.id;
  update public.serialized_inventory
  set availability_status = 'available', updated_at = clock_timestamp(),
      updated_by = p_actor_id
  where shop_id = p_shop_id and id = p_device_id;
end;
$function$;

revoke all on function private.assert_repair_access(uuid, uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function private.claim_repair_operation(
  uuid, uuid, uuid, text, text, jsonb, uuid, uuid, uuid
) from public, anon, authenticated, service_role;
revoke all on function private.reject_repair_history_mutation()
  from public, anon, authenticated, service_role;
revoke all on function private.guard_repair_job_update()
  from public, anon, authenticated, service_role;
revoke all on function private.require_repair_follow_up_link()
  from public, anon, authenticated, service_role;
revoke all on function private.validate_repair_cost_entry()
  from public, anon, authenticated, service_role;
revoke all on function private.validate_repair_custody_link()
  from public, anon, authenticated, service_role;
revoke all on function private.validate_repair_custody_event_source()
  from public, anon, authenticated, service_role;
revoke all on function private.mirror_repair_custody_event()
  from public, anon, authenticated, service_role;
revoke all on function private.guard_repair_branch_deactivation()
  from public, anon, authenticated, service_role;
revoke all on function private.record_repair_event(
  uuid, uuid, uuid, uuid, uuid, integer, text, text, text, uuid, jsonb
) from public, anon, authenticated, service_role;
revoke all on function private.insert_repair_cost_entry(
  uuid, uuid, uuid, uuid, uuid, text, numeric, char, text, jsonb, text, uuid,
  numeric, text, timestamptz, text, uuid, text
) from public, anon, authenticated, service_role;
revoke all on function private.release_repair_reservation(uuid, uuid, uuid, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.create_repair_job(
  p_shop_id uuid,
  p_branch_id uuid,
  p_serialized_inventory_id uuid,
  p_ticket_reference text,
  p_reported_fault text,
  p_intake_condition text,
  p_expected_completion_at timestamptz,
  p_warranty_evidence jsonb,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor record;
  operation record;
  new_job_id uuid := gen_random_uuid();
  event_id uuid := gen_random_uuid();
  ticket_value text;
  fault_value text := nullif(btrim(p_reported_fault), '');
  condition_value text := nullif(btrim(p_intake_condition), '');
  payload jsonb;
  device_row public.serialized_inventory%rowtype;
  balance_row public.inventory_balances%rowtype;
begin
  select * into actor
  from private.assert_repair_access(p_shop_id, p_branch_id, 'write');
  if fault_value is null or char_length(fault_value) > 2000
    or condition_value is null or char_length(condition_value) > 2000
    or (p_ticket_reference is not null
      and char_length(btrim(p_ticket_reference)) not between 1 and 80)
    or p_warranty_evidence is null
    or jsonb_typeof(p_warranty_evidence) is distinct from 'object'
  then
    raise exception 'Repair fault, intake condition, ticket, or warranty evidence is invalid.'
      using errcode = '22023';
  end if;
  ticket_value := coalesce(
    nullif(btrim(p_ticket_reference), ''),
    'REP-' || upper(substr(md5(p_shop_id::text || ':' || btrim(p_idempotency_key)), 1, 16))
  );
  payload := jsonb_build_object(
    'branch_id', p_branch_id, 'device_id', p_serialized_inventory_id,
    'ticket_reference', ticket_value, 'reported_fault', fault_value,
    'intake_condition', condition_value,
    'expected_completion_at', p_expected_completion_at,
    'warranty_evidence', p_warranty_evidence
  );
  select * into operation
  from private.claim_repair_operation(
    p_shop_id, p_branch_id, actor.actor_id, p_idempotency_key,
    'create', payload, new_job_id, event_id, null
  );
  if operation.replayed then return operation.result_job_id; end if;

  lock table public.products in row share mode;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stockpilot:device-claim:' || p_shop_id::text, 0)
  );
  select device.* into device_row
  from public.serialized_inventory as device
  join public.product_variants as variant
    on variant.shop_id = device.shop_id and variant.id = device.variant_id
  join public.products as product
    on product.shop_id = variant.shop_id and product.id = variant.product_id
  where device.shop_id = p_shop_id and device.branch_id = p_branch_id
    and device.id = p_serialized_inventory_id
    and device.availability_status = 'available'
    and device.transfer_state is null and device.custody_state = 'none'
    and device.valuation_status in ('known_cost', 'unknown_cost')
    and product.tracking_mode = 'serialized'
    and product.archived_at is null and variant.archived_at is null
  for update of device;
  if not found then
    raise exception 'The device is unavailable, pending FX, archived, or not at this branch.'
      using errcode = '23514';
  end if;
  if exists (
    select 1 from public.inventory_transfer_lines as transfer_line
    where transfer_line.shop_id = p_shop_id
      and transfer_line.serialized_inventory_id = p_serialized_inventory_id
      and transfer_line.claim_active
  ) or exists (
    select 1 from public.inventory_custody_items as custody_item
    where custody_item.shop_id = p_shop_id
      and custody_item.serialized_inventory_id = p_serialized_inventory_id
      and custody_item.claim_active
  ) then
    raise exception 'A device with an active transfer or custody claim cannot enter repair.'
      using errcode = '23514';
  end if;
  select balance.* into balance_row
  from public.inventory_balances as balance
  where balance.shop_id = p_shop_id and balance.branch_id = p_branch_id
    and balance.variant_id = device_row.variant_id
    and balance.valuation_status = device_row.valuation_status
  for update;
  if not found or balance_row.available_qty < 1 or balance_row.on_hand_qty < 1
    or balance_row.valuation_currency_code is distinct from device_row.valuation_currency_code
  then
    raise exception 'The branch balance cannot reserve this repair device.'
      using errcode = '23514';
  end if;

  insert into public.repair_jobs (
    id, shop_id, branch_id, serialized_inventory_id, ticket_reference,
    reported_fault, intake_condition, expected_completion_at,
    warranty_evidence, status, device_claim_active, created_by, updated_by
  ) values (
    new_job_id, p_shop_id, p_branch_id, p_serialized_inventory_id, ticket_value,
    fault_value, condition_value, p_expected_completion_at,
    p_warranty_evidence, 'open', true, actor.actor_id, actor.actor_id
  );
  update public.inventory_balances
  set available_qty = available_qty - 1,
      reserved_repair_qty = reserved_repair_qty + 1,
      updated_at = clock_timestamp(), updated_by = actor.actor_id
  where shop_id = p_shop_id and id = balance_row.id;
  update public.serialized_inventory
  set availability_status = 'reserved', updated_at = clock_timestamp(),
      updated_by = actor.actor_id
  where shop_id = p_shop_id and id = device_row.id;
  perform private.record_repair_event(
    event_id, p_shop_id, p_branch_id, new_job_id, operation.operation_id, 0,
    'created', null, 'open', actor.actor_id,
    jsonb_build_object(
      'ticket_reference', ticket_value,
      'serialized_inventory_id', device_row.id,
      'valuation_status', device_row.valuation_status,
      'device_cost_shop', device_row.unit_cost_shop,
      'reserved_qty', 1, 'on_hand_delta', 0, 'available_delta', -1
    )
  );
  return new_job_id;
end;
$function$;

create or replace function public.assign_repair_technician(
  p_shop_id uuid,
  p_repair_job_id uuid,
  p_expected_version bigint,
  p_technician_type text,
  p_internal_technician_user_id uuid,
  p_external_technician_name text,
  p_external_technician_contact text,
  p_reason text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  job_snapshot public.repair_jobs%rowtype;
  actor record;
  operation record;
  event_id uuid := gen_random_uuid();
  name_value text := nullif(btrim(p_external_technician_name), '');
  contact_value text := nullif(btrim(p_external_technician_contact), '');
  reason_value text := nullif(btrim(p_reason), '');
  payload jsonb;
  technician_role public.shop_role;
begin
  select job.* into job_snapshot from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_repair_job_id;
  if not found then raise exception 'Repair job not found.' using errcode = '22023'; end if;
  select * into actor from private.assert_repair_access(p_shop_id, job_snapshot.branch_id, 'admin');
  if p_technician_type = 'internal' then
    if p_internal_technician_user_id is null or name_value is not null
      or contact_value is not null
    then
      raise exception 'Internal technician assignment requires only an internal user ID.'
        using errcode = '22023';
    end if;
    select membership.role into technician_role
    from public.shop_memberships as membership
    where membership.shop_id = p_shop_id
      and membership.user_id = p_internal_technician_user_id
      and membership.status = 'active'
    for share;
    if not found or technician_role not in ('owner', 'manager', 'inventory_staff') then
      raise exception 'Internal technician must be active and authorized for this branch.'
        using errcode = '42501';
    end if;
    if technician_role <> 'owner' then
      perform 1 from public.branch_memberships as assignment
      where assignment.shop_id = p_shop_id
        and assignment.branch_id = job_snapshot.branch_id
        and assignment.user_id = p_internal_technician_user_id
      for share;
      if not found then
        raise exception 'Internal technician must be active and authorized for this branch.'
          using errcode = '42501';
      end if;
    end if;
  elsif p_technician_type = 'external' then
    if p_internal_technician_user_id is not null or name_value is null
      or char_length(name_value) > 200 or char_length(coalesce(contact_value, '')) > 300
    then
      raise exception 'External technician name or contact is invalid.'
        using errcode = '22023';
    end if;
  else
    raise exception 'Technician type must be internal or external.'
      using errcode = '22023';
  end if;
  if reason_value is null or char_length(reason_value) > 500 then
    raise exception 'A technician assignment reason is required.'
      using errcode = '22023';
  end if;
  payload := jsonb_build_object(
    'job_id', p_repair_job_id, 'expected_version', p_expected_version,
    'technician_type', p_technician_type,
    'internal_user_id', p_internal_technician_user_id,
    'external_name', name_value, 'external_contact', contact_value,
    'reason', reason_value
  );
  select * into operation from private.claim_repair_operation(
    p_shop_id, job_snapshot.branch_id, actor.actor_id, p_idempotency_key,
    'assign_technician', payload, p_repair_job_id, event_id, null
  );
  if operation.replayed then return operation.result_job_id; end if;
  lock table public.products in row share mode;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stockpilot:device-claim:' || p_shop_id::text, 0)
  );
  select job.* into job_snapshot from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_repair_job_id
  for update;
  if p_expected_version is null or p_expected_version < 1
    or job_snapshot.version <> p_expected_version
    or not job_snapshot.device_claim_active
    or job_snapshot.status in ('completed', 'cancelled', 'closed')
  then
    raise exception 'Repair job changed or is no longer assignable.'
      using errcode = '40001';
  end if;
  update public.repair_jobs
  set technician_type = p_technician_type,
      technician_user_id = p_internal_technician_user_id,
      external_technician_name = name_value,
      external_technician_contact = contact_value,
      version = version + 1, updated_at = clock_timestamp(),
      updated_by = actor.actor_id
  where shop_id = p_shop_id and id = p_repair_job_id;
  perform private.record_repair_event(
    event_id, p_shop_id, job_snapshot.branch_id, p_repair_job_id,
    operation.operation_id, 0, 'technician_assigned', job_snapshot.status,
    job_snapshot.status, actor.actor_id,
    jsonb_build_object(
      'technician_type', p_technician_type,
      'internal_user_id', p_internal_technician_user_id,
      'external_name', name_value, 'external_contact', contact_value,
      'reason', reason_value,
      'previous_technician_type', job_snapshot.technician_type,
      'previous_internal_user_id', job_snapshot.technician_user_id,
      'previous_external_name', job_snapshot.external_technician_name
    )
  );
  return p_repair_job_id;
end;
$function$;

create or replace function private.update_repair_notes(
  p_shop_id uuid,
  p_repair_job_id uuid,
  p_expected_version bigint,
  p_note text,
  p_target_status text,
  p_evidence jsonb,
  p_idempotency_key text,
  p_operation_type text,
  p_event_type text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  job_snapshot public.repair_jobs%rowtype;
  actor record;
  operation record;
  event_id uuid := gen_random_uuid();
  note_value text := nullif(btrim(p_note), '');
  next_status text;
  payload jsonb;
begin
  select job.* into job_snapshot from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_repair_job_id;
  if not found then raise exception 'Repair job not found.' using errcode = '22023'; end if;
  select * into actor from private.assert_repair_access(
    p_shop_id, job_snapshot.branch_id, 'write'
  );
  if note_value is null or char_length(note_value) > 4000
    or p_evidence is null or jsonb_typeof(p_evidence) is distinct from 'object'
  then
    raise exception 'Repair notes require text and object evidence.'
      using errcode = '22023';
  end if;
  if p_operation_type = 'diagnosis' then
    if p_target_status is not null and p_target_status not in (
      'diagnosing', 'awaiting_approval', 'in_progress', 'awaiting_parts'
    ) then
      raise exception 'Diagnosis cannot perform this repair state transition.'
        using errcode = '23514';
    end if;
  elsif p_operation_type = 'progress' then
    if p_target_status is null
      or p_target_status not in ('diagnosing', 'in_progress', 'awaiting_parts')
    then
      raise exception 'Progress status must be diagnosing, in progress, or awaiting parts.'
        using errcode = '23514';
    end if;
  end if;
  next_status := coalesce(p_target_status, job_snapshot.status);
  payload := jsonb_build_object(
    'job_id', p_repair_job_id, 'expected_version', p_expected_version,
    'note', note_value, 'target_status', p_target_status, 'evidence', p_evidence
  );
  select * into operation from private.claim_repair_operation(
    p_shop_id, job_snapshot.branch_id, actor.actor_id, p_idempotency_key,
    p_operation_type, payload, p_repair_job_id, event_id, null
  );
  if operation.replayed then return operation.result_job_id; end if;
  lock table public.products in row share mode;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stockpilot:device-claim:' || p_shop_id::text, 0)
  );
  select job.* into job_snapshot from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_repair_job_id
  for update;
  if p_expected_version is null or p_expected_version < 1
    or job_snapshot.version <> p_expected_version
    or not job_snapshot.device_claim_active then
    raise exception 'Repair job changed or is no longer active.'
      using errcode = '40001';
  end if;
  update public.repair_jobs
  set diagnosis = case when p_operation_type = 'diagnosis' then note_value else diagnosis end,
      status = next_status, version = version + 1,
      updated_at = clock_timestamp(), updated_by = actor.actor_id
  where shop_id = p_shop_id and id = p_repair_job_id;
  perform private.record_repair_event(
    event_id, p_shop_id, job_snapshot.branch_id, p_repair_job_id,
    operation.operation_id, 0, p_event_type, job_snapshot.status, next_status,
    actor.actor_id, jsonb_build_object('note', note_value, 'evidence', p_evidence)
  );
  return p_repair_job_id;
end;
$function$;

create or replace function public.update_repair_diagnosis(
  p_shop_id uuid,
  p_repair_job_id uuid,
  p_expected_version bigint,
  p_diagnosis text,
  p_target_status text,
  p_evidence jsonb,
  p_idempotency_key text
)
returns uuid
language sql
security definer
set search_path = ''
as $function$
  select private.update_repair_notes(
    p_shop_id, p_repair_job_id, p_expected_version, p_diagnosis,
    p_target_status, p_evidence, p_idempotency_key, 'diagnosis',
    'diagnosis_updated'
  );
$function$;

create or replace function public.update_repair_progress(
  p_shop_id uuid,
  p_repair_job_id uuid,
  p_expected_version bigint,
  p_progress_note text,
  p_target_status text,
  p_evidence jsonb,
  p_idempotency_key text
)
returns uuid
language sql
security definer
set search_path = ''
as $function$
  select private.update_repair_notes(
    p_shop_id, p_repair_job_id, p_expected_version, p_progress_note,
    p_target_status, p_evidence, p_idempotency_key, 'progress',
    'progress_updated'
  );
$function$;

revoke all on function private.update_repair_notes(
  uuid, uuid, bigint, text, text, jsonb, text, text, text
) from public, anon, authenticated, service_role;

create or replace function public.submit_repair_estimate(
  p_shop_id uuid,
  p_repair_job_id uuid,
  p_expected_version bigint,
  p_amount numeric,
  p_currency_code char(3),
  p_evidence jsonb,
  p_invoice_reference text,
  p_rate_snapshot_id uuid,
  p_manual_rate numeric,
  p_manual_rate_source text,
  p_manual_rate_observed_at timestamptz,
  p_manual_rate_reason text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  job_row public.repair_jobs%rowtype;
  actor record;
  operation record;
  event_id uuid := gen_random_uuid();
  cost_row record;
  payload jsonb;
begin
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_repair_job_id;
  if not found then raise exception 'Repair job not found.' using errcode = '22023'; end if;
  select * into actor from private.assert_repair_access(p_shop_id, job_row.branch_id, 'write');
  if p_evidence is null or jsonb_typeof(p_evidence) is distinct from 'object'
    or job_row.status not in ('open', 'diagnosing', 'awaiting_approval', 'approved', 'in_progress', 'awaiting_parts')
  then
    raise exception 'Estimate evidence or repair state is invalid.'
      using errcode = '23514';
  end if;
  payload := jsonb_build_object(
    'job_id', p_repair_job_id, 'expected_version', p_expected_version,
    'amount', p_amount, 'currency', p_currency_code, 'evidence', p_evidence,
    'invoice_reference', p_invoice_reference,
    'rate_snapshot_id', p_rate_snapshot_id, 'manual_rate', p_manual_rate,
    'manual_rate_source', p_manual_rate_source,
    'manual_rate_observed_at', p_manual_rate_observed_at,
    'manual_rate_reason', p_manual_rate_reason
  );
  select * into operation from private.claim_repair_operation(
    p_shop_id, job_row.branch_id, actor.actor_id, p_idempotency_key,
    'estimate', payload, p_repair_job_id, event_id, null
  );
  if operation.replayed then return operation.result_job_id; end if;
  lock table public.products in row share mode;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stockpilot:device-claim:' || p_shop_id::text, 0)
  );
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_repair_job_id
  for update;
  if p_expected_version is null or p_expected_version < 1
    or job_row.version <> p_expected_version or not job_row.device_claim_active
    or job_row.status not in ('open', 'diagnosing', 'awaiting_approval', 'approved', 'in_progress', 'awaiting_parts')
  then
    raise exception 'Repair job changed or cannot accept an estimate.'
      using errcode = '40001';
  end if;
  select * into cost_row from private.insert_repair_cost_entry(
    p_shop_id, job_row.branch_id, job_row.id, operation.operation_id,
    actor.actor_id, 'estimate', p_amount, p_currency_code, 'shop', p_evidence,
    p_invoice_reference, p_rate_snapshot_id, p_manual_rate,
    p_manual_rate_source, p_manual_rate_observed_at, p_manual_rate_reason,
    null, null
  );
  update public.repair_jobs
  set status = 'awaiting_approval', version = version + 1,
      updated_at = clock_timestamp(), updated_by = actor.actor_id
  where shop_id = p_shop_id and id = job_row.id;
  perform private.record_repair_event(
    event_id, p_shop_id, job_row.branch_id, job_row.id, operation.operation_id,
    0, 'estimate_submitted', job_row.status, 'awaiting_approval', actor.actor_id,
    jsonb_build_object('cost_entry_id', cost_row.entry_id, 'fx_status', cost_row.fx_status)
  );
  return job_row.id;
end;
$function$;

create or replace function public.approve_repair_spend(
  p_shop_id uuid,
  p_repair_job_id uuid,
  p_expected_version bigint,
  p_approved_limit numeric,
  p_currency_code char(3),
  p_reason text,
  p_evidence jsonb,
  p_rate_snapshot_id uuid,
  p_manual_rate numeric,
  p_manual_rate_source text,
  p_manual_rate_observed_at timestamptz,
  p_manual_rate_reason text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  job_row public.repair_jobs%rowtype;
  actor record;
  operation record;
  event_id uuid := gen_random_uuid();
  cost_row record;
  gross_consumed numeric(38, 8);
  payload jsonb;
begin
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_repair_job_id;
  if not found then raise exception 'Repair job not found.' using errcode = '22023'; end if;
  select * into actor from private.assert_repair_access(p_shop_id, job_row.branch_id, 'approve');
  if nullif(btrim(p_reason), '') is null or char_length(btrim(p_reason)) > 1000
    or p_evidence is null or jsonb_typeof(p_evidence) is distinct from 'object'
    or job_row.status <> 'awaiting_approval'
  then
    raise exception 'Spending approval requires an awaiting-approval job, reason, and evidence.'
      using errcode = '23514';
  end if;
  payload := jsonb_build_object(
    'job_id', p_repair_job_id, 'expected_version', p_expected_version,
    'approved_limit', p_approved_limit, 'currency', p_currency_code,
    'reason', btrim(p_reason), 'evidence', p_evidence,
    'rate_snapshot_id', p_rate_snapshot_id, 'manual_rate', p_manual_rate,
    'manual_rate_source', p_manual_rate_source,
    'manual_rate_observed_at', p_manual_rate_observed_at,
    'manual_rate_reason', p_manual_rate_reason
  );
  select * into operation from private.claim_repair_operation(
    p_shop_id, job_row.branch_id, actor.actor_id, p_idempotency_key,
    'spend_approval', payload, p_repair_job_id, event_id, null
  );
  if operation.replayed then return operation.result_job_id; end if;
  lock table public.products in row share mode;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stockpilot:device-claim:' || p_shop_id::text, 0)
  );
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_repair_job_id
  for update;
  if p_expected_version is null or p_expected_version < 1
    or job_row.version <> p_expected_version or job_row.status <> 'awaiting_approval'
    or not job_row.device_claim_active
  then
    raise exception 'Repair job changed or is not awaiting spending approval.'
      using errcode = '40001';
  end if;
  select * into cost_row from private.insert_repair_cost_entry(
    p_shop_id, job_row.branch_id, job_row.id, operation.operation_id,
    actor.actor_id, 'approved_limit', p_approved_limit, p_currency_code, 'shop',
    jsonb_build_object('reason', btrim(p_reason), 'evidence', p_evidence),
    null, p_rate_snapshot_id, p_manual_rate, p_manual_rate_source,
    p_manual_rate_observed_at, p_manual_rate_reason, null, null
  );
  if cost_row.converted_amount is null then
    raise exception 'Approved spending limit must have accepted shop-currency FX.'
      using errcode = '23514';
  end if;
  select private.repair_gross_authorization_consumed(p_shop_id, job_row.id)
    into gross_consumed;
  if gross_consumed > cost_row.converted_amount then
    raise exception 'Approved spending limit cannot be below gross shop spending already incurred.'
      using errcode = '23514';
  end if;
  update public.repair_jobs
  set status = 'approved', version = version + 1,
      updated_at = clock_timestamp(), updated_by = actor.actor_id
  where shop_id = p_shop_id and id = job_row.id;
  perform private.record_repair_event(
    event_id, p_shop_id, job_row.branch_id, job_row.id, operation.operation_id,
    0, 'spending_approved', job_row.status, 'approved', actor.actor_id,
    jsonb_build_object(
      'cost_entry_id', cost_row.entry_id,
      'approved_limit_shop', cost_row.converted_amount,
      'currency', p_currency_code, 'reason', btrim(p_reason)
    )
  );
  return job_row.id;
end;
$function$;

create or replace function public.record_repair_expense(
  p_shop_id uuid,
  p_repair_job_id uuid,
  p_expected_version bigint,
  p_amount numeric,
  p_currency_code char(3),
  p_cost_bearer text,
  p_evidence jsonb,
  p_invoice_reference text,
  p_rate_snapshot_id uuid,
  p_manual_rate numeric,
  p_manual_rate_source text,
  p_manual_rate_observed_at timestamptz,
  p_manual_rate_reason text,
  p_supersedes_entry_id uuid,
  p_correction_reason text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  job_row public.repair_jobs%rowtype;
  actor record;
  operation record;
  event_id uuid := gen_random_uuid();
  cost_row record;
  latest_limit numeric(38, 8);
  actual_total numeric(38, 8);
  gross_consumed numeric(38, 8);
  entry_kind text;
  prior_entry public.repair_cost_entries%rowtype;
  payload jsonb;
begin
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_repair_job_id;
  if not found then raise exception 'Repair job not found.' using errcode = '22023'; end if;
  select * into actor from private.assert_repair_access(p_shop_id, job_row.branch_id, 'write');
  if p_evidence is null or jsonb_typeof(p_evidence) is distinct from 'object'
    or p_cost_bearer is null
    or p_cost_bearer not in (
      'shop', 'manufacturer_warranty', 'supplier_warranty',
      'technician_warranty', 'other'
    )
    or job_row.status not in ('approved', 'in_progress', 'awaiting_parts', 'returned_pending_inspection')
  then
    raise exception 'Expense evidence or repair state is invalid.'
      using errcode = '23514';
  end if;
  entry_kind := case
    when p_supersedes_entry_id is not null then 'correction'
    when p_cost_bearer = 'shop' then 'actual'
    else 'warranty'
  end;
  if (entry_kind = 'correction') <> (p_supersedes_entry_id is not null)
    or (entry_kind = 'correction' and nullif(btrim(p_correction_reason), '') is null)
    or (entry_kind <> 'correction' and p_correction_reason is not null)
  then
    raise exception 'Expense correction must supersede an entry and include a reason.'
      using errcode = '22023';
  end if;
  payload := jsonb_build_object(
    'job_id', p_repair_job_id, 'expected_version', p_expected_version,
    'amount', p_amount, 'currency', p_currency_code, 'cost_bearer', p_cost_bearer,
    'evidence', p_evidence, 'invoice_reference', p_invoice_reference,
    'rate_snapshot_id', p_rate_snapshot_id, 'manual_rate', p_manual_rate,
    'manual_rate_source', p_manual_rate_source,
    'manual_rate_observed_at', p_manual_rate_observed_at,
    'manual_rate_reason', p_manual_rate_reason,
    'supersedes_entry_id', p_supersedes_entry_id,
    'correction_reason', p_correction_reason
  );
  select * into operation from private.claim_repair_operation(
    p_shop_id, job_row.branch_id, actor.actor_id, p_idempotency_key,
    'expense', payload, p_repair_job_id, event_id, null
  );
  if operation.replayed then return operation.result_job_id; end if;
  lock table public.products in row share mode;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stockpilot:device-claim:' || p_shop_id::text, 0)
  );
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_repair_job_id
  for update;
  if p_expected_version is null or p_expected_version < 1
    or job_row.version <> p_expected_version or not job_row.device_claim_active
    or job_row.status not in ('approved', 'in_progress', 'awaiting_parts', 'returned_pending_inspection')
  then
    raise exception 'Repair job changed or cannot accept an expense.'
      using errcode = '40001';
  end if;
  if p_supersedes_entry_id is not null then
    select prior.* into prior_entry
    from public.repair_cost_entries as prior
    where prior.shop_id = p_shop_id and prior.repair_job_id = job_row.id
      and prior.id = p_supersedes_entry_id
      and prior.entry_type in ('actual', 'correction', 'warranty')
    for share;
    if not found
      or prior_entry.cost_bearer is distinct from p_cost_bearer
      or prior_entry.original_currency_code is distinct from p_currency_code
      or exists (
        select 1 from public.repair_cost_entries as replacement
        where replacement.shop_id = p_shop_id
          and replacement.supersedes_entry_id = prior_entry.id
      )
    then
      raise exception 'A correction must match an unsuperseded expense entry for this job, cost bearer, and currency.'
        using errcode = '23514';
    end if;
  end if;
  select * into cost_row from private.insert_repair_cost_entry(
    p_shop_id, job_row.branch_id, job_row.id, operation.operation_id,
    actor.actor_id, entry_kind, p_amount, p_currency_code, p_cost_bearer,
    p_evidence, p_invoice_reference, p_rate_snapshot_id, p_manual_rate,
    p_manual_rate_source, p_manual_rate_observed_at, p_manual_rate_reason,
    p_supersedes_entry_id, nullif(btrim(p_correction_reason), '')
  );
  if p_cost_bearer = 'shop' then
    if cost_row.converted_amount is null then
      raise exception 'Shop-borne expense cannot be compared without accepted FX evidence.'
        using errcode = '23514';
    end if;
    select entry.converted_shop_amount into latest_limit
    from public.repair_cost_entries as entry
    where entry.shop_id = p_shop_id and entry.repair_job_id = job_row.id
      and entry.entry_type = 'approved_limit'
      and entry.converted_shop_amount is not null
    order by entry.created_at desc, entry.id desc
    limit 1;
    if latest_limit is null then
      raise exception 'Owner or Manager spending approval is required before recording a shop expense.'
        using errcode = '23514';
    end if;
    select private.repair_gross_authorization_consumed(p_shop_id, job_row.id)
      into gross_consumed;
    if gross_consumed > latest_limit then
      raise exception 'Gross shop-borne spending exceeds the approved spending authorization.'
        using errcode = '23514';
    end if;
    select coalesce(sum(entry.converted_shop_amount), 0)
      into actual_total
    from public.repair_cost_entries as entry
    where entry.shop_id = p_shop_id and entry.repair_job_id = job_row.id
      and entry.cost_bearer = 'shop'
      and entry.entry_type in ('actual', 'correction');
    if actual_total < 0 then
      raise exception 'Expense corrections cannot reduce net shop-borne expenses below zero.'
        using errcode = '23514';
    end if;
  end if;
  update public.repair_jobs
  set version = version + 1, updated_at = clock_timestamp(),
      updated_by = actor.actor_id
  where shop_id = p_shop_id and id = job_row.id;
  perform private.record_repair_event(
    event_id, p_shop_id, job_row.branch_id, job_row.id, operation.operation_id,
    0, 'expense_recorded', job_row.status, job_row.status, actor.actor_id,
    jsonb_build_object(
      'cost_entry_id', cost_row.entry_id, 'entry_type', entry_kind,
      'cost_bearer', p_cost_bearer,
      'converted_shop_amount', cost_row.converted_amount,
      'fx_status', cost_row.fx_status
    )
  );
  return job_row.id;
end;
$function$;

create or replace function public.complete_repair_job(
  p_shop_id uuid,
  p_repair_job_id uuid,
  p_expected_version bigint,
  p_completion_evidence jsonb,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  job_row public.repair_jobs%rowtype;
  actor record;
  operation record;
  event_id uuid := gen_random_uuid();
  device_row public.serialized_inventory%rowtype;
  latest_limit numeric(38, 8);
  gross_consumed numeric(38, 8);
  payload jsonb;
begin
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_repair_job_id;
  if not found then raise exception 'Repair job not found.' using errcode = '22023'; end if;
  select * into actor from private.assert_repair_access(p_shop_id, job_row.branch_id, 'write');
  if private.is_valid_repair_operational_evidence(p_completion_evidence)
       is distinct from true
    or job_row.status not in ('in_progress', 'awaiting_parts', 'returned_pending_inspection')
  then
    raise exception 'Completion requires an active repair and valid operational-only evidence.'
      using errcode = '23514';
  end if;
  payload := jsonb_build_object(
    'job_id', p_repair_job_id, 'expected_version', p_expected_version,
    'completion_evidence', p_completion_evidence
  );
  select * into operation from private.claim_repair_operation(
    p_shop_id, job_row.branch_id, actor.actor_id, p_idempotency_key,
    'completion', payload, p_repair_job_id, event_id, null
  );
  if operation.replayed then return operation.result_job_id; end if;
  lock table public.products in row share mode;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stockpilot:device-claim:' || p_shop_id::text, 0)
  );
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_repair_job_id
  for update;
  if p_expected_version is null or p_expected_version < 1
    or job_row.version <> p_expected_version or not job_row.device_claim_active
    or job_row.status not in ('in_progress', 'awaiting_parts', 'returned_pending_inspection')
  then
    raise exception 'Repair job changed or cannot be completed.'
      using errcode = '40001';
  end if;
  select device.* into device_row from public.serialized_inventory as device
  where device.shop_id = p_shop_id and device.branch_id = job_row.branch_id
    and device.id = job_row.serialized_inventory_id
    and device.availability_status = 'reserved'
    and device.transfer_state is null and device.custody_state = 'none'
  for update;
  if not found
    or exists (
      select 1 from public.inventory_custody_items as item
      where item.shop_id = p_shop_id
        and item.serialized_inventory_id = job_row.serialized_inventory_id
        and item.claim_active
    )
    or exists (
      select 1 from public.inventory_custody_incidents as incident
      join public.inventory_custody_items as item
        on item.shop_id = incident.shop_id and item.id = incident.item_id
      where item.shop_id = p_shop_id
        and item.serialized_inventory_id = job_row.serialized_inventory_id
        and incident.status = 'open'
    )
  then
    raise exception 'The device must be back at the source branch with no active custody claim or incident.'
      using errcode = '23514';
  end if;
  if exists (
    select 1 from public.repair_cost_entries as entry
    where entry.shop_id = p_shop_id and entry.repair_job_id = job_row.id
      and entry.cost_bearer = 'shop'
      and entry.entry_type in ('actual', 'correction')
      and entry.converted_shop_amount is null
  ) then
    raise exception 'Shop-borne expense evidence with unresolved FX prevents completion.'
      using errcode = '23514';
  end if;
  select entry.converted_shop_amount into latest_limit
  from public.repair_cost_entries as entry
  where entry.shop_id = p_shop_id and entry.repair_job_id = job_row.id
    and entry.entry_type = 'approved_limit' and entry.converted_shop_amount is not null
  order by entry.created_at desc, entry.id desc
  limit 1;
  select private.repair_gross_authorization_consumed(p_shop_id, job_row.id)
    into gross_consumed;
  if gross_consumed > 0
    and (latest_limit is null or gross_consumed > latest_limit)
  then
    raise exception 'Gross shop-borne spending exceeds the approved authorization.'
      using errcode = '23514';
  end if;

  if actor.actor_role = 'inventory_staff' then
    if job_row.completion_submitted_at is not null then
      raise exception 'Completion evidence is already awaiting Owner or Manager review.'
        using errcode = '40001';
    end if;
    update public.repair_jobs
    set completion_evidence = p_completion_evidence,
        completion_submitted_by = actor.actor_id,
        completion_submitted_at = clock_timestamp(),
        version = version + 1, updated_at = clock_timestamp(),
        updated_by = actor.actor_id
    where shop_id = p_shop_id and id = job_row.id;
    perform private.record_repair_event(
      event_id, p_shop_id, job_row.branch_id, job_row.id, operation.operation_id,
      0, 'completion_evidence_submitted', job_row.status, job_row.status,
      actor.actor_id, p_completion_evidence
    );
    return job_row.id;
  end if;

  update public.repair_jobs
  set status = 'completed',
      completion_evidence = coalesce(completion_evidence, '{}'::jsonb)
        || p_completion_evidence,
      completed_by = actor.actor_id, completed_at = clock_timestamp(),
      device_claim_active = false,
      version = version + 1, updated_at = clock_timestamp(),
      updated_by = actor.actor_id
  where shop_id = p_shop_id and id = job_row.id;
  perform private.release_repair_reservation(
    p_shop_id, job_row.branch_id, job_row.serialized_inventory_id, actor.actor_id
  );
  perform private.record_repair_event(
    event_id, p_shop_id, job_row.branch_id, job_row.id, operation.operation_id,
    0, 'completed', job_row.status, 'completed', actor.actor_id,
    p_completion_evidence
  );
  return job_row.id;
end;
$function$;

create or replace function public.mark_repair_unrepairable(
  p_shop_id uuid,
  p_repair_job_id uuid,
  p_expected_version bigint,
  p_reason text,
  p_evidence jsonb,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  job_row public.repair_jobs%rowtype;
  actor record;
  operation record;
  event_id uuid := gen_random_uuid();
  payload jsonb;
  device_row public.serialized_inventory%rowtype;
begin
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_repair_job_id;
  if not found then raise exception 'Repair job not found.' using errcode = '22023'; end if;
  select * into actor from private.assert_repair_access(p_shop_id, job_row.branch_id, 'admin');
  if nullif(btrim(p_reason), '') is null or char_length(btrim(p_reason)) > 1000
    or private.is_valid_repair_operational_evidence(p_evidence)
       is distinct from true
  then
    raise exception 'Unrepairable outcome requires a reason and valid operational-only evidence.'
      using errcode = '22023';
  end if;
  payload := jsonb_build_object(
    'job_id', p_repair_job_id, 'expected_version', p_expected_version,
    'reason', btrim(p_reason), 'evidence', p_evidence
  );
  select * into operation from private.claim_repair_operation(
    p_shop_id, job_row.branch_id, actor.actor_id, p_idempotency_key,
    'unrepairable', payload, p_repair_job_id, event_id, null
  );
  if operation.replayed then return operation.result_job_id; end if;
  lock table public.products in row share mode;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stockpilot:device-claim:' || p_shop_id::text, 0)
  );
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_repair_job_id
  for update;
  if p_expected_version is null or p_expected_version < 1
    or job_row.version <> p_expected_version or not job_row.device_claim_active
    or job_row.status not in ('diagnosing', 'in_progress', 'awaiting_parts', 'returned_pending_inspection')
  then
    raise exception 'Repair job changed or cannot be marked unrepairable.'
      using errcode = '40001';
  end if;
  select device.* into device_row from public.serialized_inventory as device
  where device.shop_id = p_shop_id and device.branch_id = job_row.branch_id
    and device.id = job_row.serialized_inventory_id
    and device.availability_status = 'reserved' and device.transfer_state is null
    and device.custody_state = 'none'
  for update;
  if not found or exists (
    select 1 from public.inventory_custody_items as item
    where item.shop_id = p_shop_id
      and item.serialized_inventory_id = job_row.serialized_inventory_id
      and item.claim_active
  ) or exists (
    select 1 from public.inventory_custody_incidents as incident
    join public.inventory_custody_items as item
      on item.shop_id = incident.shop_id and item.id = incident.item_id
    where item.shop_id = p_shop_id
      and item.serialized_inventory_id = job_row.serialized_inventory_id
      and incident.status = 'open'
  ) then
    raise exception 'The device must be physically returned and clear of custody incidents.'
      using errcode = '23514';
  end if;
  update public.repair_jobs
  set status = 'unrepairable', outcome_reason = btrim(p_reason),
      completion_evidence = p_evidence,
      version = version + 1, updated_at = clock_timestamp(),
      updated_by = actor.actor_id
  where shop_id = p_shop_id and id = job_row.id;
  perform private.record_repair_event(
    event_id, p_shop_id, job_row.branch_id, job_row.id, operation.operation_id,
    0, 'unrepairable', job_row.status, 'unrepairable', actor.actor_id,
    jsonb_build_object('reason', btrim(p_reason), 'evidence', p_evidence,
      'device_claim_retained', true, 'write_off_created', false)
  );
  return job_row.id;
end;
$function$;

create or replace function public.cancel_repair_job(
  p_shop_id uuid,
  p_repair_job_id uuid,
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
  job_row public.repair_jobs%rowtype;
  actor record;
  operation record;
  event_id uuid := gen_random_uuid();
  payload jsonb;
begin
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_repair_job_id;
  if not found then raise exception 'Repair job not found.' using errcode = '22023'; end if;
  select * into actor from private.assert_repair_access(p_shop_id, job_row.branch_id, 'admin');
  if nullif(btrim(p_reason), '') is null or char_length(btrim(p_reason)) > 1000 then
    raise exception 'Repair cancellation requires a reason.' using errcode = '22023';
  end if;
  payload := jsonb_build_object(
    'job_id', p_repair_job_id, 'expected_version', p_expected_version,
    'reason', btrim(p_reason)
  );
  select * into operation from private.claim_repair_operation(
    p_shop_id, job_row.branch_id, actor.actor_id, p_idempotency_key,
    'cancellation', payload, p_repair_job_id, event_id, null
  );
  if operation.replayed then return operation.result_job_id; end if;
  lock table public.products in row share mode;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stockpilot:device-claim:' || p_shop_id::text, 0)
  );
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_repair_job_id
  for update;
  if p_expected_version is null or p_expected_version < 1
    or job_row.version <> p_expected_version or not job_row.device_claim_active
    or job_row.status in ('completed', 'unrepairable', 'cancelled', 'closed')
  then
    raise exception 'Repair job changed or cannot be cancelled.'
      using errcode = '40001';
  end if;
  update public.repair_jobs
  set status = 'cancelled', cancellation_reason = btrim(p_reason),
      cancelled_by = actor.actor_id, cancelled_at = clock_timestamp(),
      device_claim_active = false, version = version + 1,
      updated_at = clock_timestamp(), updated_by = actor.actor_id
  where shop_id = p_shop_id and id = job_row.id;
  perform private.release_repair_reservation(
    p_shop_id, job_row.branch_id, job_row.serialized_inventory_id, actor.actor_id
  );
  perform private.record_repair_event(
    event_id, p_shop_id, job_row.branch_id, job_row.id, operation.operation_id,
    0, 'cancelled', job_row.status, 'cancelled', actor.actor_id,
    jsonb_build_object('reason', btrim(p_reason),
      'expenses_preserved', true)
  );
  return job_row.id;
end;
$function$;

create or replace function public.close_repair_job(
  p_shop_id uuid,
  p_repair_job_id uuid,
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
  job_row public.repair_jobs%rowtype;
  actor record;
  operation record;
  event_id uuid := gen_random_uuid();
  payload jsonb;
begin
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_repair_job_id;
  if not found then raise exception 'Repair job not found.' using errcode = '22023'; end if;
  select * into actor from private.assert_repair_access(p_shop_id, job_row.branch_id, 'admin');
  if nullif(btrim(p_reason), '') is null or char_length(btrim(p_reason)) > 1000
    or job_row.status not in ('completed', 'cancelled')
  then
    raise exception 'Only completed or cancelled repair jobs can be administratively closed.'
      using errcode = '23514';
  end if;
  payload := jsonb_build_object(
    'job_id', p_repair_job_id, 'expected_version', p_expected_version,
    'reason', btrim(p_reason)
  );
  select * into operation from private.claim_repair_operation(
    p_shop_id, job_row.branch_id, actor.actor_id, p_idempotency_key,
    'closure', payload, p_repair_job_id, event_id, null
  );
  if operation.replayed then return operation.result_job_id; end if;
  lock table public.products in row share mode;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stockpilot:device-claim:' || p_shop_id::text, 0)
  );
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_repair_job_id
  for update;
  if p_expected_version is null or p_expected_version < 1
    or job_row.version <> p_expected_version
    or job_row.status not in ('completed', 'cancelled')
    or job_row.device_claim_active
  then
    raise exception 'Repair job changed or is not ready for closure.'
      using errcode = '40001';
  end if;
  update public.repair_jobs
  set status = 'closed', closure_reason = btrim(p_reason),
      closed_by = actor.actor_id, closed_at = clock_timestamp(),
      version = version + 1, updated_at = clock_timestamp(),
      updated_by = actor.actor_id
  where shop_id = p_shop_id and id = job_row.id;
  perform private.record_repair_event(
    event_id, p_shop_id, job_row.branch_id, job_row.id, operation.operation_id,
    0, 'closed', job_row.status, 'closed', actor.actor_id,
    jsonb_build_object('reason', btrim(p_reason))
  );
  return job_row.id;
end;
$function$;

create or replace function public.create_follow_up_repair(
  p_shop_id uuid,
  p_previous_job_id uuid,
  p_expected_version bigint,
  p_ticket_reference text,
  p_reported_fault text,
  p_intake_condition text,
  p_expected_completion_at timestamptz,
  p_reason text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  previous_row public.repair_jobs%rowtype;
  device_row public.serialized_inventory%rowtype;
  balance_row public.inventory_balances%rowtype;
  actor record;
  operation record;
  new_job_id uuid := gen_random_uuid();
  previous_event_id uuid := gen_random_uuid();
  new_event_id uuid := gen_random_uuid();
  ticket_value text;
  fault_value text := nullif(btrim(p_reported_fault), '');
  condition_value text := nullif(btrim(p_intake_condition), '');
  reason_value text := nullif(btrim(p_reason), '');
  payload jsonb;
begin
  select job.* into previous_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_previous_job_id;
  if not found then raise exception 'Previous repair job not found.' using errcode = '22023'; end if;
  select * into actor from private.assert_repair_access(p_shop_id, previous_row.branch_id, 'admin');
  if fault_value is null or char_length(fault_value) > 2000
    or condition_value is null or char_length(condition_value) > 2000
    or reason_value is null or char_length(reason_value) > 1000
    or (p_ticket_reference is not null
      and char_length(btrim(p_ticket_reference)) not between 1 and 80)
  then
    raise exception 'Follow-up repair requires a ticket, fault, intake condition, and reason.'
      using errcode = '22023';
  end if;
  ticket_value := coalesce(
    nullif(btrim(p_ticket_reference), ''),
    'REP-' || upper(substr(md5(p_shop_id::text || ':' || btrim(p_idempotency_key)), 1, 16))
  );
  payload := jsonb_build_object(
    'previous_job_id', p_previous_job_id,
    'expected_version', p_expected_version,
    'ticket_reference', ticket_value,
    'reported_fault', fault_value, 'intake_condition', condition_value,
    'expected_completion_at', p_expected_completion_at,
    'reason', reason_value
  );
  select * into operation from private.claim_repair_operation(
    p_shop_id, previous_row.branch_id, actor.actor_id, p_idempotency_key,
    'follow_up', payload, new_job_id, new_event_id, null
  );
  if operation.replayed then return operation.result_job_id; end if;
  lock table public.products in row share mode;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stockpilot:device-claim:' || p_shop_id::text, 0)
  );
  select job.* into previous_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_previous_job_id
  for update;
  if p_expected_version is null or p_expected_version < 1
    or previous_row.version <> p_expected_version
    or previous_row.status <> 'unrepairable'
    or not previous_row.device_claim_active
    or previous_row.follow_up_from_job_id = new_job_id
  then
    raise exception 'Only the current unrepairable job may hand off its active repair hold.'
      using errcode = '40001';
  end if;
  select device.* into device_row from public.serialized_inventory as device
  where device.shop_id = p_shop_id and device.branch_id = previous_row.branch_id
    and device.id = previous_row.serialized_inventory_id
    and device.availability_status = 'reserved'
    and device.transfer_state is null and device.custody_state = 'none'
  for update;
  if not found
    or exists (
      select 1 from public.inventory_custody_items as item
      where item.shop_id = p_shop_id
        and item.serialized_inventory_id = previous_row.serialized_inventory_id
        and item.claim_active
    )
    or exists (
      select 1 from public.inventory_custody_incidents as incident
      join public.inventory_custody_items as item
        on item.shop_id = incident.shop_id and item.id = incident.item_id
      where item.shop_id = p_shop_id
        and item.serialized_inventory_id = previous_row.serialized_inventory_id
        and incident.status = 'open'
    )
  then
    raise exception 'A custody claim or unresolved incident prevents follow-up repair.'
      using errcode = '23514';
  end if;
  select balance.* into balance_row from public.inventory_balances as balance
  where balance.shop_id = p_shop_id and balance.branch_id = previous_row.branch_id
    and balance.variant_id = device_row.variant_id
    and balance.valuation_status = device_row.valuation_status
  for update;
  if not found or balance_row.reserved_repair_qty < 1 then
    raise exception 'The unrepairable device repair reservation is missing.'
      using errcode = '23514';
  end if;

  update public.repair_jobs
  set status = 'closed', closure_reason = 'Follow-up repair handed off: ' || reason_value,
      closed_by = actor.actor_id, closed_at = clock_timestamp(),
      device_claim_active = false, version = version + 1,
      updated_at = clock_timestamp(), updated_by = actor.actor_id
  where shop_id = p_shop_id and id = previous_row.id;
  insert into public.repair_jobs (
    id, shop_id, branch_id, serialized_inventory_id, follow_up_from_job_id,
    ticket_reference, reported_fault, intake_condition,
    expected_completion_at, warranty_evidence, status, device_claim_active,
    created_by, updated_by
  ) values (
    new_job_id, p_shop_id, previous_row.branch_id,
    previous_row.serialized_inventory_id, previous_row.id,
    ticket_value, fault_value, condition_value,
    p_expected_completion_at, previous_row.warranty_evidence,
    'open', true, actor.actor_id, actor.actor_id
  );
  -- The existing reserved_repair_qty remains one throughout this transaction.
  -- No available quantity is ever released during a follow-up handoff.
  perform private.record_repair_event(
    previous_event_id, p_shop_id, previous_row.branch_id, previous_row.id,
    operation.operation_id, 0, 'follow_up_handoff', 'unrepairable', 'closed',
    actor.actor_id, jsonb_build_object(
      'follow_up_job_id', new_job_id, 'reason', reason_value,
      'repair_reservation_transferred', true
    )
  );
  perform private.record_repair_event(
    new_event_id, p_shop_id, previous_row.branch_id, new_job_id,
    operation.operation_id, 1, 'follow_up_handoff', null, 'open',
    actor.actor_id, jsonb_build_object(
      'previous_job_id', previous_row.id, 'reason', reason_value,
      'repair_reservation_retained', true
    )
  );
  return new_job_id;
end;
$function$;

create or replace function public.request_repair_custody(
  p_shop_id uuid,
  p_repair_job_id uuid,
  p_expected_version bigint,
  p_external_custodian_name text,
  p_external_custodian_contact text,
  p_expected_return_at timestamptz,
  p_reason text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  job_row public.repair_jobs%rowtype;
  actor record;
  currency_record record;
  repair_operation record;
  custody_operation record;
  case_id uuid := gen_random_uuid();
  item_id uuid := gen_random_uuid();
  repair_event_id uuid := gen_random_uuid();
  case_reference text;
  name_value text := nullif(btrim(p_external_custodian_name), '');
  contact_value text := nullif(btrim(p_external_custodian_contact), '');
  reason_value text := nullif(btrim(p_reason), '');
  request_payload jsonb;
  custody_payload jsonb;
  device_row public.serialized_inventory%rowtype;
begin
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_repair_job_id;
  if not found then raise exception 'Repair job not found.' using errcode = '22023'; end if;
  select * into actor from private.assert_repair_access(p_shop_id, job_row.branch_id, 'write');
  select * into actor from private.assert_inventory_custody_access(
    p_shop_id, job_row.branch_id, 'request'
  );
  select * into currency_record
  from private.lock_inventory_transfer_currency(p_shop_id);
  if p_expected_version is null or p_expected_version < 1
    or name_value is null or char_length(name_value) > 200
    or char_length(coalesce(contact_value, '')) > 300
    or reason_value is null or char_length(reason_value) > 1000
  then
    raise exception 'Repair custody requires a current version, external custodian, and reason.'
      using errcode = '22023';
  end if;
  request_payload := jsonb_build_object(
    'job_id', p_repair_job_id, 'expected_version', p_expected_version,
    'external_custodian_name', name_value,
    'external_custodian_contact', contact_value,
    'expected_return_at', p_expected_return_at, 'reason', reason_value
  );
  case_reference := 'CUS-' || upper(substr(replace(case_id::text, '-', ''), 1, 12));
  custody_payload := jsonb_build_object(
    'shop_id', p_shop_id, 'branch_id', job_row.branch_id,
    'purpose', 'Repair job ' || job_row.ticket_reference,
    'reason', reason_value,
    'items', jsonb_build_array(jsonb_build_object(
      'serialized_inventory_id', job_row.serialized_inventory_id,
      'custodian_type', 'external', 'custodian_user_id', null,
      'custodian_name', name_value, 'custodian_contact', contact_value,
      'expected_return_at', p_expected_return_at
    ))
  );
  select * into repair_operation from private.claim_repair_operation(
    p_shop_id, job_row.branch_id, actor.actor_id, p_idempotency_key,
    'custody_request', request_payload, p_repair_job_id,
    repair_event_id, case_id
  );
  if repair_operation.replayed then
    return repair_operation.result_custody_case_id;
  end if;

  lock table public.products in row share mode;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stockpilot:device-claim:' || p_shop_id::text, 0)
  );
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = p_repair_job_id
  for update;
  if job_row.version <> p_expected_version or not job_row.device_claim_active
    or job_row.status not in ('in_progress', 'awaiting_parts')
  then
    raise exception 'Repair job changed or is not ready for external custody.'
      using errcode = '40001';
  end if;
  select device.* into device_row from public.serialized_inventory as device
  where device.shop_id = p_shop_id and device.branch_id = job_row.branch_id
    and device.id = job_row.serialized_inventory_id
    and device.availability_status = 'reserved'
    and device.transfer_state is null and device.custody_state = 'none'
    and device.valuation_status in ('known_cost', 'unknown_cost')
  for update;
  if not found or exists (
    select 1 from public.inventory_custody_items as item
    where item.shop_id = p_shop_id
      and item.serialized_inventory_id = job_row.serialized_inventory_id
      and item.claim_active
  ) or exists (
    select 1 from public.inventory_custody_incidents as incident
    join public.inventory_custody_items as item
      on item.shop_id = incident.shop_id and item.id = incident.item_id
    where item.shop_id = p_shop_id
      and item.serialized_inventory_id = job_row.serialized_inventory_id
      and incident.status = 'open'
  ) then
    raise exception 'The repair device has conflicting custody or incident state.'
      using errcode = '23514';
  end if;

  select * into custody_operation
  from private.claim_inventory_custody_operation(
    p_shop_id, job_row.branch_id, actor.actor_id, p_idempotency_key,
    'custody_request', custody_payload, case_id, null,
    currency_record.currency_code, currency_record.currency_version
  );
  if custody_operation.replayed then
    raise exception 'Repair custody idempotency state is inconsistent.'
      using errcode = '40001';
  end if;
  insert into public.inventory_custody_cases (
    id, shop_id, branch_id, case_reference, purpose, reason, status, version,
    requested_by, requested_at
  ) values (
    case_id, p_shop_id, job_row.branch_id, case_reference,
    'Repair job ' || job_row.ticket_reference, reason_value,
    'requested', 1, actor.actor_id, clock_timestamp()
  );
  insert into public.inventory_custody_items (
    id, shop_id, branch_id, case_id, line_number, serialized_inventory_id,
    custodian_type, custodian_name_snapshot, custodian_contact_snapshot,
    expected_return_at, state, claim_active
  ) values (
    item_id, p_shop_id, job_row.branch_id, case_id, 1,
    job_row.serialized_inventory_id, 'external', name_value,
    contact_value, p_expected_return_at, 'requested', true
  );
  insert into public.repair_job_custody_episodes (
    shop_id, branch_id, repair_job_id, custody_case_id,
    custody_item_id, serialized_inventory_id, linked_by
  ) values (
    p_shop_id, job_row.branch_id, job_row.id, case_id,
    item_id, job_row.serialized_inventory_id, actor.actor_id
  );
  update public.repair_jobs
  set version = version + 1, updated_at = clock_timestamp(),
      updated_by = actor.actor_id
  where shop_id = p_shop_id and id = job_row.id;
  perform private.record_inventory_custody_event(
    p_shop_id, job_row.branch_id, case_id, item_id, null,
    custody_operation.operation_id, 1, 'item_requested', null, 'requested',
    actor.actor_id, jsonb_build_object(
      'serialized_inventory_id', job_row.serialized_inventory_id,
      'custodian_type', 'external', 'custodian_name', name_value,
      'custodian_contact', contact_value,
      'expected_return_at', p_expected_return_at,
      'repair_job_id', job_row.id
    )
  );
  perform private.record_inventory_custody_event(
    p_shop_id, job_row.branch_id, case_id, null, null,
    custody_operation.operation_id, 0, 'requested', null, 'requested',
    actor.actor_id, jsonb_build_object(
      'case_reference', case_reference, 'purpose', 'Repair job ' || job_row.ticket_reference,
      'item_count', 1, 'repair_job_id', job_row.id
    )
  );
  perform private.record_repair_event(
    repair_event_id, p_shop_id, job_row.branch_id, job_row.id,
    repair_operation.operation_id, 0, 'custody_requested', job_row.status,
    job_row.status, actor.actor_id,
    jsonb_build_object('custody_case_id', case_id, 'custody_item_id', item_id)
  );
  return case_id;
end;
$function$;

create or replace function private.approve_repair_linked_custody(
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
  item_row public.inventory_custody_items%rowtype;
  job_row public.repair_jobs%rowtype;
  device_row public.serialized_inventory%rowtype;
  balance_row public.inventory_balances%rowtype;
  actor record;
  currency_record record;
  operation record;
  payload jsonb;
  repair_job_id uuid;
begin
  select custody_case.* into case_row
  from public.inventory_custody_cases as custody_case
  where custody_case.shop_id = p_shop_id and custody_case.id = p_case_id;
  if not found then raise exception 'Custody case not found.' using errcode = '22023'; end if;
  select * into actor from private.assert_inventory_custody_access(
    p_shop_id, case_row.branch_id, 'approve'
  );
  select * into currency_record
  from private.lock_inventory_transfer_currency(p_shop_id);
  if p_expected_version is null or p_expected_version < 1 then
    raise exception 'A positive custody case version is required.' using errcode = '22023';
  end if;
  payload := jsonb_build_object(
    'case_id', p_case_id, 'expected_version', p_expected_version
  );
  select * into operation from private.claim_inventory_custody_operation(
    p_shop_id, case_row.branch_id, actor.actor_id, p_idempotency_key,
    'custody_approval', payload, p_case_id, null,
    currency_record.currency_code, currency_record.currency_version
  );
  if operation.replayed then return operation.result_case_id; end if;
  lock table public.products in row share mode;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stockpilot:device-claim:' || p_shop_id::text, 0)
  );
  select episode.repair_job_id into repair_job_id
  from public.repair_job_custody_episodes as episode
  where episode.shop_id = p_shop_id and episode.custody_case_id = p_case_id
  limit 1;
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = repair_job_id
  for update;
  select custody_case.* into case_row
  from public.inventory_custody_cases as custody_case
  where custody_case.shop_id = p_shop_id and custody_case.id = p_case_id
  for update;
  if case_row.status <> 'requested' or case_row.version <> p_expected_version
    or not job_row.device_claim_active
  then
    raise exception 'Repair custody request changed or its repair hold is no longer active.'
      using errcode = '40001';
  end if;
  select item.* into item_row
  from public.inventory_custody_items as item
  where item.shop_id = p_shop_id and item.case_id = p_case_id
  for update;
  if not found or item_row.state <> 'requested' or not item_row.claim_active
    or (select count(*) from public.inventory_custody_items as item
      where item.shop_id = p_shop_id and item.case_id = p_case_id) <> 1
  then
    raise exception 'Repair-linked custody must contain exactly one requested device.'
      using errcode = '23514';
  end if;
  select device.* into device_row
  from public.serialized_inventory as device
  where device.shop_id = p_shop_id and device.branch_id = case_row.branch_id
    and device.id = item_row.serialized_inventory_id
    and device.availability_status = 'reserved'
    and device.transfer_state is null and device.custody_state = 'none'
    and device.valuation_status in ('known_cost', 'unknown_cost')
  for update;
  if not found or device_row.id is distinct from job_row.serialized_inventory_id
    or job_row.branch_id is distinct from case_row.branch_id
  then
    raise exception 'Repair custody device identity or state no longer matches.'
      using errcode = '23514';
  end if;
  if exists (
    select 1 from public.inventory_transfer_lines as transfer_line
    where transfer_line.shop_id = p_shop_id
      and transfer_line.serialized_inventory_id = device_row.id
      and transfer_line.claim_active
  ) then
    raise exception 'A device claimed by a transfer cannot enter repair custody.'
      using errcode = '23514';
  end if;
  select balance.* into balance_row
  from public.inventory_balances as balance
  where balance.shop_id = p_shop_id and balance.branch_id = case_row.branch_id
    and balance.variant_id = device_row.variant_id
    and balance.valuation_status = device_row.valuation_status
  for update;
  if not found or balance_row.reserved_repair_qty < 1 then
    raise exception 'Repair reservation is missing before custody approval.'
      using errcode = '23514';
  end if;
  update public.inventory_balances
  set reserved_repair_qty = reserved_repair_qty - 1,
      reserved_custody_qty = reserved_custody_qty + 1,
      updated_at = clock_timestamp(), updated_by = actor.actor_id
  where shop_id = p_shop_id and id = balance_row.id;
  update public.inventory_custody_items
  set state = 'approved', approved_by = actor.actor_id,
      approved_at = clock_timestamp(), version = version + 1,
      updated_at = clock_timestamp()
  where shop_id = p_shop_id and id = item_row.id;
  update public.serialized_inventory
  set availability_status = 'reserved', custody_state = 'approved',
      updated_at = clock_timestamp(), updated_by = actor.actor_id
  where shop_id = p_shop_id and id = device_row.id;
  update public.inventory_custody_cases
  set status = 'approved', version = version + 1,
      approved_by = actor.actor_id, approved_at = clock_timestamp(),
      updated_at = clock_timestamp()
  where shop_id = p_shop_id and id = p_case_id;
  perform private.record_inventory_custody_event(
    p_shop_id, case_row.branch_id, p_case_id, item_row.id, null,
    operation.operation_id, 1, 'item_approved', 'requested', 'approved',
    actor.actor_id, jsonb_build_object(
      'serialized_inventory_id', device_row.id, 'reserved_qty', 1,
      'reservation_transferred_from_repair', true,
      'valuation_status', device_row.valuation_status
    )
  );
  perform private.record_inventory_custody_event(
    p_shop_id, case_row.branch_id, p_case_id, null, null,
    operation.operation_id, 0, 'approved', 'requested', 'approved',
    actor.actor_id, jsonb_build_object('item_count', 1, 'repair_linked', true)
  );
  return p_case_id;
end;
$function$;

alter function public.approve_inventory_custody(uuid, uuid, bigint, text)
  rename to approve_inventory_custody_phase3da;
alter function public.cancel_inventory_custody(uuid, uuid, bigint, text, text)
  rename to cancel_inventory_custody_phase3da;
alter function public.return_inventory_custody(uuid, uuid, bigint, jsonb, text)
  rename to return_inventory_custody_phase3da;
alter function public.report_custody_incident(
  uuid, uuid, uuid, bigint, text, text, jsonb, text
) rename to report_custody_incident_phase3da;
alter function public.resolve_custody_incident(
  uuid, uuid, bigint, bigint, text, jsonb, text
) rename to resolve_custody_incident_phase3da;

revoke all on function public.approve_inventory_custody_phase3da(uuid, uuid, bigint, text)
  from public, anon, authenticated, service_role;
revoke all on function public.cancel_inventory_custody_phase3da(uuid, uuid, bigint, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.return_inventory_custody_phase3da(uuid, uuid, bigint, jsonb, text)
  from public, anon, authenticated, service_role;
revoke all on function public.report_custody_incident_phase3da(
  uuid, uuid, uuid, bigint, text, text, jsonb, text
) from public, anon, authenticated, service_role;
revoke all on function public.resolve_custody_incident_phase3da(
  uuid, uuid, bigint, bigint, text, jsonb, text
) from public, anon, authenticated, service_role;

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
begin
  if exists (
    select 1 from public.repair_job_custody_episodes as episode
    where episode.shop_id = p_shop_id and episode.custody_case_id = p_case_id
  ) then
    return private.approve_repair_linked_custody(
      p_shop_id, p_case_id, p_expected_version, p_idempotency_key
    );
  end if;
  return public.approve_inventory_custody_phase3da(
    p_shop_id, p_case_id, p_expected_version, p_idempotency_key
  );
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
  item_id_value uuid;
  job_id_value uuid;
  job_row public.repair_jobs%rowtype;
  actor record;
  currency_record record;
  case_id_value uuid;
  source_event_id uuid;
  balance_row public.inventory_balances%rowtype;
  device_row public.serialized_inventory%rowtype;
  open_incident boolean;
  operation_actor uuid := (select auth.uid());
begin
  if jsonb_typeof(p_returns) = 'array' then
    select item.id, episode.repair_job_id
      into item_id_value, job_id_value
    from jsonb_array_elements(p_returns) as requested(value)
    join public.inventory_custody_items as item
      on item.shop_id = p_shop_id and item.case_id = p_case_id
     and item.id::text = lower(requested.value ->> 'item_id')
    join public.repair_job_custody_episodes as episode
      on episode.shop_id = item.shop_id and episode.custody_item_id = item.id
    limit 1;
  end if;
  if job_id_value is null then
    return public.return_inventory_custody_phase3da(
      p_shop_id, p_case_id, p_expected_version, p_returns, p_idempotency_key
    );
  end if;
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = job_id_value;
  if not found then raise exception 'Linked repair job not found.' using errcode = '23503'; end if;
  select * into actor from private.assert_repair_access(
    p_shop_id, job_row.branch_id, 'write'
  );
  select * into currency_record
  from private.lock_inventory_transfer_currency(p_shop_id);
  lock table public.products in row share mode;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stockpilot:device-claim:' || p_shop_id::text, 0)
  );
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = job_id_value
  for update;
  select event.id into source_event_id
  from public.inventory_custody_events as event
  join public.inventory_operations as operation
    on operation.shop_id = event.shop_id and operation.id = event.operation_id
  where event.shop_id = p_shop_id and event.case_id = p_case_id
    and event.item_id = item_id_value and event.event_type = 'item_returned'
    and operation.actor_id = operation_actor
    and operation.idempotency_key = btrim(p_idempotency_key)
    and exists (
      select 1 from public.repair_job_events as repair_event
      where repair_event.shop_id = event.shop_id
        and repair_event.source_custody_event_id = event.id
        and repair_event.event_line_number = 1
        and repair_event.event_type = 'repair_hold_retained'
    )
  order by event.occurred_at desc, event.id desc
  limit 1;
  if source_event_id is not null then
    return public.return_inventory_custody_phase3da(
      p_shop_id, p_case_id, p_expected_version, p_returns, p_idempotency_key
    );
  end if;
  if not job_row.device_claim_active
    or job_row.serialized_inventory_id is null
  then
    raise exception 'Repair-linked custody cannot return to an inactive repair job.'
      using errcode = '23514';
  end if;
  select * into case_id_value
  from public.return_inventory_custody_phase3da(
    p_shop_id, p_case_id, p_expected_version, p_returns, p_idempotency_key
  );
  select event.id into source_event_id
  from public.inventory_custody_events as event
  join public.inventory_operations as operation
    on operation.shop_id = event.shop_id and operation.id = event.operation_id
  where event.shop_id = p_shop_id and event.case_id = p_case_id
    and event.item_id = item_id_value and event.event_type = 'item_returned'
    and operation.actor_id = operation_actor
    and operation.idempotency_key = btrim(p_idempotency_key)
  order by event.occurred_at desc, event.id desc
  limit 1;
  if source_event_id is null then
    raise exception 'Custody return evidence could not be found for the repair hold.'
      using errcode = '23514';
  end if;
  if exists (
    select 1 from public.repair_job_events as event
    where event.shop_id = p_shop_id
      and event.source_custody_event_id = source_event_id
      and event.event_line_number = 1
  ) then
    return case_id_value;
  end if;
  select exists (
    select 1 from public.inventory_custody_incidents as incident
    where incident.shop_id = p_shop_id
      and incident.item_id = item_id_value and incident.status = 'open'
  ) into open_incident;
  select device.* into device_row
  from public.serialized_inventory as device
  where device.shop_id = p_shop_id
    and device.id = job_row.serialized_inventory_id
    and device.branch_id = job_row.branch_id
  for update;
  if not found or device_row.custody_state not in ('none', 'returned_quarantine') then
    raise exception 'Returned repair device is not in a valid physical state.'
      using errcode = '23514';
  end if;
  if not open_incident then
    select balance.* into balance_row
    from public.inventory_balances as balance
    where balance.shop_id = p_shop_id and balance.branch_id = job_row.branch_id
      and balance.variant_id = device_row.variant_id
      and balance.valuation_status = device_row.valuation_status
    for update;
    if not found or balance_row.available_qty < 1 then
      raise exception 'Returned repair device availability cannot be transferred to repair.'
        using errcode = '23514';
    end if;
    update public.inventory_balances
    set available_qty = available_qty - 1,
        reserved_repair_qty = reserved_repair_qty + 1,
        updated_at = clock_timestamp(), updated_by = actor.actor_id
    where shop_id = p_shop_id and id = balance_row.id;
    update public.serialized_inventory
    set availability_status = 'reserved', custody_state = 'none',
        updated_at = clock_timestamp(), updated_by = actor.actor_id
    where shop_id = p_shop_id and id = device_row.id;
  end if;
  update public.repair_jobs
  set status = 'returned_pending_inspection', version = version + 1,
      updated_at = clock_timestamp(), updated_by = actor.actor_id
  where shop_id = p_shop_id and id = job_row.id;
  insert into public.repair_job_events (
    shop_id, branch_id, repair_job_id, source_custody_event_id,
    event_line_number, event_type, state_before, state_after, actor_id, event_data
  ) values (
    p_shop_id, job_row.branch_id, job_row.id, source_event_id,
    1, 'repair_hold_retained', job_row.status, 'returned_pending_inspection',
    actor.actor_id, jsonb_build_object(
      'open_incident', open_incident,
      'repair_reservation_retained', not open_incident,
      'custody_quarantine_retained', open_incident,
      'available_delta_after_return', 0
    )
  );
  return case_id_value;
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
  job_id_value uuid;
  job_row public.repair_jobs%rowtype;
  actor record;
  result_case_id uuid;
  source_event_id uuid;
  balance_row public.inventory_balances%rowtype;
  device_row public.serialized_inventory%rowtype;
  operation_actor uuid := (select auth.uid());
begin
  select episode.repair_job_id
    into job_id_value
  from public.repair_job_custody_episodes as episode
  where episode.shop_id = p_shop_id and episode.custody_case_id = p_case_id
  limit 1;
  if job_id_value is null then
    return public.cancel_inventory_custody_phase3da(
      p_shop_id, p_case_id, p_expected_version,
      p_cancellation_reason, p_idempotency_key
    );
  end if;
  return private.cancel_repair_linked_custody(
    p_shop_id, p_case_id, p_expected_version,
    p_cancellation_reason, p_idempotency_key
  );
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
  job_row public.repair_jobs%rowtype;
  actor record;
  currency_record record;
begin
  select job.* into job_row
  from public.repair_job_custody_episodes as episode
  join public.repair_jobs as job
    on job.shop_id = episode.shop_id and job.id = episode.repair_job_id
  where episode.shop_id = p_shop_id and episode.custody_case_id = p_case_id
    and episode.custody_item_id = p_item_id;
  if not found then
    return public.report_custody_incident_phase3da(
      p_shop_id, p_case_id, p_item_id, p_expected_case_version,
      p_incident_type, p_report, p_evidence, p_idempotency_key
    );
  end if;
  select * into actor from private.assert_repair_access(
    p_shop_id, job_row.branch_id, 'write'
  );
  select * into currency_record
  from private.lock_inventory_transfer_currency(p_shop_id);
  lock table public.products in row share mode;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stockpilot:device-claim:' || p_shop_id::text, 0)
  );
  perform 1 from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = job_row.id
  for update;
  return public.report_custody_incident_phase3da(
    p_shop_id, p_case_id, p_item_id, p_expected_case_version,
    p_incident_type, p_report, p_evidence, p_idempotency_key
  );
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
  job_row public.repair_jobs%rowtype;
  actor record;
  item_row public.inventory_custody_items%rowtype;
  device_row public.serialized_inventory%rowtype;
  balance_row public.inventory_balances%rowtype;
  source_event_id uuid;
  result_incident_id uuid;
  currency_record record;
  operation_actor uuid := (select auth.uid());
  open_incidents integer;
begin
  select job.* into job_row
  from public.inventory_custody_incidents as incident
  join public.repair_job_custody_episodes as episode
    on episode.shop_id = incident.shop_id and episode.custody_item_id = incident.item_id
  join public.repair_jobs as job
    on job.shop_id = episode.shop_id and job.id = episode.repair_job_id
  where incident.shop_id = p_shop_id and incident.id = p_incident_id;
  if not found then
    return public.resolve_custody_incident_phase3da(
      p_shop_id, p_incident_id, p_expected_case_version,
      p_expected_incident_version, p_resolution,
      p_resolution_evidence, p_idempotency_key
    );
  end if;
  select * into actor from private.assert_repair_access(
    p_shop_id, job_row.branch_id, 'admin'
  );
  select * into currency_record
  from private.lock_inventory_transfer_currency(p_shop_id);
  lock table public.products in row share mode;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stockpilot:device-claim:' || p_shop_id::text, 0)
  );
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = job_row.id
  for update;
  result_incident_id := public.resolve_custody_incident_phase3da(
    p_shop_id, p_incident_id, p_expected_case_version,
    p_expected_incident_version, p_resolution,
    p_resolution_evidence, p_idempotency_key
  );
  select event.id into source_event_id
  from public.inventory_custody_events as event
  join public.inventory_operations as operation
    on operation.shop_id = event.shop_id and operation.id = event.operation_id
  where event.shop_id = p_shop_id and event.incident_id = p_incident_id
    and event.event_type = 'incident_resolved'
    and operation.actor_id = operation_actor
    and operation.idempotency_key = btrim(p_idempotency_key)
  order by event.occurred_at desc, event.id desc
  limit 1;
  if source_event_id is null then
    raise exception 'Custody incident resolution evidence could not be found.'
      using errcode = '23514';
  end if;
  if exists (
    select 1 from public.repair_job_events as event
    where event.shop_id = p_shop_id
      and event.source_custody_event_id = source_event_id
      and event.event_line_number = 1
  ) then
    return result_incident_id;
  end if;
  select item.* into item_row
  from public.inventory_custody_incidents as incident
  join public.inventory_custody_items as item
    on item.shop_id = incident.shop_id and item.id = incident.item_id
  where incident.shop_id = p_shop_id and incident.id = p_incident_id;
  select count(*) into open_incidents
  from public.inventory_custody_incidents as incident
  where incident.shop_id = p_shop_id and incident.item_id = item_row.id
    and incident.status = 'open';
  if item_row.state = 'returned' and open_incidents = 0 then
    select device.* into device_row
    from public.serialized_inventory as device
    where device.shop_id = p_shop_id
      and device.id = item_row.serialized_inventory_id
      and device.branch_id = job_row.branch_id
      and device.custody_state = 'none'
    for update;
    if not found then
      raise exception 'Incident resolution did not return the repair device to the source branch.'
        using errcode = '23514';
    end if;
    select balance.* into balance_row
    from public.inventory_balances as balance
    where balance.shop_id = p_shop_id and balance.branch_id = job_row.branch_id
      and balance.variant_id = device_row.variant_id
      and balance.valuation_status = device_row.valuation_status
    for update;
    if not found or balance_row.available_qty < 1
    then
      raise exception 'Custody quarantine reservation cannot be transferred to active repair.'
        using errcode = '23514';
    end if;
    update public.inventory_balances
    set available_qty = available_qty - 1,
        reserved_repair_qty = reserved_repair_qty + 1,
        updated_at = clock_timestamp(), updated_by = actor.actor_id
    where shop_id = p_shop_id and id = balance_row.id;
    update public.serialized_inventory
    set availability_status = 'reserved', custody_state = 'none',
        updated_at = clock_timestamp(), updated_by = actor.actor_id
    where shop_id = p_shop_id and id = device_row.id;
  end if;
  insert into public.repair_job_events (
    shop_id, branch_id, repair_job_id, source_custody_event_id,
    event_line_number, event_type, state_before, state_after, actor_id, event_data
  ) values (
    p_shop_id, job_row.branch_id, job_row.id, source_event_id,
    1, 'repair_hold_retained', job_row.status, job_row.status,
    actor.actor_id, jsonb_build_object(
      'incident_id', p_incident_id,
      'open_incidents_remaining', open_incidents,
      'repair_reservation_restored', open_incidents = 0 and item_row.state = 'returned',
      'device_released_to_available', false
    )
  );
  return result_incident_id;
end;
$function$;

create or replace function private.cancel_repair_linked_custody(
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
  item_row public.inventory_custody_items%rowtype;
  job_row public.repair_jobs%rowtype;
  device_row public.serialized_inventory%rowtype;
  balance_row public.inventory_balances%rowtype;
  actor record;
  currency_record record;
  operation record;
  payload jsonb;
  source_event_id uuid;
  linked_job_id uuid;
begin
  select custody_case.* into case_row
  from public.inventory_custody_cases as custody_case
  where custody_case.shop_id = p_shop_id and custody_case.id = p_case_id;
  if not found then raise exception 'Custody case not found.' using errcode = '22023'; end if;
  select * into actor from private.assert_inventory_custody_access(
    p_shop_id, case_row.branch_id, 'cancel'
  );
  select * into currency_record
  from private.lock_inventory_transfer_currency(p_shop_id);
  if p_expected_version is null or p_expected_version < 1
    or nullif(btrim(p_cancellation_reason), '') is null
    or char_length(btrim(p_cancellation_reason)) > 1000
  then
    raise exception 'Custody cancellation requires a current version and reason.'
      using errcode = '22023';
  end if;
  payload := jsonb_build_object(
    'case_id', p_case_id, 'expected_version', p_expected_version,
    'reason', btrim(p_cancellation_reason)
  );
  select * into operation
  from private.claim_inventory_custody_operation(
    p_shop_id, case_row.branch_id, actor.actor_id, p_idempotency_key,
    'custody_cancellation', payload, p_case_id, null,
    currency_record.currency_code, currency_record.currency_version
  );
  if operation.replayed then return operation.result_case_id; end if;
  lock table public.products in row share mode;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stockpilot:device-claim:' || p_shop_id::text, 0)
  );
  select episode.repair_job_id into linked_job_id
  from public.repair_job_custody_episodes as episode
  where episode.shop_id = p_shop_id and episode.custody_case_id = p_case_id
  limit 1;
  select job.* into job_row from public.repair_jobs as job
  where job.shop_id = p_shop_id and job.id = linked_job_id
  for update;
  select custody_case.* into case_row
  from public.inventory_custody_cases as custody_case
  where custody_case.shop_id = p_shop_id and custody_case.id = p_case_id
  for update;
  if case_row.status not in ('requested', 'approved')
    or case_row.version <> p_expected_version or not job_row.device_claim_active
  then
    raise exception 'Repair custody can be cancelled only before handover and at its current version.'
      using errcode = '40001';
  end if;
  select item.* into item_row from public.inventory_custody_items as item
  where item.shop_id = p_shop_id and item.case_id = p_case_id
  for update;
  if not found or item_row.state not in ('requested', 'approved')
    or not item_row.claim_active
    or (select count(*) from public.inventory_custody_items as item
      where item.shop_id = p_shop_id and item.case_id = p_case_id) <> 1
  then
    raise exception 'Only the single outstanding repair custody item can be cancelled.'
      using errcode = '23514';
  end if;
  if actor.actor_role = 'inventory_staff'
    and (case_row.status <> 'requested' or case_row.requested_by <> actor.actor_id)
  then
    raise exception 'Inventory Staff may cancel only their own unapproved repair custody request.'
      using errcode = '42501';
  end if;
  select device.* into device_row
  from public.serialized_inventory as device
  where device.shop_id = p_shop_id and device.branch_id = case_row.branch_id
    and device.id = item_row.serialized_inventory_id
    and device.availability_status = 'reserved'
    and device.transfer_state is null
    and device.custody_state = case
      when item_row.state = 'requested' then 'none' else 'approved' end
  for update;
  if not found or device_row.id is distinct from job_row.serialized_inventory_id then
    raise exception 'Repair custody device state no longer matches its repair reservation.'
      using errcode = '23514';
  end if;
  select balance.* into balance_row
  from public.inventory_balances as balance
  where balance.shop_id = p_shop_id and balance.branch_id = case_row.branch_id
    and balance.variant_id = device_row.variant_id
    and balance.valuation_status = device_row.valuation_status
  for update;
  if not found then
    raise exception 'Repair custody branch balance is missing.'
      using errcode = '23514';
  end if;
  if item_row.state = 'approved' then
    if balance_row.reserved_custody_qty < 1 then
      raise exception 'Approved repair custody reservation is missing.'
        using errcode = '23514';
    end if;
    update public.inventory_balances
    set reserved_custody_qty = reserved_custody_qty - 1,
        reserved_repair_qty = reserved_repair_qty + 1,
        updated_at = clock_timestamp(), updated_by = actor.actor_id
    where shop_id = p_shop_id and id = balance_row.id;
  elsif balance_row.reserved_repair_qty < 1 then
    raise exception 'Requested repair custody has lost its repair reservation.'
      using errcode = '23514';
  end if;
  update public.inventory_custody_items
  set state = 'cancelled', claim_active = false,
      cancelled_by = actor.actor_id, cancelled_at = clock_timestamp(),
      version = version + 1, updated_at = clock_timestamp()
  where shop_id = p_shop_id and id = item_row.id;
  update public.serialized_inventory
  set availability_status = 'reserved', custody_state = 'none',
      updated_at = clock_timestamp(), updated_by = actor.actor_id
  where shop_id = p_shop_id and id = device_row.id;
  update public.inventory_custody_cases
  set status = 'cancelled', version = version + 1,
      cancelled_by = actor.actor_id, cancelled_at = clock_timestamp(),
      completed_at = clock_timestamp(), updated_at = clock_timestamp()
  where shop_id = p_shop_id and id = p_case_id;
  perform private.record_inventory_custody_event(
    p_shop_id, case_row.branch_id, p_case_id, item_row.id, null,
    operation.operation_id, 1, 'item_cancelled', item_row.state, 'cancelled',
    actor.actor_id, jsonb_build_object(
      'reason', btrim(p_cancellation_reason),
      'repair_reservation_retained', true
    )
  );
  perform private.record_inventory_custody_event(
    p_shop_id, case_row.branch_id, p_case_id, null, null,
    operation.operation_id, 0, 'cancelled', case_row.status, 'cancelled',
    actor.actor_id, jsonb_build_object(
      'reason', btrim(p_cancellation_reason), 'item_count', 1
    )
  );
  select event.id into source_event_id
  from public.inventory_custody_events as event
  where event.shop_id = p_shop_id and event.operation_id = operation.operation_id
    and event.case_id = p_case_id and event.item_id = item_row.id
    and event.event_type = 'item_cancelled'
  limit 1;
  insert into public.repair_job_events (
    shop_id, branch_id, repair_job_id, source_custody_event_id,
    event_line_number, event_type, state_before, state_after, actor_id, event_data
  ) values (
    p_shop_id, job_row.branch_id, job_row.id, source_event_id,
    1, 'repair_hold_retained', job_row.status, job_row.status,
    actor.actor_id, jsonb_build_object('custody_cancelled', true)
  );
  return p_case_id;
end;
$function$;

revoke all on function private.approve_repair_linked_custody(uuid, uuid, bigint, text)
  from public, anon, authenticated, service_role;
revoke all on function private.cancel_repair_linked_custody(
  uuid, uuid, bigint, text, text
) from public, anon, authenticated, service_role;

alter table public.repair_jobs enable row level security;
alter table public.repair_operations enable row level security;
alter table public.repair_job_events enable row level security;
alter table public.repair_job_custody_episodes enable row level security;
alter table public.repair_cost_entries enable row level security;

revoke all on public.repair_jobs,
  public.repair_operations,
  public.repair_job_events,
  public.repair_job_custody_episodes,
  public.repair_cost_entries
  from public, anon, authenticated, service_role;

grant select on public.repair_jobs,
  public.repair_operations,
  public.repair_job_events,
  public.repair_job_custody_episodes,
  public.repair_cost_entries
  to service_role;
grant select on public.repair_jobs,
  public.repair_job_events,
  public.repair_job_custody_episodes,
  public.repair_cost_entries
  to authenticated;

create policy repair_jobs_read_authorized_branch
  on public.repair_jobs for select to authenticated
  using (
    private.is_active_shop_member(shop_id)
    and private.has_shop_role(
      shop_id, array['owner', 'manager', 'inventory_staff']::public.shop_role[]
    )
    and exists (
      select 1 from public.branches as branch
      where branch.shop_id = repair_jobs.shop_id
        and branch.id = repair_jobs.branch_id and branch.is_active
    )
    and (private.has_shop_role(shop_id, array['owner']::public.shop_role[])
      or private.can_access_branch(shop_id, branch_id))
  );

create policy repair_job_events_read_authorized_branch
  on public.repair_job_events for select to authenticated
  using (
    private.is_active_shop_member(shop_id)
    and private.has_shop_role(
      shop_id, array['owner', 'manager', 'inventory_staff']::public.shop_role[]
    )
    and exists (
      select 1 from public.branches as branch
      where branch.shop_id = repair_job_events.shop_id
        and branch.id = repair_job_events.branch_id and branch.is_active
    )
    and (private.has_shop_role(shop_id, array['owner']::public.shop_role[])
      or private.can_access_branch(shop_id, branch_id))
    and (
      event_type not in (
        'created', 'estimate_submitted', 'spending_approved', 'expense_recorded'
      )
      or private.has_shop_role(
        shop_id, array['owner', 'manager']::public.shop_role[]
      )
    )
  );

create policy repair_job_custody_episodes_read_authorized_branch
  on public.repair_job_custody_episodes for select to authenticated
  using (
    private.is_active_shop_member(shop_id)
    and private.has_shop_role(
      shop_id, array['owner', 'manager', 'inventory_staff']::public.shop_role[]
    )
    and exists (
      select 1 from public.branches as branch
      where branch.shop_id = repair_job_custody_episodes.shop_id
        and branch.id = repair_job_custody_episodes.branch_id and branch.is_active
    )
    and (private.has_shop_role(shop_id, array['owner']::public.shop_role[])
      or private.can_access_branch(shop_id, branch_id))
  );

create policy repair_cost_entries_read_authorized_branch
  on public.repair_cost_entries for select to authenticated
  using (
    private.is_active_shop_member(shop_id)
    and private.has_shop_role(
      shop_id, array['owner', 'manager']::public.shop_role[]
    )
    and exists (
      select 1 from public.branches as branch
      where branch.shop_id = repair_cost_entries.shop_id
        and branch.id = repair_cost_entries.branch_id and branch.is_active
    )
    and (private.has_shop_role(shop_id, array['owner']::public.shop_role[])
      or private.can_access_branch(shop_id, branch_id))
  );

revoke all on function public.create_repair_job(
  uuid, uuid, uuid, text, text, text, timestamptz, jsonb, text
) from public, anon, service_role;
revoke all on function public.assign_repair_technician(
  uuid, uuid, bigint, text, uuid, text, text, text, text
) from public, anon, service_role;
revoke all on function public.update_repair_diagnosis(
  uuid, uuid, bigint, text, text, jsonb, text
) from public, anon, service_role;
revoke all on function public.update_repair_progress(
  uuid, uuid, bigint, text, text, jsonb, text
) from public, anon, service_role;
revoke all on function public.submit_repair_estimate(
  uuid, uuid, bigint, numeric, char, jsonb, text, uuid, numeric, text,
  timestamptz, text, text
) from public, anon, service_role;
revoke all on function public.approve_repair_spend(
  uuid, uuid, bigint, numeric, char, text, jsonb, uuid, numeric, text,
  timestamptz, text, text
) from public, anon, service_role;
revoke all on function public.record_repair_expense(
  uuid, uuid, bigint, numeric, char, text, jsonb, text, uuid, numeric,
  text, timestamptz, text, uuid, text, text
) from public, anon, service_role;
revoke all on function public.complete_repair_job(uuid, uuid, bigint, jsonb, text)
  from public, anon, service_role;
revoke all on function public.mark_repair_unrepairable(
  uuid, uuid, bigint, text, jsonb, text
) from public, anon, service_role;
revoke all on function public.cancel_repair_job(uuid, uuid, bigint, text, text)
  from public, anon, service_role;
revoke all on function public.close_repair_job(uuid, uuid, bigint, text, text)
  from public, anon, service_role;
revoke all on function public.create_follow_up_repair(
  uuid, uuid, bigint, text, text, text, timestamptz, text, text
) from public, anon, service_role;
revoke all on function public.request_repair_custody(
  uuid, uuid, bigint, text, text, timestamptz, text, text
) from public, anon, service_role;
revoke all on function public.approve_inventory_custody(uuid, uuid, bigint, text)
  from public, anon, service_role;
revoke all on function public.cancel_inventory_custody(uuid, uuid, bigint, text, text)
  from public, anon, service_role;
revoke all on function public.return_inventory_custody(uuid, uuid, bigint, jsonb, text)
  from public, anon, service_role;
revoke all on function public.report_custody_incident(
  uuid, uuid, uuid, bigint, text, text, jsonb, text
) from public, anon, service_role;
revoke all on function public.resolve_custody_incident(
  uuid, uuid, bigint, bigint, text, jsonb, text
) from public, anon, service_role;

grant execute on function public.create_repair_job(
  uuid, uuid, uuid, text, text, text, timestamptz, jsonb, text
) to authenticated;
grant execute on function public.assign_repair_technician(
  uuid, uuid, bigint, text, uuid, text, text, text, text
) to authenticated;
grant execute on function public.update_repair_diagnosis(
  uuid, uuid, bigint, text, text, jsonb, text
) to authenticated;
grant execute on function public.update_repair_progress(
  uuid, uuid, bigint, text, text, jsonb, text
) to authenticated;
grant execute on function public.submit_repair_estimate(
  uuid, uuid, bigint, numeric, char, jsonb, text, uuid, numeric, text,
  timestamptz, text, text
) to authenticated;
grant execute on function public.approve_repair_spend(
  uuid, uuid, bigint, numeric, char, text, jsonb, uuid, numeric, text,
  timestamptz, text, text
) to authenticated;
grant execute on function public.record_repair_expense(
  uuid, uuid, bigint, numeric, char, text, jsonb, text, uuid, numeric,
  text, timestamptz, text, uuid, text, text
) to authenticated;
grant execute on function public.complete_repair_job(uuid, uuid, bigint, jsonb, text)
  to authenticated;
grant execute on function public.mark_repair_unrepairable(
  uuid, uuid, bigint, text, jsonb, text
) to authenticated;
grant execute on function public.cancel_repair_job(uuid, uuid, bigint, text, text)
  to authenticated;
grant execute on function public.close_repair_job(uuid, uuid, bigint, text, text)
  to authenticated;
grant execute on function public.create_follow_up_repair(
  uuid, uuid, bigint, text, text, text, timestamptz, text, text
) to authenticated;
grant execute on function public.request_repair_custody(
  uuid, uuid, bigint, text, text, timestamptz, text, text
) to authenticated;
grant execute on function public.approve_inventory_custody(uuid, uuid, bigint, text)
  to authenticated;
grant execute on function public.cancel_inventory_custody(uuid, uuid, bigint, text, text)
  to authenticated;
grant execute on function public.return_inventory_custody(uuid, uuid, bigint, jsonb, text)
  to authenticated;
grant execute on function public.report_custody_incident(
  uuid, uuid, uuid, bigint, text, text, jsonb, text
) to authenticated;
grant execute on function public.resolve_custody_incident(
  uuid, uuid, bigint, bigint, text, jsonb, text
) to authenticated;

comment on table public.repair_jobs is
  'Workflow records for repairs to shop-owned serialized devices; the device retains its original identity and valuation.';
comment on table public.repair_operations is
  'Immutable per-actor idempotency claims for repair RPCs, including canonical payloads and result references.';
comment on table public.repair_job_events is
  'Append-only repair lifecycle and custody-link evidence; it never posts accounting or inventory value.';
comment on table public.repair_job_custody_episodes is
  'Immutable links from one repair job to each authorized custody episode for the same serialized device.';
comment on table public.repair_cost_entries is
  'Append-only estimates, cumulative gross spending authorizations, expense evidence, warranty evidence, and explicit corrections; negative corrections reduce net evidence but never restore authorization, and no accounting postings are created.';
comment on column public.repair_jobs.completion_evidence is
  'Operational-only JSON with a strict key/string schema. Free-text values cannot reliably be screened for sensitive amounts or identifiers; users must not enter financial details here.';
comment on column public.inventory_balances.reserved_repair_qty is
  'Shop-owned units held for active repair work; excluded from available stock without changing on-hand quantity or carrying value.';

commit;
