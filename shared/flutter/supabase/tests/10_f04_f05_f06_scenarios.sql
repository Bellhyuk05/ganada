\set ON_ERROR_STOP 1
-- Helpers (test only) --------------------------------------------------------
create or replace function public.t_as(p uuid) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', coalesce(p::text, ''), false); end $$;
grant execute on function public.t_as(uuid) to anon, authenticated;
create or replace function public.t_expect(p_sql text, p_expected text) returns text language plpgsql as $$
begin
  execute p_sql;
  if p_expected is null then return 'ok'; end if;
  raise exception 'EXPECTED ERROR % BUT SUCCEEDED: %', p_expected, p_sql;
exception when others then
  if p_expected is not null and (sqlerrm = p_expected or sqlstate = p_expected) then return 'ok(' || p_expected || ')'; end if;
  raise exception 'UNEXPECTED: % [%] for %', sqlerrm, sqlstate, p_sql;
end $$;
grant execute on function public.t_expect(text, text) to anon, authenticated;
create table public.t_log(n serial, label text, ok boolean, detail text);
grant all on public.t_log to anon, authenticated; grant usage on sequence t_log_n_seq to anon, authenticated;
create or replace function public.t_check(p_label text, p_ok boolean, p_detail text default null) returns void language plpgsql as $$
begin insert into public.t_log(label, ok, detail) values (p_label, coalesce(p_ok, false), p_detail);
  if not coalesce(p_ok, false) then raise warning 'FAIL: % %', p_label, coalesce(p_detail, ''); end if; end $$;
grant execute on function public.t_check(text, boolean, text) to anon, authenticated;

-- Fixtures --------------------------------------------------------------------
insert into auth.users(id) values
 ('00000000-0000-0000-0000-00000000000a'), ('00000000-0000-0000-0000-00000000000b'),
 ('00000000-0000-0000-0000-00000000000c'), ('00000000-0000-0000-0000-00000000000d'),
 ('00000000-0000-0000-0000-0000000000ff');
insert into public.profiles(id, display_name) values
 ('00000000-0000-0000-0000-0000000000ff', '방장'), ('00000000-0000-0000-0000-00000000000a', '에이'),
 ('00000000-0000-0000-0000-00000000000b', '비'), ('00000000-0000-0000-0000-00000000000c', '씨'),
 ('00000000-0000-0000-0000-00000000000d', '디');
-- R1: capacity 3, departs in 1 hour. Host row intentionally missing (F-02 not wired yet).
insert into public.rides(id, host_id, origin_name, destination_name, capacity, departure_at) values
 ('11111111-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000ff', '기숙사', '충주역', 3, now() + interval '1 hour');
\set H '''00000000-0000-0000-0000-0000000000ff'''
\set A '''00000000-0000-0000-0000-00000000000a'''
\set B '''00000000-0000-0000-0000-00000000000b'''
\set C '''00000000-0000-0000-0000-00000000000c'''
\set D '''00000000-0000-0000-0000-00000000000d'''
\set R1 '''11111111-0000-0000-0000-000000000001'''

-- F-04 ------------------------------------------------------------------------
set role authenticated;
select t_as(:A); select t_expect('select public.request_join(' || quote_literal(:R1) || ')', null);
select t_expect('select public.request_join(' || quote_literal(:R1) || ')', null); -- identical retry
select t_check('A pending', (select status from public.ride_memberships where ride_id = :R1 and user_id = :A) = 'pending');
select t_as(:H); select t_expect('select public.request_join(' || quote_literal(:R1) || ')', 'join_host');
select t_as(:B); select t_expect('select public.request_join(' || quote_literal(:R1) || ')', null);
select t_as(:A); select t_expect(format('select public.approve_applicant(%L,%L)', :R1, :B), 'host_only');
select t_as(:H);
select t_check('host sees 2 applicants', jsonb_array_length(public.list_ride_applicants(:R1)) = 2);
select t_expect(format('select public.approve_applicant(%L,%L)', :R1, :A), null);
select t_expect(format('select public.approve_applicant(%L,%L)', :R1, :A), 'applicant_missing');
select t_expect(format('select public.approve_applicant(%L,%L)', :R1, :B), null);
reset role;
select t_check('R1 full after 2 approvals', (select status from public.rides where id = :R1) = 'full');
select t_check('host row backfilled', exists (select 1 from public.ride_memberships where ride_id = :R1 and user_id = :H and status = 'approved'));
select t_check('roster lists host+A+B', (select count(*) from public.ride_memberships where ride_id = :R1 and status = 'approved') = 3);
set role authenticated;
select t_as(:C); select t_expect('select public.request_join(' || quote_literal(:R1) || ')', 'join_closed');
select t_as(:B); select t_expect('select public.leave_ride(' || quote_literal(:R1) || ')', null);
reset role;
select t_check('reopened after leave', (select status from public.rides where id = :R1) = 'recruiting');
set role authenticated;
select t_as(:C); select t_expect('select public.request_join(' || quote_literal(:R1) || ')', null);
select t_as(:H); select t_expect(format('select public.reject_applicant(%L,%L)', :R1, :C), null);
select t_as(:C);
select t_check('C sees own reject', (select status from public.ride_memberships where ride_id = :R1 and user_id = :C) = 'reject');
select t_expect('select public.request_join(' || quote_literal(:R1) || ')', null); -- re-apply after reject
select t_as(:H); select t_expect(format('select public.approve_applicant(%L,%L)', :R1, :C), null);
select t_expect(format('select public.kick_participant(%L,%L)', :R1, :C), null);
select t_expect(format('select public.kick_participant(%L,%L)', :R1, :H), 'participant_missing');
select t_expect('select public.leave_ride(' || quote_literal(:R1) || ')', 'host_cannot_leave');
select t_as(:C); select t_expect('select public.request_join(' || quote_literal(:R1) || ')', 'join_kicked');
-- pending applicant withdraws
select t_as(:D); select t_expect('select public.request_join(' || quote_literal(:R1) || ')', null);
select t_expect('select public.leave_ride(' || quote_literal(:R1) || ')', null);
select t_check('D withdrawn', not exists (select 1 from public.ride_memberships where ride_id = :R1 and user_id = :D));

