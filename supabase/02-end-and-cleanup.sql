-- Hackathon Arena · migration 02: ending events + automatic cleanup
-- Paste into Supabase → SQL Editor → New query, then Run. Safe to run more than once.
--
-- What it does
--   • Hosts can end, reopen or delete an event (password checked in the database).
--   • Ended events are read-only: no new scores or checkmarks.
--   • Every night at 3am UTC, the database deletes:
--       - events that were ended more than 7 days ago
--       - events with no activity (no scores, checkmarks or edits) for 7 days
--     Deleting an event also deletes its scores, progress and host password.

create extension if not exists pg_cron;

alter table public.events add column if not exists ended_at timestamptz;
alter table public.events add column if not exists last_activity_at timestamptz not null default now();
alter table public.events replica identity full;

-- Track activity whenever judges score or teams tick objectives
create or replace function public.touch_event_activity()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update events set last_activity_at = now() where code = new.event_code;
  return new;
end $$;

drop trigger if exists scores_touch_event on public.scores;
create trigger scores_touch_event after insert or update on public.scores for each row execute function public.touch_event_activity();
drop trigger if exists progress_touch_event on public.progress;
create trigger progress_touch_event after insert or update on public.progress for each row execute function public.touch_event_activity();

-- Scores can only be written while the event is running
drop policy if exists "judges add scores"  on public.scores;
drop policy if exists "judges edit scores" on public.scores;
create policy "judges add scores" on public.scores for insert to anon, authenticated
  with check (exists (select 1 from public.events e where e.code = event_code and e.ended_at is null) and pg_column_size(scores) < 8000);
create policy "judges edit scores" on public.scores for update to anon, authenticated
  using (exists (select 1 from public.events e where e.code = event_code and e.ended_at is null))
  with check (exists (select 1 from public.events e where e.code = event_code and e.ended_at is null) and pg_column_size(scores) < 8000);

-- Team progress: refuse changes after the event ends
create or replace function public.set_progress(p_code text, p_team text, p_done jsonb, p_finished boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from events where code = p_code and ended_at is null) then raise exception 'Event has ended or does not exist'; end if;
  if length(p_team) > 40 or pg_column_size(coalesce(p_done, '{}'::jsonb)) > 4000 then raise exception 'Invalid progress'; end if;
  insert into progress(event_code, team_id, done, finished)
  values (p_code, p_team, coalesce(p_done, '{}'::jsonb), coalesce(p_finished, false))
  on conflict (event_code, team_id) do update
    set done = progress.done || coalesce(p_done, '{}'::jsonb),
        finished = coalesce(p_finished, progress.finished),
        updated_at = now();
end $$;

create or replace function public.update_event(p_code text, p_password text, p_data jsonb)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if not verify_host(p_code, p_password) then return false; end if;
  if pg_column_size(p_data) > 200000 then raise exception 'Event is too large'; end if;
  update events set data = p_data, updated_at = now(), last_activity_at = now() where code = p_code;
  return true;
end $$;

create or replace function public.end_event(p_code text, p_password text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if not verify_host(p_code, p_password) then return false; end if;
  update events set ended_at = coalesce(ended_at, now()), last_activity_at = now() where code = p_code;
  return true;
end $$;

create or replace function public.reopen_event(p_code text, p_password text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if not verify_host(p_code, p_password) then return false; end if;
  update events set ended_at = null, last_activity_at = now() where code = p_code;
  return true;
end $$;

create or replace function public.delete_event(p_code text, p_password text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if not verify_host(p_code, p_password) then return false; end if;
  delete from events where code = p_code;   -- cascades to scores, progress and the host password
  return true;
end $$;

create or replace function public.cleanup_old_events()
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  delete from events
  where (ended_at is not null and ended_at < now() - interval '7 days')
     or (last_activity_at < now() - interval '7 days');
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.end_event(text, text)       from public;
revoke all on function public.reopen_event(text, text)    from public;
revoke all on function public.delete_event(text, text)    from public;
revoke all on function public.cleanup_old_events()        from public, anon, authenticated;
revoke all on function public.touch_event_activity()      from public, anon, authenticated;
grant execute on function public.end_event(text, text)    to anon, authenticated;
grant execute on function public.reopen_event(text, text) to anon, authenticated;
grant execute on function public.delete_event(text, text) to anon, authenticated;

-- Nightly cleanup at 03:00 UTC (re-running this replaces the existing job)
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'hackathon-arena-cleanup';
  perform cron.schedule('hackathon-arena-cleanup', '0 3 * * *', 'select public.cleanup_old_events()');
end $$;
