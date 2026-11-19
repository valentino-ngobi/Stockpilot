create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create type public.shop_role as enum (
  'owner',
  'manager',
  'sales_staff',
  'inventory_staff'
);

create type public.membership_status as enum (
  'active',
  'suspended'
);

revoke all on type public.shop_role, public.membership_status
  from public, anon;
grant usage on type public.shop_role, public.membership_status
  to authenticated;

create table public.user_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_profiles_display_name_length
    check (char_length(display_name) <= 120)
);

create table public.shops (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint shops_name_length
    check (char_length(btrim(name)) between 1 and 120)
);

create table public.shop_memberships (
  shop_id uuid not null references public.shops (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role public.shop_role not null,
  status public.membership_status not null default 'active',
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (shop_id, user_id)
);

create index shop_memberships_user_shop_idx
  on public.shop_memberships (user_id, shop_id)
  where status = 'active';

create table public.branches (
  id uuid not null default gen_random_uuid(),
  shop_id uuid not null references public.shops (id) on delete cascade,
  name text not null,
  is_primary boolean not null default false,
  is_active boolean not null default true,
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (id),
  unique (shop_id, id),
  constraint branches_name_length
    check (char_length(btrim(name)) between 1 and 120)
);

create unique index branches_shop_normalized_name_idx
  on public.branches (shop_id, lower(btrim(name)));

create unique index branches_one_primary_per_shop_idx
  on public.branches (shop_id)
  where is_primary;

create index branches_shop_active_idx
  on public.branches (shop_id, is_active, name);

create table public.branch_memberships (
  shop_id uuid not null,
  branch_id uuid not null,
  user_id uuid not null,
  created_by uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (shop_id, branch_id, user_id),
  foreign key (shop_id, branch_id)
    references public.branches (shop_id, id) on delete cascade,
  foreign key (shop_id, user_id)
    references public.shop_memberships (shop_id, user_id) on delete cascade
);

create index branch_memberships_user_scope_idx
  on public.branch_memberships (user_id, shop_id, branch_id);

create or replace function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;

revoke all on function private.touch_updated_at()
  from public, anon, authenticated;

create trigger user_profiles_touch_updated_at
  before update on public.user_profiles
  for each row execute function private.touch_updated_at();
create trigger shops_touch_updated_at
  before update on public.shops
  for each row execute function private.touch_updated_at();
create trigger shop_memberships_touch_updated_at
  before update on public.shop_memberships
  for each row execute function private.touch_updated_at();
create trigger branches_touch_updated_at
  before update on public.branches
  for each row execute function private.touch_updated_at();

create or replace function private.is_active_shop_member(p_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.shop_memberships as membership
    where membership.shop_id = p_shop_id
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
  );
$function$;

create or replace function private.has_shop_role(
  p_shop_id uuid,
  p_roles public.shop_role[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.shop_memberships as membership
    where membership.shop_id = p_shop_id
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
      and membership.role = any (p_roles)
  );
$function$;

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
    from public.shop_memberships as membership
    where membership.shop_id = p_shop_id
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
      and (
        membership.role = 'owner'
        or exists (
          select 1
          from public.branch_memberships as branch_membership
          where branch_membership.shop_id = p_shop_id
            and branch_membership.branch_id = p_branch_id
            and branch_membership.user_id = membership.user_id
        )
      )
  );
$function$;

revoke all on function private.is_active_shop_member(uuid)
  from public, anon, authenticated;
revoke all on function private.has_shop_role(uuid, public.shop_role[])
  from public, anon, authenticated;
revoke all on function private.can_access_branch(uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.is_active_shop_member(uuid)
  to authenticated;
grant execute on function private.has_shop_role(uuid, public.shop_role[])
  to authenticated;
grant execute on function private.can_access_branch(uuid, uuid)
  to authenticated;

create or replace function private.handle_auth_user_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.user_profiles (user_id, display_name)
  values (
    new.id,
    coalesce(nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''), '')
  )
  on conflict (user_id) do nothing;

  return new;
end;
$function$;

revoke all on function private.handle_auth_user_created()
  from public, anon, authenticated;

create trigger on_auth_user_created_create_profile
  after insert on auth.users
  for each row execute function private.handle_auth_user_created();

create or replace function public.create_shop_for_current_user(p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  current_user_id uuid := (select auth.uid());
  created_shop_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication is required to create a shop.'
      using errcode = '42501';
  end if;

  if p_name is null or char_length(btrim(p_name)) not between 1 and 120 then
    raise exception 'Shop name must contain between 1 and 120 characters.'
      using errcode = '22023';
  end if;

  insert into public.user_profiles (user_id)
  values (current_user_id)
  on conflict (user_id) do nothing;

  insert into public.shops (name, created_by)
  values (btrim(p_name), current_user_id)
  returning id into created_shop_id;

  insert into public.shop_memberships (
    shop_id, user_id, role, status, created_by
  ) values (
    created_shop_id,
    current_user_id,
    'owner',
    'active',
    current_user_id
  );

  insert into public.branches (
    shop_id, name, is_primary, created_by
  ) values (
    created_shop_id,
    'Main branch',
    true,
    current_user_id
  );

  return created_shop_id;
end;
$function$;

create or replace function public.create_branch(
  p_shop_id uuid,
  p_name text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  current_user_id uuid := (select auth.uid());
  created_branch_id uuid;
begin
  if current_user_id is null
    or not private.has_shop_role(p_shop_id, array['owner']::public.shop_role[])
  then
    raise exception 'Only an owner of this shop can create branches.'
      using errcode = '42501';
  end if;

  if p_name is null or char_length(btrim(p_name)) not between 1 and 120 then
    raise exception 'Branch name must contain between 1 and 120 characters.'
      using errcode = '22023';
  end if;

  insert into public.branches (shop_id, name, created_by)
  values (p_shop_id, btrim(p_name), current_user_id)
  returning id into created_branch_id;

  return created_branch_id;
end;
$function$;

create or replace function public.owner_set_member_access(
  p_shop_id uuid,
  p_user_id uuid,
  p_role public.shop_role,
  p_branch_ids uuid[]
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
    raise exception 'Only an owner of this shop can assign member access.'
      using errcode = '42501';
  end if;

  if p_user_id is null or p_user_id = current_user_id then
    raise exception 'Owners cannot assign or change their own membership.'
      using errcode = '42501';
  end if;

  if p_role is null or p_role = 'owner' then
    raise exception 'This function cannot create or change owner memberships.'
      using errcode = '42501';
  end if;

  if not exists (select 1 from auth.users as auth_user where auth_user.id = p_user_id) then
    raise exception 'The target user must have a registered account.'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.shop_memberships as membership
    where membership.shop_id = p_shop_id
      and membership.user_id = p_user_id
      and membership.role = 'owner'
  ) then
    raise exception 'Owner memberships cannot be changed by this function.'
      using errcode = '42501';
  end if;

  if coalesce(cardinality(p_branch_ids), 0) = 0 then
    raise exception 'Assign the member to at least one active branch.'
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
    raise exception 'Every assigned branch must be active and belong to this shop.'
      using errcode = '22023';
  end if;

  insert into public.shop_memberships (
    shop_id, user_id, role, status, created_by
  ) values (
    p_shop_id, p_user_id, p_role, 'active', current_user_id
  )
  on conflict (shop_id, user_id) do update
  set role = excluded.role,
      status = 'active',
      updated_at = now();

  delete from public.branch_memberships
  where shop_id = p_shop_id and user_id = p_user_id;

  insert into public.branch_memberships (
    shop_id, branch_id, user_id, created_by
  )
  select p_shop_id, input_branch.branch_id, p_user_id, current_user_id
  from unnest(p_branch_ids) as input_branch(branch_id);
end;
$function$;

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

  delete from public.branch_memberships
  where shop_id = p_shop_id and user_id = p_user_id;
end;
$function$;

revoke all on function public.create_shop_for_current_user(text)
  from public, anon;
revoke all on function public.create_branch(uuid, text)
  from public, anon;
revoke all on function public.owner_set_member_access(
  uuid, uuid, public.shop_role, uuid[]
) from public, anon;
revoke all on function public.owner_suspend_shop_member(uuid, uuid)
  from public, anon;
grant execute on function public.create_shop_for_current_user(text)
  to authenticated;
grant execute on function public.create_branch(uuid, text)
  to authenticated;
grant execute on function public.owner_set_member_access(
  uuid, uuid, public.shop_role, uuid[]
) to authenticated;
grant execute on function public.owner_suspend_shop_member(uuid, uuid)
  to authenticated;

alter table public.user_profiles enable row level security;
alter table public.shops enable row level security;
alter table public.shop_memberships enable row level security;
alter table public.branches enable row level security;
alter table public.branch_memberships enable row level security;

revoke all on public.user_profiles, public.shops,
  public.shop_memberships, public.branches, public.branch_memberships
  from public, anon, authenticated;

grant select on public.user_profiles to authenticated;
grant update (display_name) on public.user_profiles to authenticated;
grant select on public.shops, public.shop_memberships,
  public.branches, public.branch_memberships to authenticated;
grant update (name) on public.shops to authenticated;
grant update (name, is_active) on public.branches to authenticated;

create policy user_profiles_select_self
  on public.user_profiles for select to authenticated
  using (user_id = (select auth.uid()));

create policy user_profiles_update_self
  on public.user_profiles for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy shops_select_member
  on public.shops for select to authenticated
  using (private.is_active_shop_member(id));

create policy shops_update_owner
  on public.shops for update to authenticated
  using (private.has_shop_role(id, array['owner']::public.shop_role[]))
  with check (private.has_shop_role(id, array['owner']::public.shop_role[]));

create policy shop_memberships_select_self_or_owner
  on public.shop_memberships for select to authenticated
  using (
    user_id = (select auth.uid())
    or private.has_shop_role(shop_id, array['owner']::public.shop_role[])
  );

create policy branches_select_assigned
  on public.branches for select to authenticated
  using (
    is_active
    and private.can_access_branch(shop_id, id)
  );

create policy branches_update_owner
  on public.branches for update to authenticated
  using (private.has_shop_role(shop_id, array['owner']::public.shop_role[]))
  with check (private.has_shop_role(shop_id, array['owner']::public.shop_role[]));

create policy branch_memberships_select_self_or_owner
  on public.branch_memberships for select to authenticated
  using (
    (user_id = (select auth.uid()) and private.is_active_shop_member(shop_id))
    or private.has_shop_role(shop_id, array['owner']::public.shop_role[])
  );