-- F-05 ------------------------------------------------------------------------
select t_as(:A);
select t_check('A sends', (public.send_ride_message(:R1, '  안녕하세요  ')->>'body') = '안녕하세요');
select t_expect(format('select public.send_ride_message(%L,%L)', :R1, '   '), 'message_invalid');
select t_check('A reads messages (system + own)', (select count(*) from public.ride_messages where ride_id = :R1) >= 5);
select t_check('A cannot insert directly', (select t_expect(format('insert into public.ride_messages(ride_id,kind,body) values (%L,''system'',''x'')', :R1), '42501')) like 'ok%');
select t_as(:C);
select t_check('kicked C reads nothing', (select count(*) from public.ride_messages where ride_id = :R1) = 0);
select t_expect(format('select public.send_ride_message(%L,%L)', :R1, 'hi'), 'chat_closed');
select t_expect(format('select public.get_ride_flow_state(%L)', :R1), '42501');
select t_as(:B);
select t_check('left B reads nothing', (select count(*) from public.ride_messages where ride_id = :R1) = 0);
reset role; set role anon; select t_as(null);
select t_expect(format('select public.request_join(%L)', :R1), '42501');
select t_expect('select count(*) from public.ride_messages', '42501');
reset role;

-- F-06 on R1 (members: host, A) ----------------------------------------------
set role authenticated; select t_as(:A);
select t_expect(format('select public.confirm_boarding(%L)', :R1), 'boarding_not_open');
select t_check('phase before', (public.get_ride_flow_state(:R1)->>'phase') = 'before');
reset role; update public.rides set departure_at = now() - interval '1 minute' where id = :R1; set role authenticated;
select t_as(:A);
select t_check('phase boarding', (public.get_ride_flow_state(:R1)->>'phase') = 'boarding');
select t_expect(format('select public.answer_absence(%L,%L,false)', :R1, :H), 'answer_ineligible');
select t_expect(format('select public.confirm_boarding(%L)', :R1), null);
select t_expect(format('select public.confirm_boarding(%L)', :R1), null); -- idempotent
select t_check('not departed yet', (public.get_ride_flow_state(:R1)->>'departed_at') is null);
select t_as(:H); select t_expect(format('select public.kick_participant(%L,%L)', :R1, :A), null); -- still allowed before 출발 처리
select t_as(:A); select t_check('kicked A loses state', (select t_expect(format('select public.get_ride_flow_state(%L)', :R1), '42501')) like 'ok%');
reset role;
-- fresh ride R2 for the absence flow: host, A, B ------------------------------------
insert into public.rides(id, host_id, origin_name, destination_name, capacity, departure_at) values
 ('22222222-0000-0000-0000-000000000002', :H, '학교 정문', '터미널', 4, now() + interval '1 hour');
\set R2 '''22222222-0000-0000-0000-000000000002'''
insert into public.ride_memberships(ride_id, user_id, status) values (:R2, :H, 'approved'); -- F-02 style host row
set role authenticated;
select t_as(:A); select public.request_join(:R2); select t_as(:B); select public.request_join(:R2);
select t_as(:H); select public.approve_applicant(:R2, :A); select public.approve_applicant(:R2, :B);
reset role; update public.rides set departure_at = now() - interval '2 minutes' where id = :R2; set role authenticated;
select t_as(:A); select public.confirm_boarding(:R2);
select public.answer_absence(:R2, :B, true);    -- 왔어요
select t_expect(format('select public.answer_absence(%L,%L,true)', :R2, :B), 'absence_resolved');
select t_check('B vouched boarded', (select (m->>'boarded_at') is not null from jsonb_array_elements(public.get_ride_flow_state(:R2)->'members') m where m->>'id' = :B));
select public.answer_absence(:R2, :H, false);   -- 안 왔어요 → departs
select t_check('R2 departed', (public.get_ride_flow_state(:R2)->>'phase') = 'departed');
select t_as(:H);
select t_expect(format('select public.confirm_boarding(%L)', :R2), 'boarding_closed');
select t_expect(format('select public.confirm_arrival(%L)', :R2), 'answer_ineligible'); -- no-show host
select t_expect(format('select public.kick_participant(%L,%L)', :R2, :A), 'kick_closed');
select t_as(:B); select t_expect(format('select public.leave_ride(%L)', :R2), 'leave_closed');
select t_expect(format('select public.confirm_arrival(%L)', :R2), null);
select t_expect(format('select public.confirm_arrival(%L)', :R2), null); -- idempotent
select t_check('R2 ended', (public.get_ride_flow_state(:R2)->>'phase') = 'ended');
-- F-07 compatibility: A can rate B (not the no-show host)
select t_as(:A);
select t_check('rating task targets only B',
  (select jsonb_agg(t->'id') from jsonb_array_elements((public.list_rating_tasks()->0)->'targets') t) = jsonb_build_array(:B::text));
