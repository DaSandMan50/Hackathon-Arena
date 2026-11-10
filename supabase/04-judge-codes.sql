-- Hackathon Arena · migration 04: private judge codes
-- Paste into Supabase → SQL Editor → New query, then Run. Safe to run more than once.
--
-- Every event gets a private 6-character judge code. Only the host can see it.
-- Scores can only be saved through submit_score(), which checks the judge code,
-- so nobody can score just by picking "I'm a judge".

alter table public.event_secrets add column if not exists judge_code text;

create or replace function public.new_judge_code()
returns text language plpgsql as $$
declare alphabet text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; v text := '';
begin
  for i in 1..6 loop v := v || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1); end loop;
  return v;
end $$;

-- existing events get a judge code too
update public.event_secrets set judge_code = public.new_judge_code() where judge_code is null;

-- create an event and get back both codes
create or replace function public.create_event2(p_data jsonb, p_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  alphabet text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text; v_judge text;
begin
  if p_password is null or length(p_password) < 4 then raise exception 'Host password must be at least 4 characters'; end if;
  if pg_column_size(p_data) > 200000 then raise exception 'Event is too large'; end if;
  loop
    v_code := '';
    for i in 1..5 loop v_code := v_code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1); end loop;
    exit when not exists (select 1 from events where code = v_code);
  end loop;
  v_judge := new_judge_code();
  insert into events(code, data) values (v_code, p_data);
  insert into event_secrets(code, host_hash, judge_code) values (v_code, crypt(p_password, gen_salt('bf')), v_judge);
  return jsonb_build_object('code', v_code, 'judge_code', v_judge);
end $$;

-- host sees the judge code (host password required)
create or replace function public.get_judge_code(p_code text, p_password text)
returns text language plpgsql security definer set search_path = public, extensions as $$
begin
  if not verify_host(p_code, p_password) then return null; end if;
  return (select judge_code from event_secrets where code = p_code);
end $$;

-- host can issue a new judge code (old one stops working)
create or replace function public.reset_judge_code(p_code text, p_password text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare v text;
begin
  if not verify_host(p_code, p_password) then return null; end if;
  v := new_judge_code();
  update event_secrets set judge_code = v where code = p_code;
  return v;
end $$;

create or replace function public.verify_judge(p_code text, p_judge_code text)
returns boolean language sql security definer set search_path = public as $$
  select exists (select 1 from event_secrets where code = p_code and judge_code = upper(trim(p_judge_code)));
$$;

-- the only way to save a score
create or replace function public.submit_score(
  p_code text, p_judge_code text, p_id text, p_judge text, p_team text,
  p_scores jsonb, p_submitted boolean, p_total integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not verify_judge(p_code, p_judge_code) then raise exception 'Invalid judge code'; end if;
  if not exists (select 1 from events where code = p_code and ended_at is null) then raise exception 'Event has ended or does not exist'; end if;
  if length(p_id) > 120 or length(p_judge) not between 1 and 120 or length(p_team) > 40 or pg_column_size(p_scores) > 8000 then raise exception 'Invalid score'; end if;
  insert into scores(event_code, id, judge, team_id, scores, submitted, total, updated_at)
  values (p_code, p_id, p_judge, p_team, coalesce(p_scores, '{}'::jsonb), coalesce(p_submitted, false), p_total, now())
  on conflict (event_code, id) do update
    set judge = excluded.judge, team_id = excluded.team_id, scores = excluded.scores,
        submitted = excluded.submitted, total = excluded.total, updated_at = now();
end $$;

-- no more direct score writes from the website
drop policy if exists "judges add scores"  on public.scores;
drop policy if exists "judges edit scores" on public.scores;

revoke all on function public.new_judge_code()                                       from public, anon, authenticated;
revoke all on function public.create_event2(jsonb, text)                             from public;
revoke all on function public.get_judge_code(text, text)                             from public;
revoke all on function public.reset_judge_code(text, text)                           from public;
revoke all on function public.verify_judge(text, text)                               from public;
revoke all on function public.submit_score(text, text, text, text, text, jsonb, boolean, integer) from public;
grant execute on function public.create_event2(jsonb, text)                          to anon, authenticated;
grant execute on function public.get_judge_code(text, text)                          to anon, authenticated;
grant execute on function public.reset_judge_code(text, text)                        to anon, authenticated;
grant execute on function public.verify_judge(text, text)                            to anon, authenticated;
grant execute on function public.submit_score(text, text, text, text, text, jsonb, boolean, integer) to anon, authenticated;
