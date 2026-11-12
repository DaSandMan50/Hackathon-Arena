-- Hackathon Arena · migration 08: judge list
-- Paste into Supabase → SQL Editor → New query, then Run. Safe to run more than once.
--
-- Judges are added automatically when they sign in with the judge code. Hosts never
-- type judges in; during the event they can rename a judge, remove one (their
-- scorecards are deleted and they can't score again) or let a removed judge back in.

create table if not exists public.judges (
  event_code text not null references public.events(code) on delete cascade,
  id         text not null,                       -- matches the start of the judge's score ids
  name       text not null,
  joined_at  timestamptz not null default now(),
  removed    boolean not null default false,
  primary key (event_code, id)
);
alter table public.judges enable row level security;
drop policy if exists "anyone reads judges" on public.judges;
create policy "anyone reads judges" on public.judges for select to anon, authenticated using (true);

-- live updates for the leaderboard and host tools
do $$ begin
  alter publication supabase_realtime add table public.judges;
exception when duplicate_object then null; end $$;

-- judges who already scored before this migration
insert into public.judges(event_code, id, name)
select distinct on (event_code, split_part(id, '~', 1)) event_code, split_part(id, '~', 1), judge
from public.scores order by event_code, split_part(id, '~', 1), updated_at
on conflict do nothing;

-- a judge signs in: returns 'ok', or 'removed' if the host removed them
create or replace function public.join_judge(p_code text, p_judge_code text, p_id text, p_name text)
returns text language plpgsql security definer set search_path = public as $$
declare v_removed boolean;
begin
  if not verify_judge(p_code, p_judge_code) then raise exception 'Invalid judge code'; end if;
  if p_id !~ '^[a-z0-9-]{1,60}$' or length(trim(p_name)) not between 1 and 120 then raise exception 'Invalid judge'; end if;
  select removed into v_removed from judges where event_code = p_code and id = p_id;
  if v_removed then return 'removed'; end if;
  insert into judges(event_code, id, name) values (p_code, p_id, trim(p_name)) on conflict (event_code, id) do nothing;
  return 'ok';
end $$;

-- saving a score now also checks the judge hasn't been removed
create or replace function public.submit_score(
  p_code text, p_judge_code text, p_id text, p_judge text, p_team text,
  p_scores jsonb, p_submitted boolean, p_total integer)
returns void language plpgsql security definer set search_path = public as $$
declare v_judge text := split_part(p_id, '~', 1);
begin
  if not verify_judge(p_code, p_judge_code) then raise exception 'Invalid judge code'; end if;
  if not exists (select 1 from events where code = p_code and ended_at is null) then raise exception 'Event has ended or does not exist'; end if;
  if length(p_id) > 120 or length(p_judge) not between 1 and 120 or length(p_team) > 40 or pg_column_size(p_scores) > 8000 then raise exception 'Invalid score'; end if;
  if exists (select 1 from judges where event_code = p_code and id = v_judge and removed) then raise exception 'Judge removed by host'; end if;
  if v_judge ~ '^[a-z0-9-]{1,60}$' then
    insert into judges(event_code, id, name) values (p_code, v_judge, p_judge) on conflict (event_code, id) do nothing;
  end if;
  insert into scores(event_code, id, judge, team_id, scores, submitted, total, updated_at)
  values (p_code, p_id, coalesce((select name from judges where event_code = p_code and id = v_judge), p_judge), p_team, coalesce(p_scores, '{}'::jsonb), coalesce(p_submitted, false), p_total, now())
  on conflict (event_code, id) do update
    set judge = excluded.judge, team_id = excluded.team_id, scores = excluded.scores,
        submitted = excluded.submitted, total = excluded.total, updated_at = now();
end $$;

-- host: remove a judge and delete their scorecards
create or replace function public.remove_judge(p_code text, p_password text, p_id text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if not verify_host(p_code, p_password) then return false; end if;
  update judges set removed = true where event_code = p_code and id = p_id;
  delete from scores where event_code = p_code and split_part(id, '~', 1) = p_id;
  return true;
end $$;

-- host: let a removed judge score again
create or replace function public.restore_judge(p_code text, p_password text, p_id text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if not verify_host(p_code, p_password) then return false; end if;
  update judges set removed = false where event_code = p_code and id = p_id;
  return true;
end $$;

-- host: fix how a judge's name is shown
create or replace function public.rename_judge(p_code text, p_password text, p_id text, p_name text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if not verify_host(p_code, p_password) then return false; end if;
  if length(trim(p_name)) not between 1 and 120 then raise exception 'Invalid name'; end if;
  update judges set name = trim(p_name) where event_code = p_code and id = p_id;
  update scores set judge = trim(p_name) where event_code = p_code and split_part(id, '~', 1) = p_id;
  return true;
end $$;

revoke all on function public.join_judge(text, text, text, text)       from public;
revoke all on function public.remove_judge(text, text, text)           from public;
revoke all on function public.restore_judge(text, text, text)          from public;
revoke all on function public.rename_judge(text, text, text, text)     from public;
revoke all on function public.submit_score(text, text, text, text, text, jsonb, boolean, integer) from public;
grant execute on function public.join_judge(text, text, text, text)    to anon, authenticated;
grant execute on function public.remove_judge(text, text, text)        to anon, authenticated;
grant execute on function public.restore_judge(text, text, text)       to anon, authenticated;
grant execute on function public.rename_judge(text, text, text, text)  to anon, authenticated;
grant execute on function public.submit_score(text, text, text, text, text, jsonb, boolean, integer) to anon, authenticated;
