-- Spoorloos Quiz Night: run this once in Supabase SQL Editor.
-- Browser access goes through these RPCs only. Do not grant the browser direct table access.

create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  join_code text not null unique check (join_code ~ '^[0-9]{6}$'),
  host_token text not null,
  question text not null default '',
  round integer not null default 1,
  created_at timestamptz not null default now()
);

create table if not exists public.players (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  name text not null check (length(name) between 1 and 24),
  table_name text not null check (table_name ~ '^(Garden ([1-9]|1[0-9]|2[0-4])|Stoep [1-9]|Inside ([1-9]|1[0-7])|H[12])$'),
  player_token text not null,
  approved boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.buzzes (
  id bigint generated always as identity primary key,
  room_id uuid not null references public.rooms(id) on delete cascade,
  round integer not null,
  player_id uuid not null references public.players(id) on delete cascade,
  buzzed_at timestamptz not null default clock_timestamp(),
  unique (room_id, round, player_id)
);

create table if not exists public.scores (
  room_id uuid not null references public.rooms(id) on delete cascade,
  table_name text not null check (table_name ~ '^(Garden ([1-9]|1[0-9]|2[0-4])|Stoep [1-9]|Inside ([1-9]|1[0-7])|H[12])$'),
  points integer not null default 0,
  primary key (room_id, table_name)
);

-- Refresh these constraints if an earlier 8-table version of this setup was run.
alter table public.players drop constraint if exists players_table_name_check;
alter table public.scores drop constraint if exists scores_table_name_check;

-- Convert names from the previous generic Table 1..52 picker, if present.
update public.players set table_name = case
  when substring(table_name from 'Table ([0-9]+)')::integer between 1 and 24 then 'Garden ' || substring(table_name from 'Table ([0-9]+)')
  when substring(table_name from 'Table ([0-9]+)')::integer between 25 and 33 then 'Stoep ' || (substring(table_name from 'Table ([0-9]+)')::integer - 24)
  when substring(table_name from 'Table ([0-9]+)')::integer between 34 and 50 then 'Inside ' || (substring(table_name from 'Table ([0-9]+)')::integer - 33)
  when substring(table_name from 'Table ([0-9]+)')::integer between 51 and 52 then 'H' || (substring(table_name from 'Table ([0-9]+)')::integer - 50)
  else table_name end
where table_name ~ '^Table ([0-9]+)$';
update public.scores set table_name = case
  when substring(table_name from 'Table ([0-9]+)')::integer between 1 and 24 then 'Garden ' || substring(table_name from 'Table ([0-9]+)')
  when substring(table_name from 'Table ([0-9]+)')::integer between 25 and 33 then 'Stoep ' || (substring(table_name from 'Table ([0-9]+)')::integer - 24)
  when substring(table_name from 'Table ([0-9]+)')::integer between 34 and 50 then 'Inside ' || (substring(table_name from 'Table ([0-9]+)')::integer - 33)
  when substring(table_name from 'Table ([0-9]+)')::integer between 51 and 52 then 'H' || (substring(table_name from 'Table ([0-9]+)')::integer - 50)
  else table_name end
where table_name ~ '^Table ([0-9]+)$';

alter table public.scores add constraint scores_table_name_check
  check (table_name ~ '^(Garden ([1-9]|1[0-9]|2[0-4])|Stoep [1-9]|Inside ([1-9]|1[0-7])|H[12])$');
alter table public.players add constraint players_table_name_check
  check (table_name ~ '^(Garden ([1-9]|1[0-9]|2[0-4])|Stoep [1-9]|Inside ([1-9]|1[0-7])|H[12])$');
insert into public.scores(room_id, table_name)
select r.id, tables.table_name from public.rooms r cross join (
  select 'Garden ' || n as table_name from generate_series(1,24) as seq(n)
  union all select 'Stoep ' || n from generate_series(1,9) as seq(n)
  union all select 'Inside ' || n from generate_series(1,17) as seq(n)
  union all select 'H' || n from generate_series(1,2) as seq(n)
) as tables
on conflict (room_id, table_name) do nothing;

alter table public.rooms enable row level security;
alter table public.players enable row level security;
alter table public.buzzes enable row level security;
alter table public.scores enable row level security;
revoke all on public.rooms, public.players, public.buzzes, public.scores from anon, authenticated;

create or replace function public.create_game()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_code text; v_token text; v_id uuid;
begin
  loop
    v_code := (floor(random() * 900000) + 100000)::integer::text;
    exit when not exists (select 1 from public.rooms where join_code = v_code);
  end loop;
  v_token := gen_random_uuid()::text || gen_random_uuid()::text;
  insert into public.rooms(join_code, host_token) values (v_code, v_token) returning id into v_id;
  insert into public.scores(room_id, table_name)
  select v_id, 'Garden ' || n from generate_series(1, 24) as seq(n)
  union all select v_id, 'Stoep ' || n from generate_series(1, 9) as seq(n)
  union all select v_id, 'Inside ' || n from generate_series(1, 17) as seq(n)
  union all select v_id, 'H' || n from generate_series(1, 2) as seq(n);
  return jsonb_build_object('code', v_code, 'hostToken', v_token);
end;
$$;

create or replace function public.get_game(p_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.rooms%rowtype;
begin
  select * into v_room from public.rooms where join_code = upper(trim(p_code));
  if not found then raise exception 'Game code not found'; end if;
  return jsonb_build_object(
    'question', v_room.question,
    'round', v_room.round,
    'players', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'table', p.table_name, 'approved', p.approved) order by p.created_at)
      from public.players p where p.room_id = v_room.id), '[]'::jsonb),
    'buzzes', coalesce((select jsonb_agg(jsonb_build_object('id', b.player_id, 'name', p.name, 'table', p.table_name) order by b.buzzed_at, b.id)
      from public.buzzes b join public.players p on p.id = b.player_id where b.room_id = v_room.id and b.round = v_room.round), '[]'::jsonb),
    'scores', coalesce((select jsonb_agg(jsonb_build_object('table', s.table_name, 'points', s.points) order by s.table_name)
      from public.scores s where s.room_id = v_room.id), '[]'::jsonb)
  );
