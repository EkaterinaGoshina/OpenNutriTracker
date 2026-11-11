-- Portions a cook serves to other family members. See docs/WEB_ARCHITECTURE.md,
-- "Повар раскладывает порции".
--
-- Diaries live on each person's own device, so the server only carries the
-- portion from the cook's phone to the recipient's: a mailbox, not a diary.
-- The cook writes a row per recipient; the recipient's app reads its pending
-- rows, adds them to its own diary and marks them received.
--
-- Nobody is a cook by role: whoever cooked the meal serves it, any member can
-- do it any day. A cook serves only people of their own family, and never
-- themselves (their own portion goes straight into their local diary).
--
-- `id` is chosen by the cook's device and is also the id of the intake the
-- recipient's device creates, so a portion read twice (the "received" mark
-- failed, the app was closed mid-way) is added once.

create table public.family_portions (
  id uuid primary key,
  family_id uuid not null references public.families (id) on delete cascade,
  -- Set null when the cook's account is deleted; the portion still arrives.
  cook_id uuid references auth.users (id) on delete set null,
  recipient_id uuid not null references auth.users (id) on delete cascade,
  -- What the recipient's app needs to build an intake: the meal as stored in
  -- a diary (per-unit nutriments), unit, amount, meal type, time.
  payload jsonb not null
    check (jsonb_typeof(payload) = 'object' and pg_column_size(payload) <= 32768),
  created_at timestamptz not null default now(),
  received_at timestamptz
);

-- The recipient's poll: "what is waiting for me".
create index family_portions_pending
  on public.family_portions (recipient_id, created_at)
  where received_at is null;
create index family_portions_family on public.family_portions (family_id);
create index family_portions_cook on public.family_portions (cook_id);

-- ---------------------------------------------------------------------------
-- RPCs. New error codes: invalid_portion (the batch or one of its items is
-- malformed, too big, or names the cook themselves), not_a_member (a
-- recipient who is not in the cook's family).
-- ---------------------------------------------------------------------------

-- p_items: [{ "id": uuid, "recipient_id": uuid, "payload": object }, ...],
-- one to 20 items. All or nothing. Serving the same id again with the same
-- recipient is not an error and changes nothing, so a retry after a lost
-- response is safe. Returns how many rows were new.
create function public.serve_portions(p_items jsonb)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_family_id uuid;
  v_item jsonb;
  v_id uuid;
  v_recipient uuid;
  v_payload jsonb;
  v_existing public.family_portions%rowtype;
  v_new int := 0;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  v_family_id := public.my_family_id();
  if v_family_id is null then
    raise exception 'not_in_family';
  end if;

  if p_items is null
    or jsonb_typeof(p_items) <> 'array'
    or jsonb_array_length(p_items) not between 1 and 20
  then
    raise exception 'invalid_portion';
  end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    if jsonb_typeof(v_item) <> 'object'
      or jsonb_typeof(v_item -> 'payload') <> 'object'
      or pg_column_size(v_item -> 'payload') > 32768
      or (v_item ->> 'id') is null
      or (v_item ->> 'recipient_id') is null
      or (v_item ->> 'id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or (v_item ->> 'recipient_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then
      raise exception 'invalid_portion';
    end if;

    v_id := (v_item ->> 'id')::uuid;
    v_recipient := (v_item ->> 'recipient_id')::uuid;
    v_payload := v_item -> 'payload';

    if v_recipient = v_uid then
      raise exception 'invalid_portion';
    end if;
    if not exists (
      select 1 from public.family_members
      where family_id = v_family_id and user_id = v_recipient
    ) then
      raise exception 'not_a_member';
    end if;

    select * into v_existing from public.family_portions where id = v_id for update;
    if found then
      -- Somebody else's id, or the same id aimed at someone else: a clash,
      -- never a silent overwrite.
      if v_existing.cook_id is distinct from v_uid
        or v_existing.recipient_id <> v_recipient
      then
        raise exception 'invalid_portion';
      end if;
    else
      insert into public.family_portions (id, family_id, cook_id, recipient_id, payload)
      values (v_id, v_family_id, v_uid, v_recipient, v_payload);
      v_new := v_new + 1;
    end if;
  end loop;

  return v_new;
end;
$$;

-- The recipient marks portions they have added to their diary. Ids that are
-- not theirs or already marked are ignored. Returns how many were marked.
create function public.receive_portions(p_ids uuid[])
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_count int;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  if p_ids is null or cardinality(p_ids) > 100 then
    raise exception 'invalid_portion';
  end if;

  update public.family_portions
  set received_at = now()
  where recipient_id = v_uid
    and received_at is null
    and id = any (p_ids);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Row level security and grants
-- ---------------------------------------------------------------------------

alter table public.family_portions enable row level security;

-- The recipient reads what is meant for them, the cook what they served, and
-- only while both are still in that family.
create policy family_portions_select on public.family_portions
  for select to authenticated
  using (
    public.is_family_member(family_id)
    and (recipient_id = (select auth.uid()) or cook_id = (select auth.uid()))
  );

revoke all on public.family_portions from anon, authenticated;
grant select on public.family_portions to authenticated;

revoke execute on function
  public.serve_portions(jsonb),
  public.receive_portions(uuid[])
from public, anon, authenticated;

grant execute on function
  public.serve_portions(jsonb),
  public.receive_portions(uuid[])
to authenticated;
