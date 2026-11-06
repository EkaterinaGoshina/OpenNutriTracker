-- Dishes shared within a family: the kitchen's recipes, one row each, with
-- the ingredients inside `payload` (RecipeDBO.toJson without imagePath).
-- See docs/WEB_ARCHITECTURE.md, "Общие блюда".
--
-- Every member reads and edits every dish of their family. Writes go through
-- save_family_dish and delete_family_dish, which take the version the client
-- last saw: an edit made on top of an older version is refused with
-- dish_conflict instead of silently overwriting someone else's change.
--
-- Sync reads the table: `updated_at > <cursor>` returns new, changed and
-- deleted dishes alike. A deleted dish stays as a tombstone (deleted_at set,
-- payload emptied) so a device that was offline learns about it.

create table public.family_dishes (
  family_id uuid not null references public.families (id) on delete cascade,
  -- The recipe's id in the app. The key includes the family, so one personal
  -- dish can be shared into a later family after leaving an earlier one.
  id uuid not null,
  created_by uuid references auth.users (id) on delete set null,
  payload jsonb not null
    check (jsonb_typeof(payload) = 'object' and pg_column_size(payload) <= 262144),
  -- R2 object key, always under the family's own prefix.
  photo_key text check (
    photo_key is null
    or photo_key ~ ('^families/' || family_id::text || '/[0-9a-f-]{36}\.webp$')
  ),
  version int not null default 1 check (version >= 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (family_id, id)
);

create index family_dishes_sync on public.family_dishes (family_id, updated_at);

-- ---------------------------------------------------------------------------
-- RPCs. New error codes: dish_conflict (someone saved or deleted it since the
-- caller's version), dish_deleted (saving a dish that was deleted),
-- invalid_dish (payload or photo key rejected).
-- ---------------------------------------------------------------------------

-- Creates the dish when p_base_version is null, otherwise updates the version
-- the caller has. Returns the new version.
create function public.save_family_dish(
  p_id uuid,
  p_payload jsonb,
  p_photo_key text,
  p_base_version int
)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_family_id uuid;
  v_row public.family_dishes%rowtype;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  v_family_id := public.my_family_id();
  if v_family_id is null then
    raise exception 'not_in_family';
  end if;

  if p_id is null
    or p_payload is null
    or jsonb_typeof(p_payload) <> 'object'
    or pg_column_size(p_payload) > 262144
    or (
      p_photo_key is not null
      and p_photo_key !~ ('^families/' || v_family_id::text || '/[0-9a-f-]{36}\.webp$')
    )
  then
    raise exception 'invalid_dish';
  end if;

  select * into v_row
  from public.family_dishes
  where family_id = v_family_id and id = p_id
  for update;

  if not found then
    -- A known version of a row that no longer exists: the family it was in
    -- is gone, or the row was purged. Either way the caller is out of date.
    if p_base_version is not null then
      raise exception 'dish_conflict';
    end if;
    insert into public.family_dishes (family_id, id, created_by, payload, photo_key)
    values (v_family_id, p_id, v_uid, p_payload, p_photo_key);
    return 1;
  end if;

  if v_row.deleted_at is not null then
    raise exception 'dish_deleted';
  end if;
  if p_base_version is distinct from v_row.version then
    raise exception 'dish_conflict';
  end if;

  update public.family_dishes
  set payload = p_payload,
      photo_key = p_photo_key,
      version = version + 1,
      updated_at = now()
  where family_id = v_family_id and id = p_id;

  return v_row.version + 1;
end;
$$;

-- Leaves a tombstone. p_base_version null deletes whatever version is there;
-- otherwise a dish changed since the caller's version is refused with
-- dish_conflict. Deleting a deleted dish is not an error. Returns the
-- tombstone's version.
create function public.delete_family_dish(p_id uuid, p_base_version int)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_family_id uuid;
  v_row public.family_dishes%rowtype;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  v_family_id := public.my_family_id();
  if v_family_id is null then
    raise exception 'not_in_family';
  end if;

  select * into v_row
  from public.family_dishes
  where family_id = v_family_id and id = p_id
  for update;

  if not found then
    raise exception 'dish_conflict';
  end if;
  if v_row.deleted_at is not null then
    return v_row.version;
  end if;
  if p_base_version is not null and p_base_version <> v_row.version then
    raise exception 'dish_conflict';
  end if;

  -- The photo becomes unreferenced; the weekly cleanup removes it from R2.
  update public.family_dishes
  set payload = '{}'::jsonb,
      photo_key = null,
      version = version + 1,
      updated_at = now(),
      deleted_at = now()
  where family_id = v_family_id and id = p_id;

  return v_row.version + 1;
end;
$$;

-- ---------------------------------------------------------------------------
-- Row level security and grants
-- ---------------------------------------------------------------------------

alter table public.family_dishes enable row level security;

create policy family_dishes_select on public.family_dishes
  for select to authenticated
  using (public.is_family_member(family_id));

revoke all on public.family_dishes from anon, authenticated;
grant select on public.family_dishes to authenticated;

revoke execute on function
  public.save_family_dish(uuid, jsonb, text, int),
  public.delete_family_dish(uuid, int)
from public, anon, authenticated;

grant execute on function
  public.save_family_dish(uuid, jsonb, text, int),
  public.delete_family_dish(uuid, int)
to authenticated;
