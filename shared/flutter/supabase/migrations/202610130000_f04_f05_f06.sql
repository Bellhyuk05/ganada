-- 같이타(GachiTa) F-04 참여 신청·승인, F-05 그룹 채팅, F-06 출발·도착 확인과 노쇼 처리.
-- Apply after common_baseline. Works with or without f07_f08_f10. No seed data; atomic.
-- Rules follow the 2026-09-21 meeting spec. Adjustable time rules live in
-- companion_private.flow_setting() so the team can change them in one place.
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

-- ---------------------------------------------------------------------------
-- Time rules (spec §2.1, F-05, F-06). Change values here only.
-- ---------------------------------------------------------------------------
create or replace function companion_private.flow_setting(p_key text) returns interval
language sql immutable set search_path = '' as $$
  select case p_key
    when 'boarding_opens_before' then interval '0 minutes' -- 출발 확인 창: 출발 시각부터
    when 'absence_timeout'       then interval '10 minutes' -- 미확인자 응답 대기(출발 시각 기준)
    when 'no_boarding_close'     then interval '1 hour'     -- 아무도 탑승 확인 안 하면 노쇼 없이 종료
    when 'auto_arrival'          then interval '3 hours'    -- 출발 처리 후 도착 확인 없으면 자동 종료
    when 'chat_lifetime'         then interval '12 hours'   -- 출발 시각 기준 채팅 삭제
    when 'deletion_warning'      then interval '1 hour'     -- 삭제 전 경고
  end;
$$;
revoke all on function companion_private.flow_setting(text) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- F-04 bookkeeping on the common membership row (nullable additions only).
-- Kicked users keep status 'reject' plus kicked_at, so they cannot apply again.
-- ---------------------------------------------------------------------------
alter table public.ride_memberships add column if not exists requested_at timestamptz not null default now();
alter table public.ride_memberships add column if not exists decided_at timestamptz;
alter table public.ride_memberships add column if not exists kicked_at timestamptz;

-- The host is the first participant (spec F-02 "등록 후"). F-02 should insert this row;
-- this module only fills it in when it is missing, never overwrites it.
create or replace function companion_private.ensure_host_membership(p_ride_id uuid) returns void
language sql security definer set search_path = '' as $$
  insert into public.ride_memberships(ride_id, user_id, status, decided_at)
  select r.id, r.host_id, 'approved', now() from public.rides r where r.id = p_ride_id
  on conflict (ride_id, user_id) do nothing;
$$;
insert into public.ride_memberships(ride_id, user_id, status, decided_at)
select r.id, r.host_id, 'approved', now() from public.rides r
on conflict (ride_id, user_id) do nothing;

-- Seats taken = host + approved non-host members (correct even if the host row is missing).
create or replace function companion_private.ride_occupancy(p_ride_id uuid) returns integer
language sql stable security definer set search_path = '' as $$
  select 1 + count(*)::integer
  from public.ride_memberships m join public.rides r on r.id = m.ride_id
  where m.ride_id = p_ride_id and m.status = 'approved' and m.user_id <> r.host_id;
$$;

