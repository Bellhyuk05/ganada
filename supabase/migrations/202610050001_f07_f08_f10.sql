-- F-07 profile/rating, F-08 keyword notifications/FCM, F-10 blocking.
-- Apply once after common_baseline. No seed data; all feature SQL is atomic.
begin;
create schema if not exists companion_private;
revoke all on schema companion_private from public, anon, authenticated;
grant usage on schema companion_private to authenticated;

-- Fail early instead of silently creating a conflicting common schema.
do $$ begin
  perform id, display_name from public.profiles limit 0;
  perform id, host_id, origin_name, destination_name, condition_text, capacity,
    departure_at, departed_at, ended_at, status from public.rides limit 0;
  perform ride_id, user_id, status, boarded_at, no_show from public.ride_memberships limit 0;
end $$;

-- Bounded PNG structure, not a server-side pixel decoder. Only core chunks are
-- retained: no EXIF/text, palette, animation or hidden trailing payload.
create or replace function companion_private.valid_profile_photo(p_bytes bytea) returns boolean
language plpgsql immutable set search_path = '' as $$
declare v_size integer; v_offset integer := 8; v_length bigint; v_end bigint;
  v_type bytea; v_width bigint; v_height bigint; v_data boolean := false;
begin
  if p_bytes is null then return true; end if;
  v_size := octet_length(p_bytes);
  if v_size<45 or v_size>65536 or substring(p_bytes from 1 for 8)<>decode('89504e470d0a1a0a','hex') then return false; end if;
  v_width := get_byte(p_bytes,16)::bigint*16777216 + get_byte(p_bytes,17)*65536 + get_byte(p_bytes,18)*256 + get_byte(p_bytes,19);
  v_height := get_byte(p_bytes,20)::bigint*16777216 + get_byte(p_bytes,21)*65536 + get_byte(p_bytes,22)*256 + get_byte(p_bytes,23);
  if v_width not between 1 and 256 or v_height not between 1 and 256
    or get_byte(p_bytes,24)<>8 or get_byte(p_bytes,25) not in (2,6)
    or get_byte(p_bytes,26)<>0 or get_byte(p_bytes,27)<>0 or get_byte(p_bytes,28)<>0 then return false; end if;
  while v_offset+12<=v_size loop
    v_length := get_byte(p_bytes,v_offset)::bigint*16777216 + get_byte(p_bytes,v_offset+1)*65536
      + get_byte(p_bytes,v_offset+2)*256 + get_byte(p_bytes,v_offset+3);
    v_end := v_offset+v_length+12;
    if v_end>v_size then return false; end if;
    v_type := substring(p_bytes from v_offset+5 for 4);
    if v_offset=8 then
      if v_type<>decode('49484452','hex') or v_length<>13 then return false; end if;
    elsif v_type=decode('49444154','hex') then
      v_data := v_data or v_length>0;
    elsif v_type=decode('49454e44','hex') then
      return v_length=0 and v_end=v_size and v_data;
    else return false;
    end if;
    v_offset := v_end::integer;
  end loop;
  return false;
end $$;
revoke all on function companion_private.valid_profile_photo(bytea) from public, anon, authenticated, service_role;
grant execute on function companion_private.valid_profile_photo(bytea) to service_role;


alter table public.profiles add column if not exists profile_photo bytea;
alter table public.profiles drop constraint if exists profiles_photo_valid;
alter table public.profiles add constraint profiles_photo_valid
  check (companion_private.valid_profile_photo(profile_photo));


grant select (profile_photo) on public.profiles to authenticated;

create table if not exists public.ratings (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides(id) on delete restrict,
  reviewer_id uuid not null references public.profiles(id) on delete cascade,
  target_id uuid not null references public.profiles(id) on delete cascade,
  half_units smallint not null check (half_units between 1 and 10),
  created_at timestamptz not null default now(),
  unique(ride_id, reviewer_id, target_id), check(reviewer_id <> target_id)
);
create index if not exists ratings_target_idx on public.ratings(target_id);
create index if not exists ratings_reviewer_idx on public.ratings(reviewer_id);

