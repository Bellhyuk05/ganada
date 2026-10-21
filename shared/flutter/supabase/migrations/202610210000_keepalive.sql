-- 무료 요금제 자동 일시정지(7일 무요청) 방지용.
-- .github/workflows/supabase-keepalive.yml 이 3일마다 이 함수를 호출한다.
-- 데이터를 읽거나 쓰지 않고 현재 시각만 돌려준다.
begin;
create or replace function public.keepalive() returns timestamptz
language sql stable security invoker set search_path = '' as $$
  select now();
$$;
revoke all on function public.keepalive() from public;
grant execute on function public.keepalive() to anon, authenticated;
commit;
