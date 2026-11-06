-- Families: users join one family through a one-time invite code and share
-- data scoped by family_id. See docs/WEB_ARCHITECTURE.md.
--
-- Every change to who is in a family goes through the RPCs below. Clients
-- can read the tables (RLS limits them to their own family) but cannot
-- write them directly, except a profile's display_name and a family's name.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default ''
    check (char_length(display_name) <= 60),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.families (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 60),
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.family_members (
  family_id uuid not null references public.families (id) on delete cascade,
  -- One family per person.
  user_id uuid not null unique references auth.users (id) on delete cascade,
  role text not null check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (family_id, user_id)
);

-- At most one owner per family.
create unique index family_members_one_owner
  on public.family_members (family_id)
  where role = 'owner';

create table public.family_invites (
  code text primary key check (code ~ '^[A-Z2-9]{8}$'),
  family_id uuid not null references public.families (id) on delete cascade,
  created_by uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_by uuid references auth.users (id) on delete set null,
  used_at timestamptz
);

create index family_invites_family_id on public.family_invites (family_id);

-- ---------------------------------------------------------------------------
-- Profiles: one row per auth user, created on sign-up
-- ---------------------------------------------------------------------------

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (
    new.id,
    left(coalesce(
      nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
      nullif(btrim(new.raw_user_meta_data ->> 'name'), ''),
      split_part(coalesce(new.email, ''), '@', 1)
    ), 60)
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Membership helpers (security definer: they read family_members past RLS,
-- which is what keeps the policies below from recursing)
-- ---------------------------------------------------------------------------

create function public.is_family_member(p_family_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.family_members
    where family_id = p_family_id and user_id = auth.uid()
  );
$$;

create function public.is_family_owner(p_family_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.family_members
    where family_id = p_family_id and user_id = auth.uid() and role = 'owner'
  );
$$;

create function public.shares_family_with(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.family_members mine
    join public.family_members theirs on theirs.family_id = mine.family_id
    where mine.user_id = auth.uid() and theirs.user_id = p_user_id
  );
$$;

-- The caller's family, or null.
create function public.my_family_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select family_id from public.family_members where user_id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- Keep every family with exactly one owner, or delete it once empty. The
-- RPCs already keep this true; the trigger covers a deleted auth user.
-- ---------------------------------------------------------------------------

create function public.after_family_member_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.family_members where family_id = old.family_id
  ) then
    delete from public.families where id = old.family_id;
  elsif not exists (
    select 1 from public.family_members
    where family_id = old.family_id and role = 'owner'
  ) then
    update public.family_members
    set role = 'owner'
    where (family_id, user_id) = (
      select family_id, user_id from public.family_members
      where family_id = old.family_id
      order by joined_at, user_id
      limit 1
    );
  end if;
  return null;
end;
$$;

create trigger family_members_after_delete
  after delete on public.family_members
  for each row execute function public.after_family_member_delete();

-- ---------------------------------------------------------------------------
-- RPCs. Errors are raised with a stable message the app maps to text:
-- not_authenticated, already_in_family, not_in_family, not_owner,
-- invite_not_found, invite_expired, invite_used, owner_must_transfer,
-- not_a_member, too_many_invites, invalid_name.
-- ---------------------------------------------------------------------------