select t_expect(format('select public.submit_ratings(%L, %L::jsonb)', :R2, jsonb_build_array(jsonb_build_object('target_id', :B, 'half_units', 9))), null);
reset role;
select t_check('host recorded no_show', (select no_show from public.ride_memberships where ride_id = :R2 and user_id = :H));
select public.refresh_profile_stats();
select t_check('stats: host no_show_count 1', (select no_show_count from public.profile_stats where user_id = :H) = 1);
select t_check('stats: B participation 1', (select participation_count from public.profile_stats where user_id = :B) = 1);

-- Timers ----------------------------------------------------------------------
-- R3: A boarded, host silent, 15 min after departure → host auto no-show and departure.
insert into public.rides(id, host_id, origin_name, destination_name, capacity, departure_at, status) values
 ('33333333-0000-0000-0000-000000000003', :H, 'a', 'b', 2, now() - interval '15 minutes', 'full'),
 ('44444444-0000-0000-0000-000000000004', :H, 'a', 'b', 2, now() - interval '2 hours', 'full'),
 ('55555555-0000-0000-0000-000000000005', :H, 'a', 'b', 2, now() - interval '5 hours', 'full'),
 ('66666666-0000-0000-0000-000000000006', :H, 'a', 'b', 2, now() - interval '13 hours', 'completed'),
 ('77777777-0000-0000-0000-000000000007', :H, 'a', 'b', 2, now() - interval '690 minutes', 'completed');
insert into public.ride_memberships(ride_id, user_id, status, boarded_at) values
 ('33333333-0000-0000-0000-000000000003', :A, 'approved', now() - interval '14 minutes'),
 ('44444444-0000-0000-0000-000000000004', :A, 'approved', null),
 ('55555555-0000-0000-0000-000000000005', :A, 'approved', now() - interval '4 hours');
update public.rides set departed_at = now() - interval '4 hours' where id = '55555555-0000-0000-0000-000000000005';
insert into public.ride_messages(ride_id, kind, body) values
 ('66666666-0000-0000-0000-000000000006', 'system', 'old'), ('77777777-0000-0000-0000-000000000007', 'system', 'recent');
select public.process_ride_flow_timers();
select public.process_ride_flow_timers(); -- second run must not duplicate anything
select t_check('R3 host auto no-show', (select no_show from public.ride_memberships where ride_id = '33333333-0000-0000-0000-000000000003' and user_id = :H));
select t_check('R3 departed', (select departed_at is not null from public.rides where id = '33333333-0000-0000-0000-000000000003'));
select t_check('R4 closed without departure/no-show', (select status = 'completed' and departed_at is null and ended_at is not null from public.rides where id = '44444444-0000-0000-0000-000000000004')
  and not exists (select 1 from public.ride_memberships where ride_id = '44444444-0000-0000-0000-000000000004' and no_show));
select t_check('R5 auto arrival', (select status = 'completed' and ended_at is not null from public.rides where id = '55555555-0000-0000-0000-000000000005'));
select t_check('R6 chat purged', not exists (select 1 from public.ride_messages where ride_id = '66666666-0000-0000-0000-000000000006'));
select t_check('R7 single deletion warning', (select count(*) from public.ride_messages where ride_id = '77777777-0000-0000-0000-000000000007' and body like '1시간 후%') = 1);
-- cancel flow
insert into public.rides(id, host_id, origin_name, destination_name, capacity, departure_at) values
 ('88888888-0000-0000-0000-000000000008', :H, 'a', 'b', 3, now() + interval '30 minutes');
set role authenticated; select t_as(:H);
select t_expect(format('select public.cancel_ride(%L)', '88888888-0000-0000-0000-000000000008'), null);
select t_check('cancel phase', (public.get_ride_flow_state('88888888-0000-0000-0000-000000000008')->>'phase') = 'cancelled');
select t_as(:A); select t_expect(format('select public.request_join(%L)', '88888888-0000-0000-0000-000000000008'), 'join_closed');
-- Existing modules keep working: feed roster includes the host participant.
select t_as(:A);
select t_check('module marker', public.ride_flow_module_version() = 1);
reset role;
select label, ok, detail from public.t_log where not ok;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed from public.t_log;