create table if not exists public.profile_stats (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  rating_count integer not null default 0 check(rating_count >= 0),
  average_rating numeric(4,2) check(average_rating between 0.5 and 5.0),
  participation_count integer not null default 0 check(participation_count >= 0),
  no_show_count integer not null default 0 check(no_show_count >= 0),
  refreshed_at timestamptz not null default now()
);
create table if not exists public.user_keywords (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  text text not null check(text <> ''),
  normalized_text text not null check(normalized_text = lower(text)),
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  unique(user_id, normalized_text)
);
alter table public.user_keywords add column if not exists enabled boolean not null default true;
create table if not exists public.notification_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  keyword_enabled boolean not null default true
);
create table if not exists public.user_blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(blocker_id, blocked_id), check(blocker_id <> blocked_id)
);
create index if not exists user_blocks_blocked_idx on public.user_blocks(blocked_id);
create table if not exists public.keyword_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  ride_id uuid not null references public.rides(id) on delete cascade,
  title text not null, body text not null,
  created_at timestamptz not null default now(), read_at timestamptz,
  unique(user_id, ride_id)
);
create index if not exists keyword_notifications_inbox_idx on public.keyword_notifications(user_id, created_at desc);
create index if not exists keyword_notifications_ride_idx on public.keyword_notifications(ride_id);
create table if not exists public.device_tokens (
  token text primary key check(length(token) > 0),
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform text not null default 'android' check(platform = 'android'),
  updated_at timestamptz not null default now()
);
create index if not exists device_tokens_user_idx on public.device_tokens(user_id);
create table if not exists public.keyword_push_jobs (
  notification_id uuid primary key references public.keyword_notifications(id) on delete cascade,
  status text not null default 'pending' check(status in ('pending','processing','sent','skipped','failed')),
  attempts integer not null default 0,
  available_at timestamptz not null default now(), locked_at timestamptz, lease_id uuid,
  last_error text
);
create table if not exists public.keyword_push_deliveries (
  notification_id uuid not null references public.keyword_notifications(id) on delete cascade,
  token text not null,
  status text not null default 'pending' check(status in ('pending','sent','skipped')),
  primary key(notification_id, token)
);

alter table public.ratings enable row level security;
alter table public.profile_stats enable row level security;
alter table public.user_keywords enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.user_blocks enable row level security;
alter table public.keyword_notifications enable row level security;
alter table public.device_tokens enable row level security;
alter table public.keyword_push_jobs enable row level security;
alter table public.keyword_push_deliveries enable row level security;

-- No client mutation of ratings, aggregates, notifications or dispatch state.
revoke all on public.ratings, public.profile_stats, public.user_keywords,
  public.notification_preferences, public.user_blocks, public.keyword_notifications,
  public.device_tokens, public.keyword_push_jobs, public.keyword_push_deliveries
  from public, anon, authenticated;
grant select on public.ratings, public.keyword_notifications to authenticated;
grant select (user_id, rating_count, average_rating, participation_count, no_show_count, refreshed_at)
  on public.profile_stats to authenticated;
grant select, delete on public.user_keywords, public.user_blocks, public.device_tokens to authenticated;
grant update (enabled) on public.user_keywords to authenticated;
grant select, insert, update on public.notification_preferences to authenticated;
grant all on public.ratings, public.profile_stats, public.user_keywords,
  public.notification_preferences, public.user_blocks, public.keyword_notifications,
  public.device_tokens, public.keyword_push_jobs, public.keyword_push_deliveries to service_role;

drop policy if exists ratings_mine on public.ratings;
create policy ratings_mine on public.ratings for select to authenticated using(reviewer_id = (select auth.uid()));
drop policy if exists stats_public_to_members on public.profile_stats;
drop policy if exists stats_read_self on public.profile_stats;
create policy stats_read_self on public.profile_stats for select to authenticated using(user_id = (select auth.uid()));
drop policy if exists keywords_mine_select on public.user_keywords;
create policy keywords_mine_select on public.user_keywords for select to authenticated using(user_id = (select auth.uid()));
drop policy if exists keywords_mine_delete on public.user_keywords;
create policy keywords_mine_delete on public.user_keywords for delete to authenticated using(user_id = (select auth.uid()));
drop policy if exists keywords_mine_update on public.user_keywords;
create policy keywords_mine_update on public.user_keywords for update to authenticated
  using(user_id = (select auth.uid())) with check(user_id = (select auth.uid()));
