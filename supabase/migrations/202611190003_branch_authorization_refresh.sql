create or replace function private.can_access_branch(
  p_shop_id uuid,
  p_branch_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.branches as branch
    join public.shop_memberships as membership
      on membership.shop_id = branch.shop_id
    where branch.shop_id = p_shop_id
      and branch.id = p_branch_id
      and branch.is_active
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
      and (
        membership.role = 'owner'
        or exists (
          select 1
          from public.branch_memberships as branch_membership
          where branch_membership.shop_id = branch.shop_id
            and branch_membership.branch_id = branch.id
            and branch_membership.user_id = membership.user_id
        )
      )
  );
$function$;

revoke all on function private.can_access_branch(uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.can_access_branch(uuid, uuid)
  to authenticated;

create or replace function private.notify_members_after_branch_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.is_active is distinct from old.is_active then
    update public.shop_memberships as membership
    set updated_at = now()
    where membership.shop_id = new.shop_id
      and membership.status = 'active'
      and (
        membership.role = 'owner'
        or exists (
          select 1
          from public.branch_memberships as branch_membership
          where branch_membership.shop_id = new.shop_id
            and branch_membership.branch_id = new.id
            and branch_membership.user_id = membership.user_id
        )
      );
  end if;

  return new;
end;
$function$;

revoke all on function private.notify_members_after_branch_status_change()
  from public, anon, authenticated;

create trigger branches_notify_authorization_change
  after update of is_active on public.branches
  for each row
  when (old.is_active is distinct from new.is_active)
  execute function private.notify_members_after_branch_status_change();

do $migration$
begin
  if not exists (
    select 1 from pg_catalog.pg_publication
    where pubname = 'supabase_realtime'
  ) then
    raise exception 'Supabase Realtime publication is required for authorization refresh.';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'shop_memberships'
  ) then
    execute 'alter publication supabase_realtime add table public.shop_memberships';
  end if;
end;
$migration$;
