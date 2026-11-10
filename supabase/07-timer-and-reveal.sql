-- Hackathon Arena · migration 07: countdown timer + hidden scores with host reveal
-- Paste into Supabase → SQL Editor → New query, then Run. Safe to run more than once.
--
--   • Each event has a countdown timer the host controls.
--   • Scores stay hidden until the host reveals them. Before that, everyone only sees
--     how many judges have scored each team. Judges can still read their own cards,
--     and the host can preview totals.

alter table public.events add column if not exists timer jsonb;
alter table public.events add column if not exists revealed_at timestamptz;
do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'events' and column_name = 'revealed') then
    alter table public.events add column revealed boolean not null default false;
    -- events that already had scores before this migration keep showing them
    update public.events e set revealed = true, revealed_at = now() where exists (select 1 from public.scores s where s.event_code = e.code);
  end if;
end $$;

-- server clock, so every screen's countdown agrees
create or replace function public.server_now()
returns timestamptz language sql stable as $$ select now() $$;

create or replace function public.set_timer(p_code text, p_password text, p_timer jsonb)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if not verify_host(p_code, p_password) then return false; end if;
  if pg_column_size(p_timer) > 2000 then raise exception 'Invalid timer'; end if;
  update events set timer = p_timer, last_activity_at = now() where code = p_code;
  return true;
end $$;

create or replace function public.set_reveal(p_code text, p_password text, p_revealed boolean)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if not verify_host(p_code, p_password) then return false; end if;
  update events set revealed = p_revealed, revealed_at = case when p_revealed then now() else null end, last_activity_at = now() where code = p_code;
  return true;
end $$;

-- scores are only readable once revealed
drop policy if exists "anyone reads scores" on public.scores;
create policy "anyone reads scores" on public.scores for select to anon, authenticated
  using (exists (select 1 from public.events e where e.code = event_code and e.revealed));

-- before the reveal: how many judges have submitted for each team
create or replace function public.score_counts(p_code text)
returns table(team_id text, judges integer) language sql security definer set search_path = public as $$
  select s.team_id, count(*)::int from scores s where s.event_code = p_code and s.submitted group by s.team_id;
$$;

-- a judge reads back only their own scorecards
create or replace function public.judge_cards(p_code text, p_judge_code text, p_prefix text)
returns table(id text, judge text, team_id text, scores jsonb, submitted boolean, total integer)
language plpgsql security definer set search_path = public as $$
begin
  if not verify_judge(p_code, p_judge_code) then return; end if;
  return query select s.id, s.judge, s.team_id, s.scores, s.submitted, s.total from scores s
    where s.event_code = p_code and left(s.id, length(p_prefix) + 1) = p_prefix || '~';
end $$;

-- the host previews everything before revealing
create or replace function public.host_scores(p_code text, p_password text)
returns table(id text, judge text, team_id text, scores jsonb, submitted boolean, total integer)
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not verify_host(p_code, p_password) then return; end if;
  return query select s.id, s.judge, s.team_id, s.scores, s.submitted, s.total from scores s where s.event_code = p_code;
end $$;

revoke all on function public.server_now()                          from public;
revoke all on function public.set_timer(text, text, jsonb)          from public;
revoke all on function public.set_reveal(text, text, boolean)       from public;
revoke all on function public.score_counts(text)                    from public;
revoke all on function public.judge_cards(text, text, text)         from public;
revoke all on function public.host_scores(text, text)               from public;
grant execute on function public.server_now()                       to anon, authenticated;
grant execute on function public.set_timer(text, text, jsonb)       to anon, authenticated;
grant execute on function public.set_reveal(text, text, boolean)    to anon, authenticated;
grant execute on function public.score_counts(text)                 to anon, authenticated;
grant execute on function public.judge_cards(text, text, text)      to anon, authenticated;
grant execute on function public.host_scores(text, text)            to anon, authenticated;
