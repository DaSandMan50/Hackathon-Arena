-- Hackathon Arena · Supabase setup
-- Paste this whole file into Supabase → SQL Editor → New query, then click Run.
-- Safe to run more than once.

create extension if not exists pgcrypto with schema extensions;

-- ---------- tables ----------
create table if not exists public.events (
  code        text primary key check (code ~ '^[A-Z0-9]{4,8}$'),
  data        jsonb not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Host passwords live in their own table that the website can never read.
create table if not exists public.event_secrets (
  code       text primary key references public.events(code) on delete cascade,
  host_hash  text not null
);

create table if not exists public.progress (
  event_code  text not null references public.events(code) on delete cascade,
  team_id     text not null check (length(team_id) <= 40),
  done        jsonb not null default '{}'::jsonb,
  finished    boolean not null default false,
  updated_at  timestamptz not null default now(),
  primary key (event_code, team_id)
);

create table if not exists public.scores (
  event_code  text not null references public.events(code) on delete cascade,
  id          text not null check (length(id) <= 120),
  judge       text not null check (length(judge) between 1 and 120),
  team_id     text not null check (length(team_id) <= 40),
  scores      jsonb not null default '{}'::jsonb,
  submitted   boolean not null default false,
  total       integer check (total is null or total between 0 and 10000),
  updated_at  timestamptz not null default now(),
  primary key (event_code, id)
);

-- ---------- row level security ----------
alter table public.events        enable row level security;
alter table public.event_secrets enable row level security;
alter table public.progress      enable row level security;
alter table public.scores        enable row level security;

revoke all on public.event_secrets from anon, authenticated;

drop policy if exists "anyone reads events"   on public.events;
drop policy if exists "anyone reads progress" on public.progress;
drop policy if exists "anyone reads scores"   on public.scores;
drop policy if exists "judges add scores"     on public.scores;
drop policy if exists "judges edit scores"    on public.scores;

-- Everyone with the site can read events, progress and scores (that's how join-by-code and the live board work).
create policy "anyone reads events"   on public.events   for select to anon, authenticated using (true);
create policy "anyone reads progress" on public.progress for select to anon, authenticated using (true);
create policy "anyone reads scores"   on public.scores   for select to anon, authenticated using (true);

-- Judges have no accounts, so anyone can add or update a scorecard on an event that exists.
create policy "judges add scores" on public.scores for insert to anon, authenticated
  with check (exists (select 1 from public.events e where e.code = event_code) and pg_column_size(scores) < 8000);
create policy "judges edit scores" on public.scores for update to anon, authenticated
  using (true) with check (pg_column_size(scores) < 8000);

-- Events and team progress are only changed through the functions below.

-- ---------- functions ----------
create or replace function public.create_event(p_data jsonb, p_password text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare
  alphabet text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text;
begin
  if p_password is null or length(p_password) < 4 then raise exception 'Host password must be at least 4 characters'; end if;
  if pg_column_size(p_data) > 200000 then raise exception 'Event is too large'; end if;
  loop
    v_code := '';
    for i in 1..5 loop
      v_code := v_code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from events where code = v_code);
  end loop;
  insert into events(code, data) values (v_code, p_data);
  insert into event_secrets(code, host_hash) values (v_code, crypt(p_password, gen_salt('bf')));
  return v_code;
end $$;

create or replace function public.verify_host(p_code text, p_password text)
returns boolean language sql security definer set search_path = public, extensions as $$
  select exists (select 1 from event_secrets s where s.code = p_code and s.host_hash = crypt(p_password, s.host_hash));
$$;

create or replace function public.update_event(p_code text, p_password text, p_data jsonb)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if not verify_host(p_code, p_password) then return false; end if;
  if pg_column_size(p_data) > 200000 then raise exception 'Event is too large'; end if;
  update events set data = p_data, updated_at = now() where code = p_code;
  return true;
end $$;

create or replace function public.reset_event(p_code text, p_password text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if not verify_host(p_code, p_password) then return false; end if;
  delete from progress where event_code = p_code;
  delete from scores   where event_code = p_code;
  return true;
end $$;

-- Teams tick objectives without accounts. Merges one change at a time so teammates never overwrite each other.
create or replace function public.set_progress(p_code text, p_team text, p_done jsonb, p_finished boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from events where code = p_code) then raise exception 'No such event'; end if;
  if length(p_team) > 40 or pg_column_size(coalesce(p_done, '{}'::jsonb)) > 4000 then raise exception 'Invalid progress'; end if;
  insert into progress(event_code, team_id, done, finished)
  values (p_code, p_team, coalesce(p_done, '{}'::jsonb), coalesce(p_finished, false))
  on conflict (event_code, team_id) do update
    set done = progress.done || coalesce(p_done, '{}'::jsonb),
        finished = coalesce(p_finished, progress.finished),
        updated_at = now();
end $$;

revoke all on function public.create_event(jsonb, text)               from public;
revoke all on function public.verify_host(text, text)                 from public;
revoke all on function public.update_event(text, text, jsonb)         from public;
revoke all on function public.reset_event(text, text)                 from public;
revoke all on function public.set_progress(text, text, jsonb, boolean) from public;
grant execute on function public.create_event(jsonb, text)               to anon, authenticated;
grant execute on function public.verify_host(text, text)                 to anon, authenticated;
grant execute on function public.update_event(text, text, jsonb)         to anon, authenticated;
grant execute on function public.reset_event(text, text)                 to anon, authenticated;
grant execute on function public.set_progress(text, text, jsonb, boolean) to anon, authenticated;

-- ---------- realtime ----------
alter table public.progress replica identity full;
alter table public.scores   replica identity full;

do $$
declare t text;
begin
  foreach t in array array['events','progress','scores'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;
