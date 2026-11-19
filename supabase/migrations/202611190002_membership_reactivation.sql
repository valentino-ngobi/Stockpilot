create or replace function public.owner_suspend_shop_member(
  p_shop_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  current_user_id uuid := (select auth.uid());
begin
  if current_user_id is null
    or not private.has_shop_role(p_shop_id, array['owner']::public.shop_role[])
  then
    raise exception 'Only an owner of this shop can suspend a member.'
      using errcode = '42501';
  end if;

  if p_user_id is null or p_user_id = current_user_id then
    raise exception 'Owners cannot suspend their own membership.'
      using errcode = '42501';
  end if;

  update public.shop_memberships
  set status = 'suspended', updated_at = now()
  where shop_id = p_shop_id
    and user_id = p_user_id
    and role <> 'owner';

  if not found then
    raise exception 'Member was not found or is an owner.'
      using errcode = '42501';
  end if;

  -- Keep branch assignments so an authorized owner can restore the same access.
  -- RLS helpers require an active shop membership, so suspended users remain blocked.
end;
$function$;

create or replace function public.owner_reactivate_shop_member(
  p_shop_id uuid,
  p_user_id uuid,
  p_branch_ids uuid[] default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  current_user_id uuid := (select auth.uid());
  member_role public.shop_role;
  member_status public.membership_status;
begin
  if current_user_id is null
    or not private.has_shop_role(p_shop_id, array['owner']::public.shop_role[])
  then
    raise exception 'Only an owner of this shop can reactivate a member.'
      using errcode = '42501';
  end if;

  if p_user_id is null or p_user_id = current_user_id then
    raise exception 'Owners cannot reactivate their own membership.'
      using errcode = '42501';
  end if;

  select membership.role, membership.status
  into member_role, member_status
  from public.shop_memberships as membership
  where membership.shop_id = p_shop_id
    and membership.user_id = p_user_id
  for update;

  if not found or member_role = 'owner' or member_status <> 'suspended' then
    raise exception 'Suspended non-owner membership was not found in this shop.'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.branch_memberships as branch_membership
    where branch_membership.shop_id = p_shop_id
      and branch_membership.user_id = p_user_id
  ) then
    if coalesce(cardinality(p_branch_ids), 0) = 0 then
      raise exception 'No branch assignments are saved. Select the member''s branches before reactivation.'
        using errcode = '22023';
    end if;

    if cardinality(p_branch_ids) <> (
      select count(distinct branch_id)::integer
      from unnest(p_branch_ids) as input_branch(branch_id)
    ) then
      raise exception 'Branch assignments must not contain duplicates.'
        using errcode = '22023';
    end if;

    if exists (
      select 1
      from unnest(p_branch_ids) as input_branch(branch_id)
      left join public.branches as branch
        on branch.shop_id = p_shop_id
        and branch.id = input_branch.branch_id
        and branch.is_active
      where branch.id is null
    ) then
      raise exception 'Every restored branch must be active and belong to this shop.'
        using errcode = '22023';
    end if;

    insert into public.branch_memberships (
      shop_id, branch_id, user_id, created_by
    )
    select p_shop_id, input_branch.branch_id, p_user_id, current_user_id
    from unnest(p_branch_ids) as input_branch(branch_id);
  end if;

  update public.shop_memberships
  set status = 'active', updated_at = now()
  where shop_id = p_shop_id
    and user_id = p_user_id
    and role <> 'owner'
    and status = 'suspended';

  if not found then
    raise exception 'Suspended non-owner membership could not be reactivated.'
      using errcode = '42501';
  end if;
end;
$function$;

revoke all on function public.owner_reactivate_shop_member(uuid, uuid, uuid[])
  from public, anon;
grant execute on function public.owner_reactivate_shop_member(uuid, uuid, uuid[])
  to authenticated;
