-- Hackathon Arena · migration 05: let hosts keep an event from auto-deleting
-- Paste into Supabase → SQL Editor → New query, then Run. Safe to run more than once.
-- "Keep event" resets the 7-day countdown (for ended events too).

create or replace function public.keep_event(p_code text, p_password text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if not verify_host(p_code, p_password) then return false; end if;
  update events
     set last_activity_at = now(),
         ended_at = case when ended_at is null then null else now() end
   where code = p_code;
  return true;
end $$;

revoke all on function public.keep_event(text, text) from public;
grant execute on function public.keep_event(text, text) to anon, authenticated;