drop policy if exists preferences_mine on public.notification_preferences;
create policy preferences_mine on public.notification_preferences for all to authenticated
  using(user_id = (select auth.uid())) with check(user_id = (select auth.uid()));
drop policy if exists blocks_mine_select on public.user_blocks;
create policy blocks_mine_select on public.user_blocks for select to authenticated using(blocker_id = (select auth.uid()));
drop policy if exists blocks_mine_delete on public.user_blocks;
create policy blocks_mine_delete on public.user_blocks for delete to authenticated using(blocker_id = (select auth.uid()));
drop policy if exists notices_mine on public.keyword_notifications;
create policy notices_mine on public.keyword_notifications for select to authenticated using(user_id = (select auth.uid()));
drop policy if exists tokens_mine_select on public.device_tokens;
create policy tokens_mine_select on public.device_tokens for select to authenticated using(user_id = (select auth.uid()));
drop policy if exists tokens_mine_delete on public.device_tokens;
create policy tokens_mine_delete on public.device_tokens for delete to authenticated using(user_id = (select auth.uid()));
-- Push tables deliberately have no authenticated policies.

-- Profile disclosure is limited to a visible ride, host's own applicants,
-- the caller's block list, or the caller. Never accepts a caller-supplied viewer.
create or replace function companion_private.can_read_profile(p_target_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (select 1 from public.profiles p where p.id=p_target_id)
    and (p_target_id=auth.uid()
      or exists (select 1 from public.rides r where r.host_id=p_target_id
        and companion_private.can_read_ride(r.id))
      or exists (select 1 from public.ride_memberships m join public.rides r on r.id=m.ride_id
        where m.user_id=p_target_id and ((m.status='approved' and companion_private.can_read_ride(r.id))
          or (m.status='pending' and r.host_id=auth.uid())))
      or exists (select 1 from public.user_blocks b where b.blocker_id=auth.uid() and b.blocked_id=p_target_id));
$$;

-- Recreate only the profile summary functions, without CASCADE.
drop function if exists public.get_profile_summaries(uuid[]);
drop function if exists companion_private.profile_summaries(uuid[]);
create or replace function companion_private.profile_summaries(p_user_ids uuid[])
returns table(id uuid, display_name text, photo_base64 text, average_rating numeric,
  participation_count integer, no_show_count integer)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  if p_user_ids is null or cardinality(p_user_ids)>20 or array_position(p_user_ids,null) is not null then
    raise exception 'profile_invalid';
  end if;
  if exists (select 1 from unnest(p_user_ids) requested(user_id)
    where not companion_private.can_read_profile(requested.user_id)) then raise insufficient_privilege; end if;
  return query select p.id,p.display_name,replace(encode(p.profile_photo,'base64'),E'\n',''),
    case when s.rating_count>=3 then s.average_rating else null end,
    coalesce(s.participation_count,0),coalesce(s.no_show_count,0)
    from public.profiles p left join public.profile_stats s on s.user_id=p.id
    where p.id=any(p_user_ids);
end $$;
create or replace function public.get_profile_summaries(p_user_ids uuid[])
returns table(id uuid, display_name text, photo_base64 text, average_rating numeric,
  participation_count integer, no_show_count integer)
language sql stable security invoker set search_path = '' as $$
  select * from companion_private.profile_summaries(p_user_ids);
$$;

create or replace function companion_private.set_my_profile_photo(p_photo_base64 text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_photo bytea;
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  if p_photo_base64 is not null then
    if length(p_photo_base64)>87384 or p_photo_base64 !~ '^[A-Za-z0-9+/]*={0,2}$' then raise exception 'photo_invalid'; end if;
    begin
      v_photo := decode(p_photo_base64,'base64');
    exception when invalid_parameter_value then raise exception 'photo_invalid'; end;
    if not companion_private.valid_profile_photo(v_photo) then raise exception 'photo_invalid'; end if;
  end if;
  update public.profiles set profile_photo=v_photo where id=auth.uid();
  if not found then raise exception 'profile_missing'; end if;
end $$;
create or replace function public.set_my_profile_photo(p_photo_base64 text) returns void
language sql security invoker set search_path = '' as $$
  select companion_private.set_my_profile_photo(p_photo_base64);
$$;
revoke all on function companion_private.set_my_profile_photo(text), public.set_my_profile_photo(text)
  from public, anon, authenticated, service_role;
grant execute on function companion_private.set_my_profile_photo(text), public.set_my_profile_photo(text) to authenticated;

revoke all on function companion_private.can_read_profile(uuid), companion_private.profile_summaries(uuid[]),
  public.get_profile_summaries(uuid[]) from public, anon, authenticated, service_role;
grant execute on function companion_private.profile_summaries(uuid[]), public.get_profile_summaries(uuid[]) to authenticated;

-- Same outer whitespace characters as Dart String.trim(), including Unicode spaces.
create or replace function companion_private.trim_keyword(p_text text) returns text
language sql immutable strict set search_path = '' as $$
  select btrim(p_text, E' \t\n\r\f' || chr(11) || chr(133) || chr(160) || chr(5760) ||
    chr(8192) || chr(8193) || chr(8194) || chr(8195) || chr(8196) || chr(8197) ||
    chr(8198) || chr(8199) || chr(8200) || chr(8201) || chr(8202) || chr(8232) ||
    chr(8233) || chr(8239) || chr(8287) || chr(12288) || chr(65279));
$$;
create or replace function companion_private.add_keyword(p_text text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_text text := companion_private.trim_keyword(p_text);
begin
  if v_user is null then raise insufficient_privilege; end if;
  if v_text is null or v_text = '' then raise exception 'keyword_empty'; end if;
  perform pg_advisory_xact_lock(hashtextextended('keywords/' || v_user::text, 0));
  if exists(select 1 from public.user_keywords where user_id = v_user and normalized_text = lower(v_text)) then
    raise unique_violation using message = 'keyword_duplicate';
  end if;
  if (select count(*) from public.user_keywords where user_id = v_user) >= 5 then raise exception 'keyword_limit'; end if;
  insert into public.user_keywords(user_id,text,normalized_text) values(v_user,v_text,lower(v_text));
end $$;

create or replace function companion_private.block_user(p_target_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  if p_target_id = auth.uid() then raise exception 'self_block'; end if;
  if not companion_private.can_read_profile(p_target_id) then raise insufficient_privilege; end if;
  insert into public.user_blocks(blocker_id,blocked_id) values(auth.uid(),p_target_id) on conflict do nothing;
end $$;
create or replace function companion_private.list_my_blocks() returns jsonb language plpgsql stable
security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'display_name',p.display_name) order by p.display_name,p.id),'[]'::jsonb)
    from public.user_blocks b join public.profiles p on p.id=b.blocked_id where b.blocker_id=auth.uid());