create function public.create_family(p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_family_id uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if char_length(btrim(coalesce(p_name, ''))) not between 1 and 60 then
    raise exception 'invalid_name';
  end if;
  if exists (select 1 from public.family_members where user_id = v_uid) then
    raise exception 'already_in_family';
  end if;

  insert into public.families (name, created_by)
  values (btrim(p_name), v_uid)
  returning id into v_family_id;

  insert into public.family_members (family_id, user_id, role)
  values (v_family_id, v_uid, 'owner');

  return v_family_id;
end;
$$;

-- A one-time code for the caller's family, valid for 48 hours. Only the
-- owner invites. The alphabet has 32 symbols (no I, O, 0, 1), so 8 of them
-- carry 40 random bits.
create function public.create_invite()
returns table (code text, expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  -- Bytes of a v4 UUID that carry no version or variant bits.
  c_random_bytes constant int[] := array[0, 1, 2, 3, 4, 5, 7, 9];
  v_uid uuid := auth.uid();
  v_family_id uuid;
  v_bytes bytea;
  v_code text;
  v_expires_at timestamptz := now() + interval '48 hours';
  i int;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select fm.family_id into v_family_id
  from public.family_members fm
  where fm.user_id = v_uid and fm.role = 'owner';
  if v_family_id is null then
    if exists (select 1 from public.family_members fm where fm.user_id = v_uid) then
      raise exception 'not_owner';
    end if;
    raise exception 'not_in_family';
  end if;

  if (
    select count(*) from public.family_invites fi
    where fi.family_id = v_family_id
      and fi.used_by is null
      and fi.expires_at > now()
  ) >= 10 then
    raise exception 'too_many_invites';
  end if;

  loop
    v_bytes := uuid_send(gen_random_uuid());
    v_code := '';
    foreach i in array c_random_bytes loop
      v_code := v_code || substr(c_alphabet, get_byte(v_bytes, i) % 32 + 1, 1);
    end loop;
    begin
      insert into public.family_invites (code, family_id, created_by, expires_at)
      values (v_code, v_family_id, v_uid, v_expires_at);
      exit;
    exception when unique_violation then
      -- 2^40 codes: a collision is rare, just draw again.
    end;
  end loop;

  return query select v_code, v_expires_at;
end;
$$;

-- Joins the family behind p_code. Spaces, dashes and case are ignored, so a
-- code read aloud or pasted as "k7qm-2xpa" still works.
create function public.join_family(p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[\s-]', '', 'g'));
  v_invite public.family_invites%rowtype;
  v_current uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_invite
  from public.family_invites
  where code = v_code
  for update;

  if not found then
    raise exception 'invite_not_found';
  end if;

  select family_id into v_current
  from public.family_members
  where user_id = v_uid;

  -- Opening the same link twice is not an error.
  if v_current = v_invite.family_id then
    return v_current;
  end if;

  if v_invite.used_by is not null then
    raise exception 'invite_used';
  end if;
  if v_invite.expires_at <= now() then
    raise exception 'invite_expired';
  end if;
  if v_current is not null then
    raise exception 'already_in_family';
  end if;

  insert into public.family_members (family_id, user_id, role)
  values (v_invite.family_id, v_uid, 'member');

  update public.family_invites
  set used_by = v_uid, used_at = now()
  where code = v_code;

  return v_invite.family_id;
end;
$$;

-- The owner leaves only as the last member, which deletes the family;
-- otherwise they hand the role over first (transfer_ownership).
create function public.leave_family()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_member public.family_members%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_member
  from public.family_members
  where user_id = v_uid;
  if not found then
    raise exception 'not_in_family';
  end if;

  if v_member.role = 'owner' and exists (
    select 1 from public.family_members
    where family_id = v_member.family_id and user_id <> v_uid
  ) then
    raise exception 'owner_must_transfer';
  end if;

  delete from public.family_members where user_id = v_uid;
end;
$$;

create function public.remove_member(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_family_id uuid := public.my_family_id();
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  if v_family_id is null then
    raise exception 'not_in_family';
  end if;
  if not public.is_family_owner(v_family_id) then
    raise exception 'not_owner';
  end if;
  -- The owner leaves through leave_family, not by removing themself.
  if p_user_id = auth.uid() then
    raise exception 'owner_must_transfer';
  end if;

  delete from public.family_members
  where family_id = v_family_id and user_id = p_user_id;
  if not found then
    raise exception 'not_a_member';
  end if;
end;
$$;

create function public.transfer_ownership(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_family_id uuid := public.my_family_id();
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  if v_family_id is null then
    raise exception 'not_in_family';
  end if;
  if not public.is_family_owner(v_family_id) then
    raise exception 'not_owner';
  end if;
  if p_user_id = auth.uid() then
    return;
  end if;
  if not exists (
    select 1 from public.family_members
    where family_id = v_family_id and user_id = p_user_id
  ) then
    raise exception 'not_a_member';
  end if;

  -- Demote first: the one-owner index is checked per statement.
  update public.family_members set role = 'member'
  where family_id = v_family_id and user_id = auth.uid();
  update public.family_members set role = 'owner'
  where family_id = v_family_id and user_id = p_user_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.families enable row level security;
alter table public.family_members enable row level security;
alter table public.family_invites enable row level security;

create policy profiles_select on public.profiles
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or public.shares_family_with(user_id)
  );

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy families_select on public.families
  for select to authenticated
  using (public.is_family_member(id));

create policy families_update_owner on public.families
  for update to authenticated
  using (public.is_family_owner(id))
  with check (public.is_family_owner(id));

create policy family_members_select on public.family_members
  for select to authenticated
  using (public.is_family_member(family_id));

-- Only the owner sees the invites, to show and revoke pending ones.
create policy family_invites_select on public.family_invites
  for select to authenticated
  using (public.is_family_owner(family_id));

create policy family_invites_delete_owner on public.family_invites
  for delete to authenticated
  using (public.is_family_owner(family_id) and used_by is null);

-- ---------------------------------------------------------------------------
-- Grants. Supabase grants everything on new tables and functions to anon
-- and authenticated by default; take that back and hand out only what the
-- policies above are written for.
-- ---------------------------------------------------------------------------

revoke all on public.profiles, public.families, public.family_members,
  public.family_invites from anon, authenticated;

grant select on public.profiles, public.families, public.family_members,
  public.family_invites to authenticated;
grant update (display_name) on public.profiles to authenticated;
grant update (name) on public.families to authenticated;
grant delete on public.family_invites to authenticated;

revoke execute on function
  public.handle_new_user(),
  public.touch_updated_at(),
  public.after_family_member_delete(),
  public.is_family_member(uuid),
  public.is_family_owner(uuid),
  public.shares_family_with(uuid),
  public.my_family_id(),
  public.create_family(text),
  public.create_invite(),
  public.join_family(text),
  public.leave_family(),
  public.remove_member(uuid),
  public.transfer_ownership(uuid)
from public, anon, authenticated;

-- The policies call the helpers as the querying user, so authenticated needs
-- them too. is_family_member is also what the photo Worker calls with the
-- user's JWT.
grant execute on function
  public.is_family_member(uuid),
  public.is_family_owner(uuid),
  public.shares_family_with(uuid),
  public.my_family_id(),
  public.create_family(text),
  public.create_invite(),
  public.join_family(text),
  public.leave_family(),
  public.remove_member(uuid),
  public.transfer_ownership(uuid)
to authenticated;
