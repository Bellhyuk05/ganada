-- F-01 signup/login: school-email-only accounts and profile provisioning.
-- Apply after common_baseline. The app verifies a 6-digit email OTP (Supabase Auth),
-- sets a password, then calls f01_complete_signup to create its own profiles row.
-- Nickname is stored in profiles.display_name (common baseline field).
-- School domains: a.ut.ac.kr (students) and ut.ac.kr (staff)
-- (keep in sync with lib/features/auth/auth_config.dart).
begin;
create schema if not exists companion_private;
revoke all on schema companion_private from public, anon, authenticated;
grant usage on schema companion_private to authenticated;

-- Fail early if the common baseline is missing.
do $$ begin
  perform id, display_name from public.profiles limit 0;
end $$;

-- 1. Server-side guard: only school email addresses can become Auth users.
--    To create a non-school test user from the dashboard, temporarily run
--    alter table auth.users disable trigger f01_enforce_school_email;
create or replace function public.f01_enforce_school_email() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.email is null or lower(new.email) !~ '@(a\.)?ut\.ac\.kr$' then
    raise exception 'F01_SCHOOL_EMAIL_ONLY';
  end if;
  return new;
end $$;
revoke all on function public.f01_enforce_school_email() from anon, authenticated;
drop trigger if exists f01_enforce_school_email on auth.users;
create trigger f01_enforce_school_email
  before insert or update of email on auth.users
  for each row execute function public.f01_enforce_school_email();

-- 2. Profile fields for terms consent and case-insensitive unique nickname.
alter table public.profiles add column if not exists terms_version text;
alter table public.profiles add column if not exists terms_agreed_at timestamptz;
create unique index if not exists profiles_display_name_lower_key
  on public.profiles (lower(display_name));

-- 3. Guarded implementations (not exposed).
create or replace function companion_private.f01_nickname_available(p_nickname text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  return not exists(select 1 from public.profiles
    where lower(display_name) = lower(btrim(p_nickname)) and id <> auth.uid());
end $$;

create or replace function companion_private.f01_signup_completed() returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise insufficient_privilege; end if;
  return exists(select 1 from public.profiles where id = auth.uid());
end $$;

create or replace function companion_private.f01_complete_signup(p_nickname text, p_terms_version text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_nick text := btrim(p_nickname);
begin
  if v_uid is null then raise insufficient_privilege; end if;
  if lower(coalesce(auth.jwt() ->> 'email', '')) !~ '@(a\.)?ut\.ac\.kr$' then
    raise exception 'F01_SCHOOL_EMAIL_ONLY';
  end if;
  if v_nick is null or char_length(v_nick) not between 2 and 10 or v_nick !~ '^[가-힣a-zA-Z0-9]+$' then
    raise exception 'F01_NICKNAME_INVALID';
  end if;
  if coalesce(p_terms_version, '') = '' then raise exception 'F01_TERMS_REQUIRED'; end if;
  begin
    -- Existing rows (e.g. manually provisioned test users) keep their name; only consent is recorded.
    insert into public.profiles(id, display_name, terms_version, terms_agreed_at)
    values (v_uid, v_nick, p_terms_version, clock_timestamp())
    on conflict (id) do update
      set terms_version = excluded.terms_version, terms_agreed_at = excluded.terms_agreed_at;
  exception when unique_violation then
    raise exception 'F01_NICKNAME_TAKEN';
  end;
end $$;

-- 4. Public RPCs retain caller identity; guarded implementations are not exposed.
create or replace function public.f01_nickname_available(p_nickname text) returns boolean
language sql stable security invoker set search_path = '' as $$
  select companion_private.f01_nickname_available(p_nickname);
$$;
create or replace function public.f01_signup_completed() returns boolean
language sql stable security invoker set search_path = '' as $$
  select companion_private.f01_signup_completed();
$$;
create or replace function public.f01_complete_signup(p_nickname text, p_terms_version text) returns void
language sql security invoker set search_path = '' as $$
  select companion_private.f01_complete_signup(p_nickname, p_terms_version);
$$;

revoke all on function companion_private.f01_nickname_available(text), companion_private.f01_signup_completed(),
  companion_private.f01_complete_signup(text, text), public.f01_nickname_available(text),
  public.f01_signup_completed(), public.f01_complete_signup(text, text)
  from public, anon, authenticated, service_role;
grant execute on function companion_private.f01_nickname_available(text), companion_private.f01_signup_completed(),
  companion_private.f01_complete_signup(text, text), public.f01_nickname_available(text),
  public.f01_signup_completed(), public.f01_complete_signup(text, text) to authenticated;
commit;