end $$;
create or replace function companion_private.blocked_ride_participants(p_ride_id uuid) returns jsonb language plpgsql stable
security definer set search_path = '' as $$
begin
  if not companion_private.can_read_ride(p_ride_id) then raise insufficient_privilege; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'display_name',p.display_name) order by p.display_name,p.id),'[]'::jsonb)
    from public.user_blocks b join public.ride_memberships m on m.user_id=b.blocked_id
      join public.profiles p on p.id=m.user_id
    where b.blocker_id=auth.uid() and m.ride_id=p_ride_id and m.status='approved');
end $$;
create or replace function companion_private.list_rating_tasks() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(task order by ended_at desc),'[]'::jsonb) from (
    select r.ended_at, jsonb_build_object(
      'ride', jsonb_build_object('id',r.id,'host',jsonb_build_object('id',h.id,'display_name',h.display_name),
        'origin_name',r.origin_name,'destination_name',r.destination_name,'condition_text',r.condition_text,
        'capacity',r.capacity,'departure_at',r.departure_at,'departed_at',r.departed_at,'ended_at',r.ended_at,
        'status',r.status,'members','[]'::jsonb),
      'targets', (select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'display_name',p.display_name) order by p.display_name,p.id),'[]'::jsonb)
        from public.ride_memberships m join public.profiles p on p.id=m.user_id
        where m.ride_id=r.id and m.user_id<>auth.uid() and m.status='approved' and m.boarded_at is not null and not m.no_show),
      'submitted_user_ids', (select coalesce(jsonb_agg(t.target_id),'[]'::jsonb) from public.ratings t where t.ride_id=r.id and t.reviewer_id=auth.uid())
    ) as task
    from public.rides r join public.profiles h on h.id=r.host_id
    where auth.uid() is not null and r.status='completed' and r.departed_at is not null and r.ended_at is not null
      and exists(select 1 from public.ride_memberships m where m.ride_id=r.id and m.user_id=auth.uid()
        and m.status='approved' and m.boarded_at is not null and not m.no_show)
    order by r.ended_at desc limit 100
  ) tasks;