end;
$$;

create or replace function public.join_game(p_code text, p_name text, p_table text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room_id uuid; v_player public.players%rowtype; v_player_token text;
begin
  select id into v_room_id from public.rooms where join_code = upper(trim(p_code));
  if v_room_id is null then raise exception 'Game code not found'; end if;
  if p_table !~ '^(Garden ([1-9]|1[0-9]|2[0-4])|Stoep [1-9]|Inside ([1-9]|1[0-7])|H[12])$' then raise exception 'Choose a valid table'; end if;
  if length(trim(p_name)) = 0 then raise exception 'Enter your name'; end if;
  v_player_token := gen_random_uuid()::text || gen_random_uuid()::text;
  insert into public.players(room_id, name, table_name, player_token) values (v_room_id, left(trim(p_name), 24), p_table, v_player_token) returning * into v_player;
  return jsonb_build_object('player', jsonb_build_object('id', v_player.id, 'name', v_player.name, 'table', v_player.table_name, 'approved', v_player.approved), 'playerToken', v_player_token);
end;
$$;

create or replace function public.approve_player(p_code text, p_host_token text, p_player_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_room_id uuid;
begin
  select id into v_room_id from public.rooms where join_code = upper(trim(p_code)) and host_token = p_host_token;
  if v_room_id is null then raise exception 'Host session is invalid'; end if;
  update public.players set approved = true where id = p_player_id and room_id = v_room_id;
  if not found then raise exception 'Player not found'; end if;
  return true;
end;
$$;

create or replace function public.publish_question(p_code text, p_host_token text, p_question text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  update public.rooms set question = left(trim(p_question), 500)
  where join_code = upper(trim(p_code)) and host_token = p_host_token;
  if not found then raise exception 'Host session is invalid'; end if;
  return true;
end;
$$;

create or replace function public.new_round(p_code text, p_host_token text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  update public.rooms set round = round + 1
  where join_code = upper(trim(p_code)) and host_token = p_host_token;
  if not found then raise exception 'Host session is invalid'; end if;
  return true;
end;
$$;

create or replace function public.buzz(p_code text, p_player_token text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_room public.rooms%rowtype; v_approved boolean;
begin
  select * into v_room from public.rooms where join_code = upper(trim(p_code)) for update;
  if not found then raise exception 'Game code not found'; end if;
  select approved into v_approved from public.players where player_token = p_player_token and room_id = v_room.id;
  if coalesce(v_approved, false) = false then raise exception 'Player is waiting for host approval'; end if;
  insert into public.buzzes(room_id, round, player_id)
  select v_room.id, v_room.round, p.id from public.players p where p.player_token = p_player_token and p.room_id = v_room.id
  on conflict (room_id, round, player_id) do nothing;
  return true;
end;
$$;

create or replace function public.award_points(p_code text, p_host_token text, p_table text, p_points integer)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_room_id uuid;
begin
  select id into v_room_id from public.rooms where join_code = upper(trim(p_code)) and host_token = p_host_token;
  if v_room_id is null then raise exception 'Host session is invalid'; end if;
  if p_table !~ '^(Garden ([1-9]|1[0-9]|2[0-4])|Stoep [1-9]|Inside ([1-9]|1[0-7])|H[12])$' or p_points not in (1,2,3,5) then
    raise exception 'Choose a valid table and point amount';
  end if;
  update public.scores set points = points + p_points where room_id = v_room_id and table_name = p_table;
  return true;
end;
$$;

revoke execute on function public.create_game() from public, authenticated;
revoke execute on function public.get_game(text) from public, authenticated;
revoke execute on function public.join_game(text,text,text) from public, authenticated;
revoke execute on function public.approve_player(text,text,uuid) from public, authenticated;
revoke execute on function public.publish_question(text,text,text) from public, authenticated;
revoke execute on function public.new_round(text,text) from public, authenticated;
revoke execute on function public.buzz(text,text) from public, authenticated;
revoke execute on function public.award_points(text,text,text,integer) from public, authenticated;
grant execute on function public.create_game() to anon;
grant execute on function public.get_game(text) to anon;
grant execute on function public.join_game(text,text,text) to anon;
grant execute on function public.approve_player(text,text,uuid) to anon;
grant execute on function public.publish_question(text,text,text) to anon;
grant execute on function public.new_round(text,text) to anon;
grant execute on function public.buzz(text,text) to anon;
grant execute on function public.award_points(text,text,text,integer) to anon;

-- Host authentication and buzzer answer queue (run after the original setup).
create table if not exists public.quiz_hosts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.quiz_hosts enable row level security;
revoke all on public.quiz_hosts from anon, authenticated;

create or replace function public.is_authorized_host()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.quiz_hosts h where h.user_id = (select auth.uid()));
$$;
revoke all on function public.is_authorized_host() from public, anon;
grant execute on function public.is_authorized_host() to authenticated;

alter table public.rooms add column if not exists round_closed boolean not null default false;
alter table public.buzzes add column if not exists table_name text;
alter table public.buzzes add column if not exists resolved boolean not null default false;
alter table public.buzzes add column if not exists is_correct boolean;
update public.buzzes b set table_name=p.table_name from public.players p where p.id=b.player_id and b.table_name is null;
with ranked as (
  select id, row_number() over(partition by room_id, round, table_name order by buzzed_at, id) as rn
  from public.buzzes
)
delete from public.buzzes b using ranked r where b.id=r.id and r.rn>1;
alter table public.buzzes alter column table_name set not null;
alter table public.buzzes drop constraint if exists buzzes_room_id_round_player_id_key;
alter table public.buzzes drop constraint if exists buzzes_room_round_table_key;
alter table public.buzzes add constraint buzzes_room_round_table_key unique(room_id, round, table_name);

create or replace function public.create_game()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_code text; v_token text; v_id uuid;
begin
  if not public.is_authorized_host() then raise exception 'Host sign-in required'; end if;
  loop v_code := (floor(random() * 900000) + 100000)::integer::text; exit when not exists (select 1 from public.rooms where join_code=v_code); end loop;
  v_token := gen_random_uuid()::text || gen_random_uuid()::text;
  insert into public.rooms(join_code,host_token) values(v_code,v_token) returning id into v_id;
  insert into public.scores(room_id,table_name)
  select v_id,'Garden '||n from generate_series(1,24) seq(n) union all select v_id,'Stoep '||n from generate_series(1,9) seq(n) union all select v_id,'Inside '||n from generate_series(1,17) seq(n) union all select v_id,'H'||n from generate_series(1,2) seq(n);
  return jsonb_build_object('code',v_code,'hostToken',v_token);
end $$;

create or replace function public.get_game(p_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.rooms%rowtype;
begin
 select * into v_room from public.rooms where join_code=upper(trim(p_code));
 if not found then raise exception 'Game code not found'; end if;
 return jsonb_build_object('question',v_room.question,'round',v_room.round,'roundClosed',v_room.round_closed,
 'players',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'table',p.table_name,'approved',p.approved) order by p.created_at) from public.players p where p.room_id=v_room.id),'[]'::jsonb),
 'buzzes',coalesce((select jsonb_agg(jsonb_build_object('id',b.player_id,'name',p.name,'table',b.table_name,'resolved',b.resolved,'isCorrect',b.is_correct) order by b.buzzed_at,b.id) from public.buzzes b join public.players p on p.id=b.player_id where b.room_id=v_room.id and b.round=v_room.round),'[]'::jsonb),
 'scores',coalesce((select jsonb_agg(jsonb_build_object('table',s.table_name,'points',s.points) order by s.table_name) from public.scores s where s.room_id=v_room.id),'[]'::jsonb));
end $$;

create or replace function public.approve_player(p_code text,p_host_token text,p_player_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_room_id uuid;
begin
 if not public.is_authorized_host() then raise exception 'Host sign-in required'; end if;
 select id into v_room_id from public.rooms where join_code=upper(trim(p_code)) and host_token=p_host_token;
 if v_room_id is null then raise exception 'Host session is invalid'; end if;
 update public.players set approved=true where id=p_player_id and room_id=v_room_id;
 if not found then raise exception 'Player not found'; end if; return true;
end $$;

create or replace function public.publish_question(p_code text,p_host_token text,p_question text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
 if not public.is_authorized_host() then raise exception 'Host sign-in required'; end if;
 update public.rooms set question=left(trim(p_question),500) where join_code=upper(trim(p_code)) and host_token=p_host_token;
 if not found then raise exception 'Host session is invalid'; end if; return true;
end $$;

create or replace function public.new_round(p_code text,p_host_token text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
 if not public.is_authorized_host() then raise exception 'Host sign-in required'; end if;
 update public.rooms set round=round+1,round_closed=false where join_code=upper(trim(p_code)) and host_token=p_host_token;
 if not found then raise exception 'Host session is invalid'; end if; return true;
end $$;

create or replace function public.buzz(p_code text,p_player_token text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_room public.rooms%rowtype; v_player public.players%rowtype;
begin
 select * into v_room from public.rooms where join_code=upper(trim(p_code)) for update;
 if not found then raise exception 'Game code not found'; end if;
 if v_room.round_closed then raise exception 'This buzzer round is closed'; end if;
 select * into v_player from public.players where player_token=p_player_token and room_id=v_room.id;
 if not found or not v_player.approved then raise exception 'Player is waiting for host approval'; end if;
 insert into public.buzzes(room_id,round,player_id,table_name) values(v_room.id,v_room.round,v_player.id,v_player.table_name) on conflict(room_id,round,table_name) do nothing;
 return true;
end $$;

create or replace function public.resolve_buzz(p_code text,p_host_token text,p_correct boolean,p_points integer)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_room public.rooms%rowtype; v_buzz public.buzzes%rowtype;
begin
 if not public.is_authorized_host() then raise exception 'Host sign-in required'; end if;
 if p_points not in (1,2,3,5) then raise exception 'Choose a valid point amount'; end if;
 select * into v_room from public.rooms where join_code=upper(trim(p_code)) and host_token=p_host_token for update;
 if not found then raise exception 'Host session is invalid'; end if;
 select * into v_buzz from public.buzzes where room_id=v_room.id and round=v_room.round and not resolved order by buzzed_at,id limit 1 for update;
 if not found then raise exception 'No table is waiting to answer'; end if;
 if p_correct then
   update public.buzzes set resolved=true,is_correct=true where id=v_buzz.id;
   update public.scores set points=points+p_points where room_id=v_room.id and table_name=v_buzz.table_name;
   update public.rooms set round_closed=true where id=v_room.id;
 else
   -- Remove the missed table from the active queue. It can buzz again and rejoins at the back.
   delete from public.buzzes where id=v_buzz.id;
 end if;
 return true;
end $$;

revoke execute on function public.create_game() from public,anon;
revoke execute on function public.get_game(text) from public,authenticated;
revoke execute on function public.approve_player(text,text,uuid) from public,anon;
revoke execute on function public.publish_question(text,text,text) from public,anon;
revoke execute on function public.new_round(text,text) from public,anon;
revoke execute on function public.buzz(text,text) from public,authenticated;
revoke execute on function public.resolve_buzz(text,text,boolean,integer) from public,anon;
revoke execute on function public.is_authorized_host() from public,anon;
grant execute on function public.create_game() to authenticated;
grant execute on function public.get_game(text) to anon;
grant execute on function public.approve_player(text,text,uuid) to authenticated;
grant execute on function public.publish_question(text,text,text) to authenticated;
grant execute on function public.new_round(text,text) to authenticated;
grant execute on function public.buzz(text,text) to anon;
grant execute on function public.resolve_buzz(text,text,boolean,integer) to authenticated;
grant execute on function public.is_authorized_host() to authenticated;

-- Remove the old unrestricted manual scoring endpoint; scoring now only happens
-- inside resolve_buzz after an authorized host confirms a correct answer.
revoke execute on function public.award_points(text,text,text,integer) from public, anon, authenticated;
grant execute on function public.get_game(text) to authenticated;


-- Quiz length, quarter reward checkpoints, and explicit end-of-game controls.
alter table public.rooms add column if not exists total_questions integer not null default 20 check (total_questions between 4 and 100);
alter table public.rooms add column if not exists question_no integer not null default 1 check (question_no between 1 and 100);
alter table public.rooms add column if not exists questions_completed integer not null default 0 check (questions_completed between 0 and 100);
alter table public.rooms add column if not exists ended boolean not null default false;

create table if not exists public.reward_milestones (
  room_id uuid not null references public.rooms(id) on delete cascade,
  milestone integer not null check (milestone between 1 and 4),
  question_number integer not null check (question_number between 1 and 100),
  awarded_to text check (awarded_to is null or awarded_to ~ '^(Garden ([1-9]|1[0-9]|2[0-4])|Stoep [1-9]|Inside ([1-9]|1[0-7])|H[12])$'),
  awarded_at timestamptz,
  primary key (room_id, milestone)
);
alter table public.reward_milestones enable row level security;
revoke all on public.reward_milestones from anon, authenticated;
insert into public.reward_milestones(room_id,milestone,question_number)
select r.id,m.milestone,ceil(r.total_questions::numeric*m.milestone/4)::integer
from public.rooms r cross join generate_series(1,4) as m(milestone)
on conflict (room_id,milestone) do nothing;

-- The no-argument creator is retired so every new room has a chosen question count.
revoke execute on function public.create_game() from public,anon,authenticated;
create or replace function public.create_game(p_total_questions integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_code text; v_token text; v_id uuid;
begin
  if not public.is_authorized_host() then raise exception 'Host sign-in required'; end if;
  if p_total_questions not between 4 and 100 then raise exception 'Choose between 4 and 100 questions'; end if;
  loop v_code := (floor(random() * 900000) + 100000)::integer::text; exit when not exists (select 1 from public.rooms where join_code=v_code); end loop;
  v_token := gen_random_uuid()::text || gen_random_uuid()::text;
  insert into public.rooms(join_code,host_token,total_questions,question_no,questions_completed,ended)
  values(v_code,v_token,p_total_questions,1,0,false) returning id into v_id;
  insert into public.scores(room_id,table_name)
  select v_id,'Garden '||n from generate_series(1,24) seq(n)
  union all select v_id,'Stoep '||n from generate_series(1,9) seq(n)
  union all select v_id,'Inside '||n from generate_series(1,17) seq(n)
  union all select v_id,'H'||n from generate_series(1,2) seq(n);
  insert into public.reward_milestones(room_id,milestone,question_number)
  select v_id,m,ceil(p_total_questions::numeric*m/4)::integer from generate_series(1,4) as seq(m);
  return jsonb_build_object('code',v_code,'hostToken',v_token,'totalQuestions',p_total_questions);
end $$;

create or replace function public.get_game(p_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.rooms%rowtype;
begin
 select * into v_room from public.rooms where join_code=upper(trim(p_code));
 if not found then raise exception 'Game code not found'; end if;
 return jsonb_build_object(
  'question',v_room.question,'round',v_room.round,'roundClosed',v_room.round_closed,
  'questionNo',v_room.question_no,'totalQuestions',v_room.total_questions,
  'questionsCompleted',v_room.questions_completed,'ended',v_room.ended,
  'players',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'table',p.table_name,'approved',p.approved) order by p.created_at) from public.players p where p.room_id=v_room.id),'[]'::jsonb),
  'buzzes',coalesce((select jsonb_agg(jsonb_build_object('id',b.player_id,'name',p.name,'table',b.table_name,'resolved',b.resolved,'isCorrect',b.is_correct) order by b.buzzed_at,b.id) from public.buzzes b join public.players p on p.id=b.player_id where b.room_id=v_room.id and b.round=v_room.round),'[]'::jsonb),
  'scores',coalesce((select jsonb_agg(jsonb_build_object('table',s.table_name,'points',s.points) order by s.table_name) from public.scores s where s.room_id=v_room.id),'[]'::jsonb),
  'rewards',coalesce((select jsonb_agg(jsonb_build_object('milestone',m.milestone,'question',m.question_number,'awardedTo',m.awarded_to) order by m.milestone) from public.reward_milestones m where m.room_id=v_room.id),'[]'::jsonb));
end $$;

create or replace function public.join_game(p_code text,p_name text,p_table text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_room public.rooms%rowtype; v_player public.players%rowtype; v_player_token text;
begin
 select * into v_room from public.rooms where join_code=upper(trim(p_code));
 if not found then raise exception 'Game code not found'; end if;
 if v_room.ended then raise exception 'This game has ended'; end if;
 if p_table !~ '^(Garden ([1-9]|1[0-9]|2[0-4])|Stoep [1-9]|Inside ([1-9]|1[0-7])|H[12])$' then raise exception 'Choose a valid table'; end if;
 if length(trim(p_name))=0 then raise exception 'Enter your name'; end if;
 v_player_token:=gen_random_uuid()::text||gen_random_uuid()::text;
 insert into public.players(room_id,name,table_name,player_token) values(v_room.id,left(trim(p_name),24),p_table,v_player_token) returning * into v_player;
 return jsonb_build_object('player',jsonb_build_object('id',v_player.id,'name',v_player.name,'table',v_player.table_name,'approved',v_player.approved),'playerToken',v_player_token);
end $$;

create or replace function public.approve_player(p_code text,p_host_token text,p_player_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_room_id uuid;
begin
 if not public.is_authorized_host() then raise exception 'Host sign-in required'; end if;
 select id into v_room_id from public.rooms where join_code=upper(trim(p_code)) and host_token=p_host_token and not ended;
 if v_room_id is null then raise exception 'Host session is invalid or the game has ended'; end if;
 update public.players set approved=true where id=p_player_id and room_id=v_room_id;
 if not found then raise exception 'Player not found'; end if; return true;
end $$;

create or replace function public.publish_question(p_code text,p_host_token text,p_question text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
 if not public.is_authorized_host() then raise exception 'Host sign-in required'; end if;
 update public.rooms set question=left(trim(p_question),500) where join_code=upper(trim(p_code)) and host_token=p_host_token and not ended;
 if not found then raise exception 'Host session is invalid or the game has ended'; end if; return true;
end $$;

create or replace function public.buzz(p_code text,p_player_token text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_room public.rooms%rowtype; v_player public.players%rowtype;
begin
 select * into v_room from public.rooms where join_code=upper(trim(p_code)) for update;
 if not found then raise exception 'Game code not found'; end if;
 if v_room.ended or v_room.round_closed then raise exception 'This buzzer round is closed'; end if;
 select * into v_player from public.players where player_token=p_player_token and room_id=v_room.id;
 if not found or not v_player.approved then raise exception 'Player is waiting for host approval'; end if;
 insert into public.buzzes(room_id,round,player_id,table_name) values(v_room.id,v_room.round,v_player.id,v_player.table_name) on conflict(room_id,round,table_name) do nothing;
 return true;
end $$;

create or replace function public.next_question(p_code text,p_host_token text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_room public.rooms%rowtype; v_completed integer;
begin
 if not public.is_authorized_host() then raise exception 'Host sign-in required'; end if;
 select * into v_room from public.rooms where join_code=upper(trim(p_code)) and host_token=p_host_token for update;
 if not found then raise exception 'Host session is invalid'; end if;
 if v_room.ended then raise exception 'The game has already ended'; end if;
 if exists(select 1 from public.buzzes where room_id=v_room.id and round=v_room.round and not resolved) then raise exception 'Resolve the current buzzer queue before advancing'; end if;
 v_completed:=v_room.question_no;
 if v_completed>=v_room.total_questions then
   update public.rooms set questions_completed=v_completed,ended=true,round_closed=true where id=v_room.id;
 else
   update public.rooms set questions_completed=v_completed,question_no=v_completed+1,round=round+1,round_closed=false,question='' where id=v_room.id;
 end if;
 return true;
end $$;

create or replace function public.end_game(p_code text,p_host_token text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
 if not public.is_authorized_host() then raise exception 'Host sign-in required'; end if;
 update public.rooms set ended=true,round_closed=true where join_code=upper(trim(p_code)) and host_token=p_host_token and not ended;
 if not found then raise exception 'Host session is invalid or the game has already ended'; end if;
 return true;
end $$;

create or replace function public.mark_reward_given(p_code text,p_host_token text,p_milestone integer,p_table text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_room_id uuid;
begin
 if not public.is_authorized_host() then raise exception 'Host sign-in required'; end if;
 if p_milestone not between 1 and 4 or p_table !~ '^(Garden ([1-9]|1[0-9]|2[0-4])|Stoep [1-9]|Inside ([1-9]|1[0-7])|H[12])$' then raise exception 'Choose a valid reward checkpoint and table'; end if;
 select id into v_room_id from public.rooms where join_code=upper(trim(p_code)) and host_token=p_host_token;
 if v_room_id is null then raise exception 'Host session is invalid'; end if;
 update public.reward_milestones m set awarded_to=p_table,awarded_at=now()
 where m.room_id=v_room_id and m.milestone=p_milestone and m.question_number<=(select r.questions_completed from public.rooms r where r.id=v_room_id) and m.awarded_to is null;
 if not found then raise exception 'Reward checkpoint is not due or has already been recorded'; end if;
 return true;
end $$;

revoke execute on function public.create_game() from public,anon,authenticated;
revoke execute on function public.create_game(integer) from public,anon,authenticated;
revoke execute on function public.new_round(text,text) from public,anon,authenticated;
revoke execute on function public.get_game(text) from public,authenticated;
revoke execute on function public.join_game(text,text,text) from public,authenticated;
revoke execute on function public.approve_player(text,text,uuid) from public,anon;
revoke execute on function public.publish_question(text,text,text) from public,anon;
revoke execute on function public.buzz(text,text) from public,authenticated;
revoke execute on function public.next_question(text,text) from public,anon;
revoke execute on function public.end_game(text,text) from public,anon;
revoke execute on function public.mark_reward_given(text,text,integer,text) from public,anon;
revoke execute on function public.resolve_buzz(text,text,boolean,integer) from public,anon;
revoke execute on function public.award_points(text,text,text,integer) from public,anon,authenticated;
grant execute on function public.create_game(integer) to authenticated;
grant execute on function public.get_game(text) to anon,authenticated;
grant execute on function public.join_game(text,text,text) to anon;
grant execute on function public.approve_player(text,text,uuid) to authenticated;
grant execute on function public.publish_question(text,text,text) to authenticated;
grant execute on function public.buzz(text,text) to anon;
grant execute on function public.resolve_buzz(text,text,boolean,integer) to authenticated;
grant execute on function public.next_question(text,text) to authenticated;
grant execute on function public.end_game(text,text) to authenticated;
grant execute on function public.mark_reward_given(text,text,integer,text) to authenticated;
