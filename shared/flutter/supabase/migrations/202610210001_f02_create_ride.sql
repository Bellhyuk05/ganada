-- F-02 동행팟 등록 (회의록 2026-09-21 F-02).
-- 앱의 "팟 올리기" → create_ride RPC 한 번으로 팟 생성 + 방장을 첫 참여자로 등록.
-- 규칙은 앱에서도 검사하지만, 최종 판단은 여기서 한다.
--   · 카테고리: 택시만 (카풀은 후순위)
--   · 출발지 ≠ 도착지, 각 40자 이하
--   · 출발 날짜: 오늘부터 7일 후까지 (한국 시각 기준), 지금보다 이후
--   · 출발 시각: 15분 단위 (00, 15, 30, 45분)
--   · 모집 인원: 본인 포함 2~4명
--   · 조건: 100자 이하
-- F-08 키워드 알림은 rides insert 트리거가 자동으로 처리한다.
begin;
create schema if not exists companion_private;
revoke all on schema companion_private from public, anon, authenticated;
grant usage on schema companion_private to authenticated;

do $$ begin
  perform id, host_id, origin_name, destination_name, condition_text, capacity,
    departure_at, status from public.rides limit 0;
  perform ride_id, user_id, status from public.ride_memberships limit 0;
end $$;

create or replace function companion_private.create_ride(
  p_category text,
  p_origin text,
  p_destination text,
  p_departure_at timestamptz,
  p_capacity integer,
  p_condition text
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_origin text := btrim(coalesce(p_origin, ''));
  v_destination text := btrim(coalesce(p_destination, ''));
  v_condition text := btrim(coalesce(p_condition, ''));
  v_local timestamp := p_departure_at at time zone 'Asia/Seoul';
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_id uuid;
begin
  if v_user is null then raise insufficient_privilege; end if;
  if not exists (select 1 from public.profiles where id = v_user) then
    raise exception 'ride_profile_missing';
  end if;
  if coalesce(p_category, '') <> 'taxi' then raise exception 'ride_category_unavailable'; end if;
  if v_origin = '' or v_destination = '' then raise exception 'ride_place_required'; end if;
  if char_length(v_origin) > 40 or char_length(v_destination) > 40 then raise exception 'ride_place_too_long'; end if;
  if lower(v_origin) = lower(v_destination) then raise exception 'ride_same_place'; end if;
  if p_departure_at is null or p_departure_at <= now() then raise exception 'ride_time_past'; end if;
  if v_local::date > v_today + 7 then raise exception 'ride_date_range'; end if;
  if extract(minute from v_local)::integer % 15 <> 0 or extract(second from v_local) <> 0 then
    raise exception 'ride_time_step';
  end if;
  if p_capacity is null or p_capacity not between 2 and 4 then raise exception 'ride_capacity'; end if;
  if char_length(v_condition) > 100 then raise exception 'ride_condition_too_long'; end if;
  -- 도배 방지: 동시에 모집 중인 내 팟은 3개까지
  if (select count(*) from public.rides
      where host_id = v_user and status in ('recruiting', 'full') and departure_at > now()) >= 3 then
    raise exception 'ride_host_limit';
  end if;

  insert into public.rides(host_id, origin_name, destination_name, condition_text, capacity, departure_at, status)
  values (v_user, v_origin, v_destination, v_condition, p_capacity, p_departure_at, 'recruiting')
  returning id into v_id;

  -- 방장은 첫 번째 참여자 (F-04 의 ensure_host_membership 과 같은 형태)
  insert into public.ride_memberships(ride_id, user_id, status)
  values (v_id, v_user, 'approved')
  on conflict (ride_id, user_id) do nothing;

  return v_id;
end $$;

create or replace function public.create_ride(
  p_category text,
  p_origin text,
  p_destination text,
  p_departure_at timestamptz,
  p_capacity integer,
  p_condition text
) returns uuid
language sql security invoker set search_path = '' as $$
  select companion_private.create_ride(p_category, p_origin, p_destination, p_departure_at, p_capacity, p_condition);
$$;

revoke all on function companion_private.create_ride(text, text, text, timestamptz, integer, text),
  public.create_ride(text, text, text, timestamptz, integer, text)
  from public, anon, authenticated, service_role;
grant execute on function companion_private.create_ride(text, text, text, timestamptz, integer, text),
  public.create_ride(text, text, text, timestamptz, integer, text) to authenticated;
commit;