$$;

create or replace function companion_private.submit_ratings(p_ride_id uuid, p_inputs jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_ride public.rides%rowtype; v_item jsonb;
  v_target uuid; v_score smallint; v_existing smallint; v_block boolean;
begin
  if v_user is null then raise insufficient_privilege; end if;
  if jsonb_typeof(p_inputs) is distinct from 'array' then raise exception 'rating_invalid'; end if;
  if jsonb_array_length(p_inputs)=0 then raise exception 'rating_invalid'; end if;
  if exists(select 1 from jsonb_array_elements(p_inputs) i group by i->>'target_id' having count(*)>1) then raise exception 'rating_invalid'; end if;
  perform pg_advisory_xact_lock(hashtextextended('ratings/' || p_ride_id::text || '/' || v_user::text,0));
  select * into v_ride from public.rides where id=p_ride_id for share;
  if not found or v_ride.status <> 'completed' or v_ride.departed_at is null or v_ride.ended_at is null
    or clock_timestamp()<v_ride.ended_at or clock_timestamp()>=v_ride.ended_at+interval '3 days' then raise exception 'rating_closed'; end if;
  if not exists(select 1 from public.ride_memberships where ride_id=p_ride_id and user_id=v_user
    and status='approved' and boarded_at is not null and not no_show) then raise exception 'rating_ineligible'; end if;
  for v_item in select value from jsonb_array_elements(p_inputs) loop
    begin
      v_target := (v_item->>'target_id')::uuid;
      if jsonb_typeof(v_item->'half_units') is distinct from 'number' or (v_item->>'half_units') !~ '^[0-9]+$' then raise exception 'rating_invalid'; end if;
      v_score := (v_item->>'half_units')::smallint;
      if v_item ? 'block' and jsonb_typeof(v_item->'block') is distinct from 'boolean' then raise exception 'rating_invalid'; end if;
      v_block := coalesce((v_item->>'block')::boolean,false);
    exception when invalid_text_representation or numeric_value_out_of_range then raise exception 'rating_invalid'; end;
    if v_target is null or v_target=v_user or v_score not between 1 and 10 then raise exception 'rating_invalid'; end if;
    if not exists(select 1 from public.ride_memberships where ride_id=p_ride_id and user_id=v_target
      and status='approved' and boarded_at is not null and not no_show) then raise exception 'rating_ineligible'; end if;
    select half_units into v_existing from public.ratings where ride_id=p_ride_id and reviewer_id=v_user and target_id=v_target;
    if found then
      if v_existing<>v_score then raise exception 'rating_immutable'; end if;
      -- Identical retry does not repeat optional block side effects.
    else
      insert into public.ratings(ride_id,reviewer_id,target_id,half_units) values(p_ride_id,v_user,v_target,v_score);
      if v_block then perform public.block_user(v_target); end if;
    end if;
  end loop;
end $$;

create or replace function companion_private.mark_keyword_notice_read(p_notice_id uuid) returns void
language sql security definer set search_path = '' as $$
  update public.keyword_notifications set read_at=coalesce(read_at,clock_timestamp()) where id=p_notice_id and user_id=auth.uid();
$$;
create or replace function companion_private.register_device_token(p_token text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  if p_token is null or p_token='' then raise exception 'token_empty'; end if;
  insert into public.device_tokens(token,user_id) values(p_token,auth.uid())
    on conflict(token) do update set user_id=excluded.user_id, updated_at=clock_timestamp();
end $$;

create or replace function companion_private.match_new_ride() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status<>'recruiting' then return new; end if;
  with new_notices as (
    insert into public.keyword_notifications(user_id,ride_id,title,body)
    select distinct k.user_id,new.id,'키워드가 포함된 새 팟이 있어요',new.origin_name || ' → ' || new.destination_name
    from public.user_keywords k left join public.notification_preferences pref on pref.user_id=k.user_id
    where k.enabled and k.user_id<>new.host_id and coalesce(pref.keyword_enabled,true)
      and not exists(select 1 from public.user_blocks b where b.blocker_id=k.user_id and b.blocked_id=new.host_id)
      and (strpos(lower(coalesce(new.origin_name,'')),k.normalized_text)>0
        or strpos(lower(coalesce(new.destination_name,'')),k.normalized_text)>0
        or strpos(lower(coalesce(new.condition_text,'')),k.normalized_text)>0)
    on conflict(user_id,ride_id) do nothing returning id
  ) insert into public.keyword_push_jobs(notification_id) select id from new_notices on conflict do nothing;
  return new;
end $$;
drop trigger if exists match_ride_keywords on public.rides;
create trigger match_ride_keywords after insert on public.rides for each row execute function companion_private.match_new_ride();

-- Consistent daily snapshot: sent ratings never contribute to sender's average.
create or replace function public.refresh_profile_stats() returns void
language sql security definer set search_path = '' as $$
  insert into public.profile_stats(user_id,rating_count,average_rating,participation_count,no_show_count,refreshed_at)
  select p.id, coalesce(a.n,0), a.average,
    coalesce(m.participations,0),coalesce(m.no_shows,0),statement_timestamp()
  from public.profiles p
  left join (select target_id,count(*)::integer n,round(avg(half_units::numeric/2),1) average from public.ratings group by target_id) a on a.target_id=p.id
  left join (select member.user_id,
    count(distinct r.id) filter(where r.departed_at is not null and member.status='approved')::integer participations,
    count(distinct r.id) filter(where member.status='approved' and member.no_show)::integer no_shows
    from public.ride_memberships member join public.rides r on r.id=member.ride_id group by member.user_id) m on m.user_id=p.id
  on conflict(user_id) do update set rating_count=excluded.rating_count,average_rating=excluded.average_rating,
    participation_count=excluded.participation_count,no_show_count=excluded.no_show_count,refreshed_at=excluded.refreshed_at;
$$;

create or replace function public.claim_keyword_push_jobs(p_limit integer default 20)
returns setof public.keyword_push_jobs language sql security definer set search_path = '' as $$
  with candidates as (
    select notification_id from public.keyword_push_jobs
    where (status='pending' and available_at<=clock_timestamp())
      or (status='processing' and locked_at<clock_timestamp()-interval '5 minutes')
    order by available_at limit greatest(1,least(p_limit,50)) for update skip locked
  ) update public.keyword_push_jobs j set status='processing',locked_at=clock_timestamp(),
      lease_id=gen_random_uuid(),attempts=j.attempts+1
    from candidates c where j.notification_id=c.notification_id returning j.*;
$$;


-- Public RPCs retain caller identity; guarded implementations are not exposed.
create or replace function public.add_keyword(p_text text) returns void
language sql security invoker set search_path = '' as $$
  select companion_private.add_keyword(p_text);
$$;
revoke all on function companion_private.add_keyword(text) from public, anon, authenticated, service_role;
grant execute on function companion_private.add_keyword(text) to authenticated;

create or replace function public.block_user(p_target_id uuid) returns void
language sql security invoker set search_path = '' as $$
  select companion_private.block_user(p_target_id);
$$;
revoke all on function companion_private.block_user(uuid) from public, anon, authenticated, service_role;
grant execute on function companion_private.block_user(uuid) to authenticated;

create or replace function public.list_my_blocks() returns jsonb
language sql stable security invoker set search_path = '' as $$
  select companion_private.list_my_blocks();
$$;
revoke all on function companion_private.list_my_blocks() from public, anon, authenticated, service_role;
grant execute on function companion_private.list_my_blocks() to authenticated;

create or replace function public.blocked_ride_participants(p_ride_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select companion_private.blocked_ride_participants(p_ride_id);
$$;
revoke all on function companion_private.blocked_ride_participants(uuid) from public, anon, authenticated, service_role;
grant execute on function companion_private.blocked_ride_participants(uuid) to authenticated;

create or replace function public.list_rating_tasks() returns jsonb
language sql stable security invoker set search_path = '' as $$
  select companion_private.list_rating_tasks();
$$;
revoke all on function companion_private.list_rating_tasks() from public, anon, authenticated, service_role;
grant execute on function companion_private.list_rating_tasks() to authenticated;

create or replace function public.submit_ratings(p_ride_id uuid, p_inputs jsonb) returns void
language sql security invoker set search_path = '' as $$
  select companion_private.submit_ratings(p_ride_id,p_inputs);
$$;
revoke all on function companion_private.submit_ratings(uuid,jsonb) from public, anon, authenticated, service_role;
grant execute on function companion_private.submit_ratings(uuid,jsonb) to authenticated;

create or replace function public.mark_keyword_notice_read(p_notice_id uuid) returns void
language sql security invoker set search_path = '' as $$
  select companion_private.mark_keyword_notice_read(p_notice_id);
$$;
revoke all on function companion_private.mark_keyword_notice_read(uuid) from public, anon, authenticated, service_role;
grant execute on function companion_private.mark_keyword_notice_read(uuid) to authenticated;

create or replace function public.register_device_token(p_token text) returns void
language sql security invoker set search_path = '' as $$
  select companion_private.register_device_token(p_token);
$$;
revoke all on function companion_private.register_device_token(text) from public, anon, authenticated, service_role;
grant execute on function companion_private.register_device_token(text) to authenticated;
-- Remove PostgreSQL's default PUBLIC execute grant on EVERY entry point.
revoke all on function companion_private.trim_keyword(text), companion_private.match_new_ride() from public, anon, authenticated;
revoke all on function public.add_keyword(text), public.block_user(uuid), public.list_my_blocks(),
  public.blocked_ride_participants(uuid), public.list_rating_tasks(),
  public.submit_ratings(uuid,jsonb), public.mark_keyword_notice_read(uuid), public.register_device_token(text),
  public.refresh_profile_stats(), public.claim_keyword_push_jobs(integer) from public, anon, authenticated;
grant execute on function public.add_keyword(text), public.block_user(uuid), public.list_my_blocks(),
  public.blocked_ride_participants(uuid), public.list_rating_tasks(),
  public.submit_ratings(uuid,jsonb), public.mark_keyword_notice_read(uuid), public.register_device_token(text) to authenticated;
grant execute on function public.refresh_profile_stats(), public.claim_keyword_push_jobs(integer) to service_role;
-- F-07 daily snapshot: 15:00 GMT/UTC = next day 00:00 Asia/Seoul.
create extension if not exists pg_cron;
do $$ begin
  if coalesce(current_setting('cron.timezone',true),'GMT') not in ('GMT','UTC','Etc/UTC') then
    raise exception 'cron.timezone must be UTC/GMT for the documented Asia/Seoul schedule';
  end if;
end $$;
select cron.schedule('gachita-daily-profile-stats','0 15 * * *','select public.refresh_profile_stats();');
select public.refresh_profile_stats();
create or replace function public.companion_module_version() returns integer
language sql stable security invoker set search_path = '' as $$ select 1; $$;
revoke all on function public.companion_module_version() from public, anon, authenticated, service_role;
grant execute on function public.companion_module_version() to authenticated;
commit;