create or replace function companion_private.display_name(p_user_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce((select display_name from public.profiles where id = p_user_id), '알 수 없는 사용자');
$$;

-- ---------------------------------------------------------------------------
-- F-05 messages. System notices (입장·퇴장·강제퇴장·출발·도착·삭제 예고) share the table.
-- ---------------------------------------------------------------------------
create table if not exists public.ride_messages (
  id bigint generated always as identity primary key,
  ride_id uuid not null references public.rides(id) on delete cascade,
  sender_id uuid references public.profiles(id) on delete set null,
  sender_name text,
  kind text not null default 'text' check (kind in ('text', 'system')),
  body text not null check (length(body) between 1 and 1000),
  created_at timestamptz not null default now(),
  check (kind = 'system' or sender_name is not null)
);
create index if not exists ride_messages_ride_idx on public.ride_messages(ride_id, id);

create table if not exists companion_private.ride_flow_marks (
  ride_id uuid primary key references public.rides(id) on delete cascade,
  deletion_warned_at timestamptz
);

alter table public.ride_messages enable row level security;
revoke all on public.ride_messages from public, anon, authenticated;
grant select on public.ride_messages to authenticated;
grant all on public.ride_messages to service_role;
revoke all on companion_private.ride_flow_marks from public, anon, authenticated, service_role;
alter table companion_private.ride_flow_marks enable row level security; -- no policies: owner-only

-- Host and approved participants only, until 12 hours after the departure time.
create or replace function companion_private.can_chat(p_ride_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (
    select 1 from public.rides r
    where r.id = p_ride_id
      and now() < r.departure_at + companion_private.flow_setting('chat_lifetime')
      and (r.host_id = auth.uid() or exists (
        select 1 from public.ride_memberships m
        where m.ride_id = r.id and m.user_id = auth.uid() and m.status = 'approved')));
$$;
revoke all on function companion_private.can_chat(uuid) from public, anon, authenticated, service_role;
grant execute on function companion_private.can_chat(uuid) to authenticated;

drop policy if exists ride_messages_members on public.ride_messages;
create policy ride_messages_members on public.ride_messages
  for select to authenticated using (companion_private.can_chat(ride_id));

create or replace function companion_private.post_system_message(p_ride_id uuid, p_body text) returns void
language sql security definer set search_path = '' as $$
  insert into public.ride_messages(ride_id, kind, body) values (p_ride_id, 'system', p_body);
$$;

-- Realtime delivery (RLS still applies to each subscriber).
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'ride_messages') then
    alter publication supabase_realtime add table public.ride_messages;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- F-06 timers for one ride. Idempotent; called by every F-06 action, by the state
-- reader and by the per-minute job, so the result never depends on cron latency.
-- ---------------------------------------------------------------------------
create or replace function companion_private.settle_ride(p_ride_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_ride public.rides%rowtype; v_now timestamptz := now();
  v_boarded integer; v_unresolved integer; v_names text;
begin
  select * into v_ride from public.rides where id = p_ride_id for update;
  if not found or v_ride.status not in ('recruiting', 'full') then return; end if;
  if v_ride.departed_at is null then
    if v_now < v_ride.departure_at then return; end if;
    perform companion_private.ensure_host_membership(p_ride_id);
    select count(*) filter (where boarded_at is not null and not no_show),
           count(*) filter (where boarded_at is null and not no_show)
      into v_boarded, v_unresolved
      from public.ride_memberships where ride_id = p_ride_id and status = 'approved';
    if v_boarded = 0 then
      -- Nobody used the app: close without recording no-shows (spec F-06 제안).
      if v_now >= v_ride.departure_at + companion_private.flow_setting('no_boarding_close') then
        update public.rides set status = 'completed', ended_at = v_now where id = p_ride_id;
        perform companion_private.post_system_message(p_ride_id,
          '출발 확인이 없어 팟을 종료했어요. 참여 안 함은 기록하지 않아요.');
      end if;
      return;
    end if;
    if v_unresolved > 0 and v_now >= v_ride.departure_at + companion_private.flow_setting('absence_timeout') then
      select string_agg(p.display_name, ', ' order by p.display_name) into v_names
        from public.ride_memberships m join public.profiles p on p.id = m.user_id
        where m.ride_id = p_ride_id and m.status = 'approved' and m.boarded_at is null and not m.no_show;
      update public.ride_memberships set no_show = true
        where ride_id = p_ride_id and status = 'approved' and boarded_at is null and not no_show;
      perform companion_private.post_system_message(p_ride_id,
        coalesce(v_names, '확인하지 않은 참여자') || '님은 응답이 없어 참여 안 함으로 기록됐어요.');
      v_unresolved := 0;
    end if;
    if v_unresolved = 0 then
      update public.rides set departed_at = v_now, status = 'full' where id = p_ride_id;
      perform companion_private.post_system_message(p_ride_id, '출발 확인이 끝났어요. 안전하게 이동하세요!');
      v_ride.departed_at := v_now;
    end if;
  end if;
  if v_ride.departed_at is not null and v_ride.ended_at is null
    and v_now >= v_ride.departed_at + companion_private.flow_setting('auto_arrival') then
    update public.rides set status = 'completed', ended_at = v_now where id = p_ride_id;
    perform companion_private.post_system_message(p_ride_id,
      '출발 후 3시간이 지나 운행을 자동으로 종료했어요. 함께 탄 사람을 평가해 주세요.');
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- F-04 참여 신청·승인·거절·강제퇴장·자진 퇴장·팟 취소
-- ---------------------------------------------------------------------------
create or replace function companion_private.request_join(p_ride_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_ride public.rides%rowtype; v_member public.ride_memberships%rowtype;
begin
  if v_user is null then raise insufficient_privilege; end if;
  select * into v_ride from public.rides where id = p_ride_id for update;
  if not found then raise exception 'ride_missing'; end if;
  if v_ride.host_id = v_user then raise exception 'join_host'; end if;
  select * into v_member from public.ride_memberships where ride_id = p_ride_id and user_id = v_user;
  if found and v_member.kicked_at is not null then raise exception 'join_kicked'; end if;
  if found and v_member.status in ('pending', 'approved') then return; end if; -- identical retry
  if v_ride.status <> 'recruiting' or now() >= v_ride.departure_at then raise exception 'join_closed'; end if;
  if companion_private.ride_occupancy(p_ride_id) >= v_ride.capacity then raise exception 'join_full'; end if;
  if found then -- re-apply after a rejection or after leaving is allowed; after a kick it is not
    update public.ride_memberships set status = 'pending', requested_at = now(), decided_at = null
      where ride_id = p_ride_id and user_id = v_user;
  else
    insert into public.ride_memberships(ride_id, user_id, status) values (p_ride_id, v_user, 'pending');
  end if;
end $$;

create or replace function companion_private.approve_applicant(p_ride_id uuid, p_user_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_ride public.rides%rowtype;
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  select * into v_ride from public.rides where id = p_ride_id for update;
  if not found or v_ride.host_id <> auth.uid() then raise exception 'host_only'; end if;
  if v_ride.status = 'full' then raise exception 'join_full'; end if;
  if v_ride.status <> 'recruiting' or now() >= v_ride.departure_at then raise exception 'join_closed'; end if;
  if companion_private.ride_occupancy(p_ride_id) >= v_ride.capacity then raise exception 'join_full'; end if;
  perform companion_private.ensure_host_membership(p_ride_id);
  update public.ride_memberships set status = 'approved', decided_at = now()
    where ride_id = p_ride_id and user_id = p_user_id and status = 'pending';
  if not found then raise exception 'applicant_missing'; end if;
  perform companion_private.post_system_message(p_ride_id,
    companion_private.display_name(p_user_id) || '님이 들어왔어요.');
  if companion_private.ride_occupancy(p_ride_id) >= v_ride.capacity then
    update public.rides set status = 'full' where id = p_ride_id;
    perform companion_private.post_system_message(p_ride_id, '정원이 모두 찼어요. 모집을 마감했어요.');
  end if;
end $$;

create or replace function companion_private.reject_applicant(p_ride_id uuid, p_user_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  if not exists (select 1 from public.rides where id = p_ride_id and host_id = auth.uid()) then
    raise exception 'host_only';
  end if;
  update public.ride_memberships set status = 'reject', decided_at = now()
    where ride_id = p_ride_id and user_id = p_user_id and status = 'pending';
  if not found then raise exception 'applicant_missing'; end if;
end $$;

-- Re-open recruiting when a seat frees up before the departure time (spec F-04).
create or replace function companion_private.reopen_if_seat(p_ride_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_ride public.rides%rowtype;
begin
  select * into v_ride from public.rides where id = p_ride_id;
  if v_ride.status = 'full' and v_ride.departed_at is null and now() < v_ride.departure_at
    and companion_private.ride_occupancy(p_ride_id) < v_ride.capacity then
    update public.rides set status = 'recruiting' where id = p_ride_id;
    perform companion_private.post_system_message(p_ride_id, '자리가 생겨 다시 모집 중이에요.');
  end if;
end $$;

-- Kicks are the host's decision, so they are not recorded as no-shows (spec F-04).
create or replace function companion_private.kick_participant(p_ride_id uuid, p_user_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_ride public.rides%rowtype;
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  select * into v_ride from public.rides where id = p_ride_id for update;
  if not found or v_ride.host_id <> auth.uid() then raise exception 'host_only'; end if;
  if p_user_id = v_ride.host_id then raise exception 'participant_missing'; end if;
  if v_ride.departed_at is not null or v_ride.status not in ('recruiting', 'full') then
    raise exception 'kick_closed';
  end if;
  update public.ride_memberships set status = 'reject', kicked_at = now(), decided_at = now(),
      boarded_at = null, no_show = false
    where ride_id = p_ride_id and user_id = p_user_id and status = 'approved';
  if not found then raise exception 'participant_missing'; end if;
  perform companion_private.post_system_message(p_ride_id,
    companion_private.display_name(p_user_id) || '님이 방장에 의해 퇴장됐어요.');
  perform companion_private.reopen_if_seat(p_ride_id);
  perform companion_private.settle_ride(p_ride_id);
end $$;

-- Participant leaves, or an applicant withdraws a pending request. The host cancels instead.
create or replace function companion_private.leave_ride(p_ride_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_ride public.rides%rowtype; v_status text;
begin
  if v_user is null then raise insufficient_privilege; end if;
  select * into v_ride from public.rides where id = p_ride_id for update;
  if not found then raise exception 'ride_missing'; end if;
  if v_ride.host_id = v_user then raise exception 'host_cannot_leave'; end if;
  select status into v_status from public.ride_memberships where ride_id = p_ride_id and user_id = v_user;
  if v_status = 'pending' then
    delete from public.ride_memberships where ride_id = p_ride_id and user_id = v_user;
    return;
  end if;
  if v_status is distinct from 'approved' then raise exception 'not_participant'; end if;
  if v_ride.departed_at is not null or v_ride.status not in ('recruiting', 'full') then
    raise exception 'leave_closed';
  end if;
  delete from public.ride_memberships where ride_id = p_ride_id and user_id = v_user;
  perform companion_private.post_system_message(p_ride_id,
    companion_private.display_name(v_user) || '님이 나갔어요.');
  perform companion_private.reopen_if_seat(p_ride_id);
  perform companion_private.settle_ride(p_ride_id);
end $$;

create or replace function companion_private.cancel_ride(p_ride_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_ride public.rides%rowtype;
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  select * into v_ride from public.rides where id = p_ride_id for update;
  if not found or v_ride.host_id <> auth.uid() then raise exception 'host_only'; end if;
  if v_ride.departed_at is not null or v_ride.status not in ('recruiting', 'full') then
    raise exception 'cancel_closed';
  end if;
  update public.rides set status = 'cancelled' where id = p_ride_id;
  perform companion_private.post_system_message(p_ride_id, '방장이 팟을 취소했어요.');
end $$;

-- ---------------------------------------------------------------------------
-- F-05 sending. Returns the stored row so the sender sees it before realtime arrives.
-- ---------------------------------------------------------------------------
create or replace function companion_private.send_ride_message(p_ride_id uuid, p_body text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_body text := btrim(coalesce(p_body, '')); v_row public.ride_messages%rowtype;
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  if not companion_private.can_chat(p_ride_id) then raise exception 'chat_closed'; end if;
  if length(v_body) = 0 or length(v_body) > 1000 then raise exception 'message_invalid'; end if;
  insert into public.ride_messages(ride_id, sender_id, sender_name, kind, body)
    values (p_ride_id, auth.uid(), companion_private.display_name(auth.uid()), 'text', v_body)
    returning * into v_row;
  return to_jsonb(v_row);
end $$;

-- ---------------------------------------------------------------------------
-- F-06 탑승·불참자·도착 확인
-- ---------------------------------------------------------------------------
create or replace function companion_private.confirm_boarding(p_ride_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_ride public.rides%rowtype; v_member public.ride_memberships%rowtype;
begin
  if v_user is null then raise insufficient_privilege; end if;
  select * into v_ride from public.rides where id = p_ride_id for update;
  if not found then raise exception 'ride_missing'; end if;
  if v_ride.departed_at is not null or v_ride.status not in ('recruiting', 'full') then
    raise exception 'boarding_closed';
  end if;
  if now() < v_ride.departure_at - companion_private.flow_setting('boarding_opens_before') then
    raise exception 'boarding_not_open';
  end if;
  perform companion_private.ensure_host_membership(p_ride_id);
  select * into v_member from public.ride_memberships where ride_id = p_ride_id and user_id = v_user;
  if not found or v_member.status <> 'approved' then raise exception 'not_participant'; end if;
  if v_member.no_show then raise exception 'marked_absent'; end if;
  if v_member.boarded_at is null then
    update public.ride_memberships set boarded_at = now() where ride_id = p_ride_id and user_id = v_user;
    perform companion_private.post_system_message(p_ride_id,
      companion_private.display_name(v_user) || '님이 탑승을 확인했어요.');
  end if;
  perform companion_private.settle_ride(p_ride_id);
end $$;

-- A boarded participant answers "왔어요 / 안 왔어요" for someone who has not confirmed.
create or replace function companion_private.answer_absence(p_ride_id uuid, p_user_id uuid, p_present boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_ride public.rides%rowtype;
begin
  if v_user is null then raise insufficient_privilege; end if;
  if p_present is null or p_user_id is null or p_user_id = v_user then raise exception 'absence_invalid'; end if;
  select * into v_ride from public.rides where id = p_ride_id for update;
  if not found then raise exception 'ride_missing'; end if;
  if v_ride.departed_at is not null or v_ride.status not in ('recruiting', 'full') then
    raise exception 'boarding_closed';
  end if;
  if now() < v_ride.departure_at then raise exception 'boarding_not_open'; end if;
  if not exists (select 1 from public.ride_memberships where ride_id = p_ride_id and user_id = v_user
    and status = 'approved' and boarded_at is not null and not no_show) then
    raise exception 'answer_ineligible';
  end if;
  if p_present then
    update public.ride_memberships set boarded_at = now()
      where ride_id = p_ride_id and user_id = p_user_id and status = 'approved'
        and boarded_at is null and not no_show;
  else
    update public.ride_memberships set no_show = true
      where ride_id = p_ride_id and user_id = p_user_id and status = 'approved'
        and boarded_at is null and not no_show;
  end if;
  if not found then raise exception 'absence_resolved'; end if;
  perform companion_private.post_system_message(p_ride_id,
    case when p_present
      then companion_private.display_name(v_user) || '님이 ' || companion_private.display_name(p_user_id) || '님의 탑승을 확인했어요.'
      else companion_private.display_name(p_user_id) || '님이 참여 안 함으로 기록됐어요.'
    end);
  perform companion_private.settle_ride(p_ride_id);
end $$;

create or replace function companion_private.confirm_arrival(p_ride_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_ride public.rides%rowtype;
begin
  if v_user is null then raise insufficient_privilege; end if;
  perform companion_private.settle_ride(p_ride_id);
  select * into v_ride from public.rides where id = p_ride_id for update;
  if not found then raise exception 'ride_missing'; end if;
  if v_ride.status = 'completed' and v_ride.departed_at is not null then return; end if; -- already arrived
  if v_ride.departed_at is null or v_ride.status not in ('recruiting', 'full') then
    raise exception 'arrival_closed';
  end if;
  if not exists (select 1 from public.ride_memberships where ride_id = p_ride_id and user_id = v_user
    and status = 'approved' and boarded_at is not null and not no_show) then
    raise exception 'answer_ineligible';
  end if;
  update public.rides set status = 'completed', ended_at = now() where id = p_ride_id;
  perform companion_private.post_system_message(p_ride_id,
    companion_private.display_name(v_user) || '님이 도착을 확인했어요. 운행이 끝났어요. 함께 탄 사람을 평가해 주세요.');
  perform companion_private.post_system_message(p_ride_id,
    greatest(1, ceil(extract(epoch from v_ride.departure_at
      + companion_private.flow_setting('chat_lifetime') - now()) / 3600))::integer
    || '시간 후 채팅방이 삭제돼요. 요금 분담은 미리 끝내 주세요.');
end $$;

-- ---------------------------------------------------------------------------
-- State for the chat screen: phase, members' boarding states, deadlines.
-- Host and approved participants only (also after the chat itself expired).
-- ---------------------------------------------------------------------------
create or replace function companion_private.ride_flow_state(p_ride_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_ride public.rides%rowtype; v_now timestamptz;
begin
  if v_user is null then raise insufficient_privilege; end if;
  if not exists (select 1 from public.rides r where r.id = p_ride_id and (r.host_id = v_user
    or exists (select 1 from public.ride_memberships m where m.ride_id = r.id and m.user_id = v_user
      and m.status = 'approved'))) then
    raise insufficient_privilege;
  end if;
  perform companion_private.settle_ride(p_ride_id);
  perform companion_private.ensure_host_membership(p_ride_id);
  select * into v_ride from public.rides where id = p_ride_id;
  v_now := now();
  return jsonb_build_object(
    'ride_id', v_ride.id,
    'host_id', v_ride.host_id,
    'status', v_ride.status,
    'capacity', v_ride.capacity,
    'occupancy', companion_private.ride_occupancy(p_ride_id),
    'departure_at', v_ride.departure_at,
    'departed_at', v_ride.departed_at,
    'ended_at', v_ride.ended_at,
    'server_now', v_now,
    'phase', case
      when v_ride.status = 'cancelled' then 'cancelled'
      when v_ride.status = 'completed' then 'ended'
      when v_ride.departed_at is not null then 'departed'
      when v_now >= v_ride.departure_at - companion_private.flow_setting('boarding_opens_before') then 'boarding'
      else 'before' end,
    'absence_deadline', v_ride.departure_at + companion_private.flow_setting('absence_timeout'),
    'auto_end_at', v_ride.departed_at + companion_private.flow_setting('auto_arrival'),
    'chat_expires_at', v_ride.departure_at + companion_private.flow_setting('chat_lifetime'),
    'pending_count', case when v_ride.host_id = v_user then (select count(*) from public.ride_memberships
      where ride_id = p_ride_id and status = 'pending') else 0 end,
    'members', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id, 'display_name', p.display_name, 'is_host', p.id = v_ride.host_id,
        'boarded_at', m.boarded_at, 'no_show', m.no_show)
        order by (p.id <> v_ride.host_id), m.decided_at nulls first, p.display_name), '[]'::jsonb)
      from public.ride_memberships m join public.profiles p on p.id = m.user_id
      where m.ride_id = p_ride_id and m.status = 'approved'));
end $$;

-- Per-minute job: timers, the one-hour deletion warning, and chat deletion (spec F-05/F-06).
create or replace function public.process_ride_flow_timers() returns void
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  for v_id in select id from public.rides
    where status in ('recruiting', 'full') and departure_at <= now()
      and departure_at > now() - interval '2 days'
  loop
    perform companion_private.settle_ride(v_id);
  end loop;
  with due as (
    select r.id from public.rides r
    where now() >= r.departure_at + companion_private.flow_setting('chat_lifetime')
                     - companion_private.flow_setting('deletion_warning')
      and now() < r.departure_at + companion_private.flow_setting('chat_lifetime')
      and exists (select 1 from public.ride_messages m where m.ride_id = r.id)
      and not exists (select 1 from companion_private.ride_flow_marks f
        where f.ride_id = r.id and f.deletion_warned_at is not null)
  ), marked as (
    insert into companion_private.ride_flow_marks(ride_id, deletion_warned_at)
    select id, now() from due
    on conflict (ride_id) do update set deletion_warned_at = excluded.deletion_warned_at
    returning ride_id
  )
  insert into public.ride_messages(ride_id, kind, body)
  select ride_id, 'system', '1시간 후 채팅방이 삭제돼요. 요금 분담은 미리 끝내 주세요.' from marked;
  delete from public.ride_messages m using public.rides r
    where m.ride_id = r.id and now() >= r.departure_at + companion_private.flow_setting('chat_lifetime');
end $$;

-- ---------------------------------------------------------------------------
-- Public RPCs retain caller identity; guarded implementations are not exposed.
-- ---------------------------------------------------------------------------
create or replace function public.request_join(p_ride_id uuid) returns void
language sql security invoker set search_path = '' as $$ select companion_private.request_join(p_ride_id); $$;
create or replace function public.approve_applicant(p_ride_id uuid, p_user_id uuid) returns void
language sql security invoker set search_path = '' as $$ select companion_private.approve_applicant(p_ride_id, p_user_id); $$;
create or replace function public.reject_applicant(p_ride_id uuid, p_user_id uuid) returns void
language sql security invoker set search_path = '' as $$ select companion_private.reject_applicant(p_ride_id, p_user_id); $$;
create or replace function public.kick_participant(p_ride_id uuid, p_user_id uuid) returns void
language sql security invoker set search_path = '' as $$ select companion_private.kick_participant(p_ride_id, p_user_id); $$;
create or replace function public.leave_ride(p_ride_id uuid) returns void
language sql security invoker set search_path = '' as $$ select companion_private.leave_ride(p_ride_id); $$;
create or replace function public.cancel_ride(p_ride_id uuid) returns void
language sql security invoker set search_path = '' as $$ select companion_private.cancel_ride(p_ride_id); $$;
create or replace function public.send_ride_message(p_ride_id uuid, p_body text) returns jsonb
language sql security invoker set search_path = '' as $$ select companion_private.send_ride_message(p_ride_id, p_body); $$;
create or replace function public.confirm_boarding(p_ride_id uuid) returns void
language sql security invoker set search_path = '' as $$ select companion_private.confirm_boarding(p_ride_id); $$;
create or replace function public.answer_absence(p_ride_id uuid, p_user_id uuid, p_present boolean) returns void
language sql security invoker set search_path = '' as $$ select companion_private.answer_absence(p_ride_id, p_user_id, p_present); $$;
create or replace function public.confirm_arrival(p_ride_id uuid) returns void
language sql security invoker set search_path = '' as $$ select companion_private.confirm_arrival(p_ride_id); $$;
create or replace function public.get_ride_flow_state(p_ride_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select companion_private.ride_flow_state(p_ride_id); $$;
-- Marker read by the app: missing function = this migration is not applied.
create or replace function public.ride_flow_module_version() returns integer
language sql stable security invoker set search_path = '' as $$ select 1; $$;

-- Internal helpers: owner only.
revoke all on function companion_private.ensure_host_membership(uuid), companion_private.ride_occupancy(uuid),
  companion_private.display_name(uuid), companion_private.post_system_message(uuid, text),
  companion_private.settle_ride(uuid), companion_private.reopen_if_seat(uuid)
  from public, anon, authenticated, service_role;
-- Guarded implementations: callable only through the public wrappers by signed-in users.
revoke all on function companion_private.request_join(uuid), companion_private.approve_applicant(uuid, uuid),
  companion_private.reject_applicant(uuid, uuid), companion_private.kick_participant(uuid, uuid),
  companion_private.leave_ride(uuid), companion_private.cancel_ride(uuid),
  companion_private.send_ride_message(uuid, text), companion_private.confirm_boarding(uuid),
  companion_private.answer_absence(uuid, uuid, boolean), companion_private.confirm_arrival(uuid),
  companion_private.ride_flow_state(uuid)
  from public, anon, authenticated, service_role;
grant execute on function companion_private.request_join(uuid), companion_private.approve_applicant(uuid, uuid),
  companion_private.reject_applicant(uuid, uuid), companion_private.kick_participant(uuid, uuid),
  companion_private.leave_ride(uuid), companion_private.cancel_ride(uuid),
  companion_private.send_ride_message(uuid, text), companion_private.confirm_boarding(uuid),
  companion_private.answer_absence(uuid, uuid, boolean), companion_private.confirm_arrival(uuid),
  companion_private.ride_flow_state(uuid)
  to authenticated;
-- Remove PostgreSQL's default PUBLIC execute grant on every entry point.
revoke all on function public.request_join(uuid), public.approve_applicant(uuid, uuid),
  public.reject_applicant(uuid, uuid), public.kick_participant(uuid, uuid), public.leave_ride(uuid),
  public.cancel_ride(uuid), public.send_ride_message(uuid, text), public.confirm_boarding(uuid),
  public.answer_absence(uuid, uuid, boolean), public.confirm_arrival(uuid), public.get_ride_flow_state(uuid),
  public.ride_flow_module_version(), public.process_ride_flow_timers()
  from public, anon, authenticated;
grant execute on function public.request_join(uuid), public.approve_applicant(uuid, uuid),
  public.reject_applicant(uuid, uuid), public.kick_participant(uuid, uuid), public.leave_ride(uuid),
  public.cancel_ride(uuid), public.send_ride_message(uuid, text), public.confirm_boarding(uuid),
  public.answer_absence(uuid, uuid, boolean), public.confirm_arrival(uuid), public.get_ride_flow_state(uuid),
  public.ride_flow_module_version()
  to authenticated;
grant execute on function public.process_ride_flow_timers() to service_role;

-- Per-minute timers (pg_cron). Relative times only, so the cron time zone does not matter.
create extension if not exists pg_cron;
select cron.schedule('gachita-ride-flow-timers', '* * * * *', 'select public.process_ride_flow_timers();');
commit;
