-- Keep structured financial evidence out of repair records and events visible
-- to assigned Inventory Staff. Free-text notes remain operational data and
-- cannot reliably be screened for amounts entered as prose.
-- These constraints validate the new Phase 3D-B repair tables. The scans take
-- strong DDL locks; the early deployment should have small repair histories.
-- For a large populated deployment, preflight separately and stage constraint
-- validation during a measured maintenance window.

begin;

create or replace function private.is_valid_repair_warranty_evidence(
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
    and not exists (
      select 1
      from jsonb_object_keys(case
        when jsonb_typeof(p_evidence) = 'object' then p_evidence
        else '{}'::jsonb
      end) as evidence_key(key_name)
      where evidence_key.key_name not in (
        'coverage_status', 'provider', 'reference', 'valid_until',
        'device_condition', 'technician_notes'
      )
    )
    and not exists (
      select 1
      from jsonb_each(case
        when jsonb_typeof(p_evidence) = 'object' then p_evidence
        else '{}'::jsonb
      end) as evidence_entry(key_name, value)
      where jsonb_typeof(evidence_entry.value) <> 'string'
        or char_length(btrim(evidence_entry.value #>> '{}')) not between 1 and 2000
    );
$function$;

revoke all on function private.is_valid_repair_warranty_evidence(jsonb)
  from public, anon, authenticated, service_role;

do $migration$
declare
  invalid_job_ids text;
begin
  select string_agg(job.id::text, ', ' order by job.id)
    into invalid_job_ids
  from public.repair_jobs as job
  where private.is_valid_repair_warranty_evidence(job.warranty_evidence)
    is distinct from true;

  if invalid_job_ids is not null then
    raise exception
      'Repair warranty evidence needs review before privacy validation; invalid repair job IDs: %',
      invalid_job_ids;
  end if;
end;
$migration$;

alter table public.repair_jobs
  add constraint repair_jobs_warranty_evidence_privacy_check
  check (private.is_valid_repair_warranty_evidence(warranty_evidence));

do $migration$
declare
  invalid_event_ids text;
begin
  select string_agg(event.id::text, ', ' order by event.id)
    into invalid_event_ids
  from public.repair_job_events as event
  where event.event_type in ('diagnosis_updated', 'progress_updated')
    and not (
      event.event_data ? 'evidence'
      and (
        event.event_data -> 'evidence' = '{}'::jsonb
        or private.is_valid_repair_operational_evidence(
          event.event_data -> 'evidence'
        )
      )
    );

  if invalid_event_ids is not null then
    raise exception
      'Repair operational events need review before privacy validation; invalid event IDs: %',
      invalid_event_ids;
  end if;
end;
$migration$;

alter table public.repair_job_events
  add constraint repair_job_events_operational_evidence_privacy_check
  check (
    event_type not in ('diagnosis_updated', 'progress_updated')
    or (
      event_data ? 'evidence'
      and (
        event_data -> 'evidence' = '{}'::jsonb
        or private.is_valid_repair_operational_evidence(
          event_data -> 'evidence'
        )
      )
    )
  );

comment on column public.repair_jobs.warranty_evidence is
  'Flat warranty metadata only: coverage_status, provider, reference, valid_until, device_condition, and technician_notes. Free-text values may still contain sensitive data; do not enter financial amounts or private identifiers.';

comment on column public.repair_jobs.diagnosis is
  'Operational diagnosis narrative visible to authorized branch Inventory Staff; do not include financial amounts or private identifiers.';

comment on table public.repair_jobs is
  'Workflow records for shop-owned serialized-device repairs. Authorized branch Inventory Staff can read operational prose such as reported_fault, intake_condition, diagnosis, outcome_reason, cancellation_reason, and closure_reason; do not include financial amounts or private identifiers in those fields.';

comment on column public.repair_job_events.event_data is
  'Append-only lifecycle evidence. Diagnosis and progress evidence is restricted to the operational evidence schema; free-text notes may still contain sensitive details and must not include financial amounts.';

commit;
