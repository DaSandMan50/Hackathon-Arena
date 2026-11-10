-- Hackathon Arena · migration 03: delete inactive events after 7 days (was 30)
-- Paste into Supabase → SQL Editor → New query, then Run. Safe to run more than once.
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
revoke all on function public.cleanup_old_events() from public, anon, authenticated;
