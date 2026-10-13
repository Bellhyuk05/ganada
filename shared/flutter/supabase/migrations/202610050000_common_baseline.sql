-- 같이타(GachiTa) shared common baseline. Fresh projects only; no seed data.
begin;
create schema if not exists companion_private;
revoke all on schema companion_private from public, anon, authenticated;
grant usage on schema companion_private to authenticated, service_role;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (length(btrim(display_name)) > 0),
  created_at timestamptz not null default now()
);
create table if not exists public.rides (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references public.profiles(id) on delete restrict,
  origin_name text not null check (length(btrim(origin_name)) > 0),
  destination_name text not null check (length(btrim(destination_name)) > 0),
  condition_text text not null default '',
  capacity integer not null check (capacity > 0),
  departure_at timestamptz not null,
  departed_at timestamptz,
  ended_at timestamptz,
  status text not null default 'recruiting'
    check (status in ('recruiting', 'full', 'completed', 'cancelled'))
);
create index if not exists rides_host_idx on public.rides(host_id);

create table if not exists public.ride_memberships (
  ride_id uuid not null references public.rides(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'reject')),
  boarded_at timestamptz,
  no_show boolean not null default false,
  primary key (ride_id, user_id)
);
create index if not exists ride_memberships_user_idx on public.ride_memberships(user_id);

alter table public.profiles enable row level security;
alter table public.rides enable row level security;
alter table public.ride_memberships enable row level security;

revoke all on public.profiles, public.rides, public.ride_memberships
  from public, anon, authenticated;
grant select (id, display_name) on public.profiles to authenticated;
grant select on public.rides, public.ride_memberships to authenticated;
grant all on public.profiles, public.rides, public.ride_memberships to service_role;

-- Non-exposed helper avoids recursive membership RLS. It only returns a boolean.
create or replace function companion_private.can_read_ride(p_ride_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (
    select 1 from public.rides r where r.id = p_ride_id and (
      r.status in ('recruiting', 'full') or r.host_id = auth.uid()
      or exists (select 1 from public.ride_memberships m
        where m.ride_id = r.id and m.user_id = auth.uid() and m.status = 'approved')
    )
  );
$$;
revoke all on function companion_private.can_read_ride(uuid) from public, anon, authenticated, service_role;
grant execute on function companion_private.can_read_ride(uuid) to authenticated;

drop policy if exists profiles_read_authenticated on public.profiles;
drop policy if exists profiles_read_self on public.profiles;
create policy profiles_read_self on public.profiles
  for select to authenticated using (id = (select auth.uid()));
drop policy if exists rides_read_authenticated on public.rides;
drop policy if exists rides_read_visible on public.rides;
create policy rides_read_visible on public.rides
  for select to authenticated using (companion_private.can_read_ride(id));
drop policy if exists memberships_read_visible on public.ride_memberships;
drop policy if exists memberships_read_self on public.ride_memberships;
create policy memberships_read_self on public.ride_memberships
  for select to authenticated using (user_id = (select auth.uid()));

-- Profiles, host membership, approval/rejection, boarding, no-show and completion are
-- provisioned by trusted server flows. No signup/join RPC is supplied here.
-- The project's automatic-RLS event hook is not an application endpoint.
do $$ begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke all on function public.rls_auto_enable() from public, anon, authenticated, service_role;
  end if;
end $$;
-- Core identity reads work without the F-07/F-08/F-10 module.
create or replace function companion_private.can_read_user(p_target_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists(select 1 from public.profiles where id=p_target_id)
    and (p_target_id=auth.uid()
      or exists(select 1 from public.rides r where r.host_id=p_target_id and companion_private.can_read_ride(r.id))
      or exists(select 1 from public.ride_memberships m join public.rides r on r.id=m.ride_id
        where m.user_id=p_target_id and ((m.status='approved' and companion_private.can_read_ride(r.id))
          or (m.status='pending' and r.host_id=auth.uid()))));
$$;
create or replace function companion_private.user_summaries(p_user_ids uuid[])
returns table(id uuid, display_name text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  if p_user_ids is null or cardinality(p_user_ids)>100 or array_position(p_user_ids,null) is not null then
    raise exception 'user_invalid';
  end if;
  if exists(select 1 from unnest(p_user_ids) requested(id) where not companion_private.can_read_user(requested.id)) then
    raise insufficient_privilege;
  end if;
  return query select p.id,p.display_name from public.profiles p where p.id=any(p_user_ids);
end $$;
create or replace function public.get_user_summaries(p_user_ids uuid[])
returns table(id uuid, display_name text)
language sql stable security invoker set search_path = '' as $$
  select * from companion_private.user_summaries(p_user_ids);
$$;
-- The marker is created last by the optional, atomic feature migration.
-- Missing marker is distinct from network, authentication and permission errors.
create or replace function public.get_gachita_capabilities() returns jsonb
language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('f07_f08_f10',to_regprocedure('public.companion_module_version()') is not null);
$$;
-- Approved roster is presentation data only, not boarding/no-show/history rows.
create or replace function companion_private.ride_profiles(p_ride_ids uuid[])
returns table(ride_id uuid, user_id uuid, display_name text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  if p_ride_ids is null or cardinality(p_ride_ids)>100 or array_position(p_ride_ids,null) is not null then
    raise exception 'ride_invalid';
  end if;
  if exists (select 1 from unnest(p_ride_ids) requested(ride_id)
    where not companion_private.can_read_ride(requested.ride_id)) then raise insufficient_privilege; end if;
  return query select m.ride_id,p.id,p.display_name
    from public.ride_memberships m join public.profiles p on p.id=m.user_id
    where m.ride_id=any(p_ride_ids) and m.status='approved';
end $$;
create or replace function public.list_ride_profiles(p_ride_ids uuid[])
returns table(ride_id uuid, user_id uuid, display_name text)
language sql stable security invoker set search_path = '' as $$
  select * from companion_private.ride_profiles(p_ride_ids);
$$;


create or replace function companion_private.list_ride_applicants(p_ride_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not exists(select 1 from public.rides where id=p_ride_id and host_id=auth.uid()) then
    raise exception 'host_only';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'display_name',p.display_name) order by p.display_name,p.id),'[]'::jsonb)
    from public.ride_memberships m join public.profiles p on p.id=m.user_id where m.ride_id=p_ride_id and m.status='pending');
end $$;



-- Public RPCs retain caller identity; guarded implementations are not exposed.
create or replace function public.list_ride_applicants(p_ride_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select companion_private.list_ride_applicants(p_ride_id);
$$;
revoke all on function companion_private.list_ride_applicants(uuid) from public, anon, authenticated, service_role;
grant execute on function companion_private.list_ride_applicants(uuid) to authenticated;
revoke all on function companion_private.can_read_user(uuid), companion_private.user_summaries(uuid[]),
  companion_private.ride_profiles(uuid[]), public.get_user_summaries(uuid[]), public.list_ride_profiles(uuid[]),
  public.list_ride_applicants(uuid), public.get_gachita_capabilities()
  from public, anon, authenticated, service_role;
grant execute on function companion_private.user_summaries(uuid[]), companion_private.ride_profiles(uuid[]),
  public.get_user_summaries(uuid[]), public.list_ride_profiles(uuid[]), public.list_ride_applicants(uuid),
  public.get_gachita_capabilities() to authenticated;
commit;
