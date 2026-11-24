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
