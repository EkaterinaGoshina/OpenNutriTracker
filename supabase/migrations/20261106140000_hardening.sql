-- Fixes from the Supabase advisors after the first deploy.

-- "Enable automatic RLS" at project creation installs an event-trigger
-- function in public, executable by anon and authenticated as SECURITY
-- DEFINER and so listed under /rest/v1/rpc. The event trigger fires without
-- the EXECUTE privilege, so nobody needs it. Guarded: a project created
-- without the option has no such function.
do $$
begin
  if exists (
    select 1 from pg_proc
    where proname = 'rls_auto_enable'
      and pronamespace = 'public'::regnamespace
  ) then
    revoke execute on function public.rls_auto_enable()
      from public, anon, authenticated;
  end if;
end;
$$;

-- Deleting an auth user sets these to null or cascades through them; without
-- an index each delete scans the table.
create index families_created_by on public.families (created_by);
create index family_invites_created_by on public.family_invites (created_by);
create index family_invites_used_by on public.family_invites (used_by);
create index family_dishes_created_by on public.family_dishes (created_by);
